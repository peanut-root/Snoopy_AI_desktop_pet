import Foundation
import CoreFoundation

/// Weather is fetched for the explicitly chosen city only; it never uses location or chat data.
enum WeatherKind: String, CaseIterable {
    case rain, sunny, cloudy, snow
    var title: String {
        switch self { case .rain: return "下雨"; case .sunny: return "晴天"; case .cloudy: return "多云"; case .snow: return "下雪" }
    }
    static func fromWMO(_ code: Int) -> WeatherKind? {
        switch code {
        case 0, 1: return .sunny
        case 2, 3, 45, 48: return .cloudy
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82, 95, 96, 99: return .rain
        case 71, 73, 75, 77, 85, 86: return .snow
        default: return nil
        }
    }
}

struct WeatherObservation: Equatable {
    let kind: WeatherKind
    let code: Int
    let observedAt: Date
    let fetchedAt: Date
    func isFresh(at now: Date = Date()) -> Bool {
        let observationAge = now.timeIntervalSince(observedAt)
        let fetchAge = now.timeIntervalSince(fetchedAt)
        return observationAge >= 0 && observationAge <= 1800 && fetchAge >= 0 && fetchAge <= 1800
    }
    static func parse(_ data: Data, at now: Date, location: WeatherLocation) throws -> WeatherObservation {
        struct Payload: Decodable {
            struct Current: Decodable { let time: Double; let weather_code: Int }
            struct Units: Decodable { let time: String; let weather_code: String }
            let latitude: Double
            let longitude: Double
            let current: Current
            let current_units: Units
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard location.containsForecastGrid(latitude: payload.latitude, longitude: payload.longitude),
              payload.current.time.isFinite, payload.current_units.time == "unixtime",
              payload.current_units.weather_code == "wmo code",
              let kind = WeatherKind.fromWMO(payload.current.weather_code) else {
            throw WeatherError.invalidObservation
        }
        let result = WeatherObservation(kind: kind, code: payload.current.weather_code,
            observedAt: Date(timeIntervalSince1970: payload.current.time), fetchedAt: now)
        guard result.isFresh(at: now) else { throw WeatherError.staleObservation }
        return result
    }
}

enum WeatherError: LocalizedError {
    case invalidObservation, staleObservation, requestFailed, invalidLocation, locationNotFound
    var errorDescription: String? {
        switch self {
        case .invalidObservation: return "天气数据格式或天气类型无效"
        case .staleObservation: return "天气数据已过期，暂不播放天气剧场"
        case .requestFailed: return "暂时无法获取天气数据，请稍后重试"
        case .invalidLocation: return "请输入至少两个字的城市或地区名称"
        case .locationNotFound: return "没有找到匹配的地区，请试试城市加省份或国家"
        }
    }
}

struct WeatherSettings: Equatable {
    var enabled = true
    var interval: TimeInterval = 600
    var location: WeatherLocation? = nil
    static let defaults = WeatherSettings()
    static var appSupportFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Snoopy Desktop", isDirectory: true).appendingPathComponent("weather.json")
    }
    static var adjacentFileURL: URL {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()
        let root = Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main.bundleURL.deletingLastPathComponent() : executable
        return root.appendingPathComponent("weather.json")
    }
    static var resolvedFileURL: URL? {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()
        var files = [appSupportFileURL, adjacentFileURL]
        if let index = CommandLine.arguments.firstIndex(of: "--project"), index + 1 < CommandLine.arguments.count {
            files.append(URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true).appendingPathComponent("weather.json"))
        }
        files += [executable.appendingPathComponent("project/weather.json"),
                  executable.deletingLastPathComponent().appendingPathComponent("weather.json"),
                  URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("weather.json")]
        return files.first { FileManager.default.fileExists(atPath: $0.path) }
    }
    static var saveFileURL: URL {
        let manager = FileManager.default
        if let file = resolvedFileURL, manager.isWritableFile(atPath: file.path) { return file }
        let adjacent = adjacentFileURL
        if manager.isWritableFile(atPath: adjacent.deletingLastPathComponent().path) { return adjacent }
        return appSupportFileURL
    }
    static func load(from explicit: URL? = nil) throws -> WeatherSettings {
        guard let file = explicit ?? resolvedFileURL else { return defaults }
        func invalid(_ message: String) -> NSError {
            NSError(domain: "WeatherSettings", code: 1, userInfo: [NSLocalizedDescriptionKey: "天气配置无效：" + message])
        }
        let json: Any
        do { json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) }
        catch { throw invalid("无法读取 weather.json") }
        guard let object = json as? [String: Any], Set(object.keys).isSubset(of:
            ["enabled", "intervalSeconds", "city", "admin1", "country", "latitude", "longitude", "timezone"]) else {
            throw invalid("包含不支持的字段")
        }
        var result = defaults
        if let value = object["enabled"] {
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw invalid("enabled 必须为 true 或 false") }
            result.enabled = number.boolValue
        }
        if let value = object["intervalSeconds"] {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
                  (600...86400).contains(number.doubleValue) else { throw invalid("intervalSeconds 必须在 600...86400 秒之间") }
            result.interval = number.doubleValue
        }
        let locationFields = ["city", "admin1", "country", "latitude", "longitude", "timezone"]
        if let city = object["city"] {
            guard let text = city as? String else { throw invalid("city 必须为文字") }
            if locationFields.filter({ object[$0] != nil }) == ["city"], text == "上海" {
                // Read existing installations without making their weather disappear on update.
                result.location = .shanghai
            } else {
                guard let latitude = object["latitude"] as? NSNumber,
                      let longitude = object["longitude"] as? NSNumber,
                      CFGetTypeID(latitude) != CFBooleanGetTypeID(),
                      CFGetTypeID(longitude) != CFBooleanGetTypeID(),
                      let timezone = object["timezone"] as? String else {
                    throw invalid("地区须包含城市、经纬度和时区")
                }
                guard object["admin1"] == nil || object["admin1"] is String,
                      object["country"] == nil || object["country"] is String else {
                    throw invalid("省份和国家必须为文字")
                }
                let location = WeatherLocation(city: text,
                    admin1: object["admin1"] as? String ?? "",
                    country: object["country"] as? String ?? "",
                    latitude: latitude.doubleValue, longitude: longitude.doubleValue,
                    timezone: timezone)
                guard location.isValid else { throw invalid("地区坐标或时区无效") }
                result.location = location
            }
        } else if locationFields.dropFirst().contains(where: { object[$0] != nil }) {
            throw invalid("地区字段缺少 city")
        }
        return result
    }

    var jsonObject: [String: Any] {
        var object: [String: Any] = ["enabled": enabled, "intervalSeconds": interval]
        if let location {
            object["city"] = location.city
            object["admin1"] = location.admin1
            object["country"] = location.country
            object["latitude"] = location.latitude
            object["longitude"] = location.longitude
            object["timezone"] = location.timezone
        }
        return object
    }
}

/// A due check consumes that round, even when Snoopy is busy or hidden. No event backlog is kept.
struct WeatherSchedule {
    var enabled = true
    var interval: TimeInterval = 600
    private(set) var nextDeadline: TimeInterval
    private var lastSeen: TimeInterval
    init(startedAt: TimeInterval, interval: TimeInterval = 600) {
        self.interval = max(600, interval)
        nextDeadline = startedAt + max(600, interval)
        lastSeen = startedAt
    }
    mutating func restart(at now: TimeInterval) { nextDeadline = now + max(600, interval); lastSeen = now }
    mutating func shouldStart(now: TimeInterval, isIdle: Bool, hasActiveSources: Bool, isVisible: Bool, observationFresh: Bool) -> Bool {
        guard now.isFinite else { return false }
        if now < lastSeen { restart(at: now); return false }
        lastSeen = now
        guard now >= nextDeadline else { return false }
        let lateness = now - nextDeadline
        nextDeadline = now + max(600, interval)
        // A suspended app skips a missed round rather than replaying on wake.
        guard lateness < max(600, interval), enabled, isIdle, !hasActiveSources, isVisible, observationFresh else { return false }
        return true
    }
}

/// Monotonic throttling keeps the 32fps render timer from causing network traffic or overlapping requests.
private struct WeatherFetchGate {
    private(set) var nextAttempt: TimeInterval = 0
    private(set) var inFlight = false
    private var failures = 0
    mutating func begin(at now: TimeInterval, force: Bool = false) -> Bool {
        guard now.isFinite, !inFlight, force || now >= nextAttempt else { return false }
        inFlight = true
        return true
    }
    mutating func finish(success: Bool, at now: TimeInterval) {
        inFlight = false
        failures = success ? 0 : min(2, failures + 1)
        nextAttempt = now + (success ? 600 : (failures == 1 ? 30 : 60))
    }
    mutating func reset() { self = WeatherFetchGate() }
}

final class WeatherService {
    private(set) var settings: WeatherSettings
    private(set) var observation: WeatherObservation?
    private(set) var lastError: String?
    private var gate = WeatherFetchGate()
    private var task: URLSessionDataTask?
    private var geocodingTask: URLSessionDataTask?
    private var requestID = UUID()
    private var geocodingID = UUID()
    private var settingsFileURL: URL? = WeatherSettings.resolvedFileURL
    private let uptime: () -> TimeInterval
    private let session: URLSession
    var onChange: (() -> Void)?
    static func forecastURL(for location: WeatherLocation) -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.latitude)),
            URLQueryItem(name: "longitude", value: String(location.longitude)),
            URLQueryItem(name: "current", value: "weather_code"),
            URLQueryItem(name: "timezone", value: location.timezone),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "forecast_days", value: "1")
        ]
        return components.url!
    }
    init(settings: WeatherSettings? = nil, uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.settings = settings ?? ((try? WeatherSettings.load()) ?? .defaults)
        self.uptime = uptime
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }
    deinit { task?.cancel(); geocodingTask?.cancel(); session.invalidateAndCancel() }
    var statusDescription: String {
        guard let location = settings.location else { return "尚未选择天气地区" }
        guard settings.enabled else { return location.city + "天气剧场已关闭" }
        if let observation, observation.isFresh() { return location.city + " · " + observation.kind.title + "（Open-Meteo）" }
        return location.city + "天气：" + (lastError ?? "正在获取")
    }
    func reloadSettings(from explicit: URL? = nil) throws {
        let next = try WeatherSettings.load(from: explicit)
        let previousLocation = settings.location
        settings = next
        settingsFileURL = explicit ?? WeatherSettings.resolvedFileURL
        requestID = UUID(); task?.cancel(); task = nil; gate.reset()
        if previousLocation != next.location { observation = nil; lastError = nil }
        if !next.enabled { lastError = nil }
        onChange?()
    }
    /// Settings live outside the signed app. /Applications falls back to Application Support.
    private func save(_ next: WeatherSettings) throws {
        let manager = FileManager.default
        let file: URL
        if let current = settingsFileURL, manager.isWritableFile(atPath: current.path) {
            file = current
        } else { file = WeatherSettings.saveFileURL }
        try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: next.jsonObject, options: [.prettyPrinted, .sortedKeys])
            .write(to: file, options: .atomic)
        try reloadSettings(from: file)
    }
    func setEnabled(_ enabled: Bool) throws {
        var next = settings
        next.enabled = enabled
        try save(next)
    }
    func setLocation(_ location: WeatherLocation) throws {
        guard location.isValid else { throw WeatherError.invalidLocation }
        var next = settings
        next.location = location
        try save(next)
    }
    func searchLocations(query: String, completion: @escaping (Result<[WeatherLocation], Error>) -> Void) {
        geocodingTask?.cancel()
        geocodingTask = nil
        let identifier = UUID(); geocodingID = identifier
        guard let url = WeatherLocation.searchURL(for: query) else {
            DispatchQueue.main.async { completion(.failure(WeatherError.invalidLocation)) }
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        geocodingTask = session.dataTask(with: request) { [weak self] data, response, error in
            let result: Result<[WeatherLocation], Error>
            if error == nil, let http = response as? HTTPURLResponse, http.statusCode == 200,
               let data, data.count <= 65536 {
                result = Result { try WeatherLocation.parseSearchResults(data) }
            } else { result = .failure(WeatherError.requestFailed) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.geocodingID == identifier else { return }
                self.geocodingTask = nil
                completion(result)
            }
        }
        geocodingTask?.resume()
    }
    func refreshIfNeeded(at now: Date = Date(), force: Bool = false) {
        guard settings.enabled, let location = settings.location,
              gate.begin(at: uptime(), force: force) else { return }
        let identifier = UUID(); requestID = identifier
        var request = URLRequest(url: Self.forecastURL(for: location))
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        task = session.dataTask(with: request) { [weak self] data, response, error in
            let receivedAt = Date()
            let result: Result<WeatherObservation, Error>
            if error == nil, let http = response as? HTTPURLResponse, http.statusCode == 200,
               let data, data.count <= 65536 {
                result = Result { try WeatherObservation.parse(data, at: receivedAt, location: location) }
            } else { result = .failure(WeatherError.requestFailed) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.requestID == identifier else { return }
                self.task = nil
                switch result {
                case .success(let value):
                    self.observation = value; self.lastError = nil
                    self.gate.finish(success: true, at: self.uptime())
                case .failure(let error):
                    self.lastError = error.localizedDescription
                    self.gate.finish(success: false, at: self.uptime())
                }
                self.onChange?()
            }
        }
        task?.resume()
    }
}

func runWeatherServiceTests() throws {
    struct Failure: Error, CustomStringConvertible { let description: String }
    var checks = 0
    func require(_ result: @autoclosure () -> Bool, _ message: String) throws {
        guard result() else { throw Failure(description: message) }; checks += 1
    }
    let mapping: [(WeatherKind, [Int])] = [(.sunny, [0, 1]), (.cloudy, [2, 3, 45, 48]),
        (.rain, [51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82, 95, 96, 99]), (.snow, [71, 73, 75, 77, 85, 86])]
    for (kind, codes) in mapping { for code in codes { try require(WeatherKind.fromWMO(code) == kind, "WMO \(code) maps correctly") } }
    for code in [-1, 4, 52, 70, 98, 100] { try require(WeatherKind.fromWMO(code) == nil, "Unknown WMO is not silently turned sunny") }
    let now = Date(timeIntervalSince1970: 1793160000)
    let shanghai = WeatherLocation.shanghai
    let london = WeatherLocation(city: "London", admin1: "England", country: "United Kingdom",
                                 latitude: 51.5085, longitude: -0.1257, timezone: "Europe/London")
    func fixture(code: String = "63", time: Double = 1793160000,
                 latitude: Double = 31.23, longitude: Double = 121.47,
                 units: String = "unixtime") -> Data {
        Data("{\"latitude\":\(latitude),\"longitude\":\(longitude),\"current_units\":{\"time\":\"\(units)\",\"weather_code\":\"wmo code\"},\"current\":{\"time\":\(time),\"weather_code\":\(code)}}".utf8)
    }
    let valid = try WeatherObservation.parse(fixture(), at: now, location: shanghai)
    try require(valid.kind == .rain && valid.isFresh(at: now.addingTimeInterval(1800)), "Fresh inclusive30minute observation accepted")
    try require(!valid.isFresh(at: now.addingTimeInterval(1800.01)), "Observation expires without becoming a fallback cartoon")
    let londonWeather = try WeatherObservation.parse(fixture(latitude: 51.51, longitude: -0.13), at: now, location: london)
    try require(londonWeather.kind == .rain, "A second chosen city can be observed")
    for data in [fixture(time: 1793158199), fixture(time: 1793160001), fixture(code: "true"), fixture(code: "4"), fixture(latitude: 35), fixture(units: "iso8601"), Data("{}".utf8)] {
        var rejected = false
        do { _ = try WeatherObservation.parse(data, at: now, location: shanghai) } catch { rejected = true }
        try require(rejected, "Stale, future, malformed or wrongcity observation rejected")
    }
    try require(!london.containsForecastGrid(latitude: 31.23, longitude: 121.47) &&
                !london.containsForecastGrid(latitude: 95, longitude: 0),
                "Wrong-city and invalid grid coordinates are rejected")
    let searchURL = WeatherLocation.searchURL(for: "上海, 中国")
    try require(searchURL?.host == "geocoding-api.open-meteo.com" &&
                URLComponents(url: searchURL!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "name" })?.value == "上海, 中国" &&
                WeatherLocation.searchURL(for: "x") == nil,
                "Geocoding search encodes a qualified city and rejects short input")
    let duplicateNames = Data("{\"results\":[{\"name\":\"Springfield\",\"admin1\":\"Illinois\",\"country\":\"United States\",\"latitude\":39.8,\"longitude\":-89.64,\"timezone\":\"America/Chicago\"},{\"name\":\"Springfield\",\"admin1\":\"Massachusetts\",\"country\":\"United States\",\"latitude\":42.1,\"longitude\":-72.59,\"timezone\":\"America/New_York\"}]}".utf8)
    let matches = try WeatherLocation.parseSearchResults(duplicateNames)
    try require(matches.count == 2 && matches[0].displayName != matches[1].displayName,
                "Ambiguous city names stay separate for user selection")
    var schedule = WeatherSchedule(startedAt: 100)
    func due(_ time: Double, idle: Bool = true, busy: Bool = false, visible: Bool = true, fresh: Bool = true) -> Bool {
        schedule.shouldStart(now: time, isIdle: idle, hasActiveSources: busy, isVisible: visible, observationFresh: fresh)
    }
    try require(!due(699.99) && due(700), "First scene waits tenminutes")
    try require(!due(701), "Thirtytwofps cannot duplicate a due scene")
    try require(!due(1300, idle: false) && !due(1301), "Busy due round is skipped without idlecatchup")
    try require(!due(1900, busy: true), "Active sources block weather even if phase looks idle")
    try require(!due(2500, visible: false), "Hidden desktop gets no weather scene")
    try require(!due(3100, fresh: false), "Stale or missing weather gets no scene")
    try require(due(3700), "Next independent idle round plays")
    try require(!due(9999) && !due(10000), "Long suspension consumes all missed rounds without replay")
    try require(due(10599), "One fresh round may play tenminutes after resuming")
    try require(!due(0) && !due(1), "Monotonic reset restarts the full wait")
    schedule.enabled = false
    try require(!due(600), "Disabled scene never starts")
    var gate = WeatherFetchGate()
    try require(gate.begin(at: 0) && !gate.begin(at: 1), "One network request at a time")
    gate.finish(success: false, at: 2)
    try require(!gate.begin(at: 31) && gate.begin(at: 32), "First network failure waits30s")
    gate.finish(success: false, at: 33)
    try require(!gate.begin(at: 92) && gate.begin(at: 93), "Repeated failures backoff60s")
    gate.finish(success: true, at: 94)
    try require(!gate.begin(at: 693) && gate.begin(at: 694), "Success waits600s despite render timer")
    gate.finish(success: false, at: 695)
    try require(gate.nextAttempt == 725, "Success resets failurebackoff")
    try require(gate.begin(at: 696, force: true) && !gate.begin(at: 697, force: true), "Manual refresh bypasses throttle but never overlaps")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("snoopy-weather-tests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("weather.json")
    try Data("{\"enabled\":false,\"intervalSeconds\":900,\"city\":\"上海\"}".utf8).write(to: file)
    let customSettings = try WeatherSettings.load(from: file)
    try require(customSettings == WeatherSettings(enabled: false, interval: 900, location: .shanghai),
                "Legacy Shanghai configuration loads on update")
    let service = WeatherService(settings: customSettings)
    try service.reloadSettings(from: file)
    try service.setEnabled(true)
    let savedSettings = try WeatherSettings.load(from: file)
    try require(savedSettings.enabled && savedSettings.interval == 900 &&
                savedSettings.location == .shanghai && service.settings == savedSettings,
                "Menu toggle keeps city while saving outside app")
    try service.setLocation(london)
    let moved = try WeatherSettings.load(from: file)
    try require(moved.location == london && moved.interval == 900 && moved.enabled,
                "Changing city atomically saves country, coordinates and timezone")
    let requestURL = WeatherService.forecastURL(for: london)
    let items = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
    try require(requestURL.host == "api.open-meteo.com" &&
                items.first(where: { $0.name == "latitude" })?.value == "51.5085" &&
                items.first(where: { $0.name == "timezone" })?.value == "Europe/London" &&
                !requestURL.absoluteString.contains("token"),
                "Forecast targets selected city and carries no bridge credential")
    try service.setEnabled(false)
    try require(!service.settings.enabled && service.settings.location == london,
                "Disabling persists without erasing selected city")
    for json in ["[]", "{\"enabled\":1}", "{\"intervalSeconds\":true}", "{\"intervalSeconds\":599}",
                 "{\"intervalSeconds\":90000}", "{\"city\":\"杭州\"}",
                 "{\"city\":\"London\",\"latitude\":91,\"longitude\":0,\"timezone\":\"Europe/London\"}",
                 "{\"city\":\"London\",\"latitude\":51,\"longitude\":0,\"timezone\":\"Not/AZone\"}",
                 "{\"city\":\"London\",\"admin1\":7,\"latitude\":51,\"longitude\":0,\"timezone\":\"Europe/London\"}",
                 "{\"url\":\"https://example.com\"}"] {
        try Data(json.utf8).write(to: file)
        var rejected = false
        do { _ = try WeatherSettings.load(from: file) } catch { rejected = true }
        try require(rejected, "Malformedsettings cannot change fetchdestination")
    }
    try require(WeatherSettings.defaults.location == nil &&
                WeatherService(settings: .defaults).statusDescription == "尚未选择天气地区",
                "A fresh download waits for a deliberate city choice")
    print("PASS: \(checks) WMO, weather freshness, idle scheduling, network throttling and configuration assertions")
}

import Foundation
import CoreFoundation

/// Mutable animation data lives outside the signed bundle. A reload waits for an active
/// interaction to finish, so changing speed cannot teleport a bird midway through flight.
struct InteractionMotionSettings: Equatable {
    var takeoffDuration: Double = 1.4
    var returnDuration: Double = 1.8
    var wingFramesPerSecond: Double = 8
    static let defaults = InteractionMotionSettings()
    private(set) static var current = defaults
    private static var pending: InteractionMotionSettings?
    static var resolvedFileURL: URL? {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()
        let name = "interaction-motion.json"
        var roots = [Bundle.main.bundleURL.deletingLastPathComponent(), executable]
        if let i = CommandLine.arguments.firstIndex(of: "--project"), i + 1 < CommandLine.arguments.count {
            roots.append(URL(fileURLWithPath: CommandLine.arguments[i + 1], isDirectory: true))
        }
        roots += [executable.appendingPathComponent("project"), executable.deletingLastPathComponent(),
                  URL(fileURLWithPath: FileManager.default.currentDirectoryPath)]
        return roots.map { $0.appendingPathComponent(name) }.first { FileManager.default.fileExists(atPath: $0.path) }
    }
    static func load(from explicit: URL? = nil) throws -> InteractionMotionSettings {
        guard let file = explicit ?? resolvedFileURL else { return defaults }
        func invalid(_ message: String) -> NSError {
            NSError(domain: "InteractionMotionSettings", code: 1, userInfo: [NSLocalizedDescriptionKey: "互动速度配置无效（\(file.lastPathComponent)）：\(message)"])
        }
        let json: Any
        do { json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) }
        catch { throw invalid("无法读取JSON：" + error.localizedDescription) }
        guard let object = json as? [String: Any], Set(object.keys).isSubset(of: ["takeoffDuration", "returnDuration", "wingFramesPerSecond"]) else {
            throw invalid("只支持 takeoffDuration、returnDuration、wingFramesPerSecond")
        }
        func number(_ key: String, fallback: Double, range: ClosedRange<Double>) throws -> Double {
            guard let raw = object[key] else { return fallback }
            guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
                  value.doubleValue.isFinite, range.contains(value.doubleValue) else {
                throw invalid("\(key) 必须是 \(range.lowerBound)...\(range.upperBound) 内的数值")
            }
            return value.doubleValue
        }
        return try InteractionMotionSettings(
            takeoffDuration: number("takeoffDuration", fallback: defaults.takeoffDuration, range: 0.5...4),
            returnDuration: number("returnDuration", fallback: defaults.returnDuration, range: 0.6...5),
            wingFramesPerSecond: number("wingFramesPerSecond", fallback: defaults.wingFramesPerSecond, range: 4...16))
    }
    static func apply(_ value: InteractionMotionSettings, whileInteracting: Bool) {
        if whileInteracting { pending = value }
        else { current = value; pending = nil }
    }
    static func applyPendingIfSafe(isInteracting: Bool) {
        guard !isInteracting, let next = pending else { return }
        current = next; pending = nil
    }
}

func runInteractionMotionSettingsTests() throws {
    struct Failure: Error { let message: String }
    var checks = 0
    func check(_ result: @autoclosure () -> Bool, _ message: String) throws {
        guard result() else { throw Failure(message: message) }; checks += 1
    }
    let original = InteractionMotionSettings.current
    defer { InteractionMotionSettings.apply(original, whileInteracting: false) }
    InteractionMotionSettings.apply(.defaults, whileInteracting: false)
    try check(TouchMotion.stage(1.0) == .takeoff, "The outward flight really lasts longer than the old0.55s")
    try check(TouchMotion.birdIsFlying(TouchMotion.returningStarts + 1.2), "Return is still flying after the old0.75s endpoint")
    try check(abs(TouchMotion.totalDuration - 6.71) < 0.00001, "Only flight durations lengthen the touch scene")
    try check((0..<5).map { TouchMotion.flightWingFrame(Double($0) / 8) } == [1,2,3,4,1], "Eight wing frames per second gives two gentle cycles")
    try check(TouchMotion.birdAwayProgress(0) == 0 && TouchMotion.birdAwayProgress(TouchMotion.risingStarts) == 1 && TouchMotion.birdAwayProgress(TouchMotion.totalDuration) == 0, "Slower bird still leaves and lands exactly")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("snoopy-flight-tests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("interaction-motion.json")
    try Data("{\"takeoffDuration\":2.2,\"returnDuration\":2.4,\"wingFramesPerSecond\":6}".utf8).write(to: file)
    let next = try InteractionMotionSettings.load(from: file)
    InteractionMotionSettings.apply(next, whileInteracting: true)
    try check(InteractionMotionSettings.current == .defaults, "Reload is queued while bird is airborne")
    InteractionMotionSettings.applyPendingIfSafe(isInteracting: true)
    try check(InteractionMotionSettings.current == .defaults, "An active interaction keeps one consistent timing snapshot")
    let fresh = PetState()
    try check(fresh.startBellyInteraction(at:0) && InteractionMotionSettings.current == next, "A fresh idle touch applies queued settings before starting")
    InteractionMotionSettings.applyPendingIfSafe(isInteracting: false)
    try check(InteractionMotionSettings.current == next && abs(TouchMotion.risingStarts - 2.2) < 0.00001, "Next interaction uses external timing without restarting")
    for json in ["{\"takeoffDuration\":0}", "{\"returnDuration\":99}", "{\"wingFramesPerSecond\":true}", "{\"wingFramesPerSecond\":\"8\"}", "{\"unknown\":1}", "[]", "not-json"] {
        try Data(json.utf8).write(to: file)
        var rejected = false
        do { _ = try InteractionMotionSettings.load(from: file) } catch { rejected = true }
        try check(rejected && InteractionMotionSettings.current == next, "Invalid flight data cannot damage current timing")
    }
    print("PASS: \(checks) slower-flight, external configuration and deferred-reload checks")
}

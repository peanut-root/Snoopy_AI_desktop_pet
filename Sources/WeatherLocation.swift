import Foundation

/// A location chosen by the user, resolved to coordinates by Open-Meteo.
struct WeatherLocation: Equatable {
    let city: String
    let admin1: String
    let country: String
    let latitude: Double
    let longitude: Double
    let timezone: String

    static let shanghai = WeatherLocation(city: "上海", admin1: "上海", country: "中国",
                                           latitude: 31.2304, longitude: 121.4737,
                                           timezone: "Asia/Shanghai")

    var isValid: Bool {
        let name = city.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.count <= 80 && admin1.count <= 80 && country.count <= 80 &&
            latitude.isFinite && (-90...90).contains(latitude) &&
            longitude.isFinite && (-180...180).contains(longitude) &&
            timezone.count <= 80 && TimeZone(identifier: timezone) != nil
    }

    var displayName: String {
        var parts = [city]
        if !admin1.isEmpty && admin1 != city { parts.append(admin1) }
        if !country.isEmpty { parts.append(country) }
        return parts.joined(separator: " · ")
    }

    static func searchURL(for query: String) -> URL? {
        let name = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...80).contains(name.count) else { return nil }
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "count", value: "8"),
            URLQueryItem(name: "language", value: "zh"),
            URLQueryItem(name: "format", value: "json")
        ]
        return components?.url
    }

    static func parseSearchResults(_ data: Data) throws -> [WeatherLocation] {
        struct Payload: Decodable {
            struct Place: Decodable {
                let name: String
                let admin1: String?
                let country: String?
                let latitude: Double
                let longitude: Double
                let timezone: String
            }
            let results: [Place]?
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let places = (payload.results ?? []).map {
            WeatherLocation(city: $0.name, admin1: $0.admin1 ?? "", country: $0.country ?? "",
                            latitude: $0.latitude, longitude: $0.longitude, timezone: $0.timezone)
        }.filter(\.isValid)
        guard !places.isEmpty else { throw WeatherError.locationNotFound }
        return places
    }

    /// Forecast coordinates are the selected model grid cell, not always the exact city centre.
    func containsForecastGrid(latitude gridLatitude: Double, longitude gridLongitude: Double) -> Bool {
        guard gridLatitude.isFinite, gridLongitude.isFinite,
              (-90...90).contains(gridLatitude), (-180...180).contains(gridLongitude) else { return false }
        let r = Double.pi / 180
        let dLat = (gridLatitude - latitude) * r
        let dLon = (gridLongitude - longitude) * r
        let a = pow(sin(dLat / 2), 2) + cos(latitude * r) * cos(gridLatitude * r) * pow(sin(dLon / 2), 2)
        return 6371 * 2 * asin(min(1, sqrt(max(0, a)))) <= 100
    }
}

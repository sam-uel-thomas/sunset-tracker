import Foundation

struct WeatherSnapshot {
    var temperatureF: Double
    var humidity: Double        // %
    var cloudLow: Double        // %
    var cloudMid: Double        // %
    var cloudHigh: Double       // %
    var visibility: Double      // metres

    /// Which deck dominates the sky. Low cloud is what kills a sunset, so it
    /// wins ties on the way down.
    var cloudHeightLabel: String {
        let maxCover = max(cloudLow, max(cloudMid, cloudHigh))
        if maxCover < 12 { return "Clear" }
        if cloudLow == maxCover { return "Low" }
        if cloudMid == maxCover { return "Mid" }
        return "High"
    }

    var cloudHeightFraction: Double {
        switch cloudHeightLabel {
        case "Clear": return 0.06
        case "Low": return 0.28
        case "Mid": return 0.58
        default: return 0.92
        }
    }

    /// Visibility as a fraction of "as far as you'll ever see" (24 km).
    var visibilityFraction: Double {
        min(1, max(0, visibility / 24_000))
    }
}

enum WeatherService {
    struct APIError: LocalizedError {
        var errorDescription: String?
    }

    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double?
            let relative_humidity_2m: Double?
            let cloud_cover_low: Double?
            let cloud_cover_mid: Double?
            let cloud_cover_high: Double?
        }
        struct Hourly: Decodable {
            let time: [String]?
            let visibility: [Double?]?
        }
        let current: Current?
        let hourly: Hourly?
    }

    static func fetch(latitude: Double, longitude: Double) async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(format: "%.4f", latitude)),
            .init(name: "longitude", value: String(format: "%.4f", longitude)),
            .init(name: "current", value: "temperature_2m,relative_humidity_2m,cloud_cover_low,cloud_cover_mid,cloud_cover_high"),
            .init(name: "hourly", value: "visibility"),
            .init(name: "temperature_unit", value: "fahrenheit"),
            .init(name: "forecast_days", value: "1"),
            .init(name: "timezone", value: "auto"),
        ]

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError(errorDescription: "Weather service returned an error")
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let current = decoded.current else {
            throw APIError(errorDescription: "Weather service returned no current conditions")
        }

        // Open-Meteo only publishes visibility hourly; take the current hour.
        var visibility: Double = 20_000
        if let values = decoded.hourly?.visibility {
            let hour = Calendar.current.component(.hour, from: Date())
            if hour < values.count, let v = values[hour] {
                visibility = v
            } else if let v = values.compactMap({ $0 }).first {
                visibility = v
            }
        }

        return WeatherSnapshot(
            temperatureF: current.temperature_2m ?? 0,
            humidity: current.relative_humidity_2m ?? 0,
            cloudLow: current.cloud_cover_low ?? 0,
            cloudMid: current.cloud_cover_mid ?? 0,
            cloudHigh: current.cloud_cover_high ?? 0,
            visibility: visibility
        )
    }
}

/// Turns a weather snapshot into the numbers the panel actually shows.
///
/// The heuristic is the one sunset chasers use: you need mid- and high-level
/// cloud to catch light from below the horizon, a clear low deck so that light
/// can reach it, and dry, clean air in between.
struct SunsetForecast {
    var quality: Double          // 0...1
    var conditions: String

    static func score(_ w: WeatherSnapshot) -> SunsetForecast {
        // High cloud is the best canvas, mid is good, and we want a decent
        // amount of it — around 55% cover is the sweet spot.
        let canvas = 0.62 * w.cloudHigh + 0.38 * w.cloudMid
        let coverage = max(0, 1 - abs(canvas - 55) / 55)

        // Low cloud blocks the light path entirely.
        let lowPenalty = 1 - (w.cloudLow / 100) * 0.85

        // Haze mutes the colour.
        let humidityPenalty = 1 - max(0, (w.humidity - 55) / 100) * 0.5
        let visibilityFactor = 0.35 + 0.65 * w.visibilityFraction

        let q = min(1, max(0, coverage * lowPenalty * humidityPenalty * visibilityFactor))
        return SunsetForecast(quality: q, conditions: conditionLabel(q))
    }

    private static func conditionLabel(_ q: Double) -> String {
        switch q {
        case ..<0.18: return "Washed Out"
        case ..<0.38: return "Subdued"
        case ..<0.58: return "Decent"
        case ..<0.78: return "Vivid"
        default: return "Spectacular"
        }
    }

    /// Sunrise runs cooler and rosier than sunset at the same score.
    func palette(for mode: SkyMode) -> String {
        let sunset = [
            "Shades of ash, pewter, & pale blue",
            "Shades of scarlet, orange, & lavender",
            "Shades of amber, peach, & periwinkle",
            "Shades of ember, coral, & violet",
            "Shades of magenta, gold, & crimson",
        ]
        let sunrise = [
            "Shades of slate, mist, & pale grey",
            "Shades of rose, blush, & cool blue",
            "Shades of apricot, pearl, & lilac",
            "Shades of coral, honey, & periwinkle",
            "Shades of flame, rose gold, & amber",
        ]
        return (mode == .sunset ? sunset : sunrise)[band]
    }

    func dots(for mode: SkyMode) -> [UInt32] {
        let sunset: [[UInt32]] = [
            [0xB9B4AE, 0xC7BFB4, 0xB2B6C8],
            [0xEF6C2B, 0xF4A32A, 0xA79FD8],
            [0xF07A2E, 0xF6B44A, 0x9E9BDC],
            [0xE8502A, 0xF79038, 0x8E7FD4],
            [0xD82F5A, 0xF5A623, 0xB4479B],
        ]
        let sunrise: [[UInt32]] = [
            [0xB6B8BE, 0xC5C3C2, 0xAEB6CA],
            [0xE8899B, 0xF0B7A8, 0x9DAEDC],
            [0xEF9A72, 0xF6CBA8, 0xA9A6DE],
            [0xEE7A5E, 0xF6B45E, 0x93A2DE],
            [0xE85C4A, 0xF7A96B, 0xC77FA8],
        ]
        return (mode == .sunset ? sunset : sunrise)[band]
    }

    /// Which of the five quality bands this forecast falls in.
    private var band: Int {
        switch quality {
        case ..<0.18: return 0
        case ..<0.38: return 1
        case ..<0.58: return 2
        case ..<0.78: return 3
        default: return 4
        }
    }

    static let placeholder = SunsetForecast(quality: 0.3, conditions: "—")
}

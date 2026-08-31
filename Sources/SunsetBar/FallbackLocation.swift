import Foundation
import CoreLocation

/// Where to place the user when Location Services can't tell us.
///
/// A hardcoded city is wrong for almost everyone, and wrong in a way that is
/// easy to miss: the panel would show one city's sunset formatted in another
/// city's timezone. Deriving it from the system timezone is right far more
/// often, and the panel names whichever guess it used.
enum FallbackLocation {
    struct Guess {
        let name: String
        let coordinate: CLLocationCoordinate2D
    }

    /// Representative coordinates for the commonly used IANA zones.
    private static let known: [String: (String, Double, Double)] = [
        "Europe/London": ("London", 51.5074, -0.1278),
        "Europe/Dublin": ("Dublin", 53.3498, -6.2603),
        "Europe/Paris": ("Paris", 48.8566, 2.3522),
        "Europe/Madrid": ("Madrid", 40.4168, -3.7038),
        "Europe/Lisbon": ("Lisbon", 38.7223, -9.1393),
        "Europe/Berlin": ("Berlin", 52.5200, 13.4050),
        "Europe/Amsterdam": ("Amsterdam", 52.3676, 4.9041),
        "Europe/Brussels": ("Brussels", 50.8503, 4.3517),
        "Europe/Zurich": ("Zurich", 47.3769, 8.5417),
        "Europe/Rome": ("Rome", 41.9028, 12.4964),
        "Europe/Vienna": ("Vienna", 48.2082, 16.3738),
        "Europe/Prague": ("Prague", 50.0755, 14.4378),
        "Europe/Warsaw": ("Warsaw", 52.2297, 21.0122),
        "Europe/Stockholm": ("Stockholm", 59.3293, 18.0686),
        "Europe/Oslo": ("Oslo", 59.9139, 10.7522),
        "Europe/Copenhagen": ("Copenhagen", 55.6761, 12.5683),
        "Europe/Helsinki": ("Helsinki", 60.1699, 24.9384),
        "Europe/Athens": ("Athens", 37.9838, 23.7275),
        "Europe/Istanbul": ("Istanbul", 41.0082, 28.9784),
        "Europe/Moscow": ("Moscow", 55.7558, 37.6173),
        "America/New_York": ("New York", 40.7128, -74.0060),
        "America/Toronto": ("Toronto", 43.6532, -79.3832),
        "America/Chicago": ("Chicago", 41.8781, -87.6298),
        "America/Denver": ("Denver", 39.7392, -104.9903),
        "America/Phoenix": ("Phoenix", 33.4484, -112.0740),
        "America/Los_Angeles": ("San Francisco", 37.7749, -122.4194),
        "America/Vancouver": ("Vancouver", 49.2827, -123.1207),
        "America/Anchorage": ("Anchorage", 61.2181, -149.9003),
        "America/Mexico_City": ("Mexico City", 19.4326, -99.1332),
        "America/Bogota": ("Bogotá", 4.7110, -74.0721),
        "America/Lima": ("Lima", -12.0464, -77.0428),
        "America/Sao_Paulo": ("São Paulo", -23.5505, -46.6333),
        "America/Argentina/Buenos_Aires": ("Buenos Aires", -34.6037, -58.3816),
        "America/Santiago": ("Santiago", -33.4489, -70.6693),
        "Asia/Tokyo": ("Tokyo", 35.6762, 139.6503),
        "Asia/Seoul": ("Seoul", 37.5665, 126.9780),
        "Asia/Shanghai": ("Shanghai", 31.2304, 121.4737),
        "Asia/Hong_Kong": ("Hong Kong", 22.3193, 114.1694),
        "Asia/Singapore": ("Singapore", 1.3521, 103.8198),
        "Asia/Bangkok": ("Bangkok", 13.7563, 100.5018),
        "Asia/Jakarta": ("Jakarta", -6.2088, 106.8456),
        "Asia/Kolkata": ("Mumbai", 19.0760, 72.8777),
        "Asia/Dubai": ("Dubai", 25.2048, 55.2708),
        "Asia/Jerusalem": ("Tel Aviv", 32.0853, 34.7818),
        "Africa/Cairo": ("Cairo", 30.0444, 31.2357),
        "Africa/Lagos": ("Lagos", 6.5244, 3.3792),
        "Africa/Nairobi": ("Nairobi", -1.2921, 36.8219),
        "Africa/Johannesburg": ("Johannesburg", -26.2041, 28.0473),
        "Australia/Sydney": ("Sydney", -33.8688, 151.2093),
        "Australia/Melbourne": ("Melbourne", -37.8136, 144.9631),
        "Australia/Brisbane": ("Brisbane", -27.4698, 153.0251),
        "Australia/Perth": ("Perth", -31.9505, 115.8605),
        "Pacific/Auckland": ("Auckland", -36.8485, 174.7633),
        "Atlantic/Reykjavik": ("Reykjavík", 64.1466, -21.9426),
    ]

    static func current() -> Guess {
        let zone = TimeZone.current
        if let (name, lat, lon) = known[zone.identifier] {
            return Guess(name: name, coordinate: .init(latitude: lat, longitude: lon))
        }

        // Unknown zone: the UTC offset still pins longitude to within about 7.5°,
        // which is worth a few minutes of sunset at most. Latitude is genuinely
        // unknowable here, so take the mid-northern default and say so.
        let longitude = Double(zone.secondsFromGMT()) / 3600 * 15
        return Guess(
            name: zone.identifier.split(separator: "/").last.map(String.init)?
                .replacingOccurrences(of: "_", with: " ") ?? "your timezone",
            coordinate: .init(latitude: 45, longitude: max(-180, min(180, longitude)))
        )
    }
}

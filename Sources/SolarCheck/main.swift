import Foundation
import SolarKit

// Emits computed solar times as CSV for a grid of latitudes and dates, so the
// implementation can be diffed against an independent ephemeris.
// Usage: swift run SolarCheck > times.csv

let iso: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.timeZone = TimeZone(identifier: "UTC")
    f.formatOptions = [.withInternetDateTime]
    return f
}()

let sites: [(name: String, lat: Double, lon: Double)] = [
    ("san_francisco", 37.7749, -122.4194),
    ("london", 51.5074, -0.1278),
    ("new_york", 40.7128, -74.0060),
    ("sydney", -33.8688, 151.2093),
    ("quito", -0.1807, -78.4678),
    ("reykjavik", 64.1466, -21.9426),
    ("cape_town", -33.9249, 18.4241),
    ("tokyo", 35.6762, 139.6503),
    ("anchorage", 61.2181, -149.9003),
    ("buenos_aires", -34.6037, -58.3816),
]

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "UTC")!

print("site,lat,lon,date,sunrise,sunset,golden_set")
for site in sites {
    for month in 1...12 {
        for day in [5, 20] {
            var comps = DateComponents()
            comps.year = 2026
            comps.month = month
            comps.day = day
            comps.hour = 12
            guard let date = calendar.date(from: comps) else { continue }
            let e = Solar.events(date: date, latitude: site.lat, longitude: site.lon)
            let fields = [
                site.name,
                String(format: "%.4f", site.lat),
                String(format: "%.4f", site.lon),
                String(format: "2026-%02d-%02d", month, day),
                e.sunrise.map { iso.string(from: $0) } ?? "",
                e.sunset.map { iso.string(from: $0) } ?? "",
                e.goldenHourStart.map { iso.string(from: $0) } ?? "",
            ]
            print(fields.joined(separator: ","))
        }
    }
}

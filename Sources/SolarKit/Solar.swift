import Foundation

/// Solar event times, computed locally — no network, no API key.
///
/// This is the NOAA Solar Calculator formulation (Meeus, *Astronomical
/// Algorithms*): full equation of time, plus nutation and aberration
/// corrections to the sun's apparent longitude. An earlier version of this file
/// used the shorter SunCalc series, which drifted up to ~4 minutes near the
/// equinoxes; see Tests/verify_against_usno.py for the benchmark that caught it.
public enum Solar {
    private static let rad = Double.pi / 180
    private static let j2000: Double = 2_451_545      // 2000-01-01 12:00 TT
    private static let unixEpochJD: Double = 2_440_587.5
    private static let secondsPerDay: Double = 86_400

    /// Standard altitudes, in degrees above the horizon.
    public enum Altitude {
        /// Upper limb touching the horizon, corrected for refraction.
        public static let horizon = -0.833
        /// The start of the warm, low-angle light.
        public static let golden = 6.0
        /// Colour peaks here, after the disc is gone.
        public static let blue = -4.0
    }

    private static func julianDay(_ date: Date) -> Double {
        date.timeIntervalSince1970 / secondsPerDay + unixEpochJD
    }

    private static func dateFrom(julianDay jd: Double) -> Date {
        Date(timeIntervalSince1970: (jd - unixEpochJD) * secondsPerDay)
    }

    /// The sun's declination (radians) and the equation of time (minutes) at a
    /// given instant.
    private static func solarState(julianDay jd: Double) -> (declination: Double, equationOfTime: Double) {
        let t = (jd - j2000) / 36525

        let meanLongitude = (280.46646 + t * (36000.76983 + t * 0.0003032))
            .truncatingRemainder(dividingBy: 360)
        let meanAnomaly = 357.52911 + t * (35999.05029 - 0.0001537 * t)
        let eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)

        let center = sin(rad * meanAnomaly) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(rad * 2 * meanAnomaly) * (0.019993 - 0.000101 * t)
            + sin(rad * 3 * meanAnomaly) * 0.000289

        // Apparent longitude folds in nutation and aberration; leaving these out
        // is worth about a minute of error at the solstices.
        let omega = 125.04 - 1934.136 * t
        let apparentLongitude = meanLongitude + center - 0.00569 - 0.00478 * sin(rad * omega)

        let meanObliquity = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let obliquity = meanObliquity + 0.00256 * cos(rad * omega)

        let declination = asin(sin(rad * obliquity) * sin(rad * apparentLongitude))

        let y = pow(tan(rad * obliquity / 2), 2)
        let equationOfTime = 4 / rad * (
            y * sin(2 * rad * meanLongitude)
            - 2 * eccentricity * sin(rad * meanAnomaly)
            + 4 * eccentricity * y * sin(rad * meanAnomaly) * cos(2 * rad * meanLongitude)
            - 0.5 * y * y * sin(4 * rad * meanLongitude)
            - 1.25 * eccentricity * eccentricity * sin(2 * rad * meanAnomaly)
        )

        return (declination, equationOfTime)
    }

    /// Time the sun crosses `altitude` (degrees) during the solar day containing
    /// `date` — the setting crossing unless `rising` is true.
    ///
    /// Returns nil when the sun never reaches that altitude: polar day, polar
    /// night, or a golden hour that never happens at high latitude.
    ///
    /// Solar position is re-evaluated at the solved instant and the solve
    /// repeated, because declination moves measurably between noon and sunset.
    public static func time(
        altitude degrees: Double,
        rising: Bool = false,
        date: Date,
        latitude: Double,
        longitude: Double
    ) -> Date? {
        let jd = julianDay(date)
        // Index of the solar day at this longitude, so we return *this* day's event.
        let n = (jd - j2000 + longitude / 360).rounded()
        let localNoon = j2000 + n - longitude / 360

        let phi = rad * latitude
        var estimate = localNoon
        var result: Double?

        for _ in 0..<3 {
            let state = solarState(julianDay: estimate)
            let solarNoon = localNoon - state.equationOfTime / 1440

            let cosH = (sin(rad * degrees) - sin(phi) * sin(state.declination))
                / (cos(phi) * cos(state.declination))
            guard cosH >= -1, cosH <= 1 else { return nil }

            let hourAngle = acos(cosH) / rad  // degrees
            let event = solarNoon + (rising ? -hourAngle : hourAngle) / 360
            result = event
            estimate = event
        }

        return result.map { dateFrom(julianDay: $0) }
    }

    public struct Events {
        public init() {}

        public var sunrise: Date?
        public var sunset: Date?
        /// Sun at +6°, descending — the start of golden hour before sunset.
        public var goldenHourStart: Date?
        /// Sun at +6°, ascending — the end of golden hour after sunrise.
        public var goldenHourEnd: Date?
        /// Sun at -4°, descending.
        public var blueHourStart: Date?

        public var dayLength: TimeInterval? {
            guard let sunrise, let sunset else { return nil }
            return sunset.timeIntervalSince(sunrise)
        }
    }

    public static func events(date: Date, latitude: Double, longitude: Double) -> Events {
        func at(_ altitude: Double, rising: Bool = false) -> Date? {
            time(altitude: altitude, rising: rising, date: date, latitude: latitude, longitude: longitude)
        }
        var events = Events()
        events.sunrise = at(Altitude.horizon, rising: true)
        events.sunset = at(Altitude.horizon)
        events.goldenHourStart = at(Altitude.golden)
        events.goldenHourEnd = at(Altitude.golden, rising: true)
        events.blueHourStart = at(Altitude.blue)
        return events
    }

    /// The next occurrence of `event`, rolling to tomorrow once today's has passed.
    public static func upcoming(
        _ keyPath: KeyPath<Events, Date?>,
        from now: Date,
        latitude: Double,
        longitude: Double
    ) -> (events: Events, isTomorrow: Bool) {
        let today = events(date: now, latitude: latitude, longitude: longitude)
        if let time = today[keyPath: keyPath], time > now {
            return (today, false)
        }
        let tomorrow = now.addingTimeInterval(secondsPerDay)
        return (events(date: tomorrow, latitude: latitude, longitude: longitude), true)
    }
}

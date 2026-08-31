import SwiftUI
import SolarKit
import Observation
import CoreLocation

enum SkyMode: String, CaseIterable {
    case sunset, sunrise

    var title: String { rawValue.uppercased() }
    /// Where this mode sits on the sky's phase axis.
    var phase: Double { self == .sunset ? 0 : 1 }
}

@MainActor
@Observable
final class SunsetModel {
    /// The mode being animated toward.
    var mode: SkyMode = .sunset
    /// The mode the numbers show. It lags `mode` so the readout changes while
    /// the sky is at its darkest, which is what sells the transition.
    var displayedMode: SkyMode = .sunset

    var sunsetEvents = Solar.Events()
    var sunriseEvents = Solar.Events()
    var sunsetIsTomorrow = false
    var sunriseIsTomorrow = false
    var weather: WeatherSnapshot?
    var forecast: SunsetForecast = .placeholder
    var usingFallbackLocation = true
    var errorMessage: String?
    var isRefreshing = false
    var now = Date()

    @ObservationIgnored private let location = LocationProvider()
    @ObservationIgnored private var coordinate = LocationProvider.fallback.coordinate
    let fallbackName = LocationProvider.fallback.name
    @ObservationIgnored private var tickTimer: Timer?
    @ObservationIgnored private var refreshTimer: Timer?

    init() {
        recomputeSolar()
        location.start { [weak self] fix in
            guard let self else { return }
            if let fix {
                self.coordinate = fix
                self.usingFallbackLocation = false
            } else {
                self.usingFallbackLocation = true
            }
            self.recomputeSolar()
            Task { await self.loadWeather() }
        }

        // Countdown resolution.
        tickTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.now = Date()
                self.recomputeSolar()
            }
        }
        // Conditions change slowly; every 10 minutes is plenty.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }

        Task { await loadWeather() }
    }

    private func recomputeSolar() {
        let lat = coordinate.latitude, lon = coordinate.longitude
        let set = Solar.upcoming(\.sunset, from: now, latitude: lat, longitude: lon)
        sunsetEvents = set.events
        sunsetIsTomorrow = set.isTomorrow

        let rise = Solar.upcoming(\.sunrise, from: now, latitude: lat, longitude: lon)
        sunriseEvents = rise.events
        sunriseIsTomorrow = rise.isTomorrow
    }

    /// Animate to the other mode, swapping the numbers mid-transition.
    func setMode(_ new: SkyMode, duration: Double = 1.7) {
        guard new != mode else { return }
        mode = new
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration * 0.45))
            withAnimation(.easeInOut(duration: 0.5)) { displayedMode = new }
        }
    }

    // MARK: - The active event

    private var events: Solar.Events {
        displayedMode == .sunset ? sunsetEvents : sunriseEvents
    }

    private var isTomorrow: Bool {
        displayedMode == .sunset ? sunsetIsTomorrow : sunriseIsTomorrow
    }

    /// The headline instant: sunset or sunrise, depending on mode.
    private var keyMoment: Date? {
        displayedMode == .sunset ? events.sunset : events.sunrise
    }

    func refresh() async {
        location.refresh()
        recomputeSolar()
        await loadWeather()
    }

    private func loadWeather() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let snapshot = try await WeatherService.fetch(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            weather = snapshot
            forecast = SunsetForecast.score(snapshot)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't reach the weather service"
        }
    }

    // MARK: - Formatted output

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        return f
    }()

    private static let meridiemFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "a"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d/yyyy"
        return f
    }()

    var sunsetClock: String {
        keyMoment.map { Self.timeFormatter.string(from: $0) } ?? "--:--"
    }

    var sunsetMeridiem: String {
        keyMoment.map { Self.meridiemFormatter.string(from: $0).lowercased() } ?? ""
    }

    var dateLine: String {
        Self.dateFormatter.string(from: keyMoment ?? now)
    }

    var headline: String {
        let noun = displayedMode == .sunset ? "sunset" : "sunrise"
        return (isTomorrow ? "Tomorrow's " : "Today's ") + noun
    }

    var countdownLabel: String {
        displayedMode == .sunset ? "Time to\nsunset" : "Time to\nsunrise"
    }

    var countdown: String {
        guard let moment = keyMoment else { return "—" }
        let seconds = moment.timeIntervalSince(now)
        guard seconds > 0 else { return "Now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(max(1, minutes)) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) hr" : "\(hours)h \(remainder)m"
    }

    /// Before sunset the golden hour begins; after sunrise it ends.
    var goldenHour: String {
        let moment = displayedMode == .sunset ? events.goldenHourStart : events.goldenHourEnd
        guard let moment else { return "—" }
        return Self.timeFormatter.string(from: moment)
            + Self.meridiemFormatter.string(from: moment).lowercased()
    }

    var goldenHourLabel: String {
        displayedMode == .sunset ? "Golden hour" : "Golden hour ends"
    }

    /// Just "Conditions": the header and the toggle both already say which
    /// event this is, and "SUNRISE CONDITIONS" wraps to a second line while
    /// "SUNSET CONDITIONS" does not, which reflows the label on every switch.
    let conditionsLabel = "Conditions"

    /// Sky phase for the current transition target.
    var skyPhase: Double { mode.phase }

    /// Fahrenheit only where the locale actually uses it. `.uk` is a distinct
    /// measurement system but reports temperature in Celsius, so only `.us`
    /// gets Fahrenheit.
    static var preferredTemperatureUnit: UnitTemperature {
        Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
    }

    /// Shown without a C/F suffix, as in the original design. It stays
    /// unambiguous because it always matches the reader's own locale.
    var temperature: String {
        guard let w = weather else { return "—" }
        let reading = Measurement(value: w.temperatureC, unit: UnitTemperature.celsius)
            .converted(to: Self.preferredTemperatureUnit)
        return "\(Int(reading.value.rounded()))°"
    }

    var humidity: String {
        weather.map { "\(Int($0.humidity.rounded()))%" } ?? "—"
    }

    var cloudHeight: String {
        weather?.cloudHeightLabel ?? "—"
    }

    var visibilityFraction: Double {
        weather?.visibilityFraction ?? 0
    }

    /// Deliberately computed in Celsius regardless of what is displayed: the
    /// gauge maps a physical range, so it must not shift when the locale does.
    var temperatureFraction: Double {
        guard let w = weather else { return 0.5 }
        // -10°C -> bottom, 40°C -> top.
        return min(1, max(0, (w.temperatureC + 10) / 50))
    }

    var humidityFraction: Double {
        guard let w = weather else { return 0.5 }
        return min(1, max(0, w.humidity / 100))
    }

    /// What the menu bar shows: the sunset clock time, compactly.
    var menuBarTitle: String {
        guard keyMoment != nil else { return "--:--" }
        let meridiem = sunsetMeridiem.first.map(String.init) ?? ""
        return sunsetClock + meridiem
    }
}

import Foundation
import CoreLocation

@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var onFix: ((CLLocationCoordinate2D?) -> Void)?

    /// Used until (or unless) a real fix arrives.
    static let fallback = FallbackLocation.current()

    private(set) var isAuthorized = false
    private(set) var didResolve = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func start(onFix: @escaping (CLLocationCoordinate2D?) -> Void) {
        self.onFix = onFix
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorized, .authorizedAlways:
            isAuthorized = true
            manager.requestLocation()
        default:
            didResolve = true
            onFix(nil)
        }
    }

    func refresh() {
        guard isAuthorized else { return }
        manager.requestLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorized, .authorizedAlways:
                self.isAuthorized = true
                self.manager.requestLocation()
            case .notDetermined:
                break
            default:
                self.isAuthorized = false
                self.didResolve = true
                self.onFix?(nil)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        Task { @MainActor in
            self.didResolve = true
            self.onFix?(coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.didResolve = true
            self.onFix?(nil)
        }
    }
}

import Foundation
import CoreLocation
import Observation

/// Where you are, only while the app is open and only when asked (for "Find nearby").
@MainActor
@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private(set) var location: CLLocation?
    private(set) var isDenied = false
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var waiting: [CheckedContinuation<CLLocation?, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Asks permission the first time; returns nil if refused or unavailable.
    func current() async -> CLLocation? {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            isDenied = true
            return nil
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            manager.requestLocation()
        }
        return await withCheckedContinuation { continuation in
            waiting.append(continuation)
        }
    }

    private func finish(_ location: CLLocation?) {
        if let location { self.location = location }
        let continuations = waiting
        waiting = []
        continuations.forEach { $0.resume(returning: location) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                isDenied = false
                if !waiting.isEmpty { self.manager.requestLocation() }
            case .denied, .restricted:
                isDenied = true
                finish(nil)
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let latest = locations.last
        Task { @MainActor in finish(latest) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in finish(nil) }
    }
}

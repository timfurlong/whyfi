import CoreLocation
import Observation

/// macOS reveals the Wi-Fi BSSID (which access point you're on) only to apps with Location
/// access. WhyFi never reads your location; it asks so it can log roaming between a router
/// and a mesh point.
@MainActor @Observable
final class LocationPermission: NSObject, PermissionChecking, CLLocationManagerDelegate {
    @ObservationIgnored private let manager = CLLocationManager()
    private(set) var status: CLAuthorizationStatus

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    var location: LocationAccess {
        switch manager.authorizationStatus {
        case .authorizedAlways: .granted
        case .denied, .restricted: .denied
        default: .undetermined
        }
    }

    /// Shows the system prompt the first time; does nothing once the user has answered.
    func request() {
        if status == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.status = status }
    }
}

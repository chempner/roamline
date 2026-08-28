import CoreLocation
import Combine
import Foundation

@MainActor
final class LocationTracker: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var isTracking = false
    @Published private(set) var lastError: String?

    var onLocation: ((CLLocation) -> Void)?
    var onTrackingUnavailable: ((String) -> Void)?
    private let manager = CLLocationManager()
    private var wantsTracking = false

    private var supportsBackgroundLocation: Bool {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        return modes?.contains("location") == true
    }

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.activityType = .otherNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 25
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
    }

    func start() {
        wantsTracking = true
        lastError = nil
        continueStarting(for: manager.authorizationStatus)
    }

    func stop() {
        wantsTracking = false
        manager.stopUpdatingLocation()
        if manager.allowsBackgroundLocationUpdates {
            manager.allowsBackgroundLocationUpdates = false
        }
        isTracking = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        guard wantsTracking else { return }
        continueStarting(for: manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isTracking else { return }
        for location in locations where location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 150 {
            currentLocation = location
            onLocation?(location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard (error as? CLError)?.code != .locationUnknown else { return }
        failTracking(error.localizedDescription)
    }

    private func continueStarting(for status: CLAuthorizationStatus) {
        authorizationStatus = status

        switch status {
        case .notDetermined:
            isTracking = false
            manager.requestWhenInUseAuthorization()

        case .authorizedWhenInUse:
            // Foreground updates are valid now. Background updates are enabled only
            // after iOS grants Always access; enabling them sooner raises an
            // Objective-C assertion that terminates the process.
            if manager.allowsBackgroundLocationUpdates {
                manager.allowsBackgroundLocationUpdates = false
            }
            manager.startUpdatingLocation()
            isTracking = true
            manager.requestAlwaysAuthorization()

        case .authorizedAlways:
            if supportsBackgroundLocation {
                manager.allowsBackgroundLocationUpdates = true
            }
            manager.startUpdatingLocation()
            isTracking = true

        case .denied, .restricted:
            failTracking("Location access is turned off. Enable Always Location access for Roamline in Settings to track a journey.")

        @unknown default:
            failTracking("Roamline could not start location tracking. Check its Location permission in Settings and try again.")
        }
    }

    private func failTracking(_ message: String) {
        wantsTracking = false
        manager.stopUpdatingLocation()
        if manager.allowsBackgroundLocationUpdates {
            manager.allowsBackgroundLocationUpdates = false
        }
        isTracking = false
        lastError = message
        onTrackingUnavailable?(message)
    }
}

import CoreLocation
import Combine
import Foundation

enum GPSMode: String, CaseIterable, Identifiable {
    case batterySaver
    case balanced
    case highAccuracy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .batterySaver: "Battery Saver"
        case .balanced: "Balanced"
        case .highAccuracy: "High Accuracy"
        }
    }

    var detail: String {
        switch self {
        case .batterySaver: "Updates roughly every 100–150 metres and allows iOS to pause GPS when stationary."
        case .balanced: "Updates roughly every 25 metres with a practical balance of route detail and battery life."
        case .highAccuracy: "Uses navigation-grade accuracy and continuous updates. This consumes noticeably more battery."
        }
    }
}

@MainActor
final class LocationTracker: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var isTracking = false
    @Published private(set) var lastError: String?
    @Published private(set) var gpsMode: GPSMode

    var onLocation: ((CLLocation) -> Void)?
    var onTrackingUnavailable: ((String) -> Void)?
    private let manager = CLLocationManager()
    private var wantsTracking = false
    private static let gpsModeKey = "roamline-gps-mode"

    private var supportsBackgroundLocation: Bool {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        return modes?.contains("location") == true
    }

    override init() {
        authorizationStatus = manager.authorizationStatus
        gpsMode = GPSMode(rawValue: UserDefaults.standard.string(forKey: Self.gpsModeKey) ?? "") ?? .balanced
        super.init()
        manager.delegate = self
        manager.showsBackgroundLocationIndicator = true
        applyGPSMode()
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

    func setGPSMode(_ mode: GPSMode) {
        guard gpsMode != mode else { return }
        gpsMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.gpsModeKey)
        applyGPSMode()
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

    private func applyGPSMode() {
        manager.activityType = .otherNavigation

        switch gpsMode {
        case .batterySaver:
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            manager.distanceFilter = 125
            manager.pausesLocationUpdatesAutomatically = true

        case .balanced:
            manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            manager.distanceFilter = 25
            manager.pausesLocationUpdatesAutomatically = true

        case .highAccuracy:
            manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            manager.distanceFilter = kCLDistanceFilterNone
            manager.pausesLocationUpdatesAutomatically = false
        }
    }
}

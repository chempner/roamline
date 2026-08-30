import CoreLocation
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var user: SessionUser?
    @Published private(set) var trips: [Trip] = []
    @Published var selectedTrip: Trip?
    @Published private(set) var trackingTripID: String?
    @Published private(set) var pendingPointCount = 0
    @Published private(set) var isRestoring = true
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var serverURL: String

    let locationTracker = LocationTracker()
    private let pointStore = OfflinePointStore()
    private let client: APIClient
    private var isSyncing = false
    private var token: String?
    private var statusBeforeTracking: (tripID: String, status: String)?

    private static let defaultServer = "https://roamline.chempner.ch"
    private static let serverKey = "roamline-server-url"
    private static let trackingTripKey = "roamline-tracking-trip"

    init() {
        let storedURL = UserDefaults.standard.string(forKey: Self.serverKey) ?? Self.defaultServer
        serverURL = storedURL
        token = KeychainStore.read()
        client = APIClient(baseURL: URL(string: storedURL) ?? URL(string: Self.defaultServer)!, token: token)
        trackingTripID = UserDefaults.standard.string(forKey: Self.trackingTripKey)
        locationTracker.onLocation = { [weak self] location in
            Task { await self?.capture(location) }
        }
        locationTracker.onTrackingUnavailable = { [weak self] message in
            self?.cancelTrackingAfterLocationFailure(message)
        }
        Task { await restoreSession() }
    }

    var isSignedIn: Bool { user != nil }
    var isTracking: Bool { trackingTripID != nil && locationTracker.isTracking }

    func restoreSession() async {
        defer { isRestoring = false }
        pendingPointCount = await pointStore.count()
        guard token != nil else { return }
        do {
            user = try await client.me()
            await loadTrips()
            if trackingTripID != nil { locationTracker.start() }
            await flushPending()
        } catch {
            if let apiError = error as? APIError, case .unauthorized = apiError { signOutLocally() }
            else { errorMessage = error.localizedDescription }
        }
    }

    func login(username: String, password: String, server: String) async throws {
        guard let url = normalizedServer(server) else { throw APIError.invalidServer }
        isLoading = true
        defer { isLoading = false }
        await client.configure(baseURL: url, token: nil)
        let response = try await client.login(username: username, password: password)
        if response.mustChangePassword == true { throw APIError.passwordChangeRequired }
        guard let newToken = response.token else { throw APIError.invalidResponse }
        token = newToken
        KeychainStore.save(newToken)
        serverURL = url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        UserDefaults.standard.set(serverURL, forKey: Self.serverKey)
        await client.configure(baseURL: url, token: newToken)
        user = try await client.me()
        await loadTrips()
    }

    func logout() {
        stopTracking(markCompleted: false)
        signOutLocally()
    }

    func loadTrips() async {
        guard token != nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            trips = try await client.trips()
            if let selected = selectedTrip, let match = trips.first(where: { $0.id == selected.id }) {
                selectedTrip = match
            }
        } catch {
            handle(error)
        }
    }

    func loadTrip(_ trip: Trip) async {
        do { selectedTrip = try await client.trip(id: trip.id) }
        catch { handle(error) }
    }

    func createTrip(title: String, summary: String, startDate: Date, endDate: Date?) async throws {
        let request = CreateTripRequest(
            title: title, summary: summary,
            startDate: Self.utcMidnightString(for: startDate),
            endDate: endDate.map { Self.utcMidnightString(for: $0) }, status: "planned"
        )
        let trip = try await client.createTrip(request)
        trips.insert(trip, at: 0)
        selectedTrip = trip
    }

    func startTracking(trip: Trip) async {
        do {
            statusBeforeTracking = (trip.id, trip.status)
            _ = try await client.setTripStatus(id: trip.id, status: "active")
            trackingTripID = trip.id
            UserDefaults.standard.set(trip.id, forKey: Self.trackingTripKey)
            locationTracker.start()
            await loadTrips()
        } catch {
            statusBeforeTracking = nil
            handle(error)
        }
    }

    func addMoment(to trip: Trip, title: String, story: String, place: String, date: Date, photoData: Data?) async throws {
        let current = locationTracker.currentLocation
        let lastRoutePoint = trip.route?.last
        let request = CreateMomentRequest(
            title: title, story: story, place: place,
            latitude: current?.coordinate.latitude ?? lastRoutePoint?.latitude,
            longitude: current?.coordinate.longitude ?? lastRoutePoint?.longitude,
            visitedAt: ISO8601DateFormatter().string(from: date)
        )
        let moment = try await client.createMoment(tripId: trip.id, request: request)
        if let photoData { try await client.uploadPhoto(momentId: moment.id, jpegData: photoData) }
        selectedTrip = try await client.trip(id: trip.id)
        await loadTrips()
    }

    func stopTracking(markCompleted: Bool) {
        let tripID = trackingTripID
        locationTracker.stop()
        trackingTripID = nil
        statusBeforeTracking = nil
        UserDefaults.standard.removeObject(forKey: Self.trackingTripKey)
        Task {
            await flushPending()
            if markCompleted, let tripID {
                do { _ = try await client.setTripStatus(id: tripID, status: "completed") }
                catch { handle(error) }
            }
            await loadTrips()
        }
    }

    func flushPending() async {
        guard !isSyncing, token != nil else { return }
        isSyncing = true
        defer { isSyncing = false }
        // Only the signed-in account's points (plus legacy untagged ones) are flushed, so a 404
        // for another user's trip can never delete that user's undelivered points.
        let owner = user?.username
        while true {
            // An account switch mid-flush would upload (and 404-drop) the previous user's points
            // with the new user's token, so bail as soon as the session no longer matches.
            guard user?.username == owner, token != nil else { break }
            let batch = await pointStore.nextBatch(owner: owner)
            guard !batch.isEmpty, let tripID = batch.first?.tripId else { break }
            do {
                _ = try await client.upload(tripId: tripID, points: batch)
                await pointStore.remove(ids: Set(batch.map(\.id)))
            } catch APIError.server(let status, _) where status == 404 {
                // The trip no longer exists server-side, so its queued points can never be delivered.
                // Unless the session changed while the upload was in flight — then the 404 only
                // reflects the new account's ownership, and the points must survive.
                guard user?.username == owner else { break }
                await pointStore.removeAll(tripId: tripID, owner: owner)
            } catch {
                // Transient failure: offline data is intentionally retained; the next foreground/location event retries it.
                break
            }
            pendingPointCount = await pointStore.count()
        }
        pendingPointCount = await pointStore.count()
    }

    private func capture(_ location: CLLocation) async {
        guard let tripID = trackingTripID else { return }
        statusBeforeTracking = nil
        let point = PendingLocation(
            id: UUID().uuidString.lowercased(), tripId: tripID,
            latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
            altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
            accuracy: location.horizontalAccuracy,
            speed: location.speed >= 0 ? location.speed : nil,
            course: location.course >= 0 ? location.course : nil,
            recordedAt: ISO8601DateFormatter().string(from: location.timestamp),
            owner: user?.username
        )
        await pointStore.append(point)
        pendingPointCount = await pointStore.count()
        if pendingPointCount >= 5 { await flushPending() }
    }

    // Trip start/end dates are calendar days, stored server-side as UTC midnight (the web client
    // sends date-only strings). Strip the time component in the user's calendar and encode the
    // matching UTC-midnight instant so both clients agree on the calendar date.
    private static func utcMidnightString(for date: Date) -> String {
        // Components must come from a Gregorian calendar (in the user's timezone): Calendar.current
        // honors the device's preferred calendar, and a Buddhist/Japanese year fed into the
        // Gregorian reconstruction below would land centuries off.
        var localGregorian = Calendar(identifier: .gregorian)
        localGregorian.timeZone = TimeZone.current
        let components = localGregorian.dateComponents([.year, .month, .day], from: date)
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        return ISO8601DateFormatter().string(from: utcCalendar.date(from: components) ?? date)
    }

    private func normalizedServer(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1"].contains(url.host)) else { return nil }
        return url
    }

    private func handle(_ error: Error) {
        if let apiError = error as? APIError, case .unauthorized = apiError { signOutLocally() }
        else { errorMessage = error.localizedDescription }
    }

    private func cancelTrackingAfterLocationFailure(_ message: String) {
        let failedTripID = trackingTripID
        trackingTripID = nil
        UserDefaults.standard.removeObject(forKey: Self.trackingTripKey)
        errorMessage = message
        if let previous = statusBeforeTracking, previous.tripID == failedTripID, previous.status != "active" {
            statusBeforeTracking = nil
            Task {
                // Best effort: the trip should not stay "active" when tracking never started.
                _ = try? await client.setTripStatus(id: previous.tripID, status: previous.status)
                await loadTrips()
            }
        }
    }

    private func signOutLocally() {
        locationTracker.stop()
        trackingTripID = nil
        statusBeforeTracking = nil
        UserDefaults.standard.removeObject(forKey: Self.trackingTripKey)
        token = nil
        user = nil
        trips = []
        selectedTrip = nil
        KeychainStore.delete()
        Task { await client.configure(baseURL: URL(string: serverURL) ?? URL(string: Self.defaultServer)!, token: nil) }
    }
}

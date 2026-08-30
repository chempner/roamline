import CoreLocation
import MapKit
import PhotosUI
import SwiftUI
import UIKit

extension Color {
    static let roamForest = Color(red: 22/255, green: 55/255, blue: 47/255)
    static let roamCoral = Color(red: 230/255, green: 101/255, blue: 70/255)
    static let roamCream = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 13/255, green: 22/255, blue: 19/255, alpha: 1)
            : UIColor(red: 245/255, green: 244/255, blue: 239/255, alpha: 1)
    })
    static let roamSurface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 24/255, green: 35/255, blue: 31/255, alpha: 1)
            : .white
    })
    static let roamPrimary = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 238/255, green: 241/255, blue: 239/255, alpha: 1)
            : UIColor(red: 22/255, green: 55/255, blue: 47/255, alpha: 1)
    })
    static let roamMuted = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 166/255, green: 181/255, blue: 175/255, alpha: 1)
            : UIColor(red: 111/255, green: 125/255, blue: 120/255, alpha: 1)
    })
}

private let displayDate: DateFormatter = {
    let value = DateFormatter()
    value.dateStyle = .medium
    return value
}()

// Trip start/end dates are stored as UTC midnight of the chosen calendar day, so they are
// pinned to UTC for display (matching the web app). Moment and point timestamps stay local.
private let tripDisplayDate: DateFormatter = {
    let value = DateFormatter()
    value.dateStyle = .medium
    value.timeZone = TimeZone(identifier: "UTC")
    return value
}()

private func parseISO(_ value: String?) -> Date? {
    guard let value else { return nil }
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return withFraction.date(from: value) ?? ISO8601DateFormatter().date(from: value)
}

private func tripDateText(_ trip: Trip) -> String {
    guard let start = parseISO(trip.startDate) else { return "Dates not set" }
    if let end = parseISO(trip.endDate) {
        return "\(tripDisplayDate.string(from: start)) – \(tripDisplayDate.string(from: end))"
    }
    return tripDisplayDate.string(from: start)
}

struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack {
            Color.roamCream.ignoresSafeArea()
            Group {
                if state.isRestoring {
                    ProgressView().controlSize(.large).tint(.roamCoral)
                } else if state.isSignedIn {
                    MainTabView()
                } else {
                    LoginView()
                }
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) {
            Button("OK") { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "Please try again.")
        }
    }
}

struct BrandMark: View {
    var size: CGFloat = 44
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28).fill(Color.roamCoral)
            Image(systemName: "point.bottomleft.forward.to.point.topright.scurvepath")
                .font(.system(size: size * 0.43, weight: .bold)).foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: .roamCoral.opacity(0.22), radius: 9, y: 5)
    }
}

struct LoginView: View {
    @EnvironmentObject private var state: AppState
    @State private var username = ""
    @State private var password = ""
    @State private var server = ""
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        BrandMark(size: 46)
                        Text("Roamline").font(.title2.bold()).foregroundStyle(.white)
                    }
                    .padding(.top, 24)

                    Spacer(minLength: 54)
                    Text("YOUR JOURNEY, YOUR DATA")
                        .font(.caption2.bold()).tracking(1.7).foregroundStyle(Color.white.opacity(0.6))
                    Text("Keep the road.\nTell the story.")
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                        .tracking(-1.5).foregroundStyle(.white).padding(.top, 10)
                    Text("Trace your travels in the background and keep every adventure on your own server.")
                        .font(.body).foregroundStyle(Color.white.opacity(0.68)).lineSpacing(4).padding(.top, 12)

                    VStack(spacing: 13) {
                        LoginField(title: "Username", text: $username, contentType: .username)
                        LoginField(title: "Password", text: $password, contentType: .password, secure: true)
                        LoginField(title: "Server URL", text: $server, contentType: .URL, capitalization: .never)
                    }
                    .padding(20)
                    .background(Color.roamSurface, in: RoundedRectangle(cornerRadius: 24))
                    .shadow(color: Color.black.opacity(0.14), radius: 30, y: 16)
                    .padding(.top, 35)

                    if let localError {
                        Text(localError).font(.footnote).foregroundStyle(Color(red: 1, green: 0.75, blue: 0.69)).padding(.top, 13)
                    }

                    Button {
                        Task {
                            do { try await state.login(username: username, password: password, server: server) }
                            catch { localError = error.localizedDescription }
                        }
                    } label: {
                        HStack {
                            if state.isLoading { ProgressView().tint(.white) }
                            else { Text("Continue exploring"); Spacer(); Image(systemName: "arrow.right") }
                        }
                        .fontWeight(.bold).frame(maxWidth: .infinity).padding(.horizontal, 18).frame(height: 54)
                        .background(Color.roamCoral, in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(.white)
                    }
                    .disabled(username.isEmpty || password.isEmpty || server.isEmpty || state.isLoading)
                    .padding(.top, 18)

                    Text("Sign in with your AuthService account")
                        .font(.caption).foregroundStyle(Color.white.opacity(0.48)).frame(maxWidth: .infinity).padding(.top, 14)
                }
                .padding(.horizontal, 24).padding(.bottom, 45).frame(maxWidth: 620)
            }
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [.roamForest, Color(red: 35/255, green: 79/255, blue: 67/255)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            )
            .onAppear { if server.isEmpty { server = state.serverURL } }
        }
    }
}

struct LoginField: View {
    let title: String
    @Binding var text: String
    let contentType: UITextContentType?
    var secure = false
    var capitalization: TextInputAutocapitalization = .never

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased()).font(.caption2.bold()).tracking(0.8).foregroundStyle(Color.roamMuted)
            Group {
                if secure { SecureField(title, text: $text).textContentType(contentType) }
                else { TextField(title, text: $text).textContentType(contentType).textInputAutocapitalization(capitalization).autocorrectionDisabled() }
            }
            .padding(.horizontal, 14).frame(height: 48)
            .background(Color.roamCream, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(Color.roamPrimary)
        }
    }
}

struct MainTabView: View {
    var body: some View {
        ZStack {
            Color.roamCream.ignoresSafeArea()
            TabView {
                NavigationStack { JourneyListView() }
                    .tabItem { Label("Journeys", systemImage: "map") }
                NavigationStack { TrackingView() }
                    .tabItem { Label("Tracking", systemImage: "location.fill") }
                NavigationStack { SettingsView() }
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
        }
    }
}

struct JourneyListView: View {
    @EnvironmentObject private var state: AppState
    @State private var showCreate = false

    var body: some View {
        ZStack {
            Color.roamCream.ignoresSafeArea()
            if state.trips.isEmpty && !state.isLoading {
                ContentUnavailableView {
                    Label("The map is waiting", systemImage: "globe.europe.africa")
                } description: {
                    Text("Create a journey, then let Roamline trace the road while you travel.")
                } actions: {
                    Button("Plan your first trip") { showCreate = true }.buttonStyle(.borderedProminent)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 13) {
                        JourneySummary(trips: state.trips)
                        ForEach(state.trips) { trip in
                            NavigationLink {
                                TripDetailView(trip: trip)
                            } label: {
                                JourneyCard(trip: trip, isTracking: state.trackingTripID == trip.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
                .refreshable { await state.loadTrips() }
            }
        }
        .navigationTitle("Journeys")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { BrandMark(size: 32) }
            ToolbarItem(placement: .topBarTrailing) { Button { showCreate = true } label: { Image(systemName: "plus") } }
        }
        .sheet(isPresented: $showCreate) { CreateTripView() }
    }
}

struct JourneySummary: View {
    let trips: [Trip]
    private var total: Double { trips.reduce(0) { $0 + $1.distanceKm } }
    private var moments: Int { trips.reduce(0) { $0 + $1.momentCount } }
    var body: some View {
        HStack(spacing: 0) {
            SummaryValue(value: "\(trips.count)", label: "journeys")
            Divider().frame(height: 30)
            SummaryValue(value: total.formatted(.number.precision(.fractionLength(0...1))), label: "km traced")
            Divider().frame(height: 30)
            SummaryValue(value: "\(moments)", label: "moments")
        }
        .padding(.vertical, 17).background(Color.roamSurface.opacity(0.9), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct SummaryValue: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 3) { Text(value).font(.headline).foregroundStyle(Color.roamPrimary); Text(label).font(.caption2).foregroundStyle(Color.roamMuted) }
            .frame(maxWidth: .infinity)
    }
}

struct JourneyCard: View {
    let trip: Trip
    let isTracking: Bool
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 15).fill(Color.roamCoral.opacity(0.12))
                Image(systemName: isTracking ? "location.fill" : "map.fill").foregroundStyle(Color.roamCoral)
            }.frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 5) {
                HStack { Text(trip.title).font(.headline).foregroundStyle(Color.roamPrimary).lineLimit(1); if isTracking { LiveDot() } }
                Text(tripDateText(trip)).font(.caption).foregroundStyle(Color.roamMuted)
                Text("\(trip.distanceKm.formatted(.number.precision(.fractionLength(0...1)))) km  ·  \(trip.momentCount) moments")
                    .font(.caption2).foregroundStyle(Color.roamMuted)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Color.roamMuted.opacity(0.7))
        }
        .padding(15).background(Color.roamSurface, in: RoundedRectangle(cornerRadius: 19))
    }
}

struct LiveDot: View {
    var body: some View {
        HStack(spacing: 4) { Circle().fill(Color.roamCoral).frame(width: 6, height: 6); Text("LIVE").font(.system(size: 8, weight: .heavy)).foregroundStyle(Color.roamCoral) }
            .padding(.horizontal, 7).padding(.vertical, 4).background(Color.roamCoral.opacity(0.1), in: Capsule())
    }
}

struct CreateTripView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var summary = ""
    @State private var startDate = Date()
    @State private var hasEndDate = false
    @State private var endDate = Date().addingTimeInterval(7 * 86_400)
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("The journey") {
                    TextField("Trip name", text: $title)
                    TextField("What are you looking forward to?", text: $summary, axis: .vertical).lineLimit(3...6)
                }
                Section("Dates") {
                    DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                    Toggle("Set an end date", isOn: $hasEndDate)
                    if hasEndDate { DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: .date) }
                }
            }
            .navigationTitle("New journey").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        saving = true
                        Task {
                            do { try await state.createTrip(title: title, summary: summary, startDate: startDate, endDate: hasEndDate ? endDate : nil); dismiss() }
                            catch { state.errorMessage = error.localizedDescription; saving = false }
                        }
                    }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
        }
    }
}

struct TripDetailView: View {
    @EnvironmentObject private var state: AppState
    let trip: Trip
    @State private var showMoment = false

    private var shownTrip: Trip { state.selectedTrip?.id == trip.id ? state.selectedTrip! : trip }
    private var coordinates: [CLLocationCoordinate2D] {
        (shownTrip.route ?? []).map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }
    private var mapPins: [TripMapPin] {
        (shownTrip.moments ?? []).compactMap { moment in
            guard let latitude = moment.latitude, let longitude = moment.longitude else { return nil }
            return TripMapPin(id: moment.id, title: moment.title, coordinate: .init(latitude: latitude, longitude: longitude))
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Map {
                    if coordinates.count > 1 {
                        MapPolyline(coordinates: coordinates).stroke(Color.roamCoral, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    }
                    ForEach(mapPins) { pin in
                        Marker(pin.title, coordinate: pin.coordinate).tint(Color.roamForest)
                    }
                }
                .mapStyle(.standard(elevation: .realistic)).frame(height: 310)
                .overlay(alignment: .bottomLeading) {
                    if coordinates.isEmpty {
                        Label("Start tracking to draw the route", systemImage: "location")
                            .font(.caption.bold()).padding(11).background(.thinMaterial, in: Capsule()).padding(14)
                    }
                }

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(shownTrip.status == "active" ? "ON THE ROAD" : shownTrip.status.uppercased())
                            .font(.caption2.bold()).tracking(1.2).foregroundStyle(Color.roamCoral)
                        Text(shownTrip.title).font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(Color.roamPrimary)
                        if !shownTrip.summary.isEmpty { Text(shownTrip.summary).foregroundStyle(Color.roamMuted).lineSpacing(3) }
                        Label(tripDateText(shownTrip), systemImage: "calendar").font(.caption).foregroundStyle(Color.roamMuted)
                    }

                    HStack(spacing: 0) {
                        SummaryValue(value: shownTrip.distanceKm.formatted(.number.precision(.fractionLength(0...1))), label: "kilometres")
                        Divider().frame(height: 32)
                        SummaryValue(value: "\(shownTrip.pointCount)", label: "GPS points")
                        Divider().frame(height: 32)
                        SummaryValue(value: "\(shownTrip.momentCount)", label: "moments")
                    }
                    .padding(.vertical, 15).background(Color.roamCream, in: RoundedRectangle(cornerRadius: 17))

                    Text("TRAVEL JOURNAL").font(.caption2.bold()).tracking(1.4).foregroundStyle(Color.roamCoral).padding(.top, 5)
                    if let moments = shownTrip.moments, !moments.isEmpty {
                        ForEach(moments) { moment in MomentRow(moment: moment) }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "mappin.and.ellipse").font(.largeTitle).foregroundStyle(Color.roamCoral)
                            Text("Your first moment starts the story").font(.headline)
                            Text("Moments and photos added from Roamline will appear here.").font(.caption).foregroundStyle(Color.roamMuted).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding(30)
                        .background(Color.roamCream, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
                .padding(20).background(Color.roamSurface)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle(shownTrip.title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showMoment = true } label: { Image(systemName: "mappin.and.ellipse") }
            }
        }
        .sheet(isPresented: $showMoment) { AddMomentView(trip: shownTrip) }
        .task { await state.loadTrip(trip) }
    }
}

private struct TripMapPin: Identifiable {
    let id: String
    let title: String
    let coordinate: CLLocationCoordinate2D
}

struct MomentRow: View {
    let moment: Moment
    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            ZStack { Circle().fill(Color.roamCoral.opacity(0.12)); Image(systemName: "mappin").foregroundStyle(Color.roamCoral) }.frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 5) {
                HStack { Text(moment.title).font(.headline); Spacer(); if let date = parseISO(moment.visitedAt) { Text(displayDate.string(from: date)).font(.caption2).foregroundStyle(Color.roamMuted) } }
                if !moment.place.isEmpty { Label(moment.place, systemImage: "location").font(.caption).foregroundStyle(Color.roamMuted) }
                if !moment.story.isEmpty { Text(moment.story).font(.subheadline).foregroundStyle(Color.roamMuted).lineSpacing(3).padding(.top, 2) }
            }
        }
        .padding(15).background(Color.roamCream.opacity(0.65), in: RoundedRectangle(cornerRadius: 17))
    }
}

struct AddMomentView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    @State private var title = ""
    @State private var place = ""
    @State private var story = ""
    @State private var date = Date()
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var preview: UIImage?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Moment") {
                    TextField("Title", text: $title)
                    TextField("Place", text: $place)
                    DatePicker("When", selection: $date)
                    TextField("What happened here?", text: $story, axis: .vertical).lineLimit(4...8)
                }
                Section("Photo") {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(preview == nil ? "Choose a photo" : "Change photo", systemImage: "photo")
                    }
                    if let preview {
                        Image(uiImage: preview).resizable().scaledToFill().frame(height: 190).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 14)).clipped()
                    }
                }
            }
            .navigationTitle("Add a moment").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saving = true
                        Task {
                            do { try await state.addMoment(to: trip, title: title, story: story, place: place, date: date, photoData: photoData); dismiss() }
                            catch { state.errorMessage = error.localizedDescription; saving = false }
                        }
                    }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
                }
            }
            .onChange(of: photoItem) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                    preview = image
                    photoData = image.jpegData(compressionQuality: 0.84)
                }
            }
        }
    }
}

struct TrackingView: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedID = ""
    @State private var showFinishConfirmation = false

    private var selectedTrip: Trip? {
        if let active = state.trackingTripID { return state.trips.first(where: { $0.id == active }) }
        return state.trips.first(where: { $0.id == selectedID })
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [.roamForest, Color(red: 31/255, green: 74/255, blue: 62/255)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 25) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.07), lineWidth: 28).frame(width: 235, height: 235)
                        Circle().stroke(Color.roamCoral.opacity(state.isTracking ? 0.35 : 0.12), lineWidth: 2).frame(width: 188, height: 188)
                        VStack(spacing: 9) {
                            Image(systemName: state.isTracking ? "location.fill" : "location").font(.system(size: 38, weight: .semibold)).foregroundStyle(state.isTracking ? Color.roamCoral : .white.opacity(0.5))
                            Text(state.isTracking ? "TRACKING" : "READY").font(.caption.bold()).tracking(2).foregroundStyle(.white.opacity(0.6))
                            if state.isTracking { LiveDot() }
                        }
                    }
                    .padding(.top, 20)

                    VStack(spacing: 7) {
                        Text(selectedTrip?.title ?? "Choose a journey").font(.title2.bold()).foregroundStyle(.white)
                        if let location = state.locationTracker.currentLocation {
                            Text("±\(Int(location.horizontalAccuracy)) m · \(location.timestamp.formatted(date: .omitted, time: .shortened))")
                                .font(.caption).foregroundStyle(.white.opacity(0.55))
                        } else { Text("Waiting for a location fix").font(.caption).foregroundStyle(.white.opacity(0.55)) }
                    }

                    if !state.isTracking {
                        Picker("Journey", selection: $selectedID) {
                            Text("Select a journey").tag("")
                            ForEach(state.trips.filter { $0.status != "completed" }) { Text($0.title).tag($0.id) }
                        }
                        .pickerStyle(.menu).tint(.white)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
                    }

                    Button {
                        if state.isTracking { showFinishConfirmation = true }
                        else if let selectedTrip { Task { await state.startTracking(trip: selectedTrip) } }
                    } label: {
                        Label(state.isTracking ? "Stop tracking" : "Start tracking", systemImage: state.isTracking ? "stop.fill" : "location.fill")
                            .fontWeight(.bold).frame(maxWidth: .infinity).frame(height: 56)
                            .background(state.isTracking ? Color.white : Color.roamCoral, in: RoundedRectangle(cornerRadius: 17))
                            .foregroundStyle(state.isTracking ? Color.roamForest : .white)
                    }
                    .disabled(!state.isTracking && selectedTrip == nil)

                    BackgroundAccessWarning(tracker: state.locationTracker, isTracking: state.isTracking)

                    VStack(alignment: .leading, spacing: 13) {
                        PermissionRow(icon: "location.circle", title: "Location access", value: permissionText(state.locationTracker.authorizationStatus))
                        Divider().overlay(Color.white.opacity(0.09))
                        PermissionRow(icon: "arrow.triangle.2.circlepath", title: "Waiting to sync", value: "\(state.pendingPointCount) points")
                        Divider().overlay(Color.white.opacity(0.09))
                        GPSModeMenu(tracker: state.locationTracker)
                    }
                    .padding(18).background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 19))

                    Text("Roamline records only while tracking is on. A blue location indicator may remain visible when the app is in the background.")
                        .font(.caption).foregroundStyle(.white.opacity(0.42)).multilineTextAlignment(.center).lineSpacing(3)
                }
                .padding(20)
            }
        }
        .navigationTitle("Tracking").navigationBarTitleDisplayMode(.inline).toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { if selectedID.isEmpty { selectedID = state.trips.first(where: { $0.status != "completed" })?.id ?? "" } }
        .confirmationDialog("Finish this journey?", isPresented: $showFinishConfirmation) {
            Button("Stop and mark completed") { state.stopTracking(markCompleted: true) }
            Button("Pause tracking") { state.stopTracking(markCompleted: false) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("All remaining GPS points stay safely queued until they sync.") }
    }

    private func permissionText(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedAlways: "Always allowed"
        case .authorizedWhenInUse: "While using app"
        case .denied, .restricted: "Not allowed"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }
}

struct BackgroundAccessWarning: View {
    @ObservedObject var tracker: LocationTracker
    let isTracking: Bool

    var body: some View {
        if isTracking && !tracker.backgroundCapable {
            Label("Location access is limited to \"While Using\", so recording stops whenever Roamline goes to the background. Allow Always access in Settings to keep tracking.", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote).foregroundStyle(Color.roamCoral).lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.roamCoral.opacity(0.13), in: RoundedRectangle(cornerRadius: 15))
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let value: String
    var body: some View {
        HStack { Image(systemName: icon).frame(width: 26).foregroundStyle(Color.roamCoral); Text(title).foregroundStyle(.white.opacity(0.8)); Spacer(); Text(value).foregroundStyle(.white.opacity(0.48)) }
            .font(.subheadline)
    }
}

struct GPSModeMenu: View {
    @ObservedObject var tracker: LocationTracker

    var body: some View {
        Menu {
            ForEach(GPSMode.allCases) { mode in
                Button { tracker.setGPSMode(mode) } label: {
                    Label(mode.title, systemImage: tracker.gpsMode == mode ? "checkmark" : "circle")
                }
            }
        } label: {
            HStack {
                Image(systemName: "battery.75percent").frame(width: 26).foregroundStyle(Color.roamCoral)
                Text("Battery mode").foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text(tracker.gpsMode.title).foregroundStyle(.white.opacity(0.48))
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.white.opacity(0.35))
            }
            .font(.subheadline)
            .contentShape(Rectangle())
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @AppStorage(AppAppearance.storageKey) private var appearanceValue = AppAppearance.system.rawValue

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    BrandMark(size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(state.user?.displayName ?? state.user?.username ?? "Explorer").font(.headline)
                        Text(state.user?.username ?? "").font(.caption).foregroundStyle(Color.roamMuted)
                    }
                }.padding(.vertical, 5)
            }
            Section("Appearance") {
                Picker("Color scheme", selection: $appearanceValue) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section("Tracking") {
                Picker("Battery mode", selection: Binding(
                    get: { state.locationTracker.gpsMode },
                    set: { state.locationTracker.setGPSMode($0) }
                )) {
                    ForEach(GPSMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Text(state.locationTracker.gpsMode.detail)
                    .font(.caption)
                    .foregroundStyle(Color.roamMuted)
            }
            Section("Server") {
                LabeledContent("Address", value: state.serverURL).font(.caption)
                LabeledContent("Pending GPS points", value: "\(state.pendingPointCount)")
                Button("Sync now") { Task { await state.flushPending() } }
            }
            Section("Privacy") {
                Label("Trips are private by default", systemImage: "lock.fill")
                Text("A trip is visible to others only after you create a sharing link in the web app.").font(.caption).foregroundStyle(Color.roamMuted)
            }
            Section {
                Button("Sign out", role: .destructive) { state.logout() }
            }
            Section { Text("Roamline 0.1.0").font(.caption).foregroundStyle(Color.roamMuted).frame(maxWidth: .infinity) }
        }
        .navigationTitle("Settings")
    }
}

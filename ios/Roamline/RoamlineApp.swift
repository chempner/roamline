import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "roamline-appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@main
struct RoamlineApp: App {
    @StateObject private var state = AppState()
    @AppStorage(AppAppearance.storageKey) private var appearanceValue = AppAppearance.system.rawValue

    private var preferredColorScheme: ColorScheme? {
        (AppAppearance(rawValue: appearanceValue) ?? .system).colorScheme
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Color.roamCream.ignoresSafeArea()
                RootView()
            }
            .environmentObject(state)
            .tint(.roamCoral)
            .preferredColorScheme(preferredColorScheme)
        }
    }
}

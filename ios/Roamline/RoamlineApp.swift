import SwiftUI

@main
struct RoamlineApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .tint(.roamCoral)
        }
    }
}

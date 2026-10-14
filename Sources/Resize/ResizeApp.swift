import ResizeKit
import SwiftUI

@main
struct ResizeApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView().environment(state)
        } label: {
            MenuBarLabel().environment(state)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar icon. Also opens the settings window on first launch so onboarding appears.
private struct MenuBarLabel: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Image(systemName: state.config.paused ? "minus.magnifyingglass" : "plus.magnifyingglass")
            .task {
                if !state.config.hasCompletedOnboarding { state.openSettings() }
            }
    }
}

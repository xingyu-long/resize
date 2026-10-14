import ResizeKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        Group {
            if state.config.hasCompletedOnboarding {
                NavigationSplitView {
                    List(selection: $state.route) {
                        Label("General", systemImage: "gearshape").tag(SettingsRoute.general)
                        Label("Apps", systemImage: "square.grid.2x2").tag(SettingsRoute.apps)
                        Section("Your apps") {
                            ForEach(state.rules) { rule in
                                HStack(spacing: 8) {
                                    AppIconView(bundleID: rule.bundleID, size: 18)
                                    Text(rule.displayName).lineLimit(1)
                                }
                                .tag(SettingsRoute.app(rule.bundleID))
                            }
                        }
                    }
                    .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 220)
                } detail: {
                    switch state.route {
                    case .general: GeneralSettingsView()
                    case .apps: AppsTableView()
                    case .app(let id): AppDetailView(bundleID: id)
                    }
                }
            } else {
                OnboardingView()
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}

#Preview {
    SettingsView().environment(AppState.preview())
}

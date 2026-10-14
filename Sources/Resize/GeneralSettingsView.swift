import ResizeKit
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var state
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section("Default zoom") {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(DisplayMode.allCases, id: \.self) { mode in
                        ZoomCard(mode: mode, isNow: state.currentMode == mode, percent: state.defaultBinding(mode))
                    }
                }
                Text("Apps follow these unless you set their own zoom.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Behavior") {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                if LaunchAtLogin.needsApproval {
                    Text("Approve Resize in System Settings → General → Login Items.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.red)
                }
                Toggle("Apply when an app launches", isOn: Binding(
                    get: { state.config.applyOnLaunch }, set: { state.setApplyOnLaunch($0) }))
                Toggle("Pause Resize", isOn: Binding(
                    get: { state.config.paused }, set: { state.setPaused($0) }))
            }

            Section("Permissions") {
                HStack {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(state.isTrusted ? .green : .orange)
                        .font(.caption)
                    Text(state.isTrusted ? "Accessibility access granted" : "Accessibility access needed")
                    Spacer()
                    if state.isTrusted {
                        Button("Open Settings") { AccessibilityPermission.openSettings() }
                    } else {
                        Button("Grant…") { state.requestAccessibility() }
                    }
                }
                if !state.isTrusted {
                    Text("Resize presses keyboard shortcuts such as ⌘= in your apps, which needs this permission.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
                Button("Show Config File in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([state.configFileURL])
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .onAppear { state.refreshTrust() }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            launchError = nil
        } catch {
            launchError = "Couldn't change this setting. Launch at login only works from the built Resize.app."
        }
        launchAtLogin = LaunchAtLogin.isEnabled
    }
}

#Preview {
    GeneralSettingsView().environment(AppState.preview()).frame(width: 560, height: 560)
}

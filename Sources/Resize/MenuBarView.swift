import ResizeKit
import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            header
            if !state.isTrusted { accessibilityBanner }
            Divider()
            if state.rules.isEmpty {
                Text("No apps yet. Add some in Settings.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(16)
            } else {
                VStack(spacing: 2) {
                    ForEach(state.rules) { row(for: $0) }
                }
                .padding(.vertical, 6)
            }
            Divider()
            footer
        }
        .frame(width: 320)
        .onAppear { state.refreshTrust() }
    }

    private var header: some View {
        HStack {
            Label(
                state.config.paused ? "Paused" : (state.currentMode == .external ? "External monitor" : "Laptop screen"),
                systemImage: state.currentMode == .external ? "display" : "laptopcomputer")
                .font(.headline)
            Spacer()
            Toggle("Resize on", isOn: Binding(
                get: { !state.config.paused }, set: { state.setPaused(!$0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .help(state.config.paused ? "Resume Resize" : "Pause Resize")
        }
        .padding(12)
    }

    private var accessibilityBanner: some View {
        HStack {
            Label("Accessibility needed", systemImage: "exclamationmark.triangle.fill")
                .font(.callout).foregroundStyle(.orange)
            Spacer()
            Button("Grant…") { state.requestAccessibility() }.controlSize(.small)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 8)
    }

    private func row(for rule: AppRule) -> some View {
        let running = state.isRunning(rule.bundleID)
        let percent = state.percent(for: rule, mode: state.currentMode)
        return HStack(spacing: 8) {
            Button {
                state.openSettings(route: .app(rule.bundleID))
            } label: {
                HStack(spacing: 8) {
                    AppIconView(bundleID: rule.bundleID)
                    Text(rule.displayName).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { state.step(bundleID: rule.bundleID, by: -1) } label: { Image(systemName: "minus") }
                .accessibilityLabel("Zoom out \(rule.displayName)")
            Text("\(percent)%")
                .monospacedDigit()
                .frame(width: 44)
            Button { state.step(bundleID: rule.bundleID, by: 1) } label: { Image(systemName: "plus") }
                .accessibilityLabel("Zoom in \(rule.displayName)")

            statusIcon(for: rule, running: running)
                .frame(width: 16)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12).padding(.vertical, 4)
        .opacity(rule.enabled && running ? 1 : 0.5)
    }

    @ViewBuilder
    private func statusIcon(for rule: AppRule, running: Bool) -> some View {
        switch state.lastResults[rule.bundleID] {
        case .success:
            Image(systemName: "checkmark").foregroundStyle(.green).help("Applied")
        case .failed(let message):
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help(message)
        case .skipped, .none:
            if !running { Image(systemName: "moon.zzz").foregroundStyle(.secondary).help("Not running") }
        }
    }

    private var footer: some View {
        HStack {
            Button("Apply Now") { state.applyNow() }
            Spacer()
            Button("Settings…") { state.openSettings() }
            Button("Quit") { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(12)
    }
}

#Preview {
    MenuBarView().environment(AppState.preview())
}

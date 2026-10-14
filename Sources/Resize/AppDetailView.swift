import ResizeKit
import SwiftUI

struct AppDetailView: View {
    let bundleID: String
    @Environment(AppState.self) private var state
    @State private var confirmRemove = false
    @State private var showLimits = false

    var body: some View {
        if let rule = state.rule(bundleID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header(rule)
                    HStack(alignment: .top, spacing: 12) {
                        card(.laptop, rule)
                        card(.external, rule)
                    }
                    if let base = state.baseFontDefault(for: rule) { baseFontRow(rule, defaultBase: base) }
                    howItsApplied(rule)
                    Divider()
                    Button("Remove App…", role: .destructive) { confirmRemove = true }
                }
                .padding(20)
            }
            .navigationTitle(rule.displayName)
            .confirmationDialog("Remove \(rule.displayName)?", isPresented: $confirmRemove) {
                Button("Remove", role: .destructive) { state.removeApps([bundleID]) }
            } message: {
                Text("Resize will stop managing its zoom. Its current zoom stays as it is.")
            }
        } else {
            ContentUnavailableView("App not found", systemImage: "questionmark.app")
        }
    }

    private func header(_ rule: AppRule) -> some View {
        HStack(spacing: 14) {
            AppIconView(bundleID: bundleID, size: 48)
            VStack(alignment: .leading) {
                Text(rule.displayName).font(.title2.weight(.medium))
                Text(bundleID).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer()
            Toggle("Enabled", isOn: state.enabledBinding(bundleID)).toggleStyle(.switch)
            Button("Test Now") { state.testNow(bundleID: bundleID) }
                .help("Apply this app's zoom for the current display now")
        }
    }

    private func card(_ mode: DisplayMode, _ rule: AppRule) -> some View {
        ZoomCard(
            mode: mode,
            isNow: state.currentMode == mode,
            percent: Binding(
                get: { state.percent(for: rule, mode: mode) },
                set: { state.setOverride($0, for: mode, bundleID: bundleID) }),
            useDefault: Binding(
                get: { rule.override(for: mode) == nil },
                set: { state.setOverride($0 ? nil : state.defaultPercent(for: mode), for: mode, bundleID: bundleID) }),
            defaultPercent: state.defaultPercent(for: mode))
    }

    private func baseFontRow(_ rule: AppRule, defaultBase: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Base font size (= 100%)")
                TextField(
                    "Base font size",
                    value: Binding(
                        get: { rule.baseFontSize },
                        set: { state.setBaseFont($0, bundleID: bundleID) }),
                    format: .number,
                    prompt: Text("\(defaultBase.formatted())"))
                    .labelsHidden()
                    .frame(width: 70)
                Text("pt").foregroundStyle(.secondary)
            }
            Text("Your normal font size in \(rule.displayName). Leave empty to use \(defaultBase.formatted()) pt.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func howItsApplied(_ rule: AppRule) -> some View {
        let mode = state.currentMode
        let wanted = state.percent(for: rule, mode: mode)
        let reached = state.effectivePercent(for: rule, mode: mode)
        return HStack(spacing: 6) {
            Text("How it's applied").foregroundStyle(.secondary)
            Text(state.driverDescription(for: rule))
            if reached != wanted { Text("· ≈ \(reached)% reached").foregroundStyle(.secondary) }
            if let limits = state.driverLimitations(for: rule) {
                Button { showLimits = true } label: { Image(systemName: "info.circle") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("About this method")
                    .popover(isPresented: $showLimits) {
                        Text(limits).padding(14).frame(width: 240)
                    }
            }
        }
        .font(.callout)
    }
}

#Preview {
    AppDetailView(bundleID: "com.google.Chrome").environment(AppState.preview()).frame(width: 520, height: 420)
}

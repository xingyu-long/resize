import ResizeKit
import SwiftUI

extension AppState {
    /// nil = follow the default.
    func overrideBinding(_ bundleID: String, _ mode: DisplayMode) -> Binding<Int?> {
        Binding(
            get: { self.rule(bundleID)?.override(for: mode) },
            set: { self.setOverride($0, for: mode, bundleID: bundleID) })
    }

    func enabledBinding(_ bundleID: String) -> Binding<Bool> {
        Binding(
            get: { self.rule(bundleID)?.enabled ?? false },
            set: { self.setEnabled($0, bundleID: bundleID) })
    }

    func defaultBinding(_ mode: DisplayMode) -> Binding<Int> {
        Binding(get: { self.defaultPercent(for: mode) }, set: { self.setDefault($0, for: mode) })
    }

    /// Short status for the apps table.
    func statusText(for rule: AppRule) -> (text: String, symbol: String, color: Color) {
        if !rule.enabled { return ("Off", "pause.circle", .secondary) }
        switch lastResults[rule.bundleID] {
        case .success: return ("Applied", "checkmark.circle.fill", .green)
        case .failed(let message): return (message, "exclamationmark.triangle.fill", .orange)
        case .skipped, .none:
            return isRunning(rule.bundleID) ? ("Waiting", "clock", .secondary) : ("Not running", "moon.zzz", .secondary)
        }
    }
}

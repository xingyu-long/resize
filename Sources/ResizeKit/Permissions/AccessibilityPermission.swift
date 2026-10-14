import AppKit
import ApplicationServices

/// Accessibility (AX) trust is required to post keyboard events to other apps.
/// macOS sends no notification when it changes, so callers poll `isTrusted` while a banner is visible.
public enum AccessibilityPermission {
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that leads the user to the Accessibility pane.
    @discardableResult
    public static func request() -> Bool {
        // The string value of kAXTrustedCheckOptionPrompt; the constant itself isn't concurrency-safe.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

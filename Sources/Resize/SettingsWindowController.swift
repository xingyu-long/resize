import AppKit
import SwiftUI

/// Owns the settings window. Created lazily and reused, so the window never appears at login
/// and works the same on macOS 14 and later.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(state: AppState) {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            window.title = "Resize Settings"
            window.contentViewController = NSHostingController(rootView: SettingsView().environment(state))
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("ResizeSettings")
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

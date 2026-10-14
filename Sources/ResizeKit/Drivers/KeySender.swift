import CoreGraphics
import Foundation

@MainActor
public protocol KeySending {
    func send(_ combo: KeyCombo, times: Int) async
}

/// Posts real key events to the system. Needs Accessibility permission.
///
/// Events go to the HID tap, so the target app must be frontmost. `CGEvent.postToPid` is unreliable
/// for menu key equivalents in many apps (Chromium especially).
@MainActor
public struct CGEventKeySender: KeySending {
    public init() {}

    public func send(_ combo: KeyCombo, times: Int) async {
        guard times > 0 else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        for _ in 0..<times {
            for keyDown in [true, false] {
                guard let event = CGEvent(
                    keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: keyDown) else { continue }
                event.flags = combo.flags
                event.post(tap: .cghidEventTap)
            }
            // Some apps drop key events sent faster than this.
            try? await Task.sleep(for: .milliseconds(40))
        }
    }
}

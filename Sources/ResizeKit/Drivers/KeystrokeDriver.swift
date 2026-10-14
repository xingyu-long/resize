import AppKit

/// Universal fallback: brings the app to the front, resets its zoom with ⌘0, then presses ⌘= / ⌘-.
///
/// Limitation: the zoom applies to the focused window/tab only (browsers also zoom per site).
/// The browser extension driver (Phase 4) removes that limitation.
@MainActor
public final class KeystrokeDriver: ZoomDriver {
    public struct Timing: Sendable {
        public var focusPollInterval: Duration = .milliseconds(50)
        public var focusTimeout: Duration = .milliseconds(1500)
        public var settleAfterFocus: Duration = .milliseconds(150)
        public var afterReset: Duration = .milliseconds(100)

        public static let standard = Timing()
        public static let instant = Timing(
            focusPollInterval: .zero, focusTimeout: .zero, settleAfterFocus: .zero, afterReset: .zero)
    }

    public let method = DriverMethod.keystroke
    public let requiresFocus = true

    private let sender: KeySending
    private let isTrusted: @MainActor () -> Bool
    private let focus: @MainActor (pid_t) async throws -> Void
    private let timing: Timing

    public init(
        sender: KeySending? = nil,
        isTrusted: @escaping @MainActor () -> Bool = { AccessibilityPermission.isTrusted },
        timing: Timing = .standard,
        focus: (@MainActor (pid_t) async throws -> Void)? = nil
    ) {
        self.sender = sender ?? CGEventKeySender()
        self.isTrusted = isTrusted
        self.timing = timing
        self.focus = focus ?? { pid in
            guard let app = NSRunningApplication(processIdentifier: pid) else { throw ZoomError.notRunning }
            app.activate()
            // Poll until the app is actually frontmost; keys sent earlier would go to the wrong app.
            var waited = Duration.zero
            while NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
                if waited >= timing.focusTimeout { throw ZoomError.couldNotFocus }
                try await Task.sleep(for: timing.focusPollInterval)
                waited += timing.focusPollInterval
            }
        }
    }

    public func supports(bundleID: String) -> Bool { true }

    public func status(for rule: AppRule) -> DriverStatus {
        isTrusted() ? .ready : .needsSetup("Grant Accessibility access to let Resize press keyboard shortcuts.")
    }

    public func describe(for rule: AppRule) -> String {
        KeystrokeProfiles.isKnown(rule.bundleID)
            ? "Approximate (keystrokes)"
            : "Generic (keystrokes, assumes Chrome-like steps)"
    }

    public func effectivePercent(for rule: AppRule, requested: Int) -> Int {
        KeystrokeProfile.effectivePercent(
            for: requested, scale: KeystrokeProfiles.profile(for: rule.bundleID).scale,
            baseFontSize: rule.baseFontSize)
    }

    public func limitations(for rule: AppRule) -> String? {
        "Brings the app to the front briefly and changes the zoom of its focused window or tab only."
    }

    public func apply(_ ctx: ZoomContext) async throws {
        guard isTrusted() else { throw ZoomError.notTrusted }
        let profile = KeystrokeProfiles.profile(for: ctx.bundleID)
        try await focus(ctx.pid)
        try await Task.sleep(for: timing.settleAfterFocus)
        await sender.send(profile.reset, times: 1)
        try await Task.sleep(for: timing.afterReset)
        let n = KeystrokeProfile.presses(
            for: ctx.percent, scale: profile.scale, baseFontSize: ctx.rule.baseFontSize)
        if n > 0 {
            await sender.send(profile.zoomIn, times: n)
        } else if n < 0 {
            await sender.send(profile.zoomOut, times: -n)
        }
    }
}

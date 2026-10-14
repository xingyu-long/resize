import Foundation

public enum DriverMethod: String, Sendable { case direct, configReload, keystroke }

public enum DriverStatus: Equatable, Sendable {
    case ready
    case needsSetup(String)      // human-readable instructions
    case unavailable(String)
}

public enum ZoomError: Error, Equatable, LocalizedError {
    case notRunning
    case notTrusted
    case couldNotFocus

    public var errorDescription: String? {
        switch self {
        case .notRunning: "App isn't running."
        case .notTrusted: "Accessibility access is needed."
        case .couldNotFocus: "Couldn't bring the app to the front."
        }
    }
}

/// What a driver needs to zoom one app. Carries the pid rather than an `NSRunningApplication`
/// so tests can build one; drivers look up the running app themselves.
public struct ZoomContext: Sendable {
    public let rule: AppRule
    public let percent: Int
    public let pid: pid_t
    public var bundleID: String { rule.bundleID }

    public init(rule: AppRule, percent: Int, pid: pid_t) {
        self.rule = rule
        self.percent = percent
        self.pid = pid
    }
}

@MainActor
public protocol ZoomDriver {
    var method: DriverMethod { get }
    /// Whether this driver handles the bundle ID. The fallback driver returns true for everything.
    func supports(bundleID: String) -> Bool
    func status(for rule: AppRule) -> DriverStatus
    /// true if apply() must bring the app to the front (callers serialize these).
    var requiresFocus: Bool { get }
    func apply(_ ctx: ZoomContext) async throws
    /// Short label for the UI, e.g. "Approximate (keystrokes)".
    func describe(for rule: AppRule) -> String
    /// The percent the driver will actually reach for a requested percent, shown as "≈ N%".
    func effectivePercent(for rule: AppRule, requested: Int) -> Int
    /// Limitations worth surfacing in the UI's ⓘ popover.
    func limitations(for rule: AppRule) -> String?
}

public extension ZoomDriver {
    func effectivePercent(for rule: AppRule, requested: Int) -> Int { requested }
    func limitations(for rule: AppRule) -> String? { nil }
}

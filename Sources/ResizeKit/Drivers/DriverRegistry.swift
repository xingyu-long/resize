import Foundation

@MainActor
public final class DriverRegistry {
    private let drivers: [ZoomDriver]

    /// `drivers` are tried in order; `fallback` (the keystroke driver) is always last and supports everything.
    /// Adding a more exact driver is one entry in `drivers`.
    public init(drivers: [ZoomDriver] = [], fallback: ZoomDriver? = nil) {
        self.drivers = drivers + [fallback ?? KeystrokeDriver()]
    }

    /// The first driver that supports the app and is ready; otherwise the first that supports it,
    /// so the UI can show its setup instructions.
    public func driver(for rule: AppRule) -> ZoomDriver {
        let candidates = drivers.filter { $0.supports(bundleID: rule.bundleID) }
        return candidates.first { $0.status(for: rule) == .ready }
            ?? candidates.first
            ?? drivers[drivers.count - 1]
    }
}

import Foundation

public struct AppConfig: Codable, Equatable, Sendable {
    public static let allowedPercents: ClosedRange<Int> = 25...500
    /// Presets offered in pickers and used by the menu bar −/+ buttons.
    public static let presetPercents = [50, 67, 75, 80, 90, 100, 110, 125, 150, 175, 200]

    public var version: Int
    /// Global defaults. Every app follows these unless it has its own override.
    public var defaultPercents: [DisplayMode: Int]
    public var rules: [AppRule]
    public var hasCompletedOnboarding: Bool
    /// Master on/off switch from the menu bar.
    public var paused: Bool
    public var applyOnLaunch: Bool
    public var displayChangeDebounceSeconds: Double
    public var launchApplyDelaySeconds: Double

    public init(
        version: Int = 1,
        defaultPercents: [DisplayMode: Int] = [.laptop: 100, .external: 125],
        rules: [AppRule] = [],
        hasCompletedOnboarding: Bool = false,
        paused: Bool = false,
        applyOnLaunch: Bool = true,
        displayChangeDebounceSeconds: Double = 1.5,
        launchApplyDelaySeconds: Double = 2.0
    ) {
        self.version = version
        self.defaultPercents = defaultPercents
        self.rules = rules
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.paused = paused
        self.applyOnLaunch = applyOnLaunch
        self.displayChangeDebounceSeconds = displayChangeDebounceSeconds
        self.launchApplyDelaySeconds = launchApplyDelaySeconds
    }

    public static func clamp(_ percent: Int) -> Int {
        min(max(percent, allowedPercents.lowerBound), allowedPercents.upperBound)
    }

    public func percent(for rule: AppRule, mode: DisplayMode) -> Int {
        rule.percent(for: mode, defaults: defaultPercents)
    }

    public func rule(for bundleID: String) -> AppRule? {
        rules.first { $0.bundleID == bundleID }
    }

    // Every key falls back to its default so older config files keep loading.
    public init(from decoder: Decoder) throws {
        let d = AppConfig()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? d.version
        var defaults = d.defaultPercents
        if let stored = try c.decodeIfPresent([DisplayMode: Int].self, forKey: .defaultPercents) {
            defaults.merge(stored) { _, new in new }
        }
        defaultPercents = defaults
        rules = try c.decodeIfPresent([AppRule].self, forKey: .rules) ?? d.rules
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? d.hasCompletedOnboarding
        paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? d.paused
        applyOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .applyOnLaunch) ?? d.applyOnLaunch
        displayChangeDebounceSeconds = try c.decodeIfPresent(Double.self, forKey: .displayChangeDebounceSeconds) ?? d.displayChangeDebounceSeconds
        launchApplyDelaySeconds = try c.decodeIfPresent(Double.self, forKey: .launchApplyDelaySeconds) ?? d.launchApplyDelaySeconds
    }
}

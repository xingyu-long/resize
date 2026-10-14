import Foundation

public struct AppRule: Codable, Identifiable, Hashable, Sendable {
    public var id: String { bundleID }
    public var bundleID: String
    public var displayName: String
    public var enabled: Bool
    /// nil = follow the global default for that mode (`AppConfig.defaultPercents`).
    public var laptopPercent: Int?
    public var externalPercent: Int?
    /// For point-based apps (terminals): the font size that equals 100%.
    /// nil = use the `KeystrokeProfile` default.
    public var baseFontSize: Double?

    public init(
        bundleID: String,
        displayName: String,
        enabled: Bool = true,
        laptopPercent: Int? = nil,
        externalPercent: Int? = nil,
        baseFontSize: Double? = nil
    ) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.enabled = enabled
        self.laptopPercent = laptopPercent
        self.externalPercent = externalPercent
        self.baseFontSize = baseFontSize
    }

    /// The override for `mode`, or nil when the app follows the default.
    public func override(for mode: DisplayMode) -> Int? {
        mode == .laptop ? laptopPercent : externalPercent
    }

    public mutating func setOverride(_ percent: Int?, for mode: DisplayMode) {
        if mode == .laptop { laptopPercent = percent } else { externalPercent = percent }
    }

    public func percent(for mode: DisplayMode, defaults: [DisplayMode: Int]) -> Int {
        override(for: mode) ?? defaults[mode] ?? 100
    }

    private enum CodingKeys: String, CodingKey {
        case bundleID, displayName, enabled, laptopPercent, externalPercent, baseFontSize
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try c.decode(String.self, forKey: .bundleID)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? bundleID
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        laptopPercent = try c.decodeIfPresent(Int.self, forKey: .laptopPercent)
        externalPercent = try c.decodeIfPresent(Int.self, forKey: .externalPercent)
        baseFontSize = try c.decodeIfPresent(Double.self, forKey: .baseFontSize)
    }
}

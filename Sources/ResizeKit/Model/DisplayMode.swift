import Foundation

/// Which display setup is active. Only two profiles exist: any external display means `.external`.
public enum DisplayMode: String, Codable, CaseIterable, Sendable {
    case laptop, external
}

private struct DisplayModeKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// Makes `[DisplayMode: Int]` encode as a JSON object (`{"laptop":100}`) rather than a flat array.
extension DisplayMode: CodingKeyRepresentable {
    public var codingKey: CodingKey { DisplayModeKey(stringValue: rawValue) }

    public init?<T: CodingKey>(codingKey: T) {
        self.init(rawValue: codingKey.stringValue)
    }
}

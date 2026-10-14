import XCTest
@testable import ResizeKit

final class AppConfigCodingTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("config.json")
    }

    func testRoundTrip() throws {
        var config = AppConfig()
        config.rules = [AppRule(bundleID: "com.google.Chrome", displayName: "Chrome", externalPercent: 150)]
        config.paused = true
        let decoded = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded, config)
    }

    func testDefaultPercentsEncodeAsObject() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = try String(decoding: encoder.encode(AppConfig()), as: UTF8.self)
        XCTAssertTrue(json.contains(#""defaultPercents":{"external":125,"laptop":100}"#), json)
    }

    func testMissingKeysFallBackToDefaults() throws {
        let decoded = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, AppConfig())
        let partial = try JSONDecoder().decode(
            AppConfig.self, from: Data(#"{"defaultPercents":{"external":150}}"#.utf8))
        XCTAssertEqual(partial.defaultPercents, [.laptop: 100, .external: 150])
    }

    func testRuleDefaultsAndOverrides() {
        let rule = AppRule(bundleID: "a", displayName: "A", externalPercent: 150)
        let defaults: [DisplayMode: Int] = [.laptop: 100, .external: 125]
        XCTAssertEqual(rule.percent(for: .laptop, defaults: defaults), 100)
        XCTAssertEqual(rule.percent(for: .external, defaults: defaults), 150)
    }

    func testClamp() {
        XCTAssertEqual(AppConfig.clamp(10), 25)
        XCTAssertEqual(AppConfig.clamp(900), 500)
        XCTAssertEqual(AppConfig.clamp(125), 125)
    }

    func testStoreSaveAndLoad() {
        let store = ConfigStore(url: tempURL())
        var config = AppConfig()
        config.defaultPercents[.external] = 140
        store.save(config)
        XCTAssertEqual(store.load(), config)
    }

    func testStoreMissingFileGivesDefaults() {
        XCTAssertEqual(ConfigStore(url: tempURL()).load(), AppConfig())
    }

    func testStoreCorruptFileGivesDefaults() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        XCTAssertEqual(ConfigStore(url: url).load(), AppConfig())
    }
}

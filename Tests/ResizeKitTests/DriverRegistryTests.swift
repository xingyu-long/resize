import XCTest
@testable import ResizeKit

@MainActor
final class DriverRegistryTests: XCTestCase {
    private let rule = AppRule(bundleID: "com.example.app", displayName: "App")

    func testFallbackIsUsedWhenNothingElseSupportsTheApp() {
        let fallback = FakeDriver()
        let special = FakeDriver()
        special.supported = { _ in false }
        let registry = DriverRegistry(drivers: [special], fallback: fallback)
        XCTAssertTrue(registry.driver(for: rule) as AnyObject === fallback)
    }

    func testReadyDriverBeatsEarlierDriverThatNeedsSetup() {
        let needsSetup = FakeDriver()
        needsSetup.statusValue = .needsSetup("install the extension")
        let fallback = FakeDriver()
        let registry = DriverRegistry(drivers: [needsSetup], fallback: fallback)
        XCTAssertTrue(registry.driver(for: rule) as AnyObject === fallback)
    }

    func testFirstSupportingDriverIsReturnedWhenNoneIsReady() {
        let first = FakeDriver()
        first.statusValue = .needsSetup("setup")
        let fallback = FakeDriver()
        fallback.statusValue = .unavailable("nope")
        let registry = DriverRegistry(drivers: [first], fallback: fallback)
        XCTAssertTrue(registry.driver(for: rule) as AnyObject === first)
    }

    func testDefaultFallbackIsKeystrokeDriver() {
        XCTAssertEqual(DriverRegistry().driver(for: rule).method, .keystroke)
    }
}

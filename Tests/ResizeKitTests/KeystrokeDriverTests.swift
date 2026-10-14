import XCTest
@testable import ResizeKit

@MainActor
final class KeystrokeDriverTests: XCTestCase {
    private func makeDriver(sender: RecordingKeySender, trusted: Bool = true) -> KeystrokeDriver {
        KeystrokeDriver(sender: sender, isTrusted: { trusted }, timing: .instant, focus: { _ in })
    }

    private func context(_ bundleID: String, percent: Int, base: Double? = nil) -> ZoomContext {
        ZoomContext(rule: AppRule(bundleID: bundleID, displayName: "x", baseFontSize: base), percent: percent, pid: 1)
    }

    func testResetThenZoomIn() async throws {
        let sender = RecordingKeySender()
        try await makeDriver(sender: sender).apply(context("com.google.Chrome", percent: 125))
        XCTAssertEqual(sender.sent.map(\.combo), [.cmd0, .cmdEqual])
        XCTAssertEqual(sender.sent.map(\.times), [1, 2])
    }

    func testZoomOutForTerminalPoints() async throws {
        let sender = RecordingKeySender()
        try await makeDriver(sender: sender).apply(context("com.apple.Terminal", percent: 75))
        XCTAssertEqual(sender.sent.map(\.combo), [.cmd0, .cmdMinus])
        XCTAssertEqual(sender.sent.map(\.times), [1, 3])
    }

    func testOnly100PercentJustResets() async throws {
        let sender = RecordingKeySender()
        try await makeDriver(sender: sender).apply(context("com.google.Chrome", percent: 100))
        XCTAssertEqual(sender.sent.map(\.combo), [.cmd0])
    }

    func testUnknownAppUsesChromiumSteps() async throws {
        let sender = RecordingKeySender()
        try await makeDriver(sender: sender).apply(context("com.example.unknown", percent: 110))
        XCTAssertEqual(sender.sent.map(\.times), [1, 1])
    }

    func testNotTrustedThrowsAndSendsNothing() async {
        let sender = RecordingKeySender()
        let driver = makeDriver(sender: sender, trusted: false)
        do {
            try await driver.apply(context("com.google.Chrome", percent: 125))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ZoomError, .notTrusted)
        }
        XCTAssertTrue(sender.sent.isEmpty)
        if case .needsSetup = driver.status(for: AppRule(bundleID: "x", displayName: "x")) {} else { XCTFail() }
    }

    func testFocusFailurePropagates() async {
        let sender = RecordingKeySender()
        let driver = KeystrokeDriver(
            sender: sender, isTrusted: { true }, timing: .instant, focus: { _ in throw ZoomError.couldNotFocus })
        do {
            try await driver.apply(context("com.google.Chrome", percent: 125))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ZoomError, .couldNotFocus)
        }
        XCTAssertTrue(sender.sent.isEmpty)
    }

    func testDescribe() {
        let driver = makeDriver(sender: RecordingKeySender())
        XCTAssertEqual(driver.describe(for: AppRule(bundleID: "com.google.Chrome", displayName: "")), "Approximate (keystrokes)")
        XCTAssertTrue(driver.describe(for: AppRule(bundleID: "x.y", displayName: "")).hasPrefix("Generic"))
    }
}

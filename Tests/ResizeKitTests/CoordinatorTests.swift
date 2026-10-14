import XCTest
@testable import ResizeKit

@MainActor
final class CoordinatorTests: XCTestCase {
    private var config = AppConfig(rules: [
        AppRule(bundleID: "a", displayName: "A"),
        AppRule(bundleID: "b", displayName: "B", externalPercent: 150),
    ])
    private var running: Set<String> = ["a", "b"]
    private var locked = false
    private var driver = FakeDriver()
    private var mode = DisplayMode.external

    private func makeCoordinator() -> ZoomCoordinator {
        config.launchApplyDelaySeconds = 0
        return ZoomCoordinator(
            config: { [unowned self] in config },
            registry: DriverRegistry(drivers: [], fallback: driver),
            currentMode: { [unowned self] in mode },
            runningPID: { [unowned self] in running.contains($0) ? 1 : nil },
            frontmostPID: { nil },
            activate: { _ in },
            isScreenLocked: { [unowned self] in locked })
    }

    func testAppliesResolvedPercentPerRule() async {
        let c = makeCoordinator()
        await c.applyAll(mode: .external)
        XCTAssertEqual(driver.applied.map(\.bundleID), ["a", "b"])
        XCTAssertEqual(driver.applied.map(\.percent), [125, 150]) // default, override
        XCTAssertEqual(c.lastResults["a"], .success(percentReached: 125))
    }

    func testSkipsWhenUnchangedAndForceReapplies() async {
        let c = makeCoordinator()
        await c.applyAll(mode: .external)
        await c.applyAll(mode: .external)
        XCTAssertEqual(driver.applied.count, 2)
        await c.applyAll(mode: .external, force: true)
        XCTAssertEqual(driver.applied.count, 4)
    }

    func testModeChangeReapplies() async {
        let c = makeCoordinator()
        await c.applyAll(mode: .external)
        await c.applyAll(mode: .laptop)
        XCTAssertEqual(driver.applied.suffix(2).map(\.percent), [100, 100])
    }

    func testAppsWithSamePercentInBothModesAreNotReappliedAcrossModesUnlessDifferent() async {
        config.defaultPercents = [.laptop: 100, .external: 100]
        config.rules = [AppRule(bundleID: "a", displayName: "A")]
        let c = makeCoordinator()
        await c.applyAll(mode: .external)
        await c.applyAll(mode: .laptop) // same resolved percent, but a different mode
        XCTAssertEqual(driver.applied.count, 2)
    }

    func testDisabledRulesAreIgnored() async {
        config.rules[0].enabled = false
        let c = makeCoordinator()
        await c.applyAll(mode: .external)
        XCTAssertEqual(driver.applied.map(\.bundleID), ["b"])
    }

    func testNotRunningIsSkipped() async {
        running = ["b"]
        let c = makeCoordinator()
        await c.applyAll(mode: .external)
        XCTAssertEqual(driver.applied.map(\.bundleID), ["b"])
        XCTAssertEqual(c.lastResults["a"], .skipped("Not running"))
    }

    func testTerminatedAppIsReappliedOnNextLaunch() async {
        let c = makeCoordinator()
        await c.applyAll(mode: .external)
        c.appTerminated(bundleID: "a")
        await c.applyAll(mode: .external)
        XCTAssertEqual(driver.applied.map(\.bundleID), ["a", "b", "a"])
    }

    func testPausedIsANoOp() async {
        config.paused = true
        let c = makeCoordinator()
        await c.applyAll(mode: .external, force: true)
        await c.ruleChanged(bundleID: "a")
        XCTAssertTrue(driver.applied.isEmpty)
    }

    func testFailureIsRecordedAndDoesNotStopOtherApps() async {
        driver.error = ZoomError.couldNotFocus
        let c = makeCoordinator()
        await c.applyAll(mode: .external)
        XCTAssertEqual(driver.applied.count, 2)
        XCTAssertEqual(c.lastResults["a"], .failed(ZoomError.couldNotFocus.localizedDescription))
        // A failed apply isn't remembered, so the next pass retries.
        driver.error = nil
        await c.applyAll(mode: .external)
        XCTAssertEqual(driver.applied.count, 4)
    }

    func testDriverNeedingSetupReportsFailureWithoutApplying() async {
        driver.statusValue = .needsSetup("Grant access")
        let c = makeCoordinator()
        await c.applyAll(mode: .external)
        XCTAssertTrue(driver.applied.isEmpty)
        XCTAssertEqual(c.lastResults["a"], .failed("Grant access"))
    }

    func testLockedScreenDefersUntilUnlock() async {
        locked = true
        let c = makeCoordinator()
        await c.applyAll(mode: .external)
        XCTAssertTrue(driver.applied.isEmpty)
        locked = false
        await c.screenUnlocked()
        XCTAssertEqual(driver.applied.count, 2)
    }

    func testOverlappingRequestsAreCoalesced() async {
        let c = makeCoordinator()
        var first = true
        driver.onApply = { _ in
            guard first else { return }
            first = false
            // Requests arriving mid-run merge into one extra pass instead of starting their own run.
            await c.applyAll(mode: .external, force: true)
            await c.applyAll(mode: .external, force: true)
        }
        config.rules = [AppRule(bundleID: "a", displayName: "A")]
        await c.applyAll(mode: .external)
        XCTAssertEqual(driver.applied.count, 2) // the original apply plus a single coalesced forced pass
    }

    func testRuleChangedAppliesImmediatelyEvenIfUnchanged() async {
        let c = makeCoordinator()
        await c.applyAll(mode: .external)
        await c.ruleChanged(bundleID: "a")
        XCTAssertEqual(driver.applied.map(\.bundleID), ["a", "b", "a"])
    }

    func testAppLaunchedAppliesOnlyForManagedApps() async {
        let c = makeCoordinator()
        await c.appLaunched(bundleID: "a")
        await c.appLaunched(bundleID: "unmanaged")
        XCTAssertEqual(driver.applied.map(\.bundleID), ["a"])
        config.applyOnLaunch = false
        await c.appLaunched(bundleID: "b")
        XCTAssertEqual(driver.applied.count, 1)
    }
}

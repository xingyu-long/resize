import XCTest
@testable import ResizeKit

final class KeystrokeMathTests: XCTestCase {
    private let chromium = ZoomScale.steps(KeystrokeProfiles.chromiumSteps)

    private func presses(_ percent: Int, _ scale: ZoomScale? = nil, base: Double? = nil) -> Int {
        KeystrokeProfile.presses(for: percent, scale: scale ?? chromium, baseFontSize: base)
    }

    func testChromiumSteps() {
        XCTAssertEqual(presses(100), 0)
        XCTAssertEqual(presses(110), 1)
        XCTAssertEqual(presses(125), 2)
        XCTAssertEqual(presses(150), 3)
        XCTAssertEqual(presses(90), -1)
        // 100 → 90 → 80 → 75 → 67 is four presses.
        XCTAssertEqual(presses(67), -4)
    }

    func testNearestLevelWins() {
        XCTAssertEqual(presses(120), 2) // 125 is closer than 110
    }

    func testTieGoesToLargerLevel() {
        // A synthetic scale gives a true tie, which the larger level wins.
        let scale = ZoomScale.steps([50, 100, 150])
        XCTAssertEqual(presses(125, scale), 1) // tie between 100 and 150 → 150
        XCTAssertEqual(presses(75, scale), 0)  // tie between 50 and 100 → 100
    }

    func testClampedToEnds() {
        XCTAssertEqual(presses(1000), 9)  // index of 500 (16) minus index of 100 (7)
        XCTAssertEqual(presses(1), -7)    // index of 25 (0) minus 7
    }

    func testPoints() {
        let scale = ZoomScale.points(defaultBase: 12, pointsPerStep: 1)
        XCTAssertEqual(presses(125, scale), 3)  // 15pt
        XCTAssertEqual(presses(100, scale), 0)
        XCTAssertEqual(presses(75, scale), -3)  // 9pt
    }

    func testPointsUseCustomBaseFontSize() {
        let scale = ZoomScale.points(defaultBase: 12, pointsPerStep: 1)
        XCTAssertEqual(presses(150, scale, base: 14), 7) // 21pt - 14pt
    }

    func testEffectivePercent() {
        XCTAssertEqual(KeystrokeProfile.effectivePercent(for: 120, scale: chromium, baseFontSize: nil), 125)
        let points = ZoomScale.points(defaultBase: 12, pointsPerStep: 1)
        XCTAssertEqual(KeystrokeProfile.effectivePercent(for: 125, scale: points, baseFontSize: nil), 125)
        XCTAssertEqual(KeystrokeProfile.effectivePercent(for: 110, scale: points, baseFontSize: nil), 108) // 13pt / 12pt
    }

    func testEveryStepTableContains100() {
        for steps in [KeystrokeProfiles.chromiumSteps, KeystrokeProfiles.firefoxSteps, KeystrokeProfiles.safariSteps] {
            XCTAssertTrue(steps.contains(100))
            XCTAssertEqual(steps, steps.sorted())
        }
    }

    func testEveryKnownAppHasAProfile() {
        for app in KeystrokeProfiles.knownApps {
            XCTAssertTrue(KeystrokeProfiles.isKnown(app.bundleID), app.name)
        }
    }
}

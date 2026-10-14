import XCTest
@testable import ResizeKit

final class DisplayModeTests: XCTestCase {
    private let builtin = DisplayInfo(isBuiltin: true, isActive: true, isInMirrorSet: false)

    func testBuiltInOnlyIsLaptop() {
        XCTAssertEqual(DisplayMonitor.mode(for: [builtin]), .laptop)
        XCTAssertEqual(DisplayMonitor.mode(for: []), .laptop)
    }

    func testExternalAddedIsExternal() {
        let external = DisplayInfo(isBuiltin: false, isActive: true, isInMirrorSet: false)
        XCTAssertEqual(DisplayMonitor.mode(for: [builtin, external]), .external)
    }

    func testClamshellOnlyExternalIsExternal() {
        let external = DisplayInfo(isBuiltin: false, isActive: true, isInMirrorSet: false)
        XCTAssertEqual(DisplayMonitor.mode(for: [external]), .external)
    }

    func testMirroredExternalStillCountsAsExternal() {
        let mirrored = DisplayInfo(isBuiltin: false, isActive: false, isInMirrorSet: true)
        XCTAssertEqual(DisplayMonitor.mode(for: [builtin, mirrored]), .external)
    }

    func testInactiveUnmirroredExternalIsIgnored() {
        let gone = DisplayInfo(isBuiltin: false, isActive: false, isInMirrorSet: false)
        XCTAssertEqual(DisplayMonitor.mode(for: [builtin, gone]), .laptop)
    }
}

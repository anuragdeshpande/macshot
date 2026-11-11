import Cocoa
import XCTest

final class CrossDisplayDragRoutingTests: XCTestCase {
    func testMapsDragPointBetweenSideBySideOverlayWindows() {
        let point = CrossDisplayDragRouting.pointInTargetWindow(
            NSPoint(x: 24, y: 80),
            sourceWindowFrame: NSRect(x: 2560, y: 0, width: 2560, height: 1440),
            targetWindowFrame: NSRect(x: 0, y: 0, width: 2560, height: 1440))

        XCTAssertEqual(point, NSPoint(x: 2584, y: 80))
    }

    func testMapsDragPointBetweenVerticallyStackedOverlayWindows() {
        let point = CrossDisplayDragRouting.pointInTargetWindow(
            NSPoint(x: 140, y: 30),
            sourceWindowFrame: NSRect(x: 0, y: 900, width: 1600, height: 900),
            targetWindowFrame: NSRect(x: 0, y: 0, width: 1600, height: 900))

        XCTAssertEqual(point, NSPoint(x: 140, y: 930))
    }

    func testPreservesNegativeOriginsInAsymmetricDisplayLayouts() {
        let point = CrossDisplayDragRouting.pointInTargetWindow(
            NSPoint(x: 40, y: 60),
            sourceWindowFrame: NSRect(x: -1200, y: -300, width: 1200, height: 800),
            targetWindowFrame: NSRect(x: 0, y: 0, width: 1920, height: 1080))

        XCTAssertEqual(point, NSPoint(x: -1160, y: -240))
    }
}

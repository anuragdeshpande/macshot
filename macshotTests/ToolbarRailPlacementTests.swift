import AppKit
import XCTest

final class ToolbarRailPlacementTests: XCTestCase {

    func testAnnotationOptionsAndActionsSitOnTheirRespectiveSides() {
        let selection = NSRect(x: 400, y: 300, width: 200, height: 120)
        let bounds = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let frames = ToolbarRailFrames.place(
            around: selection,
            inside: bounds,
            annotationSize: NSSize(width: 40, height: 500),
            optionsSize: NSSize(width: 180, height: 220),
            actionSize: NSSize(width: 40, height: 500))

        XCTAssertLessThan(frames.options.maxX, frames.annotations.minX)
        XCTAssertLessThan(frames.annotations.maxX, selection.minX)
        XCTAssertGreaterThan(frames.actions.minX, selection.maxX)
        XCTAssertTrue(bounds.contains(frames.options))
        XCTAssertTrue(bounds.contains(frames.annotations))
        XCTAssertTrue(bounds.contains(frames.actions))
    }

    func testNarrowLeftMarginDoesNotOverlapTheOptionsAndAnnotationRails() {
        let bounds = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let frames = ToolbarRailFrames.place(
            around: NSRect(x: 10, y: 300, width: 200, height: 120),
            inside: bounds,
            annotationSize: NSSize(width: 40, height: 500),
            optionsSize: NSSize(width: 180, height: 220),
            actionSize: NSSize(width: 40, height: 500))

        XCTAssertLessThanOrEqual(frames.options.maxX, frames.annotations.minX)
        XCTAssertTrue(bounds.contains(frames.options))
        XCTAssertTrue(bounds.contains(frames.annotations))
    }
}

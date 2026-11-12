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

    func testDisplayAwarePlacementUsesSideBySideDisplaysInPositiveCoordinates() {
        assertSideBySidePlacement(
            selection: NSRect(x: 500, y: 300, width: 200, height: 120),
            leftDisplay: NSRect(x: 0, y: 0, width: 600, height: 800),
            rightDisplay: NSRect(x: 600, y: 0, width: 600, height: 800))
    }

    func testDisplayAwarePlacementUsesSideBySideDisplaysInNegativeCoordinates() {
        assertSideBySidePlacement(
            selection: NSRect(x: -700, y: -120, width: 200, height: 120),
            leftDisplay: NSRect(x: -1200, y: -200, width: 600, height: 800),
            rightDisplay: NSRect(x: -600, y: -200, width: 600, height: 800))
    }

    func testDisplayAwarePlacementUsesLeftNeighborWhenOriginDisplayCannotFitRailsOutsideSelection() {
        let leftDisplay = NSRect(x: 0, y: 0, width: 600, height: 800)
        let originDisplay = NSRect(x: 600, y: 0, width: 600, height: 800)
        let selection = NSRect(x: 608, y: 300, width: 220, height: 120)
        let frames = ToolbarRailFrames.place(
            around: selection,
            on: [leftDisplay, originDisplay],
            annotationSize: NSSize(width: 40, height: 80),
            optionsSize: NSSize(width: 100, height: 50),
            actionSize: NSSize(width: 40, height: 80))

        XCTAssertTrue(leftDisplay.contains(frames.annotations))
        XCTAssertTrue(leftDisplay.contains(frames.options))
        XCTAssertLessThanOrEqual(frames.annotations.maxX, selection.minX)
        XCTAssertLessThanOrEqual(frames.options.maxX, selection.minX)
        XCTAssertTrue(originDisplay.contains(frames.actions))
        assertFrames(frames, containedIn: [leftDisplay, originDisplay])
    }

    func testDisplayAwarePlacementUsesRightNeighborWhenOriginDisplayCannotFitActionsOutsideSelection() {
        let originDisplay = NSRect(x: 0, y: 0, width: 600, height: 800)
        let rightDisplay = NSRect(x: 600, y: 0, width: 600, height: 800)
        let selection = NSRect(x: 380, y: 300, width: 212, height: 120)
        let frames = ToolbarRailFrames.place(
            around: selection,
            on: [originDisplay, rightDisplay],
            annotationSize: NSSize(width: 40, height: 80),
            optionsSize: NSSize(width: 100, height: 50),
            actionSize: NSSize(width: 40, height: 80))

        XCTAssertTrue(originDisplay.contains(frames.annotations))
        XCTAssertTrue(originDisplay.contains(frames.options))
        XCTAssertTrue(rightDisplay.contains(frames.actions))
        XCTAssertGreaterThanOrEqual(frames.actions.minX, selection.maxX)
        assertFrames(frames, containedIn: [originDisplay, rightDisplay])
    }

    func testDisplayAwarePlacementKeepsRailsOnVerticallyOffsetDisplaysAcrossGap() {
        let upperDisplay = NSRect(x: 0, y: 400, width: 500, height: 400)
        let lowerDisplay = NSRect(x: 300, y: 0, width: 500, height: 350)
        let frames = ToolbarRailFrames.place(
            around: NSRect(x: 200, y: 300, width: 450, height: 200),
            on: [upperDisplay, lowerDisplay],
            annotationSize: NSSize(width: 40, height: 80),
            optionsSize: NSSize(width: 100, height: 50),
            actionSize: NSSize(width: 40, height: 80))

        assertFrames(frames, containedIn: [upperDisplay, lowerDisplay])
        XCTAssertTrue(upperDisplay.contains(frames.annotations))
        XCTAssertTrue(upperDisplay.contains(frames.options))
        XCTAssertTrue(lowerDisplay.contains(frames.actions))
    }

    func testStackedDisplaysChooseOneTallEnoughForTheRails() {
        let smallDisplay = NSRect(x: 0, y: 400, width: 500, height: 300)
        let tallDisplay = NSRect(x: 0, y: -400, width: 500, height: 800)
        let frames = ToolbarRailFrames.place(
            around: NSRect(x: 200, y: 350, width: 150, height: 100),
            on: [smallDisplay, tallDisplay],
            annotationSize: NSSize(width: 40, height: 500),
            optionsSize: .zero,
            actionSize: NSSize(width: 40, height: 500))

        XCTAssertTrue(tallDisplay.contains(frames.annotations))
        XCTAssertTrue(tallDisplay.contains(frames.actions))
    }

    func testDisplayAwarePlacementMatchesExistingSingleScreenBehavior() {
        let selection = NSRect(x: 10, y: 300, width: 200, height: 120)
        let display = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let expected = ToolbarRailFrames.place(
            around: selection,
            inside: display,
            annotationSize: NSSize(width: 40, height: 500),
            optionsSize: NSSize(width: 180, height: 220),
            actionSize: NSSize(width: 40, height: 500))
        let actual = ToolbarRailFrames.place(
            around: selection,
            on: [display],
            annotationSize: NSSize(width: 40, height: 500),
            optionsSize: NSSize(width: 180, height: 220),
            actionSize: NSSize(width: 40, height: 500))

        XCTAssertEqual(actual.annotations, expected.annotations)
        XCTAssertEqual(actual.options, expected.options)
        XCTAssertEqual(actual.actions, expected.actions)
        assertFrames(actual, containedIn: [display])
    }

    private func assertSideBySidePlacement(selection: NSRect, leftDisplay: NSRect, rightDisplay: NSRect) {
        let frames = ToolbarRailFrames.place(
            around: selection,
            on: [leftDisplay, rightDisplay],
            annotationSize: NSSize(width: 40, height: 80),
            optionsSize: NSSize(width: 100, height: 50),
            actionSize: NSSize(width: 40, height: 80))

        XCTAssertTrue(leftDisplay.contains(frames.annotations))
        XCTAssertTrue(leftDisplay.contains(frames.options))
        XCTAssertTrue(rightDisplay.contains(frames.actions))
        assertFrames(frames, containedIn: [leftDisplay, rightDisplay])
    }

    private func assertFrames(_ frames: ToolbarRailFrames, containedIn displays: [NSRect]) {
        XCTAssertTrue(displays.contains { $0.contains(frames.annotations) })
        XCTAssertTrue(displays.contains { $0.contains(frames.options) })
        XCTAssertTrue(displays.contains { $0.contains(frames.actions) })
    }
}

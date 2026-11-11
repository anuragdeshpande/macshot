import XCTest

@MainActor
final class ToolOptionsPopoverControllerTests: XCTestCase {
    func testArrowOptionsPopoverUsesCompactNativePopoverDimensions() {
        let controller = ToolOptionsPopoverController(
            overlayView: OverlayView(),
            tool: .arrow,
            title: "Arrow")

        XCTAssertGreaterThan(controller.contentSize.width, 0)
        XCTAssertLessThanOrEqual(controller.contentSize.width, 240)
        XCTAssertGreaterThan(controller.contentSize.height, 0)
        XCTAssertLessThanOrEqual(controller.contentSize.height, 410)
    }

    func testToolsWithoutOptionsDoNotOpenAnOptionsPopover() {
        XCTAssertFalse(ToolOptionsRowView.supportsOptions(for: .select))
        XCTAssertFalse(ToolOptionsRowView.supportsOptions(for: .crop))
    }
}

import XCTest

@MainActor
final class ToolOptionsPopoverControllerTests: XCTestCase {
    private func toolbarButton(in view: OverlayView, for tool: AnnotationTool) -> ToolbarButtonView? {
        let strips = view.subviews.compactMap { $0 as? ToolbarStripView }
        return strips
            .flatMap(\.buttonViews)
            .first {
                if case .tool(let candidate) = $0.action { return candidate == tool }
                return false
            }
    }

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

    func testToolOptionsPopoverUsesTransparentOptionsLayerBackground() {
        let controller = ToolOptionsPopoverController(
            overlayView: OverlayView(),
            tool: .arrow,
            title: "Arrow")
        let row = controller.optionsRowViewForTesting

        XCTAssertTrue(row.hostedInGlassPanel)
        XCTAssertEqual(row.layer?.cornerRadius ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(row.layer?.backgroundColor?.alpha ?? 1, 0, accuracy: 0.001)
    }

    func testCaptureOptionsRailUsesRoundedRectangleRatherThanCircularChrome() {
        let row = ToolOptionsRowView(frame: NSRect(x: 0, y: 0, width: 180, height: 220))
        row.orientation = .vertical

        XCTAssertLessThanOrEqual(row.chromeCornerRadius, 12)
    }

    func testClickingAnInactiveCaptureToolSelectsItThroughItsToolbarButton() {
        let view = OverlayView()
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        view.currentTool = .select
        view.applySelection(NSRect(x: 100, y: 100, width: 300, height: 200))

        guard let arrowButton = toolbarButton(in: view, for: .arrow) else {
            XCTFail("Expected the capture toolbar to contain the arrow tool")
            return
        }
        arrowButton.onClick?(.tool(.arrow))

        XCTAssertEqual(view.currentTool, .arrow)
    }

    func testCaptureInlineOptionsRowRemainsAvailableForBeautifyAndAnnotationEditing() {
        XCTAssertFalse(ToolOptionsRowView.shouldShowInlineOptionsRow(
            inEditorMode: false,
            showBeautifyOptions: false,
            editingAnnotation: false))
        XCTAssertTrue(ToolOptionsRowView.shouldShowInlineOptionsRow(
            inEditorMode: false,
            showBeautifyOptions: true,
            editingAnnotation: false))
        XCTAssertTrue(ToolOptionsRowView.shouldShowInlineOptionsRow(
            inEditorMode: false,
            showBeautifyOptions: false,
            editingAnnotation: true))
        XCTAssertTrue(ToolOptionsRowView.shouldShowInlineOptionsRow(
            inEditorMode: true,
            showBeautifyOptions: false,
            editingAnnotation: false))
    }

    func testToolsWithoutOptionsDoNotOpenAnOptionsPopover() {
        XCTAssertFalse(ToolOptionsRowView.supportsOptions(for: .select))
        XCTAssertFalse(ToolOptionsRowView.supportsOptions(for: .crop))
    }
}

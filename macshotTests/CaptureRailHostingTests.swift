import AppKit
import XCTest

@MainActor
final class CaptureRailHostingTests: XCTestCase {
    func testSpanningSelectionPlacesBothInteractiveRailsAtCaptureEdges() throws {
        let screens = NSScreen.screens
        let pair = screens.lazy.compactMap { left in
            screens.first { right in
                right !== left
                    && abs(left.frame.maxX - right.frame.minX) < 1
                    && min(left.frame.maxY, right.frame.maxY) - max(left.frame.minY, right.frame.minY) > 700
            }.map { (left, $0) }
        }.first
        guard let (left, right) = pair else {
            throw XCTSkip("Two horizontally adjacent displays are required for this integration test")
        }

        let middleY = (max(left.frame.minY, right.frame.minY) + min(left.frame.maxY, right.frame.maxY)) / 2
        let globalSelection = NSRect(x: left.frame.maxX - 120, y: middleY - 80, width: 240, height: 160)
        let allTools = AnnotationTool.allCases
            .filter { $0 != .select && $0 != .translateOverlay }
            .map(\.rawValue)

        for primary in [left, right] {
            for glass in [false, true] {
                try withDefaults([LiquidGlass.defaultsKey: glass,
                                  "enabledTools": allTools, "knownToolRawValues": allTools]) {
                    let controller = OverlayWindowController(screen: primary)
                    let peer = OverlayWindowController(screen: primary === left ? right : left)
                    let window = try XCTUnwrap(NSApp.window(withWindowNumber: Int(controller.windowNumber)))
                    let view = try XCTUnwrap(
                        Mirror(reflecting: controller).children.first { $0.label == "overlayView" }?.value as? OverlayView)
                    defer { controller.tearDown(); peer.tearDown() }
                    peer.showOverlay()
                    controller.showOverlay()
                    view.currentTool = .select
                    view.applySelection(view.convert(window.convertFromScreen(globalSelection), from: nil))

                    let annotation = try XCTUnwrap(
                        Mirror(reflecting: view).children.first { $0.label == "bottomStripView" }?.value as? ToolbarStripView)
                    let actions = try XCTUnwrap(
                        Mirror(reflecting: view).children.first { $0.label == "rightStripView" }?.value as? ToolbarStripView)
                    let annotationWindow = try XCTUnwrap(annotation.window)
                    let actionWindow = try XCTUnwrap(actions.window)
                    let annotationFrame = annotationWindow.convertToScreen(annotation.convert(annotation.bounds, to: nil))
                    let actionFrame = actionWindow.convertToScreen(actions.convert(actions.bounds, to: nil))

                    XCTAssertLessThan(annotationFrame.maxX, globalSelection.minX)
                    XCTAssertGreaterThan(actionFrame.minX, globalSelection.maxX)
                    XCTAssertTrue(left.frame.contains(annotationFrame))
                    XCTAssertTrue(right.frame.contains(actionFrame))
                    if primary === left {
                        XCTAssertFalse(actionWindow === window, "the action rail must not be clipped by the first overlay")
                    } else {
                        XCTAssertFalse(annotationWindow === window, "the annotation rail must not be clipped by the first overlay")
                    }

                    let remoteStrip = primary === left ? actions : annotation
                    let remoteWindow = try XCTUnwrap(remoteStrip.window)
                    XCTAssertGreaterThan(remoteWindow.level.rawValue, window.level.rawValue)
                    let button = try XCTUnwrap(remoteStrip.buttonViews.first)
                    let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
                    let scenario = "origin: \(primary === left ? "left" : "right"), glass: \(glass)"
                    let hit = remoteWindow.contentView?.hitTest(point)
                    XCTAssertTrue(hit === button, "incorrect remote hit target \(String(describing: hit)), \(scenario)")
                    var clicked = false
                    let originalClick = remoteStrip.onClick
                    remoteStrip.onClick = { _ in clicked = true }
                    try click(button)
                    XCTAssertTrue(clicked, "the rail on the other display must receive clicks, \(scenario)")
                    remoteStrip.onClick = originalClick

                    NSApp.updateWindows()
                    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
                    let windows = try XCTUnwrap(CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
                                                as? [[String: Any]])
                    let orderedIDs = windows.compactMap { $0[kCGWindowNumber as String] as? Int }
                    let allWindows = try XCTUnwrap(CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID)
                                                   as? [[String: Any]])
                    let remoteInfo = allWindows.first { ($0[kCGWindowNumber as String] as? Int) == remoteWindow.windowNumber }
                    let remoteIndex = try XCTUnwrap(orderedIDs.firstIndex(of: remoteWindow.windowNumber),
                        "remote window: AppKit-visible \(remoteWindow.isVisible), listed \(remoteInfo != nil), "
                        + "on-screen \(String(describing: remoteInfo?[kCGWindowIsOnscreen as String]))")
                    let peerIndex = try XCTUnwrap(orderedIDs.firstIndex(of: Int(peer.windowNumber)))
                    XCTAssertLessThan(remoteIndex, peerIndex, "remote rails must be above the peer overlay")

                    let entered = try XCTUnwrap(NSEvent.enterExitEvent(
                        with: .mouseEntered, location: point, modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: remoteWindow.windowNumber, context: nil,
                        eventNumber: 2, trackingNumber: 1, userData: nil))
                    button.setHovered(false)
                    button.mouseEntered(with: entered)
                    let hoverText = Mirror(reflecting: view).children.first { $0.label == "hoveredTooltip" }?.value as? String
                    XCTAssertNotNil(hoverText, "remote hover must update the overlay, \(scenario)")
                    view.display()
                    let hoverAfterDisplay = Mirror(reflecting: view).children.first { $0.label == "hoveredTooltip" }?.value as? String
                    XCTAssertNotNil(hoverAfterDisplay, "remote hover must survive layout, \(scenario)")
                    let tooltipWindow = try XCTUnwrap(window.childWindows?.first {
                        $0.isVisible && $0.contentView is TooltipBackgroundView
                    }, "the remote toolbar tooltip must be visible, \(scenario)")
                    XCTAssertTrue((primary === left ? right : left).frame.contains(tooltipWindow.frame))
                    XCTAssertTrue(tooltipWindow.ignoresMouseEvents)

                    let exited = try XCTUnwrap(NSEvent.enterExitEvent(
                        with: .mouseExited, location: point, modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: remoteWindow.windowNumber, context: nil,
                        eventNumber: 3, trackingNumber: 1, userData: nil))
                    button.mouseExited(with: exited)
                    XCTAssertFalse(tooltipWindow.isVisible)

                    if primary === right {
                        let arrow = try XCTUnwrap(annotation.buttonViews.first {
                            if case .tool(.arrow) = $0.action { return true }
                            return false
                        })
                        try click(arrow)
                        XCTAssertEqual(view.currentTool, .arrow)
                        try click(arrow)
                        let optionsController = try XCTUnwrap(
                            Mirror(reflecting: view).children.first {
                                $0.label == "toolOptionsPopoverController"
                            }?.value as? ToolOptionsPopoverController)
                        let popover = try XCTUnwrap(
                            Mirror(reflecting: optionsController).children.first { $0.label == "popover" }?.value as? NSPopover)
                        XCTAssertTrue(popover.isShown, "remote annotation options must open")
                        XCTAssertTrue(popover.contentViewController?.view.window?.isVisible == true)
                        optionsController.dismiss()
                    }

                    let localSelection = NSRect(x: primary.frame.midX - 100, y: primary.frame.midY - 80,
                                                width: 200, height: 160)
                    view.applySelection(view.convert(window.convertFromScreen(localSelection), from: nil))
                    try redraw(view)
                    XCTAssertTrue(remoteStrip.window === window, "rails must return to the originating overlay")
                    XCTAssertFalse(remoteWindow.isVisible, "old floating panels must be closed")

                    view.applySelection(view.convert(window.convertFromScreen(globalSelection), from: nil))
                    try redraw(view)
                    let reopenedWindow = try XCTUnwrap(remoteStrip.window)
                    XCTAssertFalse(reopenedWindow === window)
                    view.clearSelection()
                    XCTAssertFalse(reopenedWindow.isVisible, "floating rails must disappear when capture ends")
                }
            }
        }
    }

    func testInitialOptionDragHostsTheFarRailOutsideItsOverlayWindow() throws {
        let screen = try XCTUnwrap(NSScreen.main, "a display is required for the capture overlay")
        let leftFrame = NSRect(
            x: screen.frame.minX,
            y: screen.frame.minY,
            width: screen.frame.width / 2,
            height: screen.frame.height)
        let rightFrame = NSRect(
            x: leftFrame.maxX,
            y: screen.frame.minY,
            width: screen.frame.maxX - leftFrame.maxX,
            height: screen.frame.height)
        guard leftFrame.width > 200, rightFrame.width > 200 else {
            throw XCTSkip("the display is too narrow to host both capture rails")
        }

        let dividerX = leftFrame.maxX
        let selection = NSRect(x: dividerX - 80, y: screen.frame.midY - 60, width: 160, height: 120)
        let allTools = AnnotationTool.allCases
            .filter { $0 != .select && $0 != .translateOverlay }
            .map(\.rawValue)

        for startsOnLeft in [true, false] {
            try withDefaults([
                LiquidGlass.defaultsKey: true,
                "spanMultipleMonitorsByDefault": false,
                "enabledTools": allTools,
                "knownToolRawValues": allTools,
            ]) {
                let controller = OverlayWindowController(screen: screen)
                let peer = OverlayWindowController(screen: screen)
                let appDelegate = AppDelegate()
                appDelegate.registerOverlayControllers([controller, peer])
                controller.overlayDelegate = appDelegate
                peer.overlayDelegate = appDelegate
                defer {
                    appDelegate.overlayDidCancel(controller)
                    peer.dismiss()
                    controller.dismiss()
                }

                let view = try XCTUnwrap(
                    Mirror(reflecting: controller).children.first { $0.label == "overlayView" }?.value as? OverlayView)
                let peerWindow = try XCTUnwrap(NSApp.window(withWindowNumber: Int(peer.windowNumber)))
                let window = try XCTUnwrap(NSApp.window(withWindowNumber: Int(controller.windowNumber)))
                peer.showOverlay()
                controller.showOverlay()
                window.setFrame(startsOnLeft ? leftFrame : rightFrame, display: false)
                peerWindow.setFrame(startsOnLeft ? rightFrame : leftFrame, display: false)

                view.currentTool = .select
                let start = startsOnLeft
                    ? NSPoint(x: selection.minX, y: selection.minY)
                    : NSPoint(x: selection.maxX, y: selection.maxY)
                let end = startsOnLeft
                    ? NSPoint(x: selection.maxX, y: selection.maxY)
                    : NSPoint(x: selection.minX, y: selection.minY)

                NSApp.sendEvent(try mouseEvent(
                    .leftMouseDown,
                    at: window.convertPoint(fromScreen: start),
                    modifierFlags: [.option],
                    in: window))
                let drag = try mouseEvent(
                    .leftMouseDragged,
                    at: peerWindow.convertPoint(fromScreen: end),
                    modifierFlags: [.option],
                    in: peerWindow)
                NSApp.sendEvent(drag)
                let release = try mouseEvent(
                    .leftMouseUp,
                    at: peerWindow.convertPoint(fromScreen: end),
                    modifierFlags: [.option],
                    in: peerWindow)
                NSApp.sendEvent(release)

                let expectedSelection = view.convert(window.convertFromScreen(selection), from: nil)
                XCTAssertEqual(view.selectionRect, expectedSelection)
                try redraw(view)

                let annotation = try XCTUnwrap(
                    Mirror(reflecting: view).children.first { $0.label == "bottomStripView" }?.value as? ToolbarStripView)
                let actions = try XCTUnwrap(
                    Mirror(reflecting: view).children.first { $0.label == "rightStripView" }?.value as? ToolbarStripView)
                let annotationWindow = try XCTUnwrap(annotation.window)
                let actionWindow = try XCTUnwrap(actions.window)
                let annotationFrame = annotationWindow.convertToScreen(annotation.convert(annotation.bounds, to: nil))
                let actionFrame = actionWindow.convertToScreen(actions.convert(actions.bounds, to: nil))

                XCTAssertLessThan(annotationFrame.maxX, selection.minX)
                XCTAssertGreaterThan(actionFrame.minX, selection.maxX)
                XCTAssertTrue(screen.frame.contains(annotationFrame))
                XCTAssertTrue(screen.frame.contains(actionFrame))

                let remoteStrip = startsOnLeft ? actions : annotation
                let remoteWindow = try XCTUnwrap(remoteStrip.window)
                XCTAssertFalse(remoteWindow === window, "the rail beyond the initiating overlay must be hosted separately")
                XCTAssertTrue(remoteWindow.isVisible)
                let button = try XCTUnwrap(remoteStrip.buttonViews.first)
                let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
                XCTAssertTrue(remoteWindow.contentView?.hitTest(point) === button)

                var clicked = false
                let originalClick = remoteStrip.onClick
                remoteStrip.onClick = { _ in clicked = true }
                try click(button)
                XCTAssertTrue(clicked, "the remote rail must receive clicks after an Option-spanning drag")
                remoteStrip.onClick = originalClick
            }
        }
    }

    private func click(_ button: ToolbarButtonView) throws {
        let window = try XCTUnwrap(button.window)
        let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1))
            NSApp.sendEvent(event)
        }
    }

    private func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint,
                            modifierFlags: NSEvent.ModifierFlags = [], in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: modifierFlags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1))
    }

    private func redraw(_ view: OverlayView) throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = graphics
        view.draw(view.bounds)
    }
}

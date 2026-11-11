import Cocoa
import XCTest

@MainActor
final class CrossDisplayDragSelectionTests: XCTestCase {
    func testInitialDragUsesActualEventsAcrossDisplayArrangements() throws {
        _ = try mainScreenOrSkip()
        let cases: [(NSRect, NSRect, NSPoint, NSPoint, NSRect)] = [
            (
                NSRect(x: 0, y: 0, width: 400, height: 300),
                NSRect(x: 400, y: 0, width: 400, height: 300),
                NSPoint(x: 350, y: 250), NSPoint(x: 50, y: 40),
                NSRect(x: 350, y: 40, width: 100, height: 210)),
            (
                NSRect(x: 0, y: 0, width: 400, height: 300),
                NSRect(x: 0, y: 300, width: 400, height: 300),
                NSPoint(x: 350, y: 250), NSPoint(x: 50, y: 40),
                NSRect(x: 50, y: 250, width: 300, height: 90)),
            (
                NSRect(x: 0, y: 0, width: 400, height: 300),
                NSRect(x: -400, y: -300, width: 400, height: 300),
                NSPoint(x: 50, y: 50), NSPoint(x: 350, y: 250),
                NSRect(x: -50, y: -50, width: 100, height: 100)),
        ]

        for (targetFrame, sourceFrame, start, end, expected) in cases {
            XCTAssertEqual(
                try dragSelection(targetFrame: targetFrame, sourceFrame: sourceFrame, from: start, to: end),
                expected)
        }
    }

    func testSelectionContinuesThroughOverlayControllerAcrossMixedDisplayOrigins() throws {
        let target = OverlayWindowController(screen: try mainScreenOrSkip())
        let appDelegate = AppDelegate()
        target.overlayDelegate = appDelegate
        let targetWindow = try XCTUnwrap(NSApp.window(withWindowNumber: Int(target.windowNumber)))
        let targetView = try XCTUnwrap(overlayView(in: target))
        let targetFrame = NSRect(x: -400, y: -300, width: 400, height: 300)
        targetWindow.setFrame(targetFrame, display: false)
        targetWindow.makeKeyAndOrderFront(nil)
        targetWindow.makeFirstResponder(targetView)

        let peer = OverlayWindowController(screen: try XCTUnwrap(NSScreen.main))
        peer.overlayDelegate = appDelegate
        let peerWindow = try XCTUnwrap(NSApp.window(withWindowNumber: Int(peer.windowNumber)))
        let peerView = try XCTUnwrap(overlayView(in: peer))
        peerWindow.setFrame(NSRect(x: 0, y: 0, width: 400, height: 300), display: false)
        peerWindow.orderFrontRegardless()

        let nextDisplayWindow = NSWindow(
            contentRect: NSRect(x: 400, y: 0, width: 400, height: 300),
            styleMask: .borderless,
            backing: .buffered,
            defer: false)
        nextDisplayWindow.orderFrontRegardless()
        defer {
            nextDisplayWindow.orderOut(nil)
            appDelegate.overlayDidCancel(target)
            peer.dismiss()
            target.dismiss()
        }

        let start = NSPoint(x: 350, y: 250)
        targetView.mouseDown(with: mouseEvent(.leftMouseDown, at: start, in: targetWindow))

        let dragPoint = NSPoint(x: 50, y: 40)
        let drag = mouseEvent(.leftMouseDragged, at: dragPoint, in: peerWindow)
        NSApp.sendEvent(drag)

        let release = mouseEvent(.leftMouseUp, at: dragPoint, in: peerWindow)
        NSApp.sendEvent(release)
        XCTAssertEqual(
            target.selectionRect,
            NSRect(x: 350, y: 250, width: 100, height: 90),
            "the drag must be evaluated in the initiating overlay's coordinates, even across a negative-origin display")

        targetView.applySelection(NSRect(x: 100, y: 100, width: 200, height: 150))
        NSApp.sendEvent(mouseEvent(.leftMouseDown, at: NSPoint(x: 300, y: 175), in: targetWindow))
        NSApp.sendEvent(mouseEvent(.leftMouseDragged, at: NSPoint(x: 50, y: 40), in: peerWindow))
        NSApp.sendEvent(mouseEvent(.leftMouseUp, at: NSPoint(x: 50, y: 40), in: peerWindow))
        XCTAssertEqual(
            target.selectionRect,
            NSRect(x: 100, y: 100, width: 350, height: 150),
            "a primary selection handle must keep tracking after the cursor enters another display")

        peer.setRemoteSelection(
            NSRect(x: 0, y: 0, width: 50, height: 100),
            fullRect: NSRect(x: -50, y: 0, width: 100, height: 100))
        NSApp.sendEvent(mouseEvent(.leftMouseDown, at: NSPoint(x: 50, y: 50), in: peerWindow))
        NSApp.sendEvent(
            mouseEvent(.leftMouseDragged, at: NSPoint(x: 50, y: 50), in: nextDisplayWindow))
        NSApp.sendEvent(
            mouseEvent(.leftMouseUp, at: NSPoint(x: 50, y: 50), in: nextDisplayWindow))

        XCTAssertEqual(
            peerView.remoteSelectionFullRect,
            NSRect(x: -50, y: 0, width: 500, height: 100),
            "a remote resize must continue beyond the grabbed display while preserving the unclipped selection")
        XCTAssertEqual(
            peer.remoteSelectionRect,
            NSRect(x: 0, y: 0, width: 400, height: 100),
            "only the visible portion should be clipped to the peer display")
    }

    func testRestoredSelectionCanBeResizedAcrossDisplayWindows() throws {
        let screen = try mainScreenOrSkip()
        let target = OverlayWindowController(screen: screen)
        let appDelegate = AppDelegate()
        appDelegate.registerOverlayControllers([target])
        target.overlayDelegate = appDelegate
        let targetWindow = try XCTUnwrap(NSApp.window(withWindowNumber: Int(target.windowNumber)))
        let selection = NSRect(x: 100, y: 100, width: 200, height: 150)
        let sourceWindow = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false)
        defer {
            sourceWindow.orderOut(nil)
            appDelegate.overlayDidCancel(target)
            target.dismiss()
        }

        withDefaults([
            "lastSelectionRect": NSStringFromRect(selection),
            "lastSelectionScreenFrame": NSStringFromRect(screen.frame),
        ]) {
            appDelegate.overlayDidRequestRestoreLastSelection(target)
            sourceWindow.orderFrontRegardless()
            NSApp.sendEvent(mouseEvent(
                .leftMouseDown, at: NSPoint(x: selection.maxX, y: selection.midY), in: targetWindow))
            NSApp.sendEvent(mouseEvent(
                .leftMouseDragged,
                at: NSPoint(x: selection.maxX + 50, y: selection.midY),
                in: sourceWindow))
            NSApp.sendEvent(mouseEvent(
                .leftMouseUp,
                at: NSPoint(x: selection.maxX + 50, y: selection.midY),
                in: sourceWindow))

            XCTAssertEqual(
                target.selectionRect,
                NSRect(x: 100, y: 100, width: 250, height: 150),
                "restored selections must install cross-display drag monitoring")
        }
    }

    func testResizedCrossScreenSelectionStitchesAndExportsPixelsAtGlobalBounds() throws {
        try XCTSkipIf(NSScreen.main == nil, "no main screen in this environment")
        let screens = NSScreen.screens
        guard let pair = adjacentScreens(in: screens) else {
            throw XCTSkip("requires two displays sharing an edge")
        }
        let primary = OverlayWindowController(screen: pair.primary)
        let peer = OverlayWindowController(screen: pair.peer)
        defer {
            primary.dismiss()
            peer.dismiss()
        }
        primary.setScreenshot(try XCTUnwrap(cgImage(
            from: ImageProbe.solidImage(width: 256, height: 144,
                                        color: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)))))
        peer.setScreenshot(try XCTUnwrap(cgImage(
            from: ImageProbe.solidImage(width: 256, height: 144,
                                        color: CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)))))

        let selection = pair.globalSelection
        let primaryLocal = NSRect(
            x: selection.minX - pair.primary.frame.minX,
            y: selection.minY - pair.primary.frame.minY,
            width: selection.width,
            height: selection.height)
        primary.applySelection(primaryLocal)
        let peerLocal = NSRect(
            x: selection.minX - pair.peer.frame.minX,
            y: selection.minY - pair.peer.frame.minY,
            width: selection.width,
            height: selection.height)
        peer.setRemoteSelection(
            peerLocal.intersection(NSRect(origin: .zero, size: pair.peer.frame.size)),
            fullRect: peerLocal)
        let stitched = try XCTUnwrap(CrossScreenCaptureStitcher.stitch(
            primarySelection: primary.selectionRect,
            primaryFrame: pair.primary.frame,
            primaryBackingScale: pair.primary.backingScaleFactor,
            primaryImage: primary.screenshotImage,
            otherScreens: [CrossScreenCaptureImage(frame: pair.peer.frame, image: try XCTUnwrap(peer.screenshotImage))]))
        XCTAssertEqual(stitched.size, selection.size)
        assertPixel(at: pair.primarySample, isRedIn: stitched, globalRect: selection)
        assertPixel(at: pair.peerSample, isBlueIn: stitched, globalRect: selection)

        var exportData: Data?
        withDefaults(["imageFormat": "png", "downscaleRetina": false]) {
            exportData = ImageEncoder.encode(stitched)
        }
        let exported = try XCTUnwrap(exportData)
        let decoded = try XCTUnwrap(NSImage(data: exported))
        let stitchedBitmap = try XCTUnwrap(ImageProbe.bitmap(from: stitched))
        let exportedBitmap = try XCTUnwrap(ImageProbe.bitmap(from: decoded))
        XCTAssertEqual(exportedBitmap.pixelsWide, stitchedBitmap.pixelsWide)
        XCTAssertEqual(exportedBitmap.pixelsHigh, stitchedBitmap.pixelsHigh)
        assertPixel(at: pair.primarySample, isRedIn: decoded, globalRect: selection)
        assertPixel(at: pair.peerSample, isBlueIn: decoded, globalRect: selection)
    }

    func testSpanningCaptureExportIncludesAnnotationsAndRetainsRawEditablePixels() throws {
        let screen = try mainScreenOrSkip()
        let controller = OverlayWindowController(screen: screen)
        let primaryImage = NSImage(
            cgImage: try XCTUnwrap(cgImage(from: ImageProbe.solidImage(
                width: 800, height: 400,
                color: CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)))),
            size: NSSize(width: 400, height: 200))
        let peerImage = NSImage(
            cgImage: try XCTUnwrap(cgImage(from: ImageProbe.solidImage(
                width: 800, height: 400,
                color: CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)))),
            size: NSSize(width: 400, height: 200))
        let delegate = SpanningCaptureDelegate(primaryImage: primaryImage, peerImage: peerImage)
        controller.overlayDelegate = delegate
        let view = try XCTUnwrap(overlayView(in: controller))
        defer { controller.dismiss() }

        let selection = NSRect(x: screen.frame.width - 100, y: 100, width: 200, height: 100)
        XCTAssertGreaterThan(selection.maxX, view.bounds.maxX, "the capture must extend onto another display")
        controller.setScreenshot(try XCTUnwrap(cgImage(from: primaryImage)))
        controller.applySelection(selection)
        view.annotations = [Annotation(
            tool: .filledRectangle,
            startPoint: NSPoint(x: screen.frame.width - 80, y: 120),
            endPoint: NSPoint(x: screen.frame.width - 40, y: 160),
            color: .red,
            strokeWidth: 2)]
        view.cachedCompositedImage = nil

        withDefaults(["playCopySound": false, "imageFormat": "png", "downscaleRetina": false]) {
            controller.overlayViewDidConfirm()
        }

        let exportedImage = try XCTUnwrap(delegate.confirmedImage)
        let exportedData = try XCTUnwrap(ImageEncoder.encode(exportedImage))
        let decodedExport = try XCTUnwrap(NSImage(data: exportedData))
        let exportedBitmap = try XCTUnwrap(ImageProbe.bitmap(from: decodedExport))
        XCTAssertEqual(exportedBitmap.pixelsWide, 400)
        XCTAssertEqual(exportedBitmap.pixelsHigh, 200)
        let globalSelection = NSRect(
            x: selection.minX + screen.frame.minX,
            y: selection.minY + screen.frame.minY,
            width: selection.width,
            height: selection.height)
        let annotationSample = NSPoint(
            x: screen.frame.minX + screen.frame.width - 60,
            y: screen.frame.minY + 140)
        let remoteSample = NSPoint(
            x: screen.frame.minX + screen.frame.width + 50,
            y: screen.frame.minY + 150)

        assertPixel(at: annotationSample, isRedIn: decodedExport, globalRect: globalSelection)
        XCTAssertEqual(exportedImage.size, selection.size)
        let rawHistoryImage = try XCTUnwrap(delegate.annotationData?.rawImage)
        let rawHistoryBitmap = try XCTUnwrap(ImageProbe.bitmap(from: rawHistoryImage))
        XCTAssertEqual(rawHistoryBitmap.pixelsWide, 400)
        XCTAssertEqual(rawHistoryBitmap.pixelsHigh, 200)
        assertPixel(at: annotationSample, isGreenIn: rawHistoryImage, globalRect: globalSelection)
        assertPixel(at: remoteSample, isBlueIn: rawHistoryImage, globalRect: globalSelection)
        XCTAssertEqual(delegate.annotationData?.annotations.count, 1)
    }

    func testSpanningScreenshotAnnotationsUseStitchedPixelsForExportAndEditorHistory() throws {
        let screen = try mainScreenOrSkip()
        let primaryImage = NSImage(
            cgImage: try XCTUnwrap(cgImage(from: ImageProbe.solidImage(
                width: 800, height: 400,
                color: CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)))),
            size: NSSize(width: 400, height: 200))
        let stripedRawImage = try stitchedFixture(
            primaryImage: primaryImage, peerImage: stripedSpanningImage())
        let captureRect = NSRect(x: screen.frame.width - 100, y: 100, width: 200, height: 100)
        let remoteAnnotationRect = NSRect(
            x: screen.frame.width + 20, y: 120, width: 60, height: 60)

        for tool in [AnnotationTool.pixelate, .blur] {
            let controller = OverlayWindowController(screen: screen)
            let delegate = SpanningCaptureDelegate(
                primaryImage: primaryImage,
                peerImage: stripedRawImage,
                stitchedImage: stripedRawImage)
            controller.overlayDelegate = delegate
            defer { controller.dismiss() }
            controller.setScreenshot(try XCTUnwrap(cgImage(from: delegate.primaryImage)))
            controller.applySelection(captureRect)
            let view = try XCTUnwrap(overlayView(in: controller))
            let annotation = Annotation(
                tool: tool,
                startPoint: remoteAnnotationRect.origin,
                endPoint: NSPoint(x: remoteAnnotationRect.maxX, y: remoteAnnotationRect.maxY),
                color: .black,
                strokeWidth: 2)
            annotation.censorMode = tool == .blur ? .blur : .pixelate
            annotation.sourceImage = view.screenshotImage
            annotation.sourceImageBounds = view.captureDrawRect
            view.annotations = [annotation]

            withDefaults(["playCopySound": false, "imageFormat": "png", "downscaleRetina": false]) {
                controller.overlayViewDidConfirm()
            }

            let exported = try XCTUnwrap(delegate.confirmedImage, "\(tool) capture should export")
            XCTAssertLessThan(
                horizontalLuminanceDeviation(in: exported, xRange: 125..<175, y: 50),
                0.12,
                "\(tool) over the remote portion must be baked from stitched pixels, not left as a translucent preview")

            let editable = try XCTUnwrap(delegate.annotationData)
            XCTAssertGreaterThan(
                horizontalLuminanceDeviation(in: editable.rawImage, xRange: 125..<175, y: 50),
                0.4,
                "editable history must retain the unmodified stitched source")
            let serialized = try XCTUnwrap(AnnotationSerializer.encode(editable.annotations))
            let restored = try XCTUnwrap(AnnotationSerializer.decode(serialized))
            let editor = EditorView(frame: NSRect(origin: .zero, size: captureRect.size))
            editor.screenshotImage = editable.rawImage
            editor.applySelection(NSRect(origin: .zero, size: captureRect.size))
            editor.setAnnotations(restored)
            let editorImage = try XCTUnwrap(editor.captureSelectedRegion())
            XCTAssertLessThan(
                horizontalLuminanceDeviation(in: editorImage, xRange: 125..<175, y: 50),
                0.12,
                "\(tool) must render from the stitched raw image after editable-history reload")
        }

        let loupeRawImage = try stitchedFixture(
            primaryImage: primaryImage, peerImage: solidSpanningImage(color: .red))
        let controller = OverlayWindowController(screen: screen)
        let delegate = SpanningCaptureDelegate(
            primaryImage: primaryImage,
            peerImage: loupeRawImage,
            stitchedImage: loupeRawImage)
        controller.overlayDelegate = delegate
        defer { controller.dismiss() }
        controller.setScreenshot(try XCTUnwrap(cgImage(from: delegate.primaryImage)))
        controller.applySelection(captureRect)
        let view = try XCTUnwrap(overlayView(in: controller))
        let loupe = Annotation(
            tool: .loupe,
            startPoint: NSPoint(x: screen.frame.width + 35, y: 135),
            endPoint: NSPoint(x: screen.frame.width + 75, y: 175),
            color: .red,
            strokeWidth: 4)
        loupe.loupeSourceRect = NSRect(x: screen.frame.width + 35, y: 135, width: 20, height: 20)
        loupe.sourceImage = view.screenshotImage
        loupe.sourceImageBounds = view.captureDrawRect
        view.annotations = [loupe]

        withDefaults(["playCopySound": false, "imageFormat": "png", "downscaleRetina": false]) {
            controller.overlayViewDidConfirm()
        }

        let loupeExport = try XCTUnwrap(delegate.confirmedImage)
        assertPixel(
            at: NSPoint(x: 155, y: 55),
            isRedIn: loupeExport,
            globalRect: NSRect(origin: .zero, size: captureRect.size))
        let loupeData = try XCTUnwrap(delegate.annotationData)
        let serializedLoupe = try XCTUnwrap(AnnotationSerializer.encode(loupeData.annotations))
        let decodedLoupe = try XCTUnwrap(AnnotationSerializer.decode(serializedLoupe))
        let editor = EditorView(frame: NSRect(origin: .zero, size: captureRect.size))
        editor.screenshotImage = loupeData.rawImage
        editor.applySelection(NSRect(origin: .zero, size: captureRect.size))
        editor.setAnnotations(decodedLoupe)
        let loupeEditorImage = try XCTUnwrap(editor.captureSelectedRegion())
        assertPixel(
            at: NSPoint(x: 155, y: 55),
            isRedIn: loupeEditorImage,
            globalRect: NSRect(origin: .zero, size: captureRect.size))
    }

    func testSpanningCaptureReportsFailureInsteadOfExportingUnrenderableSource() throws {
        let screen = try mainScreenOrSkip()
        let primaryImage = NSImage(
            cgImage: try XCTUnwrap(cgImage(from: ImageProbe.solidImage(
                width: 800, height: 400,
                color: CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)))),
            size: NSSize(width: 400, height: 200))
        let invalidStitchedImage = NSImage(size: NSSize(width: 200, height: 100))
        let failures: [CrossScreenCaptureResult] = [
                .failed,
                .image(invalidStitchedImage),
        ]
        for failure in failures {
                let controller = OverlayWindowController(screen: screen)
                let delegate = SpanningCaptureDelegate(
                    primaryImage: primaryImage,
                    peerImage: invalidStitchedImage,
                    crossScreenResult: failure)
                controller.overlayDelegate = delegate
                defer { controller.dismiss() }
                controller.setScreenshot(try XCTUnwrap(cgImage(from: primaryImage)))
                controller.applySelection(NSRect(x: screen.frame.width - 100, y: 100, width: 200, height: 100))
                let view = try XCTUnwrap(overlayView(in: controller))
                let redaction = Annotation(
                    tool: .pixelate,
                    startPoint: NSPoint(x: screen.frame.width + 20, y: 120),
                    endPoint: NSPoint(x: screen.frame.width + 80, y: 180),
                    color: .black,
                    strokeWidth: 2)
                redaction.censorMode = .solid
                view.annotations = [redaction]

                withDefaults(["playCopySound": false, "imageFormat": "png", "downscaleRetina": false]) {
                    controller.overlayViewDidConfirm()
                }

                XCTAssertNil(delegate.confirmedImage)
                XCTAssertEqual(delegate.captureFailureMessage, L("Save failed"))
        }
    }

    func testAppDelegateDistinguishesNoSpanFromMissingRemoteScreenshot() throws {
        let screen = try mainScreenOrSkip()
        let primary = OverlayWindowController(screen: screen)
        let peer = OverlayWindowController(screen: screen)
        let appDelegate = AppDelegate()
        appDelegate.registerOverlayControllers([primary, peer])
        defer {
            primary.dismiss()
            peer.dismiss()
        }

        if case .notSpanning = appDelegate.overlayCrossScreenImage(primary) {
        } else {
            XCTFail("no remote selection should be reported as not spanning")
        }

        primary.setScreenshot(try XCTUnwrap(cgImage(from: ImageProbe.solidImage(
            width: 64, height: 64,
            color: CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)))))
        primary.applySelection(NSRect(x: 20, y: 20, width: 80, height: 40))
        peer.setRemoteSelection(
            NSRect(x: 0, y: 0, width: 40, height: 40),
            fullRect: NSRect(x: -20, y: 0, width: 60, height: 40))

        if case .failed = appDelegate.overlayCrossScreenImage(primary) {
        } else {
            XCTFail("a spanning selection with a missing peer screenshot must fail")
        }
    }

    func testSingleScreenHistoryPreservesExistingBlurBake() throws {
        let screen = try mainScreenOrSkip()
        let primaryImage = NSImage(
            cgImage: try XCTUnwrap(cgImage(from: ImageProbe.solidImage(
                width: 800, height: 400,
                color: CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)))),
            size: NSSize(width: 400, height: 200))
        let controller = OverlayWindowController(screen: screen)
        let delegate = SpanningCaptureDelegate(
            primaryImage: primaryImage,
            peerImage: primaryImage,
            crossScreenResult: .notSpanning)
        controller.overlayDelegate = delegate
        defer { controller.dismiss() }
        controller.setScreenshot(try XCTUnwrap(cgImage(from: primaryImage)))
        controller.applySelection(NSRect(x: 80, y: 70, width: 120, height: 100))
        let annotation = Annotation(
            tool: .blur,
            startPoint: NSPoint(x: 100, y: 90),
            endPoint: NSPoint(x: 150, y: 140),
            color: .black,
            strokeWidth: 2)
        annotation.censorMode = .blur
        let originalBake = ImageProbe.solidImage(
            width: 40, height: 40,
            color: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        annotation.bakedBlurNSImage = originalBake
        let view = try XCTUnwrap(overlayView(in: controller))
        view.annotations = [annotation]

        withDefaults(["playCopySound": false, "imageFormat": "png", "downscaleRetina": false]) {
            controller.overlayViewDidConfirm()
        }

        let restoredBake = try XCTUnwrap(delegate.annotationData?.annotations.first?.bakedBlurNSImage)
        XCTAssertTrue(restoredBake === originalBake)
    }

    func testCrossDisplayResizeRoutingWaitsForMouseDownToStartResize() throws {
        let screen = try mainScreenOrSkip()
        let controller = OverlayWindowController(screen: screen)
        let appDelegate = AppDelegate()
        appDelegate.registerOverlayControllers([controller])
        controller.overlayDelegate = appDelegate
        let window = try XCTUnwrap(NSApp.window(withWindowNumber: Int(controller.windowNumber)))
        let view = try XCTUnwrap(overlayView(in: controller))
        let selection = NSRect(x: 100, y: 100, width: 200, height: 150)
        view.applySelection(selection)
        view.isScrollCapturing = true
        let sourceWindow = NSWindow(
            contentRect: NSRect(
                x: screen.frame.maxX,
                y: screen.frame.minY,
                width: screen.frame.width,
                height: screen.frame.height),
            styleMask: .borderless,
            backing: .buffered,
            defer: false)
        appDelegate.overlayDidFinishSelection(controller)
        defer {
            sourceWindow.orderOut(nil)
            appDelegate.overlayDidCancel(controller)
            controller.dismiss()
        }
        sourceWindow.orderFrontRegardless()

        NSApp.sendEvent(mouseEvent(
            .leftMouseDown,
            at: NSPoint(x: selection.maxX, y: selection.midY),
            in: window))
        XCTAssertFalse(view.isResizingCrossDisplaySelection)
        NSApp.sendEvent(mouseEvent(
            .leftMouseDragged,
            at: NSPoint(x: 50, y: selection.midY - screen.frame.minY),
            in: sourceWindow))
        NSApp.sendEvent(mouseEvent(
            .leftMouseUp,
            at: NSPoint(x: 50, y: selection.midY - screen.frame.minY),
            in: sourceWindow))

        XCTAssertEqual(view.selectionRect, selection)
    }

    func testCrossDisplayResizeRoutingIgnoresChromeOverlappingAHandle() throws {
        let screen = try mainScreenOrSkip()
        let controller = OverlayWindowController(screen: screen)
        let appDelegate = AppDelegate()
        appDelegate.registerOverlayControllers([controller])
        controller.overlayDelegate = appDelegate
        defer {
            appDelegate.overlayDidCancel(controller)
            controller.dismiss()
        }
        let window = try XCTUnwrap(NSApp.window(withWindowNumber: Int(controller.windowNumber)))
        let view = try XCTUnwrap(overlayView(in: controller))
        let selection = NSRect(x: 100, y: 100, width: 200, height: 150)
        view.applySelection(selection)
        let chrome = MouseDownBlockingView(frame: NSRect(x: 295, y: 170, width: 10, height: 10))
        view.addSubview(chrome)
        let sourceWindow = NSWindow(
            contentRect: NSRect(
                x: screen.frame.maxX,
                y: screen.frame.minY,
                width: screen.frame.width,
                height: screen.frame.height),
            styleMask: .borderless,
            backing: .buffered,
            defer: false)
        defer { sourceWindow.orderOut(nil) }
        window.makeKeyAndOrderFront(nil)
        sourceWindow.orderFrontRegardless()
        appDelegate.overlayDidFinishSelection(controller)

        NSApp.sendEvent(mouseEvent(.leftMouseDown, at: NSPoint(x: 300, y: 175), in: window))
        XCTAssertFalse(view.isResizingCrossDisplaySelection)
        NSApp.sendEvent(mouseEvent(
            .leftMouseDragged,
            at: NSPoint(x: 50, y: selection.midY - screen.frame.minY),
            in: sourceWindow))
        NSApp.sendEvent(mouseEvent(
            .leftMouseUp,
            at: NSPoint(x: 50, y: selection.midY - screen.frame.minY),
            in: sourceWindow))

        XCTAssertEqual(view.selectionRect, selection)
    }

    private final class MouseDownBlockingView: NSView {
        override func mouseDown(with event: NSEvent) {}
    }

    private func overlayView(in controller: OverlayWindowController) -> OverlayView? {
        Mirror(reflecting: controller).children.first { $0.label == "overlayView" }?.value as? OverlayView
    }

    private func mainScreenOrSkip() throws -> NSScreen {
        try XCTSkipIf(NSScreen.main == nil, "no main screen in this environment")
        return try XCTUnwrap(NSScreen.main)
    }

    private func cgImage(from image: NSImage) -> CGImage? {
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private func stitchedFixture(primaryImage: NSImage, peerImage: NSImage) throws -> NSImage {
        try XCTUnwrap(CrossScreenCaptureStitcher.stitch(
            primarySelection: NSRect(x: 300, y: 50, width: 200, height: 100),
            primaryFrame: NSRect(x: 0, y: 0, width: 400, height: 200),
            primaryBackingScale: 2,
            primaryImage: primaryImage,
            otherScreens: [CrossScreenCaptureImage(
                frame: NSRect(x: 400, y: 0, width: 400, height: 200),
                image: peerImage)]))
    }

    private func stripedSpanningImage() throws -> NSImage {
        let width = 800
        let height = 400
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.green.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for x in 40..<160 {
            context.setFillColor((x / 8).isMultiple(of: 2) ? NSColor.black.cgColor : NSColor.white.cgColor)
            context.fill(CGRect(x: x, y: 40, width: 1, height: 240))
        }
        return NSImage(cgImage: try XCTUnwrap(context.makeImage()),
                       size: NSSize(width: 400, height: 200))
    }

    private func solidSpanningImage(color: NSColor) throws -> NSImage {
        let width = 800
        let height = 400
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.green.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 40, y: 40, width: 120, height: 240))
        return NSImage(cgImage: try XCTUnwrap(context.makeImage()),
                       size: NSSize(width: 400, height: 200))
    }

    private func horizontalLuminanceDeviation(
        in image: NSImage,
        xRange: Range<Int>,
        y: Int
    ) -> CGFloat {
        let values = xRange.compactMap { x -> CGFloat? in
            guard let color = ImageProbe.pixelColor(image, x: x * 2, y: y * 2)?
                .usingColorSpace(.sRGB) else { return nil }
            return (color.redComponent + color.greenComponent + color.blueComponent) / 3
        }
        guard !values.isEmpty else { return .infinity }
        let mean = values.reduce(0, +) / CGFloat(values.count)
        let variance = values.reduce(CGFloat.zero) { $0 + pow($1 - mean, 2) } / CGFloat(values.count)
        return sqrt(variance)
    }

    private func assertPixel(
        at point: NSPoint,
        isRedIn image: NSImage,
        globalRect: NSRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertPixel(at: point, hasColor: .red, in: image, globalRect: globalRect, file: file, line: line)
    }

    private func assertPixel(
        at point: NSPoint,
        isBlueIn image: NSImage,
        globalRect: NSRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertPixel(at: point, hasColor: .blue, in: image, globalRect: globalRect, file: file, line: line)
    }

    private func assertPixel(
        at point: NSPoint,
        isGreenIn image: NSImage,
        globalRect: NSRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertPixel(at: point, hasColor: .green, in: image, globalRect: globalRect, file: file, line: line)
    }

    private enum ExpectedColor {
        case red
        case green
        case blue
    }

    private func assertPixel(
        at point: NSPoint,
        hasColor expected: ExpectedColor,
        in image: NSImage,
        globalRect: NSRect,
        file: StaticString,
        line: UInt
    ) {
        guard let bitmap = ImageProbe.bitmap(from: image), bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 else {
            XCTFail("stitched image must have pixels", file: file, line: line)
            return
        }
        let x = min(bitmap.pixelsWide - 1, max(0, Int(
            (point.x - globalRect.minX) / globalRect.width * CGFloat(bitmap.pixelsWide))))
        let y = min(bitmap.pixelsHigh - 1, max(0, Int(
            (globalRect.maxY - point.y) / globalRect.height * CGFloat(bitmap.pixelsHigh))))
        guard let pixel = ImageProbe.pixelColor(image, x: x, y: y)?.usingColorSpace(.sRGB) else {
            XCTFail("expected pixel color to be readable", file: file, line: line)
            return
        }
        switch expected {
        case .red:
            XCTAssertGreaterThan(pixel.redComponent, 0.9, file: file, line: line)
            XCTAssertLessThan(pixel.blueComponent, 0.1, file: file, line: line)
        case .green:
            XCTAssertGreaterThan(pixel.greenComponent, 0.9, file: file, line: line)
            XCTAssertLessThan(pixel.redComponent, 0.1, file: file, line: line)
        case .blue:
            XCTAssertGreaterThan(pixel.blueComponent, 0.9, file: file, line: line)
            XCTAssertLessThan(pixel.redComponent, 0.1, file: file, line: line)
        }
    }

    @MainActor
    private final class SpanningCaptureDelegate: OverlayWindowControllerDelegate {
        let primaryImage: NSImage
        let peerImage: NSImage
        let stitchedImage: NSImage?
        let crossScreenResult: CrossScreenCaptureResult?
        private(set) var confirmedImage: NSImage?
        private(set) var annotationData: CaptureAnnotationData?
        private(set) var captureFailureMessage: String?

        init(
            primaryImage: NSImage,
            peerImage: NSImage,
            stitchedImage: NSImage? = nil,
            crossScreenResult: CrossScreenCaptureResult? = nil
        ) {
            self.primaryImage = primaryImage
            self.peerImage = peerImage
            self.stitchedImage = stitchedImage
            self.crossScreenResult = crossScreenResult
        }

        func overlayDidCancel(_ controller: OverlayWindowController) {}
        func overlayDidFailCapture(_ controller: OverlayWindowController, message: String) {
            captureFailureMessage = message
        }
        func overlayDidConfirm(
            _ controller: OverlayWindowController,
            capturedImage: NSImage?,
            annotationData: CaptureAnnotationData?
        ) {
            confirmedImage = capturedImage
            self.annotationData = annotationData
        }
        func overlayDidRequestPin(
            _ controller: OverlayWindowController,
            image: NSImage,
            annotationData: CaptureAnnotationData?
        ) {}
        func overlayDidRequestOCR(
            _ controller: OverlayWindowController,
            result: OCRScanResult,
            image: NSImage?
        ) {}
        func overlayDidRequestUpload(
            _ controller: OverlayWindowController,
            image: NSImage,
            annotationData: CaptureAnnotationData?
        ) {}
        func overlayDidRequestStartRecording(
            _ controller: OverlayWindowController,
            rect: NSRect,
            screen: NSScreen
        ) {}
        func overlayDidRequestStopRecording(_ controller: OverlayWindowController) {}
        func overlayDidRequestScrollCapture(
            _ controller: OverlayWindowController,
            rect: NSRect,
            screen: NSScreen
        ) {}
        func overlayDidRequestStopScrollCapture(_ controller: OverlayWindowController) {}
        func overlayDidRequestCancelScrollCapture(_ controller: OverlayWindowController) {}
        func overlayDidRequestToggleAutoScroll(_ controller: OverlayWindowController) {}
        func overlayDidRequestAccessibilityPermission(_ controller: OverlayWindowController) {}
        func overlayDidRequestInputMonitoringPermission(_ controller: OverlayWindowController) {}
        func overlayDidBeginSelection(_ controller: OverlayWindowController) {}
        func overlayDidChangeSelection(_ controller: OverlayWindowController, globalRect: NSRect) {}
        func overlayDidRemoteResizeSelection(_ controller: OverlayWindowController, globalRect: NSRect) {}
        func overlayDidFinishRemoteResize(_ controller: OverlayWindowController, globalRect: NSRect) {}
        func overlayCrossScreenImage(_ controller: OverlayWindowController) -> CrossScreenCaptureResult {
            if let crossScreenResult { return crossScreenResult }
            if let stitchedImage { return .image(stitchedImage) }
            let frame = controller.screen.frame
            let peerFrame = NSRect(
                x: frame.maxX,
                y: frame.minY,
                width: frame.width,
                height: frame.height)
            guard let image = CrossScreenCaptureStitcher.stitch(
                primarySelection: controller.selectionRect,
                primaryFrame: frame,
                primaryBackingScale: controller.screen.backingScaleFactor,
                primaryImage: primaryImage,
                otherScreens: [CrossScreenCaptureImage(frame: peerFrame, image: peerImage)])
            else { return .failed }
            return .image(image)
        }
        func overlayDidChangeSnapMode(_ controller: OverlayWindowController) {}
    }
    private func adjacentScreens(in screens: [NSScreen]) -> (
        primary: NSScreen, peer: NSScreen, globalSelection: NSRect,
        primarySample: NSPoint, peerSample: NSPoint
    )? {
        for first in screens {
            for second in screens where first !== second {
                let a = first.frame
                let b = second.frame
                let overlapY = min(a.maxY, b.maxY) - max(a.minY, b.minY)
                if abs(a.maxX - b.minX) < 1, overlapY >= 40 {
                    let y = max(a.minY, b.minY) + overlapY / 2
                    let selection = NSRect(x: a.maxX - 40, y: y - 20, width: 80, height: 40)
                    return (
                        first, second, selection,
                        NSPoint(x: a.maxX - 20, y: y),
                        NSPoint(x: b.minX + 20, y: y))
                }
                if abs(b.maxX - a.minX) < 1, overlapY >= 40 {
                    let y = max(a.minY, b.minY) + overlapY / 2
                    let selection = NSRect(x: b.maxX - 40, y: y - 20, width: 80, height: 40)
                    return (
                        first, second, selection,
                        NSPoint(x: a.minX + 20, y: y),
                        NSPoint(x: b.maxX - 20, y: y))
                }
                let overlapX = min(a.maxX, b.maxX) - max(a.minX, b.minX)
                if abs(a.maxY - b.minY) < 1, overlapX >= 40 {
                    let x = max(a.minX, b.minX) + overlapX / 2
                    let selection = NSRect(x: x - 20, y: a.maxY - 40, width: 40, height: 80)
                    return (
                        first, second, selection,
                        NSPoint(x: x, y: a.maxY - 20),
                        NSPoint(x: x, y: b.minY + 20))
                }
                if abs(b.maxY - a.minY) < 1, overlapX >= 40 {
                    let x = max(a.minX, b.minX) + overlapX / 2
                    let selection = NSRect(x: x - 20, y: b.maxY - 40, width: 40, height: 80)
                    return (
                        first, second, selection,
                        NSPoint(x: x, y: a.minY + 20),
                        NSPoint(x: x, y: b.maxY - 20))
                }
            }
        }
        return nil
    }

    private func dragSelection(
        targetFrame: NSRect,
        sourceFrame: NSRect,
        from start: NSPoint,
        to end: NSPoint
    ) throws -> NSRect {
        let target = OverlayWindowController(screen: try mainScreenOrSkip())
        let appDelegate = AppDelegate()
        target.overlayDelegate = appDelegate
        let targetWindow = try XCTUnwrap(NSApp.window(withWindowNumber: Int(target.windowNumber)))
        let targetView = try XCTUnwrap(overlayView(in: target))
        targetWindow.setFrame(targetFrame, display: false)
        targetWindow.makeKeyAndOrderFront(nil)
        targetWindow.makeFirstResponder(targetView)

        let sourceWindow = NSWindow(
            contentRect: sourceFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false)
        sourceWindow.orderFrontRegardless()
        defer {
            sourceWindow.orderOut(nil)
            appDelegate.overlayDidCancel(target)
            target.dismiss()
        }

        targetView.mouseDown(with: mouseEvent(.leftMouseDown, at: start, in: targetWindow))
        NSApp.sendEvent(mouseEvent(.leftMouseDragged, at: end, in: sourceWindow))
        NSApp.sendEvent(mouseEvent(.leftMouseUp, at: end, in: sourceWindow))
        return target.selectionRect
    }

    private func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1)!
    }
}

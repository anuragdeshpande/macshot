import AppKit
import XCTest

@MainActor
final class OutsideSelectionBlurTests: XCTestCase {

    private let width = 300
    private let height = 120

    private func contrastImage() -> NSImage {
        ImageProbe.makeImage(width: width, height: height) { context in
            context.setFillColor(NSColor.black.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 80, height: height))
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 80, y: 0, width: 100, height: height))
            context.setFillColor(NSColor.black.cgColor)
            context.fill(CGRect(x: 180, y: 0, width: 120, height: height))
        }
    }

    private func renderOverlay(
        image: NSImage,
        usesExternalScreenshotPreview: Bool,
        remoteSelectionRect: NSRect? = nil,
        glass: Bool = true,
        blur: Bool = true,
        shadowDisabled: Bool = false
    ) throws -> NSBitmapImageRep {
        let bounds = NSRect(x: 0, y: 0, width: width, height: height)
        let source = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let overlay = OverlayView(frame: bounds)
        overlay.screenshotImage = image
        overlay.usesExternalScreenshotPreview = usesExternalScreenshotPreview
        if let remoteSelectionRect {
            overlay.remoteSelectionRect = remoteSelectionRect
            overlay.remoteSelectionFullRect = remoteSelectionRect
        } else {
            overlay.applySelection(NSRect(x: 0, y: 0, width: 20, height: height))
        }

        let overlayBitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let graphics = NSGraphicsContext(bitmapImageRep: overlayBitmap)!

        withDefaults([
            "hideCaptureInstructions": true,
            "disableSelectionOutsideShadow": shadowDisabled,
            LiquidGlass.defaultsKey: glass,
            LiquidGlass.outsideBlurDefaultsKey: blur,
        ]) {
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = graphics
            if usesExternalScreenshotPreview {
                graphics.cgContext.clear(bounds)
            }
            overlay.draw(bounds)
        }

        guard usesExternalScreenshotPreview else { return overlayBitmap }

        let composite = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let compositeGraphics = NSGraphicsContext(bitmapImageRep: composite)!
        let overlayImage = try XCTUnwrap(overlayBitmap.cgImage)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = compositeGraphics
        compositeGraphics.cgContext.draw(source, in: bounds)
        compositeGraphics.cgContext.draw(overlayImage, in: bounds)
        return composite
    }

    func testBlurKeepsImageDimensionsAndSoftensHighContrastEdges() throws {
        let image = ImageProbe.makeImage(width: 80, height: 40) { context in
            context.setFillColor(NSColor.black.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 40, y: 0, width: 40, height: 40))
        }
        let source = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let blurred = try XCTUnwrap(OutsideSelectionBlur().image(for: source))
        let result = NSImage(cgImage: blurred, size: image.size)
        let edge = try XCTUnwrap(ImageProbe.pixelColor(result, x: 39, y: 20)?.usingColorSpace(.deviceRGB))

        XCTAssertEqual(blurred.width, source.width)
        XCTAssertEqual(blurred.height, source.height)
        XCTAssertGreaterThan(edge.redComponent, 0.05)
        XCTAssertLessThan(edge.redComponent, 0.95)
    }

    func testOverlayDrawBlursOutsideSelectionInInternalScreenshotMode() throws {
        try XCTSkipIf(!LiquidGlass.isAvailable, "Liquid Glass requires macOS 26")
        let bitmap = try renderOverlay(image: contrastImage(), usesExternalScreenshotPreview: false)
        let outsideEdge = try XCTUnwrap(bitmap.colorAt(x: 82, y: 60)?.usingColorSpace(.deviceRGB))

        XCTAssertLessThan(
            outsideEdge.redComponent,
            0.5,
            "The screenshot drawn by the overlay must be blurred outside the selected capture region."
        )
    }

    func testOverlayDrawBlursOutsideSelectionWithExternalScreenshotPreview() throws {
        try XCTSkipIf(!LiquidGlass.isAvailable, "Liquid Glass requires macOS 26")
        let bitmap = try renderOverlay(image: contrastImage(), usesExternalScreenshotPreview: true)
        let outsideEdge = try XCTUnwrap(bitmap.colorAt(x: 82, y: 60)?.usingColorSpace(.deviceRGB))
        XCTAssertLessThan(
            outsideEdge.redComponent,
            0.5,
            "The live screenshot preview must be blurred outside the selected capture region."
        )
    }

    func testOverlayDrawKeepsRemoteSelectionSharpInInternalScreenshotMode() throws {
        try XCTSkipIf(!LiquidGlass.isAvailable, "Liquid Glass requires macOS 26")
        let remoteSelection = NSRect(x: 30, y: 20, width: 100, height: 80)
        let bitmap = try renderOverlay(
            image: contrastImage(),
            usesExternalScreenshotPreview: false,
            remoteSelectionRect: remoteSelection
        )
        let selectedBlack = try XCTUnwrap(bitmap.colorAt(x: 75, y: 60)?.usingColorSpace(.deviceRGB))
        let selectedWhite = try XCTUnwrap(bitmap.colorAt(x: 85, y: 60)?.usingColorSpace(.deviceRGB))
        let outsideWhite = try XCTUnwrap(bitmap.colorAt(x: 178, y: 60)?.usingColorSpace(.deviceRGB))
        let outsideBlack = try XCTUnwrap(bitmap.colorAt(x: 182, y: 60)?.usingColorSpace(.deviceRGB))

        XCTAssertLessThan(selectedBlack.redComponent, 0.05, "The selected black pixel must remain sharp.")
        XCTAssertGreaterThan(selectedWhite.redComponent, 0.95, "The selected white pixel must remain sharp.")
        XCTAssertLessThan(
            abs(outsideWhite.redComponent - outsideBlack.redComponent),
            0.25,
            "The contrast edge outside the remote selection must be blurred."
        )
    }

    func testOverlayDrawKeepsRemoteSelectionSharpAndBlursOutsideExternalPreview() throws {
        try XCTSkipIf(!LiquidGlass.isAvailable, "Liquid Glass requires macOS 26")
        let remoteSelection = NSRect(x: 30, y: 20, width: 100, height: 80)
        let bitmap = try renderOverlay(
            image: contrastImage(),
            usesExternalScreenshotPreview: true,
            remoteSelectionRect: remoteSelection
        )
        let selectedBlack = try XCTUnwrap(bitmap.colorAt(x: 75, y: 60)?.usingColorSpace(.deviceRGB))
        let selectedWhite = try XCTUnwrap(bitmap.colorAt(x: 85, y: 60)?.usingColorSpace(.deviceRGB))
        let outsideWhite = try XCTUnwrap(bitmap.colorAt(x: 178, y: 60)?.usingColorSpace(.deviceRGB))
        let outsideBlack = try XCTUnwrap(bitmap.colorAt(x: 182, y: 60)?.usingColorSpace(.deviceRGB))

        XCTAssertLessThan(selectedBlack.redComponent, 0.05, "The selected black pixel must remain sharp.")
        XCTAssertGreaterThan(selectedWhite.redComponent, 0.95, "The selected white pixel must remain sharp.")
        XCTAssertLessThan(
            abs(outsideWhite.redComponent - outsideBlack.redComponent),
            0.25,
            "The live preview contrast edge outside the remote selection must be blurred."
        )
    }

    func testDefaultShadowKeepsOutsideEdgesSharp() throws {
        for external in [false, true] {
            for (glass, blur) in [(false, false), (false, true), (true, false)] {
                let bitmap = try renderOverlay(
                    image: contrastImage(), usesExternalScreenshotPreview: external, glass: glass, blur: blur)
                let black = try XCTUnwrap(bitmap.colorAt(x: 78, y: 60)?.usingColorSpace(.deviceRGB))
                let white = try XCTUnwrap(bitmap.colorAt(x: 82, y: 60)?.usingColorSpace(.deviceRGB))
                XCTAssertLessThan(black.redComponent, 0.05)
                XCTAssertEqual(white.redComponent, 0.55, accuracy: 0.06,
                               "the normal shadow must not blur the captured background")
            }
        }
    }

    func testDisabledShadowAlsoDisablesOutsideBlur() throws {
        let bitmap = try renderOverlay(
            image: contrastImage(), usesExternalScreenshotPreview: false, shadowDisabled: true)
        let black = try XCTUnwrap(bitmap.colorAt(x: 78, y: 60)?.usingColorSpace(.deviceRGB))
        let white = try XCTUnwrap(bitmap.colorAt(x: 82, y: 60)?.usingColorSpace(.deviceRGB))
        XCTAssertLessThan(black.redComponent, 0.05)
        XCTAssertGreaterThan(white.redComponent, 0.95)
    }
}

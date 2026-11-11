import AppKit
import XCTest

@MainActor
final class OutsideSelectionBlurTests: XCTestCase {

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
}

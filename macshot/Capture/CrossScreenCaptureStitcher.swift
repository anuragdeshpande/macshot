import AppKit

@MainActor
struct CrossScreenCaptureImage {
    let frame: NSRect
    let image: NSImage
}

@MainActor
enum CrossScreenCaptureStitcher {
    static func stitch(
        primarySelection: NSRect,
        primaryFrame: NSRect,
        primaryBackingScale: CGFloat,
        primaryImage: NSImage?,
        otherScreens: [CrossScreenCaptureImage]
    ) -> NSImage? {
        let globalRect = NSRect(
            x: primarySelection.origin.x + primaryFrame.origin.x,
            y: primarySelection.origin.y + primaryFrame.origin.y,
            width: primarySelection.width,
            height: primarySelection.height)

        let scale: CGFloat
        if let primaryImage,
           let cgImage = primaryImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            scale = CGFloat(cgImage.width) / primaryImage.size.width
        } else {
            scale = primaryBackingScale
        }

        let pixelWidth = Int(globalRect.width * scale)
        let pixelHeight = Int(globalRect.height * scale)
        let colorSpace: CGColorSpace
        if let primaryImage,
           let cgImage = primaryImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let sourceColorSpace = cgImage.colorSpace {
            colorSpace = sourceColorSpace
        } else {
            colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        }
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        context.scaleBy(x: scale, y: scale)

        let screens = primaryImage.map {
            [CrossScreenCaptureImage(frame: primaryFrame, image: $0)] + otherScreens
        } ?? otherScreens
        for screen in screens {
            let drawRect = NSRect(
                x: screen.frame.origin.x - globalRect.origin.x,
                y: screen.frame.origin.y - globalRect.origin.y,
                width: screen.frame.width,
                height: screen.frame.height)

            context.saveGState()
            context.clip(to: CGRect(x: 0, y: 0, width: globalRect.width, height: globalRect.height))
            let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext
            screen.image.draw(in: drawRect, from: .zero, operation: .copy, fraction: 1.0)
            NSGraphicsContext.restoreGraphicsState()
            context.restoreGState()
        }

        guard let cgImage = context.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: globalRect.size)
    }
}

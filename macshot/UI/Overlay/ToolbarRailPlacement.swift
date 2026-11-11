import AppKit

struct ToolbarRailFrames {
    let annotations: NSRect
    let options: NSRect
    let actions: NSRect

    static func place(
        around selection: NSRect,
        inside bounds: NSRect,
        annotationSize: NSSize,
        optionsSize: NSSize,
        actionSize: NSSize,
        margin: CGFloat = 4,
        gap: CGFloat = 6
    ) -> ToolbarRailFrames {
        func clampedOrigin(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
            max(lower, min(value, max(lower, upper)))
        }

        func xOrigin(for width: CGFloat, proposed: CGFloat) -> CGFloat {
            clampedOrigin(
                proposed,
                lower: bounds.minX + margin,
                upper: bounds.maxX - width - margin)
        }

        func yOrigin(for height: CGFloat, proposed: CGFloat) -> CGFloat {
            clampedOrigin(
                proposed,
                lower: bounds.minY + margin,
                upper: bounds.maxY - height - margin)
        }

        let groupWidth = optionsSize.width + (optionsSize.width > 0 ? gap : 0) + annotationSize.width
        let groupLeft = xOrigin(
            for: groupWidth,
            proposed: selection.minX - groupWidth - gap)
        let optionsX = groupLeft
        let annotationX = groupLeft + optionsSize.width + (optionsSize.width > 0 ? gap : 0)
        let annotationY = yOrigin(
            for: annotationSize.height,
            proposed: selection.midY - annotationSize.height / 2)
        let annotationFrame = NSRect(origin: NSPoint(x: annotationX, y: annotationY), size: annotationSize)

        let optionsY = yOrigin(
            for: optionsSize.height,
            proposed: annotationFrame.midY - optionsSize.height / 2)
        let optionsFrame = NSRect(origin: NSPoint(x: optionsX, y: optionsY), size: optionsSize)

        let actionX = xOrigin(
            for: actionSize.width,
            proposed: selection.maxX + gap)
        let actionY = yOrigin(
            for: actionSize.height,
            proposed: selection.midY - actionSize.height / 2)
        let actionFrame = NSRect(origin: NSPoint(x: actionX, y: actionY), size: actionSize)

        return ToolbarRailFrames(annotations: annotationFrame, options: optionsFrame, actions: actionFrame)
    }
}

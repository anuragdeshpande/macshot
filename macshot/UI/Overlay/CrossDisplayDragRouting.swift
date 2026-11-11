import AppKit

enum CrossDisplayDragRouting {
    static func pointInTargetWindow(
        _ point: NSPoint,
        sourceWindowFrame: NSRect,
        targetWindowFrame: NSRect
    ) -> NSPoint {
        NSPoint(
            x: sourceWindowFrame.origin.x + point.x - targetWindowFrame.origin.x,
            y: sourceWindowFrame.origin.y + point.y - targetWindowFrame.origin.y)
    }
}

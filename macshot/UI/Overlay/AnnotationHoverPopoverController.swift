import AppKit

@MainActor
final class ToolOptionsPopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let optionsView: ToolOptionsRowView
    var onClose: (() -> Void)?
    private var didFinish = false

    var contentSize: NSSize { popover.contentSize }
    var optionsRowViewForTesting: ToolOptionsRowView { optionsView }

    init(overlayView: OverlayView, tool: AnnotationTool, title: String, annotation: Annotation? = nil) {
        let optionsView = ToolOptionsRowView()
        self.optionsView = optionsView
        super.init()

        optionsView.overlayView = overlayView
        optionsView.orientation = .vertical
        optionsView.hostedInGlassPanel = true
        if let annotation {
            optionsView.rebuild(forAnnotation: annotation)
        } else {
            optionsView.rebuild(for: tool)
        }
        optionsView.layer?.backgroundColor = NSColor.clear.cgColor
        optionsView.layer?.cornerRadius = 0

        let rowHeight = optionsView.frame.height
        let visibleOptionsHeight = min(rowHeight, 360)
        let width = max(180, optionsView.frame.width + 24)
        let size = NSSize(width: width, height: visibleOptionsHeight + 50)
        let contentView = NSView(frame: NSRect(origin: .zero, size: size))
        contentView.appearance = ToolbarLayout.appearance

        let titleField = NSTextField(labelWithString: title)
        titleField.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        titleField.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.75)
        titleField.frame = NSRect(x: 12, y: size.height - 30, width: width - 24, height: 18)
        contentView.addSubview(titleField)

        let scrollView = NSScrollView(
            frame: NSRect(x: 12, y: 12, width: width - 24, height: visibleOptionsHeight))
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = rowHeight > visibleOptionsHeight
        optionsView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: width - 24, height: rowHeight))
        scrollView.documentView = optionsView
        contentView.addSubview(scrollView)

        let contentController = NSViewController()
        contentController.view = contentView
        popover.contentViewController = contentController
        popover.contentSize = size
        popover.behavior = .transient
        popover.delegate = self
    }

    func show(relativeTo rect: NSRect, of view: NSView, preferredEdge: NSRectEdge = .maxX) {
        popover.show(relativeTo: rect, of: view, preferredEdge: preferredEdge)
    }

    func dismiss() {
        guard popover.isShown else {
            finish()
            return
        }
        popover.close()
        finish()
    }

    func containsScreenPoint(_ point: NSPoint) -> Bool {
        popover.contentViewController?.view.window?.frame.contains(point) == true
    }

    func popoverDidClose(_ notification: Notification) {
        finish()
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        optionsView.clearEditingAnnotation()
        onClose?()
    }
}

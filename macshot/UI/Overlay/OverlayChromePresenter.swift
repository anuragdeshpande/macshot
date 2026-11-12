import Cocoa

/// Manages hosting a toolbar or chrome surface (`ToolbarStripView`,
/// `ToolOptionsRowView`, `ResolutionBoxView`, `PreSelectionPresetButton`) in
/// either the Default flat UI or a native Liquid Glass container.
///
/// - Default appearance: the content view stays a direct subview of the overlay
///   (or `chromeParentView` in the detached editor) and draws its solid fill.
/// - Liquid Glass appearance: the content view is hosted inside a native
///   `NSGlassEffectView`. Cross-display capture rails use a separate panel so
///   they are not clipped to the originating overlay window.
final class OverlayChromePresenter {

    let cornerRadius: CGFloat
    let keyCapable: Bool
    private(set) var glassHost: NSView?
    private var savedAutoresizingMask: NSView.AutoresizingMask = []
    private var floatingPanel: NSPanel?
    private var floatingPanelOrdered = false
    private var lastOverlayRect: NSRect = .zero

    init(cornerRadius: CGFloat = 10, keyCapable: Bool = false) {
        self.cornerRadius = cornerRadius
        self.keyCapable = keyCapable
    }

    var hasPanel: Bool { glassHost != nil }

    /// Present `content` at `overlayRect` within `overlayView` (or `inlineHostParent` in editor mode).
    func present(_ content: ChromeContent & NSView, overlayRect: NSRect,
                 visible: Bool, glass: Bool, in overlayView: NSView,
                 inlineHostParent: NSView? = nil, cornerRadius overrideCornerRadius: CGFloat? = nil,
                 floating: Bool = false) {
        let inlineParent = inlineHostParent ?? overlayView
        let panelCornerRadius = overrideCornerRadius ?? cornerRadius
        lastOverlayRect = overlayRect
        guard visible, overlayRect.width > 1, overlayRect.height > 1 else {
            reclaim(content, to: inlineParent)
            return
        }

        let targetParent: NSView
        let targetRect: NSRect
        if floating, let owner = overlayView.window {
            let panel = floatingPanel ?? makeFloatingPanel(owner: owner)
            let screenRect = owner.convertToScreen(overlayView.convert(overlayRect, to: nil))
            if panel.frame != screenRect { panel.setFrame(screenRect, display: false) }
            guard let panelContent = panel.contentView as? CaptureChromePanelView else {
                preconditionFailure("Capture chrome panel is missing its content view")
            }
            panelContent.chromeContent = content
            targetParent = panelContent
            targetRect = NSRect(origin: .zero, size: overlayRect.size)
        } else {
            if floatingPanel != nil {
                reclaim(content, to: inlineParent)
            }
            targetParent = inlineParent
            targetRect = overlayRect
        }

        if glass, glassHost == nil {
            savedAutoresizingMask = content.autoresizingMask
            content.removeFromSuperview()
            if let host = LiquidGlass.host(content, frame: targetRect, cornerRadius: panelCornerRadius) {
                content.hostedInGlassPanel = true
                host.autoresizingMask = savedAutoresizingMask
                targetParent.addSubview(host)
                glassHost = host
            } else {
                content.hostedInGlassPanel = false
                content.frame = targetRect
                content.autoresizingMask = savedAutoresizingMask
                targetParent.addSubview(content)
            }
        }

        if !glass, let host = glassHost {
            content.hostedInGlassPanel = false
            content.removeFromSuperview()
            content.autoresizingMask = savedAutoresizingMask
            host.removeFromSuperview()
            glassHost = nil
        }

        if let host = glassHost {
            if host.superview !== targetParent {
                targetParent.addSubview(host)
            }
            host.frame = targetRect
            host.isHidden = false
            if #available(macOS 26.0, *), let glassView = host as? NSGlassEffectView {
                glassView.cornerRadius = panelCornerRadius
                glassView.contentView?.frame = glassView.bounds
            }
        } else {
            if content.superview !== targetParent {
                targetParent.addSubview(content)
            }
            content.frame = targetRect
        }

        if let panel = floatingPanel {
            if overlayView.window?.isVisible == true {
                if !floatingPanelOrdered || !panel.isVisible {
                    panel.orderFrontRegardless()
                    floatingPanelOrdered = true
                }
            } else {
                panel.orderOut(nil)
                floatingPanelOrdered = false
            }
        }
    }

    /// Tear down the glass host (if any), returning `content` to `parentView`.
    func reclaim(_ content: (ChromeContent & NSView)?, to parentView: NSView) {
        guard glassHost != nil || floatingPanel != nil else { return }
        let restoredFrame = floatingPanel == nil ? glassHost?.frame ?? lastOverlayRect : lastOverlayRect
        if let content {
            content.hostedInGlassPanel = false
            content.removeFromSuperview()
            content.frame = restoredFrame
            if glassHost != nil { content.autoresizingMask = savedAutoresizingMask }
            parentView.addSubview(content)
        }
        glassHost?.removeFromSuperview()
        glassHost = nil
        closeFloatingPanel()
    }

    func teardown() {
        glassHost?.removeFromSuperview()
        glassHost = nil
        closeFloatingPanel()
    }

    private func makeFloatingPanel(owner: NSWindow) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = CaptureChromePanelView(frame: .zero)
        owner.addChildWindow(panel, ordered: .above)
        panel.level = NSWindow.Level(owner.level.rawValue + 1)
        floatingPanel = panel
        return panel
    }

    private func closeFloatingPanel() {
        guard let panel = floatingPanel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        panel.close()
        floatingPanel = nil
        floatingPanelOrdered = false
    }
}

private final class CaptureChromePanelView: NSView {
    weak var chromeContent: NSView?

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if let content = chromeContent, !content.isHidden, let parent = content.superview,
           let hit = content.hitTest(parent.convert(local, from: self)) {
            return hit
        }
        return super.hitTest(point)
    }
}

final class CaptureRailTooltip {
    private var panel: NSPanel?
    private let content = TooltipBackgroundView(frame: .zero)

    func show(_ text: String, in frame: NSRect, owner: NSWindow) {
        let panel: NSPanel
        let isNew: Bool
        if let existing = self.panel, existing.parent === owner {
            panel = existing
            isNew = false
        } else {
            teardown()
            panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = true
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.animationBehavior = .none
            panel.contentView = content
            owner.addChildWindow(panel, ordered: .above)
            panel.level = NSWindow.Level(owner.level.rawValue + 2)
            self.panel = panel
            isNew = true
        }
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        content.text = text
        content.needsDisplay = true
        if isNew || !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func teardown() {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        panel.close()
        self.panel = nil
    }
}

final class TooltipBackgroundView: NSView {
    var text = ""

    override func draw(_ dirtyRect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: ToolbarLayout.iconColor,
        ]
        if LiquidGlass.isEnabled {
            NSColor(white: 0.1, alpha: 0.70).setFill()
        } else {
            ToolbarLayout.bgColor.setFill()
        }
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        let pad: CGFloat = 6
        (text as NSString).draw(at: NSPoint(x: pad, y: pad / 2), withAttributes: attrs)
    }
}

/// Toolbar surfaces that can be hosted in a glass chrome container.
/// When hosted, the surface must not draw its own solid background (the glass provides it).
protocol ChromeContent: AnyObject {
    var hostedInGlassPanel: Bool { get set }
}

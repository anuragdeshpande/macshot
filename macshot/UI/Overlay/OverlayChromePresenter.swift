import Cocoa

/// Manages hosting a toolbar or chrome surface (`ToolbarStripView`,
/// `ToolOptionsRowView`, `ResolutionBoxView`, `PreSelectionPresetButton`) in
/// either the Default flat UI or a native Liquid Glass container.
///
/// - Default appearance: the content view stays a direct subview of the overlay
///   (or `chromeParentView` in the detached editor) and draws its solid fill.
/// - Liquid Glass appearance: the content view is hosted inside a native
///   `NSGlassEffectView` directly in the view hierarchy (in both Capture Overlay
///   mode and Detached Editor mode). When hosted, `content.hostedInGlassPanel`
///   is true so it skips its own solid background fill.
final class OverlayChromePresenter {

    let cornerRadius: CGFloat
    let keyCapable: Bool
    private(set) var glassHost: NSView?
    private var savedAutoresizingMask: NSView.AutoresizingMask = []

    init(cornerRadius: CGFloat = 10, keyCapable: Bool = false) {
        self.cornerRadius = cornerRadius
        self.keyCapable = keyCapable
    }

    var hasPanel: Bool { glassHost != nil }

    /// Present `content` at `overlayRect` within `overlayView` (or `inlineHostParent` in editor mode).
    func present(_ content: ChromeContent & NSView, overlayRect: NSRect,
                 visible: Bool, glass: Bool, in overlayView: NSView,
                 inlineHostParent: NSView? = nil, cornerRadius overrideCornerRadius: CGFloat? = nil) {
        let targetParent = inlineHostParent ?? overlayView
        let panelCornerRadius = overrideCornerRadius ?? cornerRadius
        guard glass, visible, overlayRect.width > 1, overlayRect.height > 1 else {
            reclaim(content, to: targetParent)
            return
        }

        content.hostedInGlassPanel = true

        if glassHost == nil {
            savedAutoresizingMask = content.autoresizingMask
            content.removeFromSuperview()
            if let host = LiquidGlass.host(content, frame: overlayRect, cornerRadius: panelCornerRadius) {
                host.autoresizingMask = savedAutoresizingMask
                targetParent.addSubview(host)
                glassHost = host
            } else {
                content.frame = overlayRect
                content.autoresizingMask = savedAutoresizingMask
                targetParent.addSubview(content)
            }
        }

        if let host = glassHost {
            if host.superview !== targetParent {
                targetParent.addSubview(host)
            }
            host.frame = overlayRect
            host.isHidden = false
            if #available(macOS 26.0, *), let glassView = host as? NSGlassEffectView {
                glassView.cornerRadius = panelCornerRadius
                glassView.contentView?.frame = glassView.bounds
            }
        }
    }

    /// Tear down the glass host (if any), returning `content` to `parentView`.
    func reclaim(_ content: (ChromeContent & NSView)?, to parentView: NSView) {
        guard let host = glassHost else { return }
        let restoredFrame = host.frame
        if let content {
            content.hostedInGlassPanel = false
            content.removeFromSuperview()
            content.frame = restoredFrame
            content.autoresizingMask = savedAutoresizingMask
            parentView.addSubview(content)
        }
        host.removeFromSuperview()
        glassHost = nil
    }

    func teardown() {
        glassHost?.removeFromSuperview()
        glassHost = nil
    }
}

/// Toolbar surfaces that can be hosted in a glass chrome container.
/// When hosted, the surface must not draw its own solid background (the glass provides it).
protocol ChromeContent: AnyObject {
    var hostedInGlassPanel: Bool { get set }
}

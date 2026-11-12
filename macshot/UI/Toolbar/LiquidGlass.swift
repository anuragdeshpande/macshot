import Cocoa

/// Liquid Glass appearance support (macOS 26 Tahoe+).
///
/// When the user selects "Liquid Glass" under Settings → General → Appearance,
/// toolbars, sub-tool option rows, popovers, and HUDs render their container
/// background as Apple's native `NSGlassEffectView` material instead of a solid
/// fill — while keeping the user's configured Accent and Icon colors.
///
/// Uses the standard `.regular` glass style so `NSGlassEffectView` automatically
/// follows the user's macOS System Settings configuration for glass frostedness
/// and transparency.
///
/// IMPORTANT: `NSGlassEffectView` only renders the glass for the view assigned to
/// its `contentView`. Glass added merely as a sibling background does nothing.
/// So a glass surface must HOST its controls inside the glass `contentView`.
enum LiquidGlass {

    enum Style: Int {
        case `default` = 0
        case liquidGlass = 1
    }

    static let defaultsKey = "liquidGlassTheme"
    static let outsideBlurDefaultsKey = "liquidGlassOutsideBlur"

    /// True only on macOS 26+ where the native `NSGlassEffectView` API exists.
    static var isAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// True when the user has selected Liquid Glass AND the API is available.
    static var isEnabled: Bool {
        isAvailable && UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static var prefersOutsideBlur: Bool {
        UserDefaults.standard.object(forKey: outsideBlurDefaultsKey) as? Bool ?? true
    }

    /// True when Liquid Glass is enabled and the user prefers blur outside the selection.
    static var showsOutsideBlur: Bool {
        isEnabled && prefersOutsideBlur
    }

    static var currentStyle: Style {
        isEnabled ? .liquidGlass : .default
    }

    static func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: defaultsKey)
    }

    static func setStyle(_ style: Style) {
        setEnabled(style == .liquidGlass)
    }

    /// Container corner radius (concentric with inner controls when glass is active).
    static var cornerRadius: CGFloat {
        isEnabled ? 10 : ToolbarLayout.cornerRadius
    }

    /// Button corner radius inside a toolbar strip.
    static var buttonCornerRadius: CGFloat {
        isEnabled ? 7 : 6
    }

    /// Create a glass host view that embeds `content` as its `contentView`, or
    /// `nil` when glass isn't enabled/available (caller keeps its solid bg).
    /// The returned host should be placed where the solid background view used
    /// to be; `content` (carrying the controls) is rendered on the glass.
    static func host(_ content: NSView, frame: NSRect, cornerRadius: CGFloat) -> NSView? {
        guard isEnabled else { return nil }
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.cornerRadius = cornerRadius
            // `.regular` is the standard system Liquid Glass material that respects
            // the user's macOS System Settings for glass frostedness / transparency.
            glass.style = .regular
            content.frame = glass.bounds
            content.autoresizingMask = [.width, .height]
            glass.contentView = content
            return glass
        }
        return nil
    }

    /// Keep the glass host and its `contentView` aligned with `owner`.
    static func syncHost(_ host: NSView?, in owner: NSView) {
        guard let host else { return }
        host.frame = owner.bounds
        if #available(macOS 26.0, *), let glass = host as? NSGlassEffectView {
            glass.contentView?.frame = glass.bounds
        }
    }
}

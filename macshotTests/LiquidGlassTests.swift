import AppKit
import XCTest

final class LiquidGlassTests: XCTestCase {

    private var savedSetting: Any?
    private var savedOutsideBlurSetting: Any?

    override func setUp() {
        super.setUp()
        savedSetting = UserDefaults.standard.object(forKey: LiquidGlass.defaultsKey)
        savedOutsideBlurSetting = UserDefaults.standard.object(forKey: LiquidGlass.outsideBlurDefaultsKey)
    }

    override func tearDown() {
        if let savedSetting {
            UserDefaults.standard.set(savedSetting, forKey: LiquidGlass.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: LiquidGlass.defaultsKey)
        }
        if let savedOutsideBlurSetting {
            UserDefaults.standard.set(savedOutsideBlurSetting, forKey: LiquidGlass.outsideBlurDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: LiquidGlass.outsideBlurDefaultsKey)
        }
        super.tearDown()
    }

    func testOutsideBlurDefaultsOnAndPersistsAcrossAppearanceChanges() {
        UserDefaults.standard.removeObject(forKey: LiquidGlass.outsideBlurDefaultsKey)
        XCTAssertTrue(LiquidGlass.prefersOutsideBlur)

        LiquidGlass.setStyle(.default)
        XCTAssertFalse(LiquidGlass.showsOutsideBlur)

        guard LiquidGlass.isAvailable else { return }

        LiquidGlass.setStyle(.liquidGlass)
        XCTAssertTrue(LiquidGlass.showsOutsideBlur)

        UserDefaults.standard.set(false, forKey: LiquidGlass.outsideBlurDefaultsKey)
        XCTAssertFalse(LiquidGlass.showsOutsideBlur)

        LiquidGlass.setStyle(.default)
        XCTAssertFalse(LiquidGlass.prefersOutsideBlur)
        LiquidGlass.setStyle(.liquidGlass)
        XCTAssertFalse(LiquidGlass.showsOutsideBlur)
        XCTAssertEqual(
            UserDefaults.standard.object(forKey: LiquidGlass.outsideBlurDefaultsKey) as? Bool,
            false
        )
    }

    @MainActor
    func testLiquidGlassToggleAndHostUsesSystemRegularStyle() throws {
        LiquidGlass.setStyle(.default)
        XCTAssertFalse(LiquidGlass.isEnabled)
        XCTAssertEqual(LiquidGlass.currentStyle, .default)

        let dummy = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 36))
        XCTAssertNil(LiquidGlass.host(dummy, frame: dummy.bounds, cornerRadius: 10))

        guard LiquidGlass.isAvailable else { return }

        LiquidGlass.setStyle(.liquidGlass)
        XCTAssertTrue(LiquidGlass.isEnabled)
        XCTAssertEqual(LiquidGlass.currentStyle, .liquidGlass)

        let host = try XCTUnwrap(LiquidGlass.host(dummy, frame: dummy.bounds, cornerRadius: 10))
        if #available(macOS 26.0, *) {
            let glass = try XCTUnwrap(host as? NSGlassEffectView)
            XCTAssertEqual(glass.style, .regular)
            XCTAssertEqual(glass.cornerRadius, 10)
            XCTAssertTrue(glass.contentView === dummy)
        }
    }

    @MainActor
    func testOverlayChromePresenterInlineAndReclaim() throws {
        guard LiquidGlass.isAvailable else { return }

        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let strip = ToolbarStripView(orientation: .horizontal)
        strip.setButtons([
            ToolbarButton(action: .tool(.arrow), sfSymbol: "arrow.up.right", tooltip: "Arrow")
        ])
        parent.addSubview(strip)

        let presenter = OverlayChromePresenter(cornerRadius: 10)
        let targetRect = NSRect(x: 50, y: 20, width: strip.frame.width, height: strip.frame.height)

        LiquidGlass.setStyle(.liquidGlass)
        presenter.present(
            strip,
            overlayRect: targetRect,
            visible: true,
            glass: true,
            in: parent,
            inlineHostParent: parent
        )
        XCTAssertTrue(presenter.hasPanel)
        XCTAssertTrue(strip.hostedInGlassPanel)

        LiquidGlass.setStyle(.default)
        presenter.present(
            strip,
            overlayRect: targetRect,
            visible: true,
            glass: false,
            in: parent,
            inlineHostParent: parent
        )
        XCTAssertFalse(presenter.hasPanel)
        XCTAssertFalse(strip.hostedInGlassPanel)
        XCTAssertTrue(strip.superview === parent)
        XCTAssertEqual(strip.frame, targetRect)
    }

    @MainActor
    func testOverlayModeGlassHostPresentation() throws {
        guard LiquidGlass.isAvailable else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = NSWindow.Level(257)
        let view = OverlayView()
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        window.contentView = view
        window.orderFront(nil)

        LiquidGlass.setStyle(.liquidGlass)
        view.applySelection(NSRect(x: 100, y: 100, width: 400, height: 300))
        view.showToolbars = true

        if #available(macOS 26.0, *) {
            let glassViews = view.subviews.compactMap { $0 as? NSGlassEffectView }
            XCTAssertGreaterThanOrEqual(glassViews.count, 2, "Expected at least 2 NSGlassEffectView hosts (bottom and right strips), got: \(glassViews)")
        }
    }
}

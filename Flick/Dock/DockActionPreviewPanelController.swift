import AppKit
import SwiftUI

/// Where the user has the Dock docked — read straight from the same preference the Dock
/// itself reads, so this always matches reality instead of guessing from screen geometry
/// (which gets ambiguous with auto-hide, multiple displays, etc).
private enum DockEdge {
    case bottom, left, right

    static var current: DockEdge {
        switch CFPreferencesCopyAppValue("orientation" as CFString, "com.apple.dock" as CFString) as? String {
        case "left": return .left
        case "right": return .right
        default: return .bottom
        }
    }
}

/// Hosts `DockActionPreviewView` in a borderless, click-through panel positioned just off
/// a Dock icon's edge — above it if the Dock sits at the bottom of the screen, or to its
/// side if the user docked it to the left or right — updated live while the gesture is in
/// progress.
final class DockActionPreviewPanelController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<ActionBadgeView>?
    private var lastFrame: NSRect?
    private var lastGlyph: ActionBadgeView.Glyph?
    private var isVisible = false

    /// Gap left between the Dock icon's edge and the badge.
    private static let gap: CGFloat = 10
    /// Padding around the badge itself, so its soft shadow has room to render without
    /// being clipped by the panel's bounds.
    private static let shadowMargin: CGFloat = 20
    private static let size = CGSize(
        width: ActionBadgeView.diameter + shadowMargin * 2,
        height: ActionBadgeView.diameter + shadowMargin * 2
    )

    /// Synchronous by design: the caller (`FlickController`'s single coalesced preview
    /// dispatcher — see its `schedulePreviewUpdate`) already guarantees this only ever
    /// runs once per fresh run-loop turn, with every other preview panel's `hide`/`show`
    /// for that same turn applied right alongside it in one atomic decision. Deferring
    /// *again* in here, independently per panel, was tried before and made things worse:
    /// under a fast gesture, each panel's own independently-queued turn could drain in a
    /// different order than intended, letting two panels both end up visible at once.
    ///
    /// - Parameter dockIconFrame: the icon's frame in AppKit screen coordinates.
    func show(glyph: ActionBadgeView.Glyph, near dockIconFrame: NSRect) {
        let frame = NSRect(origin: origin(besides: dockIconFrame), size: Self.size)

        if let panel, let hostingView {
            // Multitouch-driven updates can arrive 60-120×/second. Re-applying identical
            // content/frame, and even just re-ordering an *already-frontmost* panel, that
            // often was enough to flood AppKit's constraint/display-cycle pass and trigger
            // a "needing another Update Constraints" fault/crash — so every call here is a
            // strict no-op unless something actually changed.
            if glyph != lastGlyph {
                lastGlyph = glyph
                hostingView.rootView = ActionBadgeView(glyph: glyph)
            }
            if frame != lastFrame {
                lastFrame = frame
                panel.setFrame(frame, display: false)
            }
            if !isVisible {
                isVisible = true
                panel.orderFrontRegardless()
            }
            return
        }
        lastFrame = frame
        lastGlyph = glyph
        isVisible = true
        let rootView = ActionBadgeView(glyph: glyph)

        let hostingView = NSHostingView(rootView: rootView)
        // Without this, NSHostingView tries to auto-size the panel to its SwiftUI
        // content's ideal size, fighting our explicit `setFrame` calls above.
        hostingView.sizingOptions = []
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The badge draws its own shadow (see `DockActionPreviewView`); a second,
        // AppKit-layer window shadow on top of that just looks like a smudge.
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.contentView = hostingView
        panel.orderFrontRegardless()
        self.panel = panel
        self.hostingView = hostingView
    }

    /// See `show`'s doc comment — synchronous for the same reason.
    func hide() {
        guard isVisible else { return }
        isVisible = false
        panel?.orderOut(nil)
    }

    /// Where the badge sits relative to the Dock icon, depending on which edge of the
    /// screen the user's Dock is docked to.
    private func origin(besides dockIconFrame: NSRect) -> NSPoint {
        switch DockEdge.current {
        case .bottom:
            return NSPoint(x: dockIconFrame.midX - Self.size.width / 2, y: dockIconFrame.maxY + Self.gap)
        case .left:
            return NSPoint(x: dockIconFrame.maxX + Self.gap, y: dockIconFrame.midY - Self.size.height / 2)
        case .right:
            return NSPoint(x: dockIconFrame.minX - Self.gap - Self.size.width, y: dockIconFrame.midY - Self.size.height / 2)
        }
    }
}

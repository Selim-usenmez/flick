import AppKit
import SwiftUI

/// Hosts `ActionBadgeView` in a small, click-through panel that floats near the cursor
/// while a title-bar pinch/swipe gesture is resolving to a traffic-light action (close,
/// minimize, maximize) — mirrors `SnapPreviewPanelController`'s cursor-side placement, but
/// shows a colored badge instead of a mini-screen rectangle, since none of those three
/// actions resize the window into a region worth previewing.
final class WindowActionBadgePanelController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<ActionBadgeView>?
    private var lastFrame: NSRect?
    private var lastGlyph: ActionBadgeView.Glyph?
    private var isVisible = false

    /// Padding around the badge itself, so its soft shadow has room to render without
    /// being clipped by the panel's bounds.
    private static let shadowMargin: CGFloat = 20
    private static let size = CGSize(
        width: ActionBadgeView.diameter + shadowMargin * 2,
        height: ActionBadgeView.diameter + shadowMargin * 2
    )
    private static let cursorGap: CGFloat = 20

    /// - Parameter cursor: current cursor position, in AppKit screen coordinates (e.g.
    ///   `NSEvent.mouseLocation`).
    func show(glyph: ActionBadgeView.Glyph, near cursor: NSPoint) {
        // Deferred a full run-loop turn — see `DockActionPreviewPanelController.show` for
        // why: reassigning `hostingView.rootView` (or any panel frame/order change)
        // synchronously, nested inside an AppKit display-cycle pass already underway, is
        // what causes the "needing another Update Constraints" fault this app has hit
        // before. `DispatchQueue.main.async` from the main thread preserves call order
        // relative to other `show`/`hide` calls, so the no-op checks below still see
        // consistent state.
        DispatchQueue.main.async { [self] in
            let frame = Self.panelFrame(near: cursor)

            if let panel, let hostingView {
                // Multitouch-driven updates can arrive 60-120×/second — every call here
                // is a strict no-op unless something actually changed, for the same
                // "don't flood the display cycle" reason as the other preview panels.
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
                    fadeIn(panel)
                }
                return
            }

            lastFrame = frame
            lastGlyph = glyph
            isVisible = true

            let hostingView = NSHostingView(rootView: ActionBadgeView(glyph: glyph))
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
            // The badge draws its own shadow (see `ActionBadgeView`); a second,
            // AppKit-layer window shadow on top of that just looks like a smudge.
            panel.hasShadow = false
            panel.level = .floating
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.contentView = hostingView
            fadeIn(panel)
            self.panel = panel
            self.hostingView = hostingView
        }
    }

    func hide() {
        // See the comment in `show` — deferred for the same re-entrancy reason, and to
        // keep ordering consistent with `show`'s own deferred calls.
        DispatchQueue.main.async { [self] in
            guard isVisible else { return }
            isVisible = false
            panel?.orderOut(nil)
        }
    }

    /// Positions the badge to the right of the cursor, flipping to the left if that would
    /// run off the edge of whichever screen the cursor is currently on — same behavior as
    /// `SnapPreviewPanelController.panelFrame(near:)`.
    private static func panelFrame(near cursor: NSPoint) -> NSRect {
        let screenFrame = NSScreen.screens.first { $0.frame.contains(cursor) }?.frame ?? NSScreen.main?.frame ?? .zero
        var origin = NSPoint(x: cursor.x + cursorGap, y: cursor.y - size.height / 2)
        if origin.x + size.width > screenFrame.maxX {
            origin.x = cursor.x - cursorGap - size.width
        }
        origin.y = min(max(origin.y, screenFrame.minY), screenFrame.maxY - size.height)
        return NSRect(origin: origin, size: size)
    }

    /// A quick, subtle fade-in so the badge doesn't just pop into existence — order-in is
    /// one-directional and never races `hide()`'s (unanimated, immediate) `orderOut`.
    private func fadeIn(_ panel: NSPanel) {
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }
}

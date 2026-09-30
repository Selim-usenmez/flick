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

    /// - Parameter dockIconFrame: the icon's frame in AppKit screen coordinates.
    func show(glyph: ActionBadgeView.Glyph, near dockIconFrame: NSRect) {
        // Deferred a full run-loop turn, deliberately: reassigning `hostingView.rootView`
        // (below) can land *while AppKit is already mid-layout* for this same view —
        // e.g. right as a gesture ends and `hide()`'s `orderOut` triggers a display-cycle
        // flush in the same tick a content change was requested. SwiftUI's size
        // recompute for the new `rootView` then calls `setNeedsUpdate()` back on the very
        // `NSHostingView` AppKit is already running `updateConstraints()` for, which AppKit
        // treats as illegal re-entrancy and crashes with "needing another Update
        // Constraints" pass. Hopping onto a fresh main-queue turn guarantees this never
        // executes nested inside another display pass. `DispatchQueue.main.async` from the
        // main thread preserves call order relative to other `show`/`hide` calls, so the
        // no-op checks below still see consistent state.
        DispatchQueue.main.async { [self] in
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
                    fadeIn(panel)
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

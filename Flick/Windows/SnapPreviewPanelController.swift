import AppKit
import SwiftUI

/// Hosts `SnapPreviewView` in a small, click-through panel that floats near the cursor
/// while a window-snap gesture is in progress, instead of a full-size highlight over the
/// actual target region — mirrors Swish's floating mini-preview.
final class SnapPreviewPanelController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<SnapPreviewView>?
    private var lastFrame: NSRect?
    private var lastRegion: CGRect?
    private var isVisible = false

    private static let size = SnapPreviewView.size
    private static let cursorGap: CGFloat = 20

    /// - Parameters:
    ///   - region: target snap region as a fraction (0...1) of the screen, top-left origin.
    ///   - cursor: current cursor position, in AppKit screen coordinates (e.g.
    ///     `NSEvent.mouseLocation`).
    func show(region: CGRect, near cursor: NSPoint) {
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
                // Multitouch/scroll-driven updates can arrive 60-120×/second — every call
                // here is a strict no-op unless something actually changed, for the same
                // "don't flood the display cycle" reason as the Dock pill panel.
                if region != lastRegion {
                    lastRegion = region
                    hostingView.rootView = SnapPreviewView(region: region)
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
            lastRegion = region
            isVisible = true

            let hostingView = NSHostingView(rootView: SnapPreviewView(region: region))
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
            // The mini-screen draws its own shadow (see `SnapPreviewView`).
            panel.hasShadow = false
            panel.level = .floating
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.contentView = hostingView
            panel.orderFrontRegardless()
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

    /// Positions the preview to the right of the cursor, flipping to the left if that
    /// would run off the edge of whichever screen the cursor is currently on.
    private static func panelFrame(near cursor: NSPoint) -> NSRect {
        let screenFrame = NSScreen.screens.first { $0.frame.contains(cursor) }?.frame ?? NSScreen.main?.frame ?? .zero
        var origin = NSPoint(x: cursor.x + cursorGap, y: cursor.y - size.height / 2)
        if origin.x + size.width > screenFrame.maxX {
            origin.x = cursor.x - cursorGap - size.width
        }
        origin.y = min(max(origin.y, screenFrame.minY), screenFrame.maxY - size.height)
        return NSRect(origin: origin, size: size)
    }
}

import AppKit
import SwiftUI

/// Hosts `DockActionPreviewView` in a borderless, click-through panel positioned just above
/// a Dock icon, updated live while the gesture is in progress.
final class DockActionPreviewPanelController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<DockActionPreviewView>?
    private var lastFrame: NSRect?
    private var lastImage: String?
    private var lastTint: Color?
    private var isVisible = false

    private static let size = CGSize(width: 64, height: 64)

    /// - Parameter dockIconFrame: the icon's frame in AppKit screen coordinates.
    func show(systemImage: String, tint: Color, above dockIconFrame: NSRect) {
        // Deferred a full run-loop turn, deliberately: reassigning `hostingView.rootView`
        // (below) can land *while AppKit is already mid-layout* for this same view —
        // e.g. right as a gesture ends and `hide()`'s `orderOut` triggers a display-cycle
        // flush in the same tick a content change was requested. SwiftUI's size
        // recompute for the new `rootView` then calls `setNeedsUpdate()` back on the very
        // `NSHostingView` AppKit is already running `updateConstraints()` for, which AppKit
        // treats as illegal re-entrancy and crashes with "needing another Update
        // Constraints pass". Hopping onto a fresh main-queue turn guarantees this never
        // executes nested inside another display pass. `DispatchQueue.main.async` from the
        // main thread preserves call order relative to other `show`/`hide` calls, so the
        // no-op checks below still see consistent state.
        DispatchQueue.main.async { [self] in
            let origin = NSPoint(x: dockIconFrame.midX - Self.size.width / 2, y: dockIconFrame.maxY + 12)
            let frame = NSRect(origin: origin, size: Self.size)

            if let panel, let hostingView {
                // Multitouch-driven updates can arrive 60-120×/second. Re-applying identical
                // content/frame, and even just re-ordering an *already-frontmost* panel, that
                // often was enough to flood AppKit's constraint/display-cycle pass and trigger
                // a "needing another Update Constraints" fault/crash — so every call here is a
                // strict no-op unless something actually changed.
                if systemImage != lastImage || tint != lastTint {
                    lastImage = systemImage
                    lastTint = tint
                    hostingView.rootView = DockActionPreviewView(systemImage: systemImage, tint: tint)
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
            lastImage = systemImage
            lastTint = tint
            isVisible = true
            let rootView = DockActionPreviewView(systemImage: systemImage, tint: tint)

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
            // The circle draws its own shadow (see `DockActionPreviewView`); a second,
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
}

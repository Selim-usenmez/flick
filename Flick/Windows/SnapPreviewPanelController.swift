import AppKit
import SwiftUI

/// Hosts `SnapPreviewView` in a borderless, click-through panel whose frame is driven live
/// by the in-progress gesture, then hidden once the gesture ends (successfully or not).
final class SnapPreviewPanelController {
    private var panel: NSPanel?
    private var lastFrame: NSRect?
    private var isVisible = false

    /// - Parameter frame: target frame in AppKit screen coordinates (bottom-left origin).
    func show(frame: NSRect) {
        if let panel {
            // Multitouch-driven updates can arrive 60-120×/second. Re-setting the *same*
            // frame, and even just re-ordering an *already-frontmost* panel, that often
            // was enough to flood AppKit's constraint/display-cycle pass and trigger a
            // "needing another Update Constraints" fault/crash — so every call here is a
            // strict no-op unless something actually changed. `display: false` also lets
            // AppKit coalesce the redraw into its normal cycle instead of forcing one.
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
        isVisible = true

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let hostingView = NSHostingView(rootView: SnapPreviewView())
        // Without this, NSHostingView tries to auto-size the panel to its SwiftUI
        // content's ideal size, fighting our explicit `setFrame` calls above.
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        panel?.orderOut(nil)
    }
}

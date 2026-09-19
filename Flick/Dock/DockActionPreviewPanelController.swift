import AppKit
import SwiftUI

/// Hosts `DockActionPreviewView` in a borderless, click-through panel positioned just above
/// a Dock icon, updated live while the gesture is in progress.
final class DockActionPreviewPanelController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<DockActionPreviewView>?
    private var lastFrame: NSRect?
    private var lastText: String?
    private var isVisible = false

    private static let size = CGSize(width: 200, height: 32)

    /// - Parameter dockIconFrame: the icon's frame in AppKit screen coordinates.
    func show(systemImage: String, text: String, tint: Color, above dockIconFrame: NSRect) {
        let origin = NSPoint(x: dockIconFrame.midX - Self.size.width / 2, y: dockIconFrame.maxY + 12)
        let frame = NSRect(origin: origin, size: Self.size)

        if let panel, let hostingView {
            // Multitouch-driven updates can arrive 60-120×/second. Re-applying identical
            // content/frame, and even just re-ordering an *already-frontmost* panel, that
            // often was enough to flood AppKit's constraint/display-cycle pass and trigger
            // a "needing another Update Constraints" fault/crash — so every call here is a
            // strict no-op unless something actually changed.
            if text != lastText {
                lastText = text
                hostingView.rootView = DockActionPreviewView(systemImage: systemImage, text: text, tint: tint)
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
        lastText = text
        isVisible = true
        let rootView = DockActionPreviewView(systemImage: systemImage, text: text, tint: tint)

        let hostingView = NSHostingView(rootView: rootView)
        // Without this, NSHostingView tries to auto-size the panel to its SwiftUI
        // content's ideal size, fighting our explicit `setFrame` calls below — that fight
        // is what caused the "too many Update Constraints" fault under rapid updates.
        hostingView.sizingOptions = []
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.contentView = hostingView
        panel.orderFrontRegardless()
        self.panel = panel
        self.hostingView = hostingView
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        panel?.orderOut(nil)
    }
}

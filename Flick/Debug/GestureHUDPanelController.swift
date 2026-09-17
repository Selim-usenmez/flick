import AppKit
import SwiftUI

/// Hosts `GestureHUDView` in a small always-on-top, non-activating panel so it stays
/// visible over whatever app the cursor is hovering, without stealing focus from it.
final class GestureHUDPanelController {
    private var panel: NSPanel?
    private let monitor: TouchGestureMonitor

    init(monitor: TouchGestureMonitor) {
        self.monitor = monitor
    }

    var isVisible: Bool { panel != nil }

    func show() {
        guard panel == nil else { return }

        let hostingView = NSHostingView(rootView: GestureHUDView(monitor: monitor))
        hostingView.frame = NSRect(x: 0, y: 0, width: 240, height: 170)

        let panel = NSPanel(
            contentRect: hostingView.frame,
            styleMask: [.nonactivatingPanel, .titled, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.title = "Flick — Debug"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false

        if let screenFrame = NSScreen.main?.visibleFrame {
            let origin = NSPoint(x: screenFrame.maxX - 260, y: screenFrame.minY + 20)
            panel.setFrameOrigin(origin)
        }

        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    func toggle() {
        isVisible ? hide() : show()
    }
}

import AppKit
import SwiftUI

/// Hosts `GestureHUDView` in a small always-on-top, non-activating panel so it stays
/// visible over whatever app the cursor is hovering, without stealing focus from it.
final class GestureHUDPanelController {
    private var panel: NSPanel?
    private let monitor: TouchGestureMonitor
    private let activityLog: GestureActivityLog

    init(monitor: TouchGestureMonitor, activityLog: GestureActivityLog) {
        self.monitor = monitor
        self.activityLog = activityLog
    }

    var isVisible: Bool { panel != nil }

    func show() {
        guard panel == nil else { return }

        let hostingView = NSHostingView(
            rootView: GestureHUDView(monitor: monitor, activityLog: activityLog)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 640, height: 440)
        // The live diagnostic text in this panel updates at gesture-frame frequency during
        // a pinch; without this, NSHostingView's own auto-sizing (triggered by content
        // changes, not just frame changes) can trip the same "too many Update Constraints"
        // fault seen on the preview panels.
        hostingView.sizingOptions = []

        let panel = NSPanel(
            contentRect: hostingView.frame,
            styleMask: [.nonactivatingPanel, .titled, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.title = "Flick"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false

        if let screenFrame = NSScreen.main?.visibleFrame {
            let origin = NSPoint(x: screenFrame.maxX - 660, y: screenFrame.minY + 20)
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

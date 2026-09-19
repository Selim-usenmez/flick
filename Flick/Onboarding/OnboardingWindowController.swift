import AppKit
import SwiftUI

/// Hosts the first-launch welcome tour in a plain titled window (not a panel — this is a
/// one-time, focus-worthy moment, not a heads-up display). Shown automatically once, and
/// replayable later from the menu bar.
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private static let hasCompletedKey = "com.selim.Flick.hasCompletedOnboarding"

    private var window: NSWindow?
    private let controller: FlickController

    init(controller: FlickController) {
        self.controller = controller
    }

    var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: Self.hasCompletedKey)
    }

    func showIfNeeded() {
        guard !hasCompleted else { return }
        show()
    }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hostingView = NSHostingView(
            rootView: OnboardingView(controller: controller) { [weak self] in
                self?.window?.close()
            }
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 640, height: 460)
        hostingView.sizingOptions = []

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    /// However the window closes — the "Commencer" button or the traffic-light close
    /// button — the tour has been seen and shouldn't nag again on the next launch.
    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: Self.hasCompletedKey)
    }
}

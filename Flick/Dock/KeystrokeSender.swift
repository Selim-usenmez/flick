import AppKit
import CoreGraphics

/// Synthesizes keyboard shortcuts system-wide, for actions with no dedicated Accessibility
/// API (there's no "new window" or universally-reliable "close" AX action — the shortcut
/// is the only universal hook).
enum KeystrokeSender {
    /// ANSI-US virtual keycodes. Virtual keycodes are positional, not character-based, so
    /// these target the physical N/W-position keys regardless of the active keyboard layout.
    private static let keyCodeN: CGKeyCode = 45
    private static let keyCodeW: CGKeyCode = 13

    static func sendCommandN() {
        send(keyCode: keyCodeN)
    }

    static func sendCommandW() {
        send(keyCode: keyCodeW)
    }

    /// Brings `app` to the front, then runs `action` once it has actually become active —
    /// `activate()` is asynchronous, and a shortcut posted right after it lands in whatever
    /// app was still frontmost at that instant (sometimes the one the user just swiped
    /// *away* from, which then got a ⌘W or ⌘N it never asked for). Polls briefly instead of
    /// relying on `didActivateApplicationNotification`, which doesn't fire if the app was
    /// already frontmost; falls through after `activationTimeout` regardless so an app that
    /// refuses activation can't stall the action forever. Main thread only.
    static func activate(_ app: NSRunningApplication, then action: @escaping () -> Void) {
        app.activate()
        waitForActivation(of: app, deadline: CFAbsoluteTimeGetCurrent() + activationTimeout, then: action)
    }

    private static let activationTimeout: CFAbsoluteTime = 0.5
    private static let activationPollInterval: TimeInterval = 0.03

    private static func waitForActivation(of app: NSRunningApplication, deadline: CFAbsoluteTime, then action: @escaping () -> Void) {
        if app.isActive || app.isTerminated || CFAbsoluteTimeGetCurrent() >= deadline {
            // One more turn so the window server has flushed the focus change through to
            // the HID event tap the keystroke is posted into.
            DispatchQueue.main.asyncAfter(deadline: .now() + activationPollInterval, execute: action)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + activationPollInterval) {
            waitForActivation(of: app, deadline: deadline, then: action)
        }
    }

    private static func send(keyCode: CGKeyCode) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

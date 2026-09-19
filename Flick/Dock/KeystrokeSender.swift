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

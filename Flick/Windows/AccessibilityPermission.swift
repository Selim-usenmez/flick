import AppKit
import Observation

/// Tracks whether Flick is trusted for the Accessibility API. Granting the permission in
/// System Settings does not post a notification, so this polls on a timer instead —
/// the alternative would be asking the user to relaunch the app after granting it.
@Observable
final class AccessibilityPermission {
    private(set) var isTrusted: Bool = AXIsProcessTrusted()

    private var pollTimer: Timer?

    init() {
        startPolling()
    }

    /// Prompts the system dialog if not already trusted. Safe to call repeatedly; macOS
    /// only shows the prompt once per app until the user responds.
    func requestAuthorization() {
        let options: [String: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let trusted = AXIsProcessTrusted()
            if trusted != self.isTrusted {
                self.isTrusted = trusted
            }
        }
    }

    deinit {
        pollTimer?.invalidate()
    }
}

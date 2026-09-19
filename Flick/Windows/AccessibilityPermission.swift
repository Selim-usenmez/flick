import AppKit
import Observation

/// Tracks whether Flick is trusted for the Accessibility API. Granting the permission in
/// System Settings does not post a notification, so this polls on a timer instead —
/// the alternative would be asking the user to relaunch the app after granting it.
@Observable
final class AccessibilityPermission {
    private(set) var isTrusted: Bool = AXIsProcessTrusted()

    /// Fired whenever `isTrusted` changes, including the poll picking up a grant made in
    /// System Settings after launch — callers that only check `isTrusted` once at init
    /// (to auto-enable) would otherwise miss that later transition.
    var onTrustedChange: ((Bool) -> Void)?

    private var pollTimer: Timer?

    init() {
        startPolling()
    }

    /// Prompts the system dialog if not already trusted. Safe to call repeatedly; macOS
    /// only shows the prompt once per app until the user responds.
    func requestAuthorization() {
        let options: [String: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        setTrusted(AXIsProcessTrustedWithOptions(options as CFDictionary))
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            setTrusted(AXIsProcessTrusted())
        }
    }

    private func setTrusted(_ trusted: Bool) {
        guard trusted != isTrusted else { return }
        isTrusted = trusted
        onTrustedChange?(trusted)
    }

    deinit {
        pollTimer?.invalidate()
    }
}

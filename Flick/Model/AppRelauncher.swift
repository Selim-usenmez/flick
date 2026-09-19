import AppKit

/// Relaunches Flick as a fresh process. Useful from the control panel if the gesture
/// pipeline ever gets stuck — a plain `NSApplication.shared.terminate` would just leave the
/// user without the app until they reopen it manually.
enum AppRelauncher {
    static func relaunch() {
        let bundleURL = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true

        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

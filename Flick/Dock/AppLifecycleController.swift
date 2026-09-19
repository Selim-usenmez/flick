import AppKit
import ApplicationServices

/// Applies `DockAction`s to the app represented by a Dock icon — quit, new window, and
/// minimize/unminimize/cycle acting on its window list via Accessibility.
///
/// Threading is deliberately split: `NSWorkspace`/`NSRunningApplication` calls (finding the
/// running app, `.activate()`, `.terminate()`) always happen on whatever thread `apply` is
/// called on — expected to be the main thread, since AppKit as a whole isn't documented as
/// thread-safe and calling it from a background queue was observed to crash. Only the raw
/// `AXUIElement` calls (a thin, genuinely thread-safe IPC layer to the target app) run on a
/// background queue — those are the ones that can actually hang if the target app is slow
/// to respond to an Accessibility query, which would otherwise freeze Flick's own UI.
struct AppLifecycleController {
    /// `nil` on success, else a short reason — surfaced in the control panel's activity
    /// log. Delivered on the main thread regardless of which path handled `action`.
    static func apply(_ action: DockAction, to item: DockItemLocator.Located, completion: @escaping (String?) -> Void = { _ in }) {
        switch action {
        case .quit:
            completion(quit(item))
        case .newWindow:
            completion(newWindow(item))
        case .minimizeFrontmost:
            minimizeFrontmost(item, completion: completion)
        case .unminimize:
            unminimizeOrLaunch(item, completion: completion)
        case .cycleNext:
            cycle(item, forward: true, completion: completion)
        case .cyclePrevious:
            cycle(item, forward: false, completion: completion)
        }
    }

    static func isRunning(_ item: DockItemLocator.Located) -> Bool {
        runningApplication(for: item) != nil
    }

    private static func frontmostWindow(forPID pid: pid_t) -> AXUIElement? {
        let axApp = AXUIElementCreateApplication(pid)
        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
           let focusedRef {
            return (focusedRef as! AXUIElement)
        }
        return windows(of: axApp)?.first
    }

    private static func windows(of axApp: AXUIElement) -> [AXUIElement]? {
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement]
        else { return nil }
        return windows
    }

    private static func isMinimized(_ window: AXUIElement) -> Bool {
        var minimizedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
              let minimized = minimizedRef as? Bool
        else { return false }
        return minimized
    }

    // MARK: - Main-thread-only actions
    //
    // No Accessibility round-trip here, so nothing to gain by backgrounding these — just
    // `NSWorkspace`/`NSRunningApplication`, which stay wherever the caller called from.

    /// Deliberately does *not* try to launch the app when it isn't running — auto-launching
    /// via `NSWorkspace.openApplication` from here was an unreliable path. If the app isn't
    /// open, the gesture is a no-op and the user is expected to launch it themselves.
    private static func launch(_ item: DockItemLocator.Located) -> String? {
        guard let running = runningApplication(for: item) else {
            return "app non lancée — ouvre-la toi-même"
        }
        running.activate(options: [.activateIgnoringOtherApps])
        return nil
    }

    private static func quit(_ item: DockItemLocator.Located) -> String? {
        guard let running = runningApplication(for: item) else {
            return "app non trouvée parmi les process actifs"
        }
        // A backgrounded/App Nap-suspended target can leave `terminate()` sitting
        // half-handled — its quit confirmation dialog (if any) stays invisible and the
        // process lingers. Activating first wakes it and matches what quitting from its own
        // frontmost menu bar already does correctly.
        running.activate(options: [.activateIgnoringOtherApps])
        running.terminate()
        return nil
    }

    /// Activates the app, then sends it a ⌘N keystroke — there's no generic Accessibility
    /// action for "new window/tab", so this mirrors what the keyboard shortcut itself does.
    private static func newWindow(_ item: DockItemLocator.Located) -> String? {
        guard let running = runningApplication(for: item) else {
            return launch(item) // Not running: launching already opens a window.
        }
        running.activate(options: [.activateIgnoringOtherApps])
        KeystrokeSender.sendCommandN()
        return nil
    }

    // MARK: - Actions with an Accessibility round-trip
    //
    // Each resolves the `NSRunningApplication` on the calling thread first (expected to be
    // main), then hops to a background queue for the `AXUIElement` calls only, then hops
    // back to main for any subsequent `.activate()` and for `completion`.

    private static func minimizeFrontmost(_ item: DockItemLocator.Located, completion: @escaping (String?) -> Void) {
        guard let running = runningApplication(for: item) else {
            completion("aucune fenêtre trouvée pour cette app")
            return
        }
        let pid = running.processIdentifier
        DispatchQueue.global(qos: .userInitiated).async {
            guard let window = frontmostWindow(forPID: pid) else {
                DispatchQueue.main.async { completion("aucune fenêtre trouvée pour cette app") }
                return
            }
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            DispatchQueue.main.async { completion(nil) }
        }
    }

    private static func unminimizeOrLaunch(_ item: DockItemLocator.Located, completion: @escaping (String?) -> Void) {
        guard let running = runningApplication(for: item) else {
            completion(launch(item))
            return
        }
        let pid = running.processIdentifier
        DispatchQueue.global(qos: .userInitiated).async {
            let axApp = AXUIElementCreateApplication(pid)
            if let minimizedWindow = windows(of: axApp)?.first(where: isMinimized) {
                AXUIElementSetAttributeValue(minimizedWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            DispatchQueue.main.async {
                running.activate(options: [.activateIgnoringOtherApps])
                completion(nil)
            }
        }
    }

    /// Raises the next/previous window in the app's window list relative to its currently
    /// focused one, then activates the app so the raised window actually comes to front.
    private static func cycle(_ item: DockItemLocator.Located, forward: Bool, completion: @escaping (String?) -> Void) {
        guard let running = runningApplication(for: item) else {
            completion("app non trouvée parmi les process actifs")
            return
        }
        let pid = running.processIdentifier
        DispatchQueue.global(qos: .userInitiated).async {
            let axApp = AXUIElementCreateApplication(pid)
            let windowList = windows(of: axApp) ?? []

            guard windowList.count > 1 else {
                DispatchQueue.main.async {
                    running.activate(options: [.activateIgnoringOtherApps])
                    completion(windowList.isEmpty ? "une seule fenêtre (ou aucune) à cycler" : nil)
                }
                return
            }

            var focusedRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedRef)
            let focused = focusedRef.map { $0 as! AXUIElement }
            let currentIndex = focused.flatMap { focused in windowList.firstIndex { CFEqual($0, focused) } } ?? 0

            let step = forward ? 1 : -1
            let nextIndex = (currentIndex + step + windowList.count) % windowList.count
            AXUIElementPerformAction(windowList[nextIndex], kAXRaiseAction as CFString)

            DispatchQueue.main.async {
                running.activate(options: [.activateIgnoringOtherApps])
                completion(nil)
            }
        }
    }

    private static func runningApplication(for item: DockItemLocator.Located) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { app in
            if let bundleURL = item.bundleURL, let appURL = app.bundleURL {
                return appURL == bundleURL
            }
            return !item.displayName.isEmpty && app.localizedName == item.displayName
        }
    }
}

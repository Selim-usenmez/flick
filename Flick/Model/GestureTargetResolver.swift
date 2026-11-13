import AppKit
import ApplicationServices

/// What a gesture landed on at its starting point, resolved once at gesture start and
/// reused for both the live preview and the action applied on release. Everything the
/// preview needs per frame (split ratios, whether the app is running...) is resolved here
/// once, instead of being recomputed on every one of the 60–120 updates a gesture produces
/// per second.
enum GestureTarget {
    case window(WindowLocator.Located, ratios: SnapZoneRatios, bundleID: String?)
    case dockItem(DockItemLocator.Located, isRunning: Bool)
}

/// Resolves a gesture's `GestureTarget` *off the main thread*.
///
/// Resolution is a chain of cross-process calls — the window server for the window list,
/// then the target app's (or the Dock's) Accessibility server for its windows/icons. A
/// busy or hung app answers those slowly, up to the Accessibility messaging timeout, and
/// this runs at the start of *every* two-finger scroll anywhere on screen (the monitor
/// can't know in advance whether a gesture is aimed at a title bar). Doing it on the main
/// thread meant one unresponsive app could freeze Flick's own UI — previews, animations,
/// the HUD — for seconds at a time, which read as "the app is lagging".
///
/// Only the parts that genuinely need AppKit (`NSScreen`, `NSWorkspace`,
/// `NSRunningApplication`) stay on main, before and after the background hop.
final class GestureTargetResolver {
    /// Serial on purpose: resolutions for back-to-back gestures must not overlap and race
    /// each other's Accessibility calls into the same app. A slow one delays the next, but
    /// the caller's generation check (see `FlickController`) discards stale results anyway.
    private let queue = DispatchQueue(label: "com.flick.gesture-target", qos: .userInteractive)
    private let gestureSettings: GestureSettings
    /// The Dock's PID is stable for the life of the session (it only changes if the Dock
    /// is relaunched), so it's cached rather than scanned out of `runningApplications`
    /// for every gesture — re-resolved only if a lookup against it fails.
    private var cachedDockPID: pid_t?

    /// Accessibility calls block the calling thread until the target app answers or this
    /// much time passes. The system default is 6 seconds — far too long for anything on a
    /// gesture's critical path. Set once on the system-wide element, which makes it the
    /// process-wide default for every element created afterwards.
    private static let accessibilityTimeout: Float = 1.0

    init(gestureSettings: GestureSettings) {
        self.gestureSettings = gestureSettings
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), Self.accessibilityTimeout)
    }

    /// - Parameters:
    ///   - location: the gesture's starting point in AppKit screen coordinates.
    ///   - completion: always called on the main thread, with `nil` when the gesture
    ///     didn't start over a title bar or a Dock icon.
    func resolve(at location: NSPoint, completion: @escaping (GestureTarget?) -> Void) {
        // Main-thread-only reads, captured up front.
        let quartzPoint = ScreenGeometry.quartzPoint(fromAppKit: location)
        let screen = NSScreen.screens.first { $0.frame.contains(location) }
        let dockPID = dockProcessID()
        let defaultRatios = SnapZoneRatios(
            horizontal: gestureSettings.horizontalSplitRatio,
            vertical: gestureSettings.verticalSplitRatio
        )

        queue.async {
            // A window's title bar takes priority over a Dock icon in the unlikely case
            // both somehow overlap at the gesture's starting point.
            if let screen, let window = WindowLocator.window(atTitleBar: quartzPoint, on: screen) {
                DispatchQueue.main.async {
                    let bundleID = NSRunningApplication(processIdentifier: window.pid)?.bundleIdentifier
                    let ratios = bundleID.map { AdaptiveSnapZones.shared.ratios(for: $0, defaults: defaultRatios) } ?? defaultRatios
                    completion(.window(window, ratios: ratios, bundleID: bundleID))
                }
                return
            }
            if let dockPID, let item = DockItemLocator.item(at: quartzPoint, dockPID: dockPID) {
                DispatchQueue.main.async {
                    completion(.dockItem(item, isRunning: AppLifecycleController.isRunning(item)))
                }
                return
            }
            DispatchQueue.main.async {
                if dockPID == nil { self.cachedDockPID = nil }
                completion(nil)
            }
        }
    }

    private func dockProcessID() -> pid_t? {
        if let cachedDockPID, NSRunningApplication(processIdentifier: cachedDockPID) != nil {
            return cachedDockPID
        }
        cachedDockPID = DockItemLocator.dockProcessID()
        return cachedDockPID
    }
}

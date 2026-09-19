import AppKit
import ApplicationServices

/// Finds the window under a screen point, scoped to a "title bar" hit — the strip along a
/// window's top edge, roughly matching macOS's own traffic-light row. Flick only acts on
/// gestures that start there, per `TouchGestureMonitor`'s doc comment: doing this over a
/// window's body would also drive whatever scrolls/zooms in that app.
struct WindowLocator {
    struct Located {
        let axWindow: AXUIElement
        /// Current frame in Quartz (top-left origin) global screen coordinates — the same
        /// space `CGWindowListCopyWindowInfo` and the Accessibility position/size
        /// attributes use.
        let frame: CGRect
        let screen: NSScreen
    }

    static let titleBarHitHeight: CGFloat = 32

    /// - Parameter point: a point in AppKit screen coordinates (origin bottom-left of the
    ///   primary screen), e.g. from `NSEvent.mouseLocation`.
    static func window(atTitleBar point: NSPoint) -> Located? {
        let quartzPoint = ScreenGeometry.quartzPoint(fromAppKit: point)

        guard let info = frontmostWindowInfo(at: quartzPoint),
              let pidNumber = info[kCGWindowOwnerPID as String] as? Int,
              let windowFrame = boundsRect(from: info)
        else { return nil }

        guard quartzPoint.y <= windowFrame.minY + titleBarHitHeight else { return nil }
        guard let screen = screen(containing: point) else { return nil }
        guard let axWindow = axWindow(forPID: pid_t(pidNumber), matching: windowFrame) else { return nil }

        return Located(axWindow: axWindow, frame: windowFrame, screen: screen)
    }

    /// Reads a window's current frame in the same Quartz global coordinate space as
    /// `CGWindowListCopyWindowInfo`.
    static func frame(of axWindow: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef
        else { return nil }

        let positionValue = positionRef as! AXValue
        let sizeValue = sizeRef as! AXValue

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size)
        else { return nil }

        return CGRect(origin: position, size: size)
    }

    private static func frontmostWindowInfo(at quartzPoint: CGPoint) -> [String: Any]? {
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        let ownPID = Int(ProcessInfo.processInfo.processIdentifier)

        // CGWindowListCopyWindowInfo returns windows ordered front-to-back, so the first
        // hit is the topmost window at this point.
        for info in infoList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            // Flick's own windows (the HUD panel, Preferences...) must never become a
            // gesture target: `WindowSnapper`'s AX calls for a *different* process are a
            // genuinely thread-safe IPC round-trip, safe to run in the background — but for
            // Flick's own windows they resolve to direct, same-process AppKit calls, which
            // crashes when made off the main thread the way every snap action does.
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int, ownerPID != ownPID else { continue }
            guard let bounds = boundsRect(from: info) else { continue }
            if bounds.contains(quartzPoint) { return info }
        }
        return nil
    }

    private static func boundsRect(from info: [String: Any]) -> CGRect? {
        guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
              let x = bounds["X"], let y = bounds["Y"],
              let width = bounds["Width"], let height = bounds["Height"]
        else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func screen(containing appKitPoint: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(appKitPoint) }
    }

    private static func axWindow(forPID pid: pid_t, matching targetFrame: CGRect) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement]
        else { return nil }

        for window in windows {
            guard let windowFrame = frame(of: window) else { continue }
            if windowFrame.isApproximatelyEqual(to: targetFrame) { return window }
        }
        return nil
    }
}

private extension CGRect {
    func isApproximatelyEqual(to other: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(minX - other.minX) < tolerance &&
            abs(minY - other.minY) < tolerance &&
            abs(width - other.width) < tolerance &&
            abs(height - other.height) < tolerance
    }
}

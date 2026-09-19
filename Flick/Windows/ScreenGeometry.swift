import AppKit

/// Accessibility position/size attributes and `CGWindowListCopyWindowInfo` both use Quartz's
/// global coordinate space (origin top-left of the primary screen, Y growing downward).
/// AppKit's `NSScreen`/`NSEvent`/`NSPanel` use the inverse (origin bottom-left of the
/// primary screen, Y growing upward). This flips between the two using the primary screen's
/// height as the mirror axis — the same flip in both directions, since it's self-inverse.
enum ScreenGeometry {
    static func quartzPoint(fromAppKit point: NSPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    static func quartzRect(fromAppKit rect: CGRect) -> CGRect {
        flip(rect)
    }

    static func appKitRect(fromQuartz rect: CGRect) -> CGRect {
        flip(rect)
    }

    /// The screen AppKit's global coordinate space is anchored to — the one whose origin is
    /// `(0, 0)`, not necessarily `NSScreen.screens.first`. That array's order reflects
    /// whatever the system happens to report and is **not** guaranteed to put the primary
    /// display first (e.g. when a secondary display is arranged above/left of it in
    /// System Settings). Getting this wrong silently skews every coordinate conversion in
    /// the app on a multi-monitor setup.
    private static var primaryScreenHeight: CGFloat {
        let screens = NSScreen.screens
        let primary = screens.first { $0.frame.origin == .zero } ?? screens.first
        return primary?.frame.height ?? 0
    }

    private static func flip(_ rect: CGRect) -> CGRect {
        let height = primaryScreenHeight
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }
}

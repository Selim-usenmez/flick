import CoreGraphics

/// An action performed on a running app via a gesture on its Dock icon.
enum DockAction: Equatable {
    /// Swipe down.
    case quit
    /// Pinch open — sends ⌘N to the app.
    case newWindow
    /// Pinch closed — minimizes the app's frontmost window.
    case minimizeFrontmost
    /// Swipe up — restores the app's most recently minimized window (or does nothing if
    /// it isn't running at all — see `AppLifecycleController.launch`).
    case unminimize
    /// Swipe right — activates the next window in the app's window list.
    case cycleNext
    /// Swipe left — activates the previous window in the app's window list.
    case cyclePrevious
}

/// Turns a completed gesture that started over a Dock icon into a `DockAction`.
///
/// Quit is deliberately on the swipe (translation) path rather than pinch: pinch detection
/// goes through `MultitouchSupport`'s private, from-scratch finger tracking (see
/// `TouchGestureMonitor`), which is inherently more fragile than the plain `NSEvent`-driven
/// swipe path — not a place to put an action as consequential as quitting an app.
struct DockGestureClassifier {
    static func action(for stroke: GestureStroke, settings: GestureSettings) -> DockAction? {
        switch stroke.kind {
        case .magnify:
            guard abs(stroke.magnification) >= settings.pinchThreshold else { return nil }
            let isOpen = (stroke.magnification > 0) != settings.invertPinch
            return isOpen ? .newWindow : .minimizeFrontmost
        case .translation:
            return classifyTranslation(stroke.averageTranslation, settings: settings)
        }
    }

    private static func classifyTranslation(_ translation: CGVector, settings: GestureSettings) -> DockAction? {
        let absDX = abs(translation.dx)
        let absDY = abs(translation.dy)
        guard max(absDX, absDY) >= settings.minimumSwipeDistance else { return nil }

        if absDX >= absDY {
            let right = (translation.dx > 0) != settings.invertHorizontal
            return right ? .cycleNext : .cyclePrevious
        } else {
            let up = (translation.dy < 0) != settings.invertVertical
            return up ? .unminimize : .quit
        }
    }
}

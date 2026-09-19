import AppKit
import ApplicationServices

/// A Swish-style snap target for a gesture-ended window — the half/quarter regions, plus
/// the three traffic-light actions (minimize, maximize, close).
enum SnapAction: Equatable {
    case leftHalf, rightHalf
    case topLeftQuarter, topRightQuarter, bottomLeftQuarter, bottomRightQuarter
    case maximize
    case minimize
    case close
}

/// Applies `SnapAction`s to windows located by `WindowLocator`, computing target frames in
/// the same Quartz (top-left origin) global coordinate space Accessibility uses, derived
/// from each screen's `visibleFrame` (which excludes the menu bar and Dock).
struct WindowSnapper {
    private static let animationDuration: TimeInterval = 0.14
    private static let animationSteps = 10

    /// The frame `action` would produce for `located`, in Quartz global coordinates. Used
    /// to draw the live preview overlay while a gesture is in progress. `nil` for actions
    /// that don't resize the window (`.minimize`, `.close`).
    static func previewFrame(for action: SnapAction, in located: WindowLocator.Located) -> CGRect? {
        switch action {
        case .minimize, .close:
            return nil
        default:
            let visible = ScreenGeometry.quartzRect(fromAppKit: located.screen.visibleFrame)
            return targetFrame(for: action, in: visible)
        }
    }

    /// Every branch here ends up making a synchronous, cross-process Accessibility call
    /// into the target window's own app. If that app is busy or unresponsive, the call
    /// blocks until it isn't — so this always runs off the main thread, or a slow/hung
    /// target app would freeze Flick's own UI right along with it. `completion` (the
    /// result: `nil` on success, else a short failure reason) is delivered back on main,
    /// since it typically ends up in `@Observable` state.
    static func apply(
        _ action: SnapAction,
        to located: WindowLocator.Located,
        animated: Bool = true,
        completion: @escaping (String?) -> Void = { _ in }
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let failure = performApply(action, to: located, animated: animated)
            DispatchQueue.main.async { completion(failure) }
        }
    }

    private static func performApply(_ action: SnapAction, to located: WindowLocator.Located, animated: Bool) -> String? {
        switch action {
        case .minimize:
            setMinimized(true, on: located.axWindow)
            return nil
        case .close:
            performClose(on: located.axWindow)
            return nil
        default:
            guard let target = previewFrame(for: action, in: located) else { return "cible introuvable" }
            if animated {
                animate(from: located.frame, to: target, on: located.axWindow)
            } else {
                set(frame: target, on: located.axWindow)
            }
            return nil
        }
    }

    private static func targetFrame(for action: SnapAction, in visible: CGRect) -> CGRect {
        switch action {
        case .leftHalf:
            return CGRect(x: visible.minX, y: visible.minY, width: visible.width / 2, height: visible.height)
        case .rightHalf:
            return CGRect(x: visible.midX, y: visible.minY, width: visible.width / 2, height: visible.height)
        case .topLeftQuarter:
            return CGRect(x: visible.minX, y: visible.minY, width: visible.width / 2, height: visible.height / 2)
        case .topRightQuarter:
            return CGRect(x: visible.midX, y: visible.minY, width: visible.width / 2, height: visible.height / 2)
        case .bottomLeftQuarter:
            return CGRect(x: visible.minX, y: visible.midY, width: visible.width / 2, height: visible.height / 2)
        case .bottomRightQuarter:
            return CGRect(x: visible.midX, y: visible.midY, width: visible.width / 2, height: visible.height / 2)
        case .maximize:
            return visible
        case .minimize, .close:
            fatalError("filtered out by previewFrame/apply before reaching targetFrame")
        }
    }

    /// Steps the window from `start` to `end` over `animationDuration`, easing out, instead
    /// of jumping there in one Accessibility call. Driven by chained `asyncAfter` calls on
    /// whatever background queue `apply` is already running on — deliberately not a
    /// `Timer`/`RunLoop.main`, since that would hop every single step's AX call back onto
    /// the main thread and reintroduce the exact freeze this whole function exists to avoid.
    private static func animate(from start: CGRect, to end: CGRect, on axWindow: AXUIElement) {
        let interval = animationDuration / Double(animationSteps)
        animateStep(1, from: start, to: end, on: axWindow, interval: interval)
    }

    private static func animateStep(
        _ currentStep: Int, from start: CGRect, to end: CGRect, on axWindow: AXUIElement, interval: TimeInterval
    ) {
        let progress = CGFloat(currentStep) / CGFloat(animationSteps)
        let eased = 1 - pow(1 - progress, 3) // ease-out cubic
        let frame = CGRect(
            x: start.minX + (end.minX - start.minX) * eased,
            y: start.minY + (end.minY - start.minY) * eased,
            width: start.width + (end.width - start.width) * eased,
            height: start.height + (end.height - start.height) * eased
        )
        set(frame: frame, on: axWindow, correctPosition: currentStep == animationSteps)

        guard currentStep < animationSteps else { return }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + interval) {
            animateStep(currentStep + 1, from: start, to: end, on: axWindow, interval: interval)
        }
    }

    private static func set(frame: CGRect, on axWindow: AXUIElement, correctPosition: Bool = true) {
        // Position, then size, then position again: some apps re-clamp their frame when
        // resized, which otherwise leaves the window a few points off target. Skipped on
        // intermediate animation steps to cut the number of Accessibility round-trips.
        setPosition(frame.origin, on: axWindow)
        setSize(frame.size, on: axWindow)
        if correctPosition { setPosition(frame.origin, on: axWindow) }
    }

    private static func setPosition(_ point: CGPoint, on axWindow: AXUIElement) {
        var mutablePoint = point
        guard let value = AXValueCreate(.cgPoint, &mutablePoint) else { return }
        AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, value)
    }

    private static func setSize(_ size: CGSize, on axWindow: AXUIElement) {
        var mutableSize = size
        guard let value = AXValueCreate(.cgSize, &mutableSize) else { return }
        AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, value)
    }

    private static func setMinimized(_ minimized: Bool, on axWindow: AXUIElement) {
        AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, minimized ? kCFBooleanTrue : kCFBooleanFalse)
    }

    /// Presses the window's own close button via Accessibility — same effect as clicking
    /// the red traffic light, including any "save changes?" prompt the app itself shows.
    /// Not every window exposes a standard `AXCloseButton` (some utility/panel-style
    /// windows don't), so this falls back to raising the window, focusing its owning app,
    /// and sending the universal ⌘W shortcut.
    private static func performClose(on axWindow: AXUIElement) {
        var closeButtonRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axWindow, kAXCloseButtonAttribute as CFString, &closeButtonRef) == .success,
           let closeButtonRef {
            let result = AXUIElementPerformAction((closeButtonRef as! AXUIElement), kAXPressAction as CFString)
            if result == .success { return }
        }

        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        var pid: pid_t = 0
        if AXUIElementGetPid(axWindow, &pid) == .success {
            // `performApply` (the only caller) runs this whole function on a background
            // queue for the AX calls above; NSRunningApplication/.activate() is AppKit,
            // which isn't safe to call off the main thread, so this specifically hops back.
            DispatchQueue.main.sync {
                NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateIgnoringOtherApps])
            }
        }
        KeystrokeSender.sendCommandW()
    }
}

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

    /// `action`'s target region as a fraction (0...1) of the screen, top-left origin —
    /// independent of any actual screen size, since half/quarter regions are always the
    /// same simple fractions. Used to draw the small cursor-side mini-preview while a
    /// gesture is in progress. `nil` for actions that don't resize the window (`.minimize`,
    /// `.close`), matching `previewFrame`.
    static func normalizedRegion(for action: SnapAction) -> CGRect? {
        switch action {
        case .minimize, .close:
            return nil
        case .leftHalf:
            return CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf:
            return CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topLeftQuarter:
            return CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRightQuarter:
            return CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeftQuarter:
            return CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottomRightQuarter:
            return CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .maximize:
            return CGRect(x: 0, y: 0, width: 1, height: 1)
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
        completion: @escaping (String?) -> Void = { _ in }
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let failure = performApply(action, to: located)
            DispatchQueue.main.async { completion(failure) }
        }
    }

    private static func performApply(_ action: SnapAction, to located: WindowLocator.Located) -> String? {
        switch action {
        case .minimize:
            setMinimized(true, on: located.axWindow)
            return nil
        case .close:
            performClose(on: located.axWindow)
            return nil
        default:
            guard let target = previewFrame(for: action, in: located) else { return "cible introuvable" }
            set(frame: target, on: located.axWindow)
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

    private static func set(frame: CGRect, on axWindow: AXUIElement) {
        // Position, then size, then position again: some apps re-clamp their frame when
        // resized, which otherwise leaves the window a few points off target.
        setPosition(frame.origin, on: axWindow)
        setSize(frame.size, on: axWindow)
        setPosition(frame.origin, on: axWindow)
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

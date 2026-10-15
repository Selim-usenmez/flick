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

    /// Whether this action's region is anchored to the left edge (`true`) or right edge
    /// (`false`) of the screen — `nil` for actions with no horizontal-split concept at all.
    /// Lets `AdaptiveSnapZones` interpret a post-snap manual resize as "the split line
    /// should be here" regardless of which of the two mirrored actions produced it.
    var isLeftAligned: Bool? {
        switch self {
        case .leftHalf, .topLeftQuarter, .bottomLeftQuarter: return true
        case .rightHalf, .topRightQuarter, .bottomRightQuarter: return false
        case .maximize, .minimize, .close: return nil
        }
    }

    /// Same idea as `isLeftAligned`, for the top/bottom quarter split.
    var isTopAligned: Bool? {
        switch self {
        case .topLeftQuarter, .topRightQuarter: return true
        case .bottomLeftQuarter, .bottomRightQuarter: return false
        case .leftHalf, .rightHalf, .maximize, .minimize, .close: return nil
        }
    }
}

/// Where the half/quarter split lines fall, as fractions of the screen (0...1).
/// `.even` (0.5/0.5) reproduces the original fixed halves/quarters. `horizontal` moves the
/// left/right divider; `vertical` moves the top/bottom divider used by quarters.
struct SnapZoneRatios: Equatable {
    var horizontal: CGFloat = 0.5
    var vertical: CGFloat = 0.5
    static let even = SnapZoneRatios()
}

/// Applies `SnapAction`s to windows located by `WindowLocator`, computing target frames in
/// the same Quartz (top-left origin) global coordinate space Accessibility uses, derived
/// from each screen's `visibleFrame` (which excludes the menu bar and Dock).
struct WindowSnapper {
    /// The frame `action` would produce for `located`, in Quartz global coordinates. Used
    /// to draw the live preview overlay while a gesture is in progress. `nil` for actions
    /// that don't resize the window (`.minimize`, `.close`).
    static func previewFrame(
        for action: SnapAction, in located: WindowLocator.Located, ratios: SnapZoneRatios = .even
    ) -> CGRect? {
        switch action {
        case .minimize, .close:
            return nil
        default:
            let visible = ScreenGeometry.quartzRect(fromAppKit: located.screen.visibleFrame)
            return targetFrame(for: action, in: visible, ratios: ratios)
        }
    }

    /// `action`'s target region as a fraction (0...1) of the screen, top-left origin —
    /// independent of any actual screen size, since half/quarter regions are always the
    /// same simple fractions. Used to draw the small cursor-side mini-preview while a
    /// gesture is in progress. `nil` for actions that don't resize the window (`.minimize`,
    /// `.close`), matching `previewFrame`.
    static func normalizedRegion(for action: SnapAction, ratios: SnapZoneRatios = .even) -> CGRect? {
        let h = ratios.horizontal
        let v = ratios.vertical
        switch action {
        case .minimize, .close:
            return nil
        case .leftHalf:
            return CGRect(x: 0, y: 0, width: h, height: 1)
        case .rightHalf:
            return CGRect(x: h, y: 0, width: 1 - h, height: 1)
        case .topLeftQuarter:
            return CGRect(x: 0, y: 0, width: h, height: v)
        case .topRightQuarter:
            return CGRect(x: h, y: 0, width: 1 - h, height: v)
        case .bottomLeftQuarter:
            return CGRect(x: 0, y: v, width: h, height: 1 - v)
        case .bottomRightQuarter:
            return CGRect(x: h, y: v, width: 1 - h, height: 1 - v)
        case .maximize:
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
    }

    /// Serial, not concurrent: keeps window actions applied in the exact order their
    /// gestures completed in. A concurrent queue let two rapid, back-to-back snaps (e.g.
    /// a quick double-swipe) run their Accessibility calls interleaved instead of one
    /// after the other — occasionally landing the window in the first action's target
    /// frame instead of the second's, because the two `setPosition`/`setSize` sequences
    /// raced each other.
    private static let axQueue = DispatchQueue(label: "com.flick.windowsnapper.ax")

    /// Every branch here ends up making a synchronous, cross-process Accessibility call
    /// into the target window's own app. If that app is busy or unresponsive, the call
    /// blocks until it isn't — so this always runs off the main thread, or a slow/hung
    /// target app would freeze Flick's own UI right along with it. `completion` (the
    /// result: `nil` on success, else a short failure reason) is delivered back on main,
    /// since it typically ends up in `@Observable` state.
    static func apply(
        _ action: SnapAction,
        to located: WindowLocator.Located,
        ratios: SnapZoneRatios = .even,
        completion: @escaping (String?) -> Void = { _ in }
    ) {
        axQueue.async {
            let failure = performApply(action, to: located, ratios: ratios)
            DispatchQueue.main.async { completion(failure) }
        }
    }

    private static func performApply(_ action: SnapAction, to located: WindowLocator.Located, ratios: SnapZoneRatios) -> String? {
        switch action {
        case .minimize:
            setMinimized(true, on: located.axWindow)
            return nil
        case .close:
            performClose(on: located.axWindow)
            return nil
        default:
            guard let target = previewFrame(for: action, in: located, ratios: ratios) else { return "cible introuvable" }
            set(frame: target, on: located.axWindow)
            return nil
        }
    }

    private static func targetFrame(for action: SnapAction, in visible: CGRect, ratios: SnapZoneRatios) -> CGRect {
        let h = ratios.horizontal, v = ratios.vertical
        switch action {
        case .leftHalf:
            return CGRect(x: visible.minX, y: visible.minY, width: visible.width * h, height: visible.height)
        case .rightHalf:
            let splitX = visible.minX + visible.width * h
            return CGRect(x: splitX, y: visible.minY, width: visible.maxX - splitX, height: visible.height)
        case .topLeftQuarter:
            return CGRect(x: visible.minX, y: visible.minY, width: visible.width * h, height: visible.height * v)
        case .topRightQuarter:
            let splitX = visible.minX + visible.width * h
            return CGRect(x: splitX, y: visible.minY, width: visible.maxX - splitX, height: visible.height * v)
        case .bottomLeftQuarter:
            let splitY = visible.minY + visible.height * v
            return CGRect(x: visible.minX, y: splitY, width: visible.width * h, height: visible.maxY - splitY)
        case .bottomRightQuarter:
            let splitX = visible.minX + visible.width * h
            let splitY = visible.minY + visible.height * v
            return CGRect(x: splitX, y: splitY, width: visible.maxX - splitX, height: visible.maxY - splitY)
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

import AppKit
import Observation
import Sparkle
import SwiftUI

/// What a gesture landed on at its starting point, resolved once at gesture start and
/// reused for both the live preview and the action applied on release.
private enum GestureTarget {
    case window(WindowLocator.Located)
    case dockItem(DockItemLocator.Located)
}

/// Owns the pieces that make up Flick's gesture pipeline and the app's on/off state.
@Observable
final class FlickController {
    let accessibilityPermission = AccessibilityPermission()
    let launchAtLogin = LaunchAtLoginManager()
    let gestureMonitor = TouchGestureMonitor()
    let gestureSettings = GestureSettings()
    let activityLog = GestureActivityLog()
    private(set) var isEnabled = false

    // Starts the updater's periodic background check immediately; not tied to any of
    // Flick's own observable state, so it doesn't need `@ObservationIgnored`.
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    // @Observable rewrites stored properties into computed ones backed by an
    // ObservationRegistrar, which is incompatible with `lazy`; opting this one out keeps
    // the lazy (needs `gestureMonitor` to already exist) while everything else stays tracked.
    @ObservationIgnored
    private lazy var hudPanelController = GestureHUDPanelController(
        monitor: gestureMonitor, activityLog: activityLog
    )
    // Needs `self`, hence `lazy` — same reason as `hudPanelController` above.
    @ObservationIgnored
    private lazy var onboardingController = OnboardingWindowController(controller: self)
    @ObservationIgnored
    private let snapPreviewController = SnapPreviewPanelController()
    @ObservationIgnored
    private let dockActionPreviewController = DockActionPreviewPanelController()
    @ObservationIgnored
    private let windowActionBadgeController = WindowActionBadgePanelController()
    /// Resolved once at the start of the current gesture. Reused at the end so the preview
    /// and the actually-applied action always agree, even if the cursor drifts mid-swipe.
    @ObservationIgnored
    private var activeGestureTarget: GestureTarget?
    /// Throttles only `updateLiveThrottled` (the HUD's `activityLog` text) — multitouch
    /// frames can arrive at 60-120Hz, far faster than that SwiftUI view graph can absorb
    /// without exceeding AppKit's per-flush constraint-update budget and crashing with "too
    /// many Update Constraints". The snap-preview panel's own frame updates are *not*
    /// throttled by this — repositioning a panel is cheap and a no-op when unchanged, so it
    /// stays at raw gesture rate for a fluid, finger-tracking preview.
    @ObservationIgnored
    private var lastPreviewUpdateTime: CFAbsoluteTime = 0
    // 1/30s wasn't conservative enough in practice — a sustained gesture (e.g. holding a
    // Dock quit swipe) still hit the same "too many Update Constraints" crash this is meant
    // to prevent. 1/8s matches TouchGestureMonitor.diagnosticFlushInterval, the rate that's
    // actually confirmed safe for this same HUD view graph.
    private static let previewUpdateInterval: CFAbsoluteTime = 1.0 / 8.0

    init() {
        gestureMonitor.onStrokeBegan = { [weak self] location in
            self?.resolveGestureTarget(at: location)
        }
        gestureMonitor.onStrokeUpdated = { [weak self] stroke in
            self?.updatePreview(for: stroke)
        }
        gestureMonitor.onStrokeEnded = { [weak self] stroke in
            self?.handleStrokeEnded(stroke)
        }

        // Show the control panel right away and turn gestures on immediately if
        // accessibility is already granted, so launching the app is enough to start using
        // it — no hunting through the menu bar first. Permission is often granted only
        // after launch (the normal flow: launch, then check the box in System Settings),
        // so the same auto-enable has to also happen on that later transition, not just here.
        hudPanelController.show()
        if accessibilityPermission.isTrusted {
            setEnabled(true)
        }
        accessibilityPermission.onTrustedChange = { [weak self] trusted in
            self?.setEnabled(trusted)
        }
        onboardingController.showIfNeeded()
    }

    func showOnboarding() {
        onboardingController.show()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            gestureMonitor.start()
        } else {
            gestureMonitor.stop()
        }
    }

    func toggleDebugHUD() {
        hudPanelController.toggle()
    }

    var isDebugHUDVisible: Bool {
        hudPanelController.isVisible
    }

    /// A window's title bar takes priority over a Dock icon in the unlikely case both
    /// somehow overlap at the gesture's starting point.
    private func resolveGestureTarget(at location: NSPoint) {
        if let window = WindowLocator.window(atTitleBar: location) {
            activeGestureTarget = .window(window)
        } else if let dockItem = DockItemLocator.item(at: location) {
            activeGestureTarget = .dockItem(dockItem)
        } else {
            activeGestureTarget = nil
        }
    }

    // MARK: - Live preview

    private func updatePreview(for stroke: GestureStroke) {
        // The panel repositioning below (`show`) is cheap and already a no-op when nothing
        // changed, so it runs at raw gesture-update rate for a fluid, finger-tracking
        // preview. Only the HUD's text (`activityLog.updateLive`, routed through
        // `updateLiveThrottled`) needs throttling — that's the SwiftUI relayout that was
        // actually causing the "too many Update Constraints" crash.
        switch activeGestureTarget {
        case .window(let located):
            updateWindowPreview(stroke: stroke, located: located)
        case .dockItem(let item):
            updateDockPreview(stroke: stroke, item: item)
        case nil:
            hideAllPreviews()
            updateLiveThrottled(target: "Aucune (ni barre de titre, ni Dock)", classification: "—")
        }
    }

    private func updateLiveThrottled(target: String, classification: String) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastPreviewUpdateTime >= Self.previewUpdateInterval else { return }
        lastPreviewUpdateTime = now
        activityLog.updateLive(target: target, classification: classification)
    }

    private func updateWindowPreview(stroke: GestureStroke, located: WindowLocator.Located) {
        dockActionPreviewController.hide()
        let magnitude = magnitudeDescription(for: stroke)
        guard let action = GestureClassifier.action(for: stroke, settings: gestureSettings) else {
            snapPreviewController.hide()
            windowActionBadgeController.hide()
            updateLiveThrottled(target: "Fenêtre", classification: "aucune action — \(magnitude)")
            return
        }
        updateLiveThrottled(target: "Fenêtre", classification: "\(action.description) — \(magnitude)")
        // Close/minimize/maximize don't resize the window into a region worth previewing
        // as a rectangle — they get a traffic-light-style badge instead, matching the
        // ones already used for Dock gestures.
        if let glyph = windowActionBadge(for: action) {
            snapPreviewController.hide()
            windowActionBadgeController.show(glyph: glyph, near: NSEvent.mouseLocation)
            return
        }
        windowActionBadgeController.hide()
        guard let region = WindowSnapper.normalizedRegion(for: action) else {
            snapPreviewController.hide()
            return
        }
        snapPreviewController.show(region: region, near: NSEvent.mouseLocation)
    }

    /// The three traffic-light actions get a custom badge (see `Assets.xcassets/Actions`);
    /// the half/quarter snap regions keep the rectangle mini-preview instead, which already
    /// conveys their target region clearly.
    private func windowActionBadge(for action: SnapAction) -> ActionBadgeView.Glyph? {
        switch action {
        case .close: return .badge(assetName: "fermer")
        case .maximize: return .badge(assetName: "agrandir")
        case .minimize: return .badge(assetName: "reduire")
        default: return nil
        }
    }

    private func updateDockPreview(stroke: GestureStroke, item: DockItemLocator.Located) {
        snapPreviewController.hide()
        windowActionBadgeController.hide()
        let magnitude = magnitudeDescription(for: stroke)

        if item.kind == .minimizedWindow {
            updateMinimizedWindowPreview(stroke: stroke, item: item, magnitude: magnitude)
            return
        }

        let targetDescription = "Dock : \(item.displayName.isEmpty ? "?" : item.displayName)"
        guard let action = DockGestureClassifier.action(for: stroke, settings: gestureSettings) else {
            dockActionPreviewController.hide()
            updateLiveThrottled(target: targetDescription, classification: "aucune action — \(magnitude)")
            return
        }
        let isRunning = AppLifecycleController.isRunning(item)
        updateLiveThrottled(target: targetDescription, classification: "\(action.description(isRunning: isRunning)) — \(magnitude)")
        dockActionPreviewController.show(
            glyph: dockPreviewIcon(for: action, isRunning: isRunning),
            near: ScreenGeometry.appKitRect(fromQuartz: item.frame)
        )
    }

    /// A minimized-window Dock thumbnail (the section right before the Trash) only
    /// supports one gesture — swipe up to restore it, the same `AXPress` a click sends.
    /// Accessibility gives no way to resolve which app a thumbnail belongs to (see
    /// `DockItemLocator.Kind`), so unlike a regular app icon, nothing else (quit, cycle
    /// windows...) can be driven reliably from here.
    private func updateMinimizedWindowPreview(stroke: GestureStroke, item: DockItemLocator.Located, magnitude: String) {
        let targetDescription = "Fenêtre réduite : \(item.displayName.isEmpty ? "?" : item.displayName)"
        guard DockGestureClassifier.action(for: stroke, settings: gestureSettings) == .unminimize else {
            dockActionPreviewController.hide()
            updateLiveThrottled(target: targetDescription, classification: "aucune action — \(magnitude)")
            return
        }
        updateLiveThrottled(target: targetDescription, classification: "Rouvrir — \(magnitude)")
        dockActionPreviewController.show(
            glyph: .symbol(name: "plus", tint: .yellow),
            near: ScreenGeometry.appKitRect(fromQuartz: item.frame)
        )
    }

    /// Raw numbers behind whatever classification decision was made — shown live in the
    /// panel so a gesture that isn't triggering anything can be diagnosed by watching the
    /// numbers (is the kind wrong? is the magnitude below threshold?) instead of guessing.
    private func magnitudeDescription(for stroke: GestureStroke) -> String {
        switch stroke.kind {
        case .magnify:
            return String(format: "pincement %.3f (seuil %.3f)", stroke.magnification, gestureSettings.pinchThreshold)
        case .translation:
            let t = stroke.averageTranslation
            return String(format: "dx %.0f dy %.0f (seuil %.0f)", t.dx, t.dy, gestureSettings.minimumSwipeDistance)
        }
    }

    private func hideAllPreviews() {
        snapPreviewController.hide()
        dockActionPreviewController.hide()
        windowActionBadgeController.hide()
    }

    // MARK: - Applying on release

    /// Applies whatever the gesture's translation/pinch classifies as, to whichever
    /// window/Dock icon it started over — logging the outcome either way so a swipe that
    /// seemingly did nothing can be diagnosed from the control panel.
    private func handleStrokeEnded(_ stroke: GestureStroke) {
        hideAllPreviews()
        defer { activeGestureTarget = nil }

        switch activeGestureTarget {
        case .window(let located):
            applyWindowAction(stroke: stroke, located: located)
        case .dockItem(let item):
            applyDockAction(stroke: stroke, item: item)
        case nil:
            activityLog.record("Geste ignoré (pas sur une barre de titre ni le Dock)")
        }
    }

    private func applyWindowAction(stroke: GestureStroke, located: WindowLocator.Located) {
        guard let action = GestureClassifier.action(for: stroke, settings: gestureSettings) else {
            activityLog.record("Geste ignoré (trop court)")
            return
        }
        // `WindowSnapper.apply` itself hops to a background queue for the actual
        // Accessibility calls (a slow/unresponsive target app would otherwise freeze
        // Flick's own UI) and calls back on main.
        WindowSnapper.apply(action, to: located) { [weak self] failure in
            guard let self else { return }
            self.activityLog.record(self.logLine("Fenêtre", action.description, failure: failure))
        }
    }

    private func applyDockAction(stroke: GestureStroke, item: DockItemLocator.Located) {
        guard let action = DockGestureClassifier.action(for: stroke, settings: gestureSettings) else {
            activityLog.record("Geste ignoré (trop court)")
            return
        }
        if item.kind == .minimizedWindow {
            applyMinimizedWindowAction(action, item: item)
            return
        }
        let name = item.displayName.isEmpty ? "L'app" : item.displayName
        let wasRunning = AppLifecycleController.isRunning(item)
        // Called on main, as `AppLifecycleController.apply` expects: it resolves the
        // `NSRunningApplication` here on main (AppKit isn't safe off-main) and only hops
        // to a background queue internally for the raw Accessibility calls that could
        // otherwise hang if the target app is slow to respond.
        AppLifecycleController.apply(action, to: item) { [weak self] failure in
            guard let self else { return }
            self.activityLog.record(self.logLine(name, action.description(isRunning: wasRunning), failure: failure))
        }
    }

    /// Only `.unminimize` (swipe up) does anything for a minimized-window Dock thumbnail —
    /// see `updateMinimizedWindowPreview`. Every other classified gesture is logged as
    /// ignored instead of silently doing nothing, so it's diagnosable from the panel.
    private func applyMinimizedWindowAction(_ action: DockAction, item: DockItemLocator.Located) {
        let name = item.displayName.isEmpty ? "Cette fenêtre" : item.displayName
        guard action == .unminimize else {
            activityLog.record("\(name) → geste ignoré (seul glisser vers le haut rouvre une fenêtre réduite)")
            return
        }
        let failure = AppLifecycleController.restore(item)
        activityLog.record(logLine(name, "Rouvrir", failure: failure))
    }

    private func logLine(_ subject: String, _ actionDescription: String, failure: String?) -> String {
        guard let failure else { return "\(subject) → \(actionDescription)" }
        return "\(subject) → \(actionDescription) — échec (\(failure))"
    }

    // MARK: - Dock action icon

    /// Mirrors macOS's own traffic-light icons (×, −, ⤢) instead of a text pill.
    /// `isRunning` is passed in rather than recomputed here — the caller already resolved
    /// it once for the log line, and this runs on every gesture update (up to 120×/second
    /// while a Dock swipe is in progress), so recomputing it via a second
    /// `NSWorkspace.runningApplications` scan per frame would double that cost.
    private func dockPreviewIcon(for action: DockAction, isRunning: Bool) -> ActionBadgeView.Glyph {
        switch action {
        case .quit:
            return .badge(assetName: "quitter")
        case .newWindow:
            return isRunning
                ? .badge(assetName: "agrandir")
                : .symbol(name: "questionmark", tint: .secondary)
        case .minimizeFrontmost:
            return .badge(assetName: "reduire")
        case .unminimize:
            return isRunning
                ? .symbol(name: "plus", tint: .yellow)
                : .symbol(name: "questionmark", tint: .secondary)
        case .cycleNext:
            return .symbol(name: "arrow.right", tint: .accentColor)
        case .cyclePrevious:
            return .symbol(name: "arrow.left", tint: .accentColor)
        }
    }
}

private extension SnapAction {
    var description: String {
        switch self {
        case .leftHalf: return "Moitié gauche"
        case .rightHalf: return "Moitié droite"
        case .topLeftQuarter: return "Quart haut-gauche"
        case .topRightQuarter: return "Quart haut-droit"
        case .bottomLeftQuarter: return "Quart bas-gauche"
        case .bottomRightQuarter: return "Quart bas-droit"
        case .maximize: return "Plein écran"
        case .minimize: return "Minimiser"
        case .close: return "Fermer"
        }
    }
}

private extension DockAction {
    func description(isRunning: Bool) -> String {
        switch self {
        case .quit: return "Quitter"
        case .newWindow: return isRunning ? "Nouvelle fenêtre" : "App non lancée"
        case .minimizeFrontmost: return "Minimiser"
        case .unminimize: return isRunning ? "Désminimiser" : "App non lancée"
        case .cycleNext: return "Fenêtre suivante"
        case .cyclePrevious: return "Fenêtre précédente"
        }
    }
}

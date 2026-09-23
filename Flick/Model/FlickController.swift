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
            updateLiveThrottled(target: "Fenêtre", classification: "aucune action — \(magnitude)")
            return
        }
        updateLiveThrottled(target: "Fenêtre", classification: "\(action.description) — \(magnitude)")
        guard let region = WindowSnapper.normalizedRegion(for: action) else {
            snapPreviewController.hide()
            return
        }
        snapPreviewController.show(region: region, near: NSEvent.mouseLocation)
    }

    private func updateDockPreview(stroke: GestureStroke, item: DockItemLocator.Located) {
        snapPreviewController.hide()
        let magnitude = magnitudeDescription(for: stroke)
        let targetDescription = "Dock : \(item.displayName.isEmpty ? "?" : item.displayName)"
        guard let action = DockGestureClassifier.action(for: stroke, settings: gestureSettings) else {
            dockActionPreviewController.hide()
            updateLiveThrottled(target: targetDescription, classification: "aucune action — \(magnitude)")
            return
        }
        let isRunning = AppLifecycleController.isRunning(item)
        updateLiveThrottled(target: targetDescription, classification: "\(action.description(isRunning: isRunning)) — \(magnitude)")
        let icon = dockPreviewIcon(for: action, item: item)
        dockActionPreviewController.show(
            systemImage: icon.image, tint: icon.tint,
            above: ScreenGeometry.appKitRect(fromQuartz: item.frame)
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

    private func logLine(_ subject: String, _ actionDescription: String, failure: String?) -> String {
        guard let failure else { return "\(subject) → \(actionDescription)" }
        return "\(subject) → \(actionDescription) — échec (\(failure))"
    }

    // MARK: - Dock action icon

    /// Big colored circle + glyph, mirroring macOS's own traffic-light icons (×, −, ⤢)
    /// instead of a text pill.
    private func dockPreviewIcon(for action: DockAction, item: DockItemLocator.Located) -> (image: String, tint: Color) {
        let isRunning = AppLifecycleController.isRunning(item)

        switch action {
        case .quit:
            return ("xmark", .red)
        case .newWindow:
            return isRunning ? ("arrow.up.left.and.arrow.down.right", .green) : ("questionmark", .secondary)
        case .minimizeFrontmost:
            return ("minus", .yellow)
        case .unminimize:
            return isRunning ? ("plus", .yellow) : ("questionmark", .secondary)
        case .cycleNext:
            return ("arrow.right", .accentColor)
        case .cyclePrevious:
            return ("arrow.left", .accentColor)
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

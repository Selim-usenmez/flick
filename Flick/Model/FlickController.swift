import AppKit
import ApplicationServices
import Observation
import Sparkle
import SwiftUI

/// Owns the pieces that make up Flick's gesture pipeline and the app's on/off state.
@Observable
final class FlickController {
    let accessibilityPermission = AccessibilityPermission()
    let launchAtLogin = LaunchAtLoginManager()
    let gestureMonitor = TouchGestureMonitor()
    let gestureSettings = GestureSettings()
    let activityLog = GestureActivityLog()
    private(set) var isEnabled = false
    /// Mirrors the HUD panel's actual visibility as observable state, so the menu bar's
    /// checkmark updates the moment it's toggled (the panel controller itself isn't
    /// observable, and reading it through a computed property gave SwiftUI nothing to
    /// track — the checkmark only caught up on some later, unrelated re-render).
    private(set) var isDebugHUDVisible = false

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
    private lazy var targetResolver = GestureTargetResolver(gestureSettings: gestureSettings)
    @ObservationIgnored
    private let snapPreviewController = SnapPreviewPanelController()
    @ObservationIgnored
    private let actionBadgeController = ActionBadgePanelController()

    // MARK: Per-gesture state
    //
    // All of it is internal bookkeeping written at gesture-frame rate; none of it drives a
    // view, so it stays out of Observation tracking.

    /// Resolved once at the start of the current gesture (asynchronously — see
    /// `GestureTargetResolver`). Reused at the end so the preview and the actually-applied
    /// action always agree, even if the cursor drifts mid-swipe.
    @ObservationIgnored private var activeGestureTarget: GestureTarget?
    /// Incremented every time a gesture begins or is cancelled. A resolution that comes
    /// back for an older generation (the user already lifted and started another gesture,
    /// or the stroke was cancelled meanwhile) is discarded instead of being applied to
    /// whatever gesture happens to be current now.
    @ObservationIgnored private var gestureGeneration = 0
    @ObservationIgnored private var isResolvingTarget = false
    /// The most recent stroke update while the target was still being resolved — replayed
    /// as a preview the moment resolution lands, so the badge doesn't wait for the next
    /// finger movement to appear.
    @ObservationIgnored private var latestStroke: GestureStroke?
    /// A stroke that ended while its target was still being resolved. Applied as soon as
    /// the target lands (a quick flick can finish in well under the time a busy app takes
    /// to answer an Accessibility query) — unless it's older than `pendingEndGracePeriod`.
    @ObservationIgnored private var pendingEndedStroke: GestureStroke?
    @ObservationIgnored private var pendingEndedAt: CFAbsoluteTime = 0
    /// Which screen edge the Dock sits on, read once per Dock gesture rather than on every
    /// preview frame — it's a `CFPreferences` lookup.
    @ObservationIgnored private var activeDockEdge: DockEdge = .bottom
    /// The one deferred preview decision currently in flight, if any — see
    /// `schedulePreviewUpdate`.
    @ObservationIgnored private var pendingPreviewUpdate: (() -> Void)?
    @ObservationIgnored private var hasScheduledPreviewUpdate = false
    /// Throttles only `updateLiveThrottled` (the HUD's `activityLog` text) — multitouch
    /// frames can arrive at 60-120Hz, far faster than that SwiftUI view graph can absorb
    /// without exceeding AppKit's per-flush constraint-update budget and crashing with "too
    /// many Update Constraints". The preview panels' own frame updates are *not* throttled
    /// by this — repositioning a panel is cheap and a no-op when unchanged, so it stays at
    /// raw gesture rate for a fluid, finger-tracking preview.
    @ObservationIgnored private var lastLiveTextUpdateTime: CFAbsoluteTime = 0
    /// The magnify stroke's stabilized open/closed reading for the current gesture — see
    /// `stableIsOpen`. Reset at the start of every gesture.
    @ObservationIgnored private var stableMagnifyIsOpen: Bool?

    /// How much further past the ordinary commit threshold a magnify stroke has to swing,
    /// in the *opposite* direction, before the shown/applied direction flips away from
    /// whichever one is already stable. Without this, a small, imprecise back-and-forth
    /// in raw inter-finger distance — e.g. drawing little circles instead of a clean
    /// pinch — re-crosses the plain threshold on both sides constantly, and the preview
    /// badge flickers between maximize/close (or newWindow/minimize) on every wobble.
    private static let magnifyFlipMultiplier: CGFloat = 1.75
    // 1/30s wasn't conservative enough in practice — a sustained gesture (e.g. holding a
    // Dock quit swipe) still hit the same "too many Update Constraints" crash this is meant
    // to prevent. 1/8s matches TouchGestureMonitor.diagnosticFlushInterval, the rate that's
    // actually confirmed safe for this same HUD view graph.
    private static let liveTextUpdateInterval: CFAbsoluteTime = 1.0 / 8.0
    /// See `pendingEndedStroke`.
    private static let pendingEndGracePeriod: CFAbsoluteTime = 1.0

    init() {
        gestureMonitor.onStrokeBegan = { [weak self] location in
            self?.handleStrokeBegan(at: location)
        }
        gestureMonitor.onStrokeUpdated = { [weak self] stroke in
            self?.handleStrokeUpdated(stroke)
        }
        gestureMonitor.onStrokeEnded = { [weak self] stroke in
            self?.handleStrokeEnded(stroke)
        }
        gestureMonitor.onStrokeCancelled = { [weak self] in
            self?.handleStrokeCancelled()
        }

        // Turn gestures on immediately if accessibility is already granted, so launching
        // the app is enough to start using it — no hunting through the menu bar first.
        // Permission is often granted only after launch (the normal flow: launch, then
        // check the box in System Settings), so the same auto-enable has to also happen
        // on that later transition, not just here. The debug HUD panel is deliberately
        // *not* shown here — it only appears when explicitly toggled (menu bar or
        // Preferences), never uninvited on launch.
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
        isDebugHUDVisible = hudPanelController.isVisible
    }

    // MARK: - Gesture lifecycle

    private func handleStrokeBegan(at location: NSPoint) {
        gestureGeneration += 1
        let generation = gestureGeneration
        activeGestureTarget = nil
        latestStroke = nil
        pendingEndedStroke = nil
        stableMagnifyIsOpen = nil
        isResolvingTarget = true

        targetResolver.resolve(at: location) { [weak self] target in
            guard let self, self.gestureGeneration == generation else { return }
            self.isResolvingTarget = false
            self.activeGestureTarget = target
            if case .dockItem = target { self.activeDockEdge = DockEdge.current }

            if let ended = self.pendingEndedStroke {
                self.pendingEndedStroke = nil
                if CFAbsoluteTimeGetCurrent() - self.pendingEndedAt <= Self.pendingEndGracePeriod {
                    self.finish(ended)
                } else {
                    self.activityLog.record("Geste ignoré (cible résolue trop tard)")
                    self.activeGestureTarget = nil
                }
            } else if let stroke = self.latestStroke {
                self.updatePreview(for: stroke)
            }
        }
    }

    private func handleStrokeUpdated(_ stroke: GestureStroke) {
        latestStroke = stroke
        guard !isResolvingTarget else { return }
        updatePreview(for: stroke)
    }

    private func handleStrokeEnded(_ stroke: GestureStroke) {
        hideAllPreviews()
        if isResolvingTarget {
            pendingEndedStroke = stroke
            pendingEndedAt = CFAbsoluteTimeGetCurrent()
            return
        }
        finish(stroke)
    }

    /// The monitor gave up on the stroke (lost terminating event, sensor went quiet) —
    /// nothing is applied, and any in-flight resolution for it is invalidated.
    private func handleStrokeCancelled() {
        gestureGeneration += 1
        isResolvingTarget = false
        activeGestureTarget = nil
        latestStroke = nil
        pendingEndedStroke = nil
        hideAllPreviews()
        updateLiveThrottled(target: "—", classification: "geste abandonné", force: true)
    }

    /// Applies whatever the gesture's translation/pinch classifies as, to whichever
    /// window/Dock icon it started over — logging the outcome either way so a swipe that
    /// seemingly did nothing can be diagnosed from the control panel.
    private func finish(_ stroke: GestureStroke) {
        defer { activeGestureTarget = nil }
        switch activeGestureTarget {
        case .window(let located, let ratios, _):
            applyWindowAction(stroke: stroke, located: located, ratios: ratios)
        case .dockItem(let item, let isRunning):
            applyDockAction(stroke: stroke, item: item, wasRunning: isRunning)
        case nil:
            activityLog.record("Geste ignoré (pas sur une barre de titre ni le Dock)")
        }
    }

    // MARK: - Classification

    /// The magnify stroke's open/closed reading, stabilized against small wobble — see
    /// `magnifyFlipMultiplier`. `nil` below the ordinary commit threshold, same as the
    /// raw check in `GestureClassifier`/`DockGestureClassifier`. Both the live preview and
    /// the action actually applied at release go through this (via `windowAction`/
    /// `dockAction` below), so they always agree, even mid-wobble.
    private func stableIsOpen(for stroke: GestureStroke) -> Bool? {
        let magnitude = stroke.magnification
        guard abs(magnitude) >= gestureSettings.pinchThreshold else { return nil }
        let rawIsOpen = (magnitude > 0) != gestureSettings.invertPinch

        if let stable = stableMagnifyIsOpen, stable != rawIsOpen {
            guard abs(magnitude) >= gestureSettings.pinchThreshold * Self.magnifyFlipMultiplier else {
                return stable
            }
        }
        stableMagnifyIsOpen = rawIsOpen
        return rawIsOpen
    }

    /// `GestureClassifier.action`, but routed through `stableIsOpen` for magnify strokes
    /// instead of its own raw zero-crossing check.
    private func windowAction(for stroke: GestureStroke) -> SnapAction? {
        switch stroke.kind {
        case .magnify:
            return stableIsOpen(for: stroke).map { $0 ? .maximize : .close }
        case .translation:
            return GestureClassifier.action(for: stroke, settings: gestureSettings)
        }
    }

    /// `DockGestureClassifier.action`, but routed through `stableIsOpen` for magnify
    /// strokes instead of its own raw zero-crossing check.
    private func dockAction(for stroke: GestureStroke) -> DockAction? {
        switch stroke.kind {
        case .magnify:
            return stableIsOpen(for: stroke).map { $0 ? .newWindow : .minimizeFrontmost }
        case .translation:
            return DockGestureClassifier.action(for: stroke, settings: gestureSettings)
        }
    }

    // MARK: - Live preview

    private func updatePreview(for stroke: GestureStroke) {
        // The whole decision below is wrapped in `schedulePreviewUpdate` rather than run
        // directly: multitouch/scroll updates can arrive up to 120×/second, and under a
        // fast gesture, independently deferred panels could each drain their own backlog
        // in a different order — occasionally landing two of them visible at once, since
        // whichever panel still had older queued work could show *after* another panel's
        // fresher "hide". Making this one decision — which single panel (if any) should be
        // visible right now — and deferring it as a single unit keeps that decision
        // atomic: exactly one outcome ever applies, and a burst of calls collapses to just
        // the latest one.
        schedulePreviewUpdate { [self] in
            switch activeGestureTarget {
            case .window(_, let ratios, _):
                updateWindowPreview(stroke: stroke, ratios: ratios)
            case .dockItem(let item, let isRunning):
                updateDockPreview(stroke: stroke, item: item, isRunning: isRunning)
            case nil:
                hideAllPreviews()
                updateLiveThrottled(target: "Aucune (ni barre de titre, ni Dock)", classification: "—")
            }
        }
    }

    /// Defers `work` by one run-loop turn (matching the AppKit re-entrancy guard the
    /// panel controllers used to each implement individually), but keeps only the
    /// *latest* pending call instead of queuing every single one — see the comment in
    /// `updatePreview` for why a per-panel version of this let two panels show at once.
    private func schedulePreviewUpdate(_ work: @escaping () -> Void) {
        pendingPreviewUpdate = work
        guard !hasScheduledPreviewUpdate else { return }
        hasScheduledPreviewUpdate = true
        DispatchQueue.main.async { [self] in
            hasScheduledPreviewUpdate = false
            let work = pendingPreviewUpdate
            pendingPreviewUpdate = nil
            work?()
        }
    }

    /// The HUD's live readout. Skipped entirely while the HUD is closed — the strings are
    /// passed as autoclosures so none of the per-frame `String(format:)` work happens
    /// unless something is actually going to display it.
    private func updateLiveThrottled(
        target: @autoclosure () -> String, classification: @autoclosure () -> String,
        grid: GestureGridKind = .none, cell: GestureGridPosition? = nil, force: Bool = false
    ) {
        guard isDebugHUDVisible else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard force || now - lastLiveTextUpdateTime >= Self.liveTextUpdateInterval else { return }
        lastLiveTextUpdateTime = now
        activityLog.updateLive(target: target(), classification: classification(), grid: grid, cell: cell)
    }

    private func updateWindowPreview(stroke: GestureStroke, ratios: SnapZoneRatios) {
        guard let action = windowAction(for: stroke) else {
            hideAllPreviews()
            updateLiveThrottled(target: "Fenêtre", classification: "aucune action — \(magnitudeDescription(for: stroke))")
            return
        }
        updateLiveThrottled(
            target: "Fenêtre", classification: "\(action.description) — \(magnitudeDescription(for: stroke))",
            grid: .title, cell: gridPosition(for: action)
        )
        // Close/minimize don't resize the window into a region worth previewing as a
        // rectangle — they get a traffic-light-style badge instead, matching the ones
        // already used for Dock gestures. Maximize falls through to the rectangle path
        // below instead (see `windowActionBadge`'s doc comment).
        if let glyph = windowActionBadge(for: action) {
            snapPreviewController.hide()
            actionBadgeController.show(glyph: glyph, near: NSEvent.mouseLocation)
            return
        }
        actionBadgeController.hide()
        guard let region = WindowSnapper.normalizedRegion(for: action, ratios: ratios) else {
            snapPreviewController.hide()
            return
        }
        snapPreviewController.show(region: region, near: NSEvent.mouseLocation)
    }

    /// Close and minimize don't resize the window into a region worth previewing, so they
    /// get a custom badge instead (see `Assets.xcassets/Actions`). Maximize **does** have a
    /// well-defined target region (the full screen — see `WindowSnapper.normalizedRegion`),
    /// so unlike the other two it keeps the same rectangle mini-preview as the half/quarter
    /// snaps rather than the green badge, to actually show the full-screen region filling in
    /// light blue instead of just a generic "this will maximize" icon.
    private func windowActionBadge(for action: SnapAction) -> ActionBadgeView.Glyph? {
        switch action {
        case .close: return .badge(assetName: "fermer")
        case .minimize: return .badge(assetName: "reduire")
        default: return nil
        }
    }

    private func updateDockPreview(stroke: GestureStroke, item: DockItemLocator.Located, isRunning: Bool) {
        snapPreviewController.hide()

        if item.kind == .minimizedWindow {
            updateMinimizedWindowPreview(stroke: stroke, item: item)
            return
        }

        guard let action = dockAction(for: stroke) else {
            actionBadgeController.hide()
            updateLiveThrottled(
                target: "Dock : \(item.displayName.isEmpty ? "?" : item.displayName)",
                classification: "aucune action — \(magnitudeDescription(for: stroke))"
            )
            return
        }
        updateLiveThrottled(
            target: "Dock : \(item.displayName.isEmpty ? "?" : item.displayName)",
            classification: "\(action.description(isRunning: isRunning)) — \(magnitudeDescription(for: stroke))",
            grid: .dock, cell: gridPosition(for: action)
        )
        actionBadgeController.show(
            glyph: dockPreviewIcon(for: action, isRunning: isRunning),
            besideDockIcon: ScreenGeometry.appKitRect(fromQuartz: item.frame),
            dockEdge: activeDockEdge
        )
    }

    /// A minimized-window Dock thumbnail (the section right before the Trash) only
    /// supports one gesture — swipe up to restore it, the same `AXPress` a click sends.
    /// Accessibility gives no way to resolve which app a thumbnail belongs to (see
    /// `DockItemLocator.Kind`), so unlike a regular app icon, nothing else (quit, cycle
    /// windows...) can be driven reliably from here.
    private func updateMinimizedWindowPreview(stroke: GestureStroke, item: DockItemLocator.Located) {
        guard dockAction(for: stroke) == .unminimize else {
            actionBadgeController.hide()
            updateLiveThrottled(
                target: "Fenêtre réduite : \(item.displayName.isEmpty ? "?" : item.displayName)",
                classification: "aucune action — \(magnitudeDescription(for: stroke))"
            )
            return
        }
        updateLiveThrottled(
            target: "Fenêtre réduite : \(item.displayName.isEmpty ? "?" : item.displayName)",
            classification: "Rouvrir — \(magnitudeDescription(for: stroke))"
        )
        actionBadgeController.show(
            glyph: .symbol(name: "plus", tint: .yellow),
            besideDockIcon: ScreenGeometry.appKitRect(fromQuartz: item.frame),
            dockEdge: activeDockEdge
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

    /// Also drops any preview decision still queued in `schedulePreviewUpdate` — the stroke
    /// is over, and letting a stale "show" land one run-loop turn after this hide would
    /// leave a badge stranded on screen with no gesture behind it.
    private func hideAllPreviews() {
        pendingPreviewUpdate = nil
        snapPreviewController.hide()
        actionBadgeController.hide()
    }

    // MARK: - Applying on release

    private func applyWindowAction(stroke: GestureStroke, located: WindowLocator.Located, ratios: SnapZoneRatios) {
        guard let action = windowAction(for: stroke) else {
            activityLog.record("Geste ignoré (trop court)")
            return
        }
        // `WindowSnapper.apply` itself hops to a background queue for the actual
        // Accessibility calls (a slow/unresponsive target app would otherwise freeze
        // Flick's own UI) and calls back on main.
        WindowSnapper.apply(action, to: located, ratios: ratios) { [weak self] failure in
            guard let self else { return }
            self.activityLog.record(self.logLine("Fenêtre", action.description, failure: failure))
            if failure == nil {
                self.armAdaptiveWatcher(for: action, window: located)
            }
        }
    }

    /// Starts `AdaptiveSnapZones` watching the just-snapped window for a few seconds, in
    /// case the user manually corrects it right after — see that type's doc comment.
    private func armAdaptiveWatcher(for action: SnapAction, window located: WindowLocator.Located) {
        guard let bundleID = NSRunningApplication(processIdentifier: located.pid)?.bundleIdentifier else { return }
        AdaptiveSnapZones.shared.observeForAdjustment(
            after: action, window: located.axWindow, pid: located.pid, bundleID: bundleID
        )
    }

    private func applyDockAction(stroke: GestureStroke, item: DockItemLocator.Located, wasRunning: Bool) {
        guard let action = dockAction(for: stroke) else {
            activityLog.record("Geste ignoré (trop court)")
            return
        }
        let name = item.displayName.isEmpty ? "L'app" : item.displayName
        if item.kind == .minimizedWindow {
            applyMinimizedWindowAction(action, item: item, name: name)
            return
        }
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
    private func applyMinimizedWindowAction(_ action: DockAction, item: DockItemLocator.Located, name: String) {
        guard action == .unminimize else {
            activityLog.record("\(name) → geste ignoré (seul glisser vers le haut rouvre une fenêtre réduite)")
            return
        }
        AppLifecycleController.restore(item) { [weak self] failure in
            guard let self else { return }
            self.activityLog.record(self.logLine(name, "Rouvrir", failure: failure))
        }
    }

    private func logLine(_ subject: String, _ actionDescription: String, failure: String?) -> String {
        guard let failure else { return "\(subject) → \(actionDescription)" }
        return "\(subject) → \(actionDescription) — échec (\(failure))"
    }

    // MARK: - Dock action icon

    /// Mirrors macOS's own traffic-light icons (×, −, ⤢) instead of a text pill.
    /// `isRunning` was resolved once with the gesture's target — this runs on every
    /// gesture update (up to 120×/second while a Dock swipe is in progress), far too often
    /// to rescan `NSWorkspace.runningApplications` each time.
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

    // MARK: - HUD active-cell mapping

    /// Where a resolved window action lights up in the title-bar `GestureGrid` — `nil` for
    /// `.close`, which has no dedicated cell (only the caption below the grid mentions it).
    private func gridPosition(for action: SnapAction) -> GestureGridPosition? {
        switch action {
        case .leftHalf: return .left
        case .rightHalf: return .right
        case .topLeftQuarter: return .topLeft
        case .topRightQuarter: return .topRight
        case .bottomLeftQuarter: return .bottomLeft
        case .bottomRightQuarter: return .bottomRight
        case .maximize: return .top
        case .minimize: return .bottom
        case .close: return nil
        }
    }

    /// Where a resolved Dock action lights up in the Dock `GestureGrid` — `nil` for the
    /// pinch-only actions (`.newWindow`/`.minimizeFrontmost`), which have no dedicated cell.
    private func gridPosition(for action: DockAction) -> GestureGridPosition? {
        switch action {
        case .quit: return .bottom
        case .unminimize: return .top
        case .cycleNext: return .right
        case .cyclePrevious: return .left
        case .newWindow, .minimizeFrontmost: return nil
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

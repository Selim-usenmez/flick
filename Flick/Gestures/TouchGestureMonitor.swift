import AppKit
import Observation

/// Global trackpad event capture.
///
/// Two different mechanisms feed this, because `NSEvent.addGlobalMonitorForEvents` only
/// supports a fixed, documented set of event types (mouse, keyboard, scroll wheel...) —
/// pinch/rotate and the gesture-bracket events are never delivered through it, or through
/// even a raw session-wide `CGEventTap`, for a gesture happening over *another app's*
/// window (confirmed empirically: a tap that successfully activates still receives zero
/// events for `.magnify`). AppKit apparently only ever routes those to the frontmost app.
///
/// So: `.scrollWheel`/`.swipe` (which *are* delivered) go through the ordinary NSEvent
/// monitors below. Pinch instead goes through `MultitouchSupport`, which reads raw finger
/// contacts directly from the trackpad driver — see `handleMultitouchFrame`.
///
/// Note also that events read this way have no associated view in this process, so
/// `NSEvent.allTouches()` is not usable here — it raises `-[NSEvent
/// touchesMatchingPhase:inView:]` unconditionally for a globally-monitored event. Per-gesture
/// displacement is reconstructed instead from each event type's own delta properties.
///
/// Bindings are meant to be evaluated only while the cursor is over a title bar or Dock icon
/// (see `WindowLocator`/`DockItemLocator`) — a swipe over a window's body would also scroll
/// its content, since the NSEvent monitor can't swallow/consume events for other apps.
@Observable
final class TouchGestureMonitor {
    /// The in-progress gesture's accumulated data. Written on every raw event (up to
    /// 120×/second), so deliberately kept out of Observation tracking — nothing renders it
    /// directly, and routing that write rate through the registrar is pure overhead.
    @ObservationIgnored private(set) var stroke = GestureStroke()
    private(set) var lastEventTypeDescription: String = "—"
    private(set) var isMonitoring = false
    private(set) var isStrokeActive = false
    /// Whether `MultitouchSupport` actually loaded and started — distinct from
    /// `isMonitoring`, so a failure specific to it is visible even though swipe-based
    /// gestures (on the separate NSEvent monitors) keep working regardless.
    private(set) var isMultitouchActive = false
    /// Count of raw multitouch frames received, regardless of finger count — proves the
    /// private API is actually delivering data even if no pinch has crossed threshold yet.
    /// Refreshed at `diagnosticFlushInterval`, not on every frame — see that constant.
    private(set) var multitouchFrameCount = 0
    private(set) var lastTapDiagnostic: String = "—"

    /// Fired once, right as a new gesture starts, with the screen point it started at —
    /// lets a caller resolve which window/title-bar it applies to before any displacement
    /// has accumulated.
    @ObservationIgnored var onStrokeBegan: ((NSPoint) -> Void)?
    /// Fired every time the in-progress gesture's accumulated displacement changes.
    @ObservationIgnored var onStrokeUpdated: ((GestureStroke) -> Void)?
    @ObservationIgnored var onStrokeEnded: ((GestureStroke) -> Void)?
    /// Fired when an in-progress gesture is abandoned *without* reaching a normal end —
    /// the watchdog decided its terminating event was lost (see `checkStrokeLiveness`),
    /// or monitoring stopped mid-gesture. Nothing should be applied; previews just go away.
    @ObservationIgnored var onStrokeCancelled: (() -> Void)?

    @ObservationIgnored private var globalMonitor: Any?
    @ObservationIgnored private var localMonitor: Any?
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    /// Raw inter-finger-distance tracking, one entry per physical multitouch device
    /// (keyed by the `MTDeviceRef` `MultitouchSupport` tags each frame with). A Mac can
    /// have more than one such device active at once — a MacBook's built-in trackpad plus
    /// a Bluetooth Magic Trackpad or Magic Mouse, say — and their frames are separate,
    /// unrelated streams; sharing one scalar distance/delta between them would let an
    /// unrelated device's frame land in between two frames from the real one, corrupting
    /// the delta with a jump that has nothing to do with either device's actual motion.
    @ObservationIgnored private var pinchTrackingByDevice: [UnsafeMutableRawPointer: PinchTrackingState] = [:]
    /// Which device's frames committed the currently-active magnify stroke, if any — once
    /// one device has committed to a pinch, a second device reporting its own incidental
    /// two-finger contact (e.g. a hand resting on a nearby Magic Mouse while the real pinch
    /// happens on the trackpad) must not be able to inject its delta into that same stroke.
    @ObservationIgnored private var activeMagnifyDevice: UnsafeMutableRawPointer?

    private struct PinchTrackingState {
        var lastDistance: CGFloat?
        /// Distance-delta accumulated *before* committing to a magnify-kind stroke — see
        /// `handleMultitouchFrame`.
        var pendingDelta: CGFloat = 0
        /// Consecutive multitouch frames in a row that didn't report exactly two touching
        /// fingers — see `nonPinchFrameGrace`.
        var consecutiveNonPinchFrames = 0
        /// Fingers touching this device as of its most recent frame — see `anyFingerDown`.
        var touchingCount = 0
    }

    /// What one raw multitouch frame boils down to, computed on the driver's thread so only
    /// these few bytes cross to main instead of a freshly allocated finger array per frame.
    private struct MultitouchSample {
        let device: UnsafeMutableRawPointer
        let touchingCount: Int
        /// Normalized distance between the two fingers, when exactly two are touching.
        let pairDistance: CGFloat?
    }

    @ObservationIgnored private var rawMultitouchFrameCount = 0
    @ObservationIgnored private var lastDiagnosticFlushTime: CFAbsoluteTime = 0
    @ObservationIgnored private var pendingEventDescription: String?
    @ObservationIgnored private var pendingTapDescription: String?

    // MARK: Stroke liveness

    /// Time of the last event that proved the current gesture is still physically
    /// happening: a scroll-phase event, or a multitouch frame with at least one finger down.
    @ObservationIgnored private var lastStrokeActivityTime: CFAbsoluteTime = 0
    /// Time of the last multitouch frame with at least one finger on *any* device.
    @ObservationIgnored private var lastFingerDownTime: CFAbsoluteTime = 0
    /// Time of the last multitouch frame of any kind, and when the current stroke began —
    /// the sensor's "no fingers down" verdict is only trusted once it has actually
    /// reported *something* during this stroke (see `checkStrokeLiveness`).
    @ObservationIgnored private var lastMultitouchFrameTime: CFAbsoluteTime = 0
    @ObservationIgnored private var strokeBeganTime: CFAbsoluteTime = 0
    @ObservationIgnored private var livenessTimer: Timer?
    @ObservationIgnored private var deviceRefreshTimer: Timer?

    /// Minimum finger size (as reported by MultitouchSupport) to count as an actual touch
    /// rather than a hover/proximity report some trackpads emit.
    private static let minimumFingerSize: Float = 0.0
    /// Raw inter-finger distance change required before committing to a magnify-kind
    /// stroke — see `handleMultitouchFrame`.
    private static let pinchCommitThreshold: CGFloat = 0.02
    /// Trackpad hardware can occasionally report a finger's contact dropping out for a
    /// single frame in the middle of a deliberate, sustained pinch (sensor noise, not the
    /// user actually lifting off). Requiring this many consecutive non-2-finger frames
    /// before treating the pinch as over rides through that blip instead of fragmenting
    /// one physical gesture into several sub-threshold ones. At 60-120Hz this is at most
    /// ~30ms — imperceptible for a genuine finger lift.
    private static let nonPinchFrameGrace = 2
    /// Diagnostic text/counters shown in the control panel are purely cosmetic, but were
    /// being written on every single raw event — multitouch frames alone can arrive at
    /// 60-120Hz. Writing `@Observable` properties that fast forced the panel's SwiftUI
    /// view to re-layout far faster than any display cycle could keep up with, which is
    /// what was tripping a "too many Update Constraints in Window" crash — even during a
    /// plain swipe, not just a pinch. The *functional* gesture-tracking state (`stroke`,
    /// `isStrokeActive`) still updates every frame regardless, since that has to stay
    /// accurate; only the human-readable diagnostics are throttled.
    private static let diagnosticFlushInterval: CFAbsoluteTime = 1.0 / 8.0
    /// How often the watchdog re-checks an in-progress stroke — see `checkStrokeLiveness`.
    private static let livenessCheckInterval: TimeInterval = 0.2
    /// With the multitouch sensor confirming no finger is on any trackpad for this long
    /// while a translation stroke is still marked active, its `.ended` event was lost (not
    /// merely late — the driver reports lift-off within a frame or two).
    private static let fingersUpGrace: CFAbsoluteTime = 0.3
    /// Without any proof of life at all for this long, a stroke is abandoned. With the
    /// multitouch sensor available, resting fingers keep producing frames, so this only
    /// ever fires when the sensor itself went quiet (sleep, device gone) — a user holding a
    /// gesture to look at the preview is never cut off. Without the sensor (private
    /// framework unavailable), scroll events are the only signal and a long hold *could*
    /// trip this, so it's kept generous.
    private static var staleStrokeInterval: CFAbsoluteTime { MultitouchSupport.shared.isAvailable ? 1.5 : 4.0 }
    /// How often to check whether a trackpad was added/removed — see
    /// `MultitouchSupport.deviceListHasChanged`.
    private static let deviceRefreshInterval: TimeInterval = 30

    private let touchEventTypes: NSEvent.EventTypeMask = [.swipe, .scrollWheel]

    func start() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: touchEventTypes) { [weak self] event in
            self?.handle(event)
        }
        // A local monitor covers the case where the cursor is over Flick's own HUD panel,
        // which is otherwise invisible to a global-only monitor.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: touchEventTypes) { [weak self] event in
            self?.handle(event)
            return event
        }

        startMultitouch()
        installWorkspaceObservers()
        deviceRefreshTimer = Timer.scheduledTimer(withTimeInterval: Self.deviceRefreshInterval, repeats: true) { [weak self] _ in
            self?.refreshMultitouchDevicesIfNeeded()
        }

        isMonitoring = true
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        removeWorkspaceObservers()
        deviceRefreshTimer?.invalidate()
        deviceRefreshTimer = nil
        stopMultitouch()
        isMonitoring = false
        cancelActiveStroke()
    }

    // MARK: - Multitouch lifecycle

    private func startMultitouch() {
        MultitouchSupport.shared.onFrame = { [weak self] device, fingers in
            // Reduce on the driver thread; only a few bytes cross to main per frame.
            var touching = 0
            var first: (Float, Float)?
            var second: (Float, Float)?
            for finger in fingers where finger.size > Self.minimumFingerSize {
                touching += 1
                if first == nil { first = (finger.normalizedX, finger.normalizedY) }
                else if second == nil { second = (finger.normalizedX, finger.normalizedY) }
            }
            var pairDistance: CGFloat?
            if touching == 2, let first, let second {
                let dx = CGFloat(first.0 - second.0)
                let dy = CGFloat(first.1 - second.1)
                pairDistance = (dx * dx + dy * dy).squareRoot()
            }
            let sample = MultitouchSample(device: device, touchingCount: touching, pairDistance: pairDistance)
            DispatchQueue.main.async {
                self?.handleMultitouchSample(sample)
            }
        }
        MultitouchSupport.shared.start()
        isMultitouchActive = MultitouchSupport.shared.activeDeviceCount > 0
    }

    private func stopMultitouch() {
        MultitouchSupport.shared.stop()
        MultitouchSupport.shared.onFrame = nil
        isMultitouchActive = false
        pinchTrackingByDevice.removeAll()
        activeMagnifyDevice = nil
    }

    /// Re-enumerates trackpads after the Mac wakes (the driver stops delivering frames to
    /// a pre-sleep registration) or when one was connected/disconnected. Any magnify
    /// stroke in flight is cancelled first — its device pointer is about to go stale.
    private func restartMultitouch() {
        guard isMonitoring else { return }
        if isStrokeActive, stroke.kind == .magnify { cancelActiveStroke() }
        pinchTrackingByDevice.removeAll()
        activeMagnifyDevice = nil
        MultitouchSupport.shared.restart()
        isMultitouchActive = MultitouchSupport.shared.activeDeviceCount > 0
    }

    private func refreshMultitouchDevicesIfNeeded() {
        guard isMonitoring, !isStrokeActive, MultitouchSupport.shared.deviceListHasChanged() else { return }
        restartMultitouch()
    }

    private func installWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ]
        workspaceObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // The driver can take a moment after wake before the device list is
                // trustworthy again; re-enumerating immediately sometimes yields nothing.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self?.restartMultitouch()
                }
            }
        }
    }

    private func removeWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
        workspaceObservers.removeAll()
    }

    // MARK: - Diagnostics

    /// Writes to the cosmetic diagnostic properties, at most `diagnosticFlushInterval`
    /// often — see that constant's doc comment for why this exists at all.
    private func flushDiagnostics(event: String? = nil, tap: @autoclosure () -> String? = nil) {
        if let event { pendingEventDescription = event }

        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastDiagnosticFlushTime >= Self.diagnosticFlushInterval else { return }
        lastDiagnosticFlushTime = now

        if let pendingEventDescription { lastEventTypeDescription = pendingEventDescription }
        multitouchFrameCount = rawMultitouchFrameCount
        if let tap = tap() { lastTapDiagnostic = tap }
    }

    // MARK: - Multitouch frames

    /// Tracks the distance between exactly two touching fingers across frames. Two fingers
    /// touching the trackpad also happens for an ordinary parallel swipe (the gesture that
    /// drives window snapping via `.scrollWheel`) — where that distance stays roughly
    /// constant, unlike a real pinch, where it changes a lot. So this doesn't commit to a
    /// magnify-kind stroke on first contact; it accumulates quietly until the distance has
    /// moved enough to look deliberately like a pinch. That also naturally loses any race
    /// against `.scrollWheel`'s own `.began`, which fires almost immediately on contact —
    /// once that's claimed `isStrokeActive`, `handleMagnifyDelta` backs off on its own.
    private func handleMultitouchSample(_ sample: MultitouchSample) {
        rawMultitouchFrameCount += 1
        let device = sample.device
        var state = pinchTrackingByDevice[device] ?? PinchTrackingState()
        defer { pinchTrackingByDevice[device] = state }
        state.touchingCount = sample.touchingCount

        let now = CFAbsoluteTimeGetCurrent()
        lastMultitouchFrameTime = now
        if sample.touchingCount > 0 {
            lastFingerDownTime = now
            if isStrokeActive { lastStrokeActivityTime = now }
        }

        guard let distance = sample.pairDistance else {
            flushDiagnostics(tap: "\(sample.touchingCount) doigt(s) au contact")
            state.consecutiveNonPinchFrames += 1
            if state.lastDistance != nil, state.consecutiveNonPinchFrames >= Self.nonPinchFrameGrace {
                state.lastDistance = nil
                state.pendingDelta = 0
                if device == activeMagnifyDevice { endMagnifyStroke() }
            }
            return
        }
        state.consecutiveNonPinchFrames = 0
        flushDiagnostics(tap: String(format: "2 doigts, distance %.3f", distance))

        guard let last = state.lastDistance else {
            state.lastDistance = distance
            return
        }
        let delta = distance - last
        state.lastDistance = distance

        if isStrokeActive {
            // Only the device that committed this magnify stroke may keep driving it —
            // see `activeMagnifyDevice`.
            guard device == activeMagnifyDevice else { return }
            handleMagnifyDelta(delta, at: NSEvent.mouseLocation)
            return
        }

        state.pendingDelta += delta
        if abs(state.pendingDelta) >= Self.pinchCommitThreshold {
            let committed = state.pendingDelta
            state.pendingDelta = 0
            activeMagnifyDevice = device
            handleMagnifyDelta(committed, at: NSEvent.mouseLocation)
        }
    }

    /// Whether the most recent frame from any multitouch device still reported a finger
    /// on it — the sensor's own word on whether the user has let go.
    private var anyFingerDown: Bool {
        pinchTrackingByDevice.values.contains { $0.touchingCount > 0 }
    }

    // MARK: - NSEvent monitors

    private func handle(_ event: NSEvent) {
        flushDiagnostics(event: describe(event.type))

        switch event.type {
        case .scrollWheel:
            handleScrollWheel(event)
        case .swipe:
            // Discrete three-finger swipe: no phase stream, so it's a complete gesture
            // in a single event. Guarded against an already-active stroke — trackpad
            // hardware can emit a stray `.swipe` event while a two-finger scroll-phase
            // gesture or a pinch is genuinely still in progress, and unconditionally
            // resetting `stroke`/`isStrokeActive` here would clobber that gesture's state
            // mid-flight (the rest of its `.changed`/`.ended` events would then be
            // silently dropped by the `isStrokeActive` guards below).
            guard !isStrokeActive else { return }
            let location = NSEvent.mouseLocation
            stroke.begin(touchCount: 3, at: location, kind: .translation)
            onStrokeBegan?(location)
            stroke.accumulate(dx: event.deltaX, dy: event.deltaY)
            onStrokeEnded?(stroke)
            stroke.end()
        default:
            break
        }
    }

    /// A two-finger trackpad swipe arrives as a stream of `.scrollWheel` events carrying
    /// `phase`.
    ///
    /// Trackpad hardware can emit incidental scroll-phase events alongside an unrelated
    /// gesture (e.g. a pinch), so every branch is guarded against acting on a stroke it
    /// doesn't own: a spurious `.began` during a magnify stroke would otherwise reset it
    /// back to `.translation` with zeroed accumulators; a spurious `.ended` would otherwise
    /// prematurely terminate a magnify stroke that's still in progress.
    ///
    /// A `.began` while a *translation* stroke is still marked active is a different
    /// story: AppKit never nests scroll gestures, so it can only mean the previous
    /// stroke's `.ended` was lost (it happens — a Space switch or Mission Control
    /// swallowing the tail of the gesture, say). That stale stroke used to pin
    /// `isStrokeActive` forever, silently dropping every gesture after it until the app
    /// was relaunched. It's now discarded so the new gesture can proceed.
    private func handleScrollWheel(_ event: NSEvent) {
        guard event.hasPreciseScrollingDeltas else { return }
        let phase = event.phase
        if phase.contains(.began) {
            if isStrokeActive {
                guard stroke.kind == .translation else { return }
                cancelActiveStroke()
            }
            let location = NSEvent.mouseLocation
            stroke.begin(touchCount: 2, at: location, kind: .translation)
            beginStroke()
            onStrokeBegan?(location)
        } else if phase.contains(.changed) {
            guard isStrokeActive, stroke.kind == .translation else { return }
            lastStrokeActivityTime = CFAbsoluteTimeGetCurrent()
            stroke.accumulate(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
            onStrokeUpdated?(stroke)
        } else if phase.contains(.ended) || phase.contains(.cancelled) {
            guard isStrokeActive, stroke.kind == .translation else { return }
            finishStroke()
        }
    }

    /// Pinch open/closed, driven by `handleMultitouchSample`'s raw finger-distance deltas.
    private func handleMagnifyDelta(_ delta: CGFloat, at location: NSPoint) {
        if !isStrokeActive {
            stroke.begin(touchCount: 2, at: location, kind: .magnify)
            beginStroke()
            onStrokeBegan?(location)
        } else if stroke.kind != .magnify {
            return // A translation stroke owns this moment; don't cross the streams.
        }
        stroke.accumulateMagnification(delta)
        onStrokeUpdated?(stroke)
    }

    private func endMagnifyStroke() {
        guard isStrokeActive, stroke.kind == .magnify else { return }
        finishStroke()
    }

    // MARK: - Stroke lifecycle & watchdog

    private func beginStroke() {
        isStrokeActive = true
        let now = CFAbsoluteTimeGetCurrent()
        strokeBeganTime = now
        lastStrokeActivityTime = now
        livenessTimer?.invalidate()
        livenessTimer = Timer.scheduledTimer(withTimeInterval: Self.livenessCheckInterval, repeats: true) { [weak self] _ in
            self?.checkStrokeLiveness()
        }
    }

    /// Normal end: the gesture is delivered to `onStrokeEnded` for classification.
    private func finishStroke() {
        guard isStrokeActive else { return }
        isStrokeActive = false
        activeMagnifyDevice = nil
        stopLivenessTimer()
        onStrokeEnded?(stroke)
        stroke.end()
    }

    /// Abandons the in-progress stroke without applying anything — see `onStrokeCancelled`.
    private func cancelActiveStroke() {
        let wasActive = isStrokeActive
        isStrokeActive = false
        activeMagnifyDevice = nil
        stopLivenessTimer()
        stroke.reset()
        if wasActive { onStrokeCancelled?() }
    }

    private func stopLivenessTimer() {
        livenessTimer?.invalidate()
        livenessTimer = nil
    }

    /// Runs every `livenessCheckInterval` while a stroke is active. Two failure modes are
    /// recovered here, both of which used to leave the whole pipeline dead until relaunch:
    ///
    /// 1. The sensor says every finger is off the trackpad, yet a translation stroke is
    ///    still open — its `.ended` was swallowed by the system (Space switch, Mission
    ///    Control, a modal grabbing events...). The user *did* finish the gesture, so it's
    ///    completed normally and classified like any other.
    /// 2. No proof of life whatsoever for `staleStrokeInterval` — the sensor went quiet
    ///    (sleep, device unplugged) with a stroke open. Nothing can be trusted; cancel.
    private func checkStrokeLiveness() {
        guard isStrokeActive else {
            stopLivenessTimer()
            return
        }
        let now = CFAbsoluteTimeGetCurrent()

        if isMultitouchActive, stroke.kind == .translation,
           lastMultitouchFrameTime >= strokeBeganTime, !anyFingerDown,
           now - lastFingerDownTime >= Self.fingersUpGrace {
            finishStroke()
            return
        }
        if now - lastStrokeActivityTime >= Self.staleStrokeInterval {
            cancelActiveStroke()
        }
    }

    private func describe(_ type: NSEvent.EventType) -> String {
        switch type {
        case .swipe: return "swipe"
        case .scrollWheel: return "scrollWheel"
        default: return "other"
        }
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        livenessTimer?.invalidate()
        deviceRefreshTimer?.invalidate()
        MultitouchSupport.shared.stop()
    }
}

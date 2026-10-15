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
    private(set) var stroke = GestureStroke()
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
    var onStrokeBegan: ((NSPoint) -> Void)?
    /// Fired every time the in-progress gesture's accumulated displacement changes.
    var onStrokeUpdated: ((GestureStroke) -> Void)?
    var onStrokeEnded: ((GestureStroke) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    /// Raw inter-finger-distance tracking, one entry per physical multitouch device
    /// (keyed by the `MTDeviceRef` `MultitouchSupport` tags each frame with). A Mac can
    /// have more than one such device active at once — a MacBook's built-in trackpad plus
    /// a Bluetooth Magic Trackpad or Magic Mouse, say — and their frames are separate,
    /// unrelated streams; sharing one scalar distance/delta between them would let an
    /// unrelated device's frame land in between two frames from the real one, corrupting
    /// the delta with a jump that has nothing to do with either device's actual motion.
    private var pinchTrackingByDevice: [UnsafeMutableRawPointer: PinchTrackingState] = [:]
    /// Which device's frames committed the currently-active magnify stroke, if any — once
    /// one device has committed to a pinch, a second device reporting its own incidental
    /// two-finger contact (e.g. a hand resting on a nearby Magic Mouse while the real pinch
    /// happens on the trackpad) must not be able to inject its delta into that same stroke.
    private var activeMagnifyDevice: UnsafeMutableRawPointer?

    private struct PinchTrackingState {
        var lastDistance: CGFloat?
        /// Distance-delta accumulated *before* committing to a magnify-kind stroke — see
        /// `handleMultitouchFrame`.
        var pendingDelta: CGFloat = 0
        /// Consecutive multitouch frames in a row that didn't report exactly two touching
        /// fingers — see `nonPinchFrameGrace`.
        var consecutiveNonPinchFrames = 0
    }

    @ObservationIgnored private var rawMultitouchFrameCount = 0
    @ObservationIgnored private var lastDiagnosticFlushTime: CFAbsoluteTime = 0
    @ObservationIgnored private var pendingEventDescription: String?
    @ObservationIgnored private var pendingTapDescription: String?

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

        MultitouchSupport.shared.onFrame = { [weak self] device, fingers in
            DispatchQueue.main.async {
                self?.handleMultitouchFrame(fingers, device: device)
            }
        }
        MultitouchSupport.shared.start()
        isMultitouchActive = MultitouchSupport.shared.isAvailable

        isMonitoring = true
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        MultitouchSupport.shared.stop()
        MultitouchSupport.shared.onFrame = nil
        isMultitouchActive = false
        pinchTrackingByDevice.removeAll()
        activeMagnifyDevice = nil
        isMonitoring = false
        isStrokeActive = false
        stroke.reset()
    }

    /// Writes to the cosmetic diagnostic properties, at most `diagnosticFlushInterval`
    /// often — see that constant's doc comment for why this exists at all.
    private func flushDiagnostics(event: String? = nil, tap: String? = nil) {
        if let event { pendingEventDescription = event }
        if let tap { pendingTapDescription = tap }

        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastDiagnosticFlushTime >= Self.diagnosticFlushInterval else { return }
        lastDiagnosticFlushTime = now

        if let pendingEventDescription { lastEventTypeDescription = pendingEventDescription }
        multitouchFrameCount = rawMultitouchFrameCount
        if let pendingTapDescription { lastTapDiagnostic = pendingTapDescription }
    }

    /// Tracks the distance between exactly two touching fingers across frames. Two fingers
    /// touching the trackpad also happens for an ordinary parallel swipe (the gesture that
    /// drives window snapping via `.scrollWheel`) — where that distance stays roughly
    /// constant, unlike a real pinch, where it changes a lot. So this doesn't commit to a
    /// magnify-kind stroke on first contact; it accumulates quietly until the distance has
    /// moved enough to look deliberately like a pinch. That also naturally loses any race
    /// against `.scrollWheel`'s own `.began`, which fires almost immediately on contact —
    /// once that's claimed `isStrokeActive`, `handleMagnifyDelta` backs off on its own.
    private func handleMultitouchFrame(_ fingers: [MTFinger], device: UnsafeMutableRawPointer) {
        rawMultitouchFrameCount += 1
        let touching = fingers.filter { $0.size > Self.minimumFingerSize }

        var state = pinchTrackingByDevice[device] ?? PinchTrackingState()
        defer { pinchTrackingByDevice[device] = state }

        guard touching.count == 2 else {
            flushDiagnostics(tap: "\(touching.count) doigt(s) au contact")
            state.consecutiveNonPinchFrames += 1
            if state.lastDistance != nil, state.consecutiveNonPinchFrames >= Self.nonPinchFrameGrace {
                state.lastDistance = nil
                state.pendingDelta = 0
                if device == activeMagnifyDevice { endMagnifyStroke() }
            }
            return
        }
        state.consecutiveNonPinchFrames = 0

        let dx = CGFloat(touching[0].normalizedX - touching[1].normalizedX)
        let dy = CGFloat(touching[0].normalizedY - touching[1].normalizedY)
        let distance = (dx * dx + dy * dy).squareRoot()
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
    /// doesn't own: a spurious `.began` mid-gesture would otherwise silently re-resolve the
    /// target (and can miss, since the cursor may have drifted) or reset an in-progress
    /// magnify stroke back to `.translation` with zeroed accumulators; a spurious `.ended`
    /// would otherwise prematurely terminate a magnify stroke that's still in progress.
    private func handleScrollWheel(_ event: NSEvent) {
        guard event.hasPreciseScrollingDeltas else { return }
        let phase = event.phase
        if phase.contains(.began) {
            guard !isStrokeActive else { return }
            let location = NSEvent.mouseLocation
            stroke.begin(touchCount: 2, at: location, kind: .translation)
            isStrokeActive = true
            onStrokeBegan?(location)
        } else if phase.contains(.changed) {
            guard isStrokeActive, stroke.kind == .translation else { return }
            stroke.accumulate(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
            onStrokeUpdated?(stroke)
        } else if phase.contains(.ended) || phase.contains(.cancelled) {
            guard isStrokeActive, stroke.kind == .translation else { return }
            isStrokeActive = false
            onStrokeEnded?(stroke)
            stroke.end()
        }
    }

    /// Pinch open/closed, driven by `handleMultitouchFrame`'s raw finger-distance deltas.
    private func handleMagnifyDelta(_ delta: CGFloat, at location: NSPoint) {
        if !isStrokeActive {
            stroke.begin(touchCount: 2, at: location, kind: .magnify)
            isStrokeActive = true
            onStrokeBegan?(location)
        } else if stroke.kind != .magnify {
            return // A translation stroke owns this moment; don't cross the streams.
        }
        stroke.accumulateMagnification(delta)
        onStrokeUpdated?(stroke)
    }

    private func endMagnifyStroke() {
        guard isStrokeActive, stroke.kind == .magnify else { return }
        isStrokeActive = false
        activeMagnifyDevice = nil
        onStrokeEnded?(stroke)
        stroke.end()
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
        MultitouchSupport.shared.stop()
    }
}

import AppKit
import ApplicationServices

/// Learns, per app, where the user actually likes the half/quarter split line to fall —
/// distinct from `GestureSettings`' generic default, which applies everywhere until this
/// has something more specific to say for a given app.
///
/// Signal: right after Flick applies a snap, this watches the window for a few seconds. If
/// the user manually nudges its edge immediately afterward, that's treated as "the generic
/// default wasn't quite right for this app." The same nudge has to repeat consistently a
/// few times before anything actually changes — a one-off correction (or just clicking
/// around near the edge) shouldn't retrain it off a single data point.
///
/// Built on the public `AXObserver` API (`kAXResizedNotification`/`kAXMovedNotification`) —
/// unlike `SpacesController`, this is documented, stable Apple API with no private-symbol
/// risk.
final class AdaptiveSnapZones {
    static let shared = AdaptiveSnapZones()

    private struct LearnedSplit: Codable {
        var horizontal: CGFloat?
        var vertical: CGFloat?
    }

    private enum Axis {
        case horizontal, vertical
    }

    private static let defaultsKey = "com.selim.Flick.adaptiveSnapZones"
    /// How long after a snap a manual resize still counts as "correcting that snap" rather
    /// than an unrelated, later adjustment.
    private static let observationWindow: TimeInterval = 5
    /// Consecutive consistent observations required before committing a change.
    private static let requiredConsistentObservations = 3
    /// How close recent observations must be to each other to count as "consistent" rather
    /// than the user just experimenting.
    private static let consistencyTolerance: CGFloat = 0.04
    /// How far a consistent cluster must sit from the current ratio to be worth changing
    /// at all — otherwise ordinary pixel-level noise would keep re-committing the same
    /// value over and over.
    private static let changeThreshold: CGFloat = 0.02

    private var learned: [String: LearnedSplit] = [:]
    private var pendingHorizontal: [String: [CGFloat]] = [:]
    private var pendingVertical: [String: [CGFloat]] = [:]

    private var observer: AXObserver?
    private var observedWindow: AXUIElement?
    private var observationDeadlineTimer: Timer?
    private var pendingBundleID: String?
    private var pendingIsLeftAligned: Bool?
    private var pendingIsTopAligned: Bool?

    private init() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([String: LearnedSplit].self, from: data)
        else { return }
        learned = decoded
    }

    /// The effective ratios for `bundleID` — `defaults` (from `GestureSettings`) with
    /// whichever axes have been learned for this app overriding it.
    func ratios(for bundleID: String, defaults: SnapZoneRatios) -> SnapZoneRatios {
        guard let split = learned[bundleID] else { return defaults }
        return SnapZoneRatios(
            horizontal: split.horizontal ?? defaults.horizontal,
            vertical: split.vertical ?? defaults.vertical
        )
    }

    /// Call right after `WindowSnapper.apply` succeeds for a resizing action — arms a
    /// short-lived watch for a manual correction. No-op for actions with no split concept
    /// (`.maximize`, `.minimize`, `.close`), since there's nothing to learn from those.
    func observeForAdjustment(after action: SnapAction, window axWindow: AXUIElement, pid: pid_t, bundleID: String) {
        guard action.isLeftAligned != nil || action.isTopAligned != nil else { return }
        stopObserving()

        var newObserver: AXObserver?
        guard AXObserverCreate(pid, adjustmentObserverCallback, &newObserver) == .success,
              let newObserver
        else { return }

        let addedResize = AXObserverAddNotification(newObserver, axWindow, kAXResizedNotification as CFString, nil)
        let addedMove = AXObserverAddNotification(newObserver, axWindow, kAXMovedNotification as CFString, nil)
        guard addedResize == .success || addedMove == .success else { return }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .defaultMode)
        observer = newObserver
        observedWindow = axWindow
        pendingBundleID = bundleID
        pendingIsLeftAligned = action.isLeftAligned
        pendingIsTopAligned = action.isTopAligned

        observationDeadlineTimer = Timer.scheduledTimer(withTimeInterval: Self.observationWindow, repeats: false) { [weak self] _ in
            self?.stopObserving()
        }
    }

    /// Clears every learned split — exposed for a "reset learning" control in Preferences.
    func resetAll() {
        learned.removeAll()
        pendingHorizontal.removeAll()
        pendingVertical.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
    }

    fileprivate func handleObservedChange() {
        guard let observedWindow, let bundleID = pendingBundleID,
              let frame = WindowLocator.frame(of: observedWindow)
        else { return }
        let appKitFrame = ScreenGeometry.appKitRect(fromQuartz: frame)
        guard let screen = NSScreen.screens.first(where: {
            $0.frame.contains(CGPoint(x: appKitFrame.midX, y: appKitFrame.midY))
        }) else { return }
        let visible = ScreenGeometry.quartzRect(fromAppKit: screen.visibleFrame)
        guard visible.width > 0, visible.height > 0 else { return }

        if let isLeft = pendingIsLeftAligned {
            let ratio = isLeft
                ? frame.width / visible.width
                : (frame.minX - visible.minX) / visible.width
            record(ratio, axis: .horizontal, bundleID: bundleID)
        }
        if let isTop = pendingIsTopAligned {
            let ratio = isTop
                ? frame.height / visible.height
                : (frame.minY - visible.minY) / visible.height
            record(ratio, axis: .vertical, bundleID: bundleID)
        }
    }

    private func record(_ ratio: CGFloat, axis: Axis, bundleID: String) {
        // A degenerate resize (window dragged almost off-screen, or barely resized at all)
        // isn't a meaningful "I prefer this split" signal — discard it rather than let it
        // pull the learned average toward an edge case nobody actually wants repeated.
        guard (0.05...0.95).contains(ratio) else { return }

        switch axis {
        case .horizontal:
            var pending = pendingHorizontal[bundleID] ?? []
            pending.append(ratio)
            if pending.count > Self.requiredConsistentObservations {
                pending.removeFirst(pending.count - Self.requiredConsistentObservations)
            }
            pendingHorizontal[bundleID] = pending
        case .vertical:
            var pending = pendingVertical[bundleID] ?? []
            pending.append(ratio)
            if pending.count > Self.requiredConsistentObservations {
                pending.removeFirst(pending.count - Self.requiredConsistentObservations)
            }
            pendingVertical[bundleID] = pending
        }
        commitIfConsistent(bundleID: bundleID, axis: axis)
    }

    private func commitIfConsistent(bundleID: String, axis: Axis) {
        let pending = axis == .horizontal ? pendingHorizontal[bundleID] : pendingVertical[bundleID]
        guard let pending, pending.count >= Self.requiredConsistentObservations,
              let minValue = pending.min(), let maxValue = pending.max(),
              maxValue - minValue <= Self.consistencyTolerance
        else { return }

        let average = pending.reduce(0, +) / CGFloat(pending.count)
        let current = axis == .horizontal ? learned[bundleID]?.horizontal : learned[bundleID]?.vertical
        if let current, abs(current - average) < Self.changeThreshold { return }

        var entry = learned[bundleID] ?? LearnedSplit()
        switch axis {
        case .horizontal: entry.horizontal = average
        case .vertical: entry.vertical = average
        }
        learned[bundleID] = entry
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(learned) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private func stopObserving() {
        observationDeadlineTimer?.invalidate()
        observationDeadlineTimer = nil
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        observedWindow = nil
        pendingBundleID = nil
        pendingIsLeftAligned = nil
        pendingIsTopAligned = nil
    }
}

/// Non-capturing C callback — `AXObserver` has no context pointer for this, so state
/// travels through the `AdaptiveSnapZones.shared` singleton instead, same pattern as
/// `MultitouchSupport`'s C callback.
private func adjustmentObserverCallback(
    observer: AXObserver, element: AXUIElement, notification: CFString, refcon: UnsafeMutableRawPointer?
) {
    AdaptiveSnapZones.shared.handleObservedChange()
}

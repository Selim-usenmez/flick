import AppKit
import Observation

/// Global trackpad event capture. Note the fundamental limitation this whole feature lives
/// with: `NSEvent.addGlobalMonitorForEvents` only *observes* events already delivered to
/// whatever app is under the cursor — it can't swallow them. That's fine for a swipe over a
/// window's title bar (nothing there reacts to a two-finger swipe anyway), but the same
/// swipe over a window's body would also scroll its content. Bindings are therefore meant
/// to be evaluated only while the cursor is over a title bar (see `WindowLocator`).
@Observable
final class TouchGestureMonitor {
    private(set) var stroke = GestureStroke()
    private(set) var lastEventTypeDescription: String = "—"
    private(set) var isMonitoring = false
    private(set) var isStrokeActive = false

    var onStrokeEnded: ((GestureStroke) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private let touchEventTypes: NSEvent.EventTypeMask = [
        .gesture, .magnify, .rotate, .swipe, .beginGesture, .endGesture, .scrollWheel,
    ]

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
        isMonitoring = true
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        isMonitoring = false
        isStrokeActive = false
        stroke.reset()
    }

    private func handle(_ event: NSEvent) {
        lastEventTypeDescription = describe(event.type)

        switch event.type {
        case .beginGesture:
            stroke.reset()
            isStrokeActive = true
        case .gesture, .magnify, .rotate, .swipe, .scrollWheel:
            let touches = event.allTouches()
            if !touches.isEmpty {
                stroke.update(with: touches)
            }
        case .endGesture:
            isStrokeActive = false
            onStrokeEnded?(stroke)
        default:
            break
        }
    }

    private func describe(_ type: NSEvent.EventType) -> String {
        switch type {
        case .gesture: return "gesture"
        case .magnify: return "magnify"
        case .rotate: return "rotate"
        case .swipe: return "swipe"
        case .beginGesture: return "beginGesture"
        case .endGesture: return "endGesture"
        case .scrollWheel: return "scrollWheel"
        default: return "other"
        }
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }
}

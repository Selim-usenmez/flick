import AppKit
import Observation

/// Owns the pieces that make up Flick's gesture pipeline and the app's on/off state.
/// Phase 1 only wires monitoring and the debug HUD; later phases attach window control,
/// gesture-to-action bindings, and the snap preview overlay here.
@Observable
final class FlickController {
    let accessibilityPermission = AccessibilityPermission()
    let gestureMonitor = TouchGestureMonitor()
    private(set) var isEnabled = false

    // @Observable rewrites stored properties into computed ones backed by an
    // ObservationRegistrar, which is incompatible with `lazy`; opting this one out keeps
    // the lazy (needs `gestureMonitor` to already exist) while everything else stays tracked.
    @ObservationIgnored
    private lazy var hudPanelController = GestureHUDPanelController(monitor: gestureMonitor)

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
}

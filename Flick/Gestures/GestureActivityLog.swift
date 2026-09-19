import Observation

/// What Flick last did (or tried to do) in response to a gesture, plus a live readout of
/// the gesture currently in progress — shown in the control panel so a gesture that isn't
/// triggering anything can be diagnosed by watching the numbers instead of guessing blind.
@Observable
final class GestureActivityLog {
    private(set) var lastActionDescription: String = "—"
    private(set) var liveTargetDescription: String = "—"
    private(set) var liveClassificationDescription: String = "—"

    func record(_ description: String) {
        lastActionDescription = description
    }

    func updateLive(target: String, classification: String) {
        liveTargetDescription = target
        liveClassificationDescription = classification
    }
}

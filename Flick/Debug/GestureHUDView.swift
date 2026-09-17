import SwiftUI

/// Live readout of what the trackpad monitor is seeing. This exists because gestures can't
/// be scripted or simulated from outside — this view is how a real two-finger swipe on the
/// physical trackpad gets confirmed to actually reach `TouchGestureMonitor`, and in
/// particular whether `NSEvent.allTouches()` is populated for `.scrollWheel` events or only
/// for the `.gesture` family (undocumented either way).
struct GestureHUDView: View {
    let monitor: TouchGestureMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(monitor.isMonitoring ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(monitor.isMonitoring ? "Surveillance active" : "Surveillance arrêtée")
                    .font(.caption.weight(.semibold))
            }

            Divider()

            LabeledContent("Dernier événement", value: monitor.lastEventTypeDescription)
            LabeledContent("État du geste", value: monitor.isStrokeActive ? "en cours" : "terminé")
            LabeledContent("Doigts actifs", value: "\(monitor.stroke.activeTouchCount)")

            let translation = monitor.stroke.averageTranslation
            LabeledContent("Déplacement dx", value: String(format: "%.3f", translation.dx))
            LabeledContent("Déplacement dy", value: String(format: "%.3f", translation.dy))
        }
        .font(.caption.monospacedDigit())
        .padding(12)
        .frame(width: 240, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

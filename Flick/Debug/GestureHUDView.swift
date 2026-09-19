import AppKit
import SwiftUI

/// Flick's floating control panel: a live status readout, a cheat sheet of gesture-to-
/// action mappings, a couple of tunable settings, and a one-click relaunch for when the
/// gesture pipeline gets stuck. Meant to be left open in a corner of the screen while using
/// the app day to day, not just for debugging.
struct GestureHUDView: View {
    let monitor: TouchGestureMonitor
    let activityLog: GestureActivityLog

    @Environment(\.openWindow) private var openWindow

    /// A wide, short rectangle rather than a tall narrow strip — two columns side by side
    /// instead of everything stacked in one long scroll.
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    liveCard
                    diagnosticsSection
                }
                .frame(width: 180)
                Divider()
                GestureCheatSheetView(compact: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack(spacing: 8) {
                openPreferencesButton
                relaunchButton
            }
        }
        .padding(16)
        .frame(width: 640)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Flick").font(.headline)
                statusPill(isOn: monitor.isMonitoring, onLabel: "Surveillance active", offLabel: "Surveillance arrêtée")
            }
            Spacer()
        }
    }

    private func statusPill(isOn: Bool, onLabel: String, offLabel: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isOn ? Color.green : Color.red)
                .frame(width: 6, height: 6)
            Text(isOn ? onLabel : offLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Live feedback

    /// What the current gesture is targeting, front and center — this is the thing a user
    /// actually watches mid-swipe, so it gets the most visual weight in the panel.
    private var liveCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("EN DIRECT")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(activityLog.liveTargetDescription)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Text(activityLog.liveClassificationDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Divider().padding(.vertical, 2)
            HStack(spacing: 4) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(activityLog.lastActionDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Diagnostics

    /// Raw numbers behind gesture recognition — secondary in the visual hierarchy (smaller,
    /// muted) but left visible rather than hidden, since a gesture that isn't triggering
    /// anything is otherwise impossible to diagnose.
    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Diagnostic", icon: "waveform.path.ecg")
            diagnosticRow("Dernier événement", monitor.lastEventTypeDescription)
            diagnosticRow("État du geste", monitor.isStrokeActive ? "en cours" : "terminé")
            HStack(spacing: 5) {
                Circle()
                    .fill(monitor.isMultitouchActive ? Color.green : Color.red)
                    .frame(width: 5, height: 5)
                Text(monitor.isMultitouchActive ? "Capteur pincement actif" : "Capteur pincement inactif")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            diagnosticRow("Trames multitouch", "\(monitor.multitouchFrameCount)")
            diagnosticRow("Doigts / distance", monitor.lastTapDiagnostic)
        }
        .font(.caption2)
    }

    private func diagnosticRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.tertiary)
            Spacer()
            Text(value).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).foregroundStyle(.tint)
            Text(title.uppercased())
                .foregroundStyle(.secondary)
        }
        .font(.caption2.weight(.semibold))
    }

    // MARK: - Footer

    /// The full settings (sensitivity sliders, inversions, launch at login) now live in the
    /// proper Preferences window — this panel is just the live, at-a-glance heads-up display.
    private var openPreferencesButton: some View {
        Button {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: PreferencesView.windowID)
        } label: {
            Label("Réglages Flick…", systemImage: "slider.horizontal.3")
                .font(.caption)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var relaunchButton: some View {
        Button {
            AppRelauncher.relaunch()
        } label: {
            Label("Relancer Flick", systemImage: "arrow.clockwise")
                .font(.caption)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

#Preview {
    let activityLog = GestureActivityLog()
    activityLog.updateLive(target: "Fenêtre", classification: "Moitié gauche — dx -180 dy 4 (seuil 60)")
    activityLog.record("Fenêtre → Moitié gauche")
    return GestureHUDView(monitor: TouchGestureMonitor(), activityLog: activityLog)
}

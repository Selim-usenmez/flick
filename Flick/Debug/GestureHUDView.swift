import AppKit
import SwiftUI

/// Flick's floating control panel: a live status readout, the gesture-to-action grids (with
/// the in-progress gesture's cell lit up), a couple of tunable settings, and a one-click
/// relaunch for when the gesture pipeline gets stuck. Meant to be left open in a corner of
/// the screen while using the app day to day, not just for debugging.
struct GestureHUDView: View {
    let monitor: TouchGestureMonitor
    let activityLog: GestureActivityLog

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    liveCard
                    diagnosticsSection
                }
                .frame(width: 200)
                gridsSection
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                openPreferencesButton
                relaunchButton
            }
        }
        .padding(16)
        .frame(width: 640)
        .background(Color(hex: 0x202024, opacity: 0.92).background(.ultraThinMaterial))
        .clipShape(RoundedRectangle(cornerRadius: FlickTheme.hudCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: FlickTheme.hudCornerRadius)
                .strokeBorder(Color.white.opacity(0.12))
        )
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text("Flick")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(FlickTheme.textPrimary)
            StatusPill(isOn: monitor.isMonitoring, onLabel: "Surveillance active", offLabel: "Surveillance arrêtée")
            Spacer()
        }
    }

    // MARK: - Live feedback

    /// `activityLog.liveClassificationDescription` already reads "<action> — <magnitude>"
    /// (see `FlickController.updateLiveThrottled` callers); split it so the action name
    /// gets headline weight and the raw numbers get their own monospaced line, matching
    /// the design without adding a second piece of state to `GestureActivityLog`.
    private var liveClassificationParts: (headline: String, detail: String?) {
        let text = activityLog.liveClassificationDescription
        guard let range = text.range(of: " — ") else { return (text, nil) }
        return (String(text[..<range.lowerBound]), String(text[range.upperBound...]))
    }

    /// What the current gesture is targeting, front and center — this is the thing a user
    /// actually watches mid-swipe, so it gets the most visual weight in the panel.
    private var liveCard: some View {
        let parts = liveClassificationParts
        return VStack(alignment: .leading, spacing: 6) {
            Text("EN DIRECT")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(FlickTheme.accentText)
            Text(activityLog.liveTargetDescription)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(FlickTheme.textPrimary)
                .lineLimit(1)
            Text(parts.headline)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: 0xC8C8CE))
                .lineLimit(2)
            if let detail = parts.detail {
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(FlickTheme.textTertiary)
                    .lineLimit(1)
            }
            CardDivider().padding(.vertical, 2)
            HStack(spacing: 4) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 10))
                    .foregroundStyle(FlickTheme.textQuaternary)
                Text(activityLog.lastActionDescription)
                    .font(.system(size: 11.5))
                    .foregroundStyle(FlickTheme.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [FlickTheme.accent.opacity(0.16), FlickTheme.accent.opacity(0.06)], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(FlickTheme.accent.opacity(0.3)))
    }

    // MARK: - Diagnostics

    /// Raw numbers behind gesture recognition — secondary in the visual hierarchy (smaller,
    /// muted) but left visible rather than hidden, since a gesture that isn't triggering
    /// anything is otherwise impossible to diagnose.
    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("DIAGNOSTIC")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(FlickTheme.textTertiary)
                .padding(.bottom, 1)
            diagnosticRow("Dernier événement", monitor.lastEventTypeDescription, mono: true)
            diagnosticRow("État du geste", monitor.isStrokeActive ? "en cours" : "terminé", mono: false)
            HStack(spacing: 5) {
                Text("Capteur pincement").foregroundStyle(FlickTheme.textQuaternary)
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(monitor.isMultitouchActive ? FlickTheme.success : FlickTheme.error)
                        .frame(width: 5, height: 5)
                    Text(monitor.isMultitouchActive ? "actif" : "inactif")
                        .foregroundStyle(FlickTheme.gridLabel)
                }
            }
            diagnosticRow("Trames multitouch", "\(monitor.multitouchFrameCount)", mono: true)
            diagnosticRow("Doigts / distance", monitor.lastTapDiagnostic, mono: true)
        }
        .font(.system(size: 11))
    }

    private func diagnosticRow(_ label: String, _ value: String, mono: Bool) -> some View {
        HStack {
            Text(label).foregroundStyle(FlickTheme.textQuaternary)
            Spacer()
            Text(value)
                .foregroundStyle(FlickTheme.gridLabel)
                .font(mono ? .system(size: 11, design: .monospaced) : .system(size: 11))
                .lineLimit(1)
        }
    }

    // MARK: - Gesture grids

    private var gridsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("BARRE DE TITRE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(FlickTheme.textTertiary)
                    GestureGridView(
                        grid: .title, style: .compact,
                        activePosition: activityLog.liveGrid == .title ? activityLog.liveCell : nil
                    )
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("ICÔNE DU DOCK")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(FlickTheme.textTertiary)
                    GestureGridView(
                        grid: .dock, style: .compact,
                        activePosition: activityLog.liveGrid == .dock ? activityLog.liveCell : nil
                    )
                }
            }
            (
                Text("Pincer : fenêtre ")
                    + Text("fermer / plein écran").foregroundColor(Color(hex: 0xC8C8CE))
                    + Text(" · Dock ")
                    + Text("minimiser / ⌘N").foregroundColor(Color(hex: 0xC8C8CE))
            )
            .font(.system(size: 10.5))
            .foregroundStyle(FlickTheme.textTertiary)
        }
    }

    // MARK: - Footer

    /// The full settings (sensitivity sliders, inversions, launch at login) now live in the
    /// proper Preferences window — this panel is just the live, at-a-glance heads-up display.
    private var openPreferencesButton: some View {
        Button("⚙ Réglages Flick…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: PreferencesView.windowID)
        }
        .buttonStyle(.flickSubtle)
    }

    private var relaunchButton: some View {
        Button("↻ Relancer Flick") {
            AppRelauncher.relaunch()
        }
        .buttonStyle(.flickSubtle)
    }
}

#Preview {
    let activityLog = GestureActivityLog()
    activityLog.updateLive(
        target: "Fenêtre", classification: "Moitié gauche — dx -180 dy 4 (seuil 60)",
        grid: .title, cell: .left
    )
    activityLog.record("Fenêtre → Moitié gauche")
    return GestureHUDView(monitor: TouchGestureMonitor(), activityLog: activityLog)
        .padding(40)
        .background(Color.gray)
}

import Sparkle
import SwiftUI

/// Flick's menu bar popover — a `.window`-style `MenuBarExtra` (not a native `.menu`) so it
/// can show the colored status line, the inline enable switch, and the orange permission
/// banner from the design handoff, none of which a native menu can render.
struct MenuBarView: View {
    let controller: FlickController

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            if !controller.accessibilityPermission.isTrusted {
                permissionBanner
            }
            CardDivider().padding(.vertical, 3)

            MenuRow(label: "Réglages Flick…", shortcut: "⌘,") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: PreferencesView.windowID)
                dismiss()
            }
            MenuRow(label: "Afficher le panneau Flick", checked: controller.isDebugHUDVisible) {
                controller.toggleDebugHUD()
                dismiss()
            }
            MenuRow(label: "Revoir la présentation…") {
                controller.showOnboarding()
                dismiss()
            }
            MenuRow(label: "Rechercher les mises à jour…") {
                controller.updaterController.checkForUpdates(nil)
                dismiss()
            }

            CardDivider().padding(.vertical, 3)

            MenuRow(label: "Quitter Flick", shortcut: "⌘Q") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(5)
        .frame(width: 260)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Flick").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FlickTheme.textPrimary)
                Text(controller.isEnabled ? "Surveillance active" : "Surveillance arrêtée")
                    .font(.system(size: 11))
                    .foregroundStyle(controller.isEnabled ? FlickTheme.success : FlickTheme.error)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { controller.isEnabled },
                set: { controller.setEnabled($0) }
            ))
            .labelsHidden()
            .toggleStyle(.flick(.small))
            .disabled(!controller.accessibilityPermission.isTrusted)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Accessibilité non autorisée")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(FlickTheme.warning)
            Button("Autoriser l'accessibilité…") {
                controller.accessibilityPermission.requestAuthorization()
                dismiss()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(FlickTheme.textPrimary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FlickTheme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }
}

/// One row in the menu bar popover: label, optional trailing shortcut hint or checkmark,
/// and an accent-blue hover highlight (the native menu can't be reused once the whole
/// popover is custom, so hover feedback has to be drawn by hand).
private struct MenuRow: View {
    let label: String
    var shortcut: String?
    var checked: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label).font(.system(size: 13))
                Spacer()
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FlickTheme.accent)
                } else if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 12))
                        .foregroundStyle(isHovering ? .white.opacity(0.7) : FlickTheme.textTertiary)
                }
            }
            .foregroundStyle(FlickTheme.textPrimary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(isHovering ? FlickTheme.accent : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

#Preview {
    MenuBarView(controller: FlickController())
        .background(Color(hex: 0x242428, opacity: 0.94))
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .padding(40)
        .background(.gray)
}

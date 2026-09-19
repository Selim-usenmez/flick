import SwiftUI

struct GeneralSettingsTab: View {
    let controller: FlickController

    var body: some View {
        Form {
            Section("État") {
                Toggle("Activé", isOn: Binding(
                    get: { controller.isEnabled },
                    set: { controller.setEnabled($0) }
                ))
                .disabled(!controller.accessibilityPermission.isTrusted)

                Button {
                    AppRelauncher.relaunch()
                } label: {
                    Label("Relancer Flick", systemImage: "arrow.clockwise")
                }
            }

            Section("Permissions") {
                if controller.accessibilityPermission.isTrusted {
                    Label("Accessibilité autorisée", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Accessibilité non autorisée", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button("Autoriser l'accessibilité…") {
                        controller.accessibilityPermission.requestAuthorization()
                    }
                    Button("Ouvrir Réglages Système…") {
                        controller.accessibilityPermission.openSystemSettings()
                    }
                }
            }

            Section("Démarrage") {
                Toggle("Lancer Flick au démarrage du Mac", isOn: Binding(
                    get: { controller.launchAtLogin.status != .disabled },
                    set: { controller.launchAtLogin.setEnabled($0) }
                ))
                if controller.launchAtLogin.status == .requiresApproval {
                    Label("Approbation requise dans Réglages Système", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button("Ouvrir Réglages Système…") {
                        controller.launchAtLogin.openSystemSettings()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    GeneralSettingsTab(controller: FlickController())
        .frame(width: 460, height: 420)
}

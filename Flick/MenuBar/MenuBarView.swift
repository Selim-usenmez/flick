import SwiftUI

struct MenuBarView: View {
    let controller: FlickController

    var body: some View {
        Toggle("Activé", isOn: Binding(
            get: { controller.isEnabled },
            set: { controller.setEnabled($0) }
        ))
        .disabled(!controller.accessibilityPermission.isTrusted)

        Divider()

        if controller.accessibilityPermission.isTrusted {
            Label("Accessibilité autorisée", systemImage: "checkmark.circle.fill")
        } else {
            Button("Autoriser l'accessibilité…") {
                controller.accessibilityPermission.requestAuthorization()
            }
            Button("Ouvrir Réglages Système…") {
                controller.accessibilityPermission.openSystemSettings()
            }
        }

        Divider()

        Toggle("Afficher le HUD de debug", isOn: Binding(
            get: { controller.isDebugHUDVisible },
            set: { _ in controller.toggleDebugHUD() }
        ))

        Divider()

        Button("Quitter Flick") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

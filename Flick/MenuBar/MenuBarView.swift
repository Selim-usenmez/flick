import Sparkle
import SwiftUI

struct MenuBarView: View {
    let controller: FlickController

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle("Activé", isOn: Binding(
            get: { controller.isEnabled },
            set: { controller.setEnabled($0) }
        ))
        .disabled(!controller.accessibilityPermission.isTrusted)

        if !controller.accessibilityPermission.isTrusted {
            Divider()
            Label("Accessibilité non autorisée", systemImage: "exclamationmark.triangle.fill")
            Button {
                controller.accessibilityPermission.requestAuthorization()
            } label: {
                Label("Autoriser l'accessibilité…", systemImage: "hand.raised.fill")
            }
        }

        Divider()

        Button {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: PreferencesView.windowID)
        } label: {
            Label("Réglages Flick…", systemImage: "slider.horizontal.3")
        }
        .keyboardShortcut(",")

        Toggle(isOn: Binding(
            get: { controller.isDebugHUDVisible },
            set: { _ in controller.toggleDebugHUD() }
        )) {
            Label("Afficher le panneau Flick", systemImage: "sidebar.right")
        }

        Button {
            controller.showOnboarding()
        } label: {
            Label("Revoir la présentation…", systemImage: "sparkles")
        }

        Button {
            controller.updaterController.checkForUpdates(nil)
        } label: {
            Label("Rechercher les mises à jour…", systemImage: "arrow.down.circle")
        }

        Divider()

        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label("Quitter Flick", systemImage: "xmark.circle")
        }
        .keyboardShortcut("q")
    }
}

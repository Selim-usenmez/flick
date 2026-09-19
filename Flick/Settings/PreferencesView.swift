import SwiftUI

/// Flick's real Preferences window — general status, tunable gesture sensitivity, the full
/// shortcut reference, and app info. Opened from the menu bar or the HUD panel, independent
/// of the live HUD (which stays focused on in-the-moment diagnostics).
struct PreferencesView: View {
    /// Shared with callers that need to open this window via `openWindow(id:)`.
    static let windowID = "preferences"

    let controller: FlickController

    var body: some View {
        TabView {
            GeneralSettingsTab(controller: controller)
                .tabItem { Label("Général", systemImage: "gearshape") }
            GestureSettingsTab(settings: controller.gestureSettings)
                .tabItem { Label("Gestes", systemImage: "hand.draw") }
            shortcutsTab
                .tabItem { Label("Raccourcis", systemImage: "keyboard") }
            AboutTab()
                .tabItem { Label("À propos", systemImage: "info.circle") }
        }
        .scenePadding()
        .frame(width: 460, height: 480)
    }

    private var shortcutsTab: some View {
        ScrollView {
            GestureCheatSheetView()
                .padding(.vertical, 8)
        }
    }
}

#Preview {
    PreferencesView(controller: FlickController())
}

import SwiftUI

/// Flick's real Preferences window — general status, tunable gesture sensitivity, the full
/// shortcut reference, and app info. Opened from the menu bar or the HUD panel, independent
/// of the live HUD (which stays focused on in-the-moment diagnostics).
struct PreferencesView: View {
    /// Shared with callers that need to open this window via `openWindow(id:)`.
    static let windowID = "preferences"

    private enum Tab: CaseIterable {
        case general, gestures, shortcuts, about

        var label: String {
            switch self {
            case .general: return "Général"
            case .gestures: return "Gestes"
            case .shortcuts: return "Raccourcis"
            case .about: return "À propos"
            }
        }
        var glyph: String {
            switch self {
            case .general: return "gearshape"
            case .gestures: return "hand.draw"
            case .shortcuts: return "command"
            case .about: return "info"
            }
        }
        var tileColor: Color {
            switch self {
            case .general: return Color(hex: 0x8E8E93)
            case .gestures: return FlickTheme.accent
            case .shortcuts: return Color(hex: 0x5E5CE6)
            case .about: return Color(hex: 0x636366)
            }
        }
    }

    let controller: FlickController

    @State private var selection: Tab = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(FlickTheme.windowBorder)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 640, height: 480)
        .background(FlickTheme.windowBackground)
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Reserves room for the window's native traffic lights (hidden-titlebar style).
            Color.clear.frame(height: 28)
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    HStack(spacing: 9) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(tab.tileColor)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Image(systemName: tab.glyph)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white)
                            )
                        Text(tab.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(FlickTheme.textPrimary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        selection == tab ? Color.white.opacity(0.1) : .clear,
                        in: RoundedRectangle(cornerRadius: 7)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(10)
        .frame(width: 180)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(FlickTheme.sidebarBackground)
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .general: GeneralSettingsTab(controller: controller)
        case .gestures: GestureSettingsTab(settings: controller.gestureSettings)
        case .shortcuts: ShortcutsSettingsTab()
        case .about: AboutTab(controller: controller)
        }
    }
}

#Preview {
    PreferencesView(controller: FlickController())
}

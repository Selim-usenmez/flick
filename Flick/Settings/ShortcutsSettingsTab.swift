import SwiftUI

/// Preferences › Raccourcis — the full gesture-to-action reference, the same `GestureGrid`
/// model shown (at a different size) in the Onboarding tour and the live HUD panel.
struct ShortcutsSettingsTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Raccourcis")
                .font(.system(size: 20, weight: .semibold))
                .tracking(-0.1)
                .foregroundStyle(FlickTheme.textPrimary)

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Barre de titre".uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FlickTheme.textTertiary)
                    GestureGridView(grid: .title, style: .medium)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Icône du Dock".uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FlickTheme.textTertiary)
                    GestureGridView(grid: .dock, style: .medium)
                }
                .frame(maxWidth: .infinity)
            }

            SettingsCard {
                shortcutRow(label: "Pincer · fenêtre") {
                    badgeLabel("fermer", "Fermer")
                    badgeLabel("agrandir", "Plein écran")
                }
                CardDivider()
                shortcutRow(label: "Pincer · Dock") {
                    badgeLabel("reduire", "Minimiser")
                    Text("＋ Nouvelle fenêtre ⌘N")
                }
                CardDivider()
                shortcutRow(label: "Vignette réduite") {
                    Text("↑ Rouvrir la fenêtre")
                }
            }

            Text("Si l'app n'est pas lancée, lance-la toi-même — Flick ne le fait plus automatiquement.")
                .font(.system(size: 11))
                .foregroundStyle(FlickTheme.textQuaternary)
                .padding(.leading, 2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    @ViewBuilder
    private func shortcutRow(label: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(FlickTheme.textSecondary)
            Spacer()
            HStack(spacing: 10) {
                trailing()
            }
            .font(.system(size: 12))
            .foregroundStyle(FlickTheme.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func badgeLabel(_ assetName: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Image(assetName).resizable().scaledToFit().frame(width: 10, height: 10)
            Text(label)
        }
    }
}

#Preview {
    ShortcutsSettingsTab()
        .frame(width: 460, height: 420)
        .background(FlickTheme.windowBackground)
}

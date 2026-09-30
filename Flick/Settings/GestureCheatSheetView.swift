import SwiftUI

/// The gesture-to-action reference — shared between the live HUD panel (compact) and the
/// Preferences window's "Raccourcis" tab (full size), so the mapping is only defined once.
struct GestureCheatSheetView: View {
    var compact: Bool = false

    private var iconFont: Font { compact ? .caption : .title3 }
    private var badgeSize: CGFloat { compact ? 14 : 20 }
    private var labelFont: Font { compact ? .caption2 : .caption }
    private var spacing: CGFloat { compact ? 8 : 16 }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            sectionHeader("Barre de titre", icon: "macwindow")
            cheatGrid(
                topLeft: (.symbol("arrow.up.left"), "Coin"), top: (.badge("agrandir"), "Plein écran"), topRight: (.symbol("arrow.up.right"), "Coin"),
                left: (.symbol("arrow.left"), "Moitié gauche"), right: (.symbol("arrow.right"), "Moitié droite"),
                bottomLeft: (.symbol("arrow.down.left"), "Coin"), bottom: (.badge("reduire"), "Minimiser"), bottomRight: (.symbol("arrow.down.right"), "Coin")
            )
            Label("Pincer fermé = fermer · pincer ouvert = plein écran", systemImage: "hand.pinch")
                .font(labelFont)
                .foregroundStyle(.secondary)

            sectionHeader("Icône du Dock", icon: "dock.rectangle")
                .padding(.top, compact ? 4 : 8)
            cheatGrid(
                topLeft: nil, top: (.symbol("arrow.up"), "Désminimiser"), topRight: nil,
                left: (.symbol("arrow.left"), "Fenêtre préc."), right: (.symbol("arrow.right"), "Fenêtre suiv."),
                bottomLeft: nil, bottom: (.badge("quitter"), "Quitter"), bottomRight: nil
            )
            Label("Pincer fermé = minimiser · pincer ouvert = nouvelle fenêtre (⌘N)", systemImage: "hand.pinch")
                .font(labelFont)
                .foregroundStyle(.secondary)
            Text("Si l'app n'est pas lancée, lance-la toi-même — Flick ne le fait plus automatiquement.")
                .font(labelFont)
                .foregroundStyle(.tertiary)

            sectionHeader("Fenêtre réduite du Dock", icon: "arrow.up.forward.square")
                .padding(.top, compact ? 4 : 8)
            Label("Glisse vers le haut sur sa vignette (juste avant la Corbeille) pour la rouvrir.", systemImage: "hand.point.up.left")
                .font(labelFont)
                .foregroundStyle(.secondary)
        }
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).foregroundStyle(.tint)
            Text(compact ? title.uppercased() : title)
                .foregroundStyle(compact ? .secondary : .primary)
        }
        .font((compact ? Font.caption2 : Font.subheadline).weight(.semibold))
    }

    /// Either a monochrome SF Symbol (directional cells with no dedicated artwork) or one
    /// of the flat colored badges from `Assets.xcassets/Actions` — the same ones shown
    /// live during a matching gesture, so the cheat sheet and the real preview agree.
    private enum CheatIcon {
        case symbol(String)
        case badge(String)
    }

    private typealias CheatCell = (icon: CheatIcon, label: String)

    private func cheatGrid(
        topLeft: CheatCell?, top: CheatCell?, topRight: CheatCell?,
        left: CheatCell?, right: CheatCell?,
        bottomLeft: CheatCell?, bottom: CheatCell?, bottomRight: CheatCell?
    ) -> some View {
        VStack(spacing: compact ? 6 : 12) {
            HStack { cheatCell(topLeft); cheatCell(top); cheatCell(topRight) }
            HStack { cheatCell(left); Spacer(); cheatCell(right) }
            HStack { cheatCell(bottomLeft); cheatCell(bottom); cheatCell(bottomRight) }
        }
    }

    @ViewBuilder
    private func cheatCell(_ cell: CheatCell?) -> some View {
        VStack(spacing: compact ? 2 : 4) {
            if let cell {
                cheatIcon(cell.icon)
                Text(cell.label)
                    .font(labelFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func cheatIcon(_ icon: CheatIcon) -> some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(iconFont)
                .foregroundStyle(.tint)
        case .badge(let name):
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(width: badgeSize, height: badgeSize)
        }
    }
}

#Preview {
    GestureCheatSheetView()
        .padding(24)
        .frame(width: 420)
}

import SwiftUI

/// The gesture-to-action reference — shared between the live HUD panel (compact) and the
/// Preferences window's "Raccourcis" tab (full size), so the mapping is only defined once.
struct GestureCheatSheetView: View {
    var compact: Bool = false

    private var iconFont: Font { compact ? .caption : .title3 }
    private var labelFont: Font { compact ? .caption2 : .caption }
    private var spacing: CGFloat { compact ? 8 : 16 }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            sectionHeader("Barre de titre", icon: "macwindow")
            cheatGrid(
                topLeft: ("arrow.up.left", "Coin"), top: ("arrow.up", "Plein écran"), topRight: ("arrow.up.right", "Coin"),
                left: ("arrow.left", "Moitié gauche"), right: ("arrow.right", "Moitié droite"),
                bottomLeft: ("arrow.down.left", "Coin"), bottom: ("arrow.down", "Minimiser"), bottomRight: ("arrow.down.right", "Coin")
            )
            Label("Pincer fermé = fermer · pincer ouvert = plein écran", systemImage: "hand.pinch")
                .font(labelFont)
                .foregroundStyle(.secondary)

            sectionHeader("Icône du Dock", icon: "dock.rectangle")
                .padding(.top, compact ? 4 : 8)
            cheatGrid(
                topLeft: nil, top: ("arrow.up", "Désminimiser"), topRight: nil,
                left: ("arrow.left", "Fenêtre préc."), right: ("arrow.right", "Fenêtre suiv."),
                bottomLeft: nil, bottom: ("arrow.down", "Quitter"), bottomRight: nil
            )
            Label("Pincer fermé = minimiser · pincer ouvert = nouvelle fenêtre (⌘N)", systemImage: "hand.pinch")
                .font(labelFont)
                .foregroundStyle(.secondary)
            Text("Si l'app n'est pas lancée, lance-la toi-même — Flick ne le fait plus automatiquement.")
                .font(labelFont)
                .foregroundStyle(.tertiary)
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

    private typealias CheatCell = (icon: String, label: String)

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
                Image(systemName: cell.icon)
                    .font(iconFont)
                    .foregroundStyle(.tint)
                Text(cell.label)
                    .font(labelFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    GestureCheatSheetView()
        .padding(24)
        .frame(width: 420)
}

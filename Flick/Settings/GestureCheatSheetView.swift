import SwiftUI

/// Position within a 3×3 gesture grid — shared identity between the title-bar grid and
/// the Dock grid, and between every place that renders one (Onboarding, Réglages
/// Raccourcis, the live HUD). Also used by `FlickController`/`GestureActivityLog` to say
/// which cell the in-progress gesture currently corresponds to.
enum GestureGridPosition: Hashable {
    case topLeft, top, topRight
    case left, center, right
    case bottomLeft, bottom, bottomRight
}

/// Which of the two 3×3 grids (title bar vs. Dock icon) a live gesture is updating.
enum GestureGridKind {
    case none, title, dock
}

/// What a single grid cell shows: nothing (dashed placeholder), the grid's own center
/// label ("FENÊTRE"/"DOCK"), a directional SF Symbol, or one of the flat colored badges
/// from `Assets.xcassets/Actions`.
enum GestureGridCellKind {
    case empty
    case center(label: String)
    case arrow(symbol: String, label: String, shortLabel: String)
    case badge(assetName: String, label: String, shortLabel: String)
}

/// The gesture-to-action mapping for one surface (title bar or Dock icon) — shared
/// between the live HUD panel, the Onboarding tour, and the Preferences "Raccourcis" tab,
/// so the mapping itself is only ever defined once.
struct GestureGrid {
    var topLeft: GestureGridCellKind
    var top: GestureGridCellKind
    var topRight: GestureGridCellKind
    var left: GestureGridCellKind
    var center: GestureGridCellKind
    var right: GestureGridCellKind
    var bottomLeft: GestureGridCellKind
    var bottom: GestureGridCellKind
    var bottomRight: GestureGridCellKind

    func cell(at position: GestureGridPosition) -> GestureGridCellKind {
        switch position {
        case .topLeft: return topLeft
        case .top: return top
        case .topRight: return topRight
        case .left: return left
        case .center: return center
        case .right: return right
        case .bottomLeft: return bottomLeft
        case .bottom: return bottom
        case .bottomRight: return bottomRight
        }
    }

    /// Title-bar gesture map — matches `GestureClassifier`'s swipe/pinch classification.
    static let title = GestureGrid(
        topLeft: .arrow(symbol: "arrow.up.left", label: "Coin", shortLabel: "Coin"),
        top: .badge(assetName: "agrandir", label: "Plein écran", shortLabel: "Plein écran"),
        topRight: .arrow(symbol: "arrow.up.right", label: "Coin", shortLabel: "Coin"),
        left: .arrow(symbol: "arrow.left", label: "Moitié gauche", shortLabel: "Moitié g."),
        center: .center(label: "Fenêtre"),
        right: .arrow(symbol: "arrow.right", label: "Moitié droite", shortLabel: "Moitié d."),
        bottomLeft: .arrow(symbol: "arrow.down.left", label: "Coin", shortLabel: "Coin"),
        bottom: .badge(assetName: "reduire", label: "Minimiser", shortLabel: "Minimiser"),
        bottomRight: .arrow(symbol: "arrow.down.right", label: "Coin", shortLabel: "Coin")
    )

    /// Dock-icon gesture map — matches `DockGestureClassifier`'s swipe classification.
    /// Pinch-driven actions (nouvelle fenêtre / minimiser) have no dedicated cell.
    static let dock = GestureGrid(
        topLeft: .empty,
        top: .arrow(symbol: "arrow.up", label: "Désminimiser", shortLabel: "Rouvrir"),
        topRight: .empty,
        left: .arrow(symbol: "arrow.left", label: "Fenêtre préc.", shortLabel: "Préc."),
        center: .center(label: "Dock"),
        right: .arrow(symbol: "arrow.right", label: "Fenêtre suiv.", shortLabel: "Suiv."),
        bottomLeft: .empty,
        bottom: .badge(assetName: "quitter", label: "Quitter", shortLabel: "Quitter"),
        bottomRight: .empty
    )
}

/// The three sizes a `GestureGridView` is drawn at — large (Onboarding), medium
/// (Réglages › Raccourcis), and compact (live HUD panel, where the active cell lights up).
enum GestureGridStyle: Equatable {
    case large, medium, compact

    var tileSize: CGFloat {
        switch self {
        case .large: return 58
        case .medium: return 54
        case .compact: return 46
        }
    }

    var gap: CGFloat { self == .compact ? 3 : 4 }
    var cornerRadius: CGFloat { self == .large ? 10 : (self == .medium ? 9 : 8) }
    var innerSpacing: CGFloat { self == .compact ? 3 : 4 }
    /// Only the compact HUD grid has room/need for an active-cell highlight.
    var supportsActiveCell: Bool { self == .compact }
    var usesShortLabels: Bool { self != .large }

    var tileFill: Color {
        self == .compact ? Color.white.opacity(0.05) : FlickTheme.tileBackground
    }

    var centerFill: Color {
        self == .compact ? Color.white.opacity(0.04) : FlickTheme.accent.opacity(0.12)
    }

    var centerBorder: Color {
        self == .compact ? .clear : FlickTheme.accent.opacity(0.35)
    }

    var centerForeground: Color {
        self == .compact ? FlickTheme.textQuaternary : FlickTheme.accentText
    }

    var centerFont: Font {
        switch self {
        case .large: return .system(size: 10, weight: .bold)
        case .medium: return .system(size: 9.5, weight: .bold)
        case .compact: return .system(size: 9, weight: .bold)
        }
    }

    var iconFont: Font {
        switch self {
        case .large: return .system(size: 17)
        case .medium: return .system(size: 16)
        case .compact: return .system(size: 14)
        }
    }

    var badgeSize: CGFloat {
        switch self {
        case .large: return 16
        case .medium: return 15
        case .compact: return 13
        }
    }

    var labelFont: Font {
        switch self {
        case .large: return .system(size: 10.5)
        case .medium: return .system(size: 10)
        case .compact: return .system(size: 9.5)
        }
    }

    var labelColor: Color {
        self == .compact ? FlickTheme.textSecondary : FlickTheme.gridLabel
    }

    var dashColor: Color { Color.white.opacity(self == .compact ? 0.06 : 0.07) }
}

/// Renders one `GestureGrid` as a 3×3 grid of tiles — the single shared component behind
/// the Onboarding gesture tour, the Preferences "Raccourcis" tab, and the live HUD panel's
/// two compact grids (which additionally light up whichever cell the current gesture maps
/// to, via `activePosition`).
struct GestureGridView: View {
    let grid: GestureGrid
    var style: GestureGridStyle
    var activePosition: GestureGridPosition? = nil

    private static let positions: [[GestureGridPosition]] = [
        [.topLeft, .top, .topRight],
        [.left, .center, .right],
        [.bottomLeft, .bottom, .bottomRight]
    ]

    var body: some View {
        VStack(spacing: style.gap) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: style.gap) {
                    ForEach(Self.positions[row], id: \.self) { position in
                        cell(at: position)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(at position: GestureGridPosition) -> some View {
        let isActive = style.supportsActiveCell && position == activePosition
        cellBody(grid.cell(at: position), isActive: isActive)
            .frame(width: style.tileSize, height: style.tileSize)
    }

    @ViewBuilder
    private func cellBody(_ kind: GestureGridCellKind, isActive: Bool) -> some View {
        switch kind {
        case .empty:
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .strokeBorder(style.dashColor, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

        case .center(let label):
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .fill(style.centerFill)
                .overlay(RoundedRectangle(cornerRadius: style.cornerRadius).strokeBorder(style.centerBorder))
                .overlay(
                    Text(label.uppercased())
                        .font(style.centerFont)
                        .foregroundStyle(style.centerForeground)
                        .tracking(0.5)
                )

        case .arrow(let symbol, let label, let shortLabel):
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .fill(isActive ? FlickTheme.accent : style.tileFill)
                .overlay(
                    VStack(spacing: style.innerSpacing) {
                        Image(systemName: symbol)
                            .font(style.iconFont)
                            .foregroundStyle(isActive ? Color.white : FlickTheme.accent)
                        Text(style.usesShortLabels ? shortLabel : label)
                            .font(style.labelFont)
                            .foregroundStyle(isActive ? Color.white : style.labelColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                )

        case .badge(let assetName, let label, let shortLabel):
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .fill(isActive ? FlickTheme.accent : style.tileFill)
                .overlay(
                    VStack(spacing: style.innerSpacing) {
                        Image(assetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: style.badgeSize, height: style.badgeSize)
                        Text(style.usesShortLabels ? shortLabel : label)
                            .font(style.labelFont)
                            .foregroundStyle(isActive ? Color.white : style.labelColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                )
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        HStack(spacing: 24) {
            GestureGridView(grid: .title, style: .large)
            GestureGridView(grid: .dock, style: .large)
        }
        HStack(spacing: 16) {
            GestureGridView(grid: .title, style: .medium)
            GestureGridView(grid: .dock, style: .medium)
        }
        HStack(spacing: 12) {
            GestureGridView(grid: .title, style: .compact, activePosition: .left)
            GestureGridView(grid: .dock, style: .compact)
        }
    }
    .padding(24)
    .background(FlickTheme.windowBackground)
}

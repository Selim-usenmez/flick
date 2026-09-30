import SwiftUI

/// A small flat glyph shown beside a Dock icon or near the cursor while a gesture is in
/// progress — mirrors macOS's own traffic-light glyphs (×, −, ⤢). No background shape
/// behind either kind: just the sharp-edged icon itself, in its own color. Shared between
/// `DockActionPreviewPanelController` (Dock icon gestures) and
/// `WindowActionBadgePanelController` (title-bar pinch/swipe gestures).
struct ActionBadgeView: View {
    /// Either a monochrome SF Symbol tinted to an accent color, or one of the flat colored
    /// glyphs from `Assets.xcassets/Actions` (already colored, drawn as-is).
    enum Glyph: Equatable {
        case symbol(name: String, tint: Color)
        case badge(assetName: String)
    }

    let glyph: Glyph

    /// Also read by the panel controllers to size the panel that hosts this view — kept
    /// as a single source of truth so they never drift out of sync.
    static let diameter: CGFloat = 30

    var body: some View {
        switch glyph {
        case .symbol(let name, let tint):
            Image(systemName: name)
                .resizable()
                .scaledToFit()
                .fontWeight(.bold)
                .foregroundStyle(tint)
                .frame(width: Self.diameter, height: Self.diameter)
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
        case .badge(let assetName):
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: Self.diameter, height: Self.diameter)
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
        }
    }
}

#Preview {
    HStack(spacing: 24) {
        ActionBadgeView(glyph: .badge(assetName: "quitter"))
        ActionBadgeView(glyph: .badge(assetName: "fermer"))
        ActionBadgeView(glyph: .badge(assetName: "agrandir"))
        ActionBadgeView(glyph: .badge(assetName: "reduire"))
        ActionBadgeView(glyph: .symbol(name: "plus", tint: .yellow))
        ActionBadgeView(glyph: .symbol(name: "arrow.right", tint: .accentColor))
    }
    .padding(40)
    .background(.gray)
}

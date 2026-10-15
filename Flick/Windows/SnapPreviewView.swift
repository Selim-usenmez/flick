import SwiftUI

/// A tiny "mini screen" preview shown near the cursor while a window-snap gesture is in
/// progress — just a translucent screen silhouette with the target snap region filled in
/// solid accent, no glass frame or border. Deliberately minimal and small (30×22) so it
/// reads as a quick confirmation, not a focal overlay.
struct SnapPreviewView: View {
    /// Target region as a fraction (0...1) of the screen's visible frame, top-left origin.
    /// Fixed-size, geometry-only content (no text, no dynamic intrinsic size) by design —
    /// see `DockActionPreviewPanelController` for why a `NSHostingView` whose ideal size can
    /// drift from its panel's fixed frame is how these panels have crashed before.
    let region: CGRect

    static let size = CGSize(width: 30, height: 22)
    /// Padding around the mini-screen so the target region's soft shadow has room to
    /// render without being clipped by the hosting panel's bounds (which is sized to
    /// `panelSize`, not `size`).
    private static let shadowMargin: CGFloat = 8
    static let panelSize = CGSize(width: size.width + shadowMargin * 2, height: size.height + shadowMargin * 2)

    var body: some View {
        let x = Self.inset(origin: region.minX, size: region.width, dimension: Self.size.width)
        let y = Self.inset(origin: region.minY, size: region.height, dimension: Self.size.height)

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 7)
                .fill(FlickTheme.snap.opacity(0.20))

            RoundedRectangle(cornerRadius: 6)
                .fill(FlickTheme.snap)
                .shadow(color: FlickTheme.snap.opacity(0.35), radius: 4, y: 2)
                .frame(width: x.size, height: y.size)
                .offset(x: x.origin, y: y.origin)
                .animation(FlickTheme.spring, value: region)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .padding(Self.shadowMargin)
    }

    /// A 1pt gap is kept at every internal dividing line (half/quarter boundaries) so
    /// adjacent regions never visually touch, while regions against a screen edge stay
    /// flush with it.
    private static func inset(origin: CGFloat, size: CGFloat, dimension: CGFloat) -> (origin: CGFloat, size: CGFloat) {
        let o = origin * dimension + (origin > 0 ? 1 : 0)
        let s = size * dimension - (size < 1 ? 1 : 0)
        return (o, s)
    }
}

#Preview {
    HStack(spacing: 24) {
        SnapPreviewView(region: CGRect(x: 0, y: 0, width: 0.5, height: 1))
        SnapPreviewView(region: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
        SnapPreviewView(region: CGRect(x: 0, y: 0, width: 1, height: 1))
    }
    .padding(40)
    .background(.gray)
}

import SwiftUI

/// A small "mini screen" preview shown near the cursor while a window-snap gesture is in
/// progress — a frosted-glass outline of the screen with the target snap region
/// highlighted, mirroring Swish's floating cursor-side preview instead of a full-size
/// overlay on the actual target region.
struct SnapPreviewView: View {
    /// Target region as a fraction (0...1) of the screen's visible frame, top-left origin.
    /// Fixed-size, geometry-only content (no text, no dynamic intrinsic size) by design —
    /// see `DockActionPreviewPanelController` for why a `NSHostingView` whose ideal size can
    /// drift from its panel's fixed frame is how these panels have crashed before.
    let region: CGRect

    static let size = CGSize(width: 160, height: 100)
    private static let inset: CGFloat = 7

    var body: some View {
        let usableWidth = Self.size.width - Self.inset * 2
        let usableHeight = Self.size.height - Self.inset * 2

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 16)
                .fill(.black.opacity(0.18))
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.22), lineWidth: 1)

            RoundedRectangle(cornerRadius: 7)
                .fill(
                    LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.55), lineWidth: 1))
                .shadow(color: .blue.opacity(0.6), radius: 8, y: 3)
                .frame(width: usableWidth * region.width, height: usableHeight * region.height)
                .offset(x: Self.inset + usableWidth * region.minX, y: Self.inset + usableHeight * region.minY)
                .animation(.spring(response: 0.25, dampingFraction: 0.75), value: region)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
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

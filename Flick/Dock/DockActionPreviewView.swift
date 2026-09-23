import SwiftUI

/// A big glossy circle shown above a Dock icon while a gesture is in progress — mirrors
/// macOS's own traffic-light glyphs (×, −, ⤢), styled like a native glass button rather
/// than a flat colored dot.
struct DockActionPreviewView: View {
    let systemImage: String
    let tint: Color

    private static let diameter: CGFloat = 72

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [tint.opacity(0.85), tint],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .overlay(
                // A soft sheen toward the upper-left, like light catching a glass button.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.35), .white.opacity(0)],
                            center: UnitPoint(x: 0.3, y: 0.25),
                            startRadius: 0,
                            endRadius: Self.diameter * 0.65
                        )
                    )
            )
            .overlay(
                Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1.5)
            )
            .frame(width: Self.diameter, height: Self.diameter)
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: Self.diameter * 0.36, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
            )
            .shadow(color: tint.opacity(0.55), radius: 16, y: 8)
            .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
    }
}

#Preview {
    HStack(spacing: 24) {
        DockActionPreviewView(systemImage: "xmark", tint: .red)
        DockActionPreviewView(systemImage: "minus", tint: .yellow)
        DockActionPreviewView(systemImage: "arrow.up.left.and.arrow.down.right", tint: .green)
    }
    .padding(40)
    .background(.gray)
}

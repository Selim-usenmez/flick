import SwiftUI

/// A small pill shown above a Dock icon while a gesture (launch/quit/close/maximize) is in
/// progress.
struct DockActionPreviewView: View {
    let systemImage: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .foregroundStyle(tint)
        .background(.ultraThinMaterial, in: Capsule())
        .background(tint.opacity(0.15), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.3), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
    }
}

#Preview {
    VStack(spacing: 20) {
        DockActionPreviewView(systemImage: "xmark.circle.fill", text: "Safari — Quitter", tint: .red)
        DockActionPreviewView(systemImage: "plus.square.fill", text: "Nouvelle fenêtre", tint: .accentColor)
        DockActionPreviewView(systemImage: "minus.circle.fill", text: "Minimiser", tint: .yellow)
    }
    .padding(40)
}

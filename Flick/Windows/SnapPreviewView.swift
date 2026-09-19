import SwiftUI

/// Translucent highlight drawn over the screen region a gesture is about to snap a window
/// into, updated live while the gesture is in progress.
struct SnapPreviewView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.blue.opacity(0.25))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.blue, lineWidth: 3)
            )
            .padding(8)
    }
}

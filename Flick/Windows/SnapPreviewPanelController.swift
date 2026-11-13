import AppKit
import SwiftUI

/// Hosts `SnapPreviewView` in a small, click-through panel that floats near the cursor
/// while a window-snap gesture is in progress, instead of a full-size highlight over the
/// actual target region — mirrors Swish's floating mini-preview.
final class SnapPreviewPanelController {
    private let panel = FloatingPreviewPanel<SnapPreviewView>()

    /// - Parameters:
    ///   - region: target snap region as a fraction (0...1) of the screen, top-left origin.
    ///   - cursor: current cursor position, in AppKit screen coordinates (e.g.
    ///     `NSEvent.mouseLocation`).
    func show(region: CGRect, near cursor: NSPoint) {
        panel.show(
            contentKey: RegionKey(region),
            frame: CursorAnchoredFrame.frame(near: cursor, size: SnapPreviewView.panelSize)
        ) {
            SnapPreviewView(region: region)
        }
    }

    func hide() {
        panel.hide()
    }

    /// `CGRect` isn't `Hashable`; this is just enough identity for the no-op diffing.
    private struct RegionKey: Hashable {
        let x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat
        init(_ rect: CGRect) {
            x = rect.minX; y = rect.minY; width = rect.width; height = rect.height
        }
    }
}

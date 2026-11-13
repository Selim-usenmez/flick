import AppKit
import SwiftUI

/// Where the user has the Dock docked — read straight from the same preference the Dock
/// itself reads, so this always matches reality instead of guessing from screen geometry
/// (which gets ambiguous with auto-hide, multiple displays, etc).
enum DockEdge {
    case bottom, left, right

    static var current: DockEdge {
        switch CFPreferencesCopyAppValue("orientation" as CFString, "com.apple.dock" as CFString) as? String {
        case "left": return .left
        case "right": return .right
        default: return .bottom
        }
    }
}

/// Hosts `ActionBadgeView` in a click-through floating panel while a gesture is resolving
/// to a traffic-light-style action. One panel serves both gesture surfaces — they're never
/// visible at the same time, since a gesture has exactly one target:
///
/// - **Title bar** (close/minimize): the badge floats beside the cursor, mirroring
///   `SnapPreviewPanelController`'s placement.
/// - **Dock icon** (quit, new window, cycle...): the badge sits just off the icon's edge —
///   above it for a bottom Dock, beside it for a left/right Dock.
final class ActionBadgePanelController {
    private let panel = FloatingPreviewPanel<ActionBadgeView>()

    /// Gap left between a Dock icon's edge and the badge.
    private static let dockGap: CGFloat = 10
    /// Padding around the badge itself, so its soft shadow has room to render without
    /// being clipped by the panel's bounds.
    private static let shadowMargin: CGFloat = 20
    private static let size = CGSize(
        width: ActionBadgeView.diameter + shadowMargin * 2,
        height: ActionBadgeView.diameter + shadowMargin * 2
    )

    /// - Parameter cursor: current cursor position, in AppKit screen coordinates.
    func show(glyph: ActionBadgeView.Glyph, near cursor: NSPoint) {
        show(glyph: glyph, frame: CursorAnchoredFrame.frame(near: cursor, size: Self.size))
    }

    /// - Parameters:
    ///   - dockIconFrame: the icon's frame in AppKit screen coordinates.
    ///   - dockEdge: resolved once per gesture by the caller (it's a preference read).
    func show(glyph: ActionBadgeView.Glyph, besideDockIcon dockIconFrame: NSRect, dockEdge: DockEdge) {
        let origin: NSPoint
        switch dockEdge {
        case .bottom:
            origin = NSPoint(x: dockIconFrame.midX - Self.size.width / 2, y: dockIconFrame.maxY + Self.dockGap)
        case .left:
            origin = NSPoint(x: dockIconFrame.maxX + Self.dockGap, y: dockIconFrame.midY - Self.size.height / 2)
        case .right:
            origin = NSPoint(x: dockIconFrame.minX - Self.dockGap - Self.size.width, y: dockIconFrame.midY - Self.size.height / 2)
        }
        show(glyph: glyph, frame: NSRect(origin: origin, size: Self.size))
    }

    func hide() {
        panel.hide()
    }

    private func show(glyph: ActionBadgeView.Glyph, frame: NSRect) {
        panel.show(contentKey: glyph, frame: frame) {
            ActionBadgeView(glyph: glyph)
        }
    }
}

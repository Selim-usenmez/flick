import AppKit
import SwiftUI

/// A borderless, click-through, always-on-top panel hosting one small SwiftUI view — the
/// shared machinery behind every live gesture preview (the cursor-side snap mini-screen
/// and the action badges). Owns exactly what the three former per-panel controllers each
/// duplicated: lazy panel creation, strict no-op diffing for the 60–120Hz update stream,
/// and a short AppKit-driven fade in/out.
///
/// Synchronous by design: the caller (`FlickController`'s single coalesced preview
/// dispatcher) already guarantees `show`/`hide` run once per fresh run-loop turn, with
/// every other panel's decision for that same turn applied alongside in one atomic step.
/// Deferring *again* in here, independently per panel, was tried before and made things
/// worse — under a fast gesture, each panel's own queued turn could drain in a different
/// order than intended, letting two panels end up visible at once.
final class FloatingPreviewPanel<Content: View> {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<Content>?
    private var lastFrame: NSRect?
    private var lastContentKey: AnyHashable?
    private(set) var isVisible = false
    /// Bumped on every show/hide so a fade-out's completion can tell whether the panel was
    /// re-shown in the meantime (in which case it must *not* order the panel out).
    private var visibilityGeneration = 0

    private static var fadeInDuration: TimeInterval { 0.12 }
    private static var fadeOutDuration: TimeInterval { 0.14 }

    /// - Parameters:
    ///   - contentKey: identifies the content; the SwiftUI root view is only rebuilt when
    ///     it changes. Re-applying identical content/frames that often was enough to flood
    ///     AppKit's constraint/display pass and trip a "needing another Update Constraints"
    ///     fault, so every call here is a strict no-op unless something actually changed.
    ///   - frame: the panel's frame in AppKit screen coordinates.
    func show(contentKey: AnyHashable, frame: NSRect, content: () -> Content) {
        if let panel, let hostingView {
            if contentKey != lastContentKey {
                lastContentKey = contentKey
                if isVisible {
                    hostingView.rootView = content()
                } else {
                    // Coming back from hidden: swap content with implicit animations
                    // suppressed, so a transition doesn't start on an off-screen window
                    // (where no display cycle runs to ever finish it) and then play out
                    // half-done the moment the panel appears.
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { hostingView.rootView = content() }
                }
            }
            if frame != lastFrame {
                lastFrame = frame
                panel.setFrame(frame, display: false)
            }
            if !isVisible { fadeIn(panel) }
            return
        }

        lastFrame = frame
        lastContentKey = contentKey

        let hostingView = NSHostingView(rootView: content())
        // Without this, NSHostingView tries to auto-size the panel to its SwiftUI
        // content's ideal size, fighting our explicit `setFrame` calls above.
        hostingView.sizingOptions = []
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Each content view draws its own shadow; a second, AppKit-layer window shadow on
        // top of that just looks like a smudge.
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = hostingView
        self.panel = panel
        self.hostingView = hostingView
        fadeIn(panel)
    }

    func hide() {
        guard isVisible, let panel else { return }
        isVisible = false
        visibilityGeneration += 1
        let generation = visibilityGeneration
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fadeOutDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.visibilityGeneration == generation else { return }
            panel.orderOut(nil)
        })
    }

    private func fadeIn(_ panel: NSPanel) {
        isVisible = true
        visibilityGeneration += 1
        // Never animate *from* a stale mid-fade value; always a clean fade from clear.
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeInDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }
}

/// Where a cursor-anchored panel of `size` should sit: to the right of the cursor, flipped
/// to the left if that would run off the edge of whichever screen the cursor is on, and
/// clamped vertically to that screen.
enum CursorAnchoredFrame {
    static let cursorGap: CGFloat = 20

    static func frame(near cursor: NSPoint, size: CGSize) -> NSRect {
        let screenFrame = NSScreen.screens.first { $0.frame.contains(cursor) }?.frame ?? NSScreen.main?.frame ?? .zero
        var origin = NSPoint(x: cursor.x + cursorGap, y: cursor.y - size.height / 2)
        if origin.x + size.width > screenFrame.maxX {
            origin.x = cursor.x - cursorGap - size.width
        }
        origin.y = min(max(origin.y, screenFrame.minY), screenFrame.maxY - size.height)
        return NSRect(origin: origin, size: size)
    }
}

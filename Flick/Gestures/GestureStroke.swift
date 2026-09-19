import AppKit

/// What kind of trackpad gesture produced a stroke's accumulated data — determines which
/// accumulator (`averageTranslation` or `magnification`) is meaningful.
enum GestureKind: Equatable {
    case translation
    case magnify
}

/// Accumulates trackpad displacement for the lifetime of a single gesture (first finger
/// down to last finger up), so a caller can classify a completed gesture once it ends.
///
/// Translation comes from `NSEvent.scrollingDeltaX/Y` (see `TouchGestureMonitor`).
/// Magnification comes from raw finger-distance deltas computed from
/// `MultitouchSupport.framework` frames, not from `NSEvent.magnification` — AppKit's pinch
/// gesture events are only ever delivered to whichever app is frontmost, so they're useless
/// for a gesture happening over another app's window or a Dock icon.
struct GestureStroke {
    private(set) var kind: GestureKind = .translation
    private(set) var activeTouchCount: Int = 0
    /// Screen point (AppKit coordinates) where the gesture started, captured via
    /// `NSEvent.mouseLocation` — used to find which window's title bar the gesture began
    /// over.
    private(set) var startLocation: NSPoint = .zero
    private var accumulatedDX: CGFloat = 0
    private var accumulatedDY: CGFloat = 0
    private(set) var magnification: CGFloat = 0

    var isEmpty: Bool { activeTouchCount == 0 }

    /// Accumulated displacement since `begin`, in points. Only meaningful for `.translation`.
    var averageTranslation: CGVector { CGVector(dx: accumulatedDX, dy: accumulatedDY) }

    mutating func begin(touchCount: Int, at location: NSPoint, kind: GestureKind) {
        self.kind = kind
        activeTouchCount = touchCount
        startLocation = location
        accumulatedDX = 0
        accumulatedDY = 0
        magnification = 0
    }

    mutating func accumulate(dx: CGFloat, dy: CGFloat) {
        accumulatedDX += dx
        accumulatedDY += dy
    }

    mutating func accumulateMagnification(_ delta: CGFloat) {
        magnification += delta
    }

    mutating func end() {
        activeTouchCount = 0
    }

    mutating func reset() {
        activeTouchCount = 0
        accumulatedDX = 0
        accumulatedDY = 0
        magnification = 0
    }
}

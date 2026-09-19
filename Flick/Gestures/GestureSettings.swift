import CoreGraphics
import Observation

/// User-tunable knobs for gesture recognition, editable live from the control panel.
@Observable
final class GestureSettings {
    /// Minimum swipe travel, in points, before it counts as intentional rather than noise.
    var minimumSwipeDistance: CGFloat = 60
    /// How close the smaller axis's magnitude must be to the larger one before a swipe is
    /// classified as diagonal rather than cardinal. 0.5 made an ordinary, not-perfectly-
    /// straight swipe (natural hand motion always has some drift on the other axis) land as
    /// a quarter instead of the intended half far too easily — this needs to look close to
    /// an actual 45° swipe before treating it as diagonal.
    var diagonalRatio: CGFloat = 0.7
    /// Minimum cumulative change in normalized inter-finger trackpad distance (roughly
    /// 0...1 across the whole pad) before it counts as a close/maximize (or quit/new-window)
    /// gesture rather than noise.
    var pinchThreshold: CGFloat = 0.08

    /// Flip these if directions feel backwards: `NSEvent`'s scrolling deltas invert with
    /// the system's "Natural Scrolling" trackpad setting, which isn't queryable from here.
    var invertHorizontal = false
    var invertVertical = false
    /// Flip if pinching closed triggers maximize/new-window instead of close/quit.
    var invertPinch = false
}

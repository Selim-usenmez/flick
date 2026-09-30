import CoreGraphics
import Foundation
import Observation

/// User-tunable knobs for gesture recognition, editable live from the control panel.
/// Persisted to `UserDefaults` as each one changes, so a tweak (e.g. loosening the
/// diagonal tolerance) survives a relaunch instead of silently reverting to the default.
@Observable
final class GestureSettings {
    private enum Key {
        static let minimumSwipeDistance = "com.selim.Flick.minimumSwipeDistance"
        static let diagonalRatio = "com.selim.Flick.diagonalRatio"
        static let pinchThreshold = "com.selim.Flick.pinchThreshold"
        static let invertHorizontal = "com.selim.Flick.invertHorizontal"
        static let invertVertical = "com.selim.Flick.invertVertical"
        static let invertPinch = "com.selim.Flick.invertPinch"
    }

    /// Minimum swipe travel, in points, before it counts as intentional rather than noise.
    var minimumSwipeDistance: CGFloat {
        didSet { UserDefaults.standard.set(Double(minimumSwipeDistance), forKey: Key.minimumSwipeDistance) }
    }
    /// How close the smaller axis's magnitude must be to the larger one before a swipe is
    /// classified as diagonal rather than cardinal. 0.5 made an ordinary, not-perfectly-
    /// straight swipe (natural hand motion always has some drift on the other axis) land as
    /// a quarter instead of the intended half far too easily — this needs to look close to
    /// an actual 45° swipe before treating it as diagonal.
    var diagonalRatio: CGFloat {
        didSet { UserDefaults.standard.set(Double(diagonalRatio), forKey: Key.diagonalRatio) }
    }
    /// Minimum cumulative change in normalized inter-finger trackpad distance (roughly
    /// 0...1 across the whole pad) before it counts as a close/maximize (or quit/new-window)
    /// gesture rather than noise.
    var pinchThreshold: CGFloat {
        didSet { UserDefaults.standard.set(Double(pinchThreshold), forKey: Key.pinchThreshold) }
    }

    /// Flip these if directions feel backwards: `NSEvent`'s scrolling deltas invert with
    /// the system's "Natural Scrolling" trackpad setting, which isn't queryable from here.
    var invertHorizontal: Bool {
        didSet { UserDefaults.standard.set(invertHorizontal, forKey: Key.invertHorizontal) }
    }
    var invertVertical: Bool {
        didSet { UserDefaults.standard.set(invertVertical, forKey: Key.invertVertical) }
    }
    /// Flip if pinching closed triggers maximize/new-window instead of close/quit.
    var invertPinch: Bool {
        didSet { UserDefaults.standard.set(invertPinch, forKey: Key.invertPinch) }
    }

    init() {
        let defaults = UserDefaults.standard
        minimumSwipeDistance = Self.storedDouble(defaults, Key.minimumSwipeDistance, default: 60)
        diagonalRatio = Self.storedDouble(defaults, Key.diagonalRatio, default: 0.7)
        pinchThreshold = Self.storedDouble(defaults, Key.pinchThreshold, default: 0.08)
        invertHorizontal = Self.storedBool(defaults, Key.invertHorizontal, default: false)
        invertVertical = Self.storedBool(defaults, Key.invertVertical, default: false)
        invertPinch = Self.storedBool(defaults, Key.invertPinch, default: false)
    }

    /// `object(forKey:) as? CGFloat` isn't a reliable cast from the `NSNumber` a stored
    /// double round-trips through — going via `double(forKey:)` (only meaningful once
    /// presence is confirmed, since it otherwise silently returns 0) is the safe path.
    private static func storedDouble(_ defaults: UserDefaults, _ key: String, default fallback: CGFloat) -> CGFloat {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return CGFloat(defaults.double(forKey: key))
    }

    private static func storedBool(_ defaults: UserDefaults, _ key: String, default fallback: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.bool(forKey: key)
    }
}

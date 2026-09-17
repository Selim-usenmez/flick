import AppKit

/// Accumulates per-finger trackpad displacement between the first touch-down and now,
/// so a caller can classify a completed gesture once every finger has lifted.
struct GestureStroke {
    /// `NSTouch.identity` is opaque and untyped, but Apple guarantees it stays the same
    /// object for a given finger across its whole lifetime — so its `ObjectIdentifier`
    /// is a safe, allocation-free dictionary key. The `NSTouch` object itself is not:
    /// AppKit creates a fresh instance every phase, and its Hashable/Equatable
    /// conformance is not documented to be identity-based.
    private var startPositions: [ObjectIdentifier: NSPoint] = [:]
    private var currentPositions: [ObjectIdentifier: NSPoint] = [:]

    /// Sampled path of the stroke's centroid, oldest first. Unused until Phase 5 (shape
    /// gestures), kept here because this is where the touch stream is already collapsed
    /// into one displacement per event.
    private(set) var centroidPath: [NSPoint] = []

    var activeTouchCount: Int { currentPositions.count }

    var isEmpty: Bool { currentPositions.isEmpty }

    mutating func update(with touches: Set<NSTouch>) {
        for touch in touches {
            let key = ObjectIdentifier(touch.identity as AnyObject)
            let phase = touch.phase
            if phase.contains(.began) {
                startPositions[key] = touch.normalizedPosition
                currentPositions[key] = touch.normalizedPosition
            } else if phase.contains(.moved) || phase.contains(.stationary) {
                currentPositions[key] = touch.normalizedPosition
            } else if phase.contains(.ended) || phase.contains(.cancelled) {
                startPositions.removeValue(forKey: key)
                currentPositions.removeValue(forKey: key)
            }
        }
        if let centroid = averageCurrentPosition {
            centroidPath.append(centroid)
        }
    }

    mutating func reset() {
        startPositions.removeAll()
        currentPositions.removeAll()
        centroidPath.removeAll()
    }

    private var averageCurrentPosition: NSPoint? {
        guard !currentPositions.isEmpty else { return nil }
        let sum = currentPositions.values.reduce(NSPoint.zero) { NSPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        let count = CGFloat(currentPositions.count)
        return NSPoint(x: sum.x / count, y: sum.y / count)
    }

    /// Average per-finger displacement since each finger's own touch-down, in normalized
    /// trackpad units (0...1 per axis). Averaging per-finger (rather than diffing
    /// centroids) keeps the result stable if fingers land at slightly different times.
    var averageTranslation: CGVector {
        var totalDX: CGFloat = 0
        var totalDY: CGFloat = 0
        var count = 0
        for (key, current) in currentPositions {
            guard let start = startPositions[key] else { continue }
            totalDX += current.x - start.x
            totalDY += current.y - start.y
            count += 1
        }
        guard count > 0 else { return .zero }
        return CGVector(dx: totalDX / CGFloat(count), dy: totalDY / CGFloat(count))
    }
}

import CoreGraphics

/// Turns a completed gesture into a snap action: swipe direction maps to a screen region or
/// the yellow traffic-light button (Swish-style), pinch maps to the red/green traffic-light
/// buttons — close and maximize.
struct GestureClassifier {
    static func action(for stroke: GestureStroke, settings: GestureSettings) -> SnapAction? {
        switch stroke.kind {
        case .magnify:
            guard abs(stroke.magnification) >= settings.pinchThreshold else { return nil }
            // Pinch closed (fingers coming together) = red close button.
            // Pinch open = green maximize button.
            let isOpen = (stroke.magnification > 0) != settings.invertPinch
            return isOpen ? .maximize : .close
        case .translation:
            return classifyTranslation(stroke.averageTranslation, settings: settings)
        }
    }

    private static func classifyTranslation(_ translation: CGVector, settings: GestureSettings) -> SnapAction? {
        let absDX = abs(translation.dx)
        let absDY = abs(translation.dy)
        guard max(absDX, absDY) >= settings.minimumSwipeDistance else { return nil }

        let right = (translation.dx > 0) != settings.invertHorizontal
        let up = (translation.dy < 0) != settings.invertVertical

        let isDiagonal = min(absDX, absDY) >= max(absDX, absDY) * settings.diagonalRatio
        if isDiagonal {
            switch (right, up) {
            case (false, true): return .topLeftQuarter
            case (true, true): return .topRightQuarter
            case (false, false): return .bottomLeftQuarter
            case (true, false): return .bottomRightQuarter
            }
        } else if absDX >= absDY {
            return right ? .rightHalf : .leftHalf
        } else {
            // Swipe up = green maximize button. Swipe down = yellow minimize button.
            return up ? .maximize : .minimize
        }
    }
}

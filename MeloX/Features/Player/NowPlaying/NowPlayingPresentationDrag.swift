import Foundation

/// Point/velocity policy shared by the card and its scroll-aware pan recognizer.
enum NowPlayingPresentationDrag {
    static let maximumTopCornerRadius = 34.0
    // Rational easing preserves the measured ~23.65pt radius at 38% travel,
    // while growing continuously from square to the display-like 34pt radius.
    static let topCornerGrowth = 0.27

    static func progress(origin: Double, translation: Double, height: Double) -> Double {
        let limit = max(0.12, -origin * 2)
        // Invert the rubber band when grabbing a spring above the top edge,
        // so zero finger travel always preserves the visible origin.
        let rawOrigin = origin < 0 ? origin / (1 + origin / limit) : origin
        let raw = rawOrigin + translation / max(height, 1)
        // Downward travel is 1:1. Upward travel asymptotically resists the finger.
        return raw >= 0 ? raw : raw / (1 - raw / limit)
    }

    /// Derivative of the damped offset with respect to finger travel, evaluated
    /// at the release translation. Downward travel stays 1:1; upward travel is
    /// damped by the same rubber band as `progress`, so the spring starts at the
    /// card's visible velocity rather than the raw finger velocity.
    static func velocityScale(origin: Double, translation: Double, height: Double) -> Double {
        let limit = max(0.12, -origin * 2)
        let rawOrigin = origin < 0 ? origin / (1 + origin / limit) : origin
        let raw = rawOrigin + translation / max(height, 1)
        guard raw < 0 else { return 1 }
        let distance = 1 - raw / limit
        return 1 / (distance * distance)
    }

    /// The same visible offset has the same radius in every motion phase.
    static func topCornerRadius(offset: Double, height: Double) -> Double {
        guard height > 0 else { return 0 }
        let progress = min(max(offset / height, 0), 1)
        return maximumTopCornerRadius * progress
            / (progress + topCornerGrowth * (1 - progress))
    }

    static func shouldDismiss(progress: Double, velocity: Double, height: Double) -> Bool {
        // A fast upward reversal should cancel even after crossing the distance threshold.
        guard velocity > -600 else { return false }
        let projected = progress + max(velocity, 0) * 0.2 / max(height, 1)
        return progress > 0.25 || (progress > 0.01 && projected > 0.25)
    }

    static func canBegin(velocityX: Double, velocityY: Double, scrollOffsets: [Double]) -> Bool {
        guard abs(velocityY) > abs(velocityX) else { return false }
        // Each offset includes its scroll view's adjusted top inset. Nested
        // scroll views must all be at the top before yielding a downward drag.
        return scrollOffsets.isEmpty || (velocityY > 0 && scrollOffsets.allSatisfy { $0 <= 1 })
    }
}

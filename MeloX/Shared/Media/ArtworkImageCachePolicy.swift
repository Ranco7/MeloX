import Foundation

nonisolated enum ArtworkImageCachePolicy {
    /// A late, smaller thumbnail must not evict a larger decoded cover.
    static func shouldReplace(existingCost: Int?, newCost: Int) -> Bool {
        guard let existingCost else { return true }
        return newCost >= existingCost
    }
}

nonisolated enum ArtworkBackdropSizing {
    static let minimumPixelDimension = 512.0
    static let maximumPixelDimension = 1024.0
    private static let quantum = 16.0

    static func pixelDimension(longestPixel: Double) -> Double {
        let finite = longestPixel.isFinite ? max(longestPixel, 0) : 0
        let bounded = min(
            max(finite, minimumPixelDimension),
            maximumPixelDimension
        )
        return (bounded / quantum).rounded(.up) * quantum
    }

    static func quantized(dimension: Double) -> Double {
        let finite = dimension.isFinite
            ? dimension
            : minimumPixelDimension
        let bounded = min(
            max(finite, minimumPixelDimension),
            maximumPixelDimension
        )
        return (bounded / quantum).rounded(.up) * quantum
    }
}

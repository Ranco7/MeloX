import Foundation

/// Geometry measured in the supplied album/playlist recordings, conditional
/// on their 2x capture scale. Glyph opacity is a design approximation.
nonisolated enum MusicCollectionSearchLayout {
    static let expandedHeight = 44.0
    static let topInset = 11.0
    static let artworkGap = 29.0
    static let glyphFadeDistance = 7.0
    static let contentTopInset = topInset + expandedHeight + artworkGap

    static func expandedHeight(fontSize: Double) -> Double {
        // Body's line box is taller than its point size, especially at AX sizes.
        max(expandedHeight, ceil((fontSize * 1.3 + 16) / 4) * 4)
    }

    static func height(scroll: Double, expandedHeight: Double = MusicCollectionSearchLayout.expandedHeight) -> Double {
        max(0, expandedHeight - max(0, scroll))
    }

    static func glyphOpacity(scroll: Double) -> Double {
        max(0, 1 - max(0, scroll) / glyphFadeDistance)
    }
}

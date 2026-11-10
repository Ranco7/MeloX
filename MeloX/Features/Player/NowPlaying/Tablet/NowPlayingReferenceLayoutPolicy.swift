import CoreGraphics

/// Select the unmodified 9d5d354 screen by its own geometry, not by the ideal
/// size of a rebuilt column. Its ScrollView remains responsible for real text
/// and controls that exceed the old conservative budget.
enum NowPlayingReferenceLayoutPolicy {
    static let minimumColumnWidth: CGFloat = 5 * 44

    static func controlBudget(elementScale: CGFloat) -> CGFloat {
        238 + 45 * elementScale
    }

    static func usesReference(viewport: CGSize, isAccessibilitySize: Bool = false) -> Bool {
        guard !isAccessibilitySize,
              viewport.width.isFinite, viewport.height.isFinite,
              viewport.width > 0, viewport.height > 0 else { return false }
        let layout = NowPlayingReferenceTabletLayout(viewport: viewport)
        let artworkSection = layout.artworkTopInset + layout.artworkSize + layout.metadataTopInset
        // Only absorb floating-point error at the old compression boundary.
        return layout.playerWidth >= minimumColumnWidth
            && artworkSection + controlBudget(elementScale: layout.elementScale) <= layout.contentHeight + 0.000_001
    }
}

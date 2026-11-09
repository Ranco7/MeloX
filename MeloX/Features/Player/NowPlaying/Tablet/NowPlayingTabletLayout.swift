import CoreGraphics

struct NowPlayingTabletLayout {
    /// Height range over which the player column grows from its base width.
    private static let playerWidthGrowthStartHeight: CGFloat = 600
    private static let playerWidthGrowthHeightRange: CGFloat = 168
    private static let basePlayerWidth: CGFloat = 320
    private static let playerWidthGrowth: CGFloat = 102
    /// Scale references matching the native iPad layout at its design size.
    private static let elementScaleReferenceHeight: CGFloat = 768
    private static let elementScaleReferenceWidth: CGFloat = 1_200
    private static let splitViewWidthRatio: CGFloat = 0.5
    private static let splitViewHorizontalInset: CGFloat = 40
    private static let filledRegionHorizontalInset: CGFloat = 48

    let viewport: CGSize
    var fillsRegion = false

    static let chromeHeight: CGFloat = 48
    static let lyricsTopPadding: CGFloat = 40
    static let bottomBarHeight: CGFloat = 64

    private var heightProgress: CGFloat {
        min(
            max(
                (viewport.height - Self.playerWidthGrowthStartHeight)
                    / Self.playerWidthGrowthHeightRange,
                0
            ),
            1
        )
    }

    var elementScale: CGFloat {
        min(
            max(viewport.height / Self.elementScaleReferenceHeight, 1),
            max(viewport.width / Self.elementScaleReferenceWidth, 1)
        )
    }

    var contentHeight: CGFloat {
        if fillsRegion { return viewport.height }
        return max(viewport.height - Self.chromeHeight - Self.bottomBarHeight, 0)
    }

    private var scaledPlayerWidth: CGFloat {
        (Self.basePlayerWidth + heightProgress * Self.playerWidthGrowth)
            * elementScale
    }

    var playerWidth: CGFloat {
        if fillsRegion {
            return max(
                min(
                    scaledPlayerWidth,
                    viewport.width - Self.filledRegionHorizontalInset
                ),
                1
            )
        }
        // Preserve the desktop proportions while leaving room for both
        // columns in portrait and resizable iPad windows.
        return min(
            scaledPlayerWidth,
            viewport.width * Self.splitViewWidthRatio
                - Self.splitViewHorizontalInset
        )
    }

    var playerLeading: CGFloat {
        viewport.width * 0.25 - playerWidth * 0.5
    }

    var centeredPlayerLeading: CGFloat {
        (viewport.width - playerWidth) * 0.5
    }

    var panelLeading: CGFloat {
        viewport.width * 0.5
    }

    var panelWidth: CGFloat {
        viewport.width * 0.5 - max(24, viewport.width * 0.045)
    }

    private var referenceArtworkSize: CGFloat {
        min((214 + heightProgress * 94) * elementScale, playerWidth * 0.74)
    }

    private var referenceArtworkTopInset: CGFloat {
        let compression = min(max(600 - viewport.height, 0), 50)
        return (54 - compression + heightProgress * 60) * elementScale
    }

    private var referenceMetadataTopInset: CGFloat {
        (70 + heightProgress * 10) * elementScale
    }

    private var verticalCompressionScale: CGFloat {
        // Reserve space for the native touch controls before sizing the
        // artwork and desktop-style whitespace. Short windows can scroll.
        let controlsHeight = 238 + 45 * elementScale
        let artworkSectionHeight = referenceArtworkTopInset
            + referenceArtworkSize
            + referenceMetadataTopInset
        return min(max((contentHeight - controlsHeight) / artworkSectionHeight, 0.6), 1)
    }

    var artworkSize: CGFloat {
        referenceArtworkSize * verticalCompressionScale
    }

    var artworkTopInset: CGFloat {
        referenceArtworkTopInset * verticalCompressionScale
    }

    var metadataTopInset: CGFloat {
        referenceMetadataTopInset * verticalCompressionScale
    }

    var lyricsFocusAnchorOffset: CGFloat {
        artworkTopInset + artworkSize * 0.5 - Self.lyricsTopPadding
    }
}

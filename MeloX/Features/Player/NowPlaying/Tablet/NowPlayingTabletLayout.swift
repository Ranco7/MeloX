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
    /// Replaced by the control band's intrinsic height during SwiftUI layout.
    /// Includes metadata, every inter-row gap, the volume row and bottom inset.
    var controlsHeight: CGFloat? = nil

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

    var playerContainerWidth: CGFloat {
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
        // columns in portrait and resizable iPad windows. A transient
        // zero-width geometry pass during Stage Manager resizing must not
        // produce a negative frame.
        return max(
            min(
                scaledPlayerWidth,
                viewport.width * Self.splitViewWidthRatio
                    - Self.splitViewHorizontalInset
            ),
            1
        )
    }

    var playerLeading: CGFloat {
        viewport.width * 0.25 - playerContainerWidth * 0.5
    }

    var centeredPlayerLeading: CGFloat {
        (viewport.width - playerContainerWidth) * 0.5
    }

    var panelLeading: CGFloat {
        viewport.width * 0.5
    }

    var panelWidth: CGFloat {
        max(
            viewport.width * 0.5
                - max(24, viewport.width * 0.045),
            1
        )
    }

    var progressTopInset: CGFloat { 24 * elementScale }
    var transportTopInset: CGFloat { 24 * elementScale }
    static let volumeTopInset: CGFloat = 12
    static let playerBottomInset: CGFloat = 20

    /// Initial budget only. The view measures the complete band, including
    /// Dynamic Type and optional badges, before placing either subview.
    var estimatedControlsHeight: CGFloat {
        metadataTopInset + 64 + progressTopInset + 78
            + transportTopInset + 52 + Self.volumeTopInset + 44
            + Self.playerBottomInset
    }

    var resolvedControlsHeight: CGFloat {
        max(controlsHeight ?? estimatedControlsHeight, 0)
    }

    var playerWidth: CGFloat {
        max(min(playerContainerWidth, contentHeight - artworkTopInset - resolvedControlsHeight), 1)
    }

    func fitting(controlsHeight: CGFloat) -> Self {
        var result = self
        result.controlsHeight = controlsHeight
        return result
    }

    var artworkSize: CGFloat {
        playerWidth
    }

    var artworkTopInset: CGFloat {
        16
    }

    var metadataTopInset: CGFloat {
        24
    }

    var playerStackHeight: CGFloat {
        artworkTopInset + artworkSize + resolvedControlsHeight
    }

    /// Share surplus height between all five group boundaries, rather than
    /// leaving one empty band above the bottom toolbar.
    var extraVerticalSpace: CGFloat {
        max(contentHeight - playerStackHeight, 0)
    }

    var distributedGap: CGFloat { extraVerticalSpace / 5 }

    var renderedStackHeight: CGFloat { playerStackHeight + extraVerticalSpace }

    var lyricsFocusAnchorOffset: CGFloat {
        artworkTopInset + artworkSize * 0.5 - Self.lyricsTopPadding
    }
}

import CoreGraphics

/// Input is the safe-area-adjusted viewport from the card host. Only artwork
/// yields height; metadata and controls always use the independent column width.
struct NowPlayingTabletLayout {
    let viewport: CGSize
    var fillsRegion = false
    var showsSidePanel = false
    var controlsHeight: CGFloat? = nil

    static let chromeHeight: CGFloat = 48
    static let lyricsTopPadding: CGFloat = 40
    static let bottomBarHeight: CGFloat = 64
    static let volumeTopInset: CGFloat = 4
    static let playerBottomInset: CGFloat = 8
    static let minimumArtworkSide: CGFloat = 64

    var contentHeight: CGFloat {
        max(viewport.height - (fillsRegion ? 0 : Self.chromeHeight + Self.bottomBarHeight), 0)
    }

    private var regionWidth: CGFloat {
        max(viewport.width * (showsSidePanel ? 0.5 : 1), 0)
    }

    var playerContainerWidth: CGFloat {
        let margin = min(max(regionWidth * 0.11, 24), 80)
        return max(min(regionWidth - 2 * margin, 640), 1)
    }

    /// Five 44pt targets form the minimum transport row. A physically narrower
    /// pane scrolls horizontally instead of clipping or shrinking those targets.
    var playerWidth: CGFloat { max(playerContainerWidth, 220) }
    var playerLeading: CGFloat { viewport.width * 0.25 - playerContainerWidth * 0.5 }
    var centeredPlayerLeading: CGFloat { (viewport.width - playerContainerWidth) * 0.5 }
    var panelLeading: CGFloat { viewport.width * 0.5 }
    var panelWidth: CGFloat { max(viewport.width * 0.5 - 24, 1) }

    var artworkTopInset: CGFloat { 16 }
    var metadataTopInset: CGFloat { 16 }
    var progressTopInset: CGFloat { 8 }
    var transportTopInset: CGFloat { 4 }
    var transportHeight: CGFloat {
        44 + 20 * min(max((contentHeight - 400) / 200, 0), 1)
    }
    var estimatedControlsHeight: CGFloat {
        metadataTopInset + 64 + progressTopInset + 78
            + transportTopInset + transportHeight + Self.volumeTopInset + 44 + Self.playerBottomInset
    }
    var resolvedControlsHeight: CGFloat { max(controlsHeight ?? estimatedControlsHeight, 0) }

    var artworkSize: CGFloat {
        // If controls alone cannot fit, keep a recognisable cover and scroll
        // the native-height stack, rather than collapsing it to a 1pt speck.
        min(playerWidth, max(Self.minimumArtworkSide, contentHeight - artworkTopInset - resolvedControlsHeight))
    }

    func fitting(controlsHeight: CGFloat) -> Self {
        var result = self
        result.controlsHeight = controlsHeight
        return result
    }

    var playerStackHeight: CGFloat { artworkTopInset + artworkSize + resolvedControlsHeight }
    var extraVerticalSpace: CGFloat { max(contentHeight - playerStackHeight, 0) }
    var distributedGap: CGFloat { extraVerticalSpace / 5 }
    var renderedStackHeight: CGFloat { playerStackHeight + extraVerticalSpace }
    var needsScroll: Bool { playerStackHeight > contentHeight + 0.5 }
    var lyricsFocusAnchorOffset: CGFloat {
        artworkTopInset + artworkSize * 0.5 - Self.lyricsTopPadding
    }
}

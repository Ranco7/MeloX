import CoreGraphics

/// Deterministic geometry for the portrait Now Playing screen.
///
/// The content column and the control band are stacked vertically instead of
/// overlapping. Artwork sizing uses a conservative metadata budget; the page
/// always sits in a size-based scroll view so real two-line titles, badges and
/// Dynamic Type never get clipped by that estimate.
struct NowPlayingPortraitLayout {
    static let minimumHorizontalMargin: CGFloat = 16
    static let maximumHorizontalMargin: CGFloat = 32
    static let minimumArtworkSide: CGFloat = 96
    static let minimumTouchTarget: CGFloat = 44

    /// Progress slider plus the time/quality row. The quality capsule and the
    /// time labels share one 44pt touch-height row, so the section is the
    /// slider, the row gap and that row.
    static let baseProgressHeight: CGFloat = 78
    static let baseProgressTransportGap: CGFloat = 19
    static let baseTransportHeight: CGFloat = 82
    static let baseTransportVolumeGap: CGFloat = 31
    static let baseVolumeHeight: CGFloat = minimumTouchTarget
    static let baseVolumeSelectorGap: CGFloat = 3
    static let basePageSelectorHeight: CGFloat = 50
    static let baseUtilityHeight: CGFloat = 62

    private static let baseProgressBlock =
        baseProgressHeight + baseProgressTransportGap
    private static let baseTransportBlock =
        baseTransportHeight + baseTransportVolumeGap
    private static let baseVolumeBlock =
        baseVolumeHeight + baseVolumeSelectorGap
    static let baseCoreHeight =
        baseProgressBlock
        + baseTransportBlock
        + baseVolumeBlock
        + basePageSelectorHeight
    static let baseOverlayHeight = baseUtilityHeight + baseCoreHeight

    private static let baseArtworkTopSpacing: CGFloat = 16
    private static let baseArtworkBottomSpacing: CGFloat = 22
    /// Conservative budget used only for artwork sizing — never for deciding
    /// whether text remains reachable (the page always size-based-scrolls).
    private static let baseMetadataHeight: CGFloat = 110
    private static let minimumGapCompression: CGFloat = 0.4

    /// Collapse handle reserves a full 44pt hit target even though the capsule
    /// itself stays visually thin.
    static let dismissalHandleHeight: CGFloat = minimumTouchTarget
    static let bottomSafeAreaPadding: CGFloat = 3

    let viewport: CGSize
    var textScale: CGFloat = 1
    var showsUtilityRow = false
    var showsArtworkPage = true

    private var clampedTextScale: CGFloat {
        min(max(textScale, 1), 1.35)
    }

    private func scaled(_ value: CGFloat) -> CGFloat {
        (value * clampedTextScale).rounded(.up)
    }

    var horizontalMargin: CGFloat {
        min(
            max(
                viewport.width * 0.055,
                Self.minimumHorizontalMargin
            ),
            Self.maximumHorizontalMargin
        )
    }

    var contentWidth: CGFloat {
        max(viewport.width - horizontalMargin * 2, 1)
    }

    /// Shrinks whitespace gaps on short windows so the transport band and a
    /// minimum artwork still share the viewport before whole-player scrolling.
    /// Computed only from base constants so it cannot recurse through the
    /// compressed gap properties.
    var gapCompression: CGFloat {
        let fixedBand =
            scaled(Self.baseProgressHeight)
            + scaled(Self.baseTransportHeight)
            + scaled(Self.baseVolumeHeight)
            + scaled(Self.basePageSelectorHeight)
            + (showsUtilityRow ? scaled(Self.baseUtilityHeight) : 0)
        let fullGaps =
            scaled(Self.baseProgressTransportGap)
            + scaled(Self.baseTransportVolumeGap)
            + scaled(Self.baseVolumeSelectorGap)
        let minimumPage =
            scaled(Self.baseArtworkTopSpacing)
            + Self.minimumArtworkSide
            + scaled(Self.baseArtworkBottomSpacing)
            + scaled(Self.baseMetadataHeight)
        let reserved =
            Self.dismissalHandleHeight
            + Self.bottomSafeAreaPadding
            + fixedBand
            + minimumPage
        let leftover = viewport.height - reserved
        if fullGaps <= 0.5 {
            return 1
        }
        if leftover >= fullGaps {
            return 1
        }
        if leftover <= 0 {
            return Self.minimumGapCompression
        }
        return max(Self.minimumGapCompression, leftover / fullGaps)
    }

    var progressHeight: CGFloat {
        scaled(Self.baseProgressHeight)
    }

    var progressTransportGap: CGFloat {
        (scaled(Self.baseProgressTransportGap) * gapCompression)
            .rounded(.up)
    }

    var transportHeight: CGFloat {
        scaled(Self.baseTransportHeight)
    }

    var transportVolumeGap: CGFloat {
        (scaled(Self.baseTransportVolumeGap) * gapCompression)
            .rounded(.up)
    }

    var volumeHeight: CGFloat {
        scaled(Self.baseVolumeHeight)
    }

    var volumeSelectorGap: CGFloat {
        (scaled(Self.baseVolumeSelectorGap) * gapCompression)
            .rounded(.up)
    }

    var pageSelectorHeight: CGFloat {
        scaled(Self.basePageSelectorHeight)
    }

    var utilityHeight: CGFloat {
        scaled(Self.baseUtilityHeight)
    }

    var controlsHeight: CGFloat {
        let progressBlock = progressHeight + progressTransportGap
        let transportBlock = transportHeight + transportVolumeGap
        let volumeBlock = volumeHeight + volumeSelectorGap
        return progressBlock + transportBlock + volumeBlock + pageSelectorHeight
    }

    var overlayHeight: CGFloat {
        (showsUtilityRow ? utilityHeight : 0) + controlsHeight
    }

    var artworkTopSpacing: CGFloat {
        scaled(Self.baseArtworkTopSpacing)
    }

    var artworkBottomSpacing: CGFloat {
        scaled(Self.baseArtworkBottomSpacing)
    }

    var metadataEstimatedHeight: CGFloat {
        scaled(Self.baseMetadataHeight)
    }

    /// Natural height of the artwork page using the conservative metadata
    /// budget. Real rendered metadata may be taller; the page scroll view
    /// absorbs that without clipping.
    var naturalContentHeight: CGFloat {
        artworkTopSpacing
            + artworkSide
            + artworkBottomSpacing
            + metadataEstimatedHeight
    }

    /// Smallest page column worth showing: floor artwork, its gaps and the
    /// metadata budget. Independent of the current band height, so it never
    /// feeds back into `artworkSide`.
    var minimumPageAreaHeight: CGFloat {
        artworkTopSpacing
            + Self.minimumArtworkSide
            + artworkBottomSpacing
            + metadataEstimatedHeight
    }

    /// Space above the control band if the pages were allowed to shrink.
    var pageContentHeight: CGFloat {
        max(
            viewport.height
                - Self.dismissalHandleHeight
                - Self.bottomSafeAreaPadding
                - overlayHeight,
            1
        )
    }

    var artworkSide: CGFloat {
        // The playing cover and controls share one column at every width.
        // Short windows scroll instead of narrowing only the artwork.
        contentWidth
    }

    /// Height given to the page column inside the portrait stack. Matches the
    /// space above the control band when everything fits; grows to the page
    /// floor when the whole player must scroll so nothing is clipped.
    var pageAreaHeight: CGFloat {
        max(pageContentHeight, showsArtworkPage ? naturalContentHeight : minimumPageAreaHeight)
    }

    /// True when the conservative natural page content exceeds the band left
    /// above the controls. Informational for artwork budgeting; the artwork
    /// page always uses a size-based ScrollView either way.
    var usesScrollFallback: Bool {
        naturalContentHeight > pageContentHeight + 0.5
    }

    /// Extremely short windows (or large Dynamic Type) where even a compressed
    /// control band plus the page floor cannot share the viewport. The whole
    /// portrait stack then scrolls so every control stays reachable.
    var needsWholePlayerScroll: Bool {
        pageContentHeight < (showsArtworkPage ? naturalContentHeight : minimumPageAreaHeight) - 0.5
    }

    /// Total height of the portrait stack. Equal to the visible height
    /// whenever no whole-player scrolling is needed.
    var portraitStackHeight: CGFloat {
        Self.dismissalHandleHeight
            + Self.bottomSafeAreaPadding
            + pageAreaHeight
            + overlayHeight
    }
}

/// Equal-width side-by-side columns for compact landscape windows. The right
/// column can scroll independently when its native controls need more height.
struct NowPlayingLandscapeLayout {
    let viewport: CGSize
    var spacing: CGFloat { min(max(viewport.width * 0.035, 32), 38) }
    var columnWidth: CGFloat {
        max(1, min(viewport.height, (min(viewport.width, 1_100) - spacing) * 0.5, 460))
    }
    var controlsHeight: CGFloat { max(viewport.height, 360) }
}

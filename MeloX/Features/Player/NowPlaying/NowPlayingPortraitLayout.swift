import CoreGraphics

/// Places the collapse handle on the exact horizontal center. Side content is
/// only allowed on the same row when it stays outside the centered handle's
/// touch region.
struct NowPlayingPortraitHeaderMetrics {
    static let handleWidth: CGFloat = 60
    static let spacing: CGFloat = 8
    static let handleHeight: CGFloat = 44

    struct Frames {
        let badges: CGRect
        let handle: CGRect
        let quality: CGRect
        var height: CGFloat { max(badges.maxY, handle.maxY, quality.maxY) }
    }

    static func frames(width: CGFloat, badges: CGSize, quality: CGSize) -> Frames {
        let centerX = (width - handleWidth) / 2
        let sideLimit = max(centerX - spacing, 0)
        if badges.width <= sideLimit && quality.width <= sideLimit {
            let height = max(handleHeight, badges.height, quality.height)
            return Frames(
                badges: CGRect(x: 0, y: (height - badges.height) / 2, width: badges.width, height: badges.height),
                handle: CGRect(x: centerX, y: (height - handleHeight) / 2, width: handleWidth, height: handleHeight),
                quality: CGRect(x: width - quality.width, y: (height - quality.height) / 2, width: quality.width, height: quality.height)
            )
        }
        let sharesRow = badges.width + spacing + quality.width <= width
        let rowHeight = max(badges.height, quality.height)
        return Frames(
            badges: CGRect(x: 0, y: handleHeight + (sharesRow ? (rowHeight - badges.height) / 2 : 0), width: badges.width, height: badges.height),
            handle: CGRect(x: centerX, y: 0, width: handleWidth, height: handleHeight),
            quality: CGRect(x: width - quality.width, y: handleHeight + (sharesRow ? (rowHeight - quality.height) / 2 : badges.height), width: quality.width, height: quality.height)
        )
    }
}

/// Deterministic geometry for the portrait Now Playing screen.
///
/// The content column and the control band are stacked vertically instead of
/// overlapping. Short windows reserve the full-width controls and metadata
/// first, then shrink only the centered artwork to the remaining height.
struct NowPlayingPortraitLayout {
    static let minimumHorizontalMargin: CGFloat = 16
    static let maximumHorizontalMargin: CGFloat = 32
    static let minimumArtworkSide: CGFloat = 64
    static let minimumTouchTarget: CGFloat = 44

    /// A 44pt slider and passive time labels. Quality and active badges share
    /// the top chrome, so they never consume another full-height control row.
    static let baseProgressHeight: CGFloat = 52
    static let baseProgressTransportGap: CGFloat = 24
    static let baseTransportHeight: CGFloat = 80
    static let baseTransportVolumeGap: CGFloat = 24
    static let baseVolumeHeight: CGFloat = minimumTouchTarget
    static let baseVolumeSelectorGap: CGFloat = 8
    static let basePageSelectorHeight: CGFloat = 44
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

    /// First-pass budget; the artwork page reports its actual metadata height.
    /// Text and controls retain their full content width as artwork shrinks.
    private static let baseMetadataHeight: CGFloat = 52

    /// Collapse handle reserves a full 44pt hit target even though the capsule
    /// itself stays visually thin.
    static let dismissalHandleHeight: CGFloat = minimumTouchTarget
    static let bottomSafeAreaPadding: CGFloat = 4

    let viewport: CGSize
    var textScale: CGFloat = 1
    var showsUtilityRow = false
    var showsArtworkPage = true
    var measuredMetadataHeight: CGFloat? = nil
    var measuredProgressHeight: CGFloat? = nil
    var measuredHeaderHeight: CGFloat? = nil

    var headerHeight: CGFloat { max(measuredHeaderHeight ?? Self.dismissalHandleHeight, Self.minimumTouchTarget) }

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

    /// Continuous interpolation between compact and generous 4/8pt endpoints.
    /// Resizing through 700pt does not switch layouts or move the cover abruptly.
    private var spacingProgress: CGFloat {
        min(max((viewport.height - 480) / 420, 0), 1)
    }

    private var baseTopGap: CGFloat { 4 + 12 * spacingProgress }
    private var baseArtworkGap: CGFloat { 12 + 12 * spacingProgress }
    private var baseMetadataGap: CGFloat { 4 + 20 * spacingProgress }
    private var baseControlGap: CGFloat { 4 + 20 * spacingProgress }
    private var baseToolbarGap: CGFloat { 4 + 4 * spacingProgress }

    /// Once the square reaches its width limit, distribute excess height
    /// across the groups instead of leaving one empty band above the artwork.
    private var extraGapUnit: CGFloat {
        let rows = headerHeight + Self.bottomSafeAreaPadding
            + metadataEstimatedHeight + progressHeight + transportHeight
            + volumeHeight + pageSelectorHeight
            + (showsUtilityRow ? utilityHeight : 0)
        let gaps = baseTopGap + baseArtworkGap + baseMetadataGap + 2 * baseControlGap + baseToolbarGap
        return max(viewport.height - rows - gaps - contentWidth, 0) / 9
    }

    var progressHeight: CGFloat {
        max(scaled(Self.baseProgressHeight), measuredProgressHeight ?? 0)
    }

    var progressTransportGap: CGFloat {
        baseControlGap + 2 * extraGapUnit
    }

    var transportHeight: CGFloat {
        44 + 36 * spacingProgress
    }

    static func skipSymbolSize(controlDiameter: CGFloat) -> CGFloat {
        min(34, (controlDiameter - 4) / 1.4)
    }

    static func playSymbolSize(
        controlDiameter: CGFloat,
        isTablet: Bool
    ) -> CGFloat {
        min(isTablet ? 40 : 44, max(30, controlDiameter - 4))
    }

    var transportVolumeGap: CGFloat {
        baseControlGap + 2 * extraGapUnit
    }

    var volumeHeight: CGFloat {
        Self.minimumTouchTarget
    }

    var volumeSelectorGap: CGFloat {
        baseToolbarGap + extraGapUnit
    }

    var pageSelectorHeight: CGFloat {
        Self.basePageSelectorHeight
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
        baseTopGap + extraGapUnit
    }

    var artworkBottomSpacing: CGFloat {
        baseArtworkGap + 2 * extraGapUnit
    }

    var metadataBottomSpacing: CGFloat {
        baseMetadataGap + extraGapUnit
    }

    var metadataEstimatedHeight: CGFloat {
        max(measuredMetadataHeight ?? scaled(Self.baseMetadataHeight), 1)
    }

    /// Includes every gap and the current measured metadata height. The initial
    /// budget is replaced without narrowing the title or controls.
    var naturalContentHeight: CGFloat {
        artworkTopSpacing
            + artworkSide
            + artworkBottomSpacing
            + metadataEstimatedHeight
            + metadataBottomSpacing
    }

    /// Smallest page column worth showing: floor artwork, its gaps and the
    /// metadata budget. Independent of the current band height, so it never
    /// feeds back into `artworkSide`.
    var minimumPageAreaHeight: CGFloat {
        artworkTopSpacing
            + Self.minimumArtworkSide
            + artworkBottomSpacing
            + metadataEstimatedHeight
            + metadataBottomSpacing
    }

    /// Space above the control band if the pages were allowed to shrink.
    var pageContentHeight: CGFloat {
        max(
            viewport.height
                - headerHeight
                - Self.bottomSafeAreaPadding
                - overlayHeight,
            1
        )
    }

    var artworkSide: CGFloat {
        // Reserve every control, toolbar and metadata row before allocating
        // the square. Controls and text retain the full content width.
        max(
            min(
                contentWidth,
                pageContentHeight - artworkTopSpacing
                    - artworkBottomSpacing - metadataEstimatedHeight
                    - metadataBottomSpacing
            ),
            min(Self.minimumArtworkSide, contentWidth)
        )
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
        headerHeight
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

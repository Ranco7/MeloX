import SwiftUI

struct MediaCardGridLayout {
    let columns: [GridItem]
    let itemWidth: CGFloat

    init(
        containerWidth: CGFloat,
        horizontalPadding: CGFloat = 16,
        minimumItemWidth: CGFloat = 145,
        spacing: CGFloat = 16
    ) {
        let availableWidth = max(
            containerWidth - horizontalPadding * 2,
            1
        )
        let columnCount = max(
            Int(
                (availableWidth + spacing)
                    / (minimumItemWidth + spacing)
            ),
            1
        )
        let totalSpacing = spacing * CGFloat(columnCount - 1)
        itemWidth = (availableWidth - totalSpacing) / CGFloat(columnCount)
        columns = Array(
            repeating: GridItem(
                .fixed(itemWidth),
                spacing: spacing,
                alignment: .top
            ),
            count: columnCount
        )
    }
}

enum MusicCollectionLayout {
    // Every column on the playlist/album page is derived from `wideInset`,
    // the leading edge of the hero artwork. Row thumbnails share that edge;
    // song separators start at the title column beyond the leading content.
    // Proportions follow Apple Music on iPad (2026-11 reference): thumbnails
    // align with the hero artwork, the favourite mark hangs in the margin,
    // the artist column starts at the middle of the row and rows are 56pt.
    static let compactInset: CGFloat = 20
    static let wideInset: CGFloat = 32
    static let rowArtworkSize: CGFloat = 48
    static let wideRowArtworkSize: CGFloat = 48
    static let wideRowHeight: CGFloat = 56
    static let columnSpacing: CGFloat = 12
    static let wideArtworkTitleSpacing: CGFloat = 11
    static let favoriteColumnWidth: CGFloat = 12
    static let favoriteArtworkSpacing: CGFloat = 4
    static let indexColumnWidth: CGFloat = 40
    static let durationColumnWidth: CGFloat = 54
    static let downloadStatusColumnWidth: CGFloat = 18
    static let accessorySpacing: CGFloat = 4
    static let controlMinimumSize: CGFloat = 44
    /// The ⋯ glyph is ~20pt wide inside its 44pt hit area. Letting the hit
    /// area overhang the row edge puts the glyph on the separator's end.
    static let moreButtonOverhang: CGFloat = 12
    static let miniPlayerMaximumWidth: CGFloat = 690
    static let miniPlayerClearance: CGFloat = 88
    static let miniPlayerInset: CGFloat = 14
    /// Distance from the bottom of the screen to the floating mini player.
    static let miniPlayerScreenBottomInset: CGFloat = 20
    static let heroColumnSpacing: CGFloat = 34
    static let heroTopInset: CGFloat = 28
    static let heroBottomInset: CGFloat = 40

    static func horizontalInset(wide: Bool) -> CGFloat {
        wide ? wideInset : compactInset
    }

    /// Leading padding of a wide row. When the favourite mark is shown it
    /// sits in the margin so the thumbnail starts exactly at `wideInset`.
    static func wideRowLeadingPadding(showsFavorite: Bool) -> CGFloat {
        showsFavorite ? wideInset - favoriteColumnWidth - favoriteArtworkSpacing : wideInset
    }

    static var wideRowTrailingPadding: CGFloat { wideInset - moreButtonOverhang }

    /// Width taken on the right of the row content box by download status,
    /// duration and the ⋯ button, including the gaps between them.
    static var wideTrailingAccessoryWidth: CGFloat {
        downloadStatusColumnWidth + accessorySpacing
            + durationColumnWidth + accessorySpacing
            + (controlMinimumSize - moreButtonOverhang) + accessorySpacing
    }

    // Hero action row (shuffle, play, download) on wide layouts.
    static let heroControlSize: CGFloat = 48
    static let heroPlayButtonWidth: CGFloat = 160
    static let heroControlSpacing: CGFloat = 14
    static let minimumArtistColumnWidth: CGFloat = 96

    /// Distance from the content's leading edge to the right edge of the hero
    /// play button: artwork, column gap, shuffle button, gap, play button.
    static func heroPlayButtonTrailingEdge(artworkSize: CGFloat) -> CGFloat {
        artworkSize + heroColumnSpacing
            + heroControlSize + heroControlSpacing + heroPlayButtonWidth
    }

    /// The artist column starts on the same vertical line as the right edge
    /// of the hero play button, like Apple Music. Both come from the
    /// constants above, so they stay aligned at every window width.
    static func wideArtistColumnWidth(rowWidth: CGFloat, artworkSize: CGFloat) -> CGFloat {
        max(
            minimumArtistColumnWidth,
            rowWidth - heroPlayButtonTrailingEdge(artworkSize: artworkSize) - wideTrailingAccessoryWidth
        )
    }

    static func titleLeadingInset(wide: Bool, artwork: Bool, selecting: Bool) -> CGFloat {
        let leadingWidth = artwork
            ? (wide ? wideRowArtworkSize : rowArtworkSize) : indexColumnWidth
        let titleSpacing = wide && artwork && !selecting
            ? wideArtworkTitleSpacing : columnSpacing
        return horizontalInset(wide: wide)
            + (selecting ? 24 + columnSpacing : 0)
            + leadingWidth + titleSpacing
    }
    static let wideLayoutBreakpoint = CGFloat(MusicCollectionWidthPolicy.wideLayoutBreakpoint)
    static let heroArtworkRatio: CGFloat = 0.28
    static let maximumHeroArtworkSize: CGFloat = 300

    static func wideWidth(_ width: CGFloat, isTablet: Bool = true, isAccessibilitySize: Bool = false) -> CGFloat? {
        MusicCollectionWidthPolicy.wideWidth(Double(width), isTablet: isTablet, isAccessibilitySize: isAccessibilitySize).map { CGFloat($0) }
    }

}

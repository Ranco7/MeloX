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
    // Provisional HIG-oriented metrics, NOT measured from Apple Music screenshots.
    // Keep tunable playlist/album metrics together until reference images arrive.
    static let compactInset: CGFloat = 20
    static let wideInset: CGFloat = 32
    static let rowArtworkSize: CGFloat = 48
    static let columnSpacing: CGFloat = 12
    static let favoriteColumnWidth: CGFloat = 12
    static let indexColumnWidth: CGFloat = 40
    static let durationColumnWidth: CGFloat = 54
    static let controlMinimumSize: CGFloat = 44
    static let miniPlayerMaximumWidth: CGFloat = 690
    static let miniPlayerClearance: CGFloat = 76
    static let miniPlayerInset: CGFloat = 14
    static let miniPlayerBottomInset: CGFloat = 8
    static let heroColumnSpacing: CGFloat = 34
    static let heroTopInset: CGFloat = 28
    static let heroBottomInset: CGFloat = 36

    static func horizontalInset(wide: Bool) -> CGFloat {
        wide ? wideInset : compactInset
    }

    static func titleLeadingInset(wide: Bool, artwork: Bool, selecting: Bool) -> CGFloat {
        horizontalInset(wide: wide)
            + (selecting ? 24 + columnSpacing : 0)
            + (wide && artwork && !selecting ? favoriteColumnWidth + columnSpacing : 0)
            + (artwork ? rowArtworkSize : indexColumnWidth) + columnSpacing
    }
    static let wideLayoutBreakpoint: CGFloat = 710
    static let heroArtworkRatio: CGFloat = 0.28
    static let maximumHeroArtworkSize: CGFloat = 300
    static let trackArtistColumnRatio: CGFloat = 0.24
    static let maximumTrackArtistColumnWidth: CGFloat = 220
}

/// A scroll-view row has no native List cell to supply pressed feedback.
/// ButtonStyle tracks the real press lifecycle (including scroll cancellation)
/// instead of adding a competing drag/tap recognizer.
struct MusicTrackPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.primary.opacity(0.12) : Color.clear)
    }
}

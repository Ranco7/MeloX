import CoreGraphics

/// The production layout enum is extracted by test_song_row_alignment.py.
/// Compare its separator inset with the actual row's leading-content sequence.
@main
struct MusicCollectionRowAlignmentChecks {
    static func main() {
        let cases: [(Bool, Bool, Bool, CGFloat)] = [
            (false, true, false, 80), (false, false, false, 72),
            (false, true, true, 116), (false, false, true, 108),
            (true, true, false, 91), (true, false, false, 84),
            (true, true, true, 128), (true, false, true, 120)
        ]
        for (wide, artwork, selecting, expected) in cases {
            let hasFavoriteColumn = wide && artwork && !selecting
            var title = wide
                ? MusicCollectionLayout.wideRowLeadingPadding(showsFavorite: hasFavoriteColumn)
                : MusicCollectionLayout.compactInset
            if selecting { title += 24 + MusicCollectionLayout.columnSpacing }
            if hasFavoriteColumn {
                title += MusicCollectionLayout.favoriteColumnWidth + MusicCollectionLayout.favoriteArtworkSpacing
            }
            title += artwork
                ? (wide ? MusicCollectionLayout.wideRowArtworkSize : MusicCollectionLayout.rowArtworkSize)
                : MusicCollectionLayout.indexColumnWidth
            // The row uses a 12pt HStack gap, with a -1pt trailing correction
            // only on the normal wide artwork/favorite group.
            title += MusicCollectionLayout.columnSpacing
            if hasFavoriteColumn {
                title += MusicCollectionLayout.wideArtworkTitleSpacing - MusicCollectionLayout.columnSpacing
            }
            let separator = MusicCollectionLayout.titleLeadingInset(wide: wide, artwork: artwork, selecting: selecting)
            precondition(abs(separator - title) < 0.000_001, "Separator missed the actual title axis")
            precondition(separator == expected, "Known row-mode regression")
        }
        precondition(MusicCollectionLayout.wideRowHeight == 56)
        precondition(MusicCollectionLayout.rowArtworkSize == 48)
        precondition(MusicCollectionLayout.wideRowArtworkSize == 48)
        print("Song row alignment passed: all 8 wide/compact, artwork/index and selection modes; existing sizes retained")
    }
}

import CoreGraphics
import Foundation

@main
struct NowPlayingPortraitLayoutChecks {
    private struct Case {
        let name: String
        let size: CGSize
        let route: String
    }

    static func main() {
        runPortraitMatrix()
        runDynamicType()
        runUtilityAndMargins()
        runArtworkMonotonic()
        runTouchTargets()
        runWholePlayerScroll()
        runTabletMatrix()
        print("Now Playing adaptive layout checks passed")
    }

    private static func runPortraitMatrix() {
        let cases = [
            Case(name: "320x480", size: CGSize(width: 320, height: 480), route: "portrait"),
            Case(name: "375x667", size: CGSize(width: 375, height: 667), route: "portrait"),
            Case(name: "430x700", size: CGSize(width: 430, height: 700), route: "portrait"),
            Case(name: "500x400", size: CGSize(width: 500, height: 400), route: "portrait"),
            Case(name: "700x900", size: CGSize(width: 700, height: 900), route: "portrait"),
            Case(name: "1024x768", size: CGSize(width: 1_024, height: 768), route: "portrait"),
            Case(name: "1366x1024", size: CGSize(width: 1_366, height: 1_024), route: "portrait"),
            Case(name: "1180x820", size: CGSize(width: 1_180, height: 820), route: "portrait"),
        ]

        var firstFallbackCase: String?
        for testCase in cases {
            let layout = NowPlayingPortraitLayout(viewport: testCase.size)

            check(
                layout.horizontalMargin
                    >= NowPlayingPortraitLayout.minimumHorizontalMargin,
                "\(testCase.name): margin below minimum"
            )
            check(
                layout.horizontalMargin
                    <= NowPlayingPortraitLayout.maximumHorizontalMargin,
                "\(testCase.name): margin above maximum"
            )
            check(
                layout.contentWidth >= 1,
                "\(testCase.name): non-positive content width"
            )
            check(
                layout.artworkSide
                    >= NowPlayingPortraitLayout.minimumArtworkSide,
                "\(testCase.name): artwork below minimum"
            )
            check(
                layout.artworkSide
                    <= min(
                        NowPlayingPortraitLayout.maximumArtworkSide,
                        layout.contentWidth
                    ) + 0.001,
                "\(testCase.name): artwork wider than content or cap"
            )

            let progressBlock =
                layout.progressHeight + layout.progressTransportGap
            let transportBlock =
                layout.transportHeight + layout.transportVolumeGap
            let volumeBlock =
                layout.volumeHeight + layout.volumeSelectorGap
            check(
                layout.controlsHeight
                    == progressBlock + transportBlock + volumeBlock
                        + layout.pageSelectorHeight,
                "\(testCase.name): control band does not match its parts"
            )
            check(
                layout.overlayHeight >= layout.controlsHeight,
                "\(testCase.name): overlay shorter than core controls"
            )
            check(
                layout.pageContentHeight >= 1,
                "\(testCase.name): page content height is not positive"
            )
            check(
                layout.pageAreaHeight
                    >= layout.pageContentHeight - 0.001,
                "\(testCase.name): page area shorter than content band"
            )
            check(
                layout.pageAreaHeight
                    >= layout.minimumPageAreaHeight - 0.001,
                "\(testCase.name): page area shorter than the page floor"
            )
            // When artwork is not width/cap limited, natural content fills the
            // page band. The 420pt cap on tall windows is allowed to leave
            // unused vertical space above the metadata.
            if layout.artworkSide + 0.001
                < NowPlayingPortraitLayout.maximumArtworkSide
                && layout.artworkSide + 0.001 < layout.contentWidth
            {
                check(
                    abs(
                        layout.naturalContentHeight
                            - layout.pageAreaHeight
                    ) < 1.5,
                    "\(testCase.name): unconstrained artwork should fill the page band"
                )
            }
            check(
                layout.naturalContentHeight
                    + layout.overlayHeight
                    + NowPlayingPortraitLayout.dismissalHandleHeight
                    + NowPlayingPortraitLayout.bottomSafeAreaPadding
                    <= layout.viewport.height + 0.5
                    || layout.usesScrollFallback
                    || layout.needsWholePlayerScroll,
                "\(testCase.name): content collides with the control band"
            )
            check(
                layout.usesScrollFallback
                    == (layout.naturalContentHeight
                        > layout.pageContentHeight + 0.5),
                "\(testCase.name): scroll fallback invariant broken"
            )
            check(
                layout.gapCompression >= 0.4 - 0.001
                    && layout.gapCompression <= 1 + 0.001,
                "\(testCase.name): gap compression out of range"
            )

            if layout.usesScrollFallback {
                firstFallbackCase = firstFallbackCase ?? testCase.name
            }

            for value in [
                layout.horizontalMargin,
                layout.contentWidth,
                layout.artworkSide,
                layout.controlsHeight,
                layout.overlayHeight,
                layout.pageContentHeight,
                layout.pageAreaHeight,
                layout.naturalContentHeight,
                layout.gapCompression,
            ] {
                check(value >= 0, "\(testCase.name): negative geometry")
            }

            // Route note: these cases exercise the portrait model only.
            check(
                testCase.route == "portrait",
                "\(testCase.name): unexpected route tag"
            )
        }

        check(
            firstFallbackCase == "320x480",
            "Expected 320x480 to use the scroll fallback, got \(firstFallbackCase ?? "none")"
        )
    }

    private static func runDynamicType() {
        let base = NowPlayingPortraitLayout(
            viewport: CGSize(width: 430, height: 700)
        )
        let large = NowPlayingPortraitLayout(
            viewport: CGSize(width: 430, height: 700),
            textScale: 1.24
        )
        let accessibility = NowPlayingPortraitLayout(
            viewport: CGSize(width: 430, height: 700),
            textScale: 3
        )
        let clamped = NowPlayingPortraitLayout(
            viewport: CGSize(width: 430, height: 700),
            textScale: 1.35
        )
        check(
            large.controlsHeight > base.controlsHeight,
            "Dynamic Type did not grow the band"
        )
        check(
            accessibility.controlsHeight == clamped.controlsHeight,
            "Dynamic Type multiplier is not clamped at 1.35"
        )
        check(
            large.artworkSide <= base.artworkSide,
            "Larger text should not enlarge the artwork"
        )
        check(
            NowPlayingPortraitLayout(
                viewport: CGSize(width: 430, height: 700),
                textScale: 0.5 as CGFloat
            ).controlsHeight == base.controlsHeight,
            "Text scale below 1 must not shrink controls"
        )
    }

    private static func runUtilityAndMargins() {
        let base = NowPlayingPortraitLayout(
            viewport: CGSize(width: 430, height: 700)
        )
        let withUtilities = NowPlayingPortraitLayout(
            viewport: CGSize(width: 430, height: 700),
            showsUtilityRow: true
        )
        check(
            withUtilities.overlayHeight
                == base.overlayHeight + withUtilities.utilityHeight,
            "Utility row height is not additive"
        )

        let narrow = NowPlayingPortraitLayout(
            viewport: CGSize(width: 280, height: 900)
        )
        let ramped = NowPlayingPortraitLayout(
            viewport: CGSize(width: 430, height: 700)
        )
        let wide = NowPlayingPortraitLayout(
            viewport: CGSize(width: 1_366, height: 400)
        )
        check(
            narrow.horizontalMargin
                == NowPlayingPortraitLayout.minimumHorizontalMargin,
            "Widths below the ramp should use the minimum margin"
        )
        check(
            ramped.horizontalMargin > narrow.horizontalMargin,
            "Margin should ramp with width"
        )
        check(
            wide.horizontalMargin
                == NowPlayingPortraitLayout.maximumHorizontalMargin,
            "Wide width should use the maximum margin"
        )
        check(
            NowPlayingPortraitLayout(
                viewport: CGSize(width: 700, height: 300)
            ).horizontalMargin
                == NowPlayingPortraitLayout(
                    viewport: CGSize(width: 700, height: 900)
                ).horizontalMargin,
            "Margin must not depend on height"
        )
    }

    private static func runArtworkMonotonic() {
        var previousSide: CGFloat = 0
        for height in stride(
            from: CGFloat(480),
            through: CGFloat(1_200),
            by: CGFloat(40)
        ) {
            let layout = NowPlayingPortraitLayout(
                viewport: CGSize(width: 430, height: height)
            )
            check(
                layout.artworkSide + 0.001 >= previousSide,
                "Artwork side decreased as height grew at \(height)"
            )
            previousSide = layout.artworkSide
        }
    }

    private static func runTouchTargets() {
        check(
            NowPlayingPortraitLayout.minimumTouchTarget >= 44,
            "minimumTouchTarget below HIG 44pt"
        )
        check(
            NowPlayingPortraitLayout.dismissalHandleHeight
                == NowPlayingPortraitLayout.minimumTouchTarget,
            "dismissal handle must reserve a 44pt hit target"
        )
    }

    private static func runWholePlayerScroll() {
        let shortLargeType = NowPlayingPortraitLayout(
            viewport: CGSize(width: 500, height: 360),
            textScale: 1.35,
            showsUtilityRow: true
        )
        check(
            shortLargeType.needsWholePlayerScroll
                || shortLargeType.usesScrollFallback,
            "Short window + large type must scroll somewhere"
        )
        check(
            shortLargeType.pageAreaHeight
                >= shortLargeType.naturalContentHeight - 0.001,
            "Whole-player scroll must still expose natural page content"
        )

        let comfortable = NowPlayingPortraitLayout(
            viewport: CGSize(width: 430, height: 700)
        )
        check(
            !comfortable.needsWholePlayerScroll,
            "430x700 should not need whole-player scroll at default type"
        )
    }

    /// Production tablet layout is a separate route from the portrait model.
    /// These checks prove column geometry only — they do not claim a rendered
    /// SwiftUI verification of the tablet chrome.
    private static func runTabletMatrix() {
        let cases: [(String, CGSize)] = [
            ("tablet-700x900", CGSize(width: 700, height: 900)),
            ("tablet-1024x768", CGSize(width: 1_024, height: 768)),
            ("tablet-1366x1024", CGSize(width: 1_366, height: 1_024)),
            ("tablet-1180x820", CGSize(width: 1_180, height: 820)),
            ("tablet-800x500", CGSize(width: 800, height: 500)),
        ]

        for (name, size) in cases {
            let layout = NowPlayingTabletLayout(viewport: size)
            check(layout.playerWidth >= 1, "\(name): non-positive player width")
            check(layout.panelWidth >= 1, "\(name): non-positive panel width")
            check(layout.contentHeight >= 0, "\(name): negative content height")
            check(
                layout.artworkSize >= 1,
                "\(name): non-positive artwork size"
            )
            check(
                layout.artworkSize <= layout.playerWidth + 0.001,
                "\(name): artwork wider than player column"
            )
            check(
                layout.playerWidth <= size.width + 0.001,
                "\(name): player wider than viewport"
            )
            // Estimated geometry only — not a claim about the rendered UI.
            check(
                layout.playerLeading.isFinite
                    && layout.panelLeading.isFinite,
                "\(name): non-finite column origins"
            )
        }

        let fills = NowPlayingTabletLayout(
            viewport: CGSize(width: 700, height: 500),
            fillsRegion: true
        )
        check(fills.playerWidth >= 1, "filled tablet player width")
        check(
            fills.contentHeight == 500,
            "filled tablet content height should match viewport"
        )
    }

    private static func check(
        _ condition: Bool,
        _ message: String
    ) {
        guard condition else {
            fputs("FAIL: \(message)\n", stderr)
            preconditionFailure(message)
        }
    }
}

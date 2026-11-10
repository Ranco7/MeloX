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
        runCompactWindowVisibility()
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
                layout.artworkSide >= 1,
                "\(testCase.name): artwork has no positive size"
            )
            check(
                layout.artworkSide <= layout.contentWidth + 0.001,
                "\(testCase.name): artwork exceeds the full-width controls column"
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
                    >= min(layout.minimumPageAreaHeight, layout.naturalContentHeight) - 0.001,
                "\(testCase.name): page area shorter than the page floor"
            )
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
            firstFallbackCase == "500x400",
            "Only the physically shorter page should need scrolling, got \(firstFallbackCase ?? "none")"
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
            comfortable.pageAreaHeight >= comfortable.naturalContentHeight,
            "Fitted artwork must reserve enough vertical space before controls"
        )
        let lyrics = NowPlayingPortraitLayout(
            viewport: CGSize(width: 430, height: 700), showsArtworkPage: false
        )
        check(!lyrics.needsWholePlayerScroll, "Lyrics must not inherit the artwork's full-square height")
    }

    private static func runCompactWindowVisibility() {
        let windows: [CGSize] = [
            CGSize(width: 440, height: 570),
            CGSize(width: 430, height: 540),
            CGSize(width: 500, height: 600),
            CGSize(width: 320, height: 900),
            CGSize(width: 390, height: 1000),
        ]
        for window in windows {
            for safeInsets: CGFloat in [0, 44, 58] {
                for metadata: CGFloat in [64, 110, 148] {
                    for textScale: CGFloat in [1, 1.35] {
                      for measuredProgress: CGFloat in [78, 160] {
                        let viewport = CGSize(width: window.width, height: window.height - safeInsets)
                        let layout = NowPlayingPortraitLayout(viewport: viewport, textScale: textScale, measuredMetadataHeight: metadata, measuredProgressHeight: measuredProgress)

                        // Reconstruct the whole visible stack, through the bottom
                        // toolbar. A square-only or source assertion misses this bug.
                        let artworkTop = CGFloat(44) + layout.artworkTopSpacing
                        let metadataBottom = artworkTop + layout.artworkSide
                            + layout.artworkBottomSpacing + layout.metadataEstimatedHeight + layout.metadataBottomSpacing
                        let progressTop = CGFloat(44) + layout.pageAreaHeight
                        let transportTop = progressTop + layout.progressHeight + layout.progressTransportGap
                        let volumeTop = transportTop + layout.transportHeight + layout.transportVolumeGap
                        let volumeBottom = volumeTop + layout.volumeHeight
                        let toolbarBottom = volumeBottom + layout.volumeSelectorGap + layout.pageSelectorHeight
                        let stackBottom = toolbarBottom + 4

                        check(metadataBottom <= progressTop + 0.001, "Artwork/metadata collide with progress at \(viewport)")
                        check(artworkTop >= 44 && layout.artworkSide >= 1, "Artwork crossed its top inset")
                        check(abs(stackBottom - layout.portraitStackHeight) < 0.001, "Stack test omitted a control or padding")
                        if stackBottom <= viewport.height + 0.5 {
                            check(volumeBottom <= viewport.height - layout.pageSelectorHeight - layout.volumeSelectorGap - 4 + 0.5, "Volume is below the visible viewport")
                            check(!layout.needsWholePlayerScroll && !layout.usesScrollFallback, "A fitting stack should not scroll")
                        } else {
                            check(layout.needsWholePlayerScroll && layout.usesScrollFallback, "An oversized control band must scroll")
                            check(layout.artworkSide == 1, "Controls must keep their size before the fallback")
                        }
                        check(layout.contentWidth == viewport.width - 2 * layout.horizontalMargin, "Controls narrowed with the artwork")
                        check(layout.transportHeight >= 64 && layout.volumeHeight >= 44 && layout.pageSelectorHeight >= 44, "Short-window fit reduced native hit targets")
                        let paused = layout.artworkSide * 0.82
                        let inset = (layout.artworkSide - paused) * 0.5
                        check(inset >= 0 && abs(inset + paused * 0.5 - layout.artworkSide * 0.5) < 0.001, "Paused artwork is not centered")
                      }
                    }
                }
            }
        }
        let known: [(CGSize, CGFloat)] = [
            (CGSize(width: 440, height: 570), 112.285714),
            (CGSize(width: 430, height: 540), 88.857143),
            (CGSize(width: 500, height: 600), 135.714286),
            (CGSize(width: 440, height: 526), 77.923810),
        ]
        for (size, expectedSide) in known {
            let layout = NowPlayingPortraitLayout(viewport: size)
            check(abs(layout.artworkSide - expectedSide) < 0.001, "Unexpected short-window artwork size")
            check(layout.artworkSide < layout.contentWidth, "Short-window policy must shrink only artwork")
        }
        let tall = NowPlayingPortraitLayout(viewport: CGSize(width: 390, height: 1000))
        check(abs(tall.artworkSide - tall.contentWidth) < 0.001, "Narrow tall artwork should keep its full size")
        for height in stride(from: CGFloat(480), through: 1000, by: 1) {
            let a = NowPlayingPortraitLayout(viewport: CGSize(width: 440, height: height - 0.001))
            let b = NowPlayingPortraitLayout(viewport: CGSize(width: 440, height: height + 0.001))
            for (before, after) in [
                (a.artworkSide, b.artworkSide),
                (a.transportHeight, b.transportHeight),
                (a.artworkTopSpacing, b.artworkTopSpacing),
                (a.artworkBottomSpacing, b.artworkBottomSpacing),
                (a.metadataBottomSpacing, b.metadataBottomSpacing),
                (a.progressTransportGap, b.progressTransportGap),
                (a.transportVolumeGap, b.transportVolumeGap),
                (a.volumeSelectorGap, b.volumeSelectorGap),
            ] {
                check(abs(before - after) < 0.01, "Height resize jumped at \(height)")
            }
        }
        let accessibility = NowPlayingPortraitLayout(viewport: CGSize(width: 430, height: 482), textScale: 1.35, measuredMetadataHeight: 148, measuredProgressHeight: 160)
        check(accessibility.needsWholePlayerScroll, "Physically impossible accessibility layout must remain scrollable")
        print("Compact volume fit passed: 180 complete stacks, including measured progress and scroll fallback")
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
                abs(layout.artworkSize - layout.playerWidth) < 0.001,
                "\(name): playing artwork not aligned with player column"
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

        for width: CGFloat in [0, 240, 320, 390, 500, 700, 834, 1024, 1194, 1366] {
            for height: CGFloat in [0, 320, 400, 600, 768, 834, 1024, 1366] {
                for fillsRegion in [false, true] {
                    let layout = NowPlayingTabletLayout(
                        viewport: CGSize(width: width, height: height), fillsRegion: fillsRegion
                    )
                    check(layout.artworkSize.isFinite && layout.artworkSize >= 1, "Transient and resized artwork must remain valid")
                    check(abs(layout.artworkSize - layout.playerWidth) < 0.001, "Both tablet routes must align to the content column")
                    check(layout.artworkTopInset >= 0 && layout.metadataTopInset >= 0, "Vertical sections must not overlap")
                }
            }
        }

        for width: CGFloat in [320, 568, 700, 844, 1024, 1366] {
            for height: CGFloat in [0, 200, 320, 430] {
                let layout = NowPlayingLandscapeLayout(viewport: CGSize(width: width, height: height))
                check(layout.columnWidth.isFinite && layout.columnWidth >= 1, "Compact landscape has invalid columns")
                check(layout.columnWidth * 2 + layout.spacing <= width + 0.001, "Equal landscape columns overlap")
                check(layout.controlsHeight >= 360, "Landscape controls need a scrollable native-height column")
            }
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

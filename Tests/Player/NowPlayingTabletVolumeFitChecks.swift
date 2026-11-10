import CoreGraphics
import Foundation

/// Tests the production geometry with complete intrinsic control-band inputs.
/// Row heights are explicit fixtures, not claims of SwiftUI rendering on Linux.
@main
struct NowPlayingTabletVolumeFitChecks {
    private struct Rows {
        let metadata: CGFloat
        let progress: CGFloat
        let transport: CGFloat
        let volume: CGFloat

        func bandHeight(_ layout: NowPlayingTabletLayout) -> CGFloat {
            // Independently sum every view and padding in the column. Do not
            // use estimatedControlsHeight to prove the estimate fits itself.
            24 + metadata + 24 * layout.elementScale + progress
                + 24 * layout.elementScale + transport + 12 + volume + 20
        }
    }

    static func main() {
        let windows: [CGSize] = [
            CGSize(width: 1194, height: 834),
            CGSize(width: 834, height: 1194),
            CGSize(width: 1366, height: 1024),
            CGSize(width: 1024, height: 1366),
            CGSize(width: 597, height: 834),
            CGSize(width: 507, height: 834),
            CGSize(width: 694, height: 1024),
            CGSize(width: 507, height: 1194),
        ]
        let rows = [
            Rows(metadata: 48, progress: 78, transport: 52, volume: 44),
            Rows(metadata: 64, progress: 78, transport: 52, volume: 44),
            Rows(metadata: 128, progress: 110, transport: 52, volume: 44),
            Rows(metadata: 200, progress: 150, transport: 52, volume: 44),
        ]
        var count = 0
        for window in windows {
            // The card host already applies safe area padding. GeometryReader
            // receives this reduced size; subtract it exactly once.
            for safeInsets: CGFloat in [0, 44, 58] {
                for fillsRegion in [false, true] {
                    let viewport = CGSize(
                        width: window.width,
                        height: window.height - safeInsets
                            - (fillsRegion ? 112 : 0)
                    )
                    let base = NowPlayingTabletLayout(viewport: viewport, fillsRegion: fillsRegion)
                    for row in rows {
                        verify(base, rows: row)
                        count += 1
                    }
                }
            }
        }
        verifyKnownGeometry()
        verifyHeightAndFontChanges()
        print("Tablet volume fit passed: \(count) full stacks, safe areas, measured fonts/badges, both tablet routes")
    }

    private static func verify(_ base: NowPlayingTabletLayout, rows: Rows) {
        let band = rows.bandHeight(base)
        let fitted = base.fitting(controlsHeight: band)
        let chrome: CGFloat = base.fillsRegion ? 0 : 48
        let bottomBar: CGFloat = base.fillsRegion ? 0 : 64

        let artworkTop = chrome + fitted.artworkTopInset
        let gap = fitted.distributedGap
        let metadataTop = artworkTop + fitted.artworkSize + 24 + gap
        let progressTop = metadataTop + rows.metadata + 24 * fitted.elementScale + gap
        let transportTop = progressTop + rows.progress + 24 * fitted.elementScale + gap
        let volumeTop = transportTop + rows.transport + 12 + gap
        let volumeBottom = volumeTop + rows.volume
        let stackBottom = volumeBottom + 20 + gap
        let visibleBottom = base.viewport.height - bottomBar

        check(abs(fitted.artworkSize - fitted.playerWidth) < 0.001, "Artwork and controls must share a width")
        check(fitted.playerWidth <= fitted.playerContainerWidth, "Column exceeds its horizontal allowance")
        check(abs(stackBottom - chrome - fitted.renderedStackHeight) < 0.001, "Full stack omits a row or gap")
        check(abs(stackBottom - visibleBottom) < 0.001, "Surplus height must be shared between groups")
        check(stackBottom <= visibleBottom + 0.001, "Full stack overflows: \(base.viewport), band \(band)")
        check(volumeTop >= chrome && volumeBottom <= visibleBottom - 20 + 0.001, "Volume is outside the visible player region")
        check(rows.volume >= 44 && rows.transport >= 44, "Native touch controls must keep their height")
        check(fitted.artworkTopInset == 16, "Artwork top gap must stay modest at every height")

        // The native artwork surface scales about its center without changing
        // the stack. Verify both paused edges remain inside the playing square.
        let pausedSide = fitted.artworkSize * 0.82
        let inset = (fitted.artworkSize - pausedSide) * 0.5
        check(inset >= 0 && abs(inset + pausedSide * 0.5 - fitted.artworkSize * 0.5) < 0.001, "Paused center moved")
        check(artworkTop + inset + pausedSide <= artworkTop + fitted.artworkSize, "Paused artwork escaped its square")
    }

    private static func verifyKnownGeometry() {
        let cases: [(CGSize, CGFloat, CGFloat)] = [
            (CGSize(width: 1194, height: 834), 364, 722),
            (CGSize(width: 834, height: 1194), 377, 735),
            (CGSize(width: 1366, height: 1024), 480.376667, 845.016667),
            (CGSize(width: 1024, height: 1366), 422, 780),
            (CGSize(width: 597, height: 834), 258.5, 616.5),
            (CGSize(width: 1194, height: 790), 320, 678),
        ]
        let normal = Rows(metadata: 64, progress: 78, transport: 52, volume: 44)
        for (size, width, height) in cases {
            let base = NowPlayingTabletLayout(viewport: size)
            let fitted = base.fitting(controlsHeight: normal.bandHeight(base))
            check(abs(fitted.playerWidth - width) < 0.001, "Unexpected width at \(size): \(fitted.playerWidth)")
            check(abs(fitted.playerStackHeight - height) < 0.001, "Unexpected full stack at \(size)")
        }
    }

    private static func verifyHeightAndFontChanges() {
        let size = CGSize(width: 1194, height: 834)
        let base = NowPlayingTabletLayout(viewport: size)
        let normal = base.fitting(controlsHeight: 342)
        let largerText = base.fitting(controlsHeight: 422)
        check(abs(normal.playerWidth - largerText.playerWidth - 80) < 0.001, "Growing text must shrink both artwork and column")
        check(abs(normal.playerStackHeight - largerText.playerStackHeight) < 0.001, "Growing text pushed volume offscreen")
        check(abs(normal.lyricsFocusAnchorOffset - largerText.lyricsFocusAnchorOffset - 40) < 0.001, "Lyrics focus must follow the fitted artwork center")

        let shorter = NowPlayingTabletLayout(viewport: CGSize(width: 1194, height: 790), controlsHeight: 342)
        check(abs(normal.playerWidth - shorter.playerWidth - 44) < 0.001, "Safe area did not reduce the square and column together")
        let tooShort = NowPlayingTabletLayout(viewport: CGSize(width: 1194, height: 300), controlsHeight: 342)
        check(tooShort.playerWidth == 1 && tooShort.playerStackHeight > tooShort.contentHeight, "Physically impossible bands must retain scrollable controls")
    }

    private static func check(_ condition: Bool, _ message: String) {
        guard condition else {
            fputs("FAIL: \(message)\n", stderr)
            preconditionFailure(message)
        }
    }
}

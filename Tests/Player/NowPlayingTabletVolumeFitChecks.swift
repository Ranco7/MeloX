import CoreGraphics
import Foundation

/// Intrinsic rows are explicit fixtures, not rendered SwiftUI measurements.
@main
struct NowPlayingTabletVolumeFitChecks {
    static func main() {
        // Original pixels, calibrated against the source's 60pt handle and
        // 44pt menu. Also cover the requested approximate 446x580 estimate.
        let windows: [CGSize] = [
            CGSize(width: 375, height: 486), CGSize(width: 375, height: 682),
            CGSize(width: 698, height: 886), CGSize(width: 698, height: 590),
            CGSize(width: 446, height: 580), CGSize(width: 320, height: 480),
            CGSize(width: 1194, height: 834), CGSize(width: 834, height: 1194),
            CGSize(width: 1366, height: 1024), CGSize(width: 1024, height: 1366),
            CGSize(width: 597, height: 834), CGSize(width: 507, height: 834),
        ]
        var count = 0
        for window in windows {
            for safeArea: CGFloat in [0, 44, 58] {
                for fillsRegion in [false, true] {
                    for sidePanel in [false, true] {
                        for metadata: CGFloat in [48, 76, 96, 105, 124, 128, 148, 240] {
                            for progress: CGFloat in [78, 160] {
                                let base = NowPlayingTabletLayout(
                                    viewport: CGSize(width: window.width, height: window.height - safeArea),
                                    fillsRegion: fillsRegion, showsSidePanel: sidePanel
                                )
                                verify(base, metadata: metadata, progress: progress)
                                count += 1
                            }
                        }
                    }
                }
            }
        }
        // Normal wide reference windows must pass without a scroll fallback.
        for window in [CGSize(width: 698, height: 886), CGSize(width: 698, height: 590)] {
            for safeArea: CGFloat in [0, 44, 58] {
                for metadata: CGFloat in [52, 76, 96, 105, 124, 128] {
                    let base = NowPlayingTabletLayout(viewport: CGSize(width: window.width, height: window.height - safeArea))
                    let layout = base.fitting(controlsHeight: 16 + metadata + 8 + 78 + 4 + base.transportHeight + 4 + 44 + 8)
                    check(!layout.needsScroll, "Normal wide reference must retain full first-screen controls")
                    check(abs(layout.renderedStackHeight + 48 + 64 - layout.viewport.height) < 0.001, "Normal wide full stack lost chrome/toolbar")
                }
            }
        }
        let tall = NowPlayingTabletLayout(viewport: CGSize(width: 698, height: 842), controlsHeight: 298)
        let short = NowPlayingTabletLayout(viewport: CGSize(width: 698, height: 546), controlsHeight: 298)
        check(abs(tall.playerWidth - 544.44) < 0.001, "Measured split window must have a broad column")
        check(tall.playerWidth == short.playerWidth, "Resizing height must never narrow metadata/progress")
        check(tall.artworkSize > short.artworkSize, "Height should be absorbed by artwork")
        let larger = tall.fitting(controlsHeight: 378)
        check(larger.playerWidth == tall.playerWidth, "Dynamic Type must not narrow the column")
        check(abs(tall.artworkSize - larger.artworkSize - 80) < 0.001, "Native row growth must consume artwork height")
        check(abs(tall.lyricsFocusAnchorOffset - larger.lyricsFocusAnchorOffset - 40) < 0.001, "Lyrics must follow the fitted square")
        let narrow = NowPlayingTabletLayout(viewport: CGSize(width: 320, height: 600), showsSidePanel: true)
        check(narrow.playerWidth == 220 && narrow.playerContainerWidth < 220, "Narrow panes need a scrollable 44pt transport row")
        let roomy = NowPlayingTabletLayout(viewport: CGSize(width: 375, height: 1200))
        check(roomy.artworkSize == roomy.playerWidth, "Align square and column when height permits")
        for height in stride(from: CGFloat(300), through: 1400, by: 1) {
            let before = NowPlayingTabletLayout(viewport: CGSize(width: 698, height: height - 0.001))
            let after = NowPlayingTabletLayout(viewport: CGSize(width: 698, height: height + 0.001))
            check(abs(before.artworkSize - after.artworkSize) < 0.003, "Height resize must be continuous")
            check(before.playerWidth == after.playerWidth, "Column changed with height")
        }
        print("Tablet independent-column fit passed: \(count) stacks; reference windows, safe areas, accessibility, scroll fallback, both routes")
    }

    private static func verify(_ base: NowPlayingTabletLayout, metadata: CGFloat, progress: CGFloat) {
        // Full visible-volume band, reconstructed independently of the model.
        let band: CGFloat = 16 + metadata + 8 + progress + 4 + base.transportHeight + 4 + 44 + 8
        let fitted = base.fitting(controlsHeight: band)
        let gap = fitted.distributedGap
        let metadataTop = 16 + fitted.artworkSize + 16 + gap
        let progressTop = metadataTop + metadata + 8 + gap
        let transportTop = progressTop + progress + 4 + gap
        let volumeTop = transportTop + fitted.transportHeight + 4 + gap
        let stackBottom = volumeTop + 44 + 8 + gap
        check(abs(stackBottom - fitted.renderedStackHeight) < 0.001, "Missing native row/padding")
        check(fitted.playerWidth == base.playerWidth, "Fitting controls narrowed the column")
        check(fitted.artworkSize <= fitted.playerWidth, "Square exceeds column")
        if fitted.needsScroll {
            check(fitted.artworkSize == min(fitted.playerWidth, 64), "Impossible stack must keep artwork floor")
            check(stackBottom > fitted.contentHeight, "Scroll fallback has no overflow")
        } else {
            check(abs(stackBottom - fitted.contentHeight) < 0.001, "Surplus height is not evenly distributed")
            check(volumeTop + 44 <= fitted.contentHeight - 8 + 0.001, "Default volume is offscreen")
        }
        let paused = fitted.artworkSize * 0.82
        let inset = (fitted.artworkSize - paused) * 0.5
        check(abs(inset + paused * 0.5 - fitted.artworkSize * 0.5) < 0.001, "Paused artwork center moved")
    }

    private static func check(_ condition: Bool, _ message: String) {
        guard condition else { fatalError(message) }
    }
}

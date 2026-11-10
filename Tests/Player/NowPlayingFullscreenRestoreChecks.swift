import CoreGraphics
import Foundation

/// Compiles the production fit decision against the frozen 9d5d354 geometry.
/// Intrinsic row heights below are fixtures, not rendered font measurements.
@main
struct NowPlayingFullscreenRestoreChecks {
    private static let windows: [CGSize] = [
        CGSize(width: 1024, height: 705), CGSize(width: 705, height: 1024),
        CGSize(width: 1194, height: 834), CGSize(width: 834, height: 1194),
        CGSize(width: 375, height: 486), CGSize(width: 375, height: 682),
        CGSize(width: 698, height: 886), CGSize(width: 698, height: 590),
        CGSize(width: 446, height: 580), CGSize(width: 320, height: 300),
        CGSize(width: 1366, height: 1024), CGSize(width: 1024, height: 1366),
    ]

    static func main() {
        var count = 0
        for window in windows {
            for safe: CGFloat in [0, 44, 58] {
                let viewport = CGSize(width: window.width, height: window.height - safe)
                for fills in [false, true] {
                    compareGolden(viewport, fills: fills)
                }
                let old = NowPlayingReferenceTabletLayout(viewport: viewport)
                // One-line baseline metadata / active badges / accessibility.
                // The old title deliberately stays one line, even when long.
                for metadata: CGFloat in [44, 72, 148, 240] {
                    for progress: CGFloat in [64, 78, 160] {
                        for volume: CGFloat in [0, 42] {
                            let band = metadata + progress + 52 + volume + 45 * old.elementScale + 32
                            let column = old.columnArtworkSectionHeight + band
                            let required = old.requiredSize(measuredColumnSize: CGSize(width: old.playerWidth, height: column))
                            let shouldFit = old.playerWidth >= 220 && column <= old.contentHeight
                            check((required.width <= viewport.width && required.height <= viewport.height) == shouldFit,
                                  "Reference decision omitted a real row, chrome, or width budget")
                            check(old.playerWidth >= 1 && old.playingArtworkSize <= old.playerWidth + 0.001,
                                  "Reference geometry is not finite or exceeds the old column")
                            if !shouldFit {
                                verifyAdaptive(viewport, metadata: metadata, progress: progress, showsVolume: volume > 0)
                            }
                            count += 1
                        }
                    }
                }
                let exact = old.requiredSize(measuredColumnSize: CGSize(width: old.playerWidth, height: old.contentHeight))
                near(exact.height, viewport.height, "Equality must fit without extra slack")
                let over = old.requiredSize(measuredColumnSize: CGSize(width: old.playerWidth, height: old.contentHeight + 0.001))
                check(over.height > viewport.height, "Height overflow must choose adaptive")
                let wide = old.requiredSize(measuredColumnSize: CGSize(width: old.playerWidth + 1, height: old.contentHeight))
                check(wide.width > viewport.width, "Fixed-size badge overflow must choose adaptive")
                let short = old.requiredSize(measuredColumnSize: CGSize(width: old.playerWidth, height: 0))
                if viewport.width < 520 { check(short.width > viewport.width, "Five 44pt targets need 220pt in the old half-column") }
            }
        }
        // Width seam derives from 0.5 * width - 40 >= 5 * 44.
        for width: CGFloat in [519.999, 520, 520.001] {
            let layout = NowPlayingReferenceTabletLayout(viewport: CGSize(width: width, height: 1200))
            let fit = layout.requiredSize(measuredColumnSize: CGSize(width: layout.playerWidth, height: 500))
            check((fit.width <= width) == (width >= 520), "Width seam drifted")
        }
        // No geometry quantization inside either branch. Switching branch is
        // intentional: do not interpolate away the exact old endpoint.
        for height in stride(from: CGFloat(300), through: 1400, by: 1) {
            for width: CGFloat in [375, 698, 834, 1024, 1194] {
                let a = NowPlayingReferenceTabletLayout(viewport: CGSize(width: width, height: height - 0.001))
                let b = NowPlayingReferenceTabletLayout(viewport: CGSize(width: width, height: height + 0.001))
                check(abs(a.playingArtworkSize - b.playingArtworkSize) < 0.02, "Reference resize jumped within its branch")
                let available = a.contentHeight - a.columnArtworkSectionHeight
                let before = a.requiredSize(measuredColumnSize: CGSize(width: a.playerWidth, height: a.columnArtworkSectionHeight + available - 0.01))
                let after = a.requiredSize(measuredColumnSize: CGSize(width: a.playerWidth, height: a.columnArtworkSectionHeight + available + 0.01))
                near(before.height, a.viewport.height, "Fitting side of seam drifted")
                check(after.height > a.viewport.height, "Overflow side of seam was accepted")
            }
        }
        // Explicit known values independently recorded from the old snapshot.
        let landscape = NowPlayingReferenceTabletLayout(viewport: CGSize(width: 1024, height: 705))
        near(landscape.playerWidth, 383.75, "1024x705 column")
        let portrait = NowPlayingReferenceTabletLayout(viewport: CGSize(width: 834, height: 1194))
        near(portrait.playerWidth, 377, "834x1194 column")
        near(portrait.playingArtworkSize, 377, "834x1194 visible playing square")
        check(!accepts(landscape, band: 297) && accepts(landscape, band: 255),
              "Volume / actual row heights must affect the fit; do not force hidden")
        check(accepts(portrait, band: 500), "Roomy portrait must restore the baseline")
        print("Fullscreen restoration passed: \(count) measured-stack fixtures, frozen geometry, safe areas, settings, width/height seams and adaptive fallback")
    }

    private static func accepts(_ layout: NowPlayingReferenceTabletLayout, band: CGFloat) -> Bool {
        let size = layout.requiredSize(measuredColumnSize: CGSize(width: layout.playerWidth, height: layout.columnArtworkSectionHeight + band))
        return size.width <= layout.viewport.width && size.height <= layout.viewport.height
    }

    private static func compareGolden(_ viewport: CGSize, fills: Bool) {
        let old = GoldenNowPlayingTabletLayout(viewport: viewport, fillsRegion: fills)
        let new = NowPlayingReferenceTabletLayout(viewport: viewport, fillsRegion: fills)
        let pairs: [(CGFloat, CGFloat)] = [
            (new.elementScale, old.elementScale), (new.contentHeight, old.contentHeight),
            (new.playerWidth, old.playerWidth), (new.playerLeading, old.playerLeading),
            (new.centeredPlayerLeading, old.centeredPlayerLeading), (new.panelLeading, old.panelLeading),
            (new.panelWidth, old.panelWidth), (new.artworkSize, old.artworkSize),
            (new.artworkTopInset, old.artworkTopInset), (new.metadataTopInset, old.metadataTopInset),
            (new.lyricsFocusAnchorOffset, old.lyricsFocusAnchorOffset),
        ]
        for (actual, expected) in pairs { near(actual, expected, "9d5d354 geometry changed") }
        near(NowPlayingReferenceTabletLayout.chromeHeight, 48, "Old header")
        near(NowPlayingReferenceTabletLayout.bottomBarHeight, 64, "Old footer")
        near(new.playingArtworkSize, old.artworkSize / 0.74, "Old playing transform was omitted")
        let slotOrigin = old.centeredPlayerLeading + (old.playerWidth - old.artworkSize) / 2
        let oldVisibleOrigin = slotOrigin - (old.artworkSize / 0.74 - old.artworkSize) / 2
        let newVisibleOrigin = new.centeredPlayerLeading + (new.playerWidth - new.playingArtworkSize) / 2
        near(newVisibleOrigin, oldVisibleOrigin, "Playing artwork position changed")
        let oldVisibleTop = 48 + old.artworkTopInset - (old.artworkSize / 0.74 - old.artworkSize) / 2
        let newVisibleTop = 48 + new.artworkTopInset + (new.artworkSize - new.playingArtworkSize) / 2
        near(newVisibleTop, oldVisibleTop, "Playing artwork vertical position changed")
        let paused = new.playingArtworkSize * 0.82
        near(newVisibleOrigin + (new.playingArtworkSize - paused) / 2 + paused / 2,
             oldVisibleOrigin + old.artworkSize / 0.74 / 2, "Paused 82% square lost its center")
    }

    private static func verifyAdaptive(_ viewport: CGSize, metadata: CGFloat, progress: CGFloat, showsVolume: Bool) {
        // Check both retained 575068d geometries; runtime still uses the original
        // size-class route. Complete old-column rejection must never clip.
        let base = NowPlayingTabletLayout(viewport: viewport)
        let band = 16 + metadata + 8 + progress + 4 + base.transportHeight + 4 + (showsVolume ? 44 : 0) + 8
        let fitted = base.fitting(controlsHeight: band)
        near(fitted.playerWidth, base.playerWidth, "Fallback narrowed its control column")
        check(fitted.transportHeight >= 44, "Fallback shrank a transport target")
        if !fitted.needsScroll {
            near(fitted.renderedStackHeight, fitted.contentHeight, "Fallback dropped or clipped controls")
        } else {
            check(fitted.renderedStackHeight > fitted.contentHeight, "Extreme fallback must remain scrollable")
        }
        // Normal four windows and the alternative first-window size retain
        // full controls with a two-line title, badge and default system volume.
        let normalNarrow = (viewport.width == 375 && viewport.height >= 428)
            || (viewport.width == 446 && viewport.height >= 522)
        if normalNarrow && metadata <= 76 && progress <= 78 {
            let portrait = NowPlayingPortraitLayout(viewport: viewport, measuredMetadataHeight: metadata, measuredProgressHeight: 52)
            check(portrait.artworkSide >= 64, "Normal small-window artwork collapsed")
            check(!portrait.needsWholePlayerScroll, "Normal small windows must show every control on the first screen")
        }
        if viewport.width == 698 && viewport.height >= 532 && metadata <= 128 && progress <= 78 {
            check(!fitted.needsScroll, "Normal wide reference must retain first-screen volume and toolbar")
        }
    }

    private static func near(_ actual: CGFloat, _ expected: CGFloat, _ message: String) {
        check(actual.isFinite && abs(actual - expected) < 0.000_001, message)
    }
    private static func check(_ condition: Bool, _ message: String) {
        guard condition else { fatalError(message) }
    }
}

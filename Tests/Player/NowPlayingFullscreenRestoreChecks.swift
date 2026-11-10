import CoreGraphics
import Foundation

/// Test the real selection policy against frozen 9d5d354 geometry. Row heights
/// are explicit stress fixtures, not measured SwiftUI font/slider intrinsics.
@main
struct NowPlayingFullscreenRestoreChecks {
    private static let windows: [CGSize] = [
        CGSize(width: 1408, height: 970), CGSize(width: 970, height: 1408),
        CGSize(width: 1024, height: 768), CGSize(width: 1210, height: 834),
        CGSize(width: 1024, height: 705), CGSize(width: 705, height: 1024),
        CGSize(width: 1194, height: 834), CGSize(width: 834, height: 1194),
        CGSize(width: 375, height: 486), CGSize(width: 375, height: 682),
        CGSize(width: 698, height: 886), CGSize(width: 698, height: 590),
        CGSize(width: 446, height: 580), CGSize(width: 320, height: 300),
        CGSize(width: 1366, height: 1024), CGSize(width: 1024, height: 1366)
    ]

    private enum VolumeFixture: CaseIterable {
        case hidden, independent, system
        var visualHeight: CGFloat { self == .hidden ? 0 : 42 }
    }

    static func main() {
        var count = 0
        for window in windows {
            for safe: CGFloat in [0, 44, 52, 58] {
                let viewport = CGSize(width: window.width, height: window.height - safe)
                for fills in [false, true] { compareGolden(viewport, fills: fills) }
                let selected = NowPlayingReferenceLayoutPolicy.usesReference(viewport: viewport)
                check(selected == originalBudgetCanFit(viewport), "Policy is not derived from the original budget/floor")
                check(!NowPlayingReferenceLayoutPolicy.usesReference(viewport: viewport, isAccessibilitySize: true),
                      "Accessibility must retain the measured adaptive fallback")
                for metadata: CGFloat in [44, 72, 148, 240] {
                    for progress: CGFloat in [64, 78, 160] {
                        // Hidden, independent and system. Active badge / long
                        // title fixtures must not feed a new intrinsic-fit gate.
                        for mode in VolumeFixture.allCases {
                            let volume = mode.visualHeight
                            let old = NowPlayingReferenceTabletLayout(viewport: viewport)
                            let band = metadata + progress + 52 + volume + 45 * old.elementScale + 32
                            let columnHeight = old.artworkTopInset + old.artworkSize + old.metadataTopInset + band
                            check(columnHeight.isFinite && columnHeight > 0, "Original scroll content is invalid")
                            check(NowPlayingReferenceLayoutPolicy.usesReference(viewport: viewport) == selected,
                                  "Settings/content changed reference selection")
                            if !selected { verifyAdaptive(viewport, metadata: metadata, progress: progress, showsVolume: volume > 0) }
                            count += 1
                        }
                    }
                }
            }
        }
        let device = NowPlayingReferenceTabletLayout(viewport: CGSize(width: 1408, height: 918))
        near(device.playerWidth, 495.14666666666665, "Calibrated device column")
        near(device.artworkSize / 0.74, 427.1605470011845, "Calibrated device playing square")
        let top = 32 + 48 + device.artworkTopInset - (device.artworkSize / 0.74 - device.artworkSize) / 2
        near(top, 141.466738451599, "Calibrated device visible top")
        let section = device.artworkTopInset + device.artworkSize + device.metadataTopInset
        let badgeSystemBand: CGFloat = 72 + 78 + 52 + 42 + 45 * device.elementScale + 32
        check(section + badgeSystemBand > device.contentHeight, "Fixture must reproduce 9302's false rejection")
        check(NowPlayingReferenceLayoutPolicy.usesReference(viewport: device.viewport), "System + badge + minimum-text device must select original")

        for size in [CGSize(width: 1024, height: 705), CGSize(width: 1194, height: 834),
                     CGSize(width: 834, height: 1194), CGSize(width: 970, height: 1408)] {
            for safe: CGFloat in [0, 44, 52, 58] {
                check(NowPlayingReferenceLayoutPolicy.usesReference(viewport: CGSize(width: size.width, height: size.height - safe)),
                      "Normal full window incorrectly selected adaptive")
            }
        }
        for width: CGFloat in [519.999, 520, 520.001] {
            let viewport = CGSize(width: width, height: 1200)
            check(NowPlayingReferenceLayoutPolicy.usesReference(viewport: viewport) == (width >= 520), "Five 44pt controls / old width seam")
        }
        for width: CGFloat in [520, 698, 834, 1024, 1194, 1408] {
            var low: CGFloat = 200
            var high: CGFloat = 1000
            for _ in 0..<60 {
                let middle = (low + high) / 2
                if originalBudgetCanFit(CGSize(width: width, height: middle)) { high = middle } else { low = middle }
            }
            check(!NowPlayingReferenceLayoutPolicy.usesReference(viewport: CGSize(width: width, height: high - 0.01)), "Before fit seam accepted")
            check(NowPlayingReferenceLayoutPolicy.usesReference(viewport: CGSize(width: width, height: high + 0.01)), "After fit seam rejected")
            for height in stride(from: CGFloat(300), through: 1400, by: 1) {
                let a = NowPlayingReferenceTabletLayout(viewport: CGSize(width: width, height: height - 0.001))
                let b = NowPlayingReferenceTabletLayout(viewport: CGSize(width: width, height: height + 0.001))
                check(abs(a.artworkSize - b.artworkSize) < 0.02, "Original branch quantized resize geometry")
                let viewport = CGSize(width: width, height: height)
                check(NowPlayingReferenceLayoutPolicy.usesReference(viewport: viewport) == originalBudgetCanFit(viewport), "Resize policy diverged from frozen source")
            }
        }
        for invalid in [CGSize.zero, CGSize(width: .infinity, height: 918),
                        CGSize(width: 1408, height: .nan), CGSize(width: -1, height: 918)] {
            check(!NowPlayingReferenceLayoutPolicy.usesReference(viewport: invalid), "Transient invalid geometry entered reference")
        }
        print("Original fullscreen selection passed: \(count) content/settings fixtures, calibrated golden, source geometry, zoom/portrait/split/safe areas, accessibility and fit seams")
    }

    /// The old compression can fit its own budget iff the uncompressed section
    /// at its 0.6 floor fits. This is independent of the production policy's sum
    /// of already-compressed properties, and uses the frozen source constants.
    private static func originalBudgetCanFit(_ size: CGSize) -> Bool {
        let old = GoldenNowPlayingTabletLayout(viewport: size)
        let p = min(max((size.height - 600) / 168, 0), 1)
        let top = (54 - min(max(600 - size.height, 0), 50) + 60 * p) * old.elementScale
        let art = min((214 + 94 * p) * old.elementScale, old.playerWidth * 0.74)
        let metadata = (70 + 10 * p) * old.elementScale
        return old.playerWidth >= 220 && 0.6 * (top + art + metadata) + 238 + 45 * old.elementScale <= old.contentHeight + 0.000_001
    }

    private static func compareGolden(_ viewport: CGSize, fills: Bool) {
        let old = GoldenNowPlayingTabletLayout(viewport: viewport, fillsRegion: fills)
        let new = NowPlayingReferenceTabletLayout(viewport: viewport, fillsRegion: fills)
        for (actual, expected) in [
            (new.elementScale, old.elementScale), (new.contentHeight, old.contentHeight),
            (new.playerWidth, old.playerWidth), (new.playerLeading, old.playerLeading),
            (new.centeredPlayerLeading, old.centeredPlayerLeading), (new.panelLeading, old.panelLeading),
            (new.panelWidth, old.panelWidth), (new.artworkSize, old.artworkSize),
            (new.artworkTopInset, old.artworkTopInset), (new.metadataTopInset, old.metadataTopInset),
            (new.lyricsFocusAnchorOffset, old.lyricsFocusAnchorOffset)
        ] { near(actual, expected, "Frozen original geometry changed") }
        let playing = new.artworkSize / 0.74
        let paused = playing * 0.82
        near((new.playerWidth - paused) / 2 + paused / 2, old.playerWidth / 2, "82% pause lost its center")
    }

    private static func verifyAdaptive(_ viewport: CGSize, metadata: CGFloat, progress: CGFloat, showsVolume: Bool) {
        let base = NowPlayingTabletLayout(viewport: viewport)
        let band = 16 + metadata + 8 + progress + 4 + base.transportHeight + 4 + (showsVolume ? 44 : 0) + 8
        let fitted = base.fitting(controlsHeight: band)
        near(fitted.playerWidth, base.playerWidth, "Fallback narrowed controls")
        check(fitted.transportHeight >= 44, "Fallback shrank a target")
        if !fitted.needsScroll { near(fitted.renderedStackHeight, fitted.contentHeight, "Fallback lost a row") }
        else { check(fitted.renderedStackHeight > fitted.contentHeight, "Extreme fallback lost scrolling") }
        let normalNarrow = (viewport.width == 375 && viewport.height >= 428)
            || (viewport.width == 446 && viewport.height >= 522)
        if normalNarrow && metadata <= 76 && progress <= 78 {
            let portrait = NowPlayingPortraitLayout(viewport: viewport, measuredMetadataHeight: metadata, measuredProgressHeight: 52)
            check(!portrait.needsWholePlayerScroll, "Normal small window lost first-screen controls")
        }
        if viewport.width == 698 && viewport.height >= 532 && metadata <= 128 && progress <= 78 {
            check(!fitted.needsScroll, "Normal short-wide window lost first-screen controls")
        }
    }
    private static func near(_ actual: CGFloat, _ expected: CGFloat, _ message: String) {
        check(actual.isFinite && abs(actual - expected) < 0.000_001, message)
    }
    private static func check(_ condition: Bool, _ message: String) {
        guard condition else { fatalError(message) }
    }
}

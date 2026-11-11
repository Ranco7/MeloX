import Foundation

// L10n's public titles are irrelevant to preference resolution; avoid pulling
// UI/localisation infrastructure into this standalone pure Swift executable.
enum L10n { static func string(_ key: String) -> String { key } }

@main
struct MusicCollectionSearchLayoutChecks {
    static func main() {
        precondition(PlayerVolumeControlMode.resolved(storedValue: nil) == .system)
        precondition(PlayerVolumeControlMode.resolved(storedValue: "obsolete") == .system)
        for mode in PlayerVolumeControlMode.allCases {
            precondition(PlayerVolumeControlMode.resolved(storedValue: mode.rawValue) == mode)
        }
        for width in [0.0, 320, 709.9, 710, 834, 1408, Double.infinity, Double.nan] {
            for tablet in [false, true] {
                for accessibility in [false, true] {
                    let resolved = MusicCollectionWidthPolicy.wideWidth(width, isTablet: tablet, isAccessibilitySize: accessibility)
                    precondition((resolved != nil) == (tablet && !accessibility && width.isFinite && width >= 710), "Search and content must use the same width predicate")
                }
            }
        }
        for scroll in stride(from: -50.0, through: 100, by: 0.25) {
            let height = MusicCollectionSearchLayout.height(scroll: scroll)
            let opacity = MusicCollectionSearchLayout.glyphOpacity(scroll: scroll)
            precondition((0...44).contains(height) && (0...1).contains(opacity))
            if (0...44).contains(scroll) {
                precondition(abs(height + scroll - 44) < 0.0001)
                // Content moves once; it stays 29pt below the shrinking search.
                let artworkTop = MusicCollectionSearchLayout.contentTopInset - scroll
                precondition(abs(artworkTop - (11 + height) - 29) < 0.0001)
            }
            if scroll >= 7 { precondition(opacity == 0) }
        }
        precondition(MusicCollectionSearchLayout.height(scroll: 44) == 0)
        precondition(MusicCollectionSearchLayout.height(scroll: -20) == 44)
        for fontSize in [17.0, 20, 23, 28, 34, 44, 53, 64] {
            let expanded = MusicCollectionSearchLayout.expandedHeight(fontSize: fontSize)
            precondition(expanded >= 44 && expanded >= fontSize * 1.3 + 16)
            precondition(MusicCollectionSearchLayout.height(scroll: -20, expandedHeight: expanded) == expanded)
            precondition(MusicCollectionSearchLayout.height(scroll: expanded, expandedHeight: expanded) == 0)
        }
        precondition(PressFeedbackPolicy.lyricInternalInset < 16, "Leave the existing clip gutter intact")
        precondition(PressFeedbackPolicy.rowOpacity < 0.1 && PressFeedbackPolicy.lyricOpacity < 0.1)
        precondition(PressFeedbackPolicy.animationDuration(isActive: true, reducesMotion: false) == 0)
        precondition(PressFeedbackPolicy.animationDuration(isActive: false, reducesMotion: true) == 0)
        precondition(PressFeedbackPolicy.animationDuration(isActive: false, reducesMotion: false) <= 0.2)
        print("Search collapse/gap and visible-by-default volume preference checks passed")
    }
}

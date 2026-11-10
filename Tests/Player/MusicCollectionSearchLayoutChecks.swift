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
            precondition((0...38).contains(height) && (0...1).contains(opacity))
            if (0...38).contains(scroll) {
                precondition(abs(height + scroll - 38) < 0.0001)
                // Content moves once; it stays 29pt below the shrinking search.
                let artworkTop = MusicCollectionSearchLayout.contentTopInset - scroll
                precondition(abs(artworkTop - (11 + height) - 29) < 0.0001)
            }
            if scroll >= 7 { precondition(opacity == 0) }
        }
        precondition(MusicCollectionSearchLayout.height(scroll: 38) == 0)
        precondition(MusicCollectionSearchLayout.height(scroll: -20) == 38)
        print("Search collapse/gap and visible-by-default volume preference checks passed")
    }
}

import Foundation

nonisolated enum MusicCollectionWidthPolicy {
    static let wideLayoutBreakpoint = 710.0

    static func wideWidth(_ width: Double, isTablet: Bool = true, isAccessibilitySize: Bool = false) -> Double? {
        guard isTablet, !isAccessibilitySize, width.isFinite, width >= wideLayoutBreakpoint else { return nil }
        return width
    }
}

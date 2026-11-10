import Foundation

nonisolated enum MusicCollectionWidthPolicy {
    static let wideLayoutBreakpoint = 710.0

    static func wideWidth(_ width: Double) -> Double? {
        guard width.isFinite, width >= wideLayoutBreakpoint else { return nil }
        return width
    }
}

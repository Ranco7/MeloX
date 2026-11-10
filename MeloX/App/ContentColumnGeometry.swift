import Foundation

nonisolated struct ContentColumnHorizontalBounds: Equatable, Sendable {
    let minX: Double
    let maxX: Double
}

nonisolated enum ContentColumnGeometryMath {
    /// Per-tab horizontal bounds in the root's named coordinate space,
    /// quantized to display pixels. Vertical position and height never enter
    /// the store.
    static func horizontalBounds(
        minX: Double,
        maxX: Double,
        displayScale: Double
    ) -> ContentColumnHorizontalBounds? {
        guard minX.isFinite, maxX.isFinite, maxX >= minX else {
            return nil
        }
        let scale = displayScale > 0 && displayScale.isFinite ? displayScale : 1
        let leading = (minX * scale).rounded() / scale
        let trailing = (maxX * scale).rounded() / scale
        guard trailing >= leading else { return nil }
        return ContentColumnHorizontalBounds(minX: leading, maxX: trailing)
    }
}

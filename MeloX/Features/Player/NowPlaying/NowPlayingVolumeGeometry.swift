import CoreGraphics

/// Separate MPVolumeView drawing height from the player's minimum hit target.
/// SwiftUI may probe unspecified or infinite widths.
struct NowPlayingVolumeGeometry {
    static let nativeHeight: CGFloat = 32
    static let touchHeight: CGFloat = 44
    static let idealWidth: CGFloat = 200

    static func size(proposedWidth: CGFloat?) -> CGSize {
        let width: CGFloat
        if let proposedWidth, proposedWidth.isFinite {
            width = max(proposedWidth, 0)
        } else {
            width = idealWidth
        }
        return CGSize(width: width, height: touchHeight)
    }

    static func nativeFrame(in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.minX, y: bounds.midY - nativeHeight / 2,
               width: bounds.width, height: nativeHeight)
    }

    static func nativeHitPoint(_ point: CGPoint, frame: CGRect) -> CGPoint {
        let y = point.y >= frame.minY && point.y < frame.maxY
            ? point.y - frame.minY : nativeHeight / 2
        return CGPoint(x: point.x - frame.minX, y: y)
    }
}

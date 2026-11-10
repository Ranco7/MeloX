import CoreGraphics
import Foundation

@main
struct NowPlayingSystemVolumeChecks {
    static func main() {
        // SwiftUI probes ideal, zero, unspecified and unbounded widths while
        // distributing HStack space. Never return a non-finite fitting size.
        let proposals: [CGFloat?] = [nil, 0, 1, 44, 200, 334, 544, -1, CGFloat.infinity, -CGFloat.infinity, CGFloat.nan]
        for proposal in proposals {
            let size = NowPlayingVolumeGeometry.size(proposedWidth: proposal)
            precondition(size.width.isFinite && size.width >= 0)
            precondition(size.height == 44)
            if let proposal, proposal.isFinite {
                precondition(size.width == max(proposal, 0))
            } else {
                precondition(size.width == 200)
            }
            let bounds = CGRect(origin: .zero, size: size)
            let frame = NowPlayingVolumeGeometry.nativeFrame(in: bounds)
            precondition(frame.height == 32, "Native drawing height must remain independent of touch height")
            precondition(frame.minY == 6 && frame.maxY == 38)
            precondition(frame.midY == bounds.midY && frame.width == bounds.width)
            for x in [CGFloat(0), size.width / 2, size.width] {
                for y: CGFloat in [0, 5.999, 6, 22, 37.999, 38, 43.999] {
                    let point = NowPlayingVolumeGeometry.nativeHitPoint(CGPoint(x: x, y: y), frame: frame)
                    precondition(point.x == x, "Expanded target must preserve slider's horizontal value")
                    precondition(point.y >= 0 && point.y < 32, "44pt target must forward into the 32pt native view")
                }
            }
        }
        let shifted = NowPlayingVolumeGeometry.nativeFrame(in: CGRect(x: 10, y: 20, width: 300, height: 44))
        precondition(shifted == CGRect(x: 10, y: 26, width: 300, height: 32))
        print("System volume bridge passed: finite proposals, native32 / target44 separation, full-height hit forwarding")
    }
}

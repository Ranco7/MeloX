import Foundation

@main
struct NowPlayingPresentationDragChecks {
    static func main() {
        for height in [320.0, 480, 667, 970, 1_366] {
            for distance in [0.0, 12, 80, 200] {
                let progress = NowPlayingPresentationDrag.progress(origin: 0, translation: distance, height: height)
                precondition(abs(progress * height - distance) < 0.000_001, "Downward drag must be 1:1")
            }
            let interrupted = NowPlayingPresentationDrag.progress(origin: 0.3, translation: 40, height: height)
            precondition(abs(interrupted * height - (0.3 * height + 40)) < 0.000_001)
            for origin in [-0.03, -0.12, -0.2] {
                let grabbed = NowPlayingPresentationDrag.progress(origin: origin, translation: 0, height: height)
                precondition(abs(grabbed - origin) < 0.000_001, "Grabbing an upward spring must not snap")
            }
            let slightUp = NowPlayingPresentationDrag.progress(origin: 0, translation: -1, height: height)
            let farUp = NowPlayingPresentationDrag.progress(origin: 0, translation: -height, height: height)
            precondition(slightUp < 0 && farUp < slightUp && farUp > -0.12, "Upward rubber band must be bounded")
            precondition(!NowPlayingPresentationDrag.shouldDismiss(progress: 0.10, velocity: 0, height: height))
            precondition(NowPlayingPresentationDrag.shouldDismiss(progress: 0.26, velocity: 0, height: height))
            precondition(NowPlayingPresentationDrag.shouldDismiss(progress: 0.05, velocity: height * 2, height: height))
            precondition(!NowPlayingPresentationDrag.shouldDismiss(progress: 0.05, velocity: -height, height: height))
            precondition(!NowPlayingPresentationDrag.shouldDismiss(progress: 0, velocity: 2_000, height: height))
            precondition(!NowPlayingPresentationDrag.shouldDismiss(progress: 0.4, velocity: -900, height: height))
            for distance in [0.0, 40, 200] {
                precondition(
                    NowPlayingPresentationDrag.velocityScale(origin: 0, translation: distance, height: height) == 1,
                    "Downward release velocity must stay 1:1"
                )
            }
            let upwardScale = NowPlayingPresentationDrag.velocityScale(origin: 0, translation: -80, height: height)
            let upwardRaw = -80 / height
            let expectedScale = 1 / pow(1 - upwardRaw / 0.12, 2)
            precondition(abs(upwardScale - expectedScale) < 0.000_001)
            precondition(upwardScale < 1)
            let finiteStep = 0.01
            let beforeRelease = NowPlayingPresentationDrag.progress(origin: 0, translation: -80, height: height)
            let afterRelease = NowPlayingPresentationDrag.progress(origin: 0, translation: -80 + finiteStep, height: height)
            precondition(abs((afterRelease - beforeRelease) / finiteStep * height - upwardScale) < 0.01)
            precondition(
                abs(NowPlayingPresentationDrag.velocityScale(origin: 0, translation: 0, height: height) - 1) < 0.000_001
            )
            precondition(
                abs(NowPlayingPresentationDrag.velocityScale(origin: 0, translation: -0.000_001, height: height) - 1) < 0.000_001,
                "Release velocity must be continuous through zero travel"
            )

            // Interrupted springs can start on either side of the top edge.
            for origin in [-0.2, -0.03, 0, 0.3] {
                for travel in [-height, -80, 0, 80] {
                    let scale = NowPlayingPresentationDrag.velocityScale(origin: origin, translation: travel, height: height)
                    let epsilon = 0.0001
                    let left = NowPlayingPresentationDrag.progress(origin: origin, translation: travel - epsilon, height: height)
                    let right = NowPlayingPresentationDrag.progress(origin: origin, translation: travel + epsilon, height: height)
                    precondition(abs((right - left) * height / (2 * epsilon) - scale) < 0.00001)
                    let offset = left * height
                    let extendedHeight = height + max(0, -offset)
                    precondition(offset + extendedHeight >= height - 0.000001, "Background must cover every upward offset")
                }
            }

            // One shared corner radius: square when flush, continuous while the
            // offset animates through opening, dismissal and cancel rebound.
            precondition(NowPlayingPresentationDrag.topCornerRadius(offset: 0, height: height) == 0)
            precondition(NowPlayingPresentationDrag.topCornerRadius(offset: -80, height: height) == 0)
            let entryRadius = NowPlayingPresentationDrag.topCornerRadius(offset: 12, height: height)
            precondition(entryRadius > 0 && entryRadius <= 34)
            precondition(NowPlayingPresentationDrag.topCornerRadius(offset: 6, height: height) < entryRadius)
            let radiusStep = height / 500
            var previousRadius = NowPlayingPresentationDrag.topCornerRadius(offset: 0, height: height)
            var visibleOffset = 0.0
            while visibleOffset < height {
                visibleOffset = min(visibleOffset + radiusStep, height)
                let radius = NowPlayingPresentationDrag.topCornerRadius(offset: visibleOffset, height: height)
                precondition(
                    abs(radius - previousRadius) <= 34.0 / 12.0 * radiusStep + 0.000_001,
                    "Corner radius must stay continuous at every visible offset"
                )
                precondition(radius >= previousRadius, "Radius must increase with downward offset")
                previousRadius = radius
            }
            precondition(NowPlayingPresentationDrag.topCornerRadius(offset: height, height: height) == 34)
        }

        precondition(abs(NowPlayingPresentationDrag.topCornerRadius(offset: 369, height: 970) - 23.65) < 0.1)
        precondition(abs(NowPlayingPresentationDrag.velocityScale(origin: 0, translation: -80, height: 970) - 0.3513) < 0.001)

        precondition(NowPlayingPresentationDrag.canBegin(velocityX: 0, velocityY: 100, scrollOffsets: []))
        precondition(NowPlayingPresentationDrag.canBegin(velocityX: 0, velocityY: -100, scrollOffsets: []))
        precondition(NowPlayingPresentationDrag.canBegin(velocityX: 1, velocityY: 100, scrollOffsets: [0, 0]))
        precondition(NowPlayingPresentationDrag.canBegin(velocityX: 1, velocityY: 100, scrollOffsets: [-12, 0.5]))
        precondition(!NowPlayingPresentationDrag.canBegin(velocityX: 1, velocityY: 100, scrollOffsets: [0, 120]))
        precondition(!NowPlayingPresentationDrag.canBegin(velocityX: 1, velocityY: 100, scrollOffsets: [120, 0]))
        precondition(!NowPlayingPresentationDrag.canBegin(velocityX: 1, velocityY: -100, scrollOffsets: [0]))
        precondition(!NowPlayingPresentationDrag.canBegin(velocityX: 100, velocityY: 1, scrollOffsets: []))
        print("Player drag policy passed: 5 window heights, release derivative, corner continuity and nested-scroll cases")
    }
}

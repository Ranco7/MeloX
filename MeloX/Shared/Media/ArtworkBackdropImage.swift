import Foundation
import Nuke
import SwiftUI
import UIKit

struct ArtworkBackdropImageAsset: @unchecked Sendable {
    let image: UIImage?
}

/// Reuses Nuke's pipeline and the URL-keyed best-resolution artwork cache for
/// the full-player backdrops. Requests are bounded and decoded off-main.
actor ArtworkBackdropImageProvider {
    static let shared = ArtworkBackdropImageProvider()

    private struct RequestKey: Hashable {
        let url: URL
        let dimension: Int
    }

    private var inFlight:
        [RequestKey: Task<ArtworkBackdropImageAsset, Never>] = [:]

    private init() {}

    func image(
        for url: URL,
        pixelDimension: CGFloat
    ) async -> ArtworkBackdropImageAsset {
        let dimension = CGFloat(
            ArtworkBackdropSizing.quantized(
                dimension: Double(pixelDimension)
            )
        )
        if let cached = ArtworkImageMemoryCache.shared.uiImage(for: url),
           ArtworkBackdropSizing.isSufficient(
               cached,
               for: Double(dimension)
           ) {
            return ArtworkBackdropImageAsset(image: cached)
        }

        let key = RequestKey(url: url, dimension: Int(dimension))
        if let task = inFlight[key] {
            return await task.value
        }
        let task = Task {
            await self.load(url: url, dimension: dimension)
        }
        inFlight[key] = task
        let asset = await task.value
        inFlight[key] = nil
        return asset
    }

    private func load(
        url: URL,
        dimension: CGFloat
    ) async -> ArtworkBackdropImageAsset {
        var request = ImageRequest(url: url)
        request.thumbnail = ImageRequest.ThumbnailOptions(
            size: CGSize(width: dimension, height: dimension),
            contentMode: .aspectFill
        )
        do {
            let image = try await ImagePipeline.shared.image(
                for: request
            )
            try Task.checkCancellation()
            ArtworkImageMemoryCache.shared.store(
                image,
                byteCost: ArtworkImageMemoryCache.byteCost(
                    of: image
                ),
                for: url
            )
            return ArtworkBackdropImageAsset(image: image)
        } catch {
            return ArtworkBackdropImageAsset(image: nil)
        }
    }
}

private extension ArtworkBackdropSizing {
    nonisolated static func pixelArea(of image: UIImage) -> Double {
        if let cgImage = image.cgImage {
            return Double(cgImage.width) * Double(cgImage.height)
        }
        let scale = Double(max(image.scale, 1))
        return Double(image.size.width)
            * Double(image.size.height)
            * scale * scale
    }

    nonisolated static func isSufficient(
        _ image: UIImage,
        for dimension: Double
    ) -> Bool {
        let required = max(dimension, 1) * max(dimension, 1) * 0.9
        return pixelArea(of: image) >= required
    }
}

/// Artwork layer shared by the full-player backdrops. It shows the best cached
/// artwork immediately, then fades a larger decode over it. The fade uses a
/// local transaction with animations explicitly re-enabled, because the
/// full-screen cover disables animations for its presentation transaction.
/// It never re-enables the cover slide or the card's own motion.
struct ArtworkBackdropImage: View {
    let url: URL?
    var placeholderColor: Color = .clear

    @Environment(\.accessibilityReduceMotion)
    private var accessibilityReduceMotion
    @Environment(\.displayScale) private var displayScale

    @State private var baseImage: UIImage?
    @State private var loadedImage: UIImage?
    @State private var fadeProgress: Double = 0

    init(url: URL?, placeholderColor: Color = .clear) {
        self.url = url
        self.placeholderColor = placeholderColor
        _baseImage = State(initialValue: url.flatMap { ArtworkImageMemoryCache.shared.uiImage(for: $0) })
    }

    var body: some View {
        GeometryReader { proxy in
            let request = request(for: proxy.size)

            ZStack {
                placeholderColor
                if let baseImage {
                    artworkImage(baseImage, in: proxy.size)
                }
                if let loadedImage {
                    artworkImage(loadedImage, in: proxy.size)
                        .opacity(
                            accessibilityReduceMotion ? 1 : fadeProgress
                        )
                        .id(ObjectIdentifier(loadedImage))
                        .onAppear(perform: fadeInLoadedImage)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .task(id: request) {
                await load(url: url, request: request)
            }
        }
    }

    private func request(
        for size: CGSize
    ) -> ArtworkBackdropRequest {
        let longestPixel = max(size.width, size.height)
            * max(displayScale, 1)
        let dimension = ArtworkBackdropSizing.pixelDimension(
            longestPixel: Double(longestPixel)
        )
        return ArtworkBackdropRequest(
            url: url,
            dimension: Int(dimension)
        )
    }

    private func load(
        url: URL?,
        request: ArtworkBackdropRequest
    ) async {
        guard let url else { return }
        let dimension = Double(request.dimension)
        if let cached = ArtworkImageMemoryCache.shared.uiImage(for: url),
           ArtworkBackdropSizing.isSufficient(cached, for: dimension) {
            install(cached)
            return
        }
        let asset = await ArtworkBackdropImageProvider.shared.image(
            for: url,
            pixelDimension: CGFloat(dimension)
        )
        guard !Task.isCancelled, let image = asset.image else { return }
        install(image)
    }

    private func install(_ image: UIImage) {
        if let baseImage,
           ArtworkBackdropSizing.pixelArea(of: baseImage)
            >= ArtworkBackdropSizing.pixelArea(of: image) {
            return
        }
        if let loadedImage,
           ArtworkBackdropSizing.pixelArea(of: loadedImage)
            >= ArtworkBackdropSizing.pixelArea(of: image) {
            return
        }
        if accessibilityReduceMotion {
            baseImage = image
            loadedImage = nil
        } else {
            fadeProgress = 0
            loadedImage = image
        }
    }

    private func fadeInLoadedImage() {
        guard !accessibilityReduceMotion, fadeProgress < 0.5 else {
            return
        }
        // Only this artwork opacity fade is animated. The presentation and the
        // card motion keep their disabled/custom transactions.
        var transaction = Transaction(
            animation: .timingCurve(0, 0, 0.3, 1, duration: 0.8)
        )
        transaction.disablesAnimations = false
        guard let incoming = loadedImage else { return }
        withTransaction(transaction) {
            withAnimation(transaction.animation, completionCriteria: .removed) {
                fadeProgress = 1
            } completion: {
                guard loadedImage === incoming else { return }
                baseImage = incoming
                loadedImage = nil
            }
        }
    }

    private func artworkImage(
        _ image: UIImage,
        in size: CGSize
    ) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
    }
}

private struct ArtworkBackdropRequest: Hashable {
    let url: URL?
    let dimension: Int
}

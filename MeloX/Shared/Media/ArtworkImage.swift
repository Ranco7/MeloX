import Nuke
import NukeUI
import SwiftUI
import UIKit

/// Bridges the moment between a new thumbnail request and Nuke's decoded-image
/// cache. Nuke keys decoded images by request (including thumbnail pixels), so
/// a layout change while a row is rebuilt would otherwise briefly show a
/// spinner even though the same artwork was just on screen.
///
/// Entries share Nuke's decoded pixel buffers; the cost is the real decoded
/// byte count so a few large covers cannot pin tens of megabytes.
private final class ArtworkImageMemoryCache {
    static let shared = ArtworkImageMemoryCache()

    private final class Entry {
        let image: Image

        init(_ image: Image) {
            self.image = image
        }
    }

    private let storage = NSCache<NSURL, Entry>()

    init() {
        storage.countLimit = 128
        storage.totalCostLimit = 64 * 1_024 * 1_024
    }

    func image(for url: URL) -> Image? {
        storage.object(forKey: url as NSURL)?.image
    }

    func store(_ image: Image, byteCost: Int, for url: URL) {
        storage.setObject(
            Entry(image),
            forKey: url as NSURL,
            cost: byteCost
        )
    }

    nonisolated static func byteCost(of image: UIImage) -> Int {
        if let cgImage = image.cgImage {
            return max(cgImage.bytesPerRow * cgImage.height, 1)
        }
        let scale = max(image.scale, 1)
        return max(
            Int(
                image.size.width * scale
                    * image.size.height * scale
                    * 4
            ),
            1
        )
    }
}

struct ArtworkImage: View {
    let url: URL?
    var cornerRadius: CGFloat = 10
    var aspectRatio: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let cachedImage = url.flatMap {
                ArtworkImageMemoryCache.shared.image(for: $0)
            }
            LazyImage(
                request: imageRequest(for: proxy.size),
                transaction: Transaction(animation: imageLoadAnimation)
            ) { state in
                content(
                    image: state.image ?? cachedImage,
                    hasError: state.error != nil
                )
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height
                )
            }
            .onCompletion { result in
                guard let url,
                      case let .success(response) = result else {
                    return
                }
                ArtworkImageMemoryCache.shared.store(
                    Image(uiImage: response.image),
                    byteCost: ArtworkImageMemoryCache.byteCost(
                        of: response.image
                    ),
                    for: url
                )
            }
            .onDisappear(.lowerPriority)
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .accessibilityHidden(true)
    }

    private func imageRequest(for size: CGSize) -> ImageRequest? {
        guard let url else { return nil }

        var request = ImageRequest(url: url)
        // Nuke's thumbnail size is expressed in pixels; SwiftUI points would
        // under-sample the image on 2x/3x displays. Quantizing the pixel size
        // keeps the request cacheable while a window or grid is resizing.
        let pixelScale = max(displayScale, 1)
        request.thumbnail = ImageRequest.ThumbnailOptions(
            size: CGSize(
                width: Self.quantizedPixelLength(
                    size.width * pixelScale
                ),
                height: Self.quantizedPixelLength(
                    size.height * pixelScale
                )
            ),
            contentMode: .aspectFill
        )
        return request
    }

    private nonisolated static func quantizedPixelLength(
        _ value: CGFloat
    ) -> CGFloat {
        let finiteValue = value.isFinite ? max(value, 1) : 1
        return max((finiteValue / 16).rounded(.up) * 16, 16)
    }

    private var imageLoadAnimation: Animation? {
        accessibilityReduceMotion ? nil : .easeOut(duration: 0.18)
    }

    @ViewBuilder
    private func content(image: Image?, hasError: Bool) -> some View {
        if let image {
            image
                .resizable()
                .scaledToFill()
                .transition(.opacity)
        } else if url == nil || hasError {
            placeholder
        } else {
            ZStack {
                Color.secondary.opacity(0.12)
                ProgressView()
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            Color.secondary.opacity(0.12)
            Image(systemName: "music.note")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}

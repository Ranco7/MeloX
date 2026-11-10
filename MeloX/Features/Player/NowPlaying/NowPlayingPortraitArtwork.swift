import SwiftUI
import UIKit

enum NowPlayingPortraitCoordinateSpace {
    static let name = "nowPlayingPortraitPageContent"
}

/// The layout always reserves the playing-size square. Playback changes only
/// the native surface transform, so the surrounding column never relayouts.
struct NowPlayingPortraitArtwork: View {
    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    @Environment(PlayerStore.self) private var player
    @Environment(AppSettings.self) private var settings

    let song: Song
    let isArtworkPage: Bool
    var usesReferenceAppearance = false

    var body: some View {
        NowPlayingArtworkSurface(
            url: song.album?.artworkURL,
            scale: isArtworkPage && !player.isPlaying && settings.shrinksPausedArtwork
                ? NowPlayingArtworkPage.pausedArtworkScale : 1,
            showsShadow: isArtworkPage,
            appearanceScale: usesReferenceAppearance && (player.isPlaying || !settings.shrinksPausedArtwork) ? 1 / 0.74 : 1,
            isPlaying: player.isPlaying,
            reducesMotion: reducesMotion
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.format("ui.song.artwork_accessibility", song.name))
    }
}

private struct NowPlayingArtworkSurface: UIViewControllerRepresentable {
    let url: URL?
    let scale: CGFloat
    let showsShadow: Bool
    let appearanceScale: CGFloat
    let isPlaying: Bool
    let reducesMotion: Bool

    func makeUIViewController(context: Context) -> NowPlayingArtworkSurfaceController {
        NowPlayingArtworkSurfaceController(
            url: url, scale: scale, showsShadow: showsShadow, appearanceScale: appearanceScale,
            isPlaying: isPlaying, reducesMotion: reducesMotion
        )
    }

    func updateUIViewController(_ controller: NowPlayingArtworkSurfaceController, context: Context) {
        controller.update(url: url, scale: scale, showsShadow: showsShadow, appearanceScale: appearanceScale,
                          isPlaying: isPlaying, reducesMotion: reducesMotion)
    }

    static func dismantleUIViewController(_ controller: NowPlayingArtworkSurfaceController, coordinator: ()) {
        controller.stopMotion()
    }
}

private final class NowPlayingArtworkSurfaceController: UIViewController {
    private let surface = UIView()
    private let imageClipView = UIView()
    private var host: UIHostingController<ArtworkImage>?
    private var animator: UIViewPropertyAnimator?
    private var url: URL?
    private var targetScale: CGFloat
    private var showsShadow: Bool
    private var appearanceScale: CGFloat
    private var isPlaying: Bool
    private var reducesMotion: Bool

    init(url: URL?, scale: CGFloat, showsShadow: Bool, appearanceScale: CGFloat, isPlaying: Bool, reducesMotion: Bool) {
        self.url = url
        self.targetScale = scale
        self.showsShadow = showsShadow
        self.appearanceScale = appearanceScale
        self.isPlaying = isPlaying
        self.reducesMotion = reducesMotion
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        surface.backgroundColor = .clear
        view.clipsToBounds = false
        surface.clipsToBounds = false
        imageClipView.clipsToBounds = true
        imageClipView.layer.cornerCurve = .continuous
        view.addSubview(surface)
        surface.addSubview(imageClipView)
        let host = UIHostingController(rootView: ArtworkImage(url: url, cornerRadius: 0))
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        addChild(host)
        imageClipView.addSubview(host.view)
        host.didMove(toParent: self)
        self.host = host
        // Install the FINAL playback scale before the card's first frame.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applyAppearance()
        CATransaction.commit()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        surface.bounds = CGRect(origin: .zero, size: view.bounds.size)
        surface.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        imageClipView.frame = surface.bounds
        host?.view.frame = imageClipView.bounds
        updateCornersAndShadowPath()
    }

    func update(url: URL?, scale: CGFloat, showsShadow: Bool, appearanceScale: CGFloat, isPlaying: Bool, reducesMotion: Bool) {
        if self.url != url {
            self.url = url
            host?.rootView = ArtworkImage(url: url, cornerRadius: 0)
        }
        let changed = self.appearanceScale != appearanceScale || targetScale != scale || self.showsShadow != showsShadow || self.isPlaying != isPlaying || self.reducesMotion != reducesMotion
        self.targetScale = scale
        self.showsShadow = showsShadow
        self.appearanceScale = appearanceScale
        self.isPlaying = isPlaying
        self.reducesMotion = reducesMotion
        guard changed, isViewLoaded else { return }
        stopMotion()
        guard !reducesMotion else {
            UIView.performWithoutAnimation { self.applyAppearance() }
            return
        }
        let animator = UIViewPropertyAnimator(duration: 0.48, curve: .easeInOut) { [weak self] in
            self?.applyAppearance()
        }
        self.animator = animator
        animator.startAnimation()
    }

    func stopMotion() {
        guard let animator else { return }
        if animator.state == .active {
            animator.stopAnimation(false)
            animator.finishAnimation(at: .current)
        }
        self.animator = nil
    }

    private func applyAppearance() {
        surface.transform = CGAffineTransform(scaleX: targetScale, y: targetScale)
        surface.layer.shadowColor = UIColor.black.cgColor
        surface.layer.shadowOpacity = showsShadow ? (isPlaying ? 0.34 : 0.18) : 0
        surface.layer.shadowRadius = (isPlaying ? 26 : 14) / targetScale * appearanceScale
        surface.layer.shadowOffset = CGSize(width: 0, height: (isPlaying ? 15 : 8) / targetScale * appearanceScale)
        updateCornersAndShadowPath()
    }

    private func updateCornersAndShadowPath() {
        // Compensate the transform so both endpoint states retain a visible
        // radius and shadow footprint in screen points. The reference tablet
        // retains the old playing appearance that was scaled by 1 / 0.74.
        let radius = 12 / targetScale * appearanceScale
        imageClipView.layer.cornerRadius = radius
        surface.layer.shadowPath = UIBezierPath(roundedRect: surface.bounds, cornerRadius: radius).cgPath
    }

}

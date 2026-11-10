import SwiftUI
import UIKit

/// Bridges the existing transparent full-screen cover to a UIKit card whose
/// transform and corner radius are owned by Core Animation. The player tree is
/// hosted once; gesture and spring updates never rebuild it.
struct NowPlayingPresentationView: UIViewControllerRepresentable {
    let initialPage: NowPlayingPage
    let reducesMotion: Bool
    let dismissalRequested: Bool
    let onDismiss: () -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(NeteaseAPI.self) private var api
    @Environment(LibraryStore.self) private var library
    @Environment(CloudMusicStore.self) private var cloud
    @Environment(DownloadStore.self) private var downloads
    @Environment(PlayerStore.self) private var player
    @Environment(ListenTogetherStore.self) private var listenTogether
    @Environment(LyricsStore.self) private var lyrics
    @Environment(FloatingLyricsController.self) private var floatingLyrics
    @Environment(LyricsNotificationController.self) private var lyricsNotifications
    @Environment(ScreenAwakeCoordinator.self) private var screenAwakeCoordinator
    @Environment(AppReleaseNotesStore.self) private var releaseNotes
    @Environment(\.effectiveLyricsRefreshRate)
    private var effectiveLyricsRefreshRate
    @Environment(\.locale) private var locale
    @Environment(\.openMusicRoute) private var openMusicRoute
    @Environment(\.openNeteaseShare) private var openNeteaseShare
    @Environment(\.scenePhase) private var scenePhase

    func makeUIViewController(
        context: Context
    ) -> NowPlayingCardContainerController {
        let host = NowPlayingHostEnvironment(
            settings: settings,
            api: api,
            library: library,
            cloud: cloud,
            downloads: downloads,
            player: player,
            listenTogether: listenTogether,
            lyrics: lyrics,
            floatingLyrics: floatingLyrics,
            lyricsNotifications: lyricsNotifications,
            screenAwakeCoordinator: screenAwakeCoordinator,
            releaseNotes: releaseNotes,
            openMusicRoute: openMusicRoute,
            openNeteaseShare: openNeteaseShare
        )
        return NowPlayingCardContainerController(
            initialPage: initialPage,
            reducesMotion: reducesMotion,
            host: host,
            effectiveLyricsRefreshRate: effectiveLyricsRefreshRate,
            locale: locale,
            scenePhase: scenePhase,
            onDismiss: onDismiss
        )
    }

    static func dismantleUIViewController(
        _ controller: NowPlayingCardContainerController, coordinator: ()
    ) { controller.shutdown() }

    func updateUIViewController(
        _ controller: NowPlayingCardContainerController,
        context: Context
    ) {
        controller.setDismissalRequested(dismissalRequested)
        controller.setScenePhase(scenePhase)
        controller.setAppearanceContext(
            effectiveLyricsRefreshRate: effectiveLyricsRefreshRate,
            locale: locale
        )
    }
}

/// Environment objects and actions that the manually hosted SwiftUI tree
/// cannot inherit from the cover's SwiftUI hierarchy. Everything the player
/// subtree reads is forwarded explicitly.
struct NowPlayingHostEnvironment {
    let settings: AppSettings
    let api: NeteaseAPI
    let library: LibraryStore
    let cloud: CloudMusicStore
    let downloads: DownloadStore
    let player: PlayerStore
    let listenTogether: ListenTogetherStore
    let lyrics: LyricsStore
    let floatingLyrics: FloatingLyricsController
    let lyricsNotifications: LyricsNotificationController
    let screenAwakeCoordinator: ScreenAwakeCoordinator
    let releaseNotes: AppReleaseNotesStore
    let openMusicRoute: OpenMusicRouteAction
    let openNeteaseShare: OpenNeteaseShareAction
}

private struct NowPlayingHostedRoot: View {
    let initialPage: NowPlayingPage
    let host: NowPlayingHostEnvironment
    let safeAreaPadding: EdgeInsets
    let isInTransit: Bool
    let effectiveLyricsRefreshRate: LyricsRefreshRate
    let locale: Locale
    let scenePhase: ScenePhase
    let onDismiss: () -> Void

    var body: some View {
        NowPlayingView(initialPage: initialPage, onDismiss: onDismiss)
            .environment(host.settings)
            .environment(host.api)
            .environment(host.library)
            .environment(host.cloud)
            .environment(host.downloads)
            .environment(host.player)
            .environment(host.listenTogether)
            .environment(host.lyrics)
            .environment(host.floatingLyrics)
            .environment(host.lyricsNotifications)
            .environment(host.screenAwakeCoordinator)
            .environment(host.releaseNotes)
            .environment(
                \.effectiveLyricsRefreshRate,
                effectiveLyricsRefreshRate
            )
            .environment(\.locale, locale)
            .environment(\.scenePhase, scenePhase)
            .environment(\.openMusicRoute, host.openMusicRoute)
            .environment(\.openNeteaseShare, host.openNeteaseShare)
            .environment(\.nowPlayingCardInTransit, isInTransit)
            .safeAreaPadding(safeAreaPadding)
            .accessibilityAction(.escape) {
                onDismiss()
            }
    }
}

/// Owns the card view hierarchy, the single hosting controller, the pan
/// admission rules and the physical spring animators. The high-frequency drag
/// path writes only `CALayer` properties.
private struct NowPlayingCardMotionCapture {
    let progress: Double
    let velocity: Double
}

@MainActor
final class NowPlayingCardContainerController: UIViewController {
    private static let transformAnimationKey = "nowPlaying.card.transform"
    private static let radiusAnimationKey = "nowPlaying.card.cornerRadius"
    private static let dismissalReleaseDelay: TimeInterval = 0.3

    private let initialPage: NowPlayingPage
    private let reducesMotion: Bool
    private let host: NowPlayingHostEnvironment
    private let onDismiss: () -> Void

    private let motionView = UIView()
    private let cardView = UIView()
    private let backgroundExtensionView = UIView()
    private let panGesture = UIPanGestureRecognizer()

    private lazy var hostingController: UIHostingController<
        NowPlayingHostedRoot
    > = {
        let controller = UIHostingController(rootView: makeRootView())
        controller.safeAreaRegions = []
        controller.view.backgroundColor = .clear
        controller.view.isOpaque = false
        return controller
    }()

    private var motionCompletion: DispatchWorkItem?
    private var transitSnapshot: UIView?
    private var animationGeneration = UUID()
    private var dismissalWorkItem: DispatchWorkItem?
    private var dragOrigin: Double?
    private var dragProgress: Double = 0
    private var settledProgress: Double = 1
    private var currentHeight: CGFloat = 0
    private var cachedSafeAreaInsets = UIEdgeInsets.zero
    private var touchedView: UIView?
    private var hasStarted = false
    private var hasStartedSpring = false
    private var hasRequestedDismissal = false
    private var hasFinishedDismissal = false
    private var isDragging = false
    private var isDismissing = false
    private var isInTransit = true
    private var effectiveLyricsRefreshRate: LyricsRefreshRate
    private var locale: Locale
    private var scenePhase: ScenePhase
    private var hasResolvedExtensionColor = false
    private var motionStartTime: CFTimeInterval?
    private var motionStartProgress: Double = 0
    private var motionTargetProgress: Double = 0
    private var motionInitialVelocity: Double = 0
    private var motionParameters: LyricPhysicalSpringParameters?

    init(
        initialPage: NowPlayingPage,
        reducesMotion: Bool,
        host: NowPlayingHostEnvironment,
        effectiveLyricsRefreshRate: LyricsRefreshRate,
        locale: Locale,
        scenePhase: ScenePhase,
        onDismiss: @escaping () -> Void
    ) {
        self.initialPage = initialPage
        self.reducesMotion = reducesMotion
        self.host = host
        self.effectiveLyricsRefreshRate = effectiveLyricsRefreshRate
        self.locale = locale
        self.scenePhase = scenePhase
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear
        view.isOpaque = false

        motionView.backgroundColor = .clear
        motionView.alpha = reducesMotion ? 0 : 1
        cardView.backgroundColor = .clear
        cardView.clipsToBounds = true
        cardView.layer.cornerCurve = .continuous
        cardView.layer.maskedCorners = [
            .layerMinXMinYCorner,
            .layerMaxXMinYCorner,
        ]

        backgroundExtensionView.isUserInteractionEnabled = false
        backgroundExtensionView.backgroundColor = extensionColor()

        motionView.addSubview(backgroundExtensionView)
        motionView.addSubview(cardView)
        view.addSubview(motionView)

        host.player.setNowPlayingCardInTransit(true)
        addChild(hostingController)
        cardView.addSubview(hostingController.view)
        hostingController.view.autoresizingMask = [
            .flexibleWidth,
            .flexibleHeight,
        ]
        hostingController.didMove(toParent: self)

        panGesture.maximumNumberOfTouches = 1
        panGesture.delegate = self
        panGesture.addTarget(
            self,
            action: #selector(handlePan(_:))
        )
        cardView.addGestureRecognizer(panGesture)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let heightChanged = abs(bounds.height - currentHeight) > 0.5
        motionView.bounds = CGRect(origin: .zero, size: bounds.size)
        motionView.center = CGPoint(
            x: bounds.midX,
            y: bounds.midY
        )
        cardView.bounds = CGRect(origin: .zero, size: bounds.size)
        cardView.center = CGPoint(
            x: bounds.midX,
            y: bounds.midY
        )
        backgroundExtensionView.frame = CGRect(
            x: 0,
            y: bounds.height,
            width: bounds.width,
            height: max(bounds.height * 0.35, 240)
        )
        hostingController.view.frame = cardView.bounds
        currentHeight = bounds.height
        updateSafeAreaIfNeeded()
        updateExtensionColorIfNeeded()

        if !hasStarted {
            apply(progress: 1)
        } else if heightChanged, !isDragging {
            _ = capturePresentationProgress()
            if isDismissing {
                settledProgress = 1
                apply(progress: 1)
                finishDismissal()
            } else {
                settledProgress = 0
                apply(progress: 0)
                setTransit(false)
            }
        }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateSafeAreaIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasStarted else { return }
        hasStarted = true
        updateExtensionColorIfNeeded()
        startPresentation()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // A full-screen child sheet can temporarily cover this controller.
        // Its already-committed CA motion must continue to its normal boundary.
        if isBeingDismissed || parent?.isBeingDismissed == true {
            cancellationCleanup()
        }
    }

    func shutdown() { cancellationCleanup() }

    override func accessibilityPerformEscape() -> Bool {
        collapse()
        return true
    }

    func setDismissalRequested(_ requested: Bool) {
        guard requested, !hasRequestedDismissal else { return }
        hasRequestedDismissal = true
        collapse()
    }

    func setScenePhase(_ phase: ScenePhase) {
        guard scenePhase != phase else { return }
        scenePhase = phase
        refreshRootView()
    }

    func setAppearanceContext(
        effectiveLyricsRefreshRate: LyricsRefreshRate,
        locale: Locale
    ) {
        guard self.effectiveLyricsRefreshRate != effectiveLyricsRefreshRate
                || self.locale != locale else {
            return
        }
        self.effectiveLyricsRefreshRate = effectiveLyricsRefreshRate
        self.locale = locale
        refreshRootView()
    }

    func collapse() {
        guard !isDismissing else { return }
        setTransit(true)
        freezeCardIfNeeded()
        isDismissing = true
        let captured = currentProgressForNewAnimation()
        let start = captured.progress
        isDragging = false
        dragOrigin = nil
        settledProgress = start

        if reducesMotion {
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                options: [.curveEaseInOut]
            ) {
                self.motionView.alpha = 0
            } completion: { _ in
                self.finishDismissal()
            }
            return
        }

        animate(
            to: max(1, start),
            from: start,
            initialVelocity: captured.velocity,
            parameters: NowPlayingCardMotionMath.closingSpring
        )
        scheduleDismissalRelease()
    }

    private func startPresentation() {
        apply(progress: 1)

        if reducesMotion {
            motionView.alpha = 0
            settledProgress = 0
            setTransit(true)
            apply(progress: 0)
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                options: [.curveEaseInOut]
            ) {
                self.motionView.alpha = 1
            } completion: { _ in
                guard !self.isDismissing else { return }
                self.setTransit(false)
            }
            return
        }

        setTransit(true)
        view.layoutIfNeeded()
        cardView.layoutIfNeeded()
        hostingController.view.layoutIfNeeded()
        CATransaction.flush()

        DispatchQueue.main.async { [weak self] in
            self?.freezeCardIfNeeded()
            self?.startOpeningSpring()
        }
    }

    private func startOpeningSpring() {
        guard !hasStartedSpring,
              !isDragging,
              !isDismissing,
              view.window != nil else {
            return
        }
        hasStartedSpring = true
        settledProgress = 0
        animate(
            to: 0,
            from: 1,
            initialVelocity: 0,
            parameters: NowPlayingCardMotionMath.openingSpring
        )
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: view).y
        switch recognizer.state {
        case .began:
            beginDrag()
            updateDrag(translation: translation)
        case .changed:
            updateDrag(translation: translation)
        case .ended:
            endDrag(
                translation: translation,
                velocity: recognizer.velocity(in: view).y,
                cancelled: false
            )
        case .cancelled, .failed:
            endDrag(
                translation: translation,
                velocity: 0,
                cancelled: true
            )
        default:
            break
        }
    }

    private func beginDrag() {
        guard !isDismissing else { return }
        hasStartedSpring = true
        let origin = currentProgressForNewAnimation().progress
        isDragging = true
        dragOrigin = origin
        dragProgress = origin
        settledProgress = origin
        setTransit(true)
        freezeCardIfNeeded()
    }

    private func updateDrag(translation: CGFloat) {
        guard let origin = dragOrigin, !isDismissing else { return }
        dragProgress = NowPlayingPresentationDrag.progress(
            origin: origin,
            translation: Double(translation),
            height: Double(currentHeight)
        )
        settledProgress = dragProgress
        apply(progress: dragProgress)
    }

    private func endDrag(
        translation: CGFloat,
        velocity: CGFloat,
        cancelled: Bool
    ) {
        guard let origin = dragOrigin, !isDismissing else { return }
        updateDrag(translation: translation)
        let progress = dragProgress
        dragOrigin = nil
        isDragging = false

        let dismisses = !cancelled
            && NowPlayingPresentationDrag.shouldDismiss(
                progress: progress,
                velocity: Double(velocity),
                height: Double(currentHeight)
            )
        let scale = NowPlayingPresentationDrag.velocityScale(
            origin: origin,
            translation: Double(translation),
            height: Double(currentHeight)
        )
        let speed = cancelled
            ? 0
            : Double(velocity)
                / max(Double(currentHeight), 1)
                * scale

        if dismisses {
            if reducesMotion {
                collapse()
            } else {
                isDismissing = true
                animate(
                    to: max(1, progress),
                    from: progress,
                    initialVelocity: speed,
                    parameters: NowPlayingCardMotionMath.closingSpring
                )
                scheduleDismissalRelease()
            }
        } else if reducesMotion {
            settleReducedMotionReturn()
        } else {
            animate(
                to: 0,
                from: progress,
                initialVelocity: speed,
                parameters: NowPlayingCardMotionMath.openingSpring
            )
        }
    }

    private func animate(
        to target: Double,
        from start: Double,
        initialVelocity velocity: Double,
        parameters: LyricPhysicalSpringParameters
    ) {
        invalidateAnimator()
        motionView.layer.removeAnimation(forKey: Self.transformAnimationKey)
        cardView.layer.removeAnimation(forKey: Self.radiusAnimationKey)
        guard currentHeight > 0 else { finishMotion(completed: true); return }
        // Sample BOTH properties from one physical trajectory. A separate UIKit
        // spring normalizes velocity and chooses its own duration, which cannot
        // share an exact nonlinear radius clock with an explicit CA animation.
        let frames = NowPlayingCardMotionMath.radiusKeyframes(
            from: start, to: target, initialVelocity: velocity,
            parameters: parameters, height: Double(currentHeight)
        )
        let duration = NowPlayingCardMotionMath.settlingDuration(
            from: start, to: target, initialVelocity: velocity,
            parameters: parameters
        )
        // Size the static tail once at the motion boundary, including unusually
        // fast upward releases. It never changes during animation or pan ticks.
        if let minimumOffset = frames.offsets.min() {
            backgroundExtensionView.frame.size.height = max(
                max(currentHeight * 0.35, 240), CGFloat(-minimumOffset + 1)
            )
        }
        let clock = CACurrentMediaTime()
        motionStartTime = clock
        motionStartProgress = start
        motionTargetProgress = target
        motionInitialVelocity = velocity
        motionParameters = parameters
        let generation = animationGeneration
        let offset = CAKeyframeAnimation(keyPath: "transform.translation.y")
        offset.values = frames.offsets.map { NSNumber(value: $0) }
        let radius = CAKeyframeAnimation(keyPath: "cornerRadius")
        radius.values = frames.radii.map { NSNumber(value: $0) }
        for animation in [offset, radius] {
            animation.keyTimes = frames.keyTimes.map { NSNumber(value: $0) }
            animation.duration = duration
            animation.calculationMode = .linear
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            animation.isRemovedOnCompletion = true
            animation.preferredFrameRateRange = CAFrameRateRange(
                minimum: 80, maximum: 120, preferred: 120
            )
        }
        offset.beginTime = motionView.layer.convertTime(clock, from: nil)
        radius.beginTime = cardView.layer.convertTime(clock, from: nil)
        apply(progress: target)
        motionView.layer.add(offset, forKey: Self.transformAnimationKey)
        cardView.layer.add(radius, forKey: Self.radiusAnimationKey)
        let completion = DispatchWorkItem { [weak self] in
            guard let self, self.animationGeneration == generation else { return }
            self.motionView.layer.removeAnimation(forKey: Self.transformAnimationKey)
            self.cardView.layer.removeAnimation(forKey: Self.radiusAnimationKey)
            self.clearMotionTrace()
            self.settledProgress = target
            self.apply(progress: target)
            self.finishMotion(completed: true)
        }
        motionCompletion = completion
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: completion)
    }

    private func settleReducedMotionReturn() {
        invalidateAnimator()
        motionView.layer.removeAnimation(forKey: Self.transformAnimationKey)
        cardView.layer.removeAnimation(forKey: Self.radiusAnimationKey)
        settledProgress = 0
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.curveEaseOut]
        ) {
            self.motionView.transform = .identity
            self.cardView.layer.cornerRadius = 0
        } completion: { _ in
            guard !self.isDismissing else { return }
            self.setTransit(false)
        }
    }

    private func currentProgressForNewAnimation()
        -> NowPlayingCardMotionCapture {
        if isDragging {
            return NowPlayingCardMotionCapture(
                progress: dragProgress,
                velocity: 0
            )
        }
        if let captured = capturePresentationProgress() {
            return captured
        }
        return NowPlayingCardMotionCapture(
            progress: settledProgress,
            velocity: 0
        )
    }

    private func capturePresentationProgress()
        -> NowPlayingCardMotionCapture? {
        guard motionStartTime != nil else { return nil }
        let transform = motionView.layer.presentation()?.transform
            ?? motionView.layer.transform
        let radius = cardView.layer.presentation()?.cornerRadius
            ?? cardView.layer.cornerRadius
        let velocity = currentAnalyticVelocity()
        let progress: Double
        if currentHeight > 0 {
            let affine = CATransform3DGetAffineTransform(transform)
            progress = Double(affine.ty / currentHeight)
        } else {
            progress = settledProgress
        }

        invalidateAnimator()
        motionView.layer.removeAnimation(forKey: Self.transformAnimationKey)
        cardView.layer.removeAnimation(
            forKey: Self.radiusAnimationKey
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        motionView.layer.transform = transform
        cardView.layer.cornerRadius = radius
        CATransaction.commit()
        clearMotionTrace()

        return NowPlayingCardMotionCapture(
            progress: progress,
            velocity: velocity
        )
    }

    private func currentAnalyticVelocity() -> Double {
        guard let motionStartTime,
              let motionParameters else {
            return 0
        }
        let elapsed = CACurrentMediaTime() - motionStartTime
        return NowPlayingCardMotionMath.velocity(
            from: motionStartProgress,
            to: motionTargetProgress,
            initialVelocity: motionInitialVelocity,
            parameters: motionParameters,
            at: elapsed
        )
    }

    private func clearMotionTrace() {
        motionStartTime = nil
        motionParameters = nil
        motionStartProgress = 0
        motionTargetProgress = 0
        motionInitialVelocity = 0
    }

    private func apply(progress: Double) {
        guard currentHeight > 0 else { return }
        if reducesMotion {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            motionView.transform = .identity
            cardView.layer.cornerRadius = 0
            CATransaction.commit()
            return
        }
        let offset = CGFloat(progress) * currentHeight
        let radius = CGFloat(
            NowPlayingPresentationDrag.topCornerRadius(
                offset: Double(offset),
                height: Double(currentHeight)
            )
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        motionView.transform = CGAffineTransform(
            translationX: 0,
            y: offset
        )
        cardView.layer.cornerRadius = radius
        CATransaction.commit()
    }

    private func finishMotion(completed: Bool) {
        guard completed else { return }
        if isDismissing {
            finishDismissal()
        } else {
            setTransit(false)
        }
    }

    private func scheduleDismissalRelease() {
        dismissalWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.finishDismissal()
        }
        dismissalWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.dismissalReleaseDelay,
            execute: workItem
        )
    }

    private func finishDismissal() {
        guard !hasFinishedDismissal else { return }
        hasFinishedDismissal = true
        host.player.setNowPlayingCardInTransit(false)
        dismissalWorkItem?.cancel()
        dismissalWorkItem = nil
        onDismiss()
    }

    private func invalidateAnimator() {
        animationGeneration = UUID()
        motionCompletion?.cancel()
        motionCompletion = nil
        dismissalWorkItem?.cancel()
        dismissalWorkItem = nil
    }

    private func cancellationCleanup() {
        motionView.layer.removeAnimation(forKey: Self.transformAnimationKey)
        cardView.layer.removeAnimation(forKey: Self.radiusAnimationKey)
        clearMotionTrace()
        cancellationInvalidate()
        host.player.setNowPlayingCardInTransit(false)
        restoreCardSnapshot(animated: false)
    }

    private func cancellationInvalidate() {
        animationGeneration = UUID()
        motionCompletion?.cancel()
        motionCompletion = nil
        dismissalWorkItem?.cancel()
        dismissalWorkItem = nil
    }

    private func setTransit(_ value: Bool) {
        guard isInTransit != value else { return }
        isInTransit = value
        host.player.setNowPlayingCardInTransit(value)
        refreshRootView()
        if !value { restoreCardSnapshot(animated: true) }
    }

    private func freezeCardIfNeeded() {
        guard transitSnapshot == nil, !reducesMotion,
              let snapshot = hostingController.view.snapshotView(afterScreenUpdates: true)
        else { return }
        snapshot.frame = cardView.bounds
        snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        snapshot.isUserInteractionEnabled = false
        cardView.addSubview(snapshot)
        transitSnapshot = snapshot
        // Keep the live hierarchy hit-testable behind the opaque snapshot.
        // Hiding it would bypass nested-scroll and control admission on re-grab.
    }

    private func restoreCardSnapshot(animated: Bool) {
        hostingController.view.isHidden = false
        guard let snapshot = transitSnapshot else { return }
        transitSnapshot = nil
        guard animated else { snapshot.removeFromSuperview(); return }
        UIViewPropertyAnimator.runningPropertyAnimator(
            withDuration: 0.12, delay: 0, options: [.curveEaseInOut]
        ) { snapshot.alpha = 0 } completion: { _ in snapshot.removeFromSuperview() }
    }

    private func refreshRootView() {
        hostingController.rootView = makeRootView()
    }

    private func makeRootView() -> NowPlayingHostedRoot {
        NowPlayingHostedRoot(
            initialPage: initialPage,
            host: host,
            safeAreaPadding: EdgeInsets(
                top: cachedSafeAreaInsets.top,
                leading: cachedSafeAreaInsets.left,
                bottom: cachedSafeAreaInsets.bottom,
                trailing: cachedSafeAreaInsets.right
            ),
            isInTransit: isInTransit,
            effectiveLyricsRefreshRate: effectiveLyricsRefreshRate,
            locale: locale,
            scenePhase: scenePhase,
            onDismiss: { [weak self] in
                self?.collapse()
            }
        )
    }

    private func updateSafeAreaIfNeeded() {
        let insets = view.safeAreaInsets
        guard insets != cachedSafeAreaInsets else { return }
        cachedSafeAreaInsets = insets
        refreshRootView()
    }

    private func extensionColor() -> UIColor {
        let fallback = UIColor(white: 0.04, alpha: 1)
        guard let url = host.player.currentSong?.album?.artworkURL,
              let assets = ArtworkAccentColorProvider.cachedDetailAssets(
                for: url
              ) else {
            return fallback
        }
        let background = assets.palette.backgroundRGB
        return UIColor(
            red: CGFloat(min(max(background.x, 0), 1)),
            green: CGFloat(min(max(background.y, 0), 1)),
            blue: CGFloat(min(max(background.z, 0), 1)),
            alpha: 1
        )
    }

    private func updateExtensionColorIfNeeded() {
        guard !hasResolvedExtensionColor,
              ArtworkAccentColorProvider.cachedDetailAssets(
                for: host.player.currentSong?.album?.artworkURL
              ) != nil else {
            return
        }
        backgroundExtensionView.backgroundColor = extensionColor()
        hasResolvedExtensionColor = true
    }

    private var scrollViews: [UIScrollView] {
        var result: [UIScrollView] = []
        var view = touchedView
        while let current = view {
            if let scrollView = current as? UIScrollView {
                result.append(scrollView)
            }
            view = current.superview
        }
        return result
    }
}

extension NowPlayingCardContainerController: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard !isDismissing else { return false }
        touchedView = touch.view
        var view = touch.view
        while let current = view {
            if current is UIControl
                || current is UITextView
                || current is UITextField {
                return false
            }
            view = current.superview
        }
        return true
    }

    func gestureRecognizerShouldBegin(
        _ gestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard !isDismissing,
              let pan = gestureRecognizer as? UIPanGestureRecognizer else {
            return false
        }
        let velocity = pan.velocity(in: pan.view)
        let offsets = scrollViews.compactMap { scroll -> Double? in
            let inset = scroll.adjustedContentInset
            let isVertical = scroll.isScrollEnabled
                && (scroll.alwaysBounceVertical
                    || scroll.contentSize.height
                        + inset.top
                        + inset.bottom
                        > scroll.bounds.height + 1)
            return isVertical
                ? Double(scroll.contentOffset.y + inset.top)
                : nil
        }
        return NowPlayingPresentationDrag.canBegin(
            velocityX: Double(velocity.x),
            velocityY: Double(velocity.y),
            scrollOffsets: offsets
        )
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        scrollViews.contains {
            $0.panGestureRecognizer === otherGestureRecognizer
        }
    }
}

extension EnvironmentValues {
    @Entry var nowPlayingCardInTransit: Bool = false
}

struct CardTransitTaskID<Value: Equatable>: Equatable {
    let value: Value
    let isInTransit: Bool
}

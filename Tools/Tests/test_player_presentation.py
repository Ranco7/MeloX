"""Exercise ContentView's actual presentation actions without SwiftUI/Xcode.

This verifies state and navigation, not rendering or UIKit gesture behavior.
"""

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from test_playback_song_switch import method


ROOT = Path(__file__).resolve().parents[2]

FIXTURE = r"""
enum NowPlayingPage { case artwork, lyrics, queue }
enum PlayerPresentation { case nowPlaying }
enum MusicRoute: Equatable { case song, album }
struct Player { var currentSong: Int? = 1 }
struct Transaction {
    init(animation: Int?) {}
    var disablesAnimations = false
}
var lastTransactionDisablesAnimations: Bool?
func withTransaction(_ transaction: Transaction, _ body: () -> Void) {
    lastTransactionDisablesAnimations = transaction.disablesAnimations
    body()
}
final class ContentView {
    var player = Player()
    var playerPresentation: PlayerPresentation?
    var isPlayerPresentationActive = false
    var playerUsesReducedMotion = false
    var isPlayerDismissalRequested = false
    var accessibilityReduceMotion = false
    var requestedPlayerPage: NowPlayingPage?
    var nowPlayingSharePresentation: Int?
    var pendingMusicRoute: MusicRoute?
    var navigatedRoutes: [MusicRoute] = []
    func navigate(to route: MusicRoute) { navigatedRoutes.append(route) }
    func prepareArtworkForPresentation() {}
    // PRODUCTION_ACTIONS

    static func checkNoSong() {
        let view = ContentView()
        view.player.currentSong = nil
        view.openPlayer(.lyrics)
        precondition(view.playerPresentation == nil)
        precondition(!view.isPlayerPresentationActive)
        precondition(view.requestedPlayerPage == nil)
    }

    static func checkRepeatedTapsAndReopen() {
        let view = ContentView()
        view.openPlayer(.artwork)
        precondition(view.playerPresentation == .nowPlaying)
        precondition(view.isPlayerPresentationActive)
        precondition(lastTransactionDisablesAnimations == true)
        view.openPlayer(.lyrics)
        precondition(view.requestedPlayerPage == .artwork)
        view.dismissPlayer()
        precondition(view.playerPresentation == nil)
        precondition(view.isPlayerPresentationActive)
        view.openPlayer(.queue)
        precondition(view.playerPresentation == nil)
        view.nowPlayingSharePresentation = 42
        view.finishPendingSongNavigation()
        precondition(!view.isPlayerPresentationActive)
        precondition(view.requestedPlayerPage == nil)
        precondition(view.nowPlayingSharePresentation == nil)
        view.openPlayer(.queue)
        precondition(view.playerPresentation == .nowPlaying)
        precondition(view.requestedPlayerPage == .queue)
    }

    static func checkDismissalBoundary() {
        let view = ContentView()
        view.openPlayer()
        // A cancelled card drag leaves the presentation binding intact.
        view.openPlayer(.lyrics)
        precondition(view.playerPresentation == .nowPlaying)
        precondition(view.requestedPlayerPage == nil)
        // Completed card motion clears the binding before onDismiss finishes.
        view.playerPresentation = nil
        view.openPlayer(.lyrics)
        precondition(view.playerPresentation == nil)
        view.finishPendingSongNavigation()
        view.openPlayer(.lyrics)
        precondition(view.requestedPlayerPage == .lyrics)
    }

    static func checkReducedMotionIsLatched() {
        let view = ContentView()
        view.accessibilityReduceMotion = true
        view.openPlayer(.lyrics)
        precondition(view.playerUsesReducedMotion)
        precondition(lastTransactionDisablesAnimations == true)
        view.accessibilityReduceMotion = false
        view.openPlayer(.queue)
        precondition(view.playerUsesReducedMotion)
        view.dismissPlayer()
        precondition(lastTransactionDisablesAnimations == true)
        view.finishPendingSongNavigation()
        view.openPlayer()
        precondition(!view.playerUsesReducedMotion)
        precondition(lastTransactionDisablesAnimations == true)
    }

    static func checkDeferredNavigation() {
        let view = ContentView()
        view.openPlayer()
        view.openMusicRoute(.song)
        precondition(view.isPlayerDismissalRequested)
        precondition(view.playerPresentation == .nowPlaying)
        precondition(view.navigatedRoutes.isEmpty)
        view.dismissPlayer()
        view.openMusicRoute(.album)
        precondition(view.navigatedRoutes.isEmpty)
        view.finishPendingSongNavigation()
        precondition(view.navigatedRoutes == [.album])
        precondition(view.pendingMusicRoute == nil)
        precondition(!view.isPlayerDismissalRequested)
        view.finishPendingSongNavigation()
        precondition(view.navigatedRoutes == [.album])
        view.openMusicRoute(.song)
        precondition(view.navigatedRoutes == [.album, .song])
    }
}
ContentView.checkNoSong()
ContentView.checkRepeatedTapsAndReopen()
ContentView.checkDismissalBoundary()
ContentView.checkReducedMotionIsLatched()
ContentView.checkDeferredNavigation()
print("Player presentation state checks passed (5 scenario groups)")
"""


class PlayerPresentationTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("swiftc"), "Swift compiler unavailable")
    def test_drag_policy(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / "drag-checks"
            subprocess.run([
                "swiftc", "-swift-version", "5",
                str(ROOT / "MeloX/Features/Player/NowPlaying/NowPlayingPresentationDrag.swift"),
                str(ROOT / "Tests/Player/NowPlayingPresentationDragChecks.swift"),
                "-o", str(executable),
            ], check=True)
            subprocess.run([str(executable)], check=True)

    @unittest.skipUnless(shutil.which("swiftc"), "Swift compiler unavailable")
    def test_production_presentation_actions(self):
        source = (ROOT / "MeloX/App/ContentView.swift").read_text()
        actions = "\n".join(method(source, signature) for signature in (
            "private func openPlayer(",
            "private func dismissPlayer()",
            "private func setPlayerPresentation(",
            "private func openMusicRoute(",
            "private func finishPendingSongNavigation()",
        ))
        with tempfile.TemporaryDirectory() as directory:
            swift = Path(directory) / "main.swift"
            executable = Path(directory) / "presentation-checks"
            swift.write_text(FIXTURE.replace("// PRODUCTION_ACTIONS", actions))
            subprocess.run(
                ["swiftc", "-swift-version", "5", str(swift), "-o", str(executable)],
                check=True,
            )
            subprocess.run([str(executable)], check=True)


    @unittest.skipUnless(shutil.which("swiftc"), "Swift compiler unavailable")
    def test_shared_offset_policy(self):
        harness = r"""
import Foundation
for height in [320.0, 480, 667, 970, 1366] {
    for distance in [0.0, 40, 200] {
        precondition(NowPlayingPresentationDrag.velocityScale(origin: 0, translation: distance, height: height) == 1)
    }
    let scale = NowPlayingPresentationDrag.velocityScale(origin: 0, translation: -80, height: height)
    let expected = 1 / pow(1 - (-80.0 / height) / 0.12, 2)
    precondition(abs(scale - expected) < 0.000_001 && scale < 1)
    // Opening, dismissal and cancel rebound all read this one function.
    precondition(NowPlayingPresentationDrag.topCornerRadius(offset: 0, height: height) == 0)
    precondition(NowPlayingPresentationDrag.topCornerRadius(offset: -80, height: height) == 0)
    let step = height / 500
    var previous = NowPlayingPresentationDrag.topCornerRadius(offset: 0, height: height)
    var offset = 0.0
    while offset < height {
        offset = min(offset + step, height)
        let radius = NowPlayingPresentationDrag.topCornerRadius(offset: offset, height: height)
        precondition(abs(radius - previous) <= 34.0 / 12.0 * step + 0.000_001)
        precondition(radius >= previous)
        previous = radius
    }
}
precondition(abs(NowPlayingPresentationDrag.topCornerRadius(offset: 369, height: 970) - 23.65) < 0.1)
precondition(abs(NowPlayingPresentationDrag.velocityScale(origin: 0, translation: -80, height: 970) - 0.3513) < 0.001)
print("Shared offset policy passed: release derivative and corner continuity")
"""
        with tempfile.TemporaryDirectory() as directory:
            swift = Path(directory) / "main.swift"
            executable = Path(directory) / "offset-policy-checks"
            swift.write_text(harness)
            subprocess.run([
                "swiftc", "-swift-version", "5",
                str(ROOT / "MeloX/Features/Player/NowPlaying/NowPlayingPresentationDrag.swift"),
                str(swift), "-o", str(executable),
            ], check=True)
            subprocess.run([str(executable)], check=True)

    def test_presentation_uses_uikit_card_motion(self):
        view = (
            ROOT
            / "MeloX/Features/Player/NowPlaying/NowPlayingPresentationView.swift"
        ).read_text()
        self.assertIn(
            "struct NowPlayingPresentationView: UIViewControllerRepresentable",
            view,
        )
        self.assertIn(
            "final class NowPlayingCardContainerController: UIViewController",
            view,
        )
        self.assertIn("UIHostingController(rootView: makeRootView())", view)
        self.assertIn('CAKeyframeAnimation(keyPath: "transform.translation.y")', view)
        self.assertIn("motionStartTime = clock", view)
        self.assertIn("NowPlayingCardMotionMath.openingSpring", view)
        self.assertIn("NowPlayingCardMotionMath.closingSpring", view)
        self.assertIn("NowPlayingPresentationDrag.topCornerRadius", view)
        self.assertIn("NowPlayingPresentationDrag.velocityScale", view)
        self.assertIn("NowPlayingPresentationDrag.shouldDismiss", view)
        self.assertIn("NowPlayingPresentationDrag.canBegin", view)
        self.assertIn("cardView.layer.maskedCorners", view)
        self.assertIn(".layerMinXMinYCorner", view)
        self.assertIn(".layerMaxXMinYCorner", view)
        self.assertIn("cardView.layer.cornerCurve = .continuous", view)
        self.assertIn("cardView.clipsToBounds = true", view)
        self.assertIn("motionView.transform = CGAffineTransform(", view)
        self.assertIn("animation.preferredFrameRateRange", view)
        self.assertIn("CAFrameRateRange(", view)
        self.assertNotIn("TimelineView", view)
        self.assertNotIn(".clipShape(", view)
        self.assertNotIn("let overhang = max(0, -offset)", view)
        self.assertNotIn("height: window.size.height + overhang", view)
        self.assertNotIn("NowPlayingCardModel", view)
        self.assertNotIn("nowPlayingBackgroundExtension", view)

        drag = view.split("private func updateDrag(translation:", 1)[1].split(
            "private func endDrag(", 1
        )[0]
        self.assertIn("apply(progress: dragProgress)", drag)
        self.assertNotIn("setTransit", drag)
        self.assertNotIn("rootView", drag)

    def test_card_interruption_and_snapshot_admission_regressions(self):
        path = ROOT / "MeloX/Features/Player/NowPlaying/NowPlayingPresentationView.swift"
        source = path.read_text()
        begin = method(source, "private func beginDrag()")
        self.assertLess(begin.index("currentProgressForNewAnimation()"), begin.index("isDragging = true"))
        self.assertNotIn("hostingController.view.isHidden = true", source)
        self.assertIn("recognizer.translation(in: view)", source)
        self.assertIn("offset.beginTime = motionView.layer.convertTime(clock", source)
        self.assertIn("radius.beginTime = cardView.layer.convertTime(clock", source)
        self.assertIn("static func dismantleUIViewController", source)
        self.assertIn("override func accessibilityPerformEscape()", source)
        player = (ROOT / "MeloX/Core/Playback/Session/PlayerStore.swift").read_text()
        perform = method(player, "private func performCurrentSongBeatAnalysis()")
        self.assertLess(perform.index("!Task.isCancelled"), perform.index("currentBeatTimeline = nil"))
        self.assertIn("else { return currentBeatTimeline }", perform)

    def test_player_content_is_hosted_once_by_container(self):
        view = (
            ROOT
            / "MeloX/Features/Player/NowPlaying/NowPlayingPresentationView.swift"
        ).read_text()
        self.assertEqual(view.count("NowPlayingView("), 1)
        self.assertEqual(
            view.count("UIHostingController(rootView: makeRootView())"), 1
        )
        self.assertEqual(
            view.count("hostingController.rootView = makeRootView()"), 1
        )
        self.assertIn("private func refreshRootView()", view)
        self.assertIn("guard isInTransit != value else { return }", view)
        self.assertIn("safeAreaRegions = []", view)
        self.assertIn(".safeAreaPadding(safeAreaPadding)", view)
        self.assertIn("hostingController.view.frame = cardView.bounds", view)
        self.assertIn("addChild(hostingController)", view)
        self.assertIn("hostingController.didMove(toParent: self)", view)
        self.assertIn(".accessibilityAction(.escape)", view)
        self.assertIn(".environment(\\.scenePhase, scenePhase)", view)
        self.assertIn("setScenePhase(scenePhase)", view)
        self.assertIn("setAppearanceContext(", view)

    def test_background_extension_is_a_static_container_layer(self):
        view = (
            ROOT / "MeloX/Features/Player/NowPlaying/NowPlayingView.swift"
        ).read_text()
        self.assertNotIn("nowPlayingBackgroundExtension", view)
        leaf = view.split("private struct NowPlayingBackgroundLayer", 1)[1]
        self.assertNotIn("backgroundExtension", leaf)
        self.assertIn("height: size.height", leaf)

        container = (
            ROOT
            / "MeloX/Features/Player/NowPlaying/NowPlayingPresentationView.swift"
        ).read_text()
        self.assertIn(
            "private let backgroundExtensionView = UIView()", container
        )
        self.assertIn(
            "backgroundExtensionView.isUserInteractionEnabled = false",
            container,
        )
        self.assertIn(
            "backgroundExtensionView.backgroundColor = extensionColor()",
            container,
        )
        layout = container.split(
            "override func viewDidLayoutSubviews()", 1
        )[1].split("override func viewSafeAreaInsetsDidChange()", 1)[0]
        self.assertEqual(layout.count("backgroundExtensionView.frame ="), 1)
        self.assertIn("height: max(bounds.height * 0.35, 240)", layout)

    def test_transit_environment_is_boundary_scoped(self):
        view = (
            ROOT / "MeloX/Features/Player/NowPlaying/NowPlayingView.swift"
        ).read_text()
        container = (
            ROOT
            / "MeloX/Features/Player/NowPlaying/NowPlayingPresentationView.swift"
        ).read_text()
        self.assertIn(
            "@Environment(\\.nowPlayingCardInTransit) private var cardInTransit",
            view,
        )
        self.assertIn("isInTransit: cardInTransit", view)
        self.assertIn("NowPlayingControlsAutoHideTaskID(", view)
        self.assertIn(".task(id: controlsAutoHideTaskID)", view)
        self.assertIn("guard !cardInTransit,", view)
        self.assertIn("guard !cardInTransit else { return }", view)

        drag = container.split("private func updateDrag(translation:", 1)[
            1
        ].split("private func endDrag(", 1)[0]
        self.assertNotIn("setTransit", drag)
        begin = container.split("private func beginDrag()", 1)[1].split(
            "private func updateDrag", 1
        )[0]
        self.assertIn("setTransit(true)", begin)
        start = container.split("private func startPresentation()", 1)[
            1
        ].split("private func startOpeningSpring()", 1)[0]
        self.assertIn("setTransit(true)", start)
        self.assertIn("guard isInTransit != value else { return }", container)
        self.assertEqual(
            container.count("hostingController.rootView = makeRootView()"), 1
        )

        for path in (
            "MeloX/Features/Player/NowPlaying/AppleMusicBackdrop/NowPlayingAppleMusicBackground.swift",
            "MeloX/Features/Player/NowPlaying/NowPlayingFlowingLightBackground.swift",
            "MeloX/Features/Player/NowPlaying/NowPlayingLyricSynchronizer.swift",
            "MeloX/Features/Player/Lyrics/Shared/LyricRowPresentationTimeline.swift",
            "MeloX/Features/Player/Lyrics/Shared/SynchronizedLyricText.swift",
            "MeloX/Features/Player/Lyrics/AppleMusic/AppleMusicLyricInterludeView.swift",
            "MeloX/Features/Player/TextPV/Views/TextPVLyricsView.swift",
        ):
            self.assertIn(
                "nowPlayingCardInTransit",
                (ROOT / path).read_text(),
                path,
            )

    def test_card_spring_parameters_are_unchanged(self):
        math = (
            ROOT
            / "MeloX/Features/Player/NowPlaying/NowPlayingCardMotionMath.swift"
        ).read_text()
        opening = math.split("static let openingSpring", 1)[1].split(
            "static let closingSpring", 1
        )[0]
        closing = math.split("static let closingSpring", 1)[1].split(
            "static let sampleCount", 1
        )[0]
        self.assertIn("mass: 1", opening)
        self.assertIn("stiffness: 329", opening)
        self.assertIn("damping: 36.2", opening)
        self.assertIn("mass: 1", closing)
        self.assertIn("stiffness: 329", closing)
        self.assertIn("damping: 28.9", closing)
        self.assertNotIn("36.2", closing)

    def test_reduce_motion_fade_and_warmup(self):
        container = (
            ROOT
            / "MeloX/Features/Player/NowPlaying/NowPlayingPresentationView.swift"
        ).read_text()
        self.assertIn("if reducesMotion {", container)
        self.assertIn("self.motionView.alpha = 0", container)
        self.assertIn("withDuration: 0.2", container)
        self.assertIn("CATransaction.flush()", container)
        self.assertIn("hostingController.view.layoutIfNeeded()", container)
        self.assertIn("startOpeningSpring()", container)
        self.assertIn("DispatchQueue.main.async { [weak self] in", container)

        layout_index = container.index(
            "hostingController.view.layoutIfNeeded()"
        )
        flush_index = container.index("CATransaction.flush()")
        async_index = container.index(
            "DispatchQueue.main.async { [weak self] in"
        )
        spring_index = container.index("self?.startOpeningSpring()")
        self.assertLess(layout_index, flush_index)
        self.assertLess(flush_index, async_index)
        self.assertLess(async_index, spring_index)
        apply = container.split("private func apply(progress:", 1)[1].split(
            "private func finishMotion", 1
        )[0]
        self.assertIn("if reducesMotion {", apply)
        self.assertIn("motionView.transform = .identity", apply)
        self.assertIn("cardView.layer.cornerRadius = 0", apply)
        dismissal = container.split("if dismisses {", 1)[1].split(
            "} else if reducesMotion", 1
        )[0]
        self.assertIn("if reducesMotion {", dismissal)
        self.assertIn("collapse()", dismissal)

    def test_layout_changes_terminate_motion(self):
        container = (
            ROOT
            / "MeloX/Features/Player/NowPlaying/NowPlayingPresentationView.swift"
        ).read_text()
        layout = container.split(
            "override func viewDidLayoutSubviews()", 1
        )[1].split("override func viewSafeAreaInsetsDidChange()", 1)[0]
        self.assertIn("if isDismissing {", layout)
        self.assertIn("finishDismissal()", layout)
        self.assertIn("setTransit(false)", layout)

    @unittest.skipUnless(shutil.which("swiftc"), "Swift compiler unavailable")
    def test_card_spring_and_radius_math(self):
        harness = r"""
import Foundation

let heights = [320.0, 667.0, 970.0, 1366.0]

func radiusAt(
    _ time: Double,
    start: Double,
    target: Double,
    velocity: Double,
    spring: LyricPhysicalSpringParameters,
    height: Double
) -> Double {
    let progress = NowPlayingCardMotionMath.progress(
        from: start,
        to: target,
        initialVelocity: velocity,
        parameters: spring,
        at: time
    )
    return NowPlayingPresentationDrag.topCornerRadius(
        offset: progress * height,
        height: height
    )
}

for height in heights {
    let closing = NowPlayingCardMotionMath.closingSpring
    let opening = NowPlayingCardMotionMath.openingSpring

    precondition(closing.stiffness == 329 && closing.damping == 28.9)
    precondition(opening.stiffness == 329 && opening.damping == 36.2)

    let cases: [(Double, Double, Double, LyricPhysicalSpringParameters)] = [
        (0, 1, 0, closing),
        (0, 1, 0.8, closing),
        (1, 0, 0, opening),
        (0.4, 0, 0.5, opening),
        (0.4, 1, 1.2, closing),
        (0.01, 0, 2, opening),
        (0.4, 0, -8, opening),
        (-0.08, 0, -2, opening),
    ]

    for (start, target, velocity, spring) in cases {
        let duration = NowPlayingCardMotionMath.settlingDuration(
            from: start,
            to: target,
            initialVelocity: velocity,
            parameters: spring
        )
        precondition(duration.isFinite && duration >= 0.12 && duration <= 1.5)
        precondition(
            abs(NowPlayingCardMotionMath.progress(
                from: start,
                to: target,
                initialVelocity: velocity,
                parameters: spring,
                at: 0
            ) - start) < 1e-9
        )
        let settled = NowPlayingCardMotionMath.progress(
            from: start,
            to: target,
            initialVelocity: velocity,
            parameters: spring,
            at: duration
        )
        precondition(abs(settled - target) <= 0.01)
        precondition(
            NowPlayingCardMotionMath.velocity(
                from: start,
                to: target,
                initialVelocity: velocity,
                parameters: spring,
                at: duration
            ).isFinite
        )

        let frames = NowPlayingCardMotionMath.radiusKeyframes(
            from: start,
            to: target,
            initialVelocity: velocity,
            parameters: spring,
            height: height
        )
        precondition(frames.keyTimes.count == frames.radii.count)
        precondition(frames.keyTimes.count <= 4096)
        precondition(abs(frames.keyTimes.first! - 0) < 1e-9)
        precondition(abs(frames.keyTimes.last! - 1) < 1e-9)
        precondition(
            frames.radii.first!
                == NowPlayingPresentationDrag.topCornerRadius(
                    offset: start * height,
                    height: height
                )
        )
        precondition(
            frames.radii.last!
                == NowPlayingPresentationDrag.topCornerRadius(
                    offset: target * height,
                    height: height
                )
        )
        var previous = -1.0
        for time in frames.keyTimes {
            precondition(time >= previous)
            previous = time
        }
        for index in 0..<(frames.keyTimes.count - 1) {
            // Independent dense interpolation checks, not the sampler's probes.
            for tick in 1..<20 {
                let fraction = Double(tick) / 20
                let offset = frames.offsets[index] + (frames.offsets[index+1] - frames.offsets[index]) * fraction
                let expected = NowPlayingPresentationDrag.topCornerRadius(offset: offset, height: height)
                let interpolated = frames.radii[index] + (frames.radii[index+1] - frames.radii[index]) * fraction
                precondition(abs(expected - interpolated) <= 0.06)
            }
        }
    }

    let midRadius = NowPlayingPresentationDrag.topCornerRadius(
        offset: height * 0.38,
        height: height
    )
    precondition(abs(midRadius - 23.65) < 0.2)
    precondition(
        NowPlayingPresentationDrag.topCornerRadius(
            offset: 0,
            height: height
        ) == 0
    )
    precondition(
        NowPlayingPresentationDrag.topCornerRadius(
            offset: height,
            height: height
        ) == 34
    )
}

precondition(
    abs(NowPlayingCardMotionMath.normalizedInitialVelocity(
        velocity: 2,
        from: 0.4,
        to: 1
    ) - 20.0 / 6.0) < 1e-9
)
precondition(
    NowPlayingCardMotionMath.normalizedInitialVelocity(
        velocity: 2,
        from: 0.4,
        to: 0
    ) < 0
)
precondition(
    NowPlayingCardMotionMath.normalizedInitialVelocity(
        velocity: 2,
        from: 0.4,
        to: 0.4
    ) == 0
)
precondition(
    NowPlayingCardMotionMath.normalizedInitialVelocity(
        velocity: .infinity,
        from: 0,
        to: 1
    ) == 0
)
print("Card spring and radius math passed: paired displacement, error-bounded radius samples, release velocity")
"""
        with tempfile.TemporaryDirectory() as directory:
            swift = Path(directory) / "main.swift"
            executable = Path(directory) / "card-motion-checks"
            swift.write_text(harness)
            subprocess.run([
                "swiftc", "-swift-version", "5",
                str(ROOT / "MeloX/Core/Lyrics/LyricPhysicalSpringParameters.swift"),
                str(ROOT / "MeloX/Features/Player/NowPlaying/NowPlayingPresentationDrag.swift"),
                str(ROOT / "MeloX/Features/Player/NowPlaying/NowPlayingCardMotionMath.swift"),
                str(swift), "-o", str(executable),
            ], check=True)
            subprocess.run([str(executable)], check=True)
    def test_sidebar_geometry_is_isolated(self):
        source = (ROOT / "MeloX/App/ContentView.swift").read_text()
        head, leaf = source.split(
            "private struct FloatingMiniPlayerBar", 1
        )
        self.assertIn(
            "@Observable\nprivate final class ContentColumnGeometryStore",
            head,
        )
        self.assertNotIn("contentColumnFrames", source)
        self.assertNotIn("frame(in: .global)", head)
        self.assertIn(
            "@State private var contentColumnGeometry = ContentColumnGeometryStore()",
            head,
        )
        self.assertIn("ContentColumnGeometryMath.horizontalBounds", head)
        self.assertIn("contentColumnGeometry.update(tab, bounds: bounds)", head)
        self.assertIn("contentColumnGeometry.retainTabs(activeTabs)", head)
        self.assertIn("contentColumnGeometry.reset()", head)
        self.assertIn("guard storedBounds[tab] != bounds else { return }", head)
        self.assertIn(
            ".coordinateSpace(.named(Self.contentColumnCoordinateSpace))",
            head,
        )
        self.assertIn("FloatingMiniPlayerBar(", head)
        self.assertNotIn("geometry.bounds(for: tab)", head)
        self.assertIn("geometry.bounds(for: tab)", leaf)
        self.assertIn(
            "let columnWidth = max(0, rootWidth - leading - trailing)",
            leaf,
        )
        self.assertIn(".ignoresSafeArea(.all, edges: .bottom)", leaf)

        geometry = (ROOT / "MeloX/App/ContentColumnGeometry.swift").read_text()
        bounds = geometry.split(
            "struct ContentColumnHorizontalBounds", 1
        )[1].split("}", 1)[0]
        self.assertIn("let minX: Double", bounds)
        self.assertIn("let maxX: Double", bounds)
        self.assertNotIn("minY", bounds)
        self.assertNotIn("let height", bounds)
        self.assertIn("(minX * scale).rounded() / scale", geometry)
        self.assertIn("(maxX * scale).rounded() / scale", geometry)

    @unittest.skipUnless(shutil.which("swiftc"), "Swift compiler unavailable")
    def test_column_geometry_quantization(self):
        harness = r"""
import Foundation

let halfPoint = ContentColumnGeometryMath.horizontalBounds(
    minX: 10.24, maxX: 100.26, displayScale: 2
)!
precondition(halfPoint.minX == 10.0)
precondition(halfPoint.maxX == 100.5)
precondition(
    ContentColumnGeometryMath.horizontalBounds(
        minX: 10.24, maxX: 100.26, displayScale: 2
    ) == halfPoint
)
precondition(
    ContentColumnGeometryMath.horizontalBounds(
        minX: 10.25, maxX: 100.25, displayScale: 2
    )!.minX == 10.5
)
precondition(
    ContentColumnGeometryMath.horizontalBounds(
        minX: 10.249, maxX: 100.249, displayScale: 2
    )!.minX == 10.0
)
precondition(
    ContentColumnGeometryMath.horizontalBounds(
        minX: 10, maxX: 9, displayScale: 2
    ) == nil
)
precondition(
    ContentColumnGeometryMath.horizontalBounds(
        minX: .nan, maxX: 9, displayScale: 2
    ) == nil
)
let unscaled = ContentColumnGeometryMath.horizontalBounds(
    minX: 10.4, maxX: 10.6, displayScale: 0
)!
precondition(unscaled.minX == 10.0 && unscaled.maxX == 11.0)
precondition(MusicCollectionWidthPolicy.wideWidth(709.99) == nil)
precondition(MusicCollectionWidthPolicy.wideWidth(710) == 710)
precondition(MusicCollectionWidthPolicy.wideWidth(711.9) == 711.9)
precondition(MusicCollectionWidthPolicy.wideWidth(712) == 712)
precondition(MusicCollectionWidthPolicy.wideWidth(970.5) == 970.5)
print("Column geometry policy passed: pixel geometry equality and continuous collection width")
"""
        with tempfile.TemporaryDirectory() as directory:
            swift = Path(directory) / "main.swift"
            executable = Path(directory) / "column-geometry-checks"
            swift.write_text(harness)
            subprocess.run([
                "swiftc", "-swift-version", "5",
                str(ROOT / "MeloX/App/ContentColumnGeometry.swift"),
                str(ROOT / "MeloX/Shared/Media/MusicCollectionWidthPolicy.swift"),
                str(swift), "-o", str(executable),
            ], check=True)
            subprocess.run([str(executable)], check=True)

    @unittest.skipUnless(shutil.which("swiftc"), "Swift compiler unavailable")
    def test_artwork_cache_and_backdrop_sizing_policy(self):
        harness = r"""
import Foundation
precondition(ArtworkImageCachePolicy.shouldReplace(existingCost: nil, newCost: 1))
precondition(ArtworkImageCachePolicy.shouldReplace(existingCost: 100, newCost: 200))
precondition(!ArtworkImageCachePolicy.shouldReplace(existingCost: 200, newCost: 100))
precondition(ArtworkImageCachePolicy.shouldReplace(existingCost: 200, newCost: 200))
precondition(ArtworkBackdropSizing.pixelDimension(longestPixel: 0) == 512)
precondition(ArtworkBackdropSizing.pixelDimension(longestPixel: 500) == 512)
precondition(ArtworkBackdropSizing.pixelDimension(longestPixel: 640) == 640)
precondition(ArtworkBackdropSizing.pixelDimension(longestPixel: 1000) == 1008)
precondition(ArtworkBackdropSizing.pixelDimension(longestPixel: 1024) == 1024)
precondition(ArtworkBackdropSizing.pixelDimension(longestPixel: 4000) == 1024)
precondition(ArtworkBackdropSizing.pixelDimension(longestPixel: .nan) == 512)
precondition(ArtworkBackdropSizing.quantized(dimension: 641) == 656)
print("Artwork cache/sizing policy passed: best resolution and bounded backdrop decode")
"""
        with tempfile.TemporaryDirectory() as directory:
            swift = Path(directory) / "main.swift"
            executable = Path(directory) / "artwork-policy-checks"
            swift.write_text(harness)
            subprocess.run([
                "swiftc", "-swift-version", "5",
                str(ROOT / "MeloX/Shared/Media/ArtworkImageCachePolicy.swift"),
                str(swift), "-o", str(executable),
            ], check=True)
            subprocess.run([str(executable)], check=True)

if __name__ == "__main__":
    unittest.main()

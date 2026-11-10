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

    def test_presentation_uses_shared_offset_policy(self):
        view = (ROOT / "MeloX/Features/Player/NowPlaying/NowPlayingPresentationView.swift").read_text()
        self.assertIn("NowPlayingPresentationDrag.topCornerRadius", view)
        self.assertIn("NowPlayingPresentationDrag.velocityScale", view)
        self.assertIn("let overhang = max(0, -offset)", view)
        self.assertIn("height: window.size.height + overhang", view)
        self.assertIn(".frame(width: window.size.width, height: window.size.height)", view)
        self.assertNotIn("Color.black", view)
        self.assertNotIn("roundsTopCorners", view)
        self.assertNotIn("dragOrigin != nil ? 1", view)
        self.assertIn("model.beginDrag(", view)
        self.assertIn("model.updateDrag(", view)
        self.assertIn("model.endDrag(", view)

    def test_player_content_is_constructed_outside_timeline(self):
        source = (ROOT / "MeloX/Features/Player/NowPlaying/NowPlayingPresentationView.swift").read_text()
        host, modifier = source.split(
            "private struct NowPlayingCardPresentationModifier", 1
        )
        self.assertIn("@Observable\nfinal class NowPlayingCardModel", source)
        self.assertNotIn("private(set) var backgroundExtension", source)
        self.assertIn(".environment(\\.nowPlayingBackgroundExtension, overhang)", source)
        self.assertIn("NowPlayingView(", host)
        self.assertEqual(source.count("NowPlayingView("), 1)
        self.assertIn("NowPlayingCardPresentationModifier(", host)
        self.assertIn("TimelineView", modifier)
        self.assertIn("func body(content: Content)", modifier)
        self.assertIn("\n                    content\n", modifier)
        self.assertNotIn("NowPlayingView(", modifier)
        for call in (
            "model.beginDrag(",
            "model.updateDrag(",
            "model.endDrag(",
            "model.collapse()",
        ):
            self.assertIn(call, modifier)
        self.assertIn("model.settle(requestID: requestID)", modifier)

    def test_background_extension_is_isolated_to_leaf(self):
        source = (ROOT / "MeloX/Features/Player/NowPlaying/NowPlayingView.swift").read_text()
        head, leaf = source.split(
            "private struct NowPlayingBackgroundLayer", 1
        )
        self.assertIn("NowPlayingBackgroundLayer(", head)
        self.assertNotIn("model.backgroundExtension", head)
        self.assertNotIn("let backgroundExtension: CGFloat", head)
        self.assertNotIn("let cardModel: NowPlayingCardModel", head)
        self.assertIn("@Environment(\\.nowPlayingBackgroundExtension)", leaf)
        self.assertIn("height: size.height + backgroundExtension", leaf)
        self.assertIn(
            "width: size.width,\n            height: size.height,\n            alignment: .top",
            leaf,
        )

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

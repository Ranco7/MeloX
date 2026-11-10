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
        self.assertIn("backgroundExtension: overhang", view)
        self.assertNotIn("Color.black", view)
        player = (ROOT / "MeloX/Features/Player/NowPlaying/NowPlayingView.swift").read_text()
        self.assertIn("height: proxy.size.height + backgroundExtension", player)
        self.assertIn("height: proxy.size.height, alignment: .top", player)
        self.assertNotIn("roundsTopCorners", view)
        self.assertNotIn("dragOrigin != nil ? 1", view)

if __name__ == "__main__":
    unittest.main()

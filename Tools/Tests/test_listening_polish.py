"""Focused source guards plus production Swift behavior checks when available.

Run: python3 -m unittest Tools.Tests.test_listening_polish -v
Source checks do not establish SwiftUI rendering, touch behavior, or device capture.
"""
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text()


class ListeningSourceChecks(unittest.TestCase):
    def test_own_audio_uses_existing_mixer_callback(self):
        capture = read("MeloX/Features/SongRecognition/SongRecognitionAppAudioCapture.swift")
        recorder = read("MeloX/Features/SongRecognition/SongRecognitionAudioRecorder.swift")
        deck = read("MeloX/Core/Playback/Engine/AudioPlaybackDeck.swift")
        self.assertIn('frameFiltering.add(entry: "melox.recognition")', deck)
        self.assertIn("playbackAudioCapture.append(buffer, from: sourceID)", deck)
        self.assertNotIn("installTap", capture)
        self.assertNotIn("ReplayKit", capture)
        self.assertNotIn("ScreenCaptureKit", recorder)
        self.assertIn("guard source == .appAudio, let playbackAudio", recorder)
        self.assertNotIn("Task {", capture, "PCM callbacks must not enqueue per-buffer UI work")
        engine = read("MeloX/Core/Playback/Engine/AudioPlaybackEngine.swift")
        self.assertIn("activeDeck.state == .playing ? activeDeck.captureSourceID : nil", engine)
        view = read("MeloX/Features/SongRecognition/SongRecognitionView.swift")
        self.assertIn("playbackAudio: player.playbackAudioCapture", view)
        self.assertIn("== .microphone, player.isPlaying", view)

    def test_capture_claims_and_adaptive_states(self):
        source = read("MeloX/Core/Settings/Recognition/SongRecognitionAudioSource.swift")
        available = source.split("static var availableCases", 1)[1].split("var title", 1)[0]
        self.assertIn("return [.microphone, .appAudio]", available)
        self.assertNotIn("return allCases", available)
        view = read("MeloX/Features/SongRecognition/SongRecognitionView.swift")
        self.assertIn("ScrollView {", view)
        self.assertIn(".defaultScrollAnchor(.center, for: .alignment)", view)
        self.assertNotIn("maxHeight: .infinity", view)
        for language in ["zh-Hans", "en"]:
            strings = read(f"MeloXLocalization/{language}.lproj/Localizable.strings")
            line = next(line for line in strings.splitlines() if line.startswith('"ui.recognition.source.appAudio.detail"'))
            self.assertIn("无法读取其他 App" if language == "zh-Hans" else "not accessible", line)

    def test_favorites_are_observed_and_centralized(self):
        library = read("MeloX/Core/Library/LibraryStore.swift")
        self.assertNotRegex(library, r"@ObservationIgnored\s+private var favoriteSongIDSet")
        for kind in ["song", "playlist", "album", "artist", "podcast"]:
            self.assertIn(f"favoriteActions.toggle(.{kind}(", library)
        toggles = library.split("func toggle(song:", 1)[1].split("private func prepareFavoriteAction", 1)[0]
        self.assertNotIn("errorMessage =", toggles)
        self.assertGreaterEqual(library.count("reapplyFavoriteActions(readRevision:"), 7)
        for path in (ROOT / "MeloX/Features").rglob("*.swift"):
            self.assertNotRegex(path.read_text(), r"api\.set(?:SongLiked|PlaylistSubscribed|AlbumSubscribed|ArtistFollowed|PodcastSubscribed)")
        for name in ["Artist/ArtistDetailView", "Album/AlbumDetailView", "Podcasts/PodcastDetailView"]:
            detail = read(f"MeloX/Features/{name}.swift")
            self.assertNotRegex(detail, r"@State private var (?:isFollowed|isSubscribed|isSubscribing|isUpdatingSubscription)")
            self.assertIn("library.favoriteRead()", detail)
        actions = read("MeloX/Features/Player/NowPlaying/NowPlayingSongActions.swift")
        self.assertIn('? "star.fill"', actions)
        self.assertIn('library.contains(song: song) ? "heart.slash" : "heart"', read("MeloX/Shared/Media/TrackRowView.swift"))

    def test_shared_feedback_has_no_competing_gestures_or_layout(self):
        source = read("MeloX/Shared/Components/SoftPressFeedback.swift")
        self.assertIn("configuration.isPressed", source)
        self.assertIn("style: .continuous", source)
        self.assertIn("accessibilityReduceMotion", source)
        for forbidden in ["@State", "Gesture(", "Timer", "GeometryReader", ".blur(", ".scaleEffect("]:
            self.assertNotIn(forbidden, source)
        for name in ["Library/LibrarySongsView", "Library/LibraryHistoryView", "Library/LibraryDownloadsView",
                     "Cloud/CloudMusicView", "Home/DailySongsView", "Search/SearchView", "Player/Queue/QueueView",
                     "Artist/ArtistDetailView", "Playlist/PlaylistTrackList", "SongRecognition/SongRecognitionView",
                     "Podcasts/PodcastComponents"]:
            self.assertIn(".buttonStyle(MusicTrackPressStyle())", read(f"MeloX/Features/{name}.swift"))

    def test_search_keeps_readable_font_and_target(self):
        search = read("MeloX/Shared/Components/MusicCollectionScrollView.swift")
        self.assertIn("@ScaledMetric(relativeTo: .body)", search)
        self.assertIn("searchFontSize: CGFloat = 17", search)
        self.assertRegex(search, r"TextField\(prompt, text: \$query\)\s+\.font\(\.body\)")
        self.assertIn(".frame(width: 44, height: 44)", search)
        self.assertIn("searchFocused || !query.isEmpty || dynamicTypeSize.isAccessibilitySize", search)
        self.assertIn(".accessibilityLabel(prompt)", search)
        self.assertNotIn("38", search)
        for name in ["Features/Search/SearchView.swift", "Features/Library/LibraryView.swift",
                     "Features/Podcasts/PodcastDetailView.swift", "Features/Settings/Root/SettingsView.swift"]:
            self.assertIn("searchable(", read("MeloX/" + name))

    def test_lyric_feedback_preserves_gutter_and_uses_background_only(self):
        interaction = read("MeloX/Features/Player/Lyrics/Shared/LyricPressInteraction.swift")
        self.assertNotIn(".scaleEffect", interaction)
        self.assertNotIn("@State private var backgroundProgress", interaction)
        self.assertIn(".accessibilityActions", interaction)
        lyric = read("MeloX/Features/Player/Lyrics/Shared/SynchronizedLyricText.swift")
        self.assertIn("interactionBackgroundVisualOverflow: CGFloat = 16", lyric)
        self.assertIn(".background(alignment: .topLeading)", lyric)
        self.assertIn(".padding(-CGFloat(PressFeedbackPolicy.lyricInternalInset) / effectiveVisualScale)", lyric)


class SwiftBehaviorChecks(unittest.TestCase):
    def run_swift(self, sources):
        with tempfile.TemporaryDirectory(prefix=".listening-checks-", dir=ROOT) as directory:
            binary = str(Path(directory) / "checks")
            subprocess.run(["swiftc", "-swift-version", "5", "-parse-as-library",
                            *[str(ROOT / source) for source in sources], "-o", binary], check=True)
            subprocess.run([binary], check=True, timeout=30)

    @unittest.skipUnless(shutil.which("swiftc"), "Swift compiler unavailable")
    def test_favorite_race_rollback_and_refresh(self):
        self.run_swift(["MeloX/Core/Library/OptimisticFavoriteActions.swift",
                        "Tests/Library/OptimisticFavoriteChecks.swift"])

    @unittest.skipUnless(shutil.which("swiftc"), "Swift compiler unavailable")
    def test_search_and_feedback_policies(self):
        self.run_swift(["MeloX/Shared/Media/MusicCollectionSearchLayout.swift",
                        "MeloX/Shared/Media/MusicCollectionWidthPolicy.swift",
                        "MeloX/Core/Settings/Playback/PlayerVolumeControlMode.swift",
                        "MeloX/Shared/Components/PressFeedbackPolicy.swift",
                        "Tests/Player/MusicCollectionSearchLayoutChecks.swift"])

    @unittest.skipUnless(sys.platform == "darwin" and shutil.which("swiftc"), "Requires macOS AVFoundation SDK")
    def test_playback_pcm_capture(self):
        self.run_swift(["MeloX/Core/Playback/Engine/PlaybackAudioCapture.swift",
                        "MeloX/Features/SongRecognition/SongRecognitionSampleBuffer.swift",
                        "MeloX/Features/SongRecognition/SongRecognitionCapturedAudioBuffer.swift",
                        "MeloX/Features/SongRecognition/SongRecognitionAppAudioCapture.swift",
                        "Tests/SongRecognition/PlaybackCaptureChecks.swift"])

    @unittest.skipUnless(sys.platform == "darwin" and shutil.which("swiftc"), "Requires macOS AVFoundation SDK")
    def test_recognition_failure_cancel_and_states(self):
        self.run_swift(["MeloX/Core/Playback/Engine/PlaybackAudioCapture.swift",
                        "MeloX/Core/Settings/Recognition/SongRecognitionAudioSource.swift",
                        "MeloX/Core/Settings/Recognition/SongRecognitionPreferences.swift",
                        "MeloX/Core/Models/Networking/AudioMatchResponse.swift",
                        "MeloX/Features/SongRecognition/SongRecognitionRecording.swift",
                        "MeloX/Features/SongRecognition/SongRecognitionResult.swift",
                        "MeloX/Features/SongRecognition/SongRecognitionStore.swift",
                        "Tests/SongRecognition/RecognitionStateChecks.swift"])


if __name__ == "__main__":
    unittest.main()

"""Run the real song-loading methods with a synchronous outgoing-clock callback.

Uses only Python and the Swift command-line tools; no Xcode, network or account.
"""

from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


def method(source, signature):
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


STUBS = r"""
struct Song { var id = 2; let durationMS = 300_000 }
struct PlaybackSource { let quality = 1 }
struct PlaybackIssue { init(song: Song, error: Error) {} }
struct Queue {
    var songs = [Song()]
    var index = 0
    var currentSong: Song? { songs[index] }
    mutating func replace(with songs: [Song], startingAt index: Int) {
        self.songs = songs
        self.index = index
    }
    mutating func select(index: Int) -> Bool {
        self.index = index
        return true
    }
}
struct Downloads {
    func localPlaybackSource(songID: Int) -> PlaybackSource? { nil }
}
@MainActor final class API {
    var beforeResolution: (() -> Void)?
    var holdsResolution = false
    var resolutionStarted: CheckedContinuation<Void, Never>?
    var pendingResolution: CheckedContinuation<Void, Never>?
    func playbackSource(id: Int) async throws -> PlaybackSource {
        beforeResolution?()
        if holdsResolution {
            await withCheckedContinuation {
                pendingResolution = $0
                resolutionStarted?.resume()
                resolutionStarted = nil
            }
        }
        return PlaybackSource()
    }
    func playbackSource(for song: Song) async throws -> PlaybackSource {
        try await playbackSource(id: song.id)
    }
    func waitForResolution() async {
        if pendingResolution == nil {
            await withCheckedContinuation { resolutionStarted = $0 }
        }
    }
}
@MainActor final class Engine {
    var onOutgoingClock: (() -> Void)?
    var loadedPosition: Double?
    var loadedAutoplay: Bool?
    var pendingSeek: Double?
    var hasCurrentItem: Bool { loadedPosition != nil }
    func unload() {
        // The real engine pauses the outgoing deck before clearing it. A
        // playing -> paused transition publishes its final playback sample.
        onOutgoingClock?()
        loadedPosition = nil
        pendingSeek = nil
    }
    func load(_ source: PlaybackSource, startAt: Double, autoplay: Bool) async {
        loadedPosition = pendingSeek ?? startAt
        pendingSeek = nil
        loadedAutoplay = autoplay
    }
    func seek(to position: Double) {
        if !hasCurrentItem { pendingSeek = position }
    }
    func play() {}
    func pause() {}
}
@MainActor final class Store {
    var playbackQueue = Queue()
    var loadGeneration = 0
    var playbackRecoveryAttempts = 0
    enum TransportCommand { case goTo, pause, progress }
    var onListenTogetherTransport: ((TransportCommand, Int?) -> Void)?
    var onListenTogetherQueueEdit: (() -> Void)?
    var currentSong: Song?
    var detailedPlaybackSongs: [Int: Song] = [:]
    var duration: Double = 300
    var progress: Double = 73
    var playbackTimelineClock = PlaybackTimelineClock()
    var isResolvingSource = false
    var isLoading = false
    var isPlaying = true
    var isUsingDownloadedSource = false
    var isUsingCachedPlaybackSource = false
    var isHandingOffToCachedSource = false
    var pendingCachedHandoffPosition: TimeInterval?
    var cachedHandoffToken: UUID?
    var cancelTrackCachePreparationCount = 0
    var startTrackCachePreparationCount = 0
    var currentPlaybackSource: PlaybackSource?
    var effectivePlaybackQuality: Int?
    var currentLoadShouldAutoplay = false
    var playbackIssue: PlaybackIssue?
    var nowPlayingLyricsSongID: Int?
    var nowPlayingLyrics: [Int] = []
    var publishedNowPlayingLyricID: Int?
    var currentIndex: Int { playbackQueue.index }
    var queue: [Song] { playbackQueue.songs }
    var nowPlayingLyricsDisplaySettings = 0
    var listenTogetherLoadTask: Task<Void, Never>?
    var isHeartModeActive = false
    var listenTogetherPlayModeTouched = false
    var hasRecordedCurrentStart = false
    var historySourceID: Int?
    var seekRevision = 0
    let engine = Engine()
    let api = API()
    let downloads = Downloads()
    let nowPlayingSession = Session()
    func cancelAutoMixPreparation() {}
    func cancelTrackCachePreparation() {
        cancelTrackCachePreparationCount += 1
    }
    func startTrackCachePreparationIfNeeded() {
        startTrackCachePreparationCount += 1
    }
    func resolveCurrentSongAudioAvailability(for song: Song, generation: Int) {}
    func resetBeatAnalysis() {}
    func updateNowPlayingState(forceNowPlayingLyrics: Bool = false, forceLyricsLiveActivity: Bool = false) {}
    func persistSnapshot() {}
    func applyListenTogetherPlayMode(_: String?) {}
    func recordCurrentPlayback() {}
    func shouldUseCachedSourceForSeek() -> Bool { false }
    func beginCachedSourceHandoff(at position: Double) {}
    struct Session {
        func setSong(_ song: Song, duration: Double, queueIndex: Int,
                     queueCount: Int, lyricsDisplaySettings: Int) {}
    }
    func playbackSourceRetryingTransientFailure(
        for song: Song, cachedDetailedSong: Song?, generation: Int
    ) async throws -> PlaybackSource {
        try await api.playbackSource(id: song.id)
    }
    func run(startAt: Double, autoplay: Bool) async {
        await loadCurrentSong(autoplay: autoplay, startAt: startAt)
    }
    func runTransportCheck() async -> Bool {
        var trackReports = 0
        var queueReports = 0
        onListenTogetherTransport = { _, _ in trackReports += 1 }
        onListenTogetherQueueEdit = { queueReports += 1 }

        await loadCurrentSong(autoplay: true)
        guard trackReports == 0, queueReports == 0 else { return false }

        await loadCurrentSong(autoplay: true, reportsToRoom: true, queueChanged: true)
        return trackReports == 1 && queueReports == 1
    }

    func runRemoteTransportCheck() async -> Bool {
        var reports = 0
        onListenTogetherTransport = { _, _ in reports += 1 }
        api.holdsResolution = true
        applyRoomPlayback(at: 0, isPlaying: true)
        await api.waitForResolution()
        seek(to: 10)
        applyRoomPlayback(at: 55, isPlaying: false)
        api.pendingResolution?.resume()
        api.pendingResolution = nil
        await listenTogetherLoadTask?.value
        return engine.loadedPosition == 55 && engine.loadedAutoplay == false && reports == 1
    }

    private func applyRoomPlayback(at position: Double, isPlaying: Bool) {
        let song = Song(id: 23)
#if IOS_LISTEN_TOGETHER
        synchronizeListenTogetherPlayback(
            songs: [song], targetSongID: song.id, progress: position,
            isPlaying: isPlaying, adoptsRoomPlayMode: false, playMode: nil
        )
#else
        synchronizeListenTogetherPlayback(
            songs: [song], targetSongID: song.id, progress: position,
            isPlaying: isPlaying, playMode: nil
        )
#endif
    }
    func seekWhileResolving(to position: Double) {
        progress = position
        reanchorPlaybackTimeline(to: position, rate: 0)
    }
    // SOURCE_METHODS
}

@main struct Regression {
    @MainActor static func main() async {
        let hasTrackCacheHooks = // HAS_TRACK_CACHE_HOOKS
        var failures = 0
        for playing in [true, false] {
            for start in [0.0, 42.0] {
                for seekDuringResolution in [false, true] {
                    for autoplay in [true, false] {
                        let store = Store()
                        if hasTrackCacheHooks {
                            store.isUsingCachedPlaybackSource = true
                            store.isHandingOffToCachedSource = true
                            store.pendingCachedHandoffPosition = 99
                            store.cachedHandoffToken = UUID()
                        }
                        if playing {
                            store.engine.onOutgoingClock = {
                                store.seekWhileResolving(to: 73)
                            }
                        }
                        if seekDuringResolution {
                            store.api.beforeResolution = {
                                store.seekWhileResolving(to: 15)
                            }
                        }
                        await store.run(startAt: start, autoplay: autoplay)
                        let expected = seekDuringResolution ? 15.0 : start
                        if store.engine.loadedPosition != expected ||
                           store.engine.loadedAutoplay != autoplay {
                            print("FAIL playing=\(playing) startAt=\(start) seek=\(seekDuringResolution) autoplay=\(autoplay): expected \(expected), got \(store.engine.loadedPosition ?? -1)")
                            failures += 1
                        }
                        let handoffReset =
                            !store.isUsingCachedPlaybackSource &&
                            !store.isHandingOffToCachedSource &&
                            store.pendingCachedHandoffPosition == nil &&
                            store.cachedHandoffToken == nil
                        let cacheLifecycle =
                            store.cancelTrackCachePreparationCount == 1 &&
                            store.startTrackCachePreparationCount ==
                                (autoplay ? 1 : 0)
                        if hasTrackCacheHooks && (!handoffReset || !cacheLifecycle) {
                            print("FAIL cache lifecycle playing=\(playing) startAt=\(start) seek=\(seekDuringResolution) autoplay=\(autoplay): reset=\(handoffReset) cancel=\(store.cancelTrackCachePreparationCount) start=\(store.startTrackCachePreparationCount)")
                            failures += 1
                        }
                    }
                }
            }
        }
        let reportsCorrectly = await Store().runTransportCheck()
        if !reportsCorrectly { failures += 1 }
        if await !Store().runRemoteTransportCheck() {
            print("FAIL: late remote pause and seek did not update the pending source load without echoing")
            failures += 1
        }
        if failures > 0 { exit(1) }
        print("PASS: 16 song-load scenarios, local reports, and a remote pause/seek during source resolution")
    }
}
"""


class SongSwitchTests(unittest.TestCase):
    def test_listen_together_polling_and_reports(self):
        harness = ROOT / "Tests/Playback/ListenTogetherSyncChecks.swift"
        for app in ("MeloXDesktop", "MeloX"):
            with self.subTest(app=app), tempfile.TemporaryDirectory() as directory:
                core = ROOT / app / "Core"
                session = core / "Playback/Session"
                sources = [
                    *sorted(session.glob("ListenTogetherStore*.swift")),
                    core / "Models/Social/ListenTogetherModels.swift",
                    core / "Networking/NeteaseListenTogetherAPI.swift",
                    harness,
                ]
                flags = ["-D", "IOS_LISTEN_TOGETHER"] if app == "MeloX" else []
                executable = Path(directory) / "regression"
                compile_result = subprocess.run(
                    ["swiftc", "-parse-as-library", *flags, *map(str, sources), "-o", str(executable)],
                    capture_output=True, text=True,
                )
                self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
                result = subprocess.run([str(executable)], capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                print(f"{app}: {result.stdout.strip()}")

    def test_outgoing_progress_cannot_override_new_song_position(self):
        for app in ("MeloXDesktop", "MeloX"):
            with self.subTest(app=app), tempfile.TemporaryDirectory() as directory:
                session = ROOT / app / "Core/Playback/Session"
                source = (session / "PlayerStore.swift").read_text()
                signatures = (
                    "private func loadCurrentSong(",
                    "private func prepareCurrentSongLoad(",
                    "private func resolveCurrentSongLoad(",
                    "func synchronizeListenTogetherPlayback(",
                    "private func adoptListenTogetherQueue(",
                    "func seek(",
                    "func estimatedProgress(",
                    "private var playbackDurationLimit:",
                    "private func clampedPlaybackPosition(",
                    "private func reanchorPlaybackTimeline(",
                )
                methods = "\n".join(method(source, sig) for sig in signatures)
                has_cache_hooks = "cancelTrackCachePreparation()" in methods
                swift = Path(directory) / "main.swift"
                swift.write_text(
                    (session / "PlaybackTimelineClock.swift").read_text()
                    + STUBS
                    .replace("// SOURCE_METHODS", methods)
                    .replace(
                        "// HAS_TRACK_CACHE_HOOKS",
                        "true" if has_cache_hooks else "false",
                    )
                )
                executable = Path(directory) / "regression"
                flags = ["-D", "IOS_LISTEN_TOGETHER"] if app == "MeloX" else []
                compile_result = subprocess.run(
                    ["swiftc", "-parse-as-library", *flags, str(swift), "-o", str(executable)],
                    capture_output=True, text=True,
                )
                self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
                result = subprocess.run([str(executable)], capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                print(f"{app}: {result.stdout.strip()}")


if __name__ == "__main__":
    unittest.main()

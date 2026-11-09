"""Static regression checks for the device-round-2 fixes.

These checks do not compile Swift. They pin the source-level invariants that
would silently regress the fixes: the playback cache policy, stable track-row
identity, collection-action visibility, floating mini-player placement, and
the artwork cache keys.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


def read(relative: str) -> str:
    return (ROOT / relative).read_text()


class PlaybackTrackCacheChecks(unittest.TestCase):
    def test_bounded_whole_track_cache(self):
        source = read("MeloX/Core/Playback/Cache/PlaybackTrackCache.swift")
        self.assertIn("maximumCacheBytes", source)
        self.assertIn("512 * 1_024 * 1_024", source)
        self.assertIn("maximumTrackBytes", source)
        self.assertIn("128 * 1_024 * 1_024", source)
        self.assertIn("minimumFreeDiskBytes", source)
        self.assertIn("volumeAvailableCapacityForImportantUsage", source)
        self.assertIn("maximumAge", source)
        self.assertIn("catch is CancellationError", source)
        self.assertNotIn("URLSession.shared.download", source)
        self.assertNotIn("reloadIgnoringLocalCacheData", source)

    def test_transfer_is_capped_during_streaming(self):
        source = read("MeloX/Core/Playback/Cache/PlaybackTrackCache.swift")
        self.assertIn("URLSessionDataDelegate", source)
        self.assertIn("didReceive data: Data", source)
        self.assertIn("httpResponse.expectedContentLength > maximumBytes", source)
        self.assertIn("receivedBytes + Int64(data.count) <= maximumBytes", source)
        self.assertIn("dataTask.cancel()", source)
        self.assertIn("activeSongID == nil", source)
        self.assertIn("configuration.urlCache = nil", source)

    def test_cache_is_wired_and_cancelled(self):
        source = read("MeloX/Core/Playback/Session/PlayerStore.swift")
        self.assertIn("PlaybackTrackCache.shared", source)
        self.assertIn("startTrackCachePreparationIfNeeded", source)
        self.assertIn("cancelTrackCachePreparation", source)
        self.assertIn("shouldUseCachedSourceForSeek", source)
        self.assertIn("beginCachedSourceHandoff", source)
        self.assertNotIn("autoplayAfterCachedHandoff", source)
        self.assertIn("discardCachedPlaybackSource", source)
        self.assertIn("isUsingCachedPlaybackSource", source)

    def test_cached_handoff_uses_current_intent_and_token_guard(self):
        source = read("MeloX/Core/Playback/Session/PlayerStore.swift")
        handoff = source.split(
            "private func beginCachedSourceHandoff", 1
        )[1].split("private func discardCachedPlaybackSource", 1)[0]
        guard_index = handoff.index("guard self.cachedHandoffToken == token")
        intent_index = handoff.index(
            "let shouldAutoplay = self.currentLoadShouldAutoplay"
        )
        clear_index = handoff.index(
            "self.isHandingOffToCachedSource = false"
        )
        self.assertLess(guard_index, intent_index)
        self.assertLess(guard_index, clear_index)
        self.assertIn("autoplay: shouldAutoplay", handoff)

    def test_cache_storage_is_visible_and_clearable(self):
        locations = read("MeloX/Core/Storage/AppStorageLocations.swift")
        maintenance = read("MeloX/Core/Storage/StorageMaintenance.swift")
        self.assertIn("playbackCacheDirectory", locations)
        self.assertIn("PlaybackTrackCache.clearCache()", maintenance)
        self.assertIn("playbackCacheBytes", maintenance)

    def test_transfer_is_nonisolated_and_cancel_safe(self):
        source = read("MeloX/Core/Playback/Cache/PlaybackTrackCache.swift")
        self.assertIn(
            "private nonisolated final class BoundedTrackTransfer", source
        )
        self.assertIn(
            "continuation.resume(throwing: URLError(.cancelled))", source
        )
        self.assertIn("self.continuation = continuation", source)
        self.assertIn("let wasCancelled = cancelled", source)
        self.assertIn("task.resume()\n        lock.unlock()", source)
        self.assertIn(
            "guard !finished, !cancelled, let handle = fileHandle", source
        )
        self.assertIn("guard !finished else {", source)

    def test_playback_source_is_explicitly_nonisolated(self):
        for path in (
            "MeloX/Core/Playback/Queue/PlaybackSource.swift",
            "MeloXDesktop/Core/Playback/Queue/PlaybackSource.swift",
        ):
            self.assertIn(
                "nonisolated struct PlaybackSource: Equatable, Sendable",
                read(path),
            )


class LayoutGuardsChecks(unittest.TestCase):
    def test_track_rows_use_stable_identity(self):
        source = read("MeloX/Features/Playlist/PlaylistTrackList.swift")
        self.assertIn("ForEach(tracks, id: \\.id)", source)
        self.assertNotIn("ForEach(tracks.indices", source)
        self.assertIn("uniquingKeysWith:", source)

    def test_tablet_player_width_is_never_negative(self):
        source = read(
            "MeloX/Features/Player/NowPlaying/Tablet/NowPlayingTabletLayout.swift"
        )
        self.assertIn("return max(\n            min(", source)
        self.assertIn("var panelWidth: CGFloat {\n        max(", source)

    def test_collection_layout_updates_are_quantized(self):
        source = read("MeloX/Features/Playlist/PlaylistDetailContent.swift")
        self.assertIn("(width / 8).rounded(.down) * 8", source)


class CollectionActionChecks(unittest.TestCase):
    def test_owned_and_liked_playlists_hide_save_action(self):
        store = read("MeloX/Core/Library/LibraryStore.swift")
        content = read("MeloX/Features/Playlist/PlaylistDetailContent.swift")
        detail = read("MeloX/Features/Playlist/PlaylistDetailView.swift")
        self.assertIn("func canToggleSaved(_ playlist: Playlist) -> Bool", store)
        self.assertIn("playlist.id == likedPlaylistID", store)
        self.assertIn("guard let userID = profile?.id else { return true }", store)
        self.assertIn("showsSavedAction", content)
        self.assertIn("if showsSavedAction {", content)
        self.assertIn("if library.canToggleSaved(playlist)", detail)

    def test_favorite_song_rows_have_explicit_trailing_inset(self):
        source = read("MeloX/Features/Library/LibrarySongsView.swift")
        self.assertIn(".listRowInsets(", source)
        self.assertIn("trailing: 20", source)


class FloatingMiniPlayerChecks(unittest.TestCase):
    def test_bar_is_a_root_overlay_with_fixed_clearance(self):
        source = read("MeloX/App/ContentView.swift")
        player_aware = source.split(
            "private var playerAwareTabView", 1
        )[1].split("private var showsMiniPlayer", 1)[0]
        self.assertIn("floatingMiniPlayerClearance", source)
        self.assertIn(".overlay(alignment: .bottom)", player_aware)
        self.assertIn(".ignoresSafeArea(.keyboard, edges: .bottom)", player_aware)
        self.assertIn("TabletMiniPlayerView(", player_aware)
        self.assertEqual(source.count("TabletMiniPlayerView("), 1)

    def test_clearance_inset_stays_inside_the_tab(self):
        source = read("MeloX/App/ContentView.swift")
        navigation = source.split(
            "private func tabNavigation", 1
        )[1].split("private func tabRoot", 1)[0]
        self.assertIn(".safeAreaInset(edge: .bottom, spacing: 0)", navigation)
        self.assertIn("Color.clear", navigation)
        self.assertNotIn("TabletMiniPlayerView", navigation)
        self.assertNotIn(".overlay(alignment: .bottom)", navigation)

    def test_wide_layout_budget_includes_inner_padding(self):
        source = read("MeloX/App/ContentView.swift")
        player_aware = source.split(
            "private var playerAwareTabView", 1
        )[1].split("private var showsMiniPlayer", 1)[0]
        self.assertIn("floatingMiniPlayerOuterPadding * 2", player_aware)
        self.assertIn(
            "floatingMiniPlayerWideContentPadding", player_aware
        )
        self.assertIn(
            ">= TabletMiniPlayerView\n                                .minimumControlsWidth",
            player_aware,
        )

    def test_single_mini_player_layout_branch(self):
        source = read(
            "MeloX/Features/Player/MiniPlayer/TabletMiniPlayerView.swift"
        )
        self.assertNotIn("ViewThatFits", source)
        self.assertIn("static let minimumControlsWidth", source)
        self.assertIn("usesWideLayout", source)
        self.assertIn("if usesWideLayout {", source)


class ArtworkChecks(unittest.TestCase):
    def test_detail_palette_cache_uses_normalized_artwork_url(self):
        playlist = read("MeloX/Features/Playlist/PlaylistDetailView.swift")
        album = read("MeloX/Features/Album/AlbumDetailView.swift")
        navigation = read("MeloX/App/AppNavigation.swift")
        self.assertIn("context.playlistSummary.artworkURL", playlist)
        self.assertIn("context.albumSummary.artworkURL", album)
        self.assertIn("context.playlistSummary.artworkURL", navigation)
        self.assertIn("context.albumSummary.artworkURL", navigation)

    def test_thumbnail_requests_are_stable_and_memory_backed(self):
        source = read("MeloX/Shared/Media/ArtworkImage.swift")
        app = read("MeloX/App/MeloXApp.swift")
        self.assertIn("quantizedPixelLength", source)
        self.assertIn("ArtworkImageMemoryCache", source)
        self.assertNotIn("state.response", source)
        self.assertIn(".onCompletion { result in", source)
        self.assertIn("Image(uiImage: response.image)", source)
        self.assertIn("byteCost: ArtworkImageMemoryCache.byteCost(", source)
        self.assertIn("cgImage.bytesPerRow * cgImage.height", source)
        self.assertNotIn("cost: 512 * 1_024", source)
        self.assertIn("configureArtworkNetworkCache", app)
        self.assertIn("URLCache.shared = URLCache(", app)

    def test_backdrop_refresh_is_adaptive(self):
        source = read(
            "MeloX/Features/Player/NowPlaying/AppleMusicBackdrop/"
            "NowPlayingAppleMusicBackground.swift"
        )
        self.assertIn("effectiveLyricsRefreshRate", source)
        self.assertIn("isBehindLyrics\n            ? 1.0 / 60.0", source)
        self.assertIn("effectiveLyricsRefreshRate.minimumInterval", source)


if __name__ == "__main__":
    unittest.main()

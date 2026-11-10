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
        self.assertIn("uniquingKeysWith:", read("MeloX/Features/Playlist/PlaylistDetailContent.swift"))

    def test_tablet_player_width_is_never_negative(self):
        source = read(
            "MeloX/Features/Player/NowPlaying/Tablet/NowPlayingTabletLayout.swift"
        )
        self.assertIn("return max(\n            min(", source)
        self.assertIn("var panelWidth: CGFloat {\n        max(", source)

    def test_collection_layout_tracks_continuous_viewport_width(self):
        source = read("MeloX/Features/Playlist/PlaylistDetailContent.swift")
        album = read("MeloX/Features/Album/AlbumDetailContent.swift")
        for content in (source, album):
            self.assertIn("GeometryReader { viewport in", content)
            self.assertIn("MusicCollectionDetailLayout(availableWidth: viewport.size.width)", content)
            self.assertIn("let prepared = MusicCollectionPreparedTracks", content)
        shared = source.split("struct MusicCollectionDetailLayout", 1)[1].split("struct MusicCollectionTrackContent", 1)[0]
        self.assertNotIn("@State", shared)
        self.assertNotIn("onGeometryChange", shared)
        self.assertNotIn("quantized", shared)
        self.assertIn("MusicCollectionLayout.wideWidth(availableWidth)", shared)
        self.assertIn("rowWidth: width - 2 * MusicCollectionLayout.wideInset", shared)
        policy = read("MeloX/Shared/Media/MusicCollectionWidthPolicy.swift")
        self.assertIn("return width", policy)
        self.assertNotIn("rounded", policy)
        tracks = read("MeloX/Features/Playlist/PlaylistTrackList.swift")
        self.assertNotIn("tracks.map", tracks)
        self.assertNotIn("PreparedTrackIndex", tracks)
        self.assertIn("let indicesBySongID:", tracks)


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
        leaf = source.split("private struct FloatingMiniPlayerBar", 1)[1]
        self.assertIn("floatingMiniPlayerClearance", source)
        self.assertIn(".overlay(alignment: .bottom)", player_aware)
        self.assertIn(
            ".coordinateSpace(.named(Self.contentColumnCoordinateSpace))",
            player_aware,
        )
        self.assertIn("FloatingMiniPlayerBar(", player_aware)
        self.assertIn("TabletMiniPlayerView(", leaf)
        self.assertIn(".ignoresSafeArea(.all, edges: .bottom)", leaf)
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
        leaf = source.split("private struct FloatingMiniPlayerBar", 1)[1]
        self.assertIn("floatingMiniPlayerOuterPadding * 2", leaf)
        self.assertIn("floatingMiniPlayerWideContentPadding", leaf)
        self.assertIn(">= TabletMiniPlayerView.minimumControlsWidth", leaf)

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
        self.assertIn("uiImage(for: url)", source)
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

    def test_artwork_cache_keeps_best_resolution(self):
        source = read("MeloX/Shared/Media/ArtworkImage.swift")
        policy = read("MeloX/Shared/Media/ArtworkImageCachePolicy.swift")
        self.assertIn("uiImage(for: url)", source)
        self.assertIn("ArtworkImageCachePolicy.shouldReplace(", source)
        self.assertIn("existing.pixelArea", source)
        self.assertIn("lock.lock()", source)
        self.assertIn("defer { lock.unlock() }", source)
        self.assertIn("newCost >= existingCost", policy)
        self.assertIn("static let maximumPixelDimension = 1024.0", policy)

    def test_backdrops_share_bounded_nuke_artwork(self):
        source = read("MeloX/Shared/Media/ArtworkBackdropImage.swift")
        apple = read(
            "MeloX/Features/Player/NowPlaying/AppleMusicBackdrop/"
            "NowPlayingAppleMusicBackground.swift"
        )
        background = read(
            "MeloX/Features/Player/NowPlaying/NowPlayingBackground.swift"
        )
        self.assertIn(
            "ImagePipeline.shared.image(\n                for: request",
            source,
        )
        self.assertIn("ImageRequest.ThumbnailOptions", source)
        self.assertIn("ArtworkBackdropSizing.quantized(", source)
        self.assertIn("inFlight", source)
        self.assertIn("ArtworkBackdropImage(", apple)
        self.assertIn("ArtworkBackdropImage(", background)
        self.assertIn(".id(artworkURL)", apple)
        self.assertIn(".id(artworkURL)", background)
        self.assertNotIn("AsyncImage", apple)
        self.assertNotIn("AsyncImage", background)
        artwork_method = apple.split(
            "private func artwork(in size: CGSize)", 1
        )[1].split("private var backdropMinimumInterval", 1)[0]
        self.assertIn("placeholderColor:", artwork_method)
        self.assertIn("red: 0.18", artwork_method)
        self.assertIn("ImageRequest(url: url)", source)
        self.assertNotIn("URLComponents", source)
        self.assertNotIn("queryItems", source)
        self.assertNotIn("param=", source)

    def test_backdrop_fade_only_local_transaction(self):
        source = read("MeloX/Shared/Media/ArtworkBackdropImage.swift")
        self.assertIn("transaction.disablesAnimations = false", source)
        self.assertIn("withTransaction(transaction)", source)
        self.assertIn("accessibilityReduceMotion", source)
        self.assertIn(
            ".timingCurve(0, 0, 0.3, 1, duration: 0.8)",
            source,
        )
        self.assertIn("completionCriteria: .removed", source)
        self.assertIn("guard loadedImage === incoming", source)
        self.assertIn("@State private var baseImage", source)
        self.assertIn("install(cached)", source)
        self.assertIn("install(image)", source)
        self.assertNotIn("if baseImage == nil", source)
        self.assertNotIn("fadeProgress < 0.999", source)
        self.assertNotIn("response.image", source)

    def test_player_artwork_prewarm_uses_current_song_url(self):
        source = read("MeloX/App/ContentView.swift")
        self.assertIn("prepareArtworkForPresentation()", source)
        method = source.split(
            "private func prepareArtworkForPresentation()", 1
        )[1].split("private func", 1)[0]
        self.assertIn(
            "player.currentSong?.album?.artworkURL",
            method,
        )
        self.assertIn(
            "await ArtworkBackdropImageProvider.shared.image(for: url, pixelDimension: 1024)",
            source,
        )
        self.assertIn(
            "playerBackgroundStyle == .flowingLight",
            method,
        )
        self.assertIn(
            "ArtworkAccentColorProvider.shared.detailAssets",
            method,
        )
        backdrop = read("MeloX/Shared/Media/ArtworkBackdropImage.swift")
        self.assertIn(".task(id: player.currentSong?.album?.artworkURL)", source)


if __name__ == "__main__":
    unittest.main()

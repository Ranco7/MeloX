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
        self.assertIn("maximumAge", source)
        self.assertIn("URLSession.shared.download", source)
        self.assertIn("catch is CancellationError", source)
        self.assertNotIn("reloadIgnoringLocalCacheData", source)

    def test_cache_is_wired_and_cancelled(self):
        source = read("MeloX/Core/Playback/Session/PlayerStore.swift")
        self.assertIn("PlaybackTrackCache.shared", source)
        self.assertIn("startTrackCachePreparationIfNeeded", source)
        self.assertIn("cancelTrackCachePreparation", source)
        self.assertIn("shouldUseCachedSourceForSeek", source)
        self.assertIn("autoplayAfterCachedHandoff", source)
        self.assertIn("discardCachedPlaybackSource", source)
        self.assertIn("isUsingCachedPlaybackSource", source)

    def test_cache_storage_is_visible_and_clearable(self):
        locations = read("MeloX/Core/Storage/AppStorageLocations.swift")
        maintenance = read("MeloX/Core/Storage/StorageMaintenance.swift")
        self.assertIn("playbackCacheDirectory", locations)
        self.assertIn("PlaybackTrackCache.clearCache()", maintenance)
        self.assertIn("playbackCacheBytes", maintenance)


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
    def test_bar_is_an_overlay_with_fixed_clearance(self):
        source = read("MeloX/App/ContentView.swift")
        self.assertIn("floatingMiniPlayerClearance", source)
        self.assertIn(".overlay(alignment: .bottom)", source)
        self.assertIn(".ignoresSafeArea(.keyboard, edges: .bottom)", source)
        self.assertEqual(source.count("TabletMiniPlayerView("), 1)
        inset = source.split(".safeAreaInset(edge: .bottom, spacing: 0)", 1)[1]
        inset = inset.split("\n    }", 1)[0]
        self.assertNotIn("TabletMiniPlayerView", inset)
        self.assertIn("Color.clear", inset)

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
        self.assertIn("onChange(of: state.image != nil, initial: true)", source)
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

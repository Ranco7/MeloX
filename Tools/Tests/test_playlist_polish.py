"""Source-level regressions only; not a UI/pixel/network test."""
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text()
class PlaylistPolishTests(unittest.TestCase):
    def test_bottom_inset_not_doubled(self):
        source = read("MeloX/App/ContentView.swift")
        self.assertNotIn("max(proxy.safeAreaInsets.bottom, 0) + 8", source)
        self.assertIn("MusicCollectionLayout.miniPlayerBottomInset", source)
    def test_content_column_measured(self):
        source = read("MeloX/App/ContentView.swift")
        self.assertNotIn("contentColumnFrames", source)
        self.assertIn("ContentColumnGeometryMath.horizontalBounds", source)
        self.assertIn("contentColumnGeometry.update(tab, bounds: bounds)", source)
        self.assertIn("let columnWidth = max(0, rootWidth - leading - trailing)", source)
    def test_shared_grid(self):
        source = read("MeloX/Features/Playlist/PlaylistTrackList.swift")
        self.assertIn("MusicCollectionLayout.titleLeadingInset", source)
        self.assertIn(".padding(.horizontal, MusicCollectionLayout.horizontalInset", source)
        self.assertIn(".frame(width: MusicCollectionLayout.controlMinimumSize, height:", source)
    def test_mutations_invalidate_detail(self):
        source = read("MeloX/Core/Library/LibraryStore.swift")
        self.assertGreaterEqual(source.count("await refreshPlaylistAfterMutation"), 2)
        self.assertIn("await self.refreshPlaylistAfterMutation", source)
        self.assertIn("await api.pageContentCache.remove(for: PlaylistContentSnapshot.cacheKey", source)
        self.assertIn("favoritePlaylists[index] = summary", source)
    def test_delete_refetches_instead_of_decrementing_twice(self):
        source = read("MeloX/Features/Playlist/PlaylistDetailView.swift")
        method = source.split("private func removeSong", 1)[1].split("private func loadMoreTracks", 1)[0]
        self.assertIn("await load()", method)
        self.assertIn("contentRevision = nil", method)
    def test_502_outcome_is_uncertain_and_not_retried(self):
        source = read("MeloX/Core/Networking/NeteaseAPI+PlaylistManagement.swift")
        self.assertIn("catch APIError.server(let statusCode, _) where statusCode == 502", source)
        self.assertIn("ui.playlists.add_gateway_uncertain", source)
        self.assertNotIn("Task.sleep", source)
    def test_scrollview_row_pressed_style(self):
        self.assertIn(".buttonStyle(MusicTrackPressStyle())", read("MeloX/Features/Playlist/PlaylistTrackList.swift"))
        self.assertIn("configuration.isPressed", read("MeloX/Shared/Media/MediaCardGridLayout.swift"))
    def test_list_song_buttons_use_native_style(self):
        for name in ["Library/LibrarySongsView", "Library/LibraryHistoryView", "Search/SearchView", "Cloud/CloudMusicView", "Home/DailySongsView", "Player/Queue/QueueView"]:
            self.assertIn(".buttonStyle(.automatic)", read("MeloX/Features/" + name + ".swift"))
    def test_cache_deletion_is_key_and_account_scoped(self):
        self.assertIn("DELETE FROM pageContent WHERE scope = ? AND cacheKey = ?", read("MeloX/Core/Storage/PageContentCache.swift"))
if __name__ == "__main__": unittest.main()

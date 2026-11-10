"""Song-row separator regressions; no SwiftUI rendering or touch-test claims."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from test_playback_song_switch import method

ROOT = Path(__file__).resolve().parents[2]
ROWS = 'MeloX/Features/Playlist/PlaylistTrackList.swift'
SHARED = 'MeloX/Shared/Media/TrackRowView.swift'
LAYOUT = 'MeloX/Shared/Media/MediaCardGridLayout.swift'


def read(path):
    return (ROOT/path).read_text()


class SongRowAlignmentTests(unittest.TestCase):
    def test_collection_song_dividers_use_title_for_both_width_modes(self):
        source = method(read(ROWS), 'struct PlaylistTrackList:')
        compact = ''.join(source.split())
        self.assertIn('MusicCollectionLayout.titleLeadingInset(wide:usesWideRows,artwork:showsArtwork,selecting:isSelectingDownloads)',compact)
        self.assertNotIn('?MusicCollectionLayout.wideInset',compact)
        self.assertIn('if song.id != tracks.last?.id',source)
        # Both kinds of detail page use the same track content/list.
        for path in ['MeloX/Features/Album/AlbumDetailContent.swift',
                     'MeloX/Features/Playlist/PlaylistDetailContent.swift']:
            self.assertIn('MusicCollectionTrackContent(',read(path))
        self.assertIn('PlaylistTrackList(',read('MeloX/Features/Playlist/PlaylistDetailContent.swift'))

    def test_native_list_guide_is_on_title_not_artwork_or_index(self):
        source = read(SHARED)
        title = source.split('Text(song.name)',1)[1].split('Text(subtitleText)',1)[0]
        self.assertIn('.alignmentGuide(.listRowSeparatorLeading)',title)
        self.assertIn('dimensions[.leading]',title)
        self.assertEqual(source.count('.listRowSeparatorLeading'),1)
        self.assertIn('AnyLayout(VStackLayout(alignment: .leading, spacing: 8))',source)
        self.assertIn('@ScaledMetric(relativeTo: .caption)',source)
        self.assertNotIn('.listRowSeparator(.hidden)',source)

    def test_hearts_are_preserved(self):
        source = read(ROWS)
        self.assertIn('Image(systemName: "heart.fill")',source)
        self.assertIn('library.contains(song: song) ? "heart.slash" : "heart"',source)
        shared = read(SHARED)
        self.assertIn('library.contains(song: song) ? "heart.slash" : "heart"',shared)
        for source in (source,shared):
            self.assertNotRegex(source,r'"star(?:\.[^\"]*)?"')
            self.assertIn('library.toggle(song: song)',source)

    def test_existing_row_visual_sizes_and_gaps_are_retained(self):
        source = read(LAYOUT)
        for name,value in [('rowArtworkSize',48),('wideRowArtworkSize',48),('wideRowHeight',56),
                           ('wideArtworkTitleSpacing',11),('columnSpacing',12)]:
            self.assertRegex(source,rf'static let {name}: CGFloat = {value}\b')
        self.assertIn('ArtworkImage(url: url, cornerRadius: 6)',read(ROWS))
        self.assertIn('.frame(width: 44, height: 44)',read(SHARED))

    @unittest.skipUnless(shutil.which('swiftc'),'Swift compiler unavailable')
    def test_production_row_insets_match_actual_leading_content(self):
        # Compile the real enum without the surrounding SwiftUI card/button code.
        enum = method(read(LAYOUT),'enum MusicCollectionLayout')
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)/'Layout.swift'
            executable = Path(directory)/'rows-checks'
            source.write_text('import CoreGraphics\n'+enum+'\n')
            subprocess.run(['swiftc','-swift-version','5',str(source),
                str(ROOT/'MeloX/Shared/Media/MusicCollectionWidthPolicy.swift'),
                str(ROOT/'Tests/Media/MusicCollectionRowAlignmentChecks.swift'),
                '-o',str(executable)],check=True)
            subprocess.run([str(executable)],check=True)


if __name__=='__main__':
    unittest.main()

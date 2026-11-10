"""Frozen-source fidelity + fit arithmetic; not SwiftUI pixel/hit-test evidence.

Run --report to reproduce conditional point geometry (not screenshot measures).
The Swift test compiles the real production fit decision on the Mac coordinator.
"""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
PLAYER = ROOT / 'MeloX/Features/Player/NowPlaying'
WINDOWS = [(1024,705),(705,1024),(1194,834),(834,1194),(375,486),
           (375,682),(698,886),(698,590),(446,580),(1366,1024),(1024,1366)]


def compact(source):
    return ''.join(source.split())


def digest(source):
    return hashlib.sha256(compact(source).encode()).hexdigest()


def block(source, start):
    begin = source.index(start)
    brace = source.index('{', begin)
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[begin:end]


# These hashes were generated from git 9d5d354, not from the restored views.
GOLDEN = {'NowPlayingAutoMixStatus': '9b838935577e9f663e2d6355de6229a463001190e774a0637cd16a31ef560e72',
 'NowPlayingProgressElapsedTime': 'fe457293969985bf1fb917ee691d1f5c58d1e97e46f7e4441ffc2d1ff6aacdda',
 'NowPlayingProgressRemainingTime': '385ba6d3fdc3ce4fcea9c9f1a58edd3617f7f357db6582cbc010db196783706d',
 'NowPlayingProgressSlider': '0c3b08e4b6037f4bb443cc4db0fa80fab576c0f056ab7f4fc8d3789571297605',
 'NowPlayingQualityMenu': 'c1f80c61fb1cd249ed1a99dcf4c27eeb52875bc5bb86f7025e17c8b389d450fb',
 'chrome': '1b85c926664e316e535511bc6111303c2bd08bfabb853243d497994e2f72e3d2',
 'layout': 'ff3ed1a80d6efed89688a5317b50be0f894e047dc419210e850de413ddcec7da',
 'metadata': '24964dc2337b7b0a9d5aeab08b47e718a3500396a1ea8956ab77e2d3c68b29ad'}
# Original 575068d route, extracted without changing its predicates or calls.
ADAPTIVE_ROUTE = '23672835017089112cd82db5aca073f787bd5e683d2d8d189b8add57ee9961ee'


def reference(width, height):
    progress = min(max((height-600)/168,0),1)
    scale = min(max(height/768,1),max(width/1200,1))
    column = max(min((320+102*progress)*scale,width*.5-40),1)
    content = max(height-112,0)
    slot = min((214+94*progress)*scale,column*.74)
    top = (54-min(max(600-height,0),50)+60*progress)*scale
    metadata = (70+10*progress)*scale
    compression = min(max((content-(238+45*scale))/(top+slot+metadata),.6),1)
    slot,top,metadata = slot*compression,top*compression,metadata*compression
    section = top+slot+metadata
    return dict(column=column, slot=slot, playing_artwork=slot/.74,
                artwork_top=48+top-(slot/.74-slot)/2,
                artwork_left=(width-slot/.74)/2,
                metadata_top=48+top+slot+metadata,
                content=content, section=section, scale=scale,
                maximum_control_band=content-section)


def accepts(width, height, band):
    g = reference(width,height)
    return width >= 520 and g['section']+band <= g['content']+1e-9


class FullscreenRestoreTests(unittest.TestCase):
    def test_frozen_geometry_is_the_actual_old_source(self):
        frozen = (ROOT/'Tests/Player/Fixtures/NowPlayingTablet9d5d354.swift').read_text().split('\n',1)[1]
        frozen = frozen.replace('GoldenNowPlayingTabletLayout','NowPlayingTabletLayout')
        self.assertEqual(digest(frozen), GOLDEN['layout'])
        actual = (PLAYER/'Tablet/NowPlayingReferenceTabletLayout.swift').read_text().split('\nextension ',1)[0]
        actual = actual.replace('NowPlayingReferenceTabletLayout','NowPlayingTabletLayout')
        self.assertEqual(digest(actual), GOLDEN['layout'])

    def test_chrome_and_metadata_preserve_old_structure(self):
        source = (PLAYER/'Tablet/NowPlayingReferenceTabletView.swift').read_text()
        chrome = block(source,'private var chrome:').replace('NowPlayingReferenceTabletLayout','NowPlayingTabletLayout')
        self.assertEqual(digest(chrome), GOLDEN['chrome'])
        source = (PLAYER/'Tablet/NowPlayingReferenceTabletColumn.swift').read_text()
        metadata = block(source,'private struct NowPlayingReferenceTabletMetadata:')
        metadata = metadata.replace('NowPlayingReferenceTabletMetadata','NowPlayingTabletMetadata')
        metadata = metadata.replace('(expandsTouchTarget: true)','()').replace(', offersAirPlayMenu: true','')
        metadata = '\n'.join(line for line in metadata.splitlines() if not line.lstrip().startswith('//'))
        self.assertEqual(digest(metadata), GOLDEN['metadata'])
        # Visible reference order/spacing is the baseline, not the adaptive grid.
        for value in ['layout.artworkTopInset','layout.metadataTopInset','23 * layout.elementScale',
                      '22 * layout.elementScale','.padding(.top, 12)','.padding(.bottom, 20)']:
            self.assertIn(value,source)
        self.assertNotIn('.scaleEffect',source)
        self.assertIn('.frame(width: layout.playingArtworkSize, height: layout.playingArtworkSize)',source)

    def test_reference_control_leaf_views_are_unchanged(self):
        source = (PLAYER/'NowPlayingControls.swift').read_text()
        for name in ('NowPlayingProgressSlider','NowPlayingProgressElapsedTime','NowPlayingProgressRemainingTime',
                     'NowPlayingAutoMixStatus','NowPlayingQualityMenu'):
            self.assertEqual(digest(block(source,'private struct '+name+':')),GOLDEN[name])
        transport = block(source,'struct NowPlayingTransportControls:')
        self.assertIn('if isReference { return 44 }',transport)
        self.assertIn('isReference ? 24 :',transport)
        self.assertIn('isReference ? 30 :',transport)
        self.assertIn('.frame(height: isReference ? 52 :',transport)
        self.assertIn('usesReferenceLayout ? 42 : 44',source)
        self.assertIn('volumeView.showsRouteButton = usesReferenceLayout',source)

    def test_fit_measures_the_whole_column_synchronously(self):
        source = (PLAYER/'Tablet/NowPlayingReferenceTabletView.swift').read_text()
        self.assertIn('subviews[0].sizeThatFits(ProposedViewSize(width: layout.playerWidth, height: nil))',source)
        self.assertIn('layout.requiredSize(measuredColumnSize: columnSize(subviews))',source)
        self.assertNotIn('GeometryReader',source)
        self.assertNotIn('@State',source)
        source = (PLAYER/'NowPlayingView.swift').read_text()
        self.assertIn('ViewThatFits(in: [.horizontal, .vertical])',source)
        self.assertIn('!hasDisplayDivision',source)
        # Original adaptive if-chain is preserved, including TextPV priority.
        adaptive = block(source,'private func adaptivePlayer(').split('{',1)[1][:-1]
        adaptive = adaptive.replace('viewport.width','proxy.size.width').replace('viewport.height','proxy.size.height')
        self.assertEqual(digest(adaptive),ADAPTIVE_ROUTE)

    def test_volume_settings_and_actions_remain_reachable(self):
        source = (PLAYER/'NowPlayingControls.swift').read_text()
        self.assertIn('if settings.playerVolumeControlMode != .hidden',source)
        self.assertIn('case .independent:',source)
        self.assertIn('case .system:',source)
        self.assertNotIn('settings.playerVolumeControlMode =',source)
        mode = (ROOT/'MeloX/Core/Settings/Playback/PlayerVolumeControlMode.swift').read_text()
        self.assertIn('static let defaultMode: Self = .system',mode)
        actions = (PLAYER/'NowPlayingSongActions.swift').read_text()
        self.assertIn('var offersAirPlayMenu = false',actions)
        self.assertIn('if offersAirPlayMenu',actions)
        self.assertIn('Button { presentedSheet = .airPlay }',actions)
        self.assertIn('NowPlayingAirPlayControl().frame(width: 44, height: 44)',actions)
        self.assertIn('floatingLyrics.toggle()',actions)
        self.assertIn('case .sleepTimer:',actions)
        self.assertIn('case .listenTogether:',actions)
        view = (PLAYER/'Tablet/NowPlayingReferenceTabletView.swift').read_text()
        self.assertIn('FloatingLyricsButton()',view)
        self.assertIn('NowPlayingTabletPageSwitcher(page: $page)',view)
        self.assertIn('NowPlayingLyricsLanguageButton(',view)

    def test_native_pause_appearance_updates_without_relayout(self):
        source = (PLAYER/'NowPlayingPortraitArtwork.swift').read_text()
        update = block(source,'func update(url:')
        self.assertIn('self.appearanceScale = appearanceScale',update)
        self.assertIn('usesReferenceAppearance && (player.isPlaying || !settings.shrinksPausedArtwork) ? 1 / 0.74 : 1',source)
        self.assertIn('UIViewPropertyAnimator(duration: 0.48',source)
        self.assertIn('surface.transform = CGAffineTransform(scaleX: targetScale, y: targetScale)',source)
        self.assertIn('let radius = 12 / targetScale * appearanceScale',source)
        self.assertIn('pausedArtworkScale: CGFloat = 0.82',(PLAYER/'NowPlayingArtworkPage.swift').read_text())
        self.assertNotIn('.scaleEffect',source)

    def test_reference_examples_and_safe_area_thresholds(self):
        self.assertAlmostEqual(reference(1024,705)['column'],383.75)
        self.assertAlmostEqual(reference(834,1194)['playing_artwork'],377)
        self.assertFalse(accepts(1024,705,297))
        self.assertTrue(accepts(1024,705,255))
        self.assertTrue(accepts(705,1024,297))
        for width,height in WINDOWS:
            for safe in (0,44,58):
                g = reference(width,height-safe)
                for band in (255,279,297,321,500):
                    selected = accepts(width,height-safe,band)
                    if selected:
                        self.assertGreaterEqual(g['column'],220)
                        self.assertLessEqual(g['section']+band,g['content']+1e-9)
                    if width < 520:
                        self.assertFalse(selected)
                self.assertGreater(g['playing_artwork'],0)
                self.assertLessEqual(g['playing_artwork'],g['column']+1e-9)
        self.assertTrue(accepts(520,1200,279))
        self.assertFalse(accepts(519.999,1200,279))

    def test_normal_references_retain_complete_adaptive_default_volume(self):
        from test_nowplaying_reference_layout import portrait, tablet
        for width,height in [(375,486),(375,682),(446,580),(698,886),(698,590)]:
            for safe in (0,44,58):
                # Baseline band 321 models active badge + system volume.
                if not accepts(width,height-safe,321):
                    g = (portrait(width,height-safe,metadata=76) if width<520
                         else tablet(width,height-safe,metadata=96))
                    self.assertFalse(g['scroll'])
                    self.assertTrue(g['volume_enabled'])
                    self.assertGreaterEqual(g['artwork'],64)
                    self.assertLessEqual(g['volume_bottom'],g['available'])

    @unittest.skipUnless(shutil.which('swiftc'),'Swift compiler unavailable')
    def test_production_hit_shape_preserves_spacing_and_default_behavior(self):
        # Compile the production pure rectangle math with tiny Path/Shape stubs.
        # This verifies geometry, not UIKit's final event delivery.
        shape = block((PLAYER/'NowPlayingControls.swift').read_text(),
                      'struct NowPlayingVerticalHitShape:')
        harness = r"""
import CoreGraphics
protocol Shape { func path(in rect: CGRect) -> Path }
struct Path { let rect: CGRect; init(_ rect: CGRect) { self.rect = rect } }
// PRODUCTION_SHAPE
for height: CGFloat in [20, 22, 24, 44, 60] {
    let rect = CGRect(x: 0, y: 40, width: 64, height: height)
    precondition(NowPlayingVerticalHitShape().path(in: rect).rect == rect)
    let badge = NowPlayingVerticalHitShape(minimumHeight: 44, maximumBottomOutset: 0).path(in: rect).rect
    precondition(badge.height >= 44 && badge.width >= 44)
    precondition(badge.minY >= 0) // passive title/artist, not another action
    precondition(badge.maxY == rect.maxY) // leave the full next gap to progress
}
for height: CGFloat in [20, 24, 28, 32, 44] {
    let slider = CGRect(x: 0, y: 23, width: 200, height: height)
    let progress = NowPlayingVerticalHitShape(minimumHeight: 44, maximumBottomOutset: 6).path(in: slider).rect
    precondition(progress.height >= 44)
    precondition(progress.minY >= 0) // preceding metadata ends here
    precondition(progress.maxY <= slider.maxY + 6) // quality target starts here
}
let native = CGRect(x: 0, y: 6, width: 200, height: 32)
let hit = NowPlayingVerticalHitShape(minimumHeight: 44).path(in: native).rect
precondition(hit == CGRect(x: 0, y: 0, width: 200, height: 44))
print("Reference hit geometry passed: 44pt targets, adjacent rows, unchanged visual/default bounds")
"""
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)/'main.swift'
            executable = Path(directory)/'hit-checks'
            source.write_text(harness.replace('// PRODUCTION_SHAPE',shape))
            subprocess.run(['swiftc','-swift-version','5',str(source),'-o',str(executable)],check=True)
            subprocess.run([str(executable)],check=True)

    @unittest.skipUnless(shutil.which('swiftc'),'Swift compiler unavailable')
    def test_production_swift_golden_and_fit_matrix(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory)/'fullscreen-checks'
            subprocess.run(['swiftc','-swift-version','5',
                str(ROOT/'Tests/Player/Fixtures/NowPlayingTablet9d5d354.swift'),
                str(PLAYER/'Tablet/NowPlayingReferenceTabletLayout.swift'),
                str(PLAYER/'Tablet/NowPlayingTabletLayout.swift'),
                str(PLAYER/'NowPlayingPortraitLayout.swift'),
                str(ROOT/'Tests/Player/NowPlayingFullscreenRestoreChecks.swift'),
                '-o',str(executable)],check=True)
            subprocess.run([str(executable)],check=True)


def write_report():
    rows = []
    for width,height in WINDOWS:
        for safe in (0,44,58):
            g = reference(width,height-safe)
            rows.append(dict(window=[width,height],safe_area=safe,**g,
                             hidden_band255=accepts(width,height-safe,255),
                             visible_band297=accepts(width,height-safe,297),
                             badge_visible_band321=accepts(width,height-safe,321)))
    destination = ROOT/'.out/fullscreen-restore/geometry.json'
    destination.parent.mkdir(parents=True,exist_ok=True)
    destination.write_text(json.dumps(dict(
        units='conditional logical points; not measured screenshots or SwiftUI row heights',
        control_band='metadata + progress + 52 transport + (42 volume or 0 hidden) + 45*scale + 32 padding',
        rows=rows),ensure_ascii=False,indent=2)+'\n')
    print(destination)
    for row in rows:
        if row['safe_area']==44:
            print(f"{row['window']}: column={row['column']:.2f}, old-art={row['playing_artwork']:.2f}, "
                  f"max-band={row['maximum_control_band']:.2f}, hidden255={row['hidden_band255']}, visible297={row['visible_band297']}")


if __name__=='__main__':
    if '--report' in sys.argv:
        write_report()
    else:
        unittest.main()

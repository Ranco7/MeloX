"""Reproducible arithmetic fixtures; these are NOT SwiftUI rendering tests.

Run unittest, or pass --report to write source-pixel measurements and model
geometry to .out/nowplaying-am. Swift tests execute production math on a Mac.
"""
import json
import math
from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / '.out/nowplaying-am'
TABLET_SOURCE = (ROOT / 'MeloX/Features/Player/NowPlaying/Tablet/NowPlayingTabletLayout.swift').read_text()
PORTRAIT_SOURCE = (ROOT / 'MeloX/Features/Player/NowPlaying/NowPlayingPortraitLayout.swift').read_text()


def scalar(source, name):
    match = re.search(r'\b' + name + r': CGFloat\s*(?:=\s*([\d.]+)|\{\s*([\d.]+)\s*\})', source)
    if not match:
        raise ValueError(name)
    return float(match[1] or match[2])


# Rectangles were read visually on 1408px-wide copies; exported back to the
# original JPEG coordinate system. Accuracy about +/- 2 display px, not an
# automated subpixel estimate. Edge pixels exclude shadow/antialiasing.
REFERENCES = [
    dict(name='short-floating', prefix='60baa5', window=(80,105,695,902),
         art=(357,206,418,267), column=(113,662), am_art=(901,216,1140,455), am_column=(784,1255),
         scale=1715/1408, logical=(375,486), route='portrait', safe=44),
    dict(name='tall-narrow', prefix='654159', window=(204,51,693,940),
         art=(323,136,574,388), column=(231,666), am_art=(764,140,1138,514), am_column=(764,1138),
         scale=2157/1408, logical=(375,682), route='portrait', safe=44),
    dict(name='half-full-height', prefix='656b5a', window=(0,0,698,886),
         art=(195,96,505,406), column=(195,505), am_art=(826,79,1291,544), am_column=(787,1330),
         scale=2, logical=(698,886), route='tablet', safe=44),
    dict(name='short-wide', prefix='56a390', window=(0,0,698,590),
         art=(284,97,414,227), column=(284,414), am_art=(974,79,1144,249), am_column=(787,1330),
         scale=2, logical=(698,590), route='tablet', safe=44),
]
STANDARD = [(320,480),(375,667),(390,844),(430,932),(446,580),(507,834),(597,834),(834,1194),(1194,834),(1366,1024)]


def tablet(width, height, metadata=96, progress=78, volume=44, fills=False, side=False):
    region = width * (0.5 if side else 1)
    column = max(min(region - 2 * min(max(region * 0.11, 24), 80), 640), 220)
    content = max(height - (0 if fills else scalar(TABLET_SOURCE,'chromeHeight') + scalar(TABLET_SOURCE,'bottomBarHeight')), 0)
    transport = 44 + 20 * min(max((content - 400) / 200, 0), 1)
    band = (scalar(TABLET_SOURCE,'metadataTopInset') + metadata + scalar(TABLET_SOURCE,'progressTopInset') + progress
            + scalar(TABLET_SOURCE,'transportTopInset') + transport + scalar(TABLET_SOURCE,'volumeTopInset') + volume
            + scalar(TABLET_SOURCE,'playerBottomInset'))
    top = scalar(TABLET_SOURCE,'artworkTopInset')
    art = min(column, max(scalar(TABLET_SOURCE,'minimumArtworkSide'), content - top - band))
    extra = max(content - top - art - band, 0)
    volume_top = top + art + 16 + metadata + 8 + progress + 4 + transport + 4 + extra * 4/5
    return dict(column=column, artwork=art, transport_height=transport, volume_top=volume_top, volume_bottom=volume_top + volume,
                stack_bottom=top + art + band + extra, available=content,
                scroll=top + art + band > content + .5, volume_enabled=volume > 0)


def portrait(width, height, metadata=52, progress=52, text_scale=1, volume=44, header=44):
    column = max(width - 2*min(max(width*.055,16),32),1)
    s = min(max((height-480)/420,0),1)
    p = max(math.ceil(scalar(PORTRAIT_SOURCE, 'baseProgressHeight')*text_scale), progress)
    t = 44 + 36*s
    top, art_gap, meta_gap, control_gap, toolbar = 4+12*s, 12+12*s, 4+20*s, 4+20*s, 4+4*s
    selector = scalar(PORTRAIT_SOURCE, 'basePageSelectorHeight')
    bottom = scalar(PORTRAIT_SOURCE, 'bottomSafeAreaPadding')
    # Header already includes quality and active badges; no duplicate row.
    extra = max(height-(header+bottom+metadata+p+t+44+selector)
                -(top+art_gap+meta_gap+2*control_gap+toolbar)-column,0)/9
    gap1, gap2, gap3 = control_gap+2*extra, control_gap+2*extra, toolbar+extra
    controls = p+gap1+t+gap2+44+gap3+selector
    page = max(height-header-bottom-controls,1)
    gaps = top+extra + art_gap+2*extra + meta_gap+extra
    art = max(min(column,page-metadata-gaps),min(scalar(PORTRAIT_SOURCE,'minimumArtworkSide'),column))
    natural = gaps+art+metadata
    area = max(page,natural)
    progress_top = header+area
    volume_top = progress_top+p+gap1+t+gap2
    toolbar_top = volume_top+44+gap3
    return dict(column=column, artwork=art, progress_height=p, transport_height=t,
                progress_transport_gap=gap1, transport_volume_gap=gap2, volume_selector_gap=gap3,
                header_height=header, volume_top=volume_top, volume_bottom=volume_top+volume,
                toolbar_top=toolbar_top, toolbar_bottom=toolbar_top+selector,
                stack_bottom=header+bottom+area+controls, available=height,
                scroll=natural>page+.5, volume_enabled=volume>0)


class ReferenceLayoutChecks(unittest.TestCase):
    def test_all_reference_and_standard_windows(self):
        for w,h in [r['logical'] for r in REFERENCES]+STANDARD:
            for safe in (0,44,58):
                for meta in (48,76,148,240):
                    for progress in (78,160):
                        for layout in (portrait,tablet):
                            with self.subTest(window=(w,h),safe=safe,meta=meta,progress=progress,route=layout.__name__):
                                g=layout(w,h-safe,metadata=meta,progress=progress)
                                self.assertGreaterEqual(g['artwork'],64)
                                self.assertLessEqual(g['artwork'],g['column'])
                                if g['scroll']:
                                    self.assertGreater(g['stack_bottom'],g['available'])
                                else:
                                    self.assertAlmostEqual(g['stack_bottom'],g['available'])
                                    self.assertLessEqual(g['volume_bottom'],g['available'])

    def test_normal_reference_controls_are_simultaneously_visible(self):
        for w,h in ((375,486),(446,580),(375,682)):
            for safe in (0,44,58):
                # One/two title lines + artist, with badges and quality in the
                # header. Volume is enabled, not omitted to make the fixture fit.
                for metadata in (52,76):
                    with self.subTest(window=(w,h), safe=safe, metadata=metadata):
                        g=portrait(w,h-safe,metadata=metadata)
                        self.assertFalse(g['scroll'])
                        self.assertTrue(g['volume_enabled'])
                        self.assertLessEqual(g['toolbar_bottom']+4,h-safe+.001)
                        self.assertLessEqual(g['volume_bottom'],g['toolbar_top']+.001)
                        self.assertAlmostEqual(g['stack_bottom'],h-safe)
                        self.assertGreaterEqual(g['artwork'],80)
        for w,h in ((698,886),(698,590)):
            for safe in (0,44,58):
                for metadata in (52,76,96,105,124,128):
                    g=tablet(w,h-safe,metadata=metadata)
                    self.assertFalse(g['scroll'])
                    self.assertTrue(g['volume_enabled'])
                    self.assertLessEqual(48+g['volume_bottom'],h-safe-64)
        self.assertAlmostEqual(portrait(375,442)['artwork'],126)
        self.assertAlmostEqual(portrait(446,536)['artwork'],203.4666666667)

    def test_only_extreme_or_accessibility_content_requires_scroll(self):
        self.assertTrue(portrait(320,300)['scroll'])
        self.assertTrue(portrait(375,442,metadata=148,progress=160,text_scale=1.35,header=88)['scroll'])

    def test_two_line_badges_remain_visible_in_short_wide_panes(self):
        for safe in (44,58):
            for metadata in (96,105,124,128):
                for side in (False,True):
                    g=tablet(698,590-safe,metadata=metadata,side=side)
                    self.assertFalse(g['scroll'])
                    self.assertGreaterEqual(g['artwork'],64)
                    self.assertGreaterEqual(g['column'],220)
                    self.assertGreaterEqual(g['transport_height'],44)
                    self.assertLessEqual(48+g['volume_bottom'],590-safe-64)
        self.assertAlmostEqual(tablet(698,546,metadata=96)['artwork'],112.6)
        self.assertAlmostEqual(tablet(698,532,metadata=96)['artwork'],100)

    def test_portrait_control_groups_retain_minimum_rhythm(self):
        for h in (428,442,536,638,900):
            g=portrait(375,h)
            self.assertGreaterEqual(g['progress_transport_gap'],4)
            self.assertGreaterEqual(g['transport_volume_gap'],4)
            self.assertGreaterEqual(g['volume_selector_gap'],4)

    def test_height_and_accessibility_do_not_narrow_tablet_column(self):
        for w in (320,375,507,698,834,1194,1366):
            widths={tablet(w,h,metadata=m)['column'] for h in (350,546,842,1200) for m in (48,76,240)}
            self.assertEqual(len(widths),1)
        self.assertAlmostEqual(tablet(698,546)['column'],544.44)

    def test_artwork_aligns_when_height_permits(self):
        g=tablet(375,1200)
        self.assertEqual(g['artwork'],g['column'])

    def test_native_transport_widths(self):
        for width in (320,375,507,698,834,1194,1366):
            for side in (False,True):
                g=tablet(width,842,side=side)
                if g['column'] >= 220:
                    diameter=min(64,max(44,(g['column']-88)/3))
                    self.assertLessEqual(88+3*diameter,g['column']+.001)

    def test_resize_continuity(self):
        for h in range(300,1400):
            a,b=tablet(698,h-.001),tablet(698,h+.001)
            self.assertLess(abs(a['artwork']-b['artwork']),.003)
            self.assertEqual(a['column'],b['column'])

    def test_source_pixel_measurements(self):
        self.assertEqual(len(list((OUT/'refs').glob('*.jpg'))),4)
        for r in REFERENCES:
            self.assertTrue(any((OUT/'refs').glob(r['prefix']+'*.jpg')))
        self.assertGreater(REFERENCES[2]['am_column'][1]-REFERENCES[2]['am_column'][0],1.7*(REFERENCES[2]['column'][1]-REFERENCES[2]['column'][0]))


def write_report():
    from PIL import Image, ImageDraw
    measured=[]
    for r in REFERENCES:
        path=next((OUT/'refs').glob(r['prefix']+'*.jpg'))
        src=Image.open(path)
        factor=r['scale']
        source_rect=lambda rect:[round(v*factor,1) for v in rect]
        row=dict(name=r['name'],file=path.name,source_pixels=src.size,
                 window_px=source_rect(r['window']),artwork_px=source_rect(r['art']),column_px=source_rect(r['column']),
                 am_artwork_px=source_rect(r['am_art']),am_column_px=source_rect(r['am_column']),
                 melox_volume_visible=False,am_volume_visible=True,logical_fixture=r['logical'],safe_area_fixture=r['safe'])
        measured.append(row)
        # Audit overlays show which pixel boundaries were read, not a redesigned screenshot.
        im=src.resize((1408,round(src.height*1408/src.width)))
        draw=ImageDraw.Draw(im)
        for rect,label in [(r['window'],'window'),(r['art'],'MeloX artwork'),(r['am_art'],'AM artwork')]:
            draw.rectangle(rect,outline='#00ffff',width=2)
            draw.text((rect[0]+2,rect[1]+2),label,fill='#00ffff',stroke_width=1,stroke_fill='#111111')
        for (x1,x2),y in [(r['column'],r['art'][3]+12),(r['am_column'],r['am_art'][3]+12)]:
            draw.line((x1,y,x2,y),fill='#ffff00',width=2)
        im.save(OUT/(r['name']+'-measured.png'))
    results=[]
    for r in REFERENCES:
        w,h=r['logical'];f=portrait if r['route']=='portrait' else tablet
        for metadata in ((52,76) if f is portrait else (72,96)):
            progress=52 if f is portrait else 78
            results.append(dict(name=r['name'],viewport=[w,h-r['safe']],metadata=metadata,progress=progress,transport=64,volume=44,
                                route=r['route'],**f(w,h-r['safe'],metadata=metadata)))
    for w,h in STANDARD:
        f=portrait if w<600 else tablet
        results.append(dict(name='standard',viewport=[w,h-44],metadata=52 if f is portrait else 96,
                            progress=52 if f is portrait else 78,transport=64,volume=44,
                            route='portrait' if w<600 else 'tablet',**f(w,h-44)))
    for safe in (44,58):
        for metadata in (124,128):
            results.append(dict(name='short-wide-stacked',viewport=[698,590-safe],metadata=metadata,
                                progress=78,volume=44,route='tablet',**tablet(698,590-safe,metadata=metadata)))
    for result in results:
        result['transport'] = result['transport_height']
    (OUT/'measurements.json').write_text(json.dumps(measured,indent=2)+'\n')
    (OUT/'layout-math.json').write_text(json.dumps(results,indent=2)+'\n')
    for g in results:
        print(f"{g['name']:17} {str(g['viewport']):12} meta={g['metadata']:3} col={g['column']:6.1f} art={g['artwork']:6.1f} volume={g['volume_top']:6.1f}..{g['volume_bottom']:6.1f} scroll={g['scroll']}")


if __name__=='__main__':
    if '--report' in sys.argv: write_report()
    else: unittest.main()

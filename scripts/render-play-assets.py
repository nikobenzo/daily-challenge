#!/usr/bin/env python3
"""Render the Google Play store graphics into docs/assets/play/ (see docs/play-store-listing.md).

- icon-512.png: the app icon tile from scripts/render-app-icon.swift --ios (full bleed; Play
  applies its own rounded mask), 512 x 512, 32-bit PNG.
- feature-graphic-1024x500.png: docs/assets/play/source/feature-graphic.html through Chrome
  (chrome-devtools-axi), 24-bit PNG.
- screenshots/NN-<name>.png: Android 10 emulator captures from docs/screenshots/android/play/
  (scripts/capture-play-screenshots.sh) with the status and navigation bars cropped, fitted to
  1080 x 1920 (9:16), 24-bit PNG.

Requires macOS (swift, system font), chrome-devtools-axi and Pillow. Run with a Python that has
Pillow, for example: python3 -m venv .build/play-venv && .build/play-venv/bin/pip install Pillow
&& .build/play-venv/bin/python scripts/render-play-assets.py
Pass --screenshots to render only the screenshots (Pillow alone; the icon and feature graphic stay).
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'docs/assets/play'
CAPTURES = ROOT / 'docs/screenshots/android'
PLAY_CAPTURES = CAPTURES / 'play'
# Listing order: the first screenshots show first on the store page.
SCREENSHOTS = ['today-light', 'daily-goals-light', 'repeat-light', 'history-light', 'setup-light',
               'today-complete-light', 'account-light', 'today-dark']
# Android 10 emulator (1080 x 2280, 440 dpi): the 24 dp status bar above, the 48 dp navigation bar below.
CAPTURE_SIZE = (1080, 2280)
STATUS_BAR, NAVIGATION_BAR_TOP = 66, 2148
# The Today card (goals, jug, pour controls) in the Redmi's today-light.png, for the feature graphic.
TODAY_CROP = (48, 388, 984, 930)
TODAY_HEIGHT = 340


def run(*args):
    env = dict(os.environ, CHROME_DEVTOOLS_AXI_SESSION='dc-play-assets')
    result = subprocess.run(['chrome-devtools-axi', *map(str, args)], cwd=ROOT, env=env, text=True,
                            timeout=90, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(result.stdout)
    return result.stdout


def icon(work):
    master = work / 'icon-1024.png'
    subprocess.run(['swift', str(ROOT / 'scripts/render-app-icon.swift'), '--ios', str(master)], check=True)
    with Image.open(master) as im:
        im.convert('RGBA').resize((512, 512), Image.Resampling.LANCZOS).save(DEST / 'icon-512.png', optimize=True)
    return master


def feature_graphic(work, master):
    cx, cy, cw, ch = TODAY_CROP
    scale = TODAY_HEIGHT / ch
    source = CAPTURES / 'today-light.png'
    with Image.open(source) as im:
        source_width = im.width
    values = {'ICON': master.as_uri(), 'TODAY': source.as_uri(),
              'TODAY_W': round(cw * scale), 'TODAY_H': TODAY_HEIGHT,
              'SOURCE_W': source_width * scale, 'SOURCE_X': -cx * scale, 'SOURCE_Y': -cy * scale}
    page = (DEST / 'source/feature-graphic.html').read_text()
    for key, value in values.items():
        page = page.replace('__' + key + '__', str(value))
    target = work / 'feature-graphic.html'
    target.write_text(page)
    output = DEST / 'feature-graphic-1024x500.png'
    run('newpage', target.as_uri())
    run('resize', 1024, 500)
    run('open', target.as_uri())
    run('eval', 'async () => { await document.fonts.ready; await Promise.all(Array.from(document.images).map(i => i.decode())); return true; }')
    overflow = run('eval', '() => [...document.querySelectorAll(".copy, h1, .brand")].some(e => e.scrollWidth > e.clientWidth + 1)')
    if 'true' in overflow.split('\n')[0]:
        raise RuntimeError('Feature graphic text overflows')
    run('screenshot', output)
    with Image.open(output) as im:
        rgb = im.convert('RGB')
    if rgb.size != (1024, 500):
        if rgb.width % 1024 or rgb.width * 500 != rgb.height * 1024:
            raise ValueError(f'Unexpected feature graphic size: {rgb.size}')
        rgb = rgb.resize((1024, 500), Image.Resampling.LANCZOS)
    rgb.save(output, optimize=True)


def screenshot(name, index):
    with Image.open(PLAY_CAPTURES / (name + '.png')) as im:
        rgb = im.convert('RGB')
    if rgb.size != CAPTURE_SIZE:
        raise ValueError(f'{name}: expected a 1080 x 2280 emulator capture, got {rgb.size}')
    app = rgb.crop((0, STATUS_BAR, 1080, NAVIGATION_BAR_TOP))
    # Fit the app into 1080 x 1920 and fill the narrow side margins by repeating each edge
    # column, which continues the app's own background.
    height = 1920
    width = round(app.width * height / app.height)
    app = app.resize((width, height), Image.Resampling.LANCZOS)
    canvas = Image.new('RGB', (1080, height))
    left = (1080 - width) // 2
    canvas.paste(app.crop((0, 0, 1, height)).resize((left, height)), (0, 0))
    canvas.paste(app.crop((width - 1, 0, width, height)).resize((1080 - left - width, height)), (left + width, 0))
    canvas.paste(app, (left, 0))
    canvas.save(DEST / 'screenshots' / f'{index:02d}-{name}.png', optimize=True)


def main():
    (DEST / 'screenshots').mkdir(parents=True, exist_ok=True)
    for old in (DEST / 'screenshots').glob('*.png'):
        old.unlink()
    if '--screenshots' not in sys.argv[1:]:
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            master = icon(work)
            feature_graphic(work, master)
    for index, name in enumerate(SCREENSHOTS, 1):
        screenshot(name, index)
    print('Rendered', DEST.relative_to(ROOT))


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Render the committed HTML + frame manifest through chrome-devtools-axi.
Requires macOS (system SF font), chrome-devtools-axi and Pillow==12.3.0.
Run with .build/app-store-venv/bin/python scripts/render-app-store-marketing.py.
Browser operations use a dedicated axi session; no app/account is launched.
"""
import argparse
import hashlib
import html
import json
import os
from pathlib import Path
import subprocess
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'docs/screenshots/app-store/marketing'
SIZES = {'iphone-6.9': (1320, 2868), 'iphone-medium': (1206, 2622)}
HEADER = DEST / 'header'

def run(*args):
    env = dict(os.environ, CHROME_DEVTOOLS_AXI_SESSION='dc-appstore-marketing')
    result = subprocess.run(['chrome-devtools-axi', *map(str, args)], cwd=ROOT,
                            env=env, text=True, timeout=90, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(result.stdout)
    return result.stdout

def render_headers():
    """Use the same Chrome/HTML/RGB export pipeline for creative headers."""
    config = json.loads((HEADER / 'header.json').read_text())
    template = (HEADER / 'template.html').read_text()
    working = ROOT / '.build/app-store-marketing/header'
    working.mkdir(parents=True, exist_ok=True)
    inputs = {}
    for key, path in config['sources'].items():
        source = ROOT / path
        with Image.open(source) as im:
            dimensions = list(im.size)
        inputs[key] = {'path': path, 'size': dimensions,
                       'sha256': hashlib.sha256(source.read_bytes()).hexdigest()}
    run('newpage', (HEADER / 'template.html').as_uri())
    metadata = []
    for asset in config['exports']:
        width, height = asset['size']
        x, y, sw, sh = asset['safe_area']
        values = {'WIDTH': width, 'HEIGHT': height, 'SAFE_X': x, 'SAFE_Y': y,
                  'SAFE_W': sw, 'SAFE_H': sh, 'LAYOUT': asset['layout'],
                  'BRAND': html.escape(config['brand']), 'TAG': html.escape(config['tag']),
                  'HEADLINE': ''.join('<span>'+html.escape(s)+'</span>' for s in config['headline'])}
        for key, path in config['sources'].items():
            values[key.upper()] = (ROOT / path).as_uri()
        # Crop the exact capture, uniformly scaled; do not reconstruct any UI.
        cx, cy, cw, ch = config['today_crop']
        display_width = asset['today_width']
        scale = display_width / cw
        values.update({'TODAY_W': display_width, 'TODAY_H': ch * scale,
                       'SOURCE_W': inputs['today']['size'][0] * scale,
                       'SOURCE_X': -cx * scale, 'SOURCE_Y': -cy * scale})
        page = template
        for key, value in values.items():
            page = page.replace('__'+key+'__', str(value))
        target = working / (asset['id'] + '.html')
        target.write_text(page)
        run('resize', width, height)
        run('open', target.as_uri())
        run('eval', 'async () => { await document.fonts.ready; await Promise.all(Array.from(document.images).map(i => i.decode())); return true; }')
        bounds = run('eval', '''() => {
          const s=document.querySelector('.safe').getBoundingClientRect();
          const result=[];
          for(const e of document.querySelectorAll('[data-key]')) {
            const r=e.getBoundingClientRect();
            if(r.left<s.left || r.top<s.top || r.right>s.right || r.bottom>s.bottom)
              throw Error('Outside Apple safe area: '+e.className);
            if(e.scrollWidth>e.clientWidth+1)
              throw Error('Overflow: '+e.className);
            // Tight headline line-height lets glyphs extend below the line box.
            // Check their ink range against the safe area, not scrollHeight.
            for(const span of e.tagName==='H1' ? e.querySelectorAll('span') : []) {
              const range=document.createRange(); range.selectNodeContents(span);
              const ink=range.getBoundingClientRect();
              if(ink.left<s.left || ink.top<s.top || ink.right>s.right || ink.bottom>s.bottom)
                throw Error('Unsafe headline glyphs');
            }
            result.push({class:e.className,x:r.x,y:r.y,width:r.width,height:r.height});
          }
          return result;
        }''')
        output = HEADER / (asset['id'] + '.png')
        run('screenshot', output)
        with Image.open(output) as im:
            if im.size != (width, height):
                raise ValueError(f'Incorrect header size: {im.size}')
            rgb = im.convert('RGB')
            rgb.save(output, optimize=True)
            # Review-only overlays and crops, never upload these previews.
            guide = rgb.copy()
            ImageDraw.Draw(guide).rectangle((x, y, x+sw-1, y+sh-1), outline='#ff8800', width=6)
            guide.thumbnail((1311, 738))
            guide.save(HEADER / (asset['id'] + '-safe-area-preview.png'))
            crop = rgb.crop((x, y, x+sw, y+sh))
            crop.save(HEADER / (asset['id'] + '-safe-area-crop.png'))
            # A conservative 402 pt portrait-phone view of the safe rectangle.
            crop.resize((402, round(sh * 402 / sw)), Image.Resampling.LANCZOS).save(
                HEADER / (asset['id'] + '-iphone-crop-preview.png'))
        metadata.append({'output': str(output.relative_to(ROOT)), 'size': asset['size'],
                         'mode': 'RGB', 'bytes': output.stat().st_size,
                         'sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
                         'safe_area': asset['safe_area'], 'today_crop': config['today_crop'],
                         'inputs': inputs, 'key_content_bounds': bounds.split('\nhelp')[0]})
        print(f'Rendered header/{asset["id"]}', flush=True)
    (HEADER / 'render-manifest.json').write_text(json.dumps(metadata, indent=2)+'\n')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--size', choices=SIZES, action='append')
    parser.add_argument('--frame', help='Render only this frame id')
    parser.add_argument('--header', action='store_true', help='Render both header creative assets and crop previews only')
    args = parser.parse_args()
    if args.header:
        if args.size or args.frame:
            parser.error('--header cannot be combined with screenshot filters')
        render_headers()
        return
    frames = json.loads((DEST / 'frames.json').read_text())
    template = (DEST / 'template.html').read_text()
    metadata = []
    run('newpage', (DEST/'template.html').as_uri())
    for size in args.size or SIZES:
        width, height = SIZES[size]
        directory = DEST / size
        directory.mkdir(exist_ok=True)
        run('resize', width, height)
        for index, frame in enumerate(frames, 1):
            if args.frame and frame['id'] != args.frame:
                continue
            source_path = frame.get('source_by_size', {}).get(size, frame['source'])
            source = ROOT / source_path
            with Image.open(source) as im:
                sw, sh = im.size
            zoom_width = 1140 / .92
            # frames.json may move the enlarged detail when its content sits elsewhere in the capture.
            zoom_top = -(sh / sw) * zoom_width * frame.get('zoom_top', .285 if frame['layout'] == 'water' else .53)
            zoom = ''
            if frame['layout'] in ('water', 'extras'):
                zoom_style = f' style="height:{frame["zoom_height"]}px"' if 'zoom_height' in frame else ''
                zoom = ('<div class="zoom ' + frame['layout'] + '"' + zoom_style + '><img src="__SOURCE__" '
                        'alt="Enlarged detail from the same capture"></div>'
                        '<div class="zoom-note">A closer look at ' +
                        ('water tracking.' if frame['layout'] == 'water' else 'your extras.') + '</div>')
            values = {'WIDTH': width, 'HEIGHT': height, 'SCALE': width / 1320, 'CANVAS_HEIGHT': height * 1320 / width,
                      'THEME': frame['theme'], 'LAYOUT': frame['layout'], 'ZOOM': zoom,
                      'ZOOM_WIDTH': zoom_width, 'ZOOM_LEFT': -.04 * zoom_width,
                      'ZOOM_TOP': zoom_top, 'TAG': html.escape(frame['tag']),
                      'HEADLINE': ''.join('<span>'+html.escape(s)+'</span>' for s in frame['headline']),
                      'DETAIL': html.escape(frame['detail']), 'SOURCE': source.as_uri(),
                      'ICON': (ROOT/'Resources/AppIcon/icon_1024.png').as_uri(), 'NUMBER': f'{index:02}', 'TOTAL': f'{len(frames):02}'}
            page = template
            # ZOOM first, because its fragment contains the SOURCE placeholder.
            page = page.replace('__ZOOM__', zoom)
            for key, value in values.items():
                page = page.replace('__'+key+'__', str(value))
            target = directory / (frame['id'] + '.html')
            # Local paths remain reproducible when the checkout moves: render-only
            # HTML lives in .build; only the path-independent template is committed.
            working = ROOT/'.build/app-store-marketing'/size
            working.mkdir(parents=True, exist_ok=True)
            target = working / target.name
            target.write_text(page)
            run('open', target.as_uri())
            run('eval', 'async () => { await document.fonts.ready; await Promise.all(Array.from(document.images).map(i => i.decode())); return {width:innerWidth,height:innerHeight}; }')
            run('eval', '''() => { const safe = document.querySelector('.canvas').getBoundingClientRect(); for (const e of document.querySelectorAll('.brand,.copy,.footer,.zoom,.phone,.zoom-note')) { const r=e.getBoundingClientRect(); if(r.left<0 || r.top<0 || r.right>safe.right+1 || r.bottom>safe.bottom+1) throw Error('Clipped '+e.className); } for(const d of document.querySelectorAll('.detail,h1 span')) if(d.scrollWidth>d.clientWidth) throw Error('Clipped caption'); return 'Layout safe'; }''')
            bounds = run('eval', '() => Array.from(document.querySelectorAll(".brand,.copy,.footer,.zoom,.phone")).map(e=>{const r=e.getBoundingClientRect();return {class:e.className,x:r.x,y:r.y,width:r.width,height:r.height}})')
            output = directory / (frame['id'] + '.png')
            run('screenshot', output)
            with Image.open(output) as im:
                if im.size != (width, height):
                    raise ValueError(f'Incorrect export size {output}: {im.size}')
                im.convert('RGB').save(output, optimize=True)
            metadata.append({'output': str(output.relative_to(ROOT)), 'size': [width, height],
                             'source': source_path, 'source_size': [sw, sh],
                             'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                             'bounds': bounds.split('\nhelp')[0]})
            print(f'Rendered {size}/{frame["id"]}', flush=True)
        if not args.frame:
            sheet = Image.new('RGB', (len(frames)*280, 660), '#f6f8fd')
            draw = ImageDraw.Draw(sheet)
            for index, frame in enumerate(frames):
                with Image.open(directory/(frame['id']+'.png')) as im:
                    im.thumbnail((264, 574))
                    sheet.paste(im, (index*280+8, 36))
                draw.text((index*280+8, 10), frame['id'], fill='#0f172a')
            sheet.save(DEST/f'contact-sheet-{size}.png')
    if not args.frame:
        (DEST/'render-manifest.json').write_text(json.dumps(metadata, indent=2)+'\n')

if __name__ == '__main__':
    main()

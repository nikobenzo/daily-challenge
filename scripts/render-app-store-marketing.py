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

def run(*args):
    env = dict(os.environ, CHROME_DEVTOOLS_AXI_SESSION='dc-appstore-marketing')
    result = subprocess.run(['chrome-devtools-axi', *map(str, args)], cwd=ROOT,
                            env=env, text=True, timeout=90, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(result.stdout)
    return result.stdout

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--size', choices=SIZES, action='append')
    parser.add_argument('--frame', help='Render only this frame id')
    args = parser.parse_args()
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
            zoom_top = -(sh / sw) * zoom_width * (.285 if frame['layout'] == 'water' else .53)
            zoom = ''
            if frame['layout'] in ('water', 'extras'):
                zoom = ('<div class="zoom ' + frame['layout'] + '"><img src="__SOURCE__" '
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

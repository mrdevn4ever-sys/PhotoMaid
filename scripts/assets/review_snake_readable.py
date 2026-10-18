#!/usr/bin/env python3
"""Static design proofs, never simulator screenshots. Uses the compiled Core probe's JSON.

Photos are the existing CC0 QA fixtures documented in app-store/media/SOURCES.md.
This utility renders a new review sheet; it does not edit the production PNG atlas.
"""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/snake-readable-20261018'
ATLAS = ROOT / 'PhotoMaid/Resources/SnakePhoto/SnakeTopDown.atlas'
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
PHOTOS = sorted((ROOT / 'app-store/media').glob('*.jpg'))
SCALE = 3


def text(draw, xy, value, size=15, fill='#dcebd3'):
    draw.text(xy, value, font=ImageFont.truetype(FONT, size), fill=fill)


def tile(index, side, border):
    size = round(side * SCALE)
    with Image.open(PHOTOS[index % len(PHOTOS)]) as image:
        image = ImageOps.fit(image.convert('RGBA'), (size, size), method=Image.Resampling.LANCZOS)
    mask = Image.new('L', image.size)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size-1, size-1), radius=size * .33, fill=255)
    image.putalpha(mask)
    ImageDraw.Draw(image).rounded_rectangle((0, 0, size-1, size-1), radius=size * .33,
                                            outline='#5ca647', width=round(border * SCALE))
    return image


def board(sample):
    w, h, c = sample['width'], sample['height'], sample['pitch']
    side, border = sample['photoSide'], sample['border']
    cols, rows = sample['columns'], sample['rows']
    result = Image.new('RGBA', (round(w * SCALE), round(h * SCALE)), '#10271b')
    draw = ImageDraw.Draw(result)
    ox, oy = (w - cols * c) / 2, (h - rows * c) / 2
    def pos(x, y): return ((ox + x * c) * SCALE, (oy + y * c) * SCALE)
    draw.rounded_rectangle((*pos(0, 0), *pos(cols, rows)), radius=24, fill='#0c2917', outline='#516852', width=3)
    for x in range(1, cols): draw.line((pos(x, 0), pos(x, rows)), fill='#213d2b', width=3)
    for y in range(1, rows): draw.line((pos(0, y), pos(cols, y)), fill='#213d2b', width=3)
    for x1, y1, x2, y2 in sample['lines']:
        a, b = pos(x1, y1), pos(x2, y2)
        for width, color in [(side * .42, '#3d8f24'), (side * .10, '#64a64e')]:
            draw.line((a, b), fill=color, width=round(width * SCALE))
            r = width * SCALE / 2
            for x, y in (a, b): draw.ellipse((x-r, y-r, x+r, y+r), fill=color)
    for i, (x, y) in enumerate(sample['points'][1:]):
        photo = tile(i, side, border)
        px, py = pos(x, y)
        result.alpha_composite(photo, (round(px-photo.width/2), round(py-photo.height/2)))
    head = Image.open(ATLAS / f'top_snake_idle_{sample["direction"]}.png')
    head.thumbnail((round(side * 1.1 * SCALE), round(side * 1.1 * SCALE)), Image.Resampling.LANCZOS)
    hx, hy = pos(*sample['points'][0])
    result.alpha_composite(head, (round(hx-head.width/2), round(hy-head.height/2)))
    return result.convert('RGB').resize((round(w), round(h)), Image.Resampling.LANCZOS)


def main():
    samples = json.loads((OUT / 'layout-samples.json').read_text())
    canvas = Image.new('RGB', (1253, 970), '#112c22')
    d = ImageDraw.Draw(canvas)
    text(d, (18, 12), 'STATISCHE ENTWURFSVORSCHAU - KEIN iOS-/SIMULATOR-SCREENSHOT', 19)
    text(d, (18, 43), 'Tatsaechliche Core-Koordinaten, Atlas-PNGs und CC0-Testfotos. Ohne Gameplay-HUD.', 15)
    x = 16
    for sample in samples[:3]:
        text(d, (x, 76), f'{sample["width"]} x {sample["height"]} pt / {sample["photoSide"]:.2f} pt Fotos')
        canvas.paste(board(sample), (x, 107))
        x += sample['width'] + 20
    canvas.save(OUT / 'static-phone-design.png')
    sample = samples[-1]
    large = Image.new('RGB', (776, 1106), '#112c22')
    text(ImageDraw.Draw(large), (20, 13), 'STATISCH / 736 x 1024 pt / keine Duo-Abnahme', 18)
    large.paste(board(sample), (20, 62)); large.save(OUT / 'static-wide-design.png')
    poses = ['idle', 'blink', 'halfBlink', 'tongue', 'eat', 'hurt', 'dead', 'sleep', 'surprised', 'lookLeft', 'lookRight']
    for char in ['snake', 'dragon', 'dino', 'monster']:
        cp = poses if char == 'snake' else ['idle', 'blink', 'eat', 'dead']
        sheet = Image.new('RGB', (760, len(cp)*155+45), '#112c22'); draw = ImageDraw.Draw(sheet)
        text(draw, (16, 8), f'Original overhead art / {char}', 16)
        for row, pose in enumerate(cp):
            for col, direction in enumerate(['up', 'right', 'down', 'left']):
                with Image.open(ATLAS / f'top_{char}_{pose}_{direction}.png') as frame:
                    frame.thumbnail((110, 110), Image.Resampling.LANCZOS)
                    sheet.paste(frame, (col*190+38, row*155+39), frame)
                text(draw, (col*190+9, row*155+150), f'{pose} / {direction}', 16)
        sheet.save(OUT / f'head-review-{char}.png')
    print('Static design proofs created; these are not native UI/FPS evidence.')


if __name__ == '__main__': main()

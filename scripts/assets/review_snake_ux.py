#!/usr/bin/env python3
"""Static UX studies from actual Core coordinates and localized copy, NOT native screenshots.

The production implementation remains SwiftUI/SpriteKit. This local review utility draws
new documentation only. Photo fixtures and their CC0 credits: app-store/media/SOURCES.md.
"""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/snake-ux-20261018'
ATLAS = ROOT / 'PhotoMaid/Resources/SnakePhoto/SnakeTopDown.atlas'
CATALOG = json.loads((ROOT / 'PhotoMaid/Resources/Localizable.xcstrings').read_text())['strings']
STRINGS = {key: {lang: entry['stringUnit']['value'] for lang, entry in value['localizations'].items()}
           for key, value in CATALOG.items() if 'localizations' in value}
PHOTOS = sorted((ROOT / 'app-store/media').glob('*.jpg'))
S = 3


def font(size, bold=False):
    name = 'DejaVuSans-Bold.ttf' if bold else 'DejaVuSans.ttf'
    return ImageFont.truetype('/usr/share/fonts/truetype/dejavu/' + name, round(size*S))


def label(image, xy, value, size=16, bold=False, fill='#f7fbf5', anchor=None):
    ImageDraw.Draw(image).text((round(xy[0]*S), round(xy[1]*S)), value, font=font(size, bold), fill=fill, anchor=anchor)


def paragraph(image, xy, value, width, size=15, fill='#d6e2d8', centre=False):
    d = ImageDraw.Draw(image); f = font(size); lines = []; current = ''
    for word in value.split():
        candidate = (current + ' ' + word).strip()
        if current and d.textlength(candidate, font=f) > width*S:
            lines.append(current); current = word
        else: current = candidate
    if current: lines.append(current)
    for i, line in enumerate(lines):
        x = xy[0] + (width - d.textlength(line, font=f)/S)/2 if centre else xy[0]
        label(image, (x, xy[1]+i*size*1.4), line, size, fill=fill)


def rect(image, box, fill, radius=16, outline=None, width=1):
    ImageDraw.Draw(image).rounded_rectangle(tuple(round(x*S) for x in box), radius=round(radius*S),
        fill=fill, outline=outline, width=round(width*S))


def button(image, x, y, width, title, primary=False, height=52):
    rect(image, (x, y, x+width, y+height), '#a8e65c' if primary else '#263c30', outline='#bce988' if primary else '#4b6052')
    f = font(17, True); d = ImageDraw.Draw(image)
    label(image, (x+width/2-d.textlength(title, font=f)/S/2, y+(height-22)/2-1), title, 17, True, '#0a2412' if primary else '#f7fbf5')


def circle_photo(index, diameter, border):
    size = round(diameter*S)
    with Image.open(PHOTOS[index % len(PHOTOS)]) as source:
        image = ImageOps.fit(source.convert('RGBA'), (size, size), method=Image.Resampling.LANCZOS)
    mask = Image.new('L', image.size); ImageDraw.Draw(mask).ellipse((0, 0, size-1, size-1), fill=255)
    image.putalpha(mask)
    ImageDraw.Draw(image).ellipse((0, 0, size-1, size-1), outline='#5ca647', width=round(border*S))
    return image


def head(image, x, y, side, direction='up'):
    with Image.open(ATLAS / f'top_snake_idle_{direction}.png') as art:
        art = art.resize((round(side*S), round(side*S)), Image.Resampling.LANCZOS)
        image.alpha_composite(art, (round((x-side/2)*S), round((y-side/2)*S)))


def board(sample, initial=False):
    w, h, c, diameter = sample['width'], sample['height'], sample['pitch'], sample['photoSide']
    cols, rows = sample['columns'], sample['rows']
    image = Image.new('RGBA', (round(w*S), round(h*S)), '#102719')
    ox, oy = (w-cols*c)/2, (h-rows*c)/2
    def p(x, y): return ((ox+x*c)*S, (oy+y*c)*S)
    d = ImageDraw.Draw(image)
    d.rounded_rectangle((*p(0, 0), *p(cols, rows)), radius=24, fill='#0c2917', outline='#50694f', width=3)
    for x in range(1, cols): d.line((p(x, 0), p(x, rows)), fill='#1d3825', width=3)
    for y in range(1, rows): d.line((p(0, y), p(cols, y)), fill='#1d3825', width=3)
    points = sample['initialPoints'] if initial else sample['points']
    lines = [a+b for a, b in zip(points, points[1:])] if initial else sample['lines']
    for x1, y1, x2, y2 in lines:
        d.line((p(x1, y1), p(x2, y2)), fill='#3d8f24', width=round(diameter*.42*S))
    # Match SpriteKit's explicit layering: tail behind, neck in front; never arbitrary sibling order.
    for i in reversed(range(1, len(points))):
        tile = circle_photo(i-1, diameter, sample['border']); px, py = p(*points[i])
        image.alpha_composite(tile, (round(px-tile.width/2), round(py-tile.height/2)))
    hx, hy = p(*points[0]); head(image, hx/S, hy/S, sample['headSide'], 'right' if initial else sample['direction'])
    return image


def gameplay(sample, ready=False):
    image = Image.new('RGBA', (402*S, 874*S), '#102719')
    image.alpha_composite(board(sample, ready), (4*S, 96*S))
    rect(image, (12, 12, 390, 84), '#07130c', radius=24)
    label(image, (25, 29), '×', 29); label(image, (72, 35), 'Ⅱ', 21)
    label(image, (246, 25), 'Score: ' + ('0' if ready else str(sample['score'])), 17, True)
    label(image, (246, 50), 'Rekord: ' + str(sample['score']), 13, fill='#d5e4d6')
    label(image, (360, 34), '⚙', 22)
    if ready:
        tint = Image.new('RGBA', (394*S, 760*S), (0, 0, 0, 61)); image.alpha_composite(tint, (4*S, 96*S))
        rect(image, (28, 282, 374, 626), '#082114', radius=28)
        head(image, 102, 328, 48)
        label(image, (140, 308), STRINGS['snake_title']['de'], 27, True)
        paragraph(image, (52, 367), STRINGS['snake_controls_hint']['de'], 298, centre=True)
        button(image, 52, 432, 298, STRINGS['snake_start_game']['de'], True)
        button(image, 52, 496, 298, STRINGS['game_setup_edit_photos']['de'])
        button(image, 91, 563, 220, STRINGS['snake_other_games']['de'], height=40)
    return image.convert('RGB')


def setup():
    image = Image.new('RGBA', (402*S, 874*S), '#102719')
    button(image, 16, 12, 105, STRINGS['close']['de'], height=42)
    button(image, 214, 12, 172, STRINGS['snake_other_games']['de'], height=42)
    rect(image, (16, 76, 386, 842), '#0a2617', radius=30)
    head(image, 201, 126, 64)
    label(image, (201, 176), STRINGS['snake_title']['de'], 32, True, anchor='mt')
    label(image, (201, 226), 'Rekord: 16', 15, anchor='mt')
    rect(image, (36, 272, 366, 479), '#1b3527', radius=18)
    label(image, (52, 288), STRINGS['game_setup_photos']['de'], 13, True, '#ccdbce')
    rect(image, (52, 316, 350, 362), '#2a4434', radius=12)
    label(image, (64, 328), STRINGS['memory_source_library']['de'], 16)
    label(image, (325, 329), '⌄', 17)
    button(image, 52, 378, 298, STRINGS['game_setup_choose_photos']['de'])
    paragraph(image, (52, 445), STRINGS['game_setup_private']['de'], 298, 12)
    button(image, 36, 502, 330, STRINGS['snake_start_game']['de'], True)
    paragraph(image, (44, 575), STRINGS['snake_controls_hint']['de'], 314, centre=True)
    rect(image, (36, 654, 366, 708), '#1b3527', radius=18)
    label(image, (54, 672), STRINGS['game_setup_options']['de'], 16, True)
    label(image, (331, 671), '⌄', 17)
    button(image, 76, 748, 250, STRINGS['game_setup_without_photos']['de'], height=42)
    return image.convert('RGB')


def main():
    samples = json.loads((OUT/'layout-samples.json').read_text())
    sample = next(s for s in samples if s['width'] == 394)
    sheet = Image.new('RGB', (1262*S, 1034*S), '#eef2e9')
    label(sheet, (22, 12), 'Foto-Snake · statische UX-Layoutstudie', 24, True, '#163620')
    label(sheet, (22, 51), 'Keine iOS-Screenshots. Core-Koordinaten, echte Atlas-PNGs und CC0-Testfotos; Beispielwerte.', 14, fill='#47604a')
    for x, title, image in [(14, '1 · Fotos und Start', setup()), (430, '2 · Klarer Startzustand', gameplay(sample, True)), (846, '3 · Runde Segmente', gameplay(sample))]:
        label(sheet, (x+4, 91), title, 19, True, '#163620')
        sheet.paste(image, (x*S, 132*S))
    sheet.resize((1262, 1034), Image.Resampling.LANCZOS).save(OUT/'static-ux-study.png')
    for sample in samples:
        image = board(sample).convert('RGB')
        image.resize((round(sample['width']), round(sample['height'])), Image.Resampling.LANCZOS).save(OUT/f'static-board-{sample["width"]}.png')
    print('Created explicitly static UX study and five board-size reviews; no native UI/FPS claim.')


if __name__ == '__main__': main()

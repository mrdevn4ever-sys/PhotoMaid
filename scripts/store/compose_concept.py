#!/usr/bin/env python3
"""Store-Bilder im Stil „Concept A – Space to Breathe“ aus echten nativen Aufnahmen setzen.

Marketing-Ebene (heller Grund, Schriftzug, Überschrift, Unterzeile, Gerätekontur) und App-Ebene bleiben getrennt:
die App-Aufnahme wird nur proportional verkleinert (nie vergrößert, nie verzerrt, nie retuschiert) und unten
angeschnitten. Der Schriftzug stammt aus der echten Startseiten-Aufnahme derselben Sprache und desselben Geräts.
Ausgabe in exakt Apples Maßen des Geräts (gleich der nativen Aufnahme), RGB ohne Alpha.
"""
import argparse
import functools
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

from wordmark_from_today import extract as extract_wordmark

ROOT = Path(__file__).resolve().parents[2]
FONTS = ROOT / 'PhotoMaid/Resources/Fonts'
INK = (0x1C, 0x19, 0x16)
SKY_TOP, SKY_BOTTOM = (0xE0, 0xEF, 0xF9), (0xEA, 0xF4, 0xFB)
GESTURE = {'keep': (0x1B, 0x6F, 0xA8), 'trash': (0xC4, 0x44, 0x1A), 'later': (0x63, 0x47, 0xD0)}
RTL = {'ar', 'he', 'ur'}
TEXT_OPTS = {'ar': {'direction': 'rtl', 'language': 'ar'}, 'he': {'direction': 'rtl', 'language': 'he'},
             'ur': {'direction': 'rtl', 'language': 'ur'}}
# Schriften der App für lateinische Schrift (wenn sie alle Zeichen hat); sonst die Systemschrift des macOS-Runners.
# Dateinamen statt fester Pfade: gesucht wird in den System-Schriftordnern (auch „Supplemental“).
SYSTEM = {
    'sf': ['SFNS.ttf', 'Helvetica.ttc'],
    'ar': ['SFArabic.ttf', 'GeezaPro.ttc'],
    'ur': ['SFArabic.ttf', 'GeezaPro.ttc'],
    'he': ['SFHebrew.ttf', 'ArialHB.ttc'],
    'ja': ['ヒラギノ角ゴシック W7.ttc', 'Hiragino Sans GB.ttc'],
    'ko': ['AppleSDGothicNeo.ttc'],
    'zh-Hans': ['PingFang.ttc', 'Hiragino Sans GB.ttc'],
    'zh-Hant': ['PingFang.ttc', 'Hiragino Sans CNS.ttc'],
    'th': ['Thonburi.ttc', 'SFThai.ttf'],
    'hi': ['Kohinoor.ttc', 'ITFDevanagari.ttc', 'DevanagariMT.ttc'],
    'mr': ['Kohinoor.ttc', 'ITFDevanagari.ttc', 'DevanagariMT.ttc'],
    'bn': ['KohinoorBangla.ttc', 'Bangla Sangam MN.ttc'],
    'gu': ['KohinoorGujarati.ttc', 'Gujarati Sangam MN.ttc'],
    'te': ['KohinoorTelugu.ttc', 'Telugu Sangam MN.ttc'],
    'pa': ['MuktaMahee.ttc', 'Gurmukhi Sangam MN.ttc', 'GurmukhiMN.ttc'],
    'ta': ['Tamil Sangam MN.ttc', 'TamilMN.ttc'],
    'kn': ['Kannada Sangam MN.ttc', 'NotoSansKannada.ttc', 'KannadaMN.ttc'],
    'ml': ['Malayalam Sangam MN.ttc', 'MalayalamMN.ttc'],
    'or': ['Oriya Sangam MN.ttc', 'NotoSansOriya.ttc', 'OriyaMN.ttc'],
}
FONT_DIRS = [Path('/System/Library/Fonts'), Path('/System/Library/Fonts/Supplemental'), Path('/Library/Fonts')]
WORDS = {}  # Sprache -> alle Texte (für die Zeichenprüfung)


def covers(path, text):
    f = ImageFont.truetype(str(path), 40)
    missing = f.getmask('\U0010FFFD').getbbox(), bytes(f.getmask('\U0010FFFD'))
    return all(ch.isspace() or (f.getmask(ch).getbbox(), bytes(f.getmask(ch))) != missing for ch in set(text))


@functools.lru_cache(maxsize=None)
def script_of(locale):
    if locale in SYSTEM: return locale
    text = WORDS.get(locale, '')
    return 'latin' if all(covers(FONTS / n, text) for n in ('PMDisplay-Bold.ttf', 'PMText-Medium.ttf', 'PMText-Bold.ttf')) else 'sf'


def find_font(name):
    for d in FONT_DIRS:
        if (d / name).exists(): return d / name
    for d in FONT_DIRS:
        hits = sorted(d.rglob(name)) if d.exists() else []
        if hits: return hits[0]
    return None


@functools.lru_cache(maxsize=None)
def font(locale, role, size):
    s = script_of(locale)
    if s == 'latin':
        name = {'head': 'PMDisplay-Bold.ttf', 'sub': 'PMText-Medium.ttf', 'gesture': 'PMText-Bold.ttf'}[role]
        return ImageFont.truetype(str(FONTS / name), size)
    want = ('Bold', 'Semibold', 'W7', 'W6', 'Heavy') if role in ('head', 'gesture') else ('Medium', 'Regular', 'W4', 'W3')
    for name in SYSTEM[s]:
        path = find_font(name)
        if path is None:
            continue
        path = str(path)
        faces = []
        for index in range(32):
            try: faces.append(ImageFont.truetype(path, size, index=index))
            except OSError: break
        for style in want:
            for f in faces:
                if f.getname()[1].replace(' ', '') == style and (s != 'zh-Hans' or any(x in f.getname()[0] for x in ('SC', 'GB'))) and (s != 'zh-Hant' or any(x in f.getname()[0] for x in ('TC', 'CNS'))):
                    return f
        f = faces[0]
        try: f.set_variation_by_name(want[0])  # variable Systemschrift (SF)
        except Exception: pass
        return f
    raise SystemExit(f'BLOCKED: keine Schrift für {locale} ({SYSTEM[s]})')


def gradient(w, h):
    im = Image.new('RGB', (w, h))
    d = ImageDraw.Draw(im)
    for y in range(h):
        t = y / (h - 1); t = t * t * (3 - 2 * t)
        d.line([(0, y), (w, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(SKY_TOP, SKY_BOTTOM)))
    return im


def fitted(draw, lines, locale, role, size, minimum, width):
    """Größte Schrift, bei der jede vorgegebene Zeile in die Breite passt (Zeilen werden nie umbrochen)."""
    for s in range(size, minimum - 1, -2):
        f = font(locale, role, s)
        if all(draw.textlength(l, font=f, **TEXT_OPTS.get(locale, {})) <= width for l in lines):
            return f
    raise SystemExit(f'Text zu lang für {locale}: {lines!r}')


def arrow(draw, box, direction, color):
    x0, y0, x1, y1 = box
    cx, cy, w = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0)
    head, shaft = w * 0.5, w * 0.18
    pts = {'up': [(cx, y0), (x1, y0 + head), (cx + shaft, y0 + head), (cx + shaft, y1), (cx - shaft, y1), (cx - shaft, y0 + head), (x0, y0 + head)]}
    base = pts['up']
    if direction == 'left': base = [(x0 + (p[1] - y0), y0 + (p[0] - x0)) for p in base]
    if direction == 'right': base = [(x1 - (p[1] - y0), y0 + (p[0] - x0)) for p in base]
    draw.polygon(base, fill=color)


def compose(native, today, slot, locale, device, out, all_heads=None, all_subs=None):
    if locale in TEXT_OPTS or script_of(locale) in ('hi', 'mr', 'bn', 'gu', 'te', 'pa', 'ta', 'kn', 'ml', 'or', 'th'):
        # Arabisch braucht echte Textformung (verbundene Buchstaben, rechts nach links).
        from PIL import features
        if not features.check('raqm'): raise SystemExit('BLOCKED: libraqm fehlt (Schrift würde ohne Textformung gesetzt)')
    src = Image.open(native).convert('RGB')
    W, H = src.size
    tablet = device == 'ipad'
    u = W / (1700 if tablet else 1206)
    rtl = locale in RTL
    im = gradient(W, H)
    d = ImageDraw.Draw(im, 'RGBA')
    m = round(70 * u)
    # Schriftzug: echte Pixel, nur verkleinert, falls größer als vorgesehen.
    wm = extract_wordmark(today, rtl=rtl)
    target_h = round(110 * u)
    if wm.height > target_h:
        wm = wm.resize((round(wm.width * target_h / wm.height), target_h), Image.LANCZOS)
    wx = W - m - wm.width if rtl else m
    im.paste(wm, (wx, round(78 * u)), wm)
    y = round(78 * u) + max(wm.height, round(90 * u)) + round(50 * u)
    head = slot['head']
    # Eine Schriftgröße für alle zehn Bilder einer Sprache (ruhiges, einheitliches Bild).
    fh = fitted(d, all_heads or head, locale, 'head', round(112 * u), round(70 * u), W - 2 * m)
    for line in head:
        x = W - m - d.textlength(line, font=fh, **TEXT_OPTS.get(locale, {})) if rtl else m
        d.text((x, y), line, font=fh, fill=INK, **TEXT_OPTS.get(locale, {}))
        y += round(fh.size * 1.16)
    if slot.get('sub'):
        y += round(14 * u)
        fs = fitted(d, all_subs or [slot['sub']], locale, 'sub', round(52 * u), round(34 * u), W - 2 * m)
        x = W - m - d.textlength(slot['sub'], font=fs, **TEXT_OPTS.get(locale, {})) if rtl else m
        d.text((x, y), slot['sub'], font=fs, fill=INK, **TEXT_OPTS.get(locale, {}))
        y += round(fs.size * 1.3)
    if slot.get('gestures'):
        y += round(26 * u)
        col = (W - 2 * m) / 3
        a = round(54 * u)
        fg = fitted(d, list(slot['gestures'].values()), locale, 'gesture', round(68 * u), round(36 * u), col - a - round(30 * u))
        for i, (key, direction) in enumerate((('keep', 'up'), ('trash', 'left'), ('later', 'right'))):
            # Pfeile zeigen die echte Fingerrichtung, auch in RTL nie gespiegelt.
            opts = TEXT_OPTS.get(locale, {})
            label = slot['gestures'][key]
            tw = d.textlength(label, font=fg, **opts)
            box = d.textbbox((0, 0), label, font=fg, **opts)
            ay = y + (box[1] + box[3]) / 2 - a / 2  # Pfeil mittig zur Schrift
            gap = round(14 * u)
            if rtl:  # Lesereihenfolge von rechts: Spalten gespiegelt, Pfeil rechts vom Wort
                x1 = W - m - i * col
                arrow(d, (x1 - a, ay, x1, ay + a), direction, GESTURE[key])
                d.text((x1 - a - gap - tw, y), label, font=fg, fill=GESTURE[key], **opts)
            else:
                x = m + i * col
                arrow(d, (x, ay, x + a, ay + a), direction, GESTURE[key])
                d.text((x + a + gap, y), label, font=fg, fill=GESTURE[key], **opts)
        y += round(84 * u)
    top = y + round(64 * u)
    # Gerät: native Aufnahme proportional verkleinert, unten angeschnitten.
    width = round(W * (0.80 if tablet else 0.78))
    scale = width / W
    assert scale <= 1
    shot = src.resize((width, round(H * scale)), Image.LANCZOS)
    radius = round((60 if tablet else 140) * u * scale)
    frame = round(9 * u)
    x0 = (W - width) // 2
    shadow = Image.new('L', (W, H), 0)
    ImageDraw.Draw(shadow).rounded_rectangle([x0 - frame, top - frame + round(12 * u), x0 + width + frame, H + radius], radius + frame, fill=70)
    im.paste((0, 0, 0), (0, 0), shadow.filter(ImageFilter.GaussianBlur(20 * u)))
    ImageDraw.Draw(im).rounded_rectangle([x0 - frame, top - frame, x0 + width + frame, H + radius], radius + frame, fill=(0x24, 0x23, 0x22))
    mask = Image.new('L', shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, shot.width - 1, shot.height - 1 + radius], radius, fill=255)
    im.paste(shot, (x0, top), mask)
    assert im.size == (W, H) and im.mode == 'RGB'
    im.save(out, optimize=True)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('assets', type=Path, help='Ausgabe von assemble_refresh.py (all-pages/…)')
    p.add_argument('--locale', required=True)
    p.add_argument('--device', required=True)
    p.add_argument('--texts', type=Path, default=ROOT / 'app-store/concept/headlines.json')
    a = p.parse_args()
    texts = json.loads(a.texts.read_text())
    slots, words = texts['slots'], texts['locales'].get(a.locale) or texts['locales']['en']
    WORDS[a.locale] = json.dumps(words, ensure_ascii=False)
    pages = {f.stem: f for f in (a.assets / 'all-pages').glob('*/*.png')}
    out = a.assets / 'concept'
    out.mkdir(exist_ok=True)
    rows = []
    for i, slot in enumerate(slots, 1):
        text = dict(words[slot['id']])
        if slot['id'] == 'swipe': text['gestures'] = words['gestures']
        target = out / f"{i:02}-{slot['id']}.png"
        heads = [l for s in slots for l in words[s['id']]['head']]
        subs = [words[s['id']]['sub'] for s in slots]
        compose(pages[slot['source']], pages['today'], text, a.locale, a.device, target, heads, subs)
        rows.append({'file': target.name, 'native_source': slot['source'],
                     'sha256': hashlib.sha256(target.read_bytes()).hexdigest()})
    (out / 'concept.json').write_text(json.dumps({'locale': a.locale, 'device': a.device, 'images': rows}, indent=1) + '\n')
    print('PASS: concept', a.locale, a.device, len(rows))


if __name__ == '__main__':
    main()

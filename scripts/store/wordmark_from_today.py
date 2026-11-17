#!/usr/bin/env python3
"""Schriftzug „GaleriQ“ (Tresor-Rad als Q) aus der echten, dunklen Startseiten-Aufnahme lösen.

Nur Pixel der App: Helligkeit über dem Seitengrund wird zur Deckkraft, gefärbt in Tinte. Nie vergrößert."""
from PIL import Image


def extract(path, ink=(0x1C, 0x19, 0x16)):
    im = Image.open(path).convert('RGB')
    w, h = im.size
    gray = im.convert('L')
    bg = sorted(gray.crop((0, int(h * 0.02), int(w * 0.05), int(h * 0.15))).get_flattened_data())[0x80]
    tablet = w / h > 0.6
    # Schriftzug steht oben links; auf dem iPad beginnt rechts daneben schon die erste Karte.
    top, bottom = int(h * 0.02), int(h * (0.09 if tablet else 0.17))
    left, right = 0, int(w * (0.25 if tablet else 0.5))
    # Zeilen mit hellen Pixeln (Weiß des Schriftzugs, nicht das graue Grußwort) zu Bändern zusammenfassen.
    rows = [any(gray.getpixel((x, y)) > 215 for x in range(left, right, 2)) for y in range(top, bottom)]
    bands, start = [], None
    for i, on in enumerate(rows + [False]):
        if on and start is None: start = i
        if not on and start is not None: bands.append((start + top, i + top)); start = None
    assert bands, 'Schriftzug nicht gefunden'
    y0, y1 = max(bands, key=lambda b: b[1] - b[0])
    pad = int((y1 - y0) * 0.3)
    y0, y1 = max(top, y0 - pad), min(bottom, y1 + pad)
    cols = [x for x in range(left, right) if any(gray.getpixel((x, y)) > bg + 40 for y in range(y0, y1, 2))]
    x0, x1 = min(cols), max(cols) + 1
    crop = gray.crop((x0, y0, x1, y1))
    alpha = crop.point(lambda v: max(0, min(255, round((v - bg) * 255 / max(1, 245 - bg)))))
    out = Image.new('RGBA', crop.size, ink + (0,))
    out.putalpha(alpha)
    # Nur das größte zusammenhängende Band behalten (Reste des Grußworts darüber fallen weg).
    mask = alpha.point(lambda v: 255 if v > 24 else 0)
    rows = [any(mask.getpixel((x, y)) for x in range(0, mask.width, 2)) for y in range(mask.height)]
    best, start = (0, 0), None
    for i, on in enumerate(rows + [False]):
        if on and start is None: start = i
        if not on and start is not None:
            if i - start > best[1] - best[0]: best = (start, i)
            start = None
    out = out.crop((0, best[0], out.width, best[1]))
    return out.crop(out.getchannel('A').point(lambda v: 255 if v > 24 else 0).getbbox())


if __name__ == '__main__':
    import sys
    extract(sys.argv[1]).save(sys.argv[2])

#!/usr/bin/env python3
"""Author and rasterize PhotoMaid's own flat, overhead Snake art. Local Inkscape only.

No original kit PNG is edited. Features are positioned in the travel coordinate system;
eye highlights stay in screen coordinates. Thus down is an overhead snout pointing down,
not an upside-down frontal face. Re-run with --check to verify all committed PNG hashes.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "PhotoMaid/Resources/SnakePhoto/SnakeTopDown.atlas"
MANIFEST = ROOT / "docs/snake-readable-20261018/head-art.json"
POSES = ["idle", "blink", "halfBlink", "tongue", "eat", "hurt", "dead", "sleep", "surprised", "lookLeft", "lookRight"]
PALETTES = {
    "snake": ("#72CF60", "#C7EF8F", "#214E35", "#4AAA52"),
    "dragon": ("#F3AE58", "#FFE3A1", "#674029", "#D18340"),
    "dino": ("#55BDB1", "#B6E6BD", "#245558", "#329D94"),
    "monster": ("#DBDB65", "#F6F4B0", "#515234", "#ABAE4D"),
}
DIRECTIONS = {"up": 0, "right": 90, "down": 180, "left": 270}


def point(x, y, degrees):
    a = math.radians(degrees)
    return (128 + math.cos(a) * (x - 128) - math.sin(a) * (y - 128),
            128 + math.sin(a) * (x - 128) + math.cos(a) * (y - 128))


def svg(character, pose, direction):
    skin, snout, ink, pattern = PALETTES[character]
    degrees = DIRECTIONS[direction]
    turn = f"rotate({degrees} 128 128)"
    extra = ""
    if character == "dragon":
        extra = f'<path d="M49 158 Q25 164 16 184 L56 184 M207 158 Q231 164 240 184 L200 184" fill="#FFE2A1" stroke="{ink}" stroke-width="5" stroke-linejoin="round"/>'
    elif character == "dino":
        extra = f'<path d="M115 183 L128 166 L141 183 L128 196Z M116 211 L128 197 L140 211 L128 223Z" fill="{pattern}"/>'
    elif character == "monster":
        extra = f'<path d="M56 140 Q27 153 35 177 L67 165 M200 140 Q229 153 221 177 L189 165" fill="#A798D3" stroke="{ink}" stroke-width="5" stroke-linejoin="round"/>'
    tongue = ""
    if pose in ("tongue", "eat"):
        tongue = '<path d="M128 39 L128 13 M128 17 L119 9 M128 17 L137 9" stroke="#DF718B" stroke-width="5" fill="none" stroke-linecap="round"/>'
    shapes = f'''<g transform="{turn}">{tongue}
      <path d="M102 242 L154 242 C158 222 189 215 207 187 C224 160 215 132 198 106 L167 56 Q152 31 128 19 Q104 31 89 56 L58 106 C41 132 32 160 49 187 C67 215 98 222 102 242Z" fill="{skin}" stroke="{ink}" stroke-width="6" stroke-linejoin="round"/>
      <path d="M82 105 Q94 67 128 44 Q162 67 174 105 Q128 120 82 105Z" fill="{snout}"/>
      <g fill="{pattern}" opacity=".7"><ellipse cx="112" cy="190" rx="7" ry="9"/><ellipse cx="144" cy="190" rx="7" ry="9"/><ellipse cx="128" cy="211" rx="6" ry="8"/></g>
      {extra}
      <ellipse cx="111" cy="65" rx="3.3" ry="4.5" fill="{ink}"/>
      <ellipse cx="145" cy="65" rx="3.3" ry="4.5" fill="{ink}"/>
    </g>'''
    if pose == "eat":
        shapes += f'<g transform="{turn}"><ellipse cx="128" cy="37" rx="14" ry="7" fill="{ink}"/><path d="M121 39 Q128 35 135 39" fill="none" stroke="#DF718B" stroke-width="4" stroke-linecap="round"/></g>'
    for x in [76, 180]:
        ex, ey = point(x, 149, degrees)
        eye = f'rotate({degrees} {ex:.3f} {ey:.3f})'
        if pose in ("blink", "sleep"):
            shapes += f'<path d="M{ex-13:.3f} {ey:.3f} q13 10 26 0" transform="{eye}" fill="none" stroke="{ink}" stroke-width="5" stroke-linecap="round"/>'
            continue
        shapes += f'<ellipse cx="{ex:.3f}" cy="{ey:.3f}" rx="17" ry="{13 if pose == "halfBlink" else 21}" transform="{eye}" fill="#FCFFF5" stroke="{ink}" stroke-width="4"/>'
        if pose == "dead":
            shapes += f'<g transform="{eye}" stroke="{ink}" stroke-width="4" stroke-linecap="round"><path d="M{ex-7:.3f} {ey-7:.3f} l14 14 M{ex+7:.3f} {ey-7:.3f} l-14 14"/></g>'
            continue
        offset = -5 if pose == "lookLeft" else 5 if pose == "lookRight" else 0
        px, py = point(x + offset, 143, degrees)
        pupil = 5.4 if pose != "surprised" else 3.8
        shapes += f'<ellipse cx="{px:.3f}" cy="{py:.3f}" rx="{pupil}" ry="{7 if pose != "halfBlink" else 4}" transform="rotate({degrees} {px:.3f} {py:.3f})" fill="{ink}"/>'
        # Fixed upper-left glint, independent of travel direction: no rotated frontal eye highlights.
        shapes += f'<circle cx="{px-1.8:.3f}" cy="{py-2.8:.3f}" r="1.9" fill="white"/>'
        if pose == "hurt":
            shapes += f'<path d="M{ex-13:.3f} {ey-11:.3f} l24 9" transform="{eye}" stroke="{ink}" stroke-width="5" stroke-linecap="round"/>'
    return '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">' + shapes + '</svg>'


def generate():
    OUT.mkdir(parents=True, exist_ok=True)
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    entries, actions = [], []
    with tempfile.TemporaryDirectory(prefix="photomaid-overhead-") as directory:
        for character in PALETTES:
            poses = POSES if character == "snake" else ["idle", "blink", "eat", "dead"]
            for pose in poses:
                for direction, degrees in DIRECTIONS.items():
                    name = f"top_{character}_{pose}_{direction}"
                    source = Path(directory) / (name + ".svg")
                    source.write_text(svg(character, pose, direction))
                    target = OUT / (name + ".png")
                    actions.append(f"file-open:{source};export-filename:{target};export-width:256;export-height:256;export-do;file-close")
                    entries.append({"name": name, "character": character, "pose": pose, "direction": direction,
                                    "nose": point(128, 37, degrees), "eyes": [point(x, 149, degrees) for x in [76, 180]],
                                    "source_svg_sha256": hashlib.sha256(source.read_bytes()).hexdigest()})
        result = subprocess.run(["inkscape", "--shell"], input="\n".join(actions) + "\n", text=True, capture_output=True)
        if result.returncode:
            raise RuntimeError(result.stderr[-3000:])
    for entry in entries:
        data = (OUT / (entry["name"] + ".png")).read_bytes()
        entry.update(sha256=hashlib.sha256(data).hexdigest(), bytes=len(data))
    MANIFEST.write_text(json.dumps({"origin": "Original PhotoMaid vector art, generated locally from scripts/assets/make_snake_topdown.py; no kit images edited", "pixels": 256, "assets": entries}, indent=2) + "\n")
    print(f"Generated {len(entries)} overhead animation frames locally.")


def check():
    manifest = json.loads(MANIFEST.read_text())
    assert len(manifest["assets"]) == 92
    assert {p.stem for p in OUT.glob('*.png')} == {a['name'] for a in manifest['assets']}
    for entry in manifest["assets"]:
        data = (OUT / (entry["name"] + ".png")).read_bytes()
        assert hashlib.sha256(data).hexdigest() == entry["sha256"]
        assert len(data) == entry["bytes"]
        authored = svg(entry['character'], entry['pose'], entry['direction']).encode()
        assert hashlib.sha256(authored).hexdigest() == entry['source_svg_sha256']
    print("PASS: 92 original overhead frames, source SVG and PNG hashes.")


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    check() if args.check else generate()

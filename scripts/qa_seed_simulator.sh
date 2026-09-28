#!/usr/bin/env bash
# Legt SYNTHETISCHE QA-Medien im gebooteten Simulator an (nie auf einem privaten iPhone).
# Voraussetzung: macOS mit Xcode, python3 + Pillow, ffmpeg optional für Testvideos.
set -euo pipefail
OUT="$(mktemp -d)/photomaid-qa"
mkdir -p "$OUT"
python3 - "$OUT" <<'PY'
import sys, pathlib
from PIL import Image, ImageDraw
out = pathlib.Path(sys.argv[1])
sizes = {"hoch": (1170, 2532), "quer": (2532, 1170), "panorama": (6000, 1200), "quadrat": (1500, 1500)}
for i in range(24):
    name, size = list(sizes.items())[i % len(sizes)]
    img = Image.new("RGB", size, (200 - i * 5, 220, 255 - i * 3))
    d = ImageDraw.Draw(img)
    d.rectangle([20, 20, size[0] - 20, size[1] - 20], outline=(255, 255, 255), width=12)
    d.text((60, 60), f"PHOTOMAID QA {i:02d} {name}", fill=(10, 40, 80))
    img.save(out / f"QA_{i:02d}_{name}.jpg", quality=90)
# Exakte Duplikate (gleiche Bytes, anderer Name)
(out / "QA_DUP_A.jpg").write_bytes((out / "QA_00_hoch.jpg").read_bytes())
(out / "QA_DUP_B.jpg").write_bytes((out / "QA_00_hoch.jpg").read_bytes())
PY
if command -v ffmpeg >/dev/null; then
  ffmpeg -loglevel error -f lavfi -i testsrc=size=1080x1920:rate=30 -f lavfi -i sine=frequency=440 -t 6 -shortest -pix_fmt yuv420p "$OUT/QA_video_ton.mp4"
  ffmpeg -loglevel error -f lavfi -i testsrc=size=1920x1080:rate=30 -t 4 -an -pix_fmt yuv420p "$OUT/QA_video_stumm.mp4"
fi
xcrun simctl addmedia booted "$OUT"/*
echo "QA-Medien hinzugefügt aus $OUT"

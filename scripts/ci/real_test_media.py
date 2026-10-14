#!/usr/bin/env python3
"""Public, non-personal test photos for the iPhone simulator (never app fixtures).

130 photographs from Lorem Picsum, five byte-identical copies, ten blurred
photographs, five screenshot PNGs and three short videos. The manifest records
the source/author and SHA-256 of every import, so duplicate results are auditable.
Run only on a disposable simulator; no private photo library is accessed.
"""
import argparse
import concurrent.futures
import hashlib
import io
import json
import pathlib
import shutil
import subprocess
import time
import urllib.request

from PIL import Image, ImageDraw, ImageFilter


def download(url):
    for attempt in range(4):
        try:
            with urllib.request.urlopen(url, timeout=45) as response:
                return response.read()
        except Exception:
            if attempt == 3:
                raise
            time.sleep(attempt + 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument("--screenshot", type=pathlib.Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    sources = json.loads(download("https://picsum.photos/v2/list?page=1&limit=100"))
    sources += json.loads(download("https://picsum.photos/v2/list?page=2&limit=100"))[:30]
    assert len({source["id"] for source in sources}) == 130

    def photo(pair):
        index, source = pair
        name = f"photo_{index:03}.jpg"
        data = download(f'https://picsum.photos/id/{source["id"]}/960/720')
        with Image.open(io.BytesIO(data)) as image:
            image.verify()
        (args.output / name).write_bytes(data)
        return {"file": name, "kind": "photo", "source": source["url"],
                "author": source["author"], "picsum_id": source["id"]}

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        manifest = list(pool.map(photo, enumerate(sources)))
    for index in range(5):
        source = f"photo_{index:03}.jpg"
        name = f"duplicate_{index:02}.jpg"
        shutil.copyfile(args.output / source, args.output / name)
        manifest.append({"file": name, "kind": "exact_duplicate", "duplicate_of": source})
    for index in range(10):
        source = f"photo_{index:03}.jpg"
        name = f"blurred_{index:02}.jpg"
        with Image.open(args.output / source) as image:
            image.filter(ImageFilter.GaussianBlur(radius=36)).save(args.output / name, quality=90)
        manifest.append({"file": name, "kind": "blurry", "derived_from": source})
    for index in range(5):
        name = f"Screenshot_{index:02}.png"
        with Image.open(args.screenshot).convert("RGB") as image:
            # Real Simulator screenshot, distinct caption prevents extra duplicates.
            ImageDraw.Draw(image).text((30, 120), f"PhotoMaid Simulator {index}", fill="red")
            exif = Image.Exif()
            exif[0x0131] = "iOS 26"
            exif[0x8769] = {0x9286: b"ASCII\0\0\0Screenshot", 0xA002: image.width, 0xA003: image.height}
            image.save(args.output / name, exif=exif)
        manifest.append({"file": name, "kind": "screenshot"})
    for index in range(3):
        name = f"video_{index:02}.mp4"
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-loop", "1", "-i",
                        str(args.output / f"photo_{index:03}.jpg"), "-t", "3", "-r", "15",
                        "-vf", "scale=960:720", "-c:v", "libx264", "-pix_fmt", "yuv420p",
                        str(args.output / name)], check=True)
        manifest.append({"file": name, "kind": "video"})
    for item in manifest:
        data = (args.output / item["file"]).read_bytes()
        item.update(bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
    hashes = [item["sha256"] for item in manifest]
    assert len(hashes) - len(set(hashes)) == 5, "Exactly five extra duplicate copies required"
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Prepared {len(manifest)} PhotoKit imports, exactly five duplicate copies")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Partition existing CI evidence for review; retain original xcresult bytes.

No simulator/app is launched. PNGs are copied without modification and deduplicated
by SHA-256; index.json retains every original name. Full result bundles are packed
into a tar and divided into 200-MiB parts for connectors with a 512-MiB limit.
"""
import ctypes
import hashlib
import json
from pathlib import Path
import re
import shutil
import sys
import tarfile
import tempfile
import zipfile

source, output = map(Path, sys.argv[1:3])
output.mkdir(parents=True, exist_ok=True)
logs = output / "logs"
logs.mkdir(exist_ok=True)
index = []
stored = {}
image_bytes = 0
partition = 1


def retain(name, data, kind="image"):
    global image_bytes, partition
    digest = hashlib.sha256(data).hexdigest()
    if digest not in stored:
        if image_bytes + len(data) > 200 * 1024 * 1024:
            partition += 1
            image_bytes = 0
        folder = output / f"images-{partition}"
        folder.mkdir(exist_ok=True)
        suffix = ".png" if kind == "image" else ".txt"
        destination = folder / (digest[:24] + suffix)
        destination.write_bytes(data)
        stored[digest] = str(destination.relative_to(output))
        image_bytes += len(data)
    index.append(dict(name=name, kind=kind, sha256=digest, file=stored[digest]))


zstd = ctypes.CDLL("libzstd.so.1")
zstd.ZSTD_getFrameContentSize.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
zstd.ZSTD_getFrameContentSize.restype = ctypes.c_ulonglong
zstd.ZSTD_decompress.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t]
zstd.ZSTD_decompress.restype = ctypes.c_size_t
zstd.ZSTD_isError.argtypes = [ctypes.c_size_t]
zstd.ZSTD_isError.restype = ctypes.c_uint


def decode(data):
    if not data.startswith(b"\x28\xb5\x2f\xfd"):
        return data
    size = min(zstd.ZSTD_getFrameContentSize(data, len(data)), 16_000_000)
    buffer = ctypes.create_string_buffer(size)
    count = zstd.ZSTD_decompress(buffer, size, data, len(data))
    return b"" if zstd.ZSTD_isError(count) else buffer.raw[:count]


def inspect_bundle(bundle):
    blobs, attachments, images = {}, {}, {}
    for path in (bundle / "Data").glob("data.*"):
        with path.open("rb") as stream:
            prefix = stream.read(8)
        reference = path.name.removeprefix("data.")
        blobs[reference] = path
        if prefix.startswith(b"\x89PNG"):
            images[reference] = path
            continue
        if path.stat().st_size > 16_000_000:
            continue
        data = decode(path.read_bytes())
        for match in re.finditer(rb"ActionTestAttachmentK8:filename\[S6:StringK2:_vV(\d+):", data):
            length = int(match[1])
            name = data[match.end():match.end() + length].decode(errors="replace")
            tail = data[match.end():match.end() + length + 1800]
            ref = re.search(rb"K10:payloadRef\[S9:ReferenceK2:id\[S6:StringK2:_vV(\d+):", tail)
            if ref:
                attachments[name] = tail[ref.end():ref.end() + int(ref[1])].decode()
    for name, reference in attachments.items():
        path = blobs.get(reference)
        if path and (name.endswith(".png") or ".hierarchy" in name):
            retain(bundle.name + "/" + name, decode(path.read_bytes()),
                   "image" if name.endswith(".png") else "hierarchy")
    referenced = set(attachments.values())
    for reference, path in images.items():
        if reference not in referenced:
            retain(bundle.name + "/payload-" + reference[:20], path.read_bytes())


for mode in ("fixtures", "real"):
    directory = source / mode
    if directory.exists():
        for path in directory.rglob("*.png"):
            retain(str(path.relative_to(source)), path.read_bytes())
        for path in directory.rglob("*"):
            if path.is_file() and (path.suffix in (".json", ".txt") or ".hierarchy" in path.name):
                retain(str(path.relative_to(source)), path.read_bytes(), "hierarchy")
for path in source.iterdir():
    if path.is_file() and path.suffix in (".json", ".log", ".exit"):
        shutil.copyfile(path, logs / path.name)
manifest = source / "real-media" / "manifest.json"
if manifest.exists():
    shutil.copyfile(manifest, logs / "real-media-manifest.json")

with tempfile.TemporaryDirectory() as work:
    work = Path(work)
    bundles = list(source.glob("*.xcresult"))
    archives = list(source.glob("*.xcresult.zip"))
    for archive in archives:
        with zipfile.ZipFile(archive) as package:
            package.extractall(work)
    bundles += list(work.glob("*.xcresult"))
    for bundle in bundles:
        inspect_bundle(bundle)
    tar_path = work / "ui-xcresults.tar"
    with tarfile.open(tar_path, "w") as package:
        for bundle in bundles:
            package.add(bundle, arcname=bundle.name)
    parts = output / "xcresult-parts"
    parts.mkdir(exist_ok=True)
    with tar_path.open("rb") as stream:
        number = 0
        while data := stream.read(200 * 1024 * 1024):
            number += 1
            (parts / f"ui-xcresults.tar.part{number:03}").write_bytes(data)
    if number > 8 or partition > 4:
        raise RuntimeError("Evidence exceeds the configured upload partitions")

(logs / "index.json").write_text(json.dumps(index, ensure_ascii=False, indent=2) + "\n")
(logs / "README.txt").write_text(
    "PNG bytes are unchanged. index.json maps every original name to its SHA-256/file.\n"
    "Reassemble all result parts in numeric order: cat ui-xcresults.tar.part* > ui-xcresults.tar\n"
    "Then: tar -xf ui-xcresults.tar (original .xcresult directories).\n")
print(f"Retained {len(index)} names, {len(stored)} unique payloads; {number} result parts")

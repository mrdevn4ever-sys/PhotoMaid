#!/usr/bin/env python3
"""Baut PhotoMaid/Resources/ios_strings.json aus den Teil-Dateien (iOS-eigene Texte und Ersetzungen, 16 Sprachen).
Danach: python3 scripts/android_strings_to_xcstrings.py"""
import importlib, json, pathlib, sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
OUT = HERE.parent.parent / "PhotoMaid" / "Resources" / "ios_strings.json"

merged = {}
for p in sorted(HERE.glob("ios_strings_part*.py")):
    mod = importlib.import_module(p.stem)
    for k, v in mod.S.items():
        if k in merged:
            sys.exit(f"doppelt: {k} ({p.name})")
        merged[k] = v
info = importlib.import_module("infoplist").S
merged["_infoPlist"] = info
OUT.write_text(json.dumps(merged, ensure_ascii=False, indent=1, sort_keys=True) + "\n", encoding="utf-8")
print(f"{OUT}: {len(merged) - 1} Texte + {len(info)} InfoPlist")

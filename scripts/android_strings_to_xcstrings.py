#!/usr/bin/env python3
"""Erzeugt PhotoMaid/Resources/Localizable.xcstrings und InfoPlist.xcstrings.

Quelle 1: die 16 Android-`strings.xml` (photomaid-android, gleiche Kennungen, vorhandene Übersetzungen).
Quelle 2: PhotoMaid/Resources/ios_strings.json – iOS-eigene Texte und Ersetzungen für Texte, die auf iOS anders
lauten müssen (z. B. „Zuletzt gelöscht“ statt „Android-Papierkorb“). Ersetzungen haben Vorrang.

Umwandlung:
  %1$s → %1$@, %s → %@, %1$d → %1$lld, %d → %lld (Swift `String(format:)` mit Int und String)
  <plurals name="x"> → Einträge „x#zero|one|two|few|many|other“ (Auswahl in der App über PluralRules)

Aufruf:
  python3 scripts/android_strings_to_xcstrings.py            # schreiben
  python3 scripts/android_strings_to_xcstrings.py --check    # nur prüfen (CI): jede in Swift benutzte Kennung
                                                             # existiert in allen 16 Sprachen, kein „Android“-Text
Die Android-Quelle wird über die Umgebungsvariable PM_ANDROID_RES gefunden (Standard: ../photomaid-android/app/src/main/res).
Fehlt sie (z. B. in CI), wird nur ios_strings.json gegen den eingecheckten Katalog geprüft.
"""
import json
import os
import pathlib
import re
import sys
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
RES_OUT = ROOT / "PhotoMaid" / "Resources"
IOS_JSON = RES_OUT / "ios_strings.json"
OUT = RES_OUT / "Localizable.xcstrings"
OUT_INFO = RES_OUT / "InfoPlist.xcstrings"
ANDROID_RES = pathlib.Path(os.environ.get("PM_ANDROID_RES", str(ROOT.parent / "photomaid-android" / "app" / "src" / "main" / "res")))

LANGS = {  # Android-Ordner → iOS-Sprachkennung
    "values": "en", "values-de": "de", "values-ar": "ar", "values-es": "es", "values-fr": "fr", "values-it": "it",
    "values-ja": "ja", "values-ko": "ko", "values-nl": "nl", "values-pl": "pl", "values-pt-rPT": "pt-PT",
    "values-ro": "ro", "values-ru": "ru", "values-tr": "tr", "values-uk": "uk", "values-zh-rCN": "zh-Hans",
}
ALL = list(LANGS.values())
# Wörter, die in iOS-Texten nicht vorkommen dürfen (Android-Begriffe). Nur für benutzte Kennungen geprüft.
FORBIDDEN = re.compile(r"Android|Google Play|Google AdMob|AdMob|TalkBack|SD-Karte|Play Store|MediaStore", re.I)

FMT = re.compile(r"%(\d+\$)?(\.\d+)?([sdf])")


def convert_format(s: str) -> str:
    def repl(m):
        pos, prec, kind = m.group(1) or "", m.group(2) or "", m.group(3)
        return "%" + pos + prec + {"s": "@", "d": "lld", "f": "f"}[kind]
    return FMT.sub(repl, s)


def unescape(raw: str) -> str:
    s = raw
    if len(s) >= 2 and s[0] == '"' and s[-1] == '"':
        s = s[1:-1]
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            n = s[i + 1]
            if n == "n":
                out.append("\n")
            elif n == "t":
                out.append("\t")
            elif n == "u" and i + 5 < len(s):
                out.append(chr(int(s[i + 2:i + 6], 16)))
                i += 4
            else:
                out.append(n)
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def text_of(el) -> str:
    # Inhalt inklusive verschachtelter Tags (selten) als Text.
    return unescape("".join(el.itertext()))


def read_android():
    data = {}  # key → lang → value
    if not ANDROID_RES.exists():
        return data
    for folder, lang in LANGS.items():
        f = ANDROID_RES / folder / "strings.xml"
        if not f.exists():
            continue
        root = ET.parse(f).getroot()
        for el in root:
            name = el.get("name")
            if not name:
                continue
            if el.tag == "string":
                data.setdefault(name, {})[lang] = convert_format(text_of(el))
            elif el.tag == "plurals":
                for item in el.findall("item"):
                    q = item.get("quantity")
                    data.setdefault(f"{name}#{q}", {})[lang] = convert_format(text_of(item))
    return data


def read_ios():
    if not IOS_JSON.exists():
        return {}, {}
    j = json.loads(IOS_JSON.read_text(encoding="utf-8"))
    strings = {k: v for k, v in j.items() if not k.startswith("_")}
    from i18n.ios_strings_remodel import STRINGS
    strings.update(STRINGS)
    return strings, j.get("_infoPlist", {})


def catalog(entries: dict) -> dict:
    strings = {}
    for key in sorted(entries):
        locs = {}
        for lang in ALL:
            v = entries[key].get(lang)
            if v is None:
                continue
            locs[lang] = {"stringUnit": {"state": "translated", "value": v}}
        strings[key] = {"extractionState": "manual", "localizations": locs}
    return {"sourceLanguage": "en", "strings": strings, "version": "1.0"}


USE = re.compile(r'\bLP?\(\s*"([A-Za-z0-9_.#]+)"')
# Kennungen stehen auch in Text(key:), Tupeln und Ternären: jede Zeichenkette in Kennungs-Form zählt, wenn sie einen
# Unterstrich enthält oder als Kennung bekannt ist (Symbolnamen enthalten Punkte, Protokoll-Kürzel Bindestriche).
LITERAL = re.compile(r'"([a-z][a-z0-9_]*[a-z0-9])"')


def used_keys(known=None):
    keys = set()
    for f in (ROOT / "PhotoMaid").rglob("*.swift"):
        text = f.read_text(encoding="utf-8")
        for m in USE.finditer(text):
            keys.add(m.group(1))
        for line in text.splitlines():
            if line.strip().startswith("//") or "Diagnostics." in line or "StoreKey" in line:
                continue
            for m in LITERAL.finditer(line):
                k = m.group(1)
                if "_" in k or (known is not None and (k in known or any(x.startswith(k + "#") for x in known))):
                    keys.add(k)
    return keys


def plural_forms(entries, key):
    return [k for k in entries if k.startswith(key + "#")]


def main():
    check = "--check" in sys.argv
    android = read_android()
    ios, info = read_ios()
    if android:
        merged = {k: dict(v) for k, v in android.items()}
    else:
        existing = json.loads(OUT.read_text(encoding="utf-8")) if OUT.exists() else {"strings": {}}
        merged = {k: {l: u["stringUnit"]["value"] for l, u in v.get("localizations", {}).items()}
                  for k, v in existing["strings"].items()}
    for k, v in ios.items():
        merged.setdefault(k, {}).update(v)

    problems = []
    for k, v in ios.items():
        missing = [l for l in ALL if l not in v]
        if missing:
            problems.append(f"ios_strings.json: {k} fehlt in {', '.join(missing)}")
    for k in sorted(used_keys(merged)):
        forms = [k] if k in merged else plural_forms(merged, k)
        if not forms:
            problems.append(f"Kennung fehlt: {k}")
            continue
        for f in forms:
            missing = [l for l in ALL if l not in merged[f]]
            # Mengenformen: nur „other“ muss in jeder Sprache vorhanden sein.
            if f.endswith(("#zero", "#one", "#two", "#few", "#many")):
                continue
            if missing:
                problems.append(f"{f}: fehlt in {', '.join(missing)}")
            for l in ("de", "en"):
                if FORBIDDEN.search(merged[f].get(l, "")):
                    problems.append(f"{f} ({l}) enthält Android-Begriff – in ios_strings.json ersetzen: {merged[f][l]!r}")

    if check:
        if problems:
            print("\n".join(problems))
            sys.exit(1)
        print(f"OK: {len(used_keys(merged))} benutzte Kennungen, {len(merged)} Einträge, 16 Sprachen")
        return
    OUT.write_text(json.dumps(catalog(merged), ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if info:
        OUT_INFO.write_text(json.dumps(catalog(info), ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"{OUT.relative_to(ROOT)}: {len(merged)} Einträge")
    if problems:
        print("Hinweise:\n" + "\n".join(problems[:200]))


if __name__ == "__main__":
    main()

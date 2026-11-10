#!/usr/bin/env python3
"""Neue App-Sprachen (Ausbau auf alle App-Store-Sprachen, 10.11.2026).

Quelle: `scripts/i18n/new_langs/source_en.tsv` (feste Nummern, nur von der App benutzte Texte).
Übersetzung je Sprache: `scripts/i18n/new_langs/<lang>.tsv`, Zeilen `nummer<TAB>text`.
Mengenformen: die Nummern der englischen Formen (`…#one`, `…#other`) gelten weiter; zusätzliche Formen der
Zielsprache als `nummer:few<TAB>text` (Nummer = irgendeine Form derselben Kennung).

    python3 scripts/i18n/new_languages.py export            # source_en.tsv neu (nur wenn noch keine Übersetzung existiert)
    python3 scripts/i18n/new_languages.py check [lang …]    # Vollständigkeit + Platzhalter
    python3 scripts/i18n/new_languages.py merge             # vollständige Sprachen → Localizable/InfoPlist.xcstrings
    python3 scripts/i18n/new_languages.py review lang …     # Prüfdatei docs/review/APP_<lang>.md

Nicht benutzte Kennungen bekommen in neuen Sprachen den englischen Text (nie eine rohe Kennung auf dem Bildschirm).
Die 16 bisherigen Sprachen und `android_strings_to_xcstrings.py` bleiben unberührt.
"""
from __future__ import annotations

import importlib.util
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
DIR = ROOT / "scripts/i18n/new_langs"
SRC = DIR / "source_en.tsv"
CATALOG = ROOT / "PhotoMaid/Resources/Localizable.xcstrings"
INFOPLIST = ROOT / "PhotoMaid/Resources/InfoPlist.xcstrings"

# iOS-Kennung → (Name, benötigte Mengenformen außer „other“)
LANGS = {
    "ca": ("Català", {"one"}), "zh-Hant": ("繁體中文", set()), "pt-BR": ("Português (Brasil)", {"one"}),
    "hr": ("Hrvatski", {"one", "few"}), "cs": ("Čeština", {"one", "few"}), "da": ("Dansk", {"one"}),
    "fi": ("Suomi", {"one"}), "el": ("Ελληνικά", {"one"}), "hu": ("Magyar", {"one"}), "nb": ("Norsk bokmål", {"one"}),
    "sk": ("Slovenčina", {"one", "few"}), "sl": ("Slovenščina", {"one", "two", "few"}), "sv": ("Svenska", {"one"}),
    "he": ("עברית", {"one", "two"}), "id": ("Bahasa Indonesia", set()), "ms": ("Bahasa Melayu", set()),
    "th": ("ไทย", set()), "vi": ("Tiếng Việt", set()), "hi": ("हिन्दी", {"one"}), "bn": ("বাংলা", {"one"}),
    "gu": ("ગુજરાતી", {"one"}), "kn": ("ಕನ್ನಡ", {"one"}), "ml": ("മലയാളം", {"one"}), "mr": ("मराठी", {"one"}),
    "or": ("ଓଡ଼ିଆ", {"one"}), "pa": ("ਪੰਜਾਬੀ", {"one"}), "ta": ("தமிழ்", {"one"}), "te": ("తెలుగు", {"one"}),
    "ur": ("اردو", {"one"}),
}
FORMS = ("zero", "one", "two", "few", "many", "other")
SPEC = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|f|\.\d+f|%)")
INFO_KEYS = ["NSPhotoLibraryUsageDescription", "NSPhotoLibraryAddUsageDescription", "NSCameraUsageDescription",
             "NSFaceIDUsageDescription", "NSMicrophoneUsageDescription", "NSUserTrackingUsageDescription"]


def load_catalog(path=CATALOG):
    return json.loads(path.read_text(encoding="utf-8"))


def used_keys(strings):
    spec = importlib.util.spec_from_file_location("a2x", ROOT / "scripts/android_strings_to_xcstrings.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    merged = {k: {l: u["stringUnit"]["value"] for l, u in v.get("localizations", {}).items() if "stringUnit" in u}
              for k, v in strings.items()}
    keys = set()
    for k in mod.used_keys(merged):
        if k in merged:
            keys.add(k)
        keys |= {x for x in merged if x.startswith(k + "#")}
    return {k for k in keys if "en" in merged[k]}, merged


def read_source():
    rows = []
    for line in SRC.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        num, key, en = line.split("\t", 2)
        rows.append((num, key, en))
    return rows


def export():
    if any(p.name != SRC.name for p in DIR.glob("*.tsv")):
        sys.exit("Es gibt schon Übersetzungen – Nummern nicht neu vergeben.")
    strings = load_catalog()["strings"]
    keys, merged = used_keys(strings)
    DIR.mkdir(parents=True, exist_ok=True)
    out = ["# nummer\tkennung\tenglisch (Quelle, nur von der App benutzte Texte; Infoplist-Texte am Ende)"]
    for i, k in enumerate(sorted(keys)):
        out.append(f"{i:04d}\t{k}\t{merged[k]['en']}")
    info = load_catalog(INFOPLIST)["strings"]
    for j, k in enumerate(INFO_KEYS):
        out.append(f"9{j:03d}\tinfo:{k}\t{info[k]['localizations']['en']['stringUnit']['value']}")
    SRC.write_text("\n".join(out) + "\n", encoding="utf-8")
    print(f"{SRC.relative_to(ROOT)}: {len(out) - 1} Texte, {sum(len(r[2]) for r in read_source())} Zeichen")


def read_lang(lang):
    path = DIR / f"{lang}.tsv"
    if not path.exists():
        return None, [f"{lang}: keine Datei"]
    rows = read_source()
    by_num = {n: k for n, k, _ in rows}
    out, problems = {}, []
    for no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.startswith("#"):
            continue
        if "\t" not in line:
            problems.append(f"{lang}.tsv:{no}: kein Tab")
            continue
        ref, text = line.split("\t", 1)
        num, _, form = ref.partition(":")
        if num not in by_num:
            problems.append(f"{lang}.tsv:{no}: unbekannte Nummer {num}")
            continue
        key = by_num[num]
        if form:
            if "#" not in key or form not in FORMS:
                problems.append(f"{lang}.tsv:{no}: Form {form} für {key} ungültig")
                continue
            key = key.split("#")[0] + "#" + form
        if key in out:
            problems.append(f"{lang}.tsv:{no}: {key} doppelt")
        if not text.strip():
            problems.append(f"{lang}.tsv:{no}: leer")
        out[key] = text
    return out, problems


def specs(text):
    return sorted(s for s in SPEC.findall(text) if s != "%%")


def check(langs):
    rows = read_source()
    en = {k: t for _, k, t in rows}
    bases = {}
    for k in en:
        if "#" in k:
            bases.setdefault(k.split("#")[0], set()).add(k)
    report, complete = [], []
    for lang in langs:
        tr, problems = read_lang(lang)
        if tr is None:
            report += problems
            continue
        need = LANGS[lang][1] | {"other"}
        missing = [k for k in en if "#" not in k and k not in tr]
        for base, forms in bases.items():
            for f in need:
                if f"{base}#{f}" not in tr:
                    missing.append(f"{base}#{f}")
        for k, t in tr.items():
            base = k.split("#")[0]
            if "#" in k:
                allowed = set().union(*(specs(en[x]) for x in bases[base]))
                if not set(specs(t)) <= allowed:
                    problems.append(f"{lang} {k}: Platzhalter {specs(t)} ≠ {sorted(allowed)}")
                if k.split("#")[1] not in need:
                    problems.append(f"{lang} {k}: Form wird in {lang} nicht verwendet")
            elif specs(t) != specs(en[k]):
                problems.append(f"{lang} {k}: Platzhalter {specs(t)} ≠ {specs(en[k])}")
            if re.search(r"photomaid|arrumo", t, re.I):
                problems.append(f"{lang} {k}: alter Name")
        if missing:
            problems.append(f"{lang}: {len(missing)} fehlen (z. B. {', '.join(missing[:5])})")
        report += problems
        print(f"{lang:8} {len(tr):5} Texte  {'OK' if not problems else f'{len(problems)} Probleme'}")
        if not problems:
            complete.append(lang)
    if report:
        print("\n".join(report[:200]))
    return complete


def merge():
    complete = check(sorted(p.stem for p in DIR.glob("*.tsv") if p.stem in LANGS))
    if not complete:
        print("Keine vollständige Sprache.")
        return
    cat = load_catalog()
    info = load_catalog(INFOPLIST)
    for lang in complete:
        tr, _ = read_lang(lang)
        for key, entry in cat["strings"].items():
            locs = entry.setdefault("localizations", {})
            if key in tr:
                locs[lang] = {"stringUnit": {"state": "translated", "value": tr[key]}}
            elif "#" in key and "en" in locs and key.split("#")[0] + "#other" in tr:
                locs.pop(lang, None)  # Form wird in dieser Sprache nicht gebraucht
            elif "en" in locs:
                locs[lang] = {"stringUnit": {"state": "needs_review", "value": locs["en"]["stringUnit"]["value"]}}
        for key in [k for k in tr if k not in cat["strings"]]:  # zusätzliche Mengenformen (few/two/…)
            cat["strings"][key] = {"extractionState": "manual",
                                   "localizations": {lang: {"stringUnit": {"state": "translated", "value": tr[key]}}}}
        for k in INFO_KEYS:
            info["strings"][k]["localizations"][lang] = {"stringUnit": {"state": "translated", "value": tr[f"info:{k}"]}}
        info["strings"]["CFBundleDisplayName"]["localizations"][lang] = {
            "stringUnit": {"state": "translated", "value": "GaleriQ"}}
    for path, data in ((CATALOG, cat), (INFOPLIST, info)):
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    proj = ROOT / "project.yml"
    text = proj.read_text(encoding="utf-8")
    m = re.search(r"CFBundleLocalizations: \[([^\]]*)\]", text)
    have = [x.strip() for x in m.group(1).split(",")]
    have += [l for l in complete if l not in have]
    proj.write_text(text[:m.start(1)] + ", ".join(have) + text[m.end(1):], encoding="utf-8")
    print(f"Eingespielt: {', '.join(complete)}")


def review(langs):
    rows = read_source()
    for lang in langs:
        tr, problems = read_lang(lang)
        name = LANGS[lang][0]
        lines = [f"# GaleriQ – App-Texte {lang} ({name}) zur Prüfung", "",
                 "Stand 10.11.2026. iPhone-App zum Aufräumen der Fotomediathek (Wischen: hoch = behalten, links = "
                 "GaleriQ-Papierkorb, rechts = später, runter = zurück), mit Tresor, Studio (Bearbeiten, Collage, Film, "
                 "PDF) und drei kleinen Spielen (Paare, Foto-Snake, Foto Blocks).", "",
                 "## Auftrag an den Prüfer",
                 "Jede Zeile: Nummer · englische Quelle · Übersetzung. Bitte als muttersprachlicher iOS-Übersetzer prüfen "
                 "und **nur Fehler** melden, je Fund `Nummer · Problem · neue Übersetzung (vollständig)`. Prüfen auf:",
                 "1. Bedeutung wie im Englischen, nichts weggelassen oder hinzugefügt.",
                 "2. Natürliche, kurze App-Sprache; Apples übliche iOS-Begriffe (Fotos-App, „Zuletzt gelöscht“, Teilen, "
                 "Einstellungen, Face ID) in der Form, die Apple in dieser Sprache verwendet; einheitliche Begriffe "
                 "(Papierkorb, Tresor, Behalten, Später) im ganzen Text.",
                 "3. Platzhalter (`%1$@`, `%1$lld`, `%@`, `%lld`) unverändert und vollständig; Reihenfolge darf wechseln, "
                 "die Nummer muss bleiben.",
                 "4. Mengenformen (Kennung endet auf `#one`, `#few`, `#other` …) passend zu den CLDR-Regeln der Sprache.",
                 "5. „GaleriQ“, „Pro“, „Foto Blocks“, „iPhone“, „iCloud“, „Face ID“, „PDF“, „GIF“ bleiben unverändert. "
                 "Knöpfe kurz halten (Bildschirmbreite).", "",
                 "| Nr. | Kennung | Englisch | " + name + " |", "|---|---|---|---|"]
        num_of = {k: n for n, k, _ in rows}
        for n, k, en in rows:
            keys = [k]
            if "#" in k and k.endswith("#other"):
                base = k.split("#")[0]
                keys = [x for x in sorted(tr) if x.split("#")[0] == base and x not in num_of] + [k]
            for kk in keys:
                if kk not in tr:
                    continue
                cell = lambda s: s.replace("|", "\\|")
                label = n if kk == k else f"{n}:{kk.split('#')[1]}"
                lines.append(f"| {label} | `{kk}` | {cell(en) if kk == k else '–'} | {cell(tr[kk])} |")
        out = ROOT / f"docs/review/APP_{lang}.md"
        out.write_text("\n".join(lines) + "\n", encoding="utf-8")
        print(out.relative_to(ROOT), len(lines))


if __name__ == "__main__":
    cmd, *args = sys.argv[1:] or ["check"]
    if cmd == "export":
        export()
    elif cmd == "check":
        ok = check(args or sorted(p.stem for p in DIR.glob("*.tsv") if p.stem in LANGS))
    elif cmd == "merge":
        merge()
    elif cmd == "review":
        review(args)
    else:
        sys.exit(__doc__)

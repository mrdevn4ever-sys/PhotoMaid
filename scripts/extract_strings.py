#!/usr/bin/env python3
"""Erzeugt/aktualisiert PhotoMaid/Resources/Localizable.xcstrings (Quellsprache: de).

Heuristische Extraktion der UI-Literale aus den Swift-Quellen der App. Xcode ergänzt beim Build
(SWIFT_EMIT_LOC_STRINGS) automatisch; dieses Skript sorgt dafür, dass der Katalog von Anfang an
existiert und alle statischen Texte enthält. `--check` meldet fehlende Einträge (für CI).
"""
import json, re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = [ROOT / "PhotoMaid" / d for d in ("App", "DesignSystem", "Features", "Infrastructure")]
OUT = ROOT / "PhotoMaid" / "Resources" / "Localizable.xcstrings"

LIT = re.compile(r'"((?:[^"\\]|\\.)*)"')
SYMBOL = re.compile(r'^[a-z0-9]+(\.[a-z0-9]+)+$')
SKIP_LINE = re.compile(r'forKey|Notification|identifier|systemImage: *$|#if|import |"%02x"|dateFormat|entityName|keyName|NSPredicate|format:|grouping|\.rules\.refresh|PM[A-Z]')
INT_HINT = re.compile(r'(count|\bn\b|available|requested|limit|days|sizeMB|ThresholdMB|position|current|total|Int\(|pixelWidth|pixelHeight|\bd\b|confirmedRemoved|basketCount|dueCount|kept|marked|later)')

def to_key(lit: str) -> str:
    def repl(m):
        expr = m.group(1)
        return "%lld" if INT_HINT.search(expr) and "formatted" not in expr and "bytes(" not in expr and "name" not in expr and "source" not in expr else "%@"
    out, i, depth = "", 0, 0
    # \( ... ) mit verschachtelten Klammern ersetzen
    while i < len(lit):
        if lit.startswith("\\(", i):
            j, depth = i + 2, 1
            while j < len(lit) and depth:
                depth += {"(": 1, ")": -1}.get(lit[j], 0); j += 1
            out += repl(re.match(r"(.*)", lit[i + 2:j - 1], re.S)); i = j
        else:
            out += lit[i]; i += 1
    return out.replace('\\"', '"')

def extract():
    keys = set()
    for base in SRC:
        for f in base.rglob("*.swift"):
            if f.name == "QAFixtures.swift":
                continue  # nur QA-Builds, keine UI-Texte
            for line in f.read_text().splitlines():
                s = line.strip()
                if s.startswith("//") or SKIP_LINE.search(s):
                    continue
                for m in LIT.finditer(s):
                    lit = m.group(1)
                    if not re.search(r"[A-Za-zÄÖÜäöü]", lit) or SYMBOL.match(lit):
                        continue
                    if re.match(r"^[a-zA-Z]+$", lit) and lit[0].islower():
                        continue  # Bezeichner
                    key = to_key(lit)
                    if not re.search(r"[A-Za-zÄÖÜäöü]{2,}", key.replace("%lld", "").replace("%@", "")):
                        continue  # reine Formatierung, kein UI-Text
                    keys.add(key)
    return keys

def main():
    keys = extract()
    catalog = {"sourceLanguage": "de", "strings": {}, "version": "1.0"}
    if OUT.exists():
        catalog = json.loads(OUT.read_text())
    missing = sorted(k for k in keys if k not in catalog["strings"])
    if "--check" in sys.argv:
        for k in missing: print("MISSING:", k)
        sys.exit(1 if missing else 0)
    # Veraltete, von diesem Skript angelegte Einträge entfernen.
    for k in [k for k, v in catalog["strings"].items() if k not in keys and v.get("extractionState") == "manual"]:
        del catalog["strings"][k]
    for k in missing:
        catalog["strings"][k] = {"extractionState": "manual",
                                 "localizations": {"de": {"stringUnit": {"state": "translated", "value": k}}}}
    catalog["strings"] = dict(sorted(catalog["strings"].items()))
    OUT.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")
    print(f"{len(catalog['strings'])} Einträge ({len(missing)} neu) → {OUT.relative_to(ROOT)}")

if __name__ == "__main__":
    main()

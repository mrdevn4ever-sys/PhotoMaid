#!/usr/bin/env python3
"""Fasst ein xcodebuild-Log als Markdown zusammen: Compilerfehler (Datei:Zeile), Concurrency-Warnungen,
fehlgeschlagene Tests. Ergebnis landet in der Job-Zusammenfassung und als Artefakt `ci-report.md`,
damit der nächste Korrekturdurchlauf (Claude Code/Codex auf Windows) es direkt lesen kann."""
import re
import sys
from collections import OrderedDict

path = sys.argv[1] if len(sys.argv) > 1 else "xcodebuild.log"
try:
    text = open(path, encoding="utf-8", errors="replace").read()
except FileNotFoundError:
    print(f"## CI-Bericht\n\nKein Log gefunden ({path}).")
    sys.exit(0)

root_markers = ("/PhotoMaid/", "/Sources/", "/Tests/", "/PhotoMaidTests/", "/PhotoMaidUITests/")

def short(p: str) -> str:
    for m in ("/Sources/", "/Tests/", "/PhotoMaidTests/", "/PhotoMaidUITests/", "/PhotoMaid/"):
        i = p.rfind(m)
        if i >= 0:
            return p[i + 1:]
    return p

diag = re.compile(r"^(/[^:\n]+):(\d+):(\d+): (error|warning): (.+)$", re.M)
errors, warnings = OrderedDict(), OrderedDict()
for f, line, col, kind, msg in diag.findall(text):
    key = (short(f), int(line), msg.strip())
    (errors if kind == "error" else warnings)[key] = True

other_errors = sorted({m.strip() for m in re.findall(r"^error: (.+)$", text, re.M)})
failed_tests = sorted(set(re.findall(r"Test Case '-\[(\S+ \S+)\]' failed", text)) |
                      set(re.findall(r"✘ Test (\S+)\(\) .*failed", text)))
outcomes = re.findall(r"\*\* ((?:BUILD|TEST(?: BUILD| EXECUTE)?) (?:SUCCEEDED|FAILED)) \*\*", text)
failures = [outcome for outcome in outcomes if outcome.endswith("FAILED")]
result = failures[-1] if failures else ("SUCCEEDED" if any(
    outcome in ("TEST SUCCEEDED", "TEST EXECUTE SUCCEEDED") for outcome in outcomes
) else (outcomes[-1] if outcomes else "UNBEKANNT"))

print("## CI-Bericht iOS\n")
print(f"Ergebnis: **{result}** · Fehler: {len(errors) + len(other_errors)} · Warnungen: {len(warnings)} · "
      f"fehlgeschlagene Tests: {len(failed_tests)}\n")
if errors or other_errors:
    print("### Compilerfehler\n")
    for (f, line, msg) in list(errors)[:200]:
        print(f"- `{f}:{line}` {msg}")
    for msg in other_errors[:50]:
        print(f"- {msg}")
    print()
if failed_tests:
    print("### Fehlgeschlagene Tests\n")
    for t in failed_tests[:100]:
        print(f"- {t}")
    print()
concurrency = [(f, l, m) for (f, l, m) in warnings if re.search(r"Sendable|isolat|actor|concurrency", m)]
if concurrency:
    print("### Concurrency-Warnungen\n")
    for (f, line, msg) in concurrency[:100]:
        print(f"- `{f}:{line}` {msg}")
    print()

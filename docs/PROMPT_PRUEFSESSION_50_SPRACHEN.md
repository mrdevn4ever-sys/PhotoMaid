# Prompt für eine unabhängige Prüf-Session (GaleriQ, 50 Sprachen, Version 1.0.1)

Kopiere alles unterhalb der Linie in eine neue Claude-Session mit Zugriff auf das Repo `mrdevn4ever-sys/photomaid`.

---

Du übernimmst die unabhängige Endprüfung für die iPhone-App „GaleriQ“ (App-Store-App-ID 6821165617). Antworte auf Deutsch, kurz, Prüfstatus immer PASS / FAIL / NOT RUN / BLOCKED.

## Ziel
Version 1.0.1 in App Store Connect ist **einreichbereit**:
- Alle **50 App-Store-Sprachen** haben vollständige Store-Texte (Name, Untertitel, Schlüsselwörter, Werbetext, Beschreibung, Neuerungen) innerhalb der Apple-Limits.
- Die App selbst ist in allen Sprachen übersetzt (45 App-Sprachen; die 50 Store-Locales enthalten regionale Varianten wie en-GB/en-AU, es-MX, fr-CA, pt-BR/pt-PT, zh-Hans/zh-Hant, die auf App-Sprachen abgebildet werden – prüfe, dass jede Store-Locale eine passende App-Sprache hat).
- Ein neuer interner TestFlight-Build (MARKETING_VERSION 1.0.1, CURRENT_PROJECT_VERSION > 2) ist von Apple verarbeitet und bei Version 1.0.1 ausgewählt.

## Arbeitsstand
- Branch: `claude/galeriq-localization-1-0-1-bgpw9u` (basiert auf dem Live-Stand `claude/experiment-artifact-design`, **nicht** main).
- Neue App-Sprachen als TSV: `scripts/i18n/new_langs/<lang>.tsv`, Quelle `source_en.tsv`, Kontext/Glossar `scripts/i18n/new_langs/KONTEXT.md`, Werkzeug `scripts/i18n/new_languages.py` (check/review/merge).
- Kataloge: `PhotoMaid/Resources/Localizable.xcstrings`, `PhotoMaid/Resources/InfoPlist.xcstrings`; `project.yml` (CFBundleLocalizations, Versionen).
- Store-Texte: `scripts/store/texts_extra_*.py` u. a.; Upload über `.github/workflows/testflight.yml` (task `store-texts`, confirm `TEXTE`), Fastlane-Lane `store_metadata` in `fastlane/Fastfile`.
- Review-Dateien: `docs/review/APP_<lang>.md`.
- Regeln des Projekts: `CLAUDE.md` (verbindlich lesen). Sichtbarer Name nur „GaleriQ“, interne Namen „PhotoMaid“ nie umbenennen.

## Prüfaufträge
1. **App-Texte, jede Sprache:** `python3 scripts/i18n/new_languages.py check <lang>` für alle neuen Sprachen; `PM_ANDROID_RES=/nonexistent python3 scripts/android_strings_to_xcstrings.py --check`. Stichproben pro Sprache (je ≥ 30 Einträge, besonders Plural-Formen, Platzhalter `%1$lld`/`%@` in richtiger Reihenfolge, RTL he/ur, Gestenpfeile nicht gespiegelt), Fachbegriffe gegen KONTEXT.md (z. B. edit_aspect_free = „frei“ nicht „gratis“, hub_large_from = Untergrenze „ab“, blocks_next = nächstes Teil, memory_flip = Karten zurückdrehen, Begrüßungen 12–13/14–17 Uhr, Vault-Rad im „Q“ dreht sich). Spielnamen gleich wie in den Store-Texten; „Foto Blocks“ überall unverändert. Text 1199 nennt nur Apple, 9001 ohne PDFs.
2. **Unveränderte Altsprachen:** Die 16 Originalsprachen (und die 8 früher ergänzten) dürfen sich durch das Einspielen nicht geändert haben – vergleiche die Kataloge mit `origin/claude/experiment-artifact-design` (nur neue Sprachen + die zwei freigegebenen Quellkorrekturen 1199/9001 dürfen abweichen).
3. **Vollständigkeit:** Jede Kennung hat in jeder der 45 App-Sprachen einen Wert; InfoPlist-Texte (inkl. CFBundleDisplayName = GaleriQ) in allen Sprachen; CFBundleLocalizations in project.yml vollständig.
4. **Store-Texte 50 Locales:** Längenlimits (Name/Untertitel ≤ 30, Schlüsselwörter ≤ 100 Bytes, Werbetext ≤ 170, Beschreibung ≤ 4000, Neuerungen ≤ 4000), keine fremden Markennamen, Inhalt passt zur App, Begriffe konsistent mit App-Texten. Wenn Zugriff möglich: Stand in App Store Connect mit dem letzten `store-texts`-Lauf vergleichen.
5. **CI:** `ci.yml` auf dem Branch muss grün sein (Build, Unit-Tests inkl. PluralRulesTests, String-Check). Aktueller Lauf: Run 42855363448.
6. **Build/Connect:** Prüfen, ob ein neuer Build (Build-Nummer > 2) verarbeitet und bei 1.0.1 ausgewählt ist; falls nicht, das als offen melden.

## Grenzen (strikt)
- **NICHT zur Prüfung einreichen, NICHT veröffentlichen/freigeben.** Das macht der Nutzer selbst.
- Keine externe TestFlight-Verteilung. Keine Secrets/Keys ins Repo oder in den Chat.
- Keine Änderungen an anderen Branches, kein Merge nach main, kein PR ohne ausdrücklichen Auftrag.
- Screenshots nicht erzeugen oder ändern.
- Gefundene Fehler zuerst als Liste melden (`Sprache · Nummer · aktueller Text · Vorschlag · Grund`); Korrekturen nur auf dem genannten Branch, danach erneut check + CI.

## Ergebnis
Kurzer Bericht: Tabelle je Prüfauftrag mit PASS/FAIL/NOT RUN/BLOCKED, Fehlerliste, und klare Aussage, ob Version 1.0.1 einreichbereit ist und was noch fehlt.

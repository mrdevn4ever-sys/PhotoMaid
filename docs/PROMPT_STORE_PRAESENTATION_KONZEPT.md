# Prompt: Wettbewerbs-Recherche und Konzept für die App-Store-Präsentation von GaleriQ

Alles unterhalb der Linie in Hermes einfügen.

---

Du erarbeitest ein **Konzept** dafür, wie die iPhone-App **GaleriQ** im Apple App Store präsentiert wird: Screenshots, App-Vorschau-Video, Reihenfolge, Texte auf den Bildern und visuelles System. Antworte auf Deutsch. **Nur Recherche und Konzept, nichts umsetzen und nichts hochladen.**

## Die App (Fakten, nichts dazuerfinden)
- GaleriQ, App-ID 6821165617, Kategorie Foto & Video, 4+, iPhone-only (iOS 26+), kostenlos mit Werbung, „GaleriQ Pro“ als Einmalkauf (kein Abo).
- Store-Seiten: https://apps.apple.com/us/app/galeriq-photo-cleaner-vault/id6821165617 und https://apps.apple.com/de/app/galeriq-fotos-aufr%C3%A4umen/id6821165617
- Kern: Fotos und Videos aufräumen per Wischen (hoch = behalten, links = GaleriQ-Papierkorb, rechts = später, runter = zurück). Gelöscht wird erst nach Bestätigung im Papierkorb **und** im iOS-Dialog (landet in „Zuletzt gelöscht“).
- Weitere Funktionen: Duplikate (identische Dateien), ähnliche Aufnahmen und Serien, große Dateien, Monatsübersicht, Analyse auf dem Gerät (Apple Vision: unscharf, Motive, Fotos mit Text), privater **Tresor** (verschlüsselt, Code/Face ID, Notizen, Dateien), Studio (Bearbeiten, Collagen, Filme aus Clips, PDF, GIF, Formate umwandeln, Standort entfernen), drei Spiele mit eigenen Fotos (Paare, Foto Snake, Foto Blocks), Erfolge.
- Datenschutz: kein Konto, kein Server, keine Foto-Uploads; Werbung nur in der Gratisversion (Google AdMob, Einwilligung zuerst).
- Schriftzug: Das „Q“ ist ein Tresor-Zahlenrad. Interne Namen „PhotoMaid“ nie nach außen zeigen.
- 50 Store-Sprachen, 45 App-Sprachen.

## Ist-Zustand
- 10 Screenshots (Maximum) im Pflichtformat 1206 × 2622 px, reine UI-Aufnahmen ohne große Überschriften, nur dunkles UI, alle Sprachen zeigen bisher dieselben englischen Bilder.
- Reihenfolge: Start → Behalten → Papierkorb → … → Spiele (2 Bilder) → Tresor (Platz 10).
- 2 Vorschauvideos vorhanden (886 × 1920, 27 s), aber nicht aktiv.
- Ein früheres Audit liegt im Repo bzw. beim Nutzer vor; die Kernaussagen: großer Hook fehlt, Tresor zu spät, Spiele zu prominent, Duplikate/große Dateien kaum sichtbar, Lokalisierung fehlt.

## Recherche-Auftrag
1. **Top-Apps der Kategorie** (US und DE, aktuell): die erfolgreichsten Foto-Cleaner, Speicher-Cleaner und Foto-Tresor-Apps, z. B. Swipewipe, Cleanup, Clever Cleaner, CleanMy Phone, Photo Purge, Gallery Vault, Private Photo Vault, Slidebox – ergänze die tatsächlich aktuellen Top-Titel aus den Charts. Mindestens 10 Apps.
2. **Apple selbst als Vorbild:** wie Apple seine eigenen Apps präsentiert (z. B. Fotos, Freeform, Pixelmator/Final Cut für iPad, Journal), was Apple im „Today“-Tab und bei „App des Tages“ hervorhebt, sowie Apples offizielle Richtlinien: https://developer.apple.com/app-store/product-page, Screenshot- und Preview-Spezifikationen, Product Page Optimization, Custom Product Pages und die 2026 eingeführten Header-/Search-Creatives.
3. Je App erfassen: Reihenfolge der Bildaussagen, Überschriften (Wortzahl, Ton), Hintergrund und Farbe, Gerätrahmen ja/nein, wie stark die echte UI im Bild ist, Video ja/nein und Inhalt der ersten 3 Sekunden, Lokalisierung, Sicherheits-/Datenschutz-Botschaften, Umgang mit Abo/Preis.
4. Was davon wirkt nachweislich (Quellen: Apple, seriöse ASO-Studien)? Klar trennen zwischen **belegt** und **Einschätzung**.

## Gewünschtes Ergebnis
1. **Wettbewerbs-Tabelle** (≥ 10 Apps + Apple-Beispiele) mit Links und den Punkten aus 3.
2. **3 Konzeptvarianten** mit unterschiedlichem Schwerpunkt, z. B. „Aufräumen zuerst“, „Privatsphäre/Tresor zuerst“, „Kontrolle & Sicherheit zuerst“. Pro Variante:
   - Reihenfolge von 8–10 Screenshots: Überschrift DE + EN (max. 2 kurze Zeilen), welcher echte App-Screen, was groß/zugeschnitten gezeigt wird, Begründung.
   - Visuelles System: Farben (vom Icon und den App-Aktionsfarben ableiten), Schrift, Layout, Gerätrahmen, hell/dunkel, Text sicher für lange Sprachen (Deutsch, Finnisch) und RTL (Arabisch, Hebräisch, Urdu).
   - Storyboard für **ein** App-Vorschau-Video (15–30 s, stumm verständlich, Posterbild).
3. **Empfehlung**: welche Variante zuerst, welche als A/B-Test (Product Page Optimization), welche als Custom Product Page (z. B. Tresor, Spiele/Kreativ).
4. **Lokalisierungsplan**: welche Sprachen zuerst eigene Bilder bekommen und wie die Überschriften für alle 50 Locales technisch erzeugt werden können.
5. **Nicht-Bild-Hebel** kurz: Untertitel/Werbetext, Icon (nur testen, nicht umbauen), Support- und Landingpage, Barrierefreiheitsangaben.
6. Optional: einfache Skizzen/Mockups der ersten 3 Bilder je Variante (z. B. als HTML oder Bild), klar als Entwurf markiert.

## Regeln
- Keine erfundenen Zahlen oder Auszeichnungen (keine „Nr. 1“, „Millionen Nutzer“, Sterne, „X GB frei“ ohne echten Beleg). Keine Funktionen versprechen, die die App nicht hat; keine „KI löscht automatisch“-Aussagen – die App entscheidet nie selbst.
- Keine fremden Marken, Logos oder Screenshots anderer Apps in eigenen Entwürfen; nur zur Analyse verlinken.
- Keine privaten oder echten Personenfotos als Motive; nur neutrale Beispielmotive vorschlagen.
- Nichts in App Store Connect ändern, nichts hochladen, nichts einreichen, keine Screenshots im Repo ersetzen. Keine Zugangsdaten nutzen oder anfordern.
- Am Ende: kurze Zusammenfassung mit den 5 wichtigsten Entscheidungen, die der Nutzer treffen muss, und Quellenliste.

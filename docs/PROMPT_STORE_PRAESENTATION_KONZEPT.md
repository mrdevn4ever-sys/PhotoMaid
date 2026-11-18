# Prompt: App-Store-Präsentation für GaleriQ – Analyse, Konzepte, englische Test-Screenshots

Alles unterhalb der Linie in Hermes einfügen.

---

Ziel: der **perfekte App-Store-Eintrag für GaleriQ**. Ablauf in drei Schritten:
1. Die besten Apps im App Store analysieren.
2. Daraus **3 klar unterschiedliche Konzepte** für die Präsentation erstellen.
3. Jedes Konzept als **vollständiges englisches Screenshot-Set** umsetzen, damit der Nutzer sie nebeneinander vergleichen und eines auswählen kann.

Danach stoppst du. Erst nach der Auswahl des Nutzers wird das gewählte Konzept auf alle 50 Sprachen ausgeweitet. Antworte auf Deutsch.

## Die App (Fakten, nichts dazuerfinden)
- GaleriQ, App-ID 6821165617, Foto & Video, 4+, iPhone-only (iOS 26+), kostenlos mit Werbung, „GaleriQ Pro“ als Einmalkauf (kein Abo).
- Store: https://apps.apple.com/us/app/galeriq-photo-cleaner-vault/id6821165617
- Kern: Fotos und Videos per Wischen aufräumen (hoch = behalten, links = GaleriQ-Papierkorb, rechts = später, runter = zurück). Gelöscht wird erst nach Bestätigung im Papierkorb **und** im iOS-Dialog („Zuletzt gelöscht“).
- Weitere Funktionen: Duplikate, ähnliche Aufnahmen und Serien, große Dateien, Monatsübersicht, Analyse auf dem Gerät (unscharf, Motive, Fotos mit Text), privater verschlüsselter **Tresor** (Code/Face ID, Notizen, Dateien), Studio (Bearbeiten, Collagen, Filme, PDF, GIF, Formate, Standort entfernen), drei Spiele mit eigenen Fotos (Paare, Foto Snake, Foto Blocks).
- Datenschutz: kein Konto, kein Server, keine Foto-Uploads; Werbung nur in der Gratisversion.
- Schriftzug: Das „Q“ ist ein Tresor-Zahlenrad. Interne Namen („PhotoMaid“) nie zeigen.
- Ist-Zustand: 10 reine UI-Screenshots ohne Überschriften, nur dunkel, Tresor erst auf Platz 10, Spiele zu prominent, Duplikate/große Dateien kaum sichtbar.

## Schritt 1 – Analyse der besten Apps
- Mindestens 10 aktuelle Top-Apps aus Foto-Cleaner, Speicher-Cleaner und Foto-Tresor (US-Store, aktuelle Charts) plus 3–5 Apps, die Apple selbst besonders hervorhebt (eigene Apple-Apps, „App des Tages“, Apple Design Awards).
- Apples Richtlinien einbeziehen: https://developer.apple.com/app-store/product-page, Screenshot-/Preview-Spezifikationen, Product Page Optimization.
- Je App: Reihenfolge der Bildaussagen, Überschriften (Länge, Ton), Hintergrund/Farbe, Gerätrahmen, Anteil echter UI, Video und erste 3 Sekunden, Sicherheits-/Datenschutz-Botschaft. Als Tabelle mit Links.
- Fazit: welche Muster nachweislich wirken (Quellen) und was davon zu GaleriQ passt. Belegt und Einschätzung trennen.

## Schritt 2 – 3 Konzepte
Drei echt verschiedene Richtungen, z. B. „Aufräumen & Platz“, „Privatsphäre & Tresor“, „Kontrolle & Sicherheit“ (oder bessere aus der Analyse). Je Konzept:
- Leitidee in einem Satz, Zielwirkung.
- Reihenfolge der 10 Screenshots: Aussage, englische Überschrift (max. 2 kurze Zeilen), welcher echte App-Screen in welchem Zustand, was vergrößert/zugeschnitten wird.
- Visuelles System: exakte Farbwerte (aus Icon und App-Aktionsfarben), Schrift, Layout, Gerätrahmen, hell/dunkel.
- Kurzes Storyboard für ein Vorschauvideo (15–30 s).

## Schritt 3 – Englische Test-Screenshots
- Für **jedes** Konzept alle 10 Screenshots in Englisch fertig bauen, im Pflichtformat **1206 × 2622 px**, PNG ohne Alpha, mit **echten App-Screens** (iOS-Simulator, englische App-Sprache, neutrale Beispielmotive) und den Überschriften.
- Zusätzlich je Konzept eine Übersicht, wie die ersten 3 Bilder im Suchergebnis wirken.
- Alles in einem eigenen Ordner, z. B. `app-store/concepts/<konzept>/en-US/`, auf einem eigenen Branch; nichts Bestehendes überschreiben.
- Eine Vergleichsseite (HTML oder Bild) mit allen drei Konzepten nebeneinander und einer klaren Empfehlung mit Begründung.

## Danach (erst nach Auswahl durch den Nutzer)
- Beschreibe schon jetzt, wie das gewählte Konzept auf alle 50 Store-Sprachen ausgeweitet wird: Überschriften-Übersetzung, echte App-Screens je Sprache, RTL (ar, he, ur) mit gespiegeltem Layout, aber Gestenpfeile **nicht** gespiegelt, Prüfung auf Textlänge/Abschneiden. **Nicht ausführen**, bis der Nutzer gewählt hat.

## Regeln
- Keine erfundenen Zahlen oder Auszeichnungen („Nr. 1“, „Millionen Nutzer“, Sterne, „X GB frei“). Keine Funktionen versprechen, die es nicht gibt; die App löscht nie selbst.
- Keine fremden Marken, Logos oder Fremd-Screenshots in den eigenen Bildern; Wettbewerber nur verlinken.
- Keine echten Personenfotos, nur neutrale Beispielmotive.
- Nichts in App Store Connect ändern, nichts hochladen oder einreichen, bestehende Store-Screenshots nicht ersetzen, keine Zugangsdaten in Repo oder Chat. Nur eigener Branch, kein Merge.
- Am Ende: kurze Zusammenfassung, Pfade zu den drei englischen Sets, Empfehlung, Quellenliste – und die Frage an den Nutzer, welches Konzept ausgeweitet werden soll.

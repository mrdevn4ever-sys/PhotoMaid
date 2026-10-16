# SnakePhoto – Original-Asset-Kit für Swift iOS

## Inhalt
- **SnakeHeads.atlas** – 15 animierbare Zustände des grünen 2D-Schlangenkopfs plus 3 weitere Charaktere mit je 4 Zuständen. Der Kopf zeigt bei `zRotation = 0` nach RECHTS (+X).
- **SnakeBody.atlas** – transparente Kreisrahmen, Foto-Maske, Platzhalter, Schatten, Körperverbindung, Schwanz und alternative Körperfarben.
- **SnakeFood.atlas** – neun Futtertypen und vier Einsammel-Effekte.
- **SnakeUI.atlas** – transparente Buttons, Pfeile, Galerie, Herzen und Einstellungen.
- **Backgrounds** – je ein grosser Tag-/Nacht-Spielhintergrund (1024×2048) sowie zwei nahtlose 512×512-Kacheln.
- **Sounds** – sechs eigens synthetisierte WAV-Sounds (mono, 44.1 kHz).
- **Sources_SVG** – editierbare Vektorquellen aller statischen Sprite-Grafiken.
- **Swift** – kleine unabhängige Hilfsdateien (Textur-Namen und Foto-Texture-Composing).
- **MASTERPROMPT_HERMES_SWIFT_IOS.md** – vollständiger Umbauauftrag für das bestehende iOS-Spiel.
- **Documentation** – Test- und Einbau-Checklisten.

## In das existierende Xcode-Projekt einbauen
1. **Keine neue App anlegen.** Bestehendes Repository, Bundle-ID, Progression und Spiellogik erhalten.
2. Die vier `.atlas`-Ordner in die iOS-App-Zielressourcen aufnehmen. Xcode kann `.atlas`-Ordner beim Build zu SpriteKit-Atlanten kompilieren. (Überprüfen, dass sie in Copy Bundle Resources/Build Phases enthalten sind.)
3. PNGs in `Backgrounds` und WAVs in `Sounds` als Ressourcen einbinden. Bei verschachtelten Ordnern auf den korrekten Bundle-Pfad achten.
4. Swift-Dateien sind **Beispiele/Hilfsmodule**, keine fertig integrierte GameScene. An den existierenden Architektur-/Deployment-Stand anpassen.
5. Die User-Galeriefotos sind **nicht** im Paket enthalten: der Nutzer wählt sie direkt über `PhotosPicker` aus, die App erzeugt kleine runde Texturen und speichert nur notwendige lokale Kopien.
6. Textur-Cache verwenden: ein Foto einmal zu 256×256 komponieren und danach für viele Segmente wiederverwenden. Keine dauerhaften SKCropNodes für 100 Segmente.
7. Die Kopf-Bitmap als Ganzes drehen, nie das Gesicht durch Stretching verzerren. Blick-/Esszustände via Frames auswechseln; Drehungen zeitbasiert interpolieren.

## Asset-Masse
- Köpfe, Rahmen, UI, Futter: **256×256 px**, transparent, mit Luft/Rand im Sprite.
- Kreisfoto-Ausschnitt: **160 px Durchmesser**, Mittelpunkt bei (128,128), nach dem Rahmen drüberlegen.
- Alle Kopfvarianten blicken beim Original **nach rechts**. In SpriteKit `atan2(dy,dx)` benutzen.
- Hintergründe sind gezeichnete Illustrations-Assets; Gameplay/HUD bleiben echte interaktive UI.

## Abgrenzung
Das Paket ist ein **einsetzbares Grafik-/Sound- und Integrationskit**, **keine bereits umgebaute oder kompilierte Swift-App**. Ohne deinen bestehenden Quellcode kann die GameScene nicht exakt an deine Architektur angepasst werden. Der Masterprompt fordert ausdrücklich die Änderungen direkt in deinem vorhandenen Repository.

## Lizenzen / Datenschutz
Die hier gelieferten Sprite-Grafiken und WAV-Sounds wurden für diesen Auftrag neu erzeugt bzw. eigens synthetisiert; sie enthalten keine heruntergeladenen Grafiken, Schriftdateien oder Fremdsounds. Apple-Frameworks (SwiftUI, PhotosUI, SpriteKit) kommen von Apple und sind SDK-Bestandteile. Beachte Apples Standard-Lizenz- und App-Review-Bedingungen. User-Fotos sind persönlicher Inhalt, verbleiben lokal und dürfen ohne gesonderte Zustimmung nicht zu Analyse-/Cloud-Diensten hochgeladen werden.

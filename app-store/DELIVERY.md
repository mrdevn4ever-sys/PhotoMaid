# PhotoMaid – Übergabe der App-Store-Assets

15.10.2026 · Branch `claude/fixes-analysis-library-vault-20261014`.

**Abgeschlossen:** 55 CC0-Hochkantfotos, 1.969 unveränderte native Dark-Mode-Seitenaufnahmen, 160 Store-Vorschläge, 48 Vorschauvideos und 48 Poster. Alles nach Sprache und Seite geordnet. [Sprachindex](INDEX.md) · [Quellen und Lizenzbelege](media/SOURCES.md) · [Format-Audit](audit.json).

Die zuvor abgeschlossenen Funktionsprüfungen mit Screenshot-Namen sowie die Nachträge für Tresor, Duplikate und Zeichnen bei Zoom stehen in [IMPLEMENTATION_STATUS.md](../docs/IMPLEMENTATION_STATUS.md). Dieser Bericht betrifft den anschließenden Assets-Auftrag.

| Punkt | Status | Dateinamen / Nachweis |
|---|---|---|
| 45 Präsentationsfotos + zehn schwierigere Motive, alle Hochkant und CC0 | PASS | `media/manifest.json`, `media/SOURCES.md` |
| Tatsächliche Simulator-Mediathek enthält genau die 55 Quelldateien | PASS | je Sprache `library.json` und `preview-library.json` |
| Einführung, Heute/Feed, Fotos, Aufräumen, Studio, Tresor, Einstellungen/Pro, Verlauf | PASS für die aufgenommenen Seiten | je Sprache `all-pages/01-introduction/` bis `08-history/`; alle Dateinamen im Sprach-README |
| Dark Mode in allen 16 App-Sprachen | PASS | 1.969 Original-PNGs, 1320 × 2868; Prüfsummen in `screenshots.json` |
| Zehn unveränderte Store-Vorschläge je Sprache | PASS | `app-store-selection/01-today.png` bis `10-vault-viewer.png` |
| Drei unterschiedliche App-Store-Vorschauen je Sprache | PASS | `previews/01-review.mp4`, `02-studio.mp4`, `03-vault.mp4` |
| 886 × 1920, H.264, 30 fps, AAC stereo, 15–30 s, passende Bild-/Tondauer | PASS | `previews/manifest.json`, `audit.json` |
| Vollständige Videodekodierung und tatsächliche Bildstichproben-/Poster-Sichtprüfung | PASS | je Sprache `review/manifest.json`: drei Videos mit je acht Stichproben, drei Poster |
| Native Einrichtung und reale Feed-/Editor-/Tresor-Aktionen | PASS | je Sprache `preview-provenance.json`: 4/4 Tests, null Fehler/Skip |
| Zusätzlicher Screenshot bei jedem Videoschritt | PASS | Quellenartefakte: je 25 native PNGs, alle 400 angesehen |
| Kamera/Dokumentenscanner, echtes Face ID | NOT RUN | physisches iPhone nötig; Scanner im Simulator nachweislich nicht unterstützt |
| iCloud-Originale, 30.000 Medien, Wärme | NOT RUN | physisches Gerät und entsprechende echte Mediathek nötig |
| Videoeditor/Wiedergabe mit echten Videodateien | NOT RUN in diesem Bildsatz | ausdrücklich nur die 55 Fotos importiert; fotobasierte Filmzusammenstellung ist im Seitenarchiv enthalten |

## Sprachen und endgültige Läufe

Je Sprache: 2/2 native Screenshot-Tests und 4/4 native Vorschau-Tests, jeweils ohne Fehler oder Skip. Insgesamt 96 bestandene native UI-Testausführungen für die endgültigen Serien. Die zuvor dokumentierten Kern-/Unit-Prüfungen bleiben separat: Swift 6.4.1 mit 394 Tests in 44 Suites; 24 iOS-Unit-Tests.

| Sprache | Originale | Vorschauen | Screenshot-Lauf | Vorschauaufnahme | Export |
|---|---:|---|---|---|---|
| [Arabisch](locales/ar/README.md) | 123 | [01-review](locales/ar/previews/01-review.mp4) · [02-studio](locales/ar/previews/02-studio.mp4) · [03-vault](locales/ar/previews/03-vault.mp4) | [38744237961](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38744237961) | [38764957492](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38764957492) | [38769640439](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38769640439) |
| [Deutsch](locales/de/README.md) | 123 | [01-review](locales/de/previews/01-review.mp4) · [02-studio](locales/de/previews/02-studio.mp4) · [03-vault](locales/de/previews/03-vault.mp4) | [38735332484](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38735332484) | [38764957492](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38764957492) | [38769640439](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38769640439) |
| [Englisch](locales/en/README.md) | 123 | [01-review](locales/en/previews/01-review.mp4) · [02-studio](locales/en/previews/02-studio.mp4) · [03-vault](locales/en/previews/03-vault.mp4) | [38735332484](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38735332484) | [38764957492](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38764957492) | [38769640439](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38769640439) |
| [Spanisch](locales/es/README.md) | 123 | [01-review](locales/es/previews/01-review.mp4) · [02-studio](locales/es/previews/02-studio.mp4) · [03-vault](locales/es/previews/03-vault.mp4) | [38750057086](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38750057086) | [38765595100](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38765595100) | [38770044249](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38770044249) |
| [Französisch](locales/fr/README.md) | 123 | [01-review](locales/fr/previews/01-review.mp4) · [02-studio](locales/fr/previews/02-studio.mp4) · [03-vault](locales/fr/previews/03-vault.mp4) | [38744237961](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38744237961) | [38765595100](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38765595100) | [38770563352](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38770563352) |
| [Italienisch](locales/it/README.md) | 123 | [01-review](locales/it/previews/01-review.mp4) · [02-studio](locales/it/previews/02-studio.mp4) · [03-vault](locales/it/previews/03-vault.mp4) | [38735332484](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38735332484) | [38765595100](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38765595100) | [38770999865](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38770999865) |
| [Japanisch](locales/ja/README.md) | 123 | [01-review](locales/ja/previews/01-review.mp4) · [02-studio](locales/ja/previews/02-studio.mp4) · [03-vault](locales/ja/previews/03-vault.mp4) | [38742616639](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38742616639) | [38765595100](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38765595100) | [38769716633](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38769716633) |
| [Koreanisch](locales/ko/README.md) | 123 | [01-review](locales/ko/previews/01-review.mp4) · [02-studio](locales/ko/previews/02-studio.mp4) · [03-vault](locales/ko/previews/03-vault.mp4) | [38757333460](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38757333460) | [38765595100](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38765595100) | [38771629526](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38771629526) |
| [Niederländisch](locales/nl/README.md) | 123 | [01-review](locales/nl/previews/01-review.mp4) · [02-studio](locales/nl/previews/02-studio.mp4) · [03-vault](locales/nl/previews/03-vault.mp4) | [38748687136](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38748687136) | [38765595100](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38765595100) | [38770999865](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38770999865) |
| [Polnisch](locales/pl/README.md) | 123 | [01-review](locales/pl/previews/01-review.mp4) · [02-studio](locales/pl/previews/02-studio.mp4) · [03-vault](locales/pl/previews/03-vault.mp4) | [38748687136](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38748687136) | [38765595100](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38765595100) | [38772655624](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38772655624) |
| [Portugiesisch (Portugal)](locales/pt-PT/README.md) | 124 | [01-review](locales/pt-PT/previews/01-review.mp4) · [02-studio](locales/pt-PT/previews/02-studio.mp4) · [03-vault](locales/pt-PT/previews/03-vault.mp4) | [38748687136](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38748687136) | [38765595100](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38765595100) | [38772655624](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38772655624) |
| [Rumänisch](locales/ro/README.md) | 123 | [01-review](locales/ro/previews/01-review.mp4) · [02-studio](locales/ro/previews/02-studio.mp4) · [03-vault](locales/ro/previews/03-vault.mp4) | [38748687136](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38748687136) | [38765595100](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38765595100) | [38774573992](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38774573992) |
| [Russisch](locales/ru/README.md) | 123 | [01-review](locales/ru/previews/01-review.mp4) · [02-studio](locales/ru/previews/02-studio.mp4) · [03-vault](locales/ru/previews/03-vault.mp4) | [38735332484](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38735332484) | [38774007322](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38774007322) | [38774007322](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38774007322) |
| [Türkisch](locales/tr/README.md) | 123 | [01-review](locales/tr/previews/01-review.mp4) · [02-studio](locales/tr/previews/02-studio.mp4) · [03-vault](locales/tr/previews/03-vault.mp4) | [38748687136](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38748687136) | [38765595100](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38765595100) | [38774573992](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38774573992) |
| [Ukrainisch](locales/uk/README.md) | 123 | [01-review](locales/uk/previews/01-review.mp4) · [02-studio](locales/uk/previews/02-studio.mp4) · [03-vault](locales/uk/previews/03-vault.mp4) | [38735332484](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38735332484) | [38765595100](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38765595100) | [38775272307](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38775272307) |
| [Chinesisch (vereinfacht)](locales/zh-Hans/README.md) | 123 | [01-review](locales/zh-Hans/previews/01-review.mp4) · [02-studio](locales/zh-Hans/previews/02-studio.mp4) · [03-vault](locales/zh-Hans/previews/03-vault.mp4) | [38735332484](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38735332484) | [38765595100](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38765595100) | [38775272307](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38775272307) |

## Grenzen und verworfene Zwischenstände

Die französische Ähnlichkeitsanalyse und die niederländische Textanalyse zeigen im Screenshot-Lauf tatsächlich 53/55 und zwei nicht analysierte Medien. Die Bilder sind korrekt erfasst; sie belegen keine vollständige Analyse aller 55 Medien in diesen beiden Scans. Leere Video-/Dateiansichten bleiben ehrlich leer. Kompakte native Steuerelemente können lange lokalisierte Titel kürzen. Die bestehenden chinesischen Texte enthalten teilweise traditionelle Zeichen; eine vollständige sprachliche Redaktion der Übersetzungen wurde nicht durchgeführt.

Die ersten Aufnahme-Workflows hatten trotz bestandener nativer Tests Exportfehler durch variable Bildraten. Der erste Linux-Gegenversuch 38768987654 wurde zusätzlich wegen zu kurzer Bildspuren verworfen. Die endgültigen Exporte prüfen Bild-/Ton-/Containerdauer; alle Videos wurden vollständig dekodiert. Originalaufnahmen bleiben erhalten, längere Demos werden auf 24 s beschleunigt, das echte Schlussbild wird drei Sekunden gehalten.

Russisch im Lauf 38765595100 bestand nur 1/4 native Tests wegen eines Recorder-Startfehlers. Ein frischer russischer Lauf ersetzt ausschließlich dessen Vorschauen vollständig; alte und neue Aufnahmen werden nicht gemischt. Der Recorder wartet länger auf Bereitschaft, bereinigt einen fehlgeschlagenen Start und archiviert jetzt auch seine Fehlerantworten. Der endgültige Lauf 38774007322 besteht 4/4 Tests und alle drei Exporte; die sechs archivierten Recorder-Antworten sind erfolgreich. Die genaue alte Ursache bleibt ohne archivierte Fehlerantwort unbewiesen.

Foto-Systemlöschungen wurden ausschließlich abgelehnt. Aufnahmehilfe und Werbeunterdrückung sind auf den Debug-Simulator plus `-store-capture` beschränkt; die 55 Fotos gehören nicht zum App-Bundle. E1–E19 wurden nicht verändert. Ein weiterer TestFlight-/App-Store-Upload gehört nicht zu diesem Assets-Auftrag.

## Commits des Assets-Auftrags

Implementierungs-, Prüf- und Asset-Commits nach dem bereits ausgelieferten TestFlight-Build 9, bis zum letzten Asset-Commit vor diesem Übergabebericht:

| Commit | Änderung |
|---|---|
| [fafa8d8](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/fafa8d8f00cbd3b82ca631a894cb9a6570cc24f5) | TestFlight-Build 9 und erfolgreiche Verarbeitung dokumentieren |
| [fb70a88](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/fb70a883d2be48468f33fd0cc3cf72583655c5c2) | Hochkant-Bildsatz und lokalisierte Store-Aufnahmen vorbereiten |
| [58b033d](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/58b033d53dfd4b4353e627058f1c544a26a8c75a) | Store-Aufnahmen an den Main Actor binden |
| [14e1675](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/14e16755e46ea19fdd37dde9c9bb8fd5858258b6) | Store-Seiten vollständig öffnen und echte Analysen aufnehmen |
| [19d7392](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/19d73920af108957ab947011536fe2e5a16ca57d) | Simulator-Fotobestand und Fotozugriff für Store-Aufnahmen bereinigen |
| [9029fe4](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/9029fe48f2913caf6586040ab8196e971f327596) | Fotoeinrichtung entkoppeln und Store-Aufnahmen in Etappen prüfen |
| [4ee5777](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/4ee57770faff61732021dee097f42eda1c895e6e) | Diashow-Leisten vor den Detailaufnahmen einblenden |
| [8e70a10](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/8e70a10a14bf51d3cf33d578e00362105a168736) | Store-Seiten ohne Kaltstart aufnehmen und Sichtprüfung vorbereiten |
| [fdea58f](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/fdea58f3e779381aea6608f67b1c69dbf6ef6930) | Store-Aufnahmen bei Scanner und Dialogen absichern |
| [335e935](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/335e935d8e0a509a707286a89ca5ac5d8a7dad2f) | Store-Navigation erst nach dem Tabaufbau öffnen |
| [da3b7c7](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/da3b7c79aa81ab20648075eab04535c091c2f9fe) | Store-Sprachindex und laufenden Aufnahmestatus dokumentieren |
| [bbb21b8](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/bbb21b890e1245350485e2de69f86d78972dbb25) | Editorwerkzeuge sichtbar prüfen und Simulator-Build gemeinsam nutzen |
| [defb941](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/defb9418a63c777a49f514a15573defbe8728d1b) | Store-Bilder erst nach echten Vorschauen und Suchindex aufnehmen |
| [130aff5](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/130aff531bdb78c1026af35eaa40b482f325fb93) | Vorschauposter mit Herkunft und Sichtprüfung erfassen |
| [4f14537](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/4f145375a471d0ca29b3709394ad35793adeb5ac) | Geprüfte Screenshots beim Ergänzen der Videos bewahren |
| [a9e116c](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/a9e116c1872d9848c48f97ac3677044db35c9d0b) | System-Löschabfrage bei Store-Aufnahmen zuverlässig ablehnen |
| [6886707](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/68867076fb0c745e99f8845ae0986dea2a20e092) | Geprüfte deutsche Dark-Mode-Screenshots für den App Store ablegen |
| [739d043](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/739d04334d9a5da88508f565e9084eca023134c3) | Geprüfte italienische Store-Aufnahmen ergänzen |
| [bb4706f](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/bb4706f7accb5bce7a2f54b86d3405bdca352ee1) | Feedposition im Store-Test nach Sprachformat auswerten |
| [59b6e81](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/59b6e8143c3ff9032f65379e6fa37d9ddf20aa30) | Store-Aufnahmen nach echten Analysepausen fortsetzen |
| [244aadd](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/244aadd95c46447bfa2835aa184d3c032a5041e5) | Geprüfte englische Store-Screenshots ergänzen |
| [69b1f70](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/69b1f70f7088e57e36c9d5028a99165cc0ec543e) | Store-Runner ohne vorhandenes Bildarchiv auschecken |
| [58c0e16](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/58c0e16ea705d9213412137793919e1dd122666e) | Sprachindex mit tatsächlich vorhandenen Aufnahmen zählen |
| [f6c16f4](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/f6c16f435d74b2981aca6d47afadc227e17f1307) | Vorschauaktionen sichtbar ausführen und einzeln belegen |
| [0b61180](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/0b611800171b053df756a36ff4d27803c3b1a6a5) | Echten Zoom in der Tresorvorschau prüfen |
| [a0e9fdf](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/a0e9fdfe2888404a517af7bb6c2bdaeb271fde74) | Metadaten vor Store-Screenshots vollständig laden |
| [819609e](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/819609e9fb766d25ab0d87e691cb274ca4ba849a) | Geprüfte russische Store-Screenshots ergänzen |
| [b4d615b](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/b4d615b873375c9ebc10bd68e46074074c22164d) | Aktuellen Prüfstand der Store-Sprachaufnahmen festhalten |
| [3e95ca2](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/3e95ca2d739059f6e5d981fdf803f5e4fc524820) | Manuelle Store-Aufnahmen und Prüfschritte dokumentieren |
| [d8744fb](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/d8744fb3794b4a447469e2317d61219cece881ae) | Wechselnde Menütypen im Store-Test stabil ansprechen |
| [f27706f](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/f27706fb337832da6e0fb4dcb91eb8559afda724) | Geprüfte japanische Store-Screenshots ergänzen |
| [b065a2b](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/b065a2b13f026ed19ac111003b5ba8b3f9936cfb) | Ukrainische und chinesische Store-Bilder geprüft ablegen |
| [d109eb7](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/d109eb728fcb13cc09d1ff9cb2390b01080c8e4d) | Französische und arabische Store-Serien geprüft ablegen |
| [de25643](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/de256437d4e32b7c4a99434546e3ea111c252e85) | Polnische und niederländische Store-Aufnahmen ergänzen |
| [35b7032](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/35b70329fca6caa1097b82154ea86d1cabc17988) | Portugiesische Store-Serie mit Analysefortsetzung ergänzen |
| [d5ed697](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/d5ed697613adf49963afd5cc5ed7ac4960e32754) | Türkische und rumänische Store-Bildserien ergänzen |
| [02e689f](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/02e689f9f486c97ab3a162af27fc3635971bfa65) | Spanische und koreanische Store-Serie abschließen |
| [364f9bf](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/364f9bf1753899f16e24ab444ae9fdf7cfde07ca) | Screenshot-Abschluss für alle 16 Sprachen dokumentieren |
| [ab6dec0](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/ab6dec013cb3e8748aa4add419d7b4709dea933d) | Videoherkunft und vollständige Prüfbelege verknüpfen |
| [741aaab](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/741aaabc7c993f754be927d8fdef65c3579a4700) | Variable Simulator-Bildraten beim Videoexport korrigieren |
| [dcc4fee](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/dcc4feef79ce564394f9bdb9501147119d9b6f79) | Vorhandene Store-Aufnahmen über CI erneut exportieren |
| [955333d](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/955333d8778d7394efcbd9455e94b3a0ee420af6) | Bildspur bis zum Ende der Store-Vorschau erhalten |
| [f146cd9](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/f146cd92183458c901a9ace1d5b84c6cdc6aab67) | Zwölf geprüfte Store-Vorschauen in vier Sprachen ablegen |
| [b4a4034](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/b4a40344a1b825e312bec14ba2204bf018ea6501) | Store-Vorschauen für vier weitere Sprachen ergänzen |
| [1836474](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/18364748171ae8325ffcc4f93ec4efc14d4f215e) | Koreanische Store-Vorschauen geprüft ergänzen |
| [6ee08f3](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/6ee08f3500ca73afe5c76bc099e77d9258e9812a) | Verzögerten Simulator-Recorder sauber behandeln |
| [1e0daee](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/1e0daee99a503ca90a51c4ce5c82543a87deb578) | Polnische und portugiesische Store-Vorschauen ergänzen |
| [c2152ac](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/c2152acf1688c29697a7be0bac6d85d6d12b7d63) | Rumänische und türkische Store-Vorschauen ergänzen |
| [cdf9852](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/cdf9852ed34ca2232c100326d914634196e27350) | Ukrainische und chinesische Store-Vorschauen ergänzen |
| [aa8e4f0](https://github.com/mrdevn4ever-sys/PhotoMaid/commit/aa8e4f0e2e3f706b3381cc9a718ad97b11ab7737) | Russische Vorschauen und vollständigen Store-Audit abschließen |

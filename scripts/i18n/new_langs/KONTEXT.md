# Kontext für neue App-Übersetzungen (aus der Prüfung vom 10.11.2026)

Diese Fehler traten in der ersten Prüfrunde (pt-BR, zh-Hant, id, vi, th, sv, da, nb) mehrfach auf.
Für alle weiteren Sprachen vorab beachten:

| Nr. | Kennung | Bedeutung im Kontext |
|---|---|---|
| 0457 | edit_aspect_free | „Frei“ = freies Seitenverhältnis beim Zuschneiden, **nicht** kostenlos |
| 0797 | hub_large_from | „ab %@“ = Größen-Untergrenze, nicht Herkunft |
| 0272 | blocks_next | nächster Spielstein (Foto Blocks), kein Arbeitsschritt |
| 0291 | blocks_tagline | Reihen entfernen, nicht die Anzahl der Reihen |
| 0964 | memory_flip | falsche Karten wieder **umdrehen/verdecken** |
| 1059 | notice | Überschrift „Hinweis“, keine gespeicherte Notiz |
| 1131 | pdf_fit | „Einpassen“ (ganz zeigen), nicht „entsprechen“ |
| 1208 | put_back | aus dem Papierkorb zurücklegen, nicht zurücksetzen |
| 1259 | rec_medal_next | „Medaille ab Schwelle · noch X“, kein „X von Y“ |
| 1362 | slideshow_again | Diashow **erneut abspielen**, nicht erneut spielen |
| 0827, 1240, 1595 | …open… | „open“ = noch nicht durchgesehen, nicht „geöffnet“ |
| 1494 / 1497 | greeting_afternoon / greeting_noon | Nachmittag (14–17 Uhr) / Mittag (12–13 Uhr) |
| 0276 | – | gemeint sind **Fotos im Tresor**, nicht der Tresor selbst |
| 1767 | – | iOS hat **nicht alle** gelöscht (einige blieben), nicht „keines“ |
| 1612, 1761 | – | die Tresor-**Scheibe/Wählscheibe** im „Q“ dreht sich |
| 1867 | – | gleiche **Tonhöhe**, nicht Lautstärke |

Apple-Begriffe immer in der offiziellen Form der Sprache: Favoriten (Sammlung, gilt für Fotos **und** Videos,
daher geschlechtsneutral), Selfies, „Zuletzt gelöscht“ (z. B. th „ที่ลบล่าสุด“), Zeitraffer, Zeitlupe, Kinomodus,
Schaltersteuerung (Switch Control), „Zurücksetzen/Original“ in der Fotos-App, „iPhone-Speicher optimieren“.

Mengenformen: Sprachen mit CLDR-„many“ für ganze Millionen (pt-BR, ca) dürfen `:many`-Zeilen haben
(`OPTIONAL` in `new_languages.py`).

## Gerätename (iPad seit 1.1)

Die App ersetzt auf dem iPad „iPhone“ durch „iPad“ (`Strings.forDevice`). Deshalb „iPhone“ möglichst **ungebeugt**
schreiben („auf diesem iPhone“ statt mit angehängter Endung). Wo die Sprache eine Endung verlangt, die gebeugte Form
samt iPad-Entsprechung in `Strings.inflected` eintragen (bisher Polnisch und Türkisch).

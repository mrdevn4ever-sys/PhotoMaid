# Prüfung zusätzlicher lokaler Modelle (Masterprompt §5)

Stand 09.10.2026. Ergebnis: **keins der beiden Modelle ist eingebaut.** Die Entscheidung liegt beim Inhaber
(`docs/IOS_ENTSCHEIDUNGEN.md`, E8). Die Angaben stammen aus den öffentlichen Projektseiten (Quellen unten).
Sie wurden nicht auf einem iPhone gemessen. Vor einer Integration muss eine Rechtsprüfung die Lizenzlage bestätigen.

## Zuerst Apple-Frameworks (ohne Zusatzmodell, keine Download-Größe)

| Aufgabe | Apple-API | Ergebnis |
|---|---|---|
| Motiv/Personen freistellen, Hintergrund entfernen | Vision `GenerateForegroundInstanceMaskRequest` (iOS 17+), `GeneratePersonSegmentationRequest`, VisionKit `ImageAnalysisInteraction` | eingebaut (iOS) |
| Text erkennen | Vision `RecognizeTextRequest` | eingebaut |
| Dokumente scannen | VisionKit `VNDocumentCameraViewController` | eingebaut |
| Kategorisieren | Vision `ClassifyImageRequest` | eingebaut |
| Ähnliche Fotos | Vision `GenerateImageFeaturePrintRequest` | eingebaut |
| Bildqualität | Vision `CalculateImageAestheticsScoresRequest` (iOS 18+) | eingebaut |
| Automatische Verbesserung | Core Image `CIImage.autoAdjustmentFilters()` | eingebaut |
| Objekt entfernen (Inpainting) | **keine öffentliche Apple-API** („Bereinigen“ der Fotos-App ist Apple Intelligence, nicht für Apps) | nur mit Zusatzmodell |

## LaMa (Objekt entfernen / Inpainting)

| Kriterium | Befund |
|---|---|
| Quelle | `advimman/lama` (Samsung AI Center, 2021/2022) |
| Lizenz Code/Gewichte | Apache-2.0 (laut Ablegern und Core-ML-Umwandlung, die sich auf das Original berufen). Die LICENSE-Datei des Originals muss vor Integration selbst geprüft werden |
| Trainingsdaten | Big-LaMa wurde auf **Places2 (Places Challenge)** trainiert. Die Nutzungsbedingungen der Places-Datensätze sind **nicht** geklärt. Ob sie die kommerzielle Nutzung der Gewichte berühren, muss eine Rechtsprüfung klären |
| Core ML | Umwandlung eines Dritten vorhanden (`mlboydaisuke/LaMa-CoreML`): 187 MB, Eingabe 800 × 800, iOS 17+, Rechenwerk „all“ (andere Einstellungen führen laut Autor zu FP16-Überlauf oder Absturz) |
| Speicher | laut Autor ca. 600 MB Spitze → auf Geräten mit 4 GB RAM riskant (Jetsam) |
| Tempo | nicht angegeben; muss auf dem Zielgerät gemessen werden |
| App-Größe | +187 MB im Bundle oder als On-Demand-Resource/Background-Assets nachzuladen (Download ohne eigenen Server nur über App Store: On-Demand Resources) |
| Bewertung | technisch machbar; Hürden sind Lizenzlage der Trainingsdaten, Größe und Speicher. Empfehlung: erst nach Rechtsprüfung, dann als On-Demand-Resource nur für Geräte mit ≥ 6 GB RAM |

## MobileSAM (Segmentierung per Tippen/Rahmen)

| Kriterium | Befund |
|---|---|
| Quelle | `ChaoningZhang/MobileSAM` (2023), Destillat aus Meta SAM |
| Lizenz | Apache-2.0 (README, Kornia-Doku, Core-ML-Umwandlung) |
| Trainingsdaten | per Destillation auf einem Teil von SA-1B. Die Bedingungen von SA-1B müssen bei der Rechtsprüfung mit betrachtet werden |
| Größe | Encoder TinyViT ≈ 5–7 Mio. Parameter, Decoder ≈ 4–6 Mio.; Core-ML-Paket eines Dritten (`mlboydaisuke/MobileSAM-CoreML`) ≈ 19 MB |
| Core ML | iOS 17+, Spitzen-RAM ca. 300 MB laut Autor; Rechenwerk nicht ändern (Autor-Hinweis) |
| Tempo | ≈ 10–12 ms auf einer Desktop-GPU (Projektangabe); iPhone-Wert nicht belegt |
| Bewertung | klein genug fürs Bundle. Nutzen gegenüber Vision `GenerateForegroundInstanceMaskRequest`: gezieltes Antippen beliebiger Objekte statt nur „Vordergrund“. Empfehlung: nach Rechtsprüfung möglich; zuerst Vision-Freistellung ausliefern |

## Optionale Bildverbesserung

Kein Zusatzmodell vorgesehen. `autoAdjustmentFilters()` (Core Image) ist lokal, ohne Download, und wird im Editor
als „Automatisch“ angeboten.

## Quellen

- [advimman/lama](https://github.com/advimman/lama)
- [LaMa Core ML (Hugging Face, Dritter)](https://huggingface.co/mlboydaisuke/LaMa-CoreML)
- [LaMa MLX bf16 (Lizenzangabe der Gewichte)](https://huggingface.co/mlx-community/LaMa-bf16)
- [LaMa ONNX (Ableger, Lizenzangabe)](https://huggingface.co/sapienkit/LaMa-ONNX)
- [MobileSAM (Hugging Face Space, README)](https://huggingface.co/spaces/guiop/MobileSAM/blob/main/README.md)
- [MobileSAM Core ML (Hugging Face, Dritter)](https://huggingface.co/mlboydaisuke/MobileSAM-CoreML)
- [Kornia: MobileSAM](https://kornia.readthedocs.io/en/latest/models/mobile_sam.html)
- [Qualcomm AI Hub: MobileSAM](https://aihub.qualcomm.com/iot/models/mobilesam)

# PhotoMaid (iOS)

Native iPhone-App (iOS 27, Swift 6, SwiftUI, Liquid Glass): lokaler Ordnungs- und Aufräumassistent
für Fotos, Videos, Screenshots und freigegebene Ordner.

**Hoch behalten · Links vormerken · Rechts später · Runter zurück.**

- Regeln für Mitwirkende: [`CLAUDE.md`](CLAUDE.md)
- Status: [`docs/IMPLEMENTATION_STATUS.md`](docs/IMPLEMENTATION_STATUS.md)
- Blocker: [`docs/RELEASE_BLOCKERS.md`](docs/RELEASE_BLOCKERS.md)
- Abschlussbericht: [`PHOTOMAID_IOS_FINAL_REPORT.md`](PHOTOMAID_IOS_FINAL_REPORT.md)

## Bauen

```sh
swift test                         # Domain-Kern (macOS oder Linux)
xcodegen generate                  # optional: Projekt aus project.yml neu erzeugen
open PhotoMaid.xcodeproj           # Scheme „PhotoMaid“, iOS 27 Simulator
```

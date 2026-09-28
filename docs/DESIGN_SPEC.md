# Design-Spezifikation

Quelle: `PhotoMaid/DesignSystem/Tokens.swift`, `Components.swift`.

## Identität

Hellblau, luftig, dunkelblaue Typografie, Systemblau für primäre Aktionen, durchscheinende
Bedienelemente. Keine violette Altmarke, kein Neon, keine schwarzen Gaming-Screens.
Die glänzende Präsentationskulisse außerhalb der iPhones ist **kein** App-Wallpaper.

## Tokens

| Rolle | Light | Dark | Erhöhter Kontrast |
|---|---|---|---|
| `background` | #EEF5FD | #0B1626 | #F6FAFF / #050B14 |
| `backgroundTint` | #DCEAFB | #122540 | #E8F1FC / #0A1628 |
| `surface` | Weiß 78 % | #15243A 86 % | deckend |
| `textPrimary` | #0F2747 | #EAF2FF | #06152B / #FFFFFF |
| `textSecondary` | #4A6282 | #A9BCD6 | #2B3F5C / #D5E1F2 |
| `accent`/`keep` | systemBlue | systemBlue | System |
| `cleanup` | systemRed | | |
| `later` | systemTeal | | |

Spacing 4/8/12/16/20/24/32, Seitenrand 18 pt, Radien 12/22/28, Touch ≥ 44 pt.
Typografie: Systemschrift, Dynamic-Type-Stile, keine festen Punktgrößen für Fließtext.

## Glas-Regeln

- Glas (`glassEffect`, `.glass`, `.glassProminent`, `GlassEffectContainer`): Kopfzeilen-Buttons,
  schwebende Controls (Feed-Aktionen, Terminleiste, Dock, Video-Controls), Einstiegshilfe.
- Inhaltslisten: ruhige `surface`-Flächen (`SurfaceCard`, `List`), nicht jeder Datensatz in Glas.
- Reduce Transparency → `GlassCapsuleModifier` fällt auf deckende Fläche zurück.
- Reduce Motion → keine Kipp-/Flugeffekte, Autoplay von Videos aus.
- Light ist Referenz; Dark = dieselbe Marke (Nachtblau).

## Komponenten

`AppBackground`, `SurfaceCard`, `GlassToolbar`, `GlassIconButton`, `SourceRow`, `MetricCard`,
`ReviewDock`, `StatusReceipt`, `EmptyState`, `ErrorState`, `CompactActions`, `LaterReceiptBar`.

## Feed-Layout

Kopf (Schließen · Quelle · Position · Menü) → Medium (Aspect Fit, gerundet) → stabile Zone 84 pt
für die Terminleiste (kein Layoutspringen) → kompakte Aktionen → Auswahlkorb-Dock. Tabbar ausgeblendet
(`fullScreenCover`).

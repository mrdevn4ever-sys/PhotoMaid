# Zustandsübergänge

## Gesten-State-Machine (`FeedGestureMachine`)

```
idle ──update(|t| ≥ deadZone, dominant ≥ lockRatio)──▶ directionLocked(d)
idle ──update(sonst)──▶ dragging
dragging ──end──▶ idle (cancelled, keine Entscheidung)
directionLocked(d) ──update(Strecke in d < unlockDistance)──▶ dragging / directionLocked(d')
directionLocked(d) ──end(Strecke ≥ commitDistance ODER Schwung ≥ flickVelocity ∧ Strecke ≥ flickMin,
                         Querachse klein)──▶ commitRequested(d)
directionLocked(d) ──end(sonst)──▶ idle (cancelled)
commitRequested ──(weitere Gesten ignoriert)── finishCommit ──▶ idle
* ──cancel (System, Rotation, Hintergrund)──▶ idle
isSuspended (Zoom, VoiceOver, Control-Bedienung) ⇒ keine Entscheidungsgesten
```

Richtungswinkel rechts: gerade bis 25° nach oben und bis 45° nach unten = `right`;
25°–50° nach oben = `rightUp` (Datum wählen); 50°–58° oben bzw. 45°–58° unten = Totzone;
ab 58° = `up`/`down`. Bei `right`/`rightUp` entscheidet der Winkel beim Loslassen.

Werte: deadZone 14 pt, lockRatio 1,6, unlockDistance 6 pt, commitDistance 110 pt,
flickVelocity 650 pt/s, flickMinDistance 36 pt.

## Feed-Session (`FeedSession`)

- `requestDecision(intent, revision)` nur wenn: kein offener Commit, Item vorhanden, Vorschau geladen.
  Schließt eine offene Terminleiste.
- `commitSucceeded(commandID)` nur für den offenen Commit (sonst verworfen) → genau `index + 1`.
  Bei `later` entsteht eine Terminleiste, gebunden an Item + Later-Command-ID + Revision.
- `commitFailed(commandID)` → Index zurück, keine Zählung.
- `goBack()` → `index − 1` oder `.atStart` (Anschlag). Keine Entscheidung.
- `jump(to:)` → keine Entscheidung.

## Item-Zustand (`Disposition`)

| von \ Aktion | keep | markForCleanup | later(s) | schedule(d) | removeDeferral | unmark |
|---|---|---|---|---|---|---|
| undecided | kept | marked | later(skip s) | ✗ | ✗ | ✗ |
| kept | = | marked | later | ✗ | ✗ | ✗ |
| marked | kept | = | later | ✗ | ✗ | undecided |
| later | kept (Termin weg) | marked (Termin weg) | later (Termin bleibt, skip s) | later(d) | undecided | ✗ |
| removed | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |

`=` → `unchanged` (keine Revision, kein Event). Jede Änderung: Revision + 1, Event, Undo-Eintrag.
Items in einer offenen Operation: `itemBusy`.

## Operation-Journal (`OperationIntent.state`)

```
prepareCleanup ─▶ prepared (Kapazität reserviert)
prepared ─markSubmitted─▶ submitted ─(Systemoperation)─▶ reconcile(outcome)
reconcile: succeeded | partiallySucceeded | cancelled | failed   (terminal, genau einmal)
Neustart: prepared ─▶ cancelled (Kapazität frei)
          submitted ─▶ reconciliationRequired (Kapazität reserviert, keine Wiederholung)
reconciliationRequired ─resolve(probes)─▶ terminal, wenn alle Items exists/missingWithFullAccess;
                                          bei unknown bleibt der Zustand
```

Tageskontingent: reserviert bei `prepare`, bestätigt bei Abgleich auf den **Reservierungstag**,
freigegeben bei Abbruch/Fehler. Pro: keine Reservierung.

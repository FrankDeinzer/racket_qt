# Report — Linux, Shim-Rebuild + Validierung §59.1/§59.2/§60.3/§60.4/§61.1/§60.6 — 2026-09-28

**Kontext:** Fortsetzung nach der macOS-lastigen §59–§61-Serie und der Windows-Validierung
vom selben Tag (`docs/2026-09-28_report-win.md`). Linux war seit 2026-09-22 (§55) nicht
mehr neu gebaut; drei ABI-relevante Shim-Änderungen (§59.2/§60.3/§60.6) waren aufgelaufen
(Build-Banner in `CLAUDE.md`). Damit ist Linux die letzte der drei Maschinen für diese
Serie.

**Racket:** v9.3 [cs], x86-64 (`~/racket`, nicht im PATH).
**Qt:** 6.11.1, `~/Qt/6.11.1/gcc_64`.
**gui-Submodul (Start dieser Session):** `6bae83df` (7 Commits hinter `origin/qt-backend`;
Umbrella-Zeiger auf `main` stand bereits auf `c986ba6a`, das lokale Checkout war nur
veraltet — `git status` im Umbrella zeigte deshalb `M third_party/gui`, aber es war kein
lokaler Diff, sondern ein rückständiges Checkout).
**qt-shim:** Build vom 2026-09-22 14:46 — vor §59.2/§60.3/§60.6, Rebuild fällig.

---

## Submodul-Sync

Vor jedem Sync-Schritt Nutzer gefragt (Regel 7). Reines Fast-Forward, kein neuer Commit:

```bash
git -C third_party/gui pull origin qt-backend
# Updating 6bae83df..c986ba6a, Fast-forward
```

Bringt das Checkout exakt auf den Stand, den der Umbrella-Zeiger (`main`, Commit
`202832e`) bereits erwartete. `git status` im Umbrella danach clean.

## Shim-Rebuild

```bash
cmake --build qt-shim/build/linux-x64
```

Sauberer Durchlauf (Ninja, 3 Targets), keine Fehler/Warnings, kein Linux-spezifischer
Build-Fix nötig (anders als Windows' `min`/`max`-Kollision in §56 — trat hier nicht auf,
GCC 13.3.0/Ninja).

`nm -D libracketqtshim.so` bestätigt alle neuen Symbole:

```
shim_menu_set_about_to_hide_cb
shim_button_set_label
```

plus alle 24 `shim_list_tree_*`-Exporte (per `grep -c shim_list_tree_` → 24, Namen
gegen die in `CLAUDE.md`s Build-Banner gelistete Menge abgeglichen — vollständig).

## Gate-Tests

```bash
~/racket/bin/raco test tests/stub-audit.rkt
# 9 tests passed

PLT_QT=1 QT_PLUGIN_PATH=~/Qt/6.11.1/gcc_64/plugins ~/racket/bin/raco test tests/smoke.rkt
# 3 tests passed

~/racket/bin/raco test tests/smoke.rkt   # ohne PLT_QT, Gate-Test nativer gtk-Start
# 3 tests passed
```

Alle drei grün, keine Regression. `git status` im Umbrella danach weiterhin clean.

## Validierung gegen echtes DrRacket (`PLT_QT=1`, natives KDE-Fenster)

Durchgeführt von einem delegierten Sonnet-Subagenten (GUI-Automatisierung braucht
Urteilsvermögen, s. `CLAUDE.md`s Subagent-Modellwahl-Regel) per `xdotool`
(fenster-relative Koordinaten) + `spectacle`-Screenshots, Methodik gespiegelt an
`docs/2026-09-28_report-win.md`.

### §59.1/§59.2 — Popup-Menü (Kontextmenü)

Rechtsklick im Definitions-Editor öffnet das Kontextmenü (Undo/Redo/Copy/Cut/Paste/
Clear/Select All). „Select All" angeklickt → Selektion sichtbar (Statuszeile
„1:0-2:0"), Menüaktion funktioniert. Menü erneut geöffnet und per Klick außerhalb
geschlossen → schließt ohne Auswahl, Selektion blieb erhalten, `ps -eo pid,cmd | grep
bin/racket` bestätigt Prozess läuft danach unverändert weiter. Kein Absturz. **PASS.**

### §60.3 — `button%` `set-label`

`Language` → `Choose Language…` per Maus-Navigation geöffnet (Dialog kam mit bereits
expandiertem Details-Bereich hoch, persistiert aus vorheriger Session — deckt sich mit
dem Windows-Befund). Klick auf „Hide Details (Ctrl+D)" kollabiert den Dialog
(880×767 → 380×630) UND das Label wechselt sichtbar zu „Show Details (Ctrl+D)".
Erneuter Klick: Dialog expandiert wieder, Label zurück zu „Hide Details (Ctrl+D)".
**PASS** — Label-Text ändert sich tatsächlich, nicht nur die Dialoggröße.

### §60.4/§61.1 — Collection-Paths-Buttons (`group-panel%`-Chrome-Fix)

Im selben Dialog, Details-Bereich „Collection Paths": alle fünf Buttons (Add, Add
Default, Remove, Raise, Lower) vollständig sichtbar, sowohl initial als auch nach
Hide/Show-Toggle erneut geprüft — keine Titelleistenhöhe schneidet sie ab. **PASS.**

### §60.6 — Mehrspalten-`list-box%` (Package Manager)

`File` → `Package Manager…` → Tab „Currently Installed": 5 Spalten mit Headern (✓,
Scope, Name, Checksum, Source), „213/213 match" (213 installierte Pakete auf dieser
Maschine — macOS hatte 217, Windows 219; erwartete Differenz durch unterschiedliche
Paketinstallationen, kein Befund). Klick auf den „Name"-Header sortiert die Liste
sichtbar alphabetisch (vorher: Installationsreihenfolge beginnend mit `draw-lib`/
`gui-lib`/`main-distribution`; nachher: durchgängig alphabetisch ab `2d`). **PASS.**

Package Manager per `xdotool windowclose`, DrRacket per Maus-Navigation `File → Quit`
sauber beendet (kein Force-Kill nötig). Kein offenes Fenster/Prozess danach.

## Methodik-Befunde (Linux-spezifisch, kein `racket-qt`-Bug)

1. **Koordinatenumrechnung Screenshot↔xdotool ist hier 1:1** (`xdotool
   getdisplaygeometry` liefert exakt die native Screenshot-Auflösung, 2478×1481) — im
   Gegensatz zu Windows' ≈1,22–1,25-Skalierungsfaktor zwischen Fenstertypen
   (`docs/2026-09-28_report-win.md`). Trotzdem: beim manuellen Ablesen von
   Pixelkoordinaten aus einer skaliert angezeigten Bildvorschau (hier 2000×1195 statt
   2478×1481) muss konsequent mit dem Skalierungsfaktor (~1,239) multipliziert werden —
   ein einziger vergessener Umrechnungsschritt führte zu einem Fehlklick auf „Print
   Definitions…" statt „Package Manager…" im File-Menü (sauber per Cancel abgebrochen,
   keine Datei erzeugt, per `git status` verifiziert — kein Bug, reiner
   Automatisierungsfehler).
2. **Menü-Item-Positionen vorab per Hover-Screenshot verifizieren, bevor geklickt
   wird**, statt blind auf berechnete Koordinaten zu vertrauen — hätte den obigen
   Fehlklick vermieden.
3. Fenster-relative Koordinaten (`xdotool mousemove --window <id> <relx> <rely>`) statt
   absoluter Bildschirmkoordinaten sind robuster gegenüber Fensterverschiebung und
   vermeiden die screenshot→real-Umrechnung pro Klick — für künftige Sessions
   bevorzugen.
4. Keine der aus früheren Sessions bekannten Linux-Fallstricke (Ctrl+A-Emacs-Bug,
   unzuverlässige Menü-Klicks) wurde hier zum Problem — alle Interaktionen liefen über
   Maus-Klicks, keine Tastatur-Shortcuts nötig.
5. Der Choose-Language-Dialog öffnet mit dem zuletzt benutzten Details-Zustand (hier:
   bereits expandiert, aus `racket-prefs.rktd`) — deckt sich mit dem Windows-Befund.

## Zusammenfassung

| Prüfpunkt | Ergebnis |
|---|---|
| Submodul-Sync (`6bae83df` → `c986ba6a`) | ✅ |
| Shim-Rebuild | ✅ |
| `stub-audit.rkt` | ✅ 9/9 |
| `smoke.rkt` (`PLT_QT=1`) | ✅ 3/3 |
| `smoke.rkt` (ohne `PLT_QT`, Gate) | ✅ 3/3 |
| §59.1/§59.2 Popup-Menü | ✅ |
| §60.3 `button%` `set-label` | ✅ |
| §60.4/§61.1 Collection-Paths-Buttons | ✅ |
| §60.6 Mehrspalten-`list-box%` | ✅ |

Alle drei seit §59.2/§60.3/§60.6 offenen Rebuild-Pflichten sind damit auf **allen drei
Maschinen** (macOS, Windows, Linux) abgeschlossen. Kein neuer racket-qt-Befund in dieser
Session — reine Rebuild+Validierungsrunde.

## Drei-Maschinen-Sync

Kein neuer Submodul-Commit auf dieser Maschine (reiner Fast-Forward-Pull auf einen
bereits von der Umbrella referenzierten Stand). Keine Code-Änderungen, nur
Dokumentation (`CLAUDE.md`, `docs/HACKING.md`, dieser Report, `STATUS.md`) — folgt dem
üblichen Umbrella-Only-Commit-Pfad. Push noch ausstehend, s. Rückfrage an den Nutzer.

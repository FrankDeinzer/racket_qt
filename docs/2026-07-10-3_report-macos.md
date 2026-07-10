# Report: 2026-07-10-3_prompt (macOS, Phase 4 — Cross-Platform-Validierung)

**Racket-Version (gemessen):** Welcome to Racket v9.2 [cs].

## 1. Zusammenfassung

Reine Validierungssession (kein Fix-Code) für die beiden auf Windows gefixten
Fundament-Befunde `docs/HACKING.md` §18.2 (Panel-Sizing) und §18.3 (Modalität), bereits
auf Linux grün validiert. Diese Session schließt die Cross-Platform-Validierung ab.
Beide Fixe sind auf macOS grün. Keine Fix-Commits in `wx/qt/`.

## 2. Phase 4 — Sync + Rebuild

- **Vor dem Pull geprüft** (CLAUDE.md Regel 7): Nutzer per `AskUserQuestion` gefragt, ob
  jetzt gesynct werden soll — bestätigt.
- gui-Submodul (`qt-backend`) lag 3 Commits hinter `origin/qt-backend`: `04935cb6` →
  `f92352e0` via `git pull --ff-only` (Fast-Forward). Enthaltene Commits: `08bf0af6`
  (list-box%/check-box% real), `8904b264` (Fix A — Panel-Sizing), `f92352e0` (Fix B —
  Modalität).
- Umbrella `main` war bereits mit `origin/main` deckungsgleich, Zeiger auf
  `third_party/gui` bereits `f92352e0` — kein Umbrella-Pull nötig.
- **Shim neu gebaut** (`cmake --preset macos-arm64 -S qt-shim && cmake --build
  qt-shim/build/macos-arm64`): sauberer Build (`shim.cpp` neu kompiliert, enthält jetzt
  `shim_widget_get_size_hint` und `shim_widget_set_enabled`), Link ohne Fehler/Warnings.
- **Bytecode neu:** macOS konsumiert den Fork über `-S`-Source-Override (kein
  Installation-wide-Link wie Windows), daher `racket -S third_party/gui/gui-lib -S
  third_party/draw/draw-lib -l raco -- make -l mred` statt `raco setup` — durchgelaufen
  ohne Fehler/Warnungen.
- **Re-Smoke:** `PLT_QT=1 racket -S ... -l raco -- test tests/smoke.rkt` → **3/3 grün**.
- **Light Mode bestätigt:** `~/Library/Preferences/org.racket-lang.prefs.rktd` zeigt
  `white-on-black-mode? #f` (und `white-on-black? #f`).

## 3. Werkzeuge dieser Session

Keine synthetischen Low-Level-Events nötig — Fenster-Interaktion lief vollständig über
die macOS-Accessibility-API via `osascript`/System Events (wie im bestehenden
`project_macos_bringup`-Muster für GUI-Diagnose auf dieser Maschine):
- Fensterposition/-größe: `tell process "racket" to set/get position/size of window …`.
- Klicks auf benannte Controls statt Pixel-Koordinaten: `click button "…" of window …`,
  `click checkbox "…" of window …` — robuster als Pixel-Scans, da der Accessibility-Baum
  Buttons/Checkboxen über ihr Label direkt adressiert.
- Screenshots: `screencapture -x -R<x>,<y>,<w>,<h>` (kein XWD-Parsing wie auf Linux nötig,
  natives PNG).
- Einzige Einschränkung: `click row … of table 1 of scroll area 1` für die `list-box%`-
  Selektion fand das Element nicht (Fehler „ungültiger Index" — vermutlich andere
  Accessibility-Rollen-Hierarchie für `QListWidget` auf macOS als angenommen). Nicht
  weiter verfolgt, da für den Modalitäts-Nachweis nicht nötig; `check-box%`-Klick und
  Funktionsnachweis liefen über den direkten `checkbox`-Rollennamen problemlos.

## 4. Fix A — Panel-Sizing (§18.2): validiert, grün

`examples/panel-sizing-probe.rkt` unverändert (keine Workarounds). Screenshot nach
Start: alle drei `button%` ("Button ONE"/"TWO"/"THREE") stehen sauber vertikal
untereinander, keine Überdeckung — identisch zum Windows-/Linux-Nachher-Ergebnis
(`docs/2026-07-10-3_report-win.md` §3.3, `docs/2026-07-10-3_report-linux.md` §4).

`examples/dialog-widgets-probe.rkt` (ebenfalls ohne Workaround): Parent-Frame
(Message-Text + 2 Buttons) UND der später geöffnete Dialog (`list-box%` mit 4 Einträgen
"Alpha"/"Beta"/"Gamma"/"Delta" + `check-box%` "Enable feature X" + OK/Cancel) layouten
korrekt ohne jede explizite Mindestgröße.

Smoke 3/3 weiterhin grün nach beiden Läufen.

## 5. Fix B — Modalität (§18.3): validiert, grün

**Ablauf:**
1. `dialog-widgets-probe.rkt` gestartet, Parent-Fenster per Accessibility-API
   positioniert. Screenshot bestätigt Ausgangslayout (siehe §4).
2. "Open dialog" per `osascript click button "Open dialog"` betätigt — Dialog erscheint
   (`list-box% + check-box% driver`), an eine nicht überlappende Position verschoben.
   Screenshot zeigt Dialog mit `list-box%` (4 Einträge) + `check-box%` + OK/Cancel, **und**
   das Parent-Fenster im Hintergrund mit sichtbar ausgegrautem Text auf "Parent button"
   und "Open dialog" — deutlicher visueller Kontrast (siehe §6).
3. `check-box%` per `click checkbox "Enable feature X"` getoggelt — Log zeigt
   `check-box toggled: #t` (Funktionsnachweis, Dialog-Controls bleiben während offenem
   Modal voll bedienbar).
4. Klick auf den Parent-Button ("Parent button (should be blocked while dialog is
   open)") bei weiterhin offenem Modal → kein sofortiger Log-Effekt.
5. Dialog per Klick auf "OK" geschlossen — Log zeigt `dialog closed — final list-box
   selections=() check-box value=#t` (die leere Selektion ist ein Artefakt des in §3
   genannten fehlgeschlagenen `list-box%`-Accessibility-Zugriffs, nicht der Modalität;
   der `check-box%`-Wert `#t` bestätigt korrektes State-Tracking über den Dialog-Lebenszyklus).
6. **Methodik-Gegenprobe:** derselbe Klick auf denselben Parent-Button, jetzt bei
   **geschlossenem** Dialog → `PARENT BUTTON CLICKED — should NOT print while dialog is
   open` erscheint — und zwar als **einziges** Vorkommen im gesamten Log, direkt nach
   `dialog closed —…`. Das belegt zweierlei gleichzeitig: die Klick-Mechanik
   (Accessibility-Klick auf den Button) funktioniert einwandfrei, UND der Klick aus
   Schritt 4 (bei offenem Modal) hat tatsächlich **keinen** Callback ausgelöst — die
   Blockade ist ursächlich an die Modalität gebunden, kein Test-Artefakt.

Vollständiger Log-Ausschnitt (chronologisch, nach Prozessende gelesen):
```
check-box toggled: #t
dialog closed — final list-box selections=() check-box value=#t
PARENT BUTTON CLICKED — should NOT print while dialog is open
```

Smoke 3/3 grün nach dem gesamten Ablauf.

## 6. Visueller Kontrast — deutlich sichtbar (Unterschied zu Linux)

Anders als bei der Linux-Validierung (Pixel-Sampling dort ergab keinen eindeutigen
Enabled/Disabled-Unterschied) ist der Grau-Kontrast auf macOS im Screenshot klar
erkennbar: die Labels "Parent button (should be blocked while dialog is open)" und
"Open dialog" im Parent-Fenster erscheinen sichtbar heller/grauer als die scharfen
schwarzen Labels im aktiven Dialog-Fenster ("Items:", "Alpha"/"Beta"/…, "Enable feature
X", "OK"/"Cancel"). Das deckt sich mit dem für Windows berichteten deutlichen Kontrast
(`docs/2026-07-10-3_report-win.md` §4.4) — plausibel eine Theme-/Style-Differenz
zwischen den Plattformen (macOS-natives Qt-Styling vs. Linux/KDE-Breeze), nicht Teil des
Scopes dieser Session.

## 7. Guardrails eingehalten

- Kein `exec()`/`QEventLoop`, keine geschachtelte Schleife (Test lief vollständig über
  externe Accessibility-Events + normale Racket-Eventspace-Pump).
- cocoa/gtk/win32 nicht angefasst.
- Nur Fast-Forward-Pull, vorher per `AskUserQuestion` bestätigt.
- Gated Diagnose bleibt gated (`PLT_QT_DEBUG` nicht verändert/genutzt).
- Reine Validierung — keine Fix-Commits in `wx/qt/`.
- Report-Header nutzt gemessene `racket --version`.

## 8. Commits & Stand

- gui-Submodul (`qt-backend`): ff-Pull `04935cb6` → `f92352e0`, keine neuen Commits.
- Umbrella (`main`): `docs/HACKING.md` §18.2/§18.3 (macOS-Validierungsabsätze),
  `STATUS.md`-Eintrag, `CLAUDE.md`-Checkpoint-Tabelle, dieser Bericht.

## 9. Nächste Schritte

Cross-Platform-Validierung für Fix A + Fix B (§18.2/§18.3) ist damit auf allen drei
Plattformen (Windows/Linux/macOS) abgeschlossen. Nächster Meilenstein: Checkpoint E
fortsetzen (choice%/radio-box%/slider%/tab-panel%), danach file-selector, danach
Preferences — wie in `docs/2026-07-10-3_prompt.md` vorgesehen.

# STATUS

Kurzer, laufend aktualisierter Stand für alle drei Entwicklungsmaschinen
(Windows / macOS arm64 / Linux x64). Details je Session in `docs/`.

---

## Session 2026-07-12 (Windows) — Konsolidierung: Push-Check + DrRacket-Lücke (2026-07-11-2_prompt)

**Kontext:** `docs/2026-07-11-2_prompt.md`. Voller Bericht: `docs/2026-07-11-2_report-win.md`.

- **Phase 0 (Push-Check):** Beide macOS-Fixe (`acc73108` id-to-menu-item, `caef3e9c`
  retained-callbacks) waren bereits auf `origin/qt-backend`, Umbrella-Zeiger (`759d025`)
  bereits auf `origin/main` — kein Push nötig, entgegen der im Prompt offen gelassenen
  Unsicherheit. Nur der lokale Windows-Submodul-Checkout war zurück (`19954ffd`).
- **Phase 1 (Sync + DrRacket-Lücke):** Nach Nutzer-Bestätigung `git submodule update
  --init` → lokal auf `caef3e9c`. Beide Fixe sind reiner Racket-Code (kein Shim-Rebuild
  nötig). `raco make` + Re-Smoke 3/3 grün. **Nachgeholt:** echtes `PLT_QT=1` DrRacket
  File → Open + Save As vom Nutzer bestätigt funktionsfähig, kein Crash. Windows
  Qt-eigen×nativ-Matrix war bereits aus Vorsession komplett (7/7 nativ).
- **Bewusst nicht getan:** Linux Crash-A/B-Rückprüfung (Kernstück des Blocks) und
  Linux/macOS-Nativ-Matrix — beide für die jeweilige Maschinen-Session vorgesehen.
  `docs/HACKING.md` §19 Crash-A/B-Status entsprechend unverändert gelassen.

---

## Session 2026-07-12 (macOS) — `file-selector` Cross-Platform-Validierung + zwei Bugfixes (2026-07-11_prompt)

**Kontext:** `docs/2026-07-11_prompt.md`. Voller Bericht: `docs/2026-07-11_report-macos.md`.

- **Sync (nach Nutzer-Bestätigung):** gui-Submodul `qt-backend` ff-Pull `f92352e0` →
  `19954ffd`. Umbrella `main` war bereits aktuell. Shim neu gebaut, Bytecode neu, Smoke
  3/3 grün. Light Mode bestätigt.
- **Button-Pfad sofort grün:** 7/7 `get-file`/`put-file`-Zyklen über den Probe-Treiber,
  `cb`-Adresse über alle Aufrufe und den `get`→`put`-Wechsel identisch.
- **Echtes DrRacket File → Open crashte zunächst reproduzierbar (2/2)** —
  anders als Linux' n=1-Abstürze. Ein Discriminator-Test (`get-file` über einen
  `menu-item%` statt einen Button) isolierte die Ursache auf den Menü-Klick-Dispatch,
  nicht auf `file-selector` selbst.
- **Zwei echte, unabhängige Bugs in `wx/qt/` gefunden + gefixt** (auf Nutzer-Zustimmung,
  beide nur wx/qt/, kein Shared-Code-Verstoß):
  1. `wx/qt/platform.rkt`s `id-to-menu-item` rief `get-mred` fälschlich selbst auf statt
     (wie gtk/win32) die Auflösung dem generischen `wx->mred` zu überlassen. Commit
     `acc73108`.
  2. `wx/qt/menu.rkt`s `append` erzeugte pro Menüpunkt eine Callback-Closure, die nirgends
     retained wurde — GC konnte sie einsammeln, während die native `QAction` einen jetzt
     toten Funktionszeiger hielt (dieselbe Landmine wie `file-selector`s eigener
     Trampolin-Fix, §19 Fund 2 — nur hier für jeden normalen Menüpunkt). Fix: neues
     `retained-callbacks`-Hasheq. Commit `caef3e9c`. Verifiziert mit explizitem
     `(collect-garbage)`-Stresstest im Probe-Skript.
- **Nach beiden Fixes: echtes DrRacket File → Open + Save As + ein zweiter File → Open
  bestätigt funktional** (Nutzer). `file-selector` auf macOS damit End-to-End
  bestätigt.
- **Dritter, unabhängiger Fund, NICHT gefixt** (außerhalb `gui-lib`, auf Nutzer-Wunsch
  untersucht): `htdp-lib`s `test-engine/test-tool.rkt` verletzt beim Öffnen eines
  zweiten Tabs eine eigene Preference-Contract (`test-engine:test-dock-size`), DrRacket
  zeigt daraufhin ein „Internal Error"-Fenster, danach folgt ein harter nativer Absturz.
  Ein isolierter Qt-only-Repro (`examples/tab-close-crash-probe.rkt`, neu) reproduziert
  den harten Absturz NICHT — braucht den vollen DrRacket-Stack, nicht root-caused.
  Vermutlich derselbe Mechanismus wie Linux' bereits dokumentiertes Crash A (§19).
- **Commits (gui-Submodul, noch NICHT gepusht — offene Entscheidung mit dem Nutzer):**
  `acc73108`, `caef3e9c`.
- **Nächster Schritt:** Push + Drei-Maschinen-Sync der beiden Fixes abstimmen; Windows/
  Linux sollten danach ihre dokumentierten Abstürze (Linux Crash A/B) erneut versuchen.
  Dritter Fund (htdp-lib) für eigene Session. Danach Cross-Platform-Matrix (Qt-eigen/
  nativ), Rest von Checkpoint E, Preferences.

---

## Session 2026-07-11 (Linux) — `file-selector` Cross-Platform-Validierung (2026-07-11_prompt)

**Kontext:** `docs/2026-07-11_prompt.md`. Voller Bericht: `docs/2026-07-11_report-linux.md`.

- **Sync (nach Nutzer-Bestätigung):** gui-Submodul `qt-backend` ff-Pull `f92352e0` →
  `19954ffd`. Umbrella `main` war bereits aktuell (Zeiger `19954ffd`), kein Pull nötig.
  Shim neu gebaut, Bytecode neu, Smoke 3/3 grün. Light Mode bestätigt.
- **Probe-Treiber validiert:** 9/9 Dialog-Zyklen (5× `get-file`, 4× `put-file`, gemischt
  Accept/Cancel/Overwrite-Warnung), `cb`-Adresse über alle 9 Aufrufe **und über den
  `get`→`put`-Moduswechsel hinweg** identisch — Einmal-Trampolin-Fix bestätigt.
- **Echtes DrRacket:** File → Open und File → Save bestätigt funktional (Nutzer,
  Datei lädt/speichert korrekt). Isolierter Test bestätigt `setDefaultSuffix`
  (Extension-Anhängen) arbeitet korrekt (`myfile` → `myfile.rkt`).
- **Zwei unabhängige, seltene Abstürze beobachtet, außerhalb des `get-file`/`put-file`-
  Wertpfads, nicht root-caused/gefixt** (Guardrail: mutmaßlich gemeinsamer Code,
  Entscheidung über Verfolgung liegt beim Nutzer): (A) `pre: arity mismatch …
  terminated in atomic mode!` bei einem sehr frühen Interaktionsversuch mit einer noch
  nicht vollständig gestarteten DrRacket-Instanz (n=1, nicht reproduziert bei
  geduldigerem zweiten Versuch); (B) `invalid memory reference` nach bereits korrekt
  gedrucktem `put-file`-Rückgabewert in einem Skript ohne sichtbares `frame%`
  (Teardown-Reihenfolge-Verdacht). Details `docs/HACKING.md` §19,
  `docs/2026-07-11_report-linux.md`.
- Keine Fix-Commits diese Session — reine Validierung + Befund.
- **Nächster Schritt:** macOS-Validierung dieses Prompts steht noch aus. Danach
  Cross-Platform-Matrix (Qt-eigen/nativ), Rest von Checkpoint E, Preferences. Crash A/B
  zur Entscheidung: gezielt verfolgen oder eigener Session überlassen.

---

## Session 2026-07-11 (Windows) — `file-selector` echt: `get-file`/`put-file` via non-modaler `QFileDialog` (2026-07-11_prompt)

**Kontext:** `docs/2026-07-11_prompt.md`.

- **Kernfrage geklärt (Checkpoint 1):** `QFileDialog::open()` (nie `exec()`) zeigt den
  Dialog window-modal an und kehrt sofort zurück; das Ergebnis kommt über
  `QDialog::finished`, das während eines normalen `shim_pump()`-Aufrufs feuert. Racket-
  seitig nach außen synchron über denselben `(yield (semaphore-peek-evt done-sema))`-
  Mechanismus wie `dialog%`s Modal-Show (`../common/dialog.rkt`). Kein `exec()`, kein
  eigener `QEventLoop`.
- **Echter Bug gefunden + gefixt (nicht nur gemessen):** ein frischer `_fun`-Callback pro
  `get-file`/`put-file`-Aufruf (statt einmalig pro Widget-Konstruktor wie überall sonst in
  diesem Backend) crashte reproduzierbar nach ein paar Aufrufen (`APPCRASH`/`c0000005`,
  per WER bestätigt) bzw. produzierte nach einem Zwischenfix einen `make-ffi-callback:
  contract violation`-Hang. Root Cause: Racket-CS-Callbacks sind immer atomic, und
  `_fun`s Ctype-Konverter erzeugt bei jedem Aufruf einen neuen nativen Trampolin, egal ob
  dieselbe Prozedur erneut übergeben wird (keine Memoisierung nach Prozedur-Identität).
  Fix: genau ein `function-ptr`-Callback einmal beim Modul-Laden, Dispatch über eine als
  `ud` durchgereichte Ganzzahl-ID; `shim_file_dialog_create`s `cb`-Parameter in
  `utils.rkt` als reines `_pointer` deklariert (nicht `_file_dialog_cb_t`), damit der
  fertige Callback-Pointer nicht erneut gewrappt wird. Details `docs/HACKING.md` §19.
- **Verifiziert (Nutzer, `examples/file-dialog-probe.rkt`, echte Interaktion):** 8/8
  aufeinanderfolgende Öffnen-Zyklen (jedes Mal andere Datei), `cb`-Adresse im Log über
  alle 8 identisch; 5× Öffnen→Abbrechen; mehrfach Speichern→Speichern (inkl. Overwrite-
  Warnung bei existierender Datei) und Speichern→Abbrechen — alles grün. Smoke 3/3.
- **Zwei separate Commits pro Repo (get-file; put-file), jeweils sofort gepusht** — get-
  file zuerst (Submodul `qt-backend` `15dee9f9`, Umbrella `main` `a40ae55`), dann put-
  file (Submodul `19954ffd`, Kernmechanik identisch — nur der `'put`-Style-Bail-out aus
  dem ersten Commit entfernt).
- **Doku:** `docs/HACKING.md` §19 (neue Lektion: Einmal-Callback-plus-Userdata-ID-Muster
  für Nicht-Widget-Callbacks), `CLAUDE.md`-Checkpoint-Tabelle, dieser Eintrag.
- **Phase 3 (nativer Windows-Dialog) — gemessen, trägt.** `PLT_QT_NATIVE_FILE_DIALOG=1`
  (Env-Schalter, kein neuer `get-file`/`put-file`-Parameter): nativer Windows-Common-
  Dialog läuft über denselben non-modalen `open()`+Pump-Mechanismus, 7/7 Zyklen grün,
  gleicher Callback über alle Aufrufe. Als Stil-Option vermerkt; Qt-eigener Dialog bleibt
  Standard-Pfad. Details `docs/HACKING.md` §19.
- **Nächster Schritt:** Cross-Platform-Matrix (Linux/macOS × Qt-eigen/nativ, 4 Fälle pro
  Plattform) — eigene Runde. Danach Rest von Checkpoint E (choice%/radio-box%/slider%/
  tab-panel%), dann Preferences.

---

## Session 2026-07-10 (3, macOS) — Panel-Sizing-Fix + Modalitäts-Fix, Cross-Platform-Validierung abgeschlossen (2026-07-10-3_prompt)

**Kontext:** `docs/2026-07-10-3_prompt.md`. Voller Bericht: `docs/2026-07-10-3_report-macos.md`.

- **Sync (nach Nutzer-Bestätigung):** gui-Submodul `qt-backend` ff-Pull `04935cb6` →
  `f92352e0`. Umbrella `main` war bereits aktuell (Zeiger `f92352e0`), kein Pull dort
  nötig. Shim neu gebaut (`cmake --build qt-shim/build/macos-arm64`), Bytecode neu
  (`-S`-Source-Override, `raco make`), Smoke 3/3 grün. Light Mode bestätigt
  (`org.racket-lang.prefs.rktd`: `white-on-black-mode?` = `#f`).
- **Fix A (Panel-Sizing) validiert:** `examples/panel-sizing-probe.rkt` (unverändert) —
  Screenshot (`osascript`/`screencapture`) zeigt alle drei `button%` sauber vertikal
  gestapelt. `dialog-widgets-probe.rkt` ohne Workaround: `list-box%`/`check-box%`
  layouten korrekt neben OK/Cancel.
- **Fix B (Modalität) validiert:** Klick via Accessibility-API (`osascript`/System
  Events) auf den Parent-Button bei offenem Modal löst keinen Callback aus; derselbe
  Klick nach Schließen des Dialogs löst ihn sofort aus (einziges Log-Vorkommen, direkt
  nach `dialog closed —…`) — bestätigt Blockade ist ursächlich an die Modalität
  gebunden. **Visueller Grau-Kontrast hier deutlich sichtbar** (anders als Linux,
  ähnlich Windows) — plausibel Theme-/Style-Differenz, nicht Teil des Scopes.
- Details `docs/HACKING.md` §18.2/§18.3 (macOS-Validierungsabsätze ergänzt).
- **Reine Validierung, keine Fix-Commits. Cross-Platform-Validierung (Windows/Linux/
  macOS) für Fix A + Fix B damit abgeschlossen.** Nächster Schritt: Checkpoint E
  fortsetzen (choice%/radio-box%/slider%/tab-panel%), danach file-selector, danach
  Preferences.

---

## Session 2026-07-10 (3, Linux) — Panel-Sizing-Fix + Modalitäts-Fix, Cross-Platform-Validierung (2026-07-10-3_prompt)

**Kontext:** `docs/2026-07-10-3_prompt.md`. Voller Bericht: `docs/2026-07-10-3_report-linux.md`.

- **Sync (nach Nutzer-Bestätigung):** gui-Submodul `qt-backend` ff-Pull `04935cb6` →
  `f92352e0` (3 Commits: `08bf0af6` list-box%/check-box%, `8904b264` Fix A, `f92352e0`
  Fix B). Umbrella `main` war bereits aktuell (`f86bb09`, Zeiger auf `f92352e0`), kein
  Pull dort nötig.
- Shim neu gebaut (`cmake --build qt-shim/build/linux-x64`) — beide neuen
  Shim-Funktionen (`shim_widget_get_size_hint`, `shim_widget_set_enabled`) kompilieren
  sauber. Bytecode neu (`raco make -l mred`). Smoke 3/3 grün. Light Mode bestätigt
  (`racket-prefs.rktd`: `framework:white-on-black?` = `#f`).
- **Fix A (Panel-Sizing) validiert:** `examples/panel-sizing-probe.rkt` (unverändert)
  — Screenshot (`xwd` + selbstgeschriebener XWD→PNG-Parser, da kein
  `pnmtopng`/`convert`/`scrot` auf dieser Maschine) zeigt alle drei `button%` sauber
  vertikal gestapelt. `dialog-widgets-probe.rkt` ohne Workaround: `list-box%`
  (4 Einträge)/`check-box%` layouten korrekt neben OK/Cancel.
- **Fix B (Modalität) validiert:** synthetischer `libXtst`-Klick (kein `xdotool`,
  selbstgebauter Helfer wie in den Redraw-Sessions) auf den Parent-Button bei offenem
  Modal löst keinen Callback aus (stdout-Log leer bis Prozessende); derselbe Klick
  nach Schließen des Dialogs löst ihn sofort aus — bestätigt Blockade ist ursächlich
  an die Modalität gebunden, kein Test-Artefakt. Visueller Grau-Kontrast in diesem
  Qt-Stil nicht eindeutig sichtbar, funktionale Blockade aber eindeutig.
- Details `docs/HACKING.md` §18.2/§18.3 (Linux-Validierungsabsätze ergänzt).
- **Reine Validierung, keine Fix-Commits.** Nächster Schritt: macOS-Validierung
  (Phase 4), danach Checkpoint E (choice%/radio-box%/slider%/tab-panel%;
  file-selector; Preferences).

---

## Session 2026-07-10 (3, Windows) — Panel-Sizing-Fix + Modalitäts-Fix (2026-07-10-3_prompt)

**Kontext:** `docs/2026-07-10-3_prompt.md`. Voller Bericht: `docs/2026-07-10-3_report-win.md`.

- **Phase 0 — grün.** `racket --version` = v9.2 [cs]. Beide Repos sauber auf
  `04935cb6`/`96cabe5` (Fetch bestätigt deckungsgleich mit origin). Shim aktuell (DLL
  neuer als `shim.cpp`). Light Mode bestätigt (`framework:white-on-black-mode?` = `#f`).
  Smoke 3/3 grün.
- **Phase 1 — Fix A (Panel-Sizing, §18.2): gefixt, gemessen, gepusht.** Neue Shim-Funktion
  `shim_widget_get_size_hint` (`QWidget::sizeHint()`), neue `window%`-Methode
  `seed-size-from-native-hint` (`wx/qt/window.rkt`), aufgerufen von
  `button.rkt`/`message.rkt`/`check-box.rkt` (nach `super-new`) und `list-box.rkt` (nach
  dem Befüllen der Choices) — bewusst NICHT von `canvas%` (eigener Seed-Pfad, `dc`-Feld
  existiert bei `super-new` noch nicht). Vorher: isoliertes 3-`button%`-Repro
  (`examples/panel-sizing-probe.rkt`, neu) zeigt nur das zuletzt erzeugte Button (Rest
  exakt überdeckt) — Screenshot bestätigt, Debug-Log zeigt `pre-seed w=0 h=0`. Nachher:
  alle drei Buttons sauber vertikal gestapelt, Debug-Log zeigt `sizeHint=81x26` etc.
  `dialog-widgets-probe.rkt`s Workaround-`[min-width]`/`[min-height]` entfernt —
  `list-box%`/`check-box%`/OK/Cancel layouten weiterhin korrekt. Smoke 3/3, `hello.rkt`
  (canvas%-Pfad) visuell nicht regrediert. Commits: gui `8904b264` (gepusht), Umbrella
  `9e54291` (gepusht).
- **Phase 2 — Fix B (Modalität, §18.3): gefixt, gemessen, gepusht.** Neue Shim-Funktion
  `shim_widget_set_enabled` (`QWidget::setEnabled`). `wx/qt/frame.rkt` bekommt
  `modal-enable` (1:1 gespiegelt an `wx/win32/frame.rkt`, berechnet über das bestehende
  `other-modal?`/`dialog-level`-Bookkeeping), `wx/qt/dialog.rkt`s `direct-show` ruft sie
  auf jedem Top-Level-Fenster der Eventspace auf (1:1 gespiegelt an
  `wx/win32/dialog.rkt`). Gemessen statt blind gefixt, ob Lücke (b) (native Callbacks
  nicht an `other-modal?` angebunden) nach (a) noch nötig ist: **nein** — Qts
  `setEnabled(false)`-Kaskade blockiert native Klick-Callbacks der Kind-Widgets bereits
  vollständig (kein `PARENT BUTTON CLICKED`-Print bei simuliertem Klick auf den
  disabled-Parent-Button). Vorher/Nachher visuell bestätigt: Parent-Frame grau/disabled
  bei offenem Modal, Klick ohne Wirkung; nach OK/Cancel wieder normal eingefärbt +
  klickbar; Dialog-Controls bleiben durchgehend funktional. Smoke 3/3 grün. Kein
  `exec()`/keine geschachtelte Schleife. Commits: gui `f92352e0` (gepusht), Umbrella
  `4030fe2` (gepusht).
- **Vier separate Commits (zwei pro Fix, Submodul zuerst, dann Umbrella-Pointer),
  jeweils sofort gepusht** — saubere Rollback-Punkte pro Fix, wie vom Prompt gefordert.
- **Doku:** `docs/HACKING.md` §18.2/§18.3 von „Kandidat" auf „bestätigt + gefixt"
  aktualisiert (Fix-Details ergänzt, Original-Diagnose als Historie erhalten),
  `CLAUDE.md`-Checkpoint-Tabelle + Narrative aktualisiert, dieser Eintrag, Report.
- **Nächster Schritt:** Linux-Validierung (Phase 3) → macOS-Validierung (Phase 4), siehe
  `docs/2026-07-10-3_prompt.md`. Danach file-selector (Block danach, jetzt auf modal
  korrektem `dialog%` aufsetzend), dann Preferences (Block danach, jetzt mit
  funktionierendem Auto-Layout).

---

## Session 2026-07-10 (2, Windows) — Checkpoint E begonnen: `list-box%`/`check-box%` echt (2026-07-10-2_prompt)

**Kontext:** `docs/2026-07-10-2_prompt.md`. Voller Bericht: `docs/2026-07-10-2_report-win.md`.

- **Treiber-Korrektur vor jeder Implementierung:** geplanter Treiber (Autosave-Recovery-
  Dialog) zieht laut Quelltext (`framework/private/autosave.rkt`) weder `list-box%` noch
  `check-box%` — gemeldet statt stillschweigend weitergemacht, Nutzer bestätigte direkten
  Wechsel zu Stufe 2 (isoliertes Testskript `examples/dialog-widgets-probe.rkt`).
- **`list-box%`/`check-box%` jetzt echt** (`QListWidget`/`QCheckBox`), nativ gegen
  wx/win32 + wx/gtk gespiegelt. Nutzerbestätigt funktional: Single-Selection über 4
  Einträge, Checkbox an/ab, OK/Cancel schließen den Dialog korrekt. Details
  `docs/HACKING.md` §18.
- **Zwei neue, vorbestehende (nicht durch diese Session verursachte) Befunde, beide
  NICHT gefixt (Scope-Entscheidung, advisor-abgestimmt):**
  1. **Panel-Sizing-Bug:** jedes echte Qt-Control (`button%`/`message%` schon vorher,
     jetzt auch `check-box%`/`list-box%`) seedet `min-width`/`min-height` als 0
     (`wxitem.rkt` fragt `get-width`/`get-height` vor dem ersten `set-size` ab) — mehrere
     Controls in einem `vertical-panel%` landen dadurch alle exakt übereinander.
     Workaround für den Treiber dieser Session: explizite `[min-width]`/`[min-height]`.
  2. **`dialog%`-Modalität blockiert native Control-Callbacks nicht:** Parent-Button
     bleibt bei offenem modalem Dialog klickbar. Root Cause: win32/gtk disablen das
     Eltern-Fenster Toolkit-seitig (`EnableWindow`/`gtk_widget_set_sensitive`) beim
     Öffnen eines modalen Dialogs, unser `wx/qt/dialog.rkt` tut das nicht; zusätzlich
     sind native Klick-Callbacks ohnehin nicht an `other-modal?` angebunden. Direkte
     Eingabe für den geplanten file-selector-Prompt.
- **Session-Infrastruktur-Zwischenfall (kein Code-Bug):** RDP-Sitzung des Nutzers
  (MacBook-Client, trennt bei Sleep) hing die Shell zunächst in eine getrennte Windows-
  Session — Screenshots/Fenster für den Nutzer unsichtbar. Nach Trennen der RDP-Verbindung
  lief die Shell in der aktiven Konsolen-Session weiter, Screenshots funktionierten.
  Automatisiertes synthetisches Klicken erreichte den Zielbutton trotz mehrerer Ansätze
  (`SendInput`/`mouse_event`/`PostMessage`) nicht zuverlässig — Nutzer hat stattdessen
  direkt interagiert und den Dialog bestätigt.
- **Commits:** gui-Submodul (neue `wx/qt/check-box.rkt`/`list-box.rkt` + Shim-Bindings +
  `platform.rkt`), gepusht; Umbrella-Zeiger-Bump + `qt-shim/src/shim.cpp` +
  `examples/dialog-widgets-probe.rkt` + `docs/HACKING.md` §18 + `CLAUDE.md`-Checkpoint +
  dieser Eintrag + Report.
- **Cross-Platform-Validierung bewusst NICHT Teil dieser Session** (macOS/Linux ziehen
  später, eigener Re-Smoke + Report).
- **Nächster Schritt:** Panel-Sizing-Fix (§18.2) und Modalitäts-Fix (§18.3) sind jeweils
  eigene Sessions; danach file-selector (Modalitäts-Fix als Voraussetzung) bzw.
  Preferences-Dialog (Panel-Sizing-Fix hilft dort ebenfalls).

---

## Session 2026-07-10 (macOS) — Redraw-Bug validiert, grün; E-0 vollständig geschlossen (2026-07-10_prompt Phase 5/6)

**Kontext:** `docs/2026-07-10_prompt.md` Phase 5/6. Voller Bericht:
`docs/2026-07-10_report-macos.md`.

- **Sync — grün.** ff-Pull `qt-backend` `87ebd078`→`04935cb6` (nach Rückfrage). Diff
  geprüft: identisch zu Windows/Linux (nur `canvas.rkt`, kein `shim.cpp`). Shim bereits
  aktuell, Bytecode neu (stale `compiled/` entfernt, `raco make`). Re-Smoke 3/3 grün.
- **Theme-Check zunächst fehlerhaft, dann selbst korrigiert.** Legacy-Key
  `framework:color-scheme` zeigte scheinbar Dark Mode; der tatsächlich maßgebliche Pref
  `framework:white-on-black-mode?` stand die ganze Zeit auf `#f` (Light, explizit gesetzt,
  nicht `'platform`). Lektion in `docs/HACKING.md` §16 festgehalten. Erklärt plausibel auch,
  warum der 07-09-Editor-Garble-Befund jetzt nicht mehr reproduzierbar ist.
- **Repro — grün.** `System Events click at` bewegte den Fokus nicht in den Qt-Canvas;
  eigener CoreGraphics-Klick-Helfer gebaut (analog zum Linux-XTest-Helfer). Danach: alle
  sieben Zeilen (`#lang racket/base` + 6× `define`) bleiben sichtbar, Debug-Log zeigt
  `begin-/end-refresh-sequence -> suspend-/resume-flush` aktiv feuernd. Resize +
  Occlusion-Zyklus zusätzlich verifiziert, beides grün. Re-Smoke danach 3/3 grün.
- **macOS-Nebenbefunde erneut geprüft:** Editor-Garble (07-09) reproduziert sich unter
  bestätigtem Light Mode nicht mehr. Menüleisten-Befund (8 statt 9, „Windows" fehlt)
  besteht weiterhin unverändert — offener Punkt, eigene Diagnose-Session.
- **Commits:** keine — reine Validierung. `docs/HACKING.md` §16 (macOS-Validierung,
  Redraw auf allen drei Plattformen geschlossen), `CLAUDE.md`-Checkpoint-Update,
  `docs/2026-07-10_report-macos.md`, dieser Eintrag.
- **Redraw-Bug damit auf allen drei Plattformen geschlossen. E-0 vollständig.** Nächster
  Meilenstein: Checkpoint E (Widget-Breite).

---

## Session 2026-07-10 (Linux) — Redraw-Bug validiert, grün (2026-07-10_prompt Phase 4)

**Kontext:** `docs/2026-07-10_prompt.md` Phase 4. Voller Bericht:
`docs/2026-07-10_report-linux.md`.

- **Sync — grün.** Umbrella `main` war bereits aktuell (`96cabe5`, Zeiger auf
  gui@`04935cb6`); gui-Submodul stand 1 Commit zurück (`87ebd078`) — nach Rückfrage
  sauberer ff-Pull auf `04935cb6`. Diff geprüft: exakt die vier im Windows-Report
  beschriebenen Änderungen in `canvas.rkt`, kein `shim.cpp`-Anteil → Shim war bereits
  aktuell, nur Bytecode neu gebaut. Re-Smoke 3/3 grün. Light Mode bestätigt
  (`racket-prefs.rktd`).
- **Repro — grün.** Da `xdotool` fehlt: kleiner XTest-Helfer selbst gebaut (Scratch,
  gegen `libX11`/`libXtst.so.6`) für echte synthetische Keystrokes. 6× `(define line-N N)`
  in echtem `PLT_QT=1`-DrRacket: alle sechs Zeilen bleiben sichtbar (Screenshot via `xwd` +
  Eigenbau-Parser), Debug-Log zeigt `begin-/end-refresh-sequence -> suspend-/resume-flush`
  aktiv feuernd statt der alten No-op-Meldungen. Identisch zum Windows-Nachher-Ergebnis.
- **Resize/Minimieren-Zusatzsicht: NICHT validiert, Ursache ungeklärt (offene
  Beobachtung, kein geschlossenes Nicht-Problem).** Roher `XResizeWindow`-Aufruf löste
  nachweislich keinen `set-size`/`shim_widget_set_geometry` im Debug-Log aus, aber die
  „reines Test-Artefakt"-Erklärung ist nicht schlüssig (KWin läuft als EWMH-WM;
  Fenster-Attribute passen nicht zu „Server dupliziert Inhalt"). Fließt als offener Punkt
  in die macOS-Resize-Prüfung ein. Blockiert das Ergebnis der eigentlichen
  Tipp-Repro-Validierung nicht.
- **Commits:** keine — reine Validierung. `docs/HACKING.md` §16 ergänzt (Linux grün),
  dieser Eintrag, `docs/2026-07-10_report-linux.md`.
- **Nächster Schritt:** macOS-Validierung (`docs/2026-07-10_prompt.md` Phase 5/6), danach
  Redraw-Zeile in `CLAUDE.md` als vollständig geschlossen markieren.

---

## Session 2026-07-10 (Windows) — Redraw-Bug gefixt + visuell bestätigt (2026-07-10_prompt)

**Kontext:** `docs/2026-07-10_prompt.md`. Voller Bericht: `docs/2026-07-10_report-win.md`.

- **Phase 0 — grün.** Beide Repos sauber, Submodul-Zeiger deckungsgleich mit
  `origin/qt-backend` (`87ebd078`). `racket --version` = v9.2 [cs]. Shim aktuell (DLL neuer
  als `shim.cpp`). Theme explizit `classic` (Light, nicht OS-gesteuert). Smoke 3/3 grün.
- **Phase 1 — Vorher-Baseline gemessen.** Identischer Repro aus `docs/2026-07-09_report-
  win.md` (6× `(define line-N N)` real getippt): nur letzte Zeile sichtbar, Rest weiß.
  Bestätigt per Screenshot + Debug-Log (`begin-/end-refresh-sequence (no-op)` feuert
  tatsächlich während des Repros).
- **Phase 2 — Fix, vier Änderungen statt zwei.** Der vorgeschriebene 2-Schritt-Fix
  (`start-backing-retained` + `suspend-/resume-flush`) hätte den Clean-Start kaputt gemacht
  (leerer Editor statt `#lang racket`). Zusätzlich nötig: `reset-backing-retained` bei
  `set-size` (Resize-Hook, wie win32/gtk über `on-resized`/`internal-on-client-size`) und
  eine Konstruktor-Reihenfolge-Korrektur (`dc` vor dem Seed-`set-size`-Aufruf definieren,
  sonst Start-Crash). Details `docs/HACKING.md` §16.
- **Phase 3 — Nachher-Messung, visuell vom Nutzer bestätigt.** Alle 6 Zeilen bleiben
  sichtbar; zusätzlich verifiziert: Resize, Minimieren/Wiederherstellen. `bm=`-Größe in den
  Flush-Logs wächst jetzt mit dem Inhalt statt auf eine Platzhaltergröße zurückzufallen.
  Smoke 3/3 grün.
- **Nebenbefund (nicht verfolgt, vorbestehend):** Toolbar-Save-Icon erscheint abhängig vom
  Zeitpunkt des letzten vollen Repaint-Zyklus — betrifft `wx/qt/button.rkt`, nicht
  `canvas%`/`backing-dc%`.
- **Commits:** Submodul (`qt-backend` `87ebd078`→`04935cb6`, gepusht), Umbrella-Zeiger-Bump
  + Doku (`HACKING.md` §16, `CLAUDE.md`-Checkpoint, dieser Eintrag, Report).
- **Nächster Schritt:** Linux (Validierung) → macOS (Validierung + macOS-Nebenbefunde),
  siehe `docs/2026-07-10_prompt.md` Phase 4/5. Validierungs-Sessions müssen gegen den
  tatsächlichen Vier-Änderungen-Diff prüfen, nicht nur gegen die ursprüngliche
  2-Schritt-Beschreibung aus der Kandidaten-Analyse vom 07-09.

---

## Session 2026-07-09 (macOS) — Clean-Start-Check, NICHT sauber, zwei Befunde (2026-07-09_prompt)

**Kontext:** `docs/2026-07-09_prompt.md`. Voller Bericht: `docs/2026-07-09_report-macos.md`.

- **Phase 0 — Sync + Rebuild, grün.** gui-Submodul stand auf `ba2dacc9`, 3 Commits hinter
  `origin/qt-backend` (`87ebd078`, vom Umbrella schon referenziert). Vor dem Pull ausführlich
  geprüft (Nutzer-Sorge wegen früherer Fast-Forward-Beschädigung): einziger Remote, HEAD ist
  strikter Vorfahre, keine lokalen Extra-Commits, Working Tree clean — sauberer Fast-Forward
  nach Nutzer-Bestätigung. Umbrella-Zeiger zeigte bereits auf `87ebd078`, kein Pointer-Commit
  nötig. Shim neu gebaut (Ninja), Bytecode neu (`-S`-Override, stale `compiled/`-Dirs vorher
  entfernt), Re-Smoke 3/3 grün.
- **Phase 1 — Clean-Start-Check: NICHT sauber, zwei unabhängige Befunde (kein Crash, kein
  Missing-Method — Guardrail: STOPP+Bericht, kein Fix versucht):**
  1. **Menüleiste: 8 statt 9 Menüs** — `Windows`-Menü fehlt, verifiziert per `osascript` direkt
     gegen die native `NSMenu`-Struktur (Daten-Befund, kein Rendering-Artefakt). Abweichung von
     der eigenen Baseline `docs/2026-07-08_report-4-macos.md` (9 Menüs inkl. `Windows` bei
     `ba2dacc9`). Code-Diff `ba2dacc9..87ebd078` berührt Menüleisten-/Frame-Aufbau nicht — Ursache
     unklar, nicht weiter diagnostiziert.
  2. **Editor-Bereich beim allerersten Paint bereits verzerrt** (vor jeder Eingabe): schwarze
     Hervorhebungsbalken, überlappender Text am unteren Fensterrand — pixelidentisch über 2
     unabhängige Screenshots (kein Timing-Artefakt). Diagnose-Hooks aus dem Pull sind strikt
     `PLT_QT_DEBUG`-gated (verifiziert per Code-Diff) und damit nicht die Ursache. Plausibel
     dieselbe Bug-Familie wie der dokumentierte Windows-Redraw-Bug (`HACKING.md §16`), aber
     nicht deckungsgleich (dort erst nach mehreren Zeilen, hier schon beim ersten Paint) —
     Vermutung, keine Messung.
- **Commits:** keine — reiner Fast-Forward-Pull, keine Landmine gezündet, kein Fix-Commit.
- **Nächster Schritt:** beide Befunde in die geplante Redraw-Fix-Session einbringen; Menü-
  Diskrepanz separat klären.

---

## Session 2026-07-09 (Linux) — Clean-Start-Check (2026-07-09_prompt)

**Kontext:** `docs/2026-07-09_prompt.md`. Voller Bericht: `docs/2026-07-09_report-linux.md`.

- **Phase 0 — Stand nachgezogen.** `racket --version` = v9.2 [cs] (gemessen). gui-Submodul
  stand auf `6df80516` (2 Commits hinter dem vom Umbrella schon referenzierten `87ebd078`) —
  nach Rückfrage (`AskUserQuestion`, CLAUDE.md Regel 7) `git submodule update` +
  `git pull --ff-only` auf `qt-backend` ausgeführt, jetzt deckungsgleich. Shim war gegenüber
  `shim.cpp` (Windows-Diagnose-Hooks) veraltet → neu gebaut (Ninja). Bytecode neu über
  `racket -S ... -l raco -- make -l mred` (kein Installation-Link auf dieser Maschine, `raco
  make` selbst hat keinen `-S`-Schalter). Re-Smoke 3/3 grün.
- **Phase 1 — Clean-Start-Check: sauber beim ersten Start.** Echtes `PLT_QT=1 racket -S ... -l
  drracket`: 9 Menüs (File/Edit/View/Language/Racket/Insert/Scripts/Tabs/Help), Editor +
  REPL-Prompt sichtbar, kein Crash — keine neue Landmine gezündet. Screenshot (`xwd` +
  Eigenbau-XWD→PNG-Parser) bestätigt.
- **Phase 2 (Redraw-Messung):** laut Prompt Windows-exklusiv, hier nicht wiederholt.
- **Commits:** keine — reiner Sync/Rebuild/Verify-Schritt, keine Landmine gezündet, also kein
  Stub-Fix nötig.
- **Nächster Schritt:** macOS-Zweig dieses Prompts (Phase 0/1) steht noch aus. Redraw-Bug-FIX
  bleibt eigene Session (Basis: `docs/2026-07-09_report-win.md`).

---

## Session 2026-07-09 (Windows) — Clean-Start-Check + Redraw-Bug gemessen (2026-07-09_prompt)

**Kontext:** `docs/2026-07-09_prompt.md`. Voller Bericht: `docs/2026-07-09_report-win.md`.

- **Phase 0 — Stand verifiziert.** `racket --version` = v9.2 [cs] (gemessen). gui-Submodul war
  bereits auf `qt-backend` `b2369d48` (enthält alle vier Fixes: addAction, mapToGlobal,
  set-label, set-icon, plus einen Kommentar-Fix aus der Vorsession) — kein Pull nötig. Shim war
  gegenüber `shim.cpp` veraltet (Kommentar-Fix von heute) → neu gebaut. `raco setup mred
  framework` neu kompiliert (Windows: Installation-wide-Link). Re-Smoke 3/3 grün.
- **Phase 1 — Clean-Start-Check: sauber beim ersten Start.** Echtes `PLT_QT=1 DrRacket.exe`:
  9 Menüs (File/Edit/View/Language/Racket/Insert/Scripts/Tabs/Help), Editor sichtbar, kein
  Crash, keine neue Landmine gezündet — Screenshot bestätigt.
- **Phase 2 — Redraw-Bug gemessen, NICHT gefixt (Guardrail).** Vier gated Diskriminatoren
  hinter `PLT_QT_DEBUG` in `shim.cpp` (`paintEvent`, `shim_canvas_blit_argb`) und
  `wx/qt/canvas.rkt` (`refresh`, `flush`, `begin-`/`end-refresh-sequence`,
  `queue-backing-flush`) eingebaut (additiv, bleiben im Code). Ergebnis: Blit deckt immer die
  volle Widget-Fläche ab (A widerlegt), Backing-Bitmap bleibt immer volle Größe (B als
  „falsche Größe" widerlegt), jeder Editor-Repaint läuft über den vollen
  `refresh→blit_argb`-Pfad statt isoliertem `request_repaint` (C widerlegt), Minimieren+
  Wiederherstellen ändert nichts am Symptom (spricht gegen reine Trigger-Frage). Root-Cause-
  Kandidat per Code-Vergleich mit win32/gtk/cocoa gefunden: `begin-refresh-sequence`/
  `end-refresh-sequence` sind im Qt-Backend No-ops, `start-backing-retained` wird nie
  aufgerufen — dadurch verwirft `backing-dc%` die Backing-Bitmap nach jedem Flush statt sie
  über Teil-Invalidierungen hinweg zu behalten. Details/Messwerte: `docs/HACKING.md` §16.
- **Commits:** gui-Submodul (`qt-backend`) — Kommentar-Update (Session-Label-Rename) bereits
  vor dieser Session gepusht; diese Session fügt die gated Diagnose-Hooks in `canvas.rkt`
  hinzu (eigener Commit). Umbrella (`main`) — `shim.cpp`-Diagnose-Hooks, `docs/HACKING.md` §16,
  `CLAUDE.md`-Checkpoint-Tabelle, dieser STATUS-Eintrag, `docs/2026-07-09_report-win.md`.
- **Nächster Schritt:** Redraw-Bug-FIX (eigene Session) auf Basis des hier gemessenen
  Mechanismus — dann Checkpoint E.

---

## Session 2026-07-08 (5, Linux) — Menü-Fixes cross-platform-validiert + set-icon-Crash gefixt (2026-07-08_prompt-4)

**Kontext:** `docs/2026-07-08_prompt-4.md`. Voller Bericht: `docs/2026-07-08_report-4-linux.md`.

- **Racket-Version (gemessen, Phase 0):** v9.2 [cs] x86_64. gui-Submodul stand vor Sync auf
  `381425d5` (stale-Shim-Falle wie vorhergesagt) — auf `ba2dacc9` nachgezogen (enthält bereits
  addAction-, mapToGlobal- **und** den macOS-`set-label`-Fix), Shim neu gebaut, Smoke 3/3 grün.
- **Ladecheck:** Linux nutzt für `gui-lib` ebenfalls **keinen** Installation-Link — `-S`-Source-
  Override zwingend, sonst stiller Fallback auf gtk. Verifiziert über `PLT_QT_DEBUG=1`.
- **addAction-Fix: grün.** Probe (`mixed`/`dynamic`) exakt wie erwartet. Zusätzlich per
  Scratch-Skript (`visual-probe.rkt`, nicht im Repo) visuell als Screenshot belegt: Blatt-Item +
  Submenü + Separator + Blatt-Item alle korrekt sichtbar. Echtes DrRacket: synthetischer
  Linksklick (via `libXtst`) auf „File" öffnet Dropdown mit 25 korrekt strukturierten Aktionen
  (Debug-Dump + `xwininfo`-Geometrie bestätigt) — Screenshot selbst zeigte das Popup nicht
  (Capture-Artefakt, siehe unten), Datennachweis ist aber eindeutig.
- **mapToGlobal-Fix: grün.** Echter synthetischer Rechtsklick (via `libXtst`) im Definitions-
  Editor öffnet Kontextmenü bei (1340,808) — 1px Differenz zum Klickpunkt (1339,807), statt am
  Fensterursprung. Inhalt (Undo/Redo/Copy/Cut/Paste/Clear/Select All/Suchen) korrekt.
- **Neuer, unabhängiger Crash gefunden + auf Nutzer-Anweisung gefixt:** `set-icon`-Methode fehlt
  komplett in `wx/qt/frame.rkt` (win32/gtk/cocoa haben sie alle) — `framework/splash.rkt` ruft
  sie bei jedem Start auf, Splash-Fenster blieb dadurch unmapped, Hauptfenster erschien nie.
  Fix: variadic No-op-Stub, gespiegelt an `set-label`/`append` im selben Backend. Nutzer hat via
  `AskUserQuestion` explizit „Ja, fixen" gewählt. Nach Fix: DrRacket startet vollständig, alle 9
  Menüs sichtbar, Smoke 3/3 weiterhin grün. Commit: gui `6df80516` (lokaler `qt-backend`-Branch
  fast-forwarded nach detached-HEAD-Checkout) — **noch nicht gepusht**, Nutzer-OK ausstehend.
- **Nebenklärung (kein Bug):** Popups, die im Screenshot-Bereich des Session-Terminals liegen,
  erschienen im `xwd`-Vollbild-Capture nicht sichtbar, obwohl per Debug-Dump/`xwininfo` korrekt
  existent und positioniert — Capture-/Compositing-Artefakt dieser Session-Umgebung, **nicht**
  der bekannte Redraw-Bug (der betrifft Editor-Repaint, nicht Popup-Sichtbarkeit im Tool). Ein
  isoliertes Scratch-Popup außerhalb dieses Bereichs rendert im selben Verfahren sichtbar korrekt.
- **Guardrail-Abweichung, vom Nutzer autorisiert:** wie bei macOS — Original-Prompt sah reine
  Validierung ohne Fix-Commits vor; Crash gemeldet, Nutzer-Entscheidung eingeholt, dann gefixt.
- **Beide Plattformen (macOS + Linux) jetzt grün — `CLAUDE.md`-Checkpoint E-0-Menü als
  vollständig geschlossen markiert.** Offen: Push von `6df80516`/Umbrella-Commit; Windows sollte
  vor Re-Sync über den vierten Fix informiert werden; Redraw-Bug weiterhin separat offen.

---

## Session 2026-07-08 (4, macOS) — Menü-Fixes cross-platform-validiert + neuer DrRacket-Crash gefixt (2026-07-08_prompt-4)

**Kontext:** `docs/2026-07-08_prompt-4.md`. Voller Bericht: `docs/2026-07-08_report-4-macos.md`.

- **Racket-Version (gemessen, Phase 0):** v9.2 [cs], arm64. gui-Submodul stand vor Sync 4
  Commits hinter `origin/qt-backend` (stale-Shim-Falle wie vorhergesagt) — auf `1641f888`
  nachgezogen, Shim neu gebaut, Smoke 3/3 grün.
- **Ladecheck wichtig:** macOS nutzt für `gui-lib` **keinen** Installation-Link (Katalog-Paket
  bleibt Upstream 1.80) — DrRacket/Racket-Aufrufe brauchen zwingend den `-S`-Source-Override,
  sonst stiller Fallback auf cocoa (falsches Grün). Verifiziert über `PLT_QT_DEBUG=1`.
- **addAction-Fix: grün.** Probe (`mixed`/`dynamic`) exakt wie erwartet; echtes DrRacket zeigt
  File-Menü vollständig gefüllt (alle Blatt-Items + 2 Submenüs, Screenshot in der Session).
- **mapToGlobal-Fix: grün.** Isolierter `client-to-screen`-Datentest (Advisor-Empfehlung, umgeht
  Popup/Event-Delivery): Basispunkt ist am Fenster verankert (nicht `(0,0)` wie beim alten
  No-op), Translation exakt 1:1. Echtes DrRacket: Rechtsklick-Kontextmenü öffnet am Klickpunkt.
- **Neuer, unabhängiger Crash gefunden + auf Nutzer-Anweisung gefixt:** `set-label`-Arity-
  Mismatch in der qt-`tab-panel%`-Stub (`wx/qt/platform.rkt:25`) — DrRacket ruft beim Start
  `set-label` mit 2 Argumenten (Index+Label), Stub akzeptierte nur 1 (Button-Stil). Ursache:
  qt-Backend meldet `tab-panel-available? => #t`, hat aber (anders als gtk/win32) keine
  dedizierte `tab-panel.rkt` mit echtem 2-Arg-`set-label`. Fix: `set-label` variadic gemacht,
  gespiegelt an `append`s bestehender Rest-Arg-Behandlung in derselben Stub-Factory — sicher,
  da nur No-op-Stub-Klassen betroffen. Nach Fix: DrRacket startet vollständig, alle 9 Menüs
  sichtbar, Smoke 3/3 weiterhin grün. Commits: gui `ba2dacc9`, Umbrella `ea92deb` — **noch
  nicht gepusht**, Nutzer-OK ausstehend.
- **Nebenklärung (kein Bug):** Der Nutzer beobachtete beim `menu-click-probe.rkt`-Lauf ein
  Dropdown, das weit außerhalb des kleinen Probe-Fensters aufging — das ist beabsichtigt
  (`shim_menu_popup` nutzt globale Bildschirmkoordinaten `(100,100)`, unabhängig von der
  Fensterposition), kein mapToGlobal-Bug, keine Aktion nötig.
- **Nebenklärung (kein Bug):** ein nacktes `text%`/`editor-canvas%` (ohne DrRacket-Editor-
  Subklassen) zeigte bei Rechtsklick gar kein Kontextmenü — Symptom passt nicht zu einem
  kaputten mapToGlobal (das würde falsch platzieren, nicht verschwinden lassen); vermutlich
  fehlendes Default-Popup-Menü auf nacktem `text%`, nicht weiter diagnostiziert (out of scope).
- **Guardrail-Abweichung, vom Nutzer autorisiert:** Original-Prompt sah reine Validierung ohne
  Fix-Commits vor; der DrRacket-Crash wurde gemeldet, gestoppt, und auf explizite Anweisung
  des Nutzers gefixt (Scope-Erweiterung, kein eigenmächtiges Abweichen).
- **Offen:** Push von `ba2dacc9`/`ea92deb` ausstehend; **Linux-Validierung steht noch aus** —
  `CLAUDE.md`-Checkpoint E-0-Menü erst nach grünem Linux schließen (inkl. des neuen
  `set-label`-Fixes, den Linux mitzieht). Windows sollte vor Re-Sync über den dritten Fix
  informiert werden. Redraw-Bug weiterhin separat offen, unverändert beobachtet.

---

## Session 2026-07-08 (3) — Menüs voll funktional: addAction-Fix + mapToGlobal-Fix (2026-07-08_prompt-3)

**Kontext:** `docs/2026-07-08_prompt-3.md`. Voller Bericht: `docs/2026-07-08_report-3.md`.

- **Racket-Version (gemessen, Phase 0):** v9.2 [cs].
- **Phase 1 — addAction-Fix (gefixt, gemessen, gepusht).** Root-Cause-Kandidat aus
  Session (2) bestätigt: `shim_action_create` fügte die `QAction` nie per `addAction()` zu
  ihrem `QMenu` hinzu. Fix, gespiegelt am Submenü-Pfad: Signatur um `menu`-Parameter
  erweitert, Action per Konstruktor an ihr Menü geparentet (Ownership — `addAction`
  übernimmt laut Qt-Doku kein Ownership, ohne Parent wäre die Action ein Leak), explizit
  `menu->addAction(a)`. Verifiziert per Probe (`direct`/`mixed`/neuem `dynamic`-Modus:
  Separatoren, Checkable, Enable/Delete-Dispatch — alles korrekt) und echtem DrRacket
  (File-/Edit-Menü vollständig gefüllt, Screenshots in der Session). Smoke 3/3 grün, kein
  Ownership-Crash/-Warning. Commits: gui `0be24d85`, Umbrella `71b7347`.
- **Checkpoint A — GO (autonom).** Alle Kriterien grün, keine Anomalie → Session lief laut
  Prompt-Vorgabe selbständig zu Phase 2 weiter.
- **Phase 2 — mapToGlobal-Fix (gefixt, gemessen, gepusht).** Neue Shim-Funktion
  `shim_widget_client_to_screen` (`QWidget::mapToGlobal`), verdrahtet in `wx/qt/window.rkt`s
  `client-to-screen` (war No-op). Verifiziert: Rechtsklick-Kontextmenü in echtem DrRacket
  öffnet jetzt am Klickpunkt statt am Fensterrand. `screen-to-client` bleibt No-op
  (ungenutzt in diesem Backend). Commits: gui `1641f888`, Umbrella `8e0bfac`.
- **Qt-Skills konsultiert** vor dem Schreiben von Shim-Code: `QWidget::addAction`/
  `QMenu::addMenu` Ownership-Semantik, `QWidget::mapToGlobal` für Multi-Screen/DPR.
- **Checkpoint B (STOPP, hier erreicht):** Nutzer-Bestätigung beider Visuals ausstehend.
  Danach Phase 3/4 (macOS/Linux: ff-Pull, Shim neu bauen — stale-Shim-Falle 07-07 —,
  re-smoke, cross-platform validieren), erst dann `CLAUDE.md`-Checkpoint E-0-Menü
  schließen. Redraw-Bug weiterhin separat offen.
- Doku: `docs/HACKING.md` §15 (neue Lektion, beide Fixes).

---

## Session 2026-07-08 (2) — Klick-Bug gemessen: korrigierte Diagnose (2026-07-08_prompt-2)

**Kontext:** `docs/2026-07-08_prompt-2.md`.

- **Racket-Version (gemessen, Phase 0):** v9.2 [cs] — `CLAUDE.md` hatte hier noch v8.18
  stehen (Versionsdrift aus einer älteren Session), jetzt korrigiert.
- **W1 — Push (Gewinn gesichert).** gui-Submodul `qt-backend`: `381425d5..6083efc9` (ff).
  Umbrella `main`: `25eb6f2..17af2ad` (ff, enthält `2c102e5` + `17af2ad`). Beide waren zuvor
  nur lokal committet.
- **W2 — Phase 3 (DrRacket-Gegencheck).** `PLT_QT=1 DrRacket.exe` gestartet, Screenshot
  bestätigt: Menüleiste horizontal (File/Edit/View/Language/Racket/Insert/Scripts/Tabs/Help),
  nicht mehr gestapelt. Titel-Fix wirkt im vollen Widget-Baum, nicht nur im Minimal-Repro.
- **W3 — Klick-Bug gemessen, NICHT gefixt (Guardrail).** Die Hypothese aus
  `2026-07-08_report.md` („Klick öffnet nie ein Dropdown, Event-Loop-Familie mit Redraw-Bug")
  wurde durch eine Nutzerbeobachtung an echtem DrRacket **korrigiert**: Dropdowns erscheinen
  für Menüs mit Submenü-Kindern (z. B. File→„Open Recent", Edit→„Key Bindings"), aber nur die
  Submenü-Einträge sind sichtbar — reine Blatt-Items fehlen. Komplett blattlose Menüs (wie
  der ursprüngliche Minimal-Repro `menu-frame.rkt`: File→Quit) zeigen deshalb gar keinen
  Dropdown — das erklärt rückwirkend das „kein einziges popup APPEARED" aus `2026-07-08_report.md`.
  **Root-Cause-Kandidat verifiziert** (Code-Lektüre + gezielte Probe, kein Fix): `shim_action_create`
  (`qt-shim/src/shim.cpp`) erzeugt eine `QAction`, hängt sie aber nie per `addAction`/
  `insertAction` an ihr `QMenu` — nur `shim_menu_add_submenu`s `addMenu()` tut das
  (`grep addAction qt-shim/src/shim.cpp` → 0 Treffer). Verifiziert mit neuem, gated
  Probe-Skript `examples/menu-click-probe.rkt` (Modus `mixed`): direkter `popup()` auf ein
  Blatt-only-Menü → kein `popup APPEARED`; auf ein Menü mit Blatt+Submenü → `popup APPEARED
  ... frameGeom=(100,100 107x30)` (genau 1 Zeile Höhe = nur das Submenü). Details:
  `docs/HACKING.md` §14.
  - Nebenbefund: `QApplication::activeWindow()` ist `NULL` direkt nach `show()` bei einem
    CLI-gestarteten Racket-Prozess. Direkte `popup()`-Aufrufe auf nicht-leere Menüs zeigten
    kurz `popup APPEARED` gefolgt von sofortigem `popup GONE` ohne Nutzerinteraktion — evtl.
    mit dem Fokus-Befund zusammenhängend, nicht isoliert bestätigt.
  - F10/Alt+F via SendKeys zeigte keine Wirkung — **konfundiert** mit `activeWindow=NULL`
    (SendKeys/`AppActivate` könnten das Fenster nie erreicht haben). Ergebnis **inkonklusiv**,
    nicht als „Tastatur-Aktivierung funktioniert nicht" zu werten.
- **W4 — Doku:** `docs/HACKING.md` §14 (korrigierte Menü-Lektion), `CLAUDE.md`-Checkpoint-
  Tabelle aktualisiert, dieser Eintrag + Nachtrag der vorherigen 07-08(1)-Session unten.
- **Neue Datei:** `examples/menu-click-probe.rkt`. Gated Mess-Hooks (alle hinter
  `PLT_QT_DEBUG`, nirgends ungegated): `debug-get-appended-menu` in `wx/qt/menu-bar.rkt`
  (liefert das wx-Level-`menu%`-Handle des in der Bar eingebetteten QMenu für Direkt-
  `popup()`-Tests) + `activeWindow`-Print in `qt-shim/src/shim.cpp`.
- **Klick-Bug-FIX bleibt out of scope** (Spur 2, nächste Session, braucht Cross-Platform-
  Daten + Review — Guardrail dieser Session).

---

## Session 2026-07-08 (1) — Menüleiste sichtbar: Titel-Fix (2026-07-08_prompt)

**Kontext:** `docs/2026-07-08_prompt.md`, Ergebnis: `docs/2026-07-08_report.md`. (Nachträglich in
STATUS.md aufgenommen — dieser Eintrag fehlte bisher.)

- **Root Cause gefunden:** `menu-bar% append` (`wx/qt/menu-bar.rkt`) bekam den Menütitel,
  reichte ihn aber nie an den zugrundeliegenden `QMenu` durch. `QMenuBar::addMenu(QMenu*)`
  leitet den Balken-Item-Text aus dem Menütitel ab → leerer Titel = 0×0-Action-Rect =
  Balkenhöhe 0 auf allen drei Plattformen. Widerlegt die ursprüngliche deferred-Layout-
  Hypothese vollständig (kein Layout-Trigger ändert je etwas an einem leeren Titel).
- **Fix:** `shim_menu_set_title` (neu, `shim.cpp` + `utils.rkt`), aufgerufen in
  `menu-bar%.append` vor `shim_menubar_add_menu`. Kein Layout-Eingriff.
- **Nutzerbestätigt:** Menüleiste sichtbar, File/Edit/Help horizontal an korrekten
  x-Positionen (0/52/107).
- **Neues Problem entdeckt (Klick öffnet keinen Dropdown)** — gemessen in Session (2) oben,
  Diagnose dort korrigiert.
- **Commits:** gui-Submodul `6083efc9`, Umbrella `2c102e5` + `17af2ad`. War zum Zeitpunkt
  dieses Berichts nur lokal — in Session (2) oben gepusht.

---

## Session 2026-07-07 (3) — Windows Menü/Redraw-Diagnose (kein Re-Sync)

**Kontext:** `docs/2026-07-07_prompt.md`, Ergebnis: `docs/2026-07-07_report_win.md`.

- **Kein Re-Sync nötig** — der 1.78→1.80-Merge ist auf Windows entstanden und gepusht.
  Umbrella `main` sauber/aktuell, gui-Submodul `qt-backend` @ `381425d5`, `info.rkt` = **1.80**.
  Konsum via **Installation-wide Link** (nicht `-S`-Override wie macOS/Linux). Keine neuen
  Sync-Commits.
- **Menü-Beobachtung:** `menu-frame.rkt` reproduziert den **fehlenden Balken** (Höhe 0) als
  isolierten Minimal-Repro — deckt sich mit Linux. Echtes DrRacket zeigt zusätzlich
  **überlappende Menütitel** (gleiche x-Origin) + weißes Rechteck-Artefakt → zwei Fehlermodi,
  gemeinsame Ursache (Balken-Geometrie/Platzierung) wahrscheinlich, aber offen.
- **Redraw-Beobachtung:** mit **echten Keystrokes** (SendKeys, nur auf Windows möglich)
  reproduziert — nach Tippen mehrerer Zeilen rendert **nur die aktuelle Zeile** (mittig,
  weißes Band nur um sie), frühere Zeilen verschwinden. Verschärft den macOS/Linux-Befund und
  stützt einen Bug im gemeinsamen `editor-canvas%`/`text%`-Redraw-Pfad (fehlender
  Backing-Store-Persist).
- **Damit liegen alle drei Plattform-Beobachtungen vor** — Eingabe für den Rendering-Fix-Prompt.
- **Commit:** nur `docs/2026-07-07_report_win.md` + dieser STATUS-Eintrag (Screenshots out-of-band,
  nicht im Repo).

---

## Session 2026-07-07 — macOS auf 1.80 re-synced + Menü/Redraw-Diagnose

**Kontext:** `docs/2026-07-07_prompt.md`, Ergebnis: `docs/2026-07-07_report_macos.md`.

- **macOS auf 1.80 re-synced, Smoke 3/3.** gui-Submodul FF-Pull 1.78→**1.80**
  (`381425d5`), stale `compiled/`-Caches gelöscht, Shim + Fork (`raco make`) neu
  gebaut. Reiner Pull, keine Sync-Commits. gui-lib wird hier via **`-S`-Source-Override**
  konsumiert (nicht verlinkt) — daher `raco make` statt `raco setup`.
- **Menü-Beobachtung:** globale macOS-Leiste zeigt nur `{Apple, racket}`, kein
  `File`/`Edit`. Diskriminierender Test mit **Non-Role**-Items **widerlegt** Qt-
  QuitRole-Merging als Ursache; Shim erstellt echten `QMenuBar` + `setMenuBar`, aber
  die native **QMenuBar→NSMenu-Anbindung greift nicht** → Fix voraussichtlich
  macOS-spezifisch (nicht Geometrie, nicht QuitRole).
- **Redraw-Beobachtung:** Total-Blank nur **transient** (erholt sich nach Ruhe),
  Live-Tippen rendert stabil; stabil verloren nur der vor-Interaktion per `insert`
  gesetzte Text + vertikaler Versatz → milderes, eigenständiges Thema.
- **Commit:** Umbrella `main` `25a13cb` (nur `docs/2026-07-07_report_macos.md`), gepusht.

---

## Session 2026-07-07 (2) — Linux auf 1.80 re-synced + Menü/Redraw-Diagnose

**Kontext:** `docs/2026-07-07_prompt.md`, Ergebnis: `docs/2026-07-07_report_linux.md`.

- **Linux auf 1.80 re-synced, Smoke 3/3.** gui-Submodul stand detached auf altem
  `6169a245` ohne lokalen `qt-backend`-Branch → `checkout -b qt-backend --track
  origin/qt-backend`, sauberer FF `6169a245`→**1.80** (`381425d5`). 10 stale
  `compiled/`-Caches gelöscht, Shim (stale seit 29.6., Quelle vom 30.6.) neu gebaut,
  Fork (`raco make`) neu gebaut. Reiner Sync, keine neuen Commits. gui-lib auch hier via
  **`-S`-Source-Override** konsumiert.
- **Menü-Beobachtung:** Menüleiste fehlt **komplett** — weder im Fenster noch (anders als
  macOS) irgendwo global, da Plasma/KWin kein globales Menüband hat. `QT_QPA_PLATFORMTHEME=`-
  Kontrolltest macht Global-Menu-Redirect unwahrscheinlich → widerspricht der macOS-These
  „vermutlich plattformspezifisch"; spricht für **eine gemeinsame Ursache** (z. B. QMenuBar
  bekommt nie Höhe im QMainWindow-Layout).
- **Redraw-Beobachtung:** Vor-Interaktion per `insert` gesetzter Text verschwindet stabil +
  vertikaler Versatz — **identisches Muster wie auf macOS** → eher Bug im gemeinsamen
  `editor-canvas%`/`text%`-Pfad statt Plattform-Sonderfall. (Transientes Blank aus dem
  macOS-Bericht mangels Keystroke-Simulationswerkzeug hier nicht gezielt geprüft.)
- **Einschränkung:** kein `xdotool`/`ydotool`/`wtype`, kein passwortloses `sudo` → Klick-Test
  (Punkt 2) nicht automatisierbar, Tipp-Test nur via programmatischer `insert`-Simulation.
- **Damit sind alle drei Maschinen auf gui-lib 1.80 in Parität.**

---

## Session 2026-07-02 — gui-lib-Angleich 1.78→1.80 + echtes DrRacket

**Kontext:** `docs/2026-07-02_prompt.md`, Ergebnis: `docs/CHECKPOINT-E0-ledger.md`.

### Was passiert ist

1. Fork (`third_party/gui`, Branch `qt-backend`) war seit dem ursprünglichen Spike auf
   gui-lib **1.78**; das mit Racket 9.2 installierte System-`gui-lib` ist **1.80**. Das
   erzeugte einen Linklet-Mismatch, der DrRacket als Testharness verhinderte (Vorgänger-
   Session griff deshalb auf `examples/widget-probe.rkt` als Ersatz zurück).
2. Fork gemergt auf den exakten Upstream-Commit, aus dem das System-Paket gebaut wurde
   (`3f0037c0`, hash-verifiziert über `package-original-source`). 86 Dateien geändert,
   **0 Konflikte**, kein `wx/qt/**`-File betroffen.
3. `gui-lib` als Installation-scope-Link gesetzt (`raco pkg update --link
   third_party/gui/gui-lib`, braucht Admin-Rechte wegen `C:\Program Files\Racket`).
   **Gate-Test bestanden:** DrRacket startet nativ (ohne `PLT_QT`) ohne Linklet-Mismatch.
4. `PLT_QT=1 drracket` echt gestartet und durch die Crash-Reihe gearbeitet: 9 Crashes +
   2 grundlegende Key-/Focus-Bugs gefunden und gefixt. Ergebnis: Tippen, Enter/Zeilen-
   umbruch und Code-Ausführung funktionieren jetzt in Definitions- **und**
   Interactions-Editor. Details: `docs/CHECKPOINT-E0-ledger.md`.
5. **Offen (Flags für E-1):**
   - Menüleiste visuell nicht sichtbar — Daten/Wiring nachweislich korrekt (165 Menü-
     punkte real gebaut), Ursache ist ein Qt-Layout/Rendering-Problem, kein Racket-Bug.
   - Popup-Positionierung falsch (Kontextmenüs, Dropdowns) — `client-to-screen` ist
     No-op, fehlender Shim für Widget→Bildschirm-Koordinaten (`QWidget::mapToGlobal`).
   - Teilweises Neuzeichnen im Editor-/Interactions-Bereich — noch nicht root-caused.

### Commits

| Repo | Commit | Inhalt |
|---|---|---|
| gui-Submodul (`qt-backend`) | `2d6325d9` | Merge auf Upstream `3f0037c0` (1.78→1.80) |
| gui-Submodul (`qt-backend`) | `381425d5` | 9 Crash-Fixes + Key-Release-Kontrakt + Focus-Tracking + `popup-menu` |
| Umbrella (`main`) | `0b9f287` | Submodul-Zeiger auf `2d6325d9` |
| Umbrella (`main`) | `b902825` | Ledger-Update + Submodul-Zeiger auf `381425d5` |

**Push-Status:** `2d6325d9` / `0b9f287` sind auf `origin` gepusht (Gate-Test war grün).
`381425d5` (die Live-Fixes aus der DrRacket-Discovery) ist **nur lokal committet**,
noch nicht gepusht — offene Entscheidung, siehe Checkpoint-E-0-Bericht der Session.

### ⚠️ Pflicht-Folgeschritt: macOS + Linux

Der Merge in Schritt 2 rückt den **geteilten** `qt-backend`-Branch signifikant vor
(gui-lib-Kernversion geändert, nicht nur additive Dateien). Sobald `381425d5` gepusht
ist, MÜSSEN macOS und Linux (Claude Code läuft dort nicht automatisch mit):

```bash
git -C third_party/gui pull origin qt-backend
git pull origin main   # Umbrella-Zeiger nachziehen
git submodule update --init --recursive
raco setup             # auf BEIDEN Maschinen — gui-lib hat sich strukturell geändert
# dann re-smoken:
PLT_QT=1 QT_PLUGIN_PATH=<...>/plugins \
  racket -S third_party/gui/gui-lib -S third_party/draw/draw-lib -l raco -- test tests/smoke.rkt
```

Ohne `raco setup` auf beiden Maschinen bleiben sie auf altem Bytecode gegen die neue
gui-lib-Quelle stehen — potentiell subtile Inkonsistenzen statt eines klaren Fehlers.

**Status (2026-07-07):** `381425d5` ist auf `origin/qt-backend` gepusht. **macOS ✅ erledigt**
(re-synced auf 1.80, Smoke 3/3 — siehe Session-Eintrag oben; auf macOS läuft der Konsum
über `-S`-Source-Override, daher `raco make` statt `raco setup`). **Linux ✅ erledigt**
(re-synced auf 1.80, Smoke 3/3 — siehe Session-Eintrag oben; ebenfalls `-S`-Source-Override).
**Alle drei Maschinen jetzt in Parität auf gui-lib 1.80.**

---

## Frühere Sessions

Siehe `docs/report*.md` (chronologisch) und die Checkpoint-Tabelle in `CLAUDE.md`.

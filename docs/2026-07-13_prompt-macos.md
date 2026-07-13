# Prompt — macOS Nativ-Datei-Dialog-Matrix (Phase 4) — 2026-07-13

**Maschine:** ausschließlich **macOS arm64**. Windows (7/7) und Linux (8/8) sind bereits
grün — **nicht** wiederholen.

**Zuerst lesen (Kontext, gezielt):** `STATUS.md` (jüngste Sessions oben), `docs/HACKING.md
§19` (file-selector-Mechanik, Fund 1/2, Qt-eigen×nativ-Matrix-Tabelle), `CLAUDE.md` (fixe
Regeln 1–8, Umgebung/Build/Run macOS, Checkpoint-Tabelle).

## Ziel (ein Thema)

Die letzte offene Zelle der 3×2-Matrix schließen: der **native macOS-Dateidialog**
(`PLT_QT_NATIVE_FILE_DIALOG=1` → NSOpenPanel/NSSavePanel) über `get-file`/`put-file`.
Zu **beweisen**: der native Dialog trägt **denselben** non-modalen
`QFileDialog::open()`+`finished`-Signal+`shim_pump()`-Mechanismus wie der Qt-eigene und
der native Windows-Dialog — **ohne eigene geschachtelte Schleife, ohne `exec()`**.
NSOpenPanel ist der klassische „eigene-Cocoa-Runloop"-Kandidat; genau das ist die Frage,
die **gemessen** (nicht angenommen) werden muss.

## Phase 0 — Umgebung messen (nicht annehmen)

1. `racket --version` **messen** (nicht aus Doku kopieren) — für den Report-Header.
   Erwartet: `v9.2 [cs]`, arm64.
2. **Sync-CHECK, kein Auto-Pull:** gui-Submodul (`third_party/gui`, Branch `qt-backend`)
   und Umbrella (`main`) prüfen — Soll: gui @ `caef3e9c`, Umbrella-Zeiger passend. macOS
   ist Ursprung dieser beiden Fixe, sollte also bereits dort stehen. **Steht etwas zurück
   → STOPP, `AskUserQuestion` (Regel 7)**, ob gepullt werden soll; nicht automatisch pullen.
3. Shim-Aktualität prüfen. Reine Validierung erwartet **keine** `shim.cpp`-Änderung ⇒ i. d. R.
   kein Rebuild. Falls (Instrumentierung, s. u.) `shim.cpp` doch angefasst wird:
   `cmake --build qt-shim/build/macos-arm64` **vor** dem Test (stale-Shim-Falle).
4. Bytecode: gui-lib wird auf macOS via `-S`-Source-Override konsumiert ⇒ bei Änderung
   `raco make`, **nicht** `raco setup`.
5. **Light Mode verifizieren** über den maßgeblichen Key `framework:white-on-black-mode?`
   = `#f` (`org.racket-lang.prefs.rktd`). **Nicht** den Legacy-Key
   `framework:color-scheme` prüfen (Falle, §16).
6. Smoke: `PLT_QT=1 racket -S third_party/gui/gui-lib -S third_party/draw/draw-lib -l raco
   -- test tests/smoke.rkt` → **3/3** erwartet. (macOS: `QT_PLUGIN_PATH` nicht nötig.)

**Self-Gate Checkpoint 0:** Version gemessen, Sync verifiziert, Light Mode bestätigt,
Smoke 3/3. Irgendetwas rot / unerwartet → **STOPP + Bericht**, bevor Phase 1 beginnt.

## Phase 1 — Nativ-Matrix messen

Treiber: `examples/file-dialog-probe.rkt` (bestehend), gestartet mit
`PLT_QT=1 PLT_QT_NATIVE_FILE_DIALOG=1 PLT_QT_DEBUG=1 racket -S third_party/gui/gui-lib -S
third_party/draw/draw-lib examples/file-dialog-probe.rkt`.

**Die eine Kernfrage, die die Messung beantworten muss:** Läuft der Pump weiter, während
der native Panel offen ist, und kommt `finished` über einen ganz normalen
`shim_pump()`-Aufruf zurück — ODER dreht NSOpenPanel/NSSavePanel eine eigene Cocoa-Runloop
und hungert unseren Pump aus?

- **Pump-Lebendigkeit gezielt nachweisen** (gated hinter `PLT_QT_DEBUG`, additiv, im Code
  bleibend — wie die bestehende Diagnose). Eine saubere, `wx/qt`-freie Möglichkeit: im
  Probe-Skript (`examples/`) einen Racket-seitigen Heartbeat (z. B. `timer%`, alle ~200 ms
  ein Print/Zähler) **vor** dem Öffnen armen — feuert er weiter, während der Panel offen
  ist, lebt der Pump; friert er ein, dreht der native Dialog eine eigene Schleife. Wähle
  die Instrumentierung selbst; entscheidend ist der belastbare Nachweis, nicht die Methode.
- Zusätzlich, wie in den anderen Zellen messen: `cb`-/Trampolin-Adresse über **alle**
  Aufrufe **und** über den `get`→`put`-Moduswechsel hinweg **identisch** (Einmal-Trampolin,
  §19 Fund 2); `native=1` durchgehend im Log; kein Crash, kein Hang.

**Self-Gate Checkpoint 1 (der springende Punkt):** Nach dem **ersten** Öffnen unter
Messung entscheiden:

- **Pump lebt, `finished` kommt via normalem Pump, sauberer Rücklauf →
  GO (autonom):** volle Serie fahren, Ziel-Parität zu Windows (7/7)/Linux (8/8) — ~8 Zyklen
  gemischt Open/Save/Cancel + Overwrite-Warnung. Das ist der gute Pfad.
- **Pump ausgehungert / Probe hängt / `finished` kommt nicht unter Pumpen / Crash →
  STOPP + Bericht.** NSOpenPanel dreht dann eine eigene Runloop. **NICHT** mit `exec()`
  erzwingen, **NICHT** umgehen, **NICHT** den nativen Pfad zum Standard machen. Harte
  Guardrail (Regel 1). Qt-eigen bleibt Standard; nativ ist nur Flag/Datenpunkt. Befund
  dokumentieren, Entscheidung dem Nutzer/Advisor überlassen.

**Falls stattdessen ein echter `wx/qt/`-Bug auftaucht** (kein Runloop-Thema, sondern z. B.
falscher Rückgabewert / Absturz im nativen Pfad): **STOPP + `AskUserQuestion`** vor jedem
Fix (Scope-Erweiterung, Regel 7). Nicht eigenmächtig fixen.

## Phase 2 — echtes DrRacket (optional, mit Nutzer)

Falls Phase 1 grün: `PLT_QT=1 PLT_QT_NATIVE_FILE_DIALOG=1` echtes DrRacket, File → Open +
Save As, vom Nutzer visuell bestätigen (End-to-End). Nice-to-have; die Probe ist der
primäre Beweis. (Vorher sicherstellen, dass keine alte DrRacket-Instanz läuft.)

## OUT OF SCOPE (nicht anfassen)

- **Crash B** (Teardown/`deleteLater()`) — geparkt, Nutzer-Entscheidung. Nicht untersuchen,
  nicht fixen.
- **htdp-lib** / `test-engine:test-dock-size` / alles htdp — Schluss-Session, nicht jetzt.
- macOS „Windows"-Menü (8 statt 9) — eigene Diagnose-Session.
- `get-directory`/`get-file-list` (`'dir`/`'multi`) — bleibt Stub, nicht Teil des Kontrakts.
- Preferences-Dialog + Rest-Widgets (`choice%`/`radio-box%`/`slider%`/`tab-panel%`) — der
  **nächste** Block, nicht dieser.
- **Kein Shared-Code** (`wx/common/…`) ändern. Scheint ein Fix Shared-Code zu brauchen →
  STOPP + fragen.
- Windows/Linux nicht wiederholen (bereits grün).

## Commit-/Sync-Disziplin

- Erwartung: **reine Validierung ⇒ keine Fix-Commits.**
- Repo-Aufteilung beachten: `qt-shim/`, `examples/`, `docs/` liegen im **Umbrella**;
  `wx/qt/*.rkt` liegt im **gui-Submodul** (`third_party/gui`, `qt-backend`).
- Diese Session berührt voraussichtlich nur `examples/` (Probe-Heartbeat) + `docs/` (ggf.
  gated `shim.cpp`-Logging) ⇒ **Umbrella-only, kein Submodul-Commit nötig.** Falls doch
  `wx/qt/` (Bug-Fix) angefasst wird: Zwei-Repo-Reihenfolge (Regel 6/8: Submodul syncen →
  committen → **pushen** → dann Umbrella-Zeiger-Commit).
- **Push/Pull erst nach `AskUserQuestion` (Regel 7).** Nichts automatisch pushen, keinen
  Sync als offenen TODO stehen lassen.

## Report

- Datei: `docs/2026-07-13_report-macos.md`, Header mit **gemessener** `racket --version`.
- Aktualisieren: `docs/HACKING.md §19` (macOS-Nativ-Absatz + Matrix-Tabelle: macOS-Nativ
  von ⬜ auf ✅, sobald grün), `CLAUDE.md`-Checkpoint (3×2-Matrix komplett), `STATUS.md`
  (neuer Eintrag oben).

# Bericht — Clean-Start-Check (2026-07-09_prompt, macOS-Zweig) — NICHT sauber, zwei Befunde

**Datum:** 2026-07-09
**Plattform:** macOS arm64 (`aarch64-macosx/cs`), Darwin 25.5.0
**Repro:** echtes `PLT_QT=1 racket -S third_party/gui/gui-lib -S third_party/draw/draw-lib -l drracket`
**Startrezept:** kein Installation-Link auf dieser Maschine — `-S`-Source-Override zwingend
(Katalog-`gui-lib` bleibt Upstream 1.80, sonst stiller Fallback auf cocoa).

**Kurzfassung:** Phase 0 (Sync/Rebuild/Re-Smoke) unauffällig, grün. Phase 2 ist laut Prompt
Windows-exklusiv, hier nicht wiederholt. **Phase 1 (Clean-Start-Check) ist NICHT sauber** —
zwei unabhängige, reproduzierte Befunde, keiner davon ein Missing-Method/Arity-Crash. Gemäß
Guardrail („Etwas anderes als Missing-Method: STOPP, berichten") wurde **kein Fix versucht**.
Prozess blieb durchgehend responsiv, kein Crash-Dialog, kontrolliert beendet.

## 1. Phase 0 — Sync + Rebuild

- `racket --version` → **v9.2 [cs]** (gemessen).
- gui-Submodul (`third_party/gui`, Branch `qt-backend`): stand auf `ba2dacc9`, 3 Commits
  hinter `origin/qt-backend` (`87ebd078`, vom Umbrella bereits referenziert). Vor dem Pull
  ausführlich verifiziert (Nutzer-Sorge wegen einer früheren Fast-Forward-Beschädigung):
  einziger Remote `origin`, `HEAD` ist strikter Vorfahre von `origin/qt-backend`, keine
  lokalen Extra-Commits, Working Tree/Index clean, kein detached HEAD, kein zweites Worktree.
  Ein frischer `fetch` brachte einen Tag `orphan-de933088` mit — das ist der bereits **vorher**
  korrekt behandelte Altfall aus `HACKING.md §17` (alter SHA vor einem Rewrite von `b2369d48`
  getaggt+gepusht), nicht live betroffen. Nach Nutzer-Bestätigung: `git -C third_party/gui pull
  --ff-only origin qt-backend` → `ba2dacc9..87ebd078`, sauberer Fast-Forward.
- Umbrella (`main`): Zeiger zeigte bereits auf `87ebd078` (aus dem Linux-Report-Commit) — kein
  neuer Pointer-Commit nötig.
- **Shim war veraltet** (Build vom 2026-07-08, `shim.cpp` vom 2026-07-09 mit den
  `PLT_QT_DEBUG`-Hooks aus der Windows-Session) → `cmake --build qt-shim/build/macos-arm64`
  (Ninja) neu ausgeführt.
- **Bytecode neu:** stale `compiled/`-Verzeichnisse in `third_party/gui` + `third_party/draw`
  entfernt, dann `racket -S third_party/gui/gui-lib -S third_party/draw/draw-lib -l raco --
  make third_party/gui/gui-lib/mred/mred.rkt` (kein Installation-Link auf dieser Maschine).
- Re-Smoke: **3 tests passed** (einzige Nebenwirkung: harmlose
  `QThreadStorage: entry 0 destroyed before end of thread`-Teardown-Meldung, bereits aus
  früheren Sessions bekannt).

## 2. Phase 1 — Clean-Start-Check: NICHT sauber

Kein laufender DrRacket-Prozess vorab. Start via `PLT_QT=1 racket -S ... -l drracket` im
Hintergrund. Prozess blieb stabil (CPU fiel von 99% auf 10,6% nach ~18s — normale
Startup-Bytecode-Last, kein Loop-Spin), kein Crash-Dialog, kein Fehler im Log. Zwei
Screenshots zu unterschiedlichen Zeitpunkten (dazwischen Fokuswechsel zu einem anderen
Fenster und zurück) zeigen **pixelidentisch dasselbe** Bild — kein Animations-/Timing-Artefakt,
sondern reproduzierbarer Zustand.

### 2.1 Befund A — Menüleiste: 8 statt 9 Menüs (Daten-Ebene, kein Rendering-Artefakt)

`osascript -e 'tell application "System Events" to tell process "racket" to get name of menu
bar items of menu bar 1'` → `Apple, racket, File, Edit, View, Language, Racket, Insert,
Scripts, Help`. Das sind **8** App-Menüs — das erwartete 9. fehlt. Da diese Abfrage direkt
gegen die native `NSMenu`-Struktur läuft (nicht gegen einen Screenshot), ist das ein
**Daten-Befund, kein Rendering-Artefakt**: das Menü fehlt tatsächlich im Menübalken.

**Abgleich mit eigener Baseline:** `docs/2026-07-08_report-4-macos.md` (Zeile 148) berichtete
für exakt diese Maschine bei Submodul-Stand `ba2dacc9` **9** Top-Level-Menüs inkl. `Windows`
(File/Edit/View/Language/Racket/Insert/Scripts/**Windows**/Help) — grün, mit Screenshot-Beleg.
Zwischen `ba2dacc9` und dem jetzigen `87ebd078` liegen 3 Commits. Code-Vergleich
(`git -C third_party/gui diff ba2dacc9..87ebd078`) zeigt: `frame.rkt` (nur `set-icon`-Stub,
bereits bekannt/gewünscht), `menu-bar.rkt`/`window.rkt` (reine Kommentar-Umbenennungen,
keine Logikänderung), `canvas.rkt` (siehe 2.2) — **keine dieser Änderungen berührt den
Menüleisten-/Frame-Aufbau**. Die fehlende 9. Menüzeile ist damit vermutlich **nicht** durch
den heutigen Sync verursacht, sondern eine bereits vorher vorhandene, aber am 2026-07-08 nicht
beobachtete Diskrepanz (möglicherweise ein von Qt/macOS zur Laufzeit dynamisch befülltes
`Window`-Menü, das nicht bei jedem Start gleich erscheint) — **nicht weiter diagnostiziert**
(Guardrail: kein Event-Loop-/Qt-Interna-Deep-Dive in dieser Session). Offener Punkt für die
nächste Session.

### 2.2 Befund B — Editor-Bereich beim allerersten Paint bereits verzerrt (kein Redraw nötig)

Direkt nach dem Start, **bevor irgendetwas getippt wurde**: der Definitions-Editor zeigt statt
einer sauberen `#lang racket/base`-Zeile + leerem Editor + REPL-Prompt ein verzerrtes Bild —
ein breiter schwarzer Hervorhebungsbalken über der `#lang`-Zeile, ein zweiter, fast
fensterbreiter schwarzer Balken auf Höhe der REPL-Eingabezeile, und am unteren Fensterrand
überlappender, ineinander verschachtelter Text (mehrere Status-/Label-Widgets scheinen an
derselben Position übereinander gezeichnet). Zwei unabhängige Screenshots (Fenster dazwischen
in den Hintergrund und wieder in den Vordergrund gebracht) zeigen exakt dasselbe Bild bis auf
Pixelebene — kein Lade-/Animationszustand.

**Ursachen-Ausschluss (Diagnose-Hooks dieser Session sind nicht die Quelle):** Der einzige
Verhaltens-relevante Teil des Pulls (`ba2dacc9..87ebd078`) in `canvas.rkt` ist strikt hinter
`(getenv "PLT_QT_DEBUG")` gated (nur `eprintf`-Aufrufe); die einzige nicht-kosmetische
Änderung — `on-backing-flush` wird jetzt mit einem zweiten `nothing-to-draw-proc`-Argument
aufgerufen statt implizit dem Default — entspricht exakt der Methoden-Signatur in
`wx/common/backing-dc.rkt:96` (`(on-backing-flush proc [nothing-to-draw-proc void])`) und
ändert das Verhalten bei nicht gesetztem `PLT_QT_DEBUG` nicht. Der gepullte Commit ist damit
**nicht** die Ursache des Garble-Befunds.

**Einordnung:** passt in der Grundmechanik zum bereits diagnostizierten Windows-Redraw-Bug
(Root-Cause-Kandidat: `begin-refresh-sequence`/`end-refresh-sequence` sind No-ops,
`start-backing-retained` wird im Qt-Backend nie aufgerufen, siehe `docs/HACKING.md §16`) —
**aber nicht 1:1 deckungsgleich**: der dokumentierte Windows-Befund tritt erst nach mehreren
getippten Zeilen auf (ältere Zeilen verschwinden), hier ist bereits der **allererste** Paint
vor jeder Eingabe betroffen und zeigt keine leeren Flächen, sondern überlappende/verschachtelte
Inhalte. Gleiche Bug-Familie ist plausibel (macOS zeichnet beim Start ggf. in mehr
Teil-Invalidierungsschritten als Windows und trifft die fehlende Retained-Klammerung dadurch
früher/härter), aber das ist eine Vermutung, keine Messung — **nicht weiter diagnostiziert**,
da außerhalb des für diese Session erlaubten Scopes (Missing-Method-Stubs) und weil ein
Redraw-Fix laut Prompt explizit die nächste Session ist.

## 3. Guardrails eingehalten

- Kein `exec()`/`QEventLoop`, keine geschachtelte Schleife — nicht berührt.
- cocoa/gtk/win32 nicht angefasst (nur `wx/common/backing-dc.rkt` gelesen, zum Abgleich).
- Sync-Schritt (`pull --ff-only`) vorab per `AskUserQuestion` bestätigt (Regel 7), inkl.
  ausführlicher Sicherheitsprüfung auf Nutzer-Anfrage.
- **Kein Fix versucht** — beide Befunde sind keine Missing-Method-Landmine, Guardrail sieht
  dafür STOPP+Bericht vor, nicht Nachbessern.
- Gated Diagnose bleibt gated; keine neuen Diagnose-Hooks in dieser Session hinzugefügt (rein
  lesende Analyse).
- Report-Header nutzt gemessene `racket --version`.

## 4. Commits & Stand

- gui-Submodul (`qt-backend`): kein neuer Commit — reiner Fast-Forward-Pull, lokaler Stand
  jetzt `87ebd078` (deckungsgleich mit `origin` und mit dem, was der Umbrella bereits
  referenziert).
- Umbrella (`main`): kein Pointer-Commit nötig (zeigte schon auf `87ebd078`). Dieser Bericht,
  `STATUS.md`-Eintrag und `CLAUDE.md`-Checkpoint-Ergänzung sind die einzigen neuen Dateien
  dieser Session.

## 5. Nächste Schritte

- **Menüleisten-Diskrepanz (Befund A):** klären, ob das 9. Menü (`Windows`) auf macOS
  zuverlässig erscheint oder ob `ba2dacc9`-Bericht einen Sonderfall erfasst hat — eigener,
  kleiner Diagnose-Schritt vor dem nächsten macOS-Release-Check.
- **Editor-Garble beim ersten Paint (Befund B):** als zusätzlicher Cross-Platform-Datenpunkt
  in die geplante Redraw-Fix-Session einbringen — insbesondere prüfen, ob der geplante Fix
  (`start-backing-retained` + `suspend-flush`/`resume-flush`, Basis
  `docs/2026-07-09_report-win.md`) auch dieses macOS-spezifische Erscheinungsbild behebt, nicht
  nur das Windows-Symptom.
- Redraw-Bug-**Fix** bleibt plattformübergreifend eine eigene Session.

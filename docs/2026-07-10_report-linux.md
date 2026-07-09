# Bericht — Redraw-Bug-Validierung (2026-07-10_prompt, Phase 4, Linux)

**Datum:** 2026-07-10
**Plattform:** Linux x86-64 (KWin/X11)
**Racket:** v9.2 [cs] (gemessen via `racket --version`)
**Repro:** echtes `PLT_QT=1 PLT_QT_DEBUG=1` DrRacket, synthetische Tastatureingabe via
selbstgebautem XTest-Helfer (kein `xdotool` auf dieser Maschine vorhanden).

**Kurzfassung:** Der auf Windows gefixte Redraw-Bug (`docs/HACKING.md` §16,
`docs/2026-07-10_report-win.md`) ist auf Linux validiert und grün — alle sechs getippten
Zeilen bleiben sichtbar, keine weißen Lücken. Reine Validierungssession, keine
Fix-Commits.

## 1. Phase 4 — Sync + Rebuild

- **Vor dem Pull ausführlich geprüft** (CLAUDE.md Regel 7/8): Umbrella `main` war bereits
  auf `origin/main` aktuell (`96cabe5`, Zeiger auf gui@`04935cb6`). Lokales gui-Submodul
  stand noch auf `87ebd078` (1 Commit zurück). Verifiziert vor dem Pull: `origin/qt-backend`
  einziger Remote, lokales HEAD strikter Vorfahre von `origin/qt-backend`, keine lokalen
  Extra-Commits, Working Tree clean, frisches `git fetch` bestätigt denselben Stand — nach
  Nutzer-Bestätigung sauberer `git pull --ff-only origin qt-backend` (`87ebd078` →
  `04935cb6`).
- **Diff-Check:** `git diff --stat 87ebd078 04935cb6` zeigt ausschließlich
  `gui-lib/mred/private/wx/qt/canvas.rkt` (23 Zeilen) — kein `shim.cpp`-Anteil. Vollständiger
  Diff geprüft: exakt die vier im Windows-Report beschriebenen Änderungen (
  `start-backing-retained` nach Konstruktion, `suspend-/resume-flush`-Verdrahtung,
  `reset-backing-retained` in `set-size`, `dc`-Definition vor den Seed-`set-size`-Aufruf
  verschoben) — nichts Zusätzliches, nichts Fehlendes.
- **Shim:** `cmake --build qt-shim/build/linux-x64` → „ninja: no work to do" (bereits
  aktuell, da dieser Fix rein Racket-seitig ist und `shim.cpp` unverändert blieb).
- **Bytecode:** `racket -S third_party/gui/gui-lib -S third_party/draw/draw-lib -l raco --
  make -l mred` — läuft ohne Fehler/Warnungen durch.
- **Re-Smoke:** `PLT_QT=1 ... raco test tests/smoke.rkt` → **3/3 grün**.
- **Theme:** `~/.config/racket/racket-prefs.rktd` zeigt
  `framework:color-scheme-light` = `classic`, kein `os`/`follow-system`-Wert — Light Mode
  explizit bestätigt.

## 2. Repro + Ergebnis

Da `xdotool`/`wtype`/`ydotool` auf dieser Maschine nicht installiert sind, wurde ein
kleiner XTest-Helfer (`synth.c`, gegen `libX11`/`libXtst.so.6` gelinkt, Header von Hand
deklariert da `libxtst-dev` fehlt) für echte synthetische Keystrokes/Klicks gebaut
(Scratch-Datei, nicht im Repo).

- `PLT_QT=1 PLT_QT_DEBUG=1 racket -S ... -l drracket` gestartet, Fenstergeometrie per
  `xwininfo` ermittelt, Klick in den Definitions-Editor, dann 6× `(define line-N N)` +
  Enter über echte `XTestFakeKeyEvent`-Tastendrücke.
- **Vorher (Clean-Start):** Screenshot (`xwd` + selbstgebauter XWD→PNG-Parser, da
  `scrot`/`import`/`gnome-screenshot` fehlen) zeigt saubere helle Baseline, 9 Menüs, leerer
  Editor mit `1`-Gutter — keine Landmine.
- **Nachher (nach 6 Zeilen):** Screenshot zeigt **alle sechs Zeilen
  (`line-1`…`line-6`) durchgehend sichtbar**, korrekt nummeriertes Gutter (1–7), keine
  weißen Lücken — identisch zum Windows-Nachher-Ergebnis.
- **Debug-Log bestätigt den Fix-Pfad aktiv:** `[qt-canvas] begin-refresh-sequence ->
  suspend-flush` / `end-refresh-sequence -> resume-flush` feuern während des Repros (statt
  der alten `(no-op)`-Meldungen).
- Smoke nach dem Repro weiterhin grün (Prozess normal beendet).

## 3. Zusätzliche Sicht (Resize/Minimieren) — NICHT validiert, Ursache ungeklärt

Im Unterschied zu Windows (SendKeys/`MoveWindow` über echte WM-APIs) hat diese Maschine
kein `xdotool`. Ein roher `XResizeWindow`-Aufruf auf das Top-Level-Fenster vergrößerte das
X-Fenster serverseitig, löste aber **keinen** `set-size`/`shim_widget_set_geometry`-Aufruf
im Debug-Log aus — Qt hat die Größenänderung nachweislich nie verarbeitet. Der
resultierende Screenshot zeigt doppelten/versetzten Inhalt.

**Wichtig:** die naheliegende Erklärung „reines X11-Test-Artefakt, weil kein WM
vermittelt" ist nicht schlüssig geprüft — im Gegenteil, KWin (`kwin_x11`) läuft als
EWMH-WM auf dieser Maschine und würde `XResizeWindow` auf ein gemanagtes Top-Level
normalerweise per `ConfigureNotify` an Qt weiterreichen. Zusätzlich passt „Server
dupliziert Inhalt in den neuen Bereich" nicht zu den vorher gemessenen Fenster-Attributen
(`Backing Store State: NotUseful`, `NorthWestGravity`). Weder „warum verarbeitete Qt
nichts" noch „warum erschien trotzdem ein kohärentes zweites Bild" ist rekonstruiert. Ein
anschließender korrekter ICCCM-Minimieren/Wiederherstellen-Zyklus
(`XIconifyWindow`/`XMapWindow`, Map-State-Wechsel technisch bestätigt) zeigte denselben
bereits verzerrten Zustand unverändert weiter — auch das nicht aufgeklärt.

**Resize-/Minimieren-Verhalten auf Linux bleibt damit als offene Beobachtung stehen**,
nicht als geschlossenes Nicht-Problem — insbesondere relevant, weil macOS bereits einen
verwandten Redraw-Nebenbefund (Erstes-Paint-Verzerrung, `docs/2026-07-09_report-macos.md`)
hat und die kommende macOS-Session denselben Codepfad per Resize prüfen wird. Kein
Fix-Versuch in dieser Session (Guardrail: reine Validierung). Die eigentliche
Validierungsanforderung aus Phase 4 (Tipp-Repro) ist davon unabhängig und eindeutig grün.

## 4. Guardrails eingehalten

- Kein `exec()`/`QEventLoop`, keine geschachtelte Schleife.
- cocoa/gtk/win32 nicht angefasst.
- Nur Fast-Forward-Pull, vorher per `AskUserQuestion` bestätigt.
- Gated Diagnose bleibt gated (`PLT_QT_DEBUG`).
- Reine Validierung — keine Fix-Commits in `wx/qt/`.
- Report-Header nutzt gemessene `racket --version`.

## 5. Nächste Schritte

- **macOS** (Validierung + macOS-Nebenbefunde, `docs/2026-07-10_prompt.md` Phase 5/6):
  gleiche Validierung gegen den tatsächlichen Vier-Änderungen-Diff, danach die beiden
  offenen macOS-Beobachtungen aus `docs/2026-07-09_report-macos.md` (Menüanzahl,
  Statuszeile) unter Light Mode erneut ansehen.
- Nach grüner macOS-Validierung: Redraw-Zeile in `CLAUDE.md` als vollständig geschlossen
  markieren (alle drei Plattformen), E-0 damit komplett; danach Checkpoint E.

## 6. Commits & Stand

- gui-Submodul (`qt-backend`): ff-Pull `87ebd078` → `04935cb6`, keine neuen Commits.
- Umbrella (`main`): `docs/HACKING.md` §16 (Linux-Validierung ergänzt), dieser Bericht,
  `STATUS.md`-Eintrag.

# Bericht — Redraw-Bug FIX (2026-07-10_prompt)

**Datum:** 2026-07-10
**Plattform:** Windows 11 Enterprise, x86-64 (primäre Entwicklungsmaschine)
**Racket:** v9.2 [cs] (gemessen via `C:\Program Files\Racket\Racket.exe --version`)
**Repro:** echtes `PLT_QT=1 PLT_QT_DEBUG=1 DrRacket.exe`, SendKeys-Tastatureingabe, Resize,
Minimieren/Wiederherstellen.

**Kurzfassung:** Der Redraw-Bug aus `docs/2026-07-09_report-win.md` (`HACKING.md` §16) ist
auf Windows gefixt und vom Nutzer visuell bestätigt. Der im Prompt vorgeschriebene
2-Schritt-Fix reichte **allein nicht** — er hätte den normalen Programmstart kaputt
gemacht (leerer Editor statt `#lang racket`). Der vollständige, verifizierte Fix umfasst
vier Änderungen in `wx/qt/canvas.rkt`, zwei mehr als ursprünglich beschrieben. Zwei-Repo-
Commit durchgeführt und gepusht (Submodul zuerst).

## 1. Phase 0 — Umgebung verifiziert

- `racket --version` → **v9.2 [cs]**.
- Beide Repos sauber vor Beginn: Umbrella (`main`) up to date mit `origin/main`; Submodul
  (`third_party/gui`, `qt-backend`) up to date mit `origin/qt-backend` (`87ebd078`), Zeiger
  im Umbrella deckungsgleich. Frisches `git fetch` in beiden Repos: keine neuen Remote-
  Commits.
- Shim aktuell: `racketqtshim.dll` (2026-07-09 09:59) neuer als `shim.cpp` (09:58) — kein
  Rebuild nötig für Phase 0 (kein Shim-Code in dieser Session geändert).
- DrRacket-Theme: `racket-prefs.rktd` zeigt `framework:color-scheme` = `framework:color-
  scheme-light` = `classic` — explizit gesetzt (kein `os`/`follow-system`-Wert vorhanden),
  Light Mode bestätigt.
- Smoke: **3/3 grün** (`raco test tests/smoke.rkt`, `PLT_QT=1`).

## 2. Phase 1 — Vorher-Baseline gemessen

Repro identisch zur Vorsession: 6× `(define line-N N)` real getippt (SendKeys, escaped
Klammern `{(}`/`{)}`, expliziter Klick in den Definitions-Editor zuerst) in ein frisches
`Untitled`-Fenster.

**Ergebnis:** Zeilen-Gutter zeigt korrekt 1–9, aber nur die letzte Zeile
(`(define line-six 6)`) ist sichtbar — der Rest ist weiß. Bug reproduziert
(Screenshot `tmp/redraw-before.png`).

**Debug-Log bestätigt den Mechanismus live:** `[qt-canvas] begin-refresh-sequence
(no-op)` / `end-refresh-sequence (no-op)` feuern tatsächlich während des echten Repros;
jeder `on-backing-flush` liefert eine volle, aber **frische** Bitmap (`bm=854x316`), nie
den akkumulierten Vorzustand.

## 3. Phase 2 — Fix (vier Änderungen, nicht zwei)

Der im Prompt vorgeschriebene 2-Schritt-Fix:

1. `(send dc start-backing-retained)` einmalig nach `qt-dc%`-Erzeugung.
2. `begin-refresh-sequence`/`end-refresh-sequence` → `(send dc suspend-flush)` /
   `(send dc resume-flush)`.

**Beim ersten Test dieser zwei Änderungen allein: Clean-Start kaputt.** Ein frisches
`Untitled`-Fenster rendert komplett leer (kein `#lang racket`, kein Gutter) — noch bevor
irgendetwas getippt wurde. Ursache per Code-Vergleich mit win32/gtk gefunden: beide haben
einen **dritten** Baustein, den die Kandidaten-Analyse vom 07-09 nicht nannte:

3. **`(send dc reset-backing-retained)` im `set-size`-Override**, direkt nach
   `shim_widget_set_geometry`. Ohne das bleibt die jetzt retained Bitmap für immer auf der
   Größe eingefroren, die beim allerersten `get-cr`-Aufruf existierte — typischerweise ein
   winziger Platzhalter (30×30, 1×1), lange bevor Rackets Layout-Engine die echte Größe
   zuweist. win32 löst das über `on-resized` → `reset-dc` (`wx/win32/canvas.rkt:273-285`),
   gtk über `internal-on-client-size` → `reset-dc` (`wx/gtk/canvas.rkt:674-686`). Im
   Qt-Backend ist `set-size` (von Rackets Layout-Engine aufgerufen) die analoge Stelle.

Nach Ergänzung von 3. trat ein zweiter, unabhängiger Fehler auf: DrRacket-Start hing bei
konstantem Speicherverbrauch (~190 MB, kein Fenster). Stderr zeigte:

```
dc: undefined;
 cannot use field before initialization
  context...: set-size method in base-canvas%
```

**Ursache:** `base-canvas%`s Konstruktor ruft bereits einmal `set-size` auf (Zeile ~181,
um `window%`s `w`/`h` aus den Init-Args zu seeden), **bevor** `(define dc ...)` in der
ursprünglichen Reihenfolge stand. Da `set-size` jetzt `dc` anfasst (Änderung 3), schlug
dieser erste Aufruf mit dem Racket-Klassenfeld-Ordering-Fehler fehl — kein Qt-Problem,
reine Konstruktor-Reihenfolge.

4. **Fix:** `(define dc (new qt-dc% [qt-canvas this]))` + `start-backing-retained` vor den
   Seed-`set-size`-Aufruf verschoben.

`git diff` auf `wx/qt/canvas.rkt` nach Abschluss: genau diese vier Änderungen, nichts
Überflüssiges aus dem Crash-Fix-Zyklus.

## 4. Phase 3 — Nachher-Messung

Identischer Repro (frisches `Untitled`-Fenster, kein Recover-Dialog, `SetForegroundWindow`
+ `CopyFromScreen` explizit verifiziert vor jeder Eingabe):

- **Alle 6 Zeilen + `#lang racket` bleiben sichtbar**, korrekt syntax-hervorgehoben
  (Screenshot `tmp/redraw-after-typing.png`).
- **Resize** (853×814 → 1100×900 via `MoveWindow`): Inhalt bleibt vollständig erhalten
  (`tmp/redraw-after-resize.png`).
- **Minimieren + Wiederherstellen** (voller Expose-Zyklus): Inhalt bleibt unverändert
  sichtbar (`tmp/redraw-after-minrestore.png`).
- **Diskriminator:** `bm=`-Größe in den `on-backing-flush`-Logs wächst jetzt mit dem
  Inhalt (`854x316` → `854x377` → `854x437` bei den sechs nacheinander getippten Zeilen),
  fällt nie mehr auf eine Platzhaltergröße (30×30, 1×1) zurück.
- Smoke: **3/3 grün** nach dem Fix.
- **Vom Nutzer visuell bestätigt** (Vorher/Nachher-Screenshots in `tmp/`).

### 4.1 Nebenbefund — Toolbar-Save-Icon (nicht verfolgt, vorbestehend)

Im Minimieren/Wiederherstellen-Screenshot ist ein Save-Icon in der Toolbar sichtbar, das
in den beiden anderen Nachher-Screenshots als weißes Rechteck erscheint. Geprüft: Toolbar-
Buttons laufen über `wx/qt/button.rkt` — eine eigene, native Widget-Klasse, komplett
getrennt von `canvas.rkt`/`backing-dc%`. Der Unterschied ist ein Timing-Effekt dieses
Buttons (Icon erscheint erst nach einem vollen Repaint-Zyklus, den Minimieren/
Wiederherstellen erzwingt) und kein Nebeneffekt dieses Fixes.

### 4.2 Nebenbefund — Autosave-Recovery-Dialog rendert selbst korrupt (nicht verfolgt)

Während der Fix-Iteration führten mehrere harte `taskkill /F` (zur schnellen Iteration
zwischen Automatisierungsversuchen) zu DrRacket-Autosave-Dateien (`mredauto.2` in
`Documents/`, dokumentiertes Verhalten, `HACKING.md` §13). Der resultierende „Recover
Files"-Dialog selbst rendert bei jedem Auftreten stark verstümmelt (zufällige Farbblöcke
statt Text/Checkboxen, per `CopyFromScreen` und `PrintWindow` gleichermaßen bestätigt).
Dieser Dialog nutzt Stub-List-/Check-Widgets, nicht `canvas%` — separates Thema, nicht
Teil dieses Fixes. Alle so erzeugten Autosave-Testartefakte (Inhalt jeweils verifiziert
als eigener Repro-Text) wurden nach Nutzer-Rückfrage entfernt.

## 5. Guardrails eingehalten

- Kein `exec()`/`QEventLoop`, keine geschachtelte Schleife.
- cocoa/gtk/win32 nicht angefasst (nur gelesen, zum Vergleich).
- Zwei-Repo-Commit (Submodul zuerst gepusht, dann Umbrella-Zeiger).
- Nur Fast-Forward-Pulls/-Pushes.
- Gated Diagnose bleibt gated (`PLT_QT_DEBUG`).
- Checkpoint (Vorher/Nachher-Screenshots) vor Commit vom Nutzer bestätigt.
- Report-Header nutzt gemessene `racket --version`.

## 6. Nächste Schritte

- **Linux** (Validierung, `docs/2026-07-10_prompt.md` Phase 4): ff-Pull, Shim neu bauen,
  Bytecode neu, Re-Smoke 3/3, identischer Repro. Muss gegen den tatsächlichen
  Vier-Änderungen-Diff prüfen, nicht nur gegen die 2-Schritt-Beschreibung aus der
  Kandidaten-Analyse vom 07-09.
- **macOS** (Validierung + macOS-Nebenbefunde, Phase 5/6): dieselbe Validierung, danach
  die beiden offenen macOS-Beobachtungen aus `docs/2026-07-09_report-macos.md`
  (Menüanzahl, Statuszeile) unter Light Mode erneut ansehen — nur beobachten, nicht fixen.
- Nach grüner Validierung auf allen drei Plattformen: Redraw-Zeile in `CLAUDE.md` als
  vollständig geschlossen markieren, E-0 damit komplett; danach Checkpoint E.

## 7. Commits & Stand

- gui-Submodul (`qt-backend`): `87ebd078` → `04935cb6`, gepusht. Vier Änderungen in
  `wx/qt/canvas.rkt` (siehe Abschnitt 3).
- Umbrella (`main`): Submodul-Zeiger-Bump, `docs/HACKING.md` §16 (Kandidat → bestätigt +
  gefixt), `CLAUDE.md`-Checkpoint-Tabelle + narrativer Absatz, `STATUS.md`-Eintrag, dieser
  Bericht, `.gitignore` (`tmp/` — lokale Screenshot-Ablage für Nutzer-Review, nicht
  getrackt).

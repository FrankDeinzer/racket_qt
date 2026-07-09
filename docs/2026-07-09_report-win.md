# Bericht — Clean-Start-Check + Redraw-Bug gemessen (2026-07-09_prompt)

**Datum:** 2026-07-09
**Plattform:** Windows 11 Enterprise, x86-64 (primäre Entwicklungsmaschine)
**Repro:** echtes `PLT_QT=1 [PLT_QT_DEBUG=1] DrRacket.exe`, SendKeys-Tastatureingabe, Minimieren/Wiederherstellen
**Startrezept:** `PLT_QT=1`, Qt-`bin` in PATH; Fork ist verlinktes Paket → plain `DrRacket.exe` (kein `-S`).

**Kurzfassung:** Zwei Ziele, beide erledigt. (1) Startup-Pfad geflusht: Repo war bereits
auf dem aktuellen `qt-backend`-Stand, Shim neu gebaut, Bytecode neu kompiliert, Clean-Start
mit echtem DrRacket ist sauber (keine neue Landmine). (2) Redraw-Bug wurde mit vier gated
Diagnose-Hooks **gemessen, nicht gefixt** (Guardrail eingehalten). Ergebnis: ein präziser
Root-Cause-Kandidat, gefunden per Code-Vergleich mit den drei funktionierenden Backends
(win32/gtk/cocoa) und live per Messung bestätigt — `wx/qt/canvas.rkt` öffnet nie eine
"retained"-Backing-Bitmap-Sitzung, wodurch jeder Flush-Zyklus die Bitmap verwirft statt sie
über Teil-Invalidierungen (z. B. Caret-Blink) hinweg zu behalten.

## 1. Phase 0 — Umgebung verifiziert

- `racket --version` → **v9.2 [cs]** (gemessen, via `C:\Program Files\Racket\Racket.exe
  --version`, da `racket`/`raco` nicht im PATH lagen — volle Pfade verwendet).
- gui-Submodul (`third_party/gui`, Branch `qt-backend`): war bereits auf `b2369d48`
  (enthält `6df80516` + alle vier Menü-/Startup-Fixes aus den Vorsessions), da der Sync in
  der vorherigen Konversation bereits durchgeführt wurde. Kein Pull nötig.
- Umbrella (`main`): sauber, Submodul-Zeiger deckungsgleich.
- **Shim war veraltet:** `qt-shim/src/shim.cpp` war neuer als die gebaute
  `racketqtshim.dll` (Kommentar-Label-Fix von heute) → `cmake --build
  qt-shim/build/windows-x64 --config Debug` neu ausgeführt.
- **Bytecode neu:** `raco setup mred framework` (Windows nutzt Installation-wide-Link,
  kein `-S`). Ein `delete-file`-Fehler beim Launcher-Rebuild (`mred-text.exe`, fehlende
  Admin-Rechte) ist irrelevant — die eigentliche Bytecode-Kompilation (inkl.
  `mred/private/wx/qt`) lief vorher durch und schrieb die `.zo`-Dateien erfolgreich.
- Re-Smoke: **3/3 grün** (`raco test tests/smoke.rkt`, `PLT_QT=1`).

## 2. Phase 1 — Clean-Start-Check: sauber

Kein laufender DrRacket-Prozess vorab (Single-Instance-Falle geprüft, HACKING §13). Start
via `Start-Process DrRacket.exe` mit `PLT_QT=1`: Hauptfenster kommt nach ~6s hoch, Titel
„Untitled - DrRacket", **9 Menüs** (File/Edit/View/Language/Racket/Insert/Scripts/Tabs/
Help), Editor-Bereich sichtbar, kein Crash-Dialog, Prozess bleibt `Responding=True`.
Screenshot bestätigt. **Ergebnis: sauber beim ersten Start, keine Landmine gezündet.**

## 3. Phase 2 — Redraw-Bug gemessen

### 3.1 Repro

Vier `(define ... N)`-Zeilen via echte Tastatureingabe (Windows `SendKeys`, escaped
Klammern — ein erster Versuch ohne Escaping landete unbeabsichtigt in der Interactions-
Konsole statt im Definitions-Editor, siehe §5) in den Definitions-Editor getippt.
Ergebnis: Zeilennummern-Gutter zeigt korrekt 1-6, aber nur die zuletzt getippte Zeile
(„line-four") ist als Text sichtbar — die Fläche darüber (wo Zeilen 1-4 stehen müssten,
unverschoben, keine Scroll-Position-Änderung) ist weiß. Bug reproduziert.

### 3.2 Vier gated Diskriminatoren (hinter `PLT_QT_DEBUG`, additiv im Code belassen)

Instrumentiert: `qt-shim/src/shim.cpp` (`paintEvent`, `shim_canvas_blit_argb`) und
`wx/qt/canvas.rkt` (`refresh`, `flush`, `begin-refresh-sequence`, `end-refresh-sequence`,
`queue-backing-flush` inkl. `qt-dc%`). Alle Ausgaben sind einmalig pro Aufruf, keine
Loop-Änderung.

1. **`paintEvent` requested vs. blitted:** Für die Editor-Canvas durchgehend
   `requested=(0,0 1400x436) blitted=(0,0 1416x436)` — praktisch deckungsgleich (die
   16px-Differenz ist Rand-Toleranz). Auch kleinere OS-Requests (z. B. `(0,27 30x3)` für
   Toolbar-Icons) werden immer voll geblittet, nie unterdimensioniert.
   → **(A) „Blit-Region zu klein" widerlegt.**
2. **Backing-QImage-Größe/Timing bei jedem Blit:** über mehrere hundert Zyklen (u. a.
   Caret-Blink alle ~500ms) bleibt die Größe für die Editor-Canvas konstant bei voller
   Widget-Größe (`1416x436`, nach Resize `1416x603`) — schrumpft nie. Ein unabhängiger
   69×19-Kanal (vermutlich ein Toolbar-/Caret-Widget) läuft mit fester eigener Größe
   nebenher. → **(B) im Sinne „QImage falsch dimensioniert" widerlegt.**
3. **Racket-seitige Aufrufkette:** jeder Editor-Repaint — auch reines Caret-Blinken —
   läuft komplett über `refresh → queue-paint → queue-backing-flush → on-backing-flush
   (proc fired, volle Bitmap-Größe) → blit_argb → request_repaint`. Der direkte
   `flush`-Pfad (`request_repaint` ohne frischen Blit) feuert 50× im Log, aber
   ausschließlich in den ersten ~4s (Toolbar-Icons beim Start), nie für die
   Editor-Canvas. → **(C) „falscher Repaint-Trigger" für den Editor-Bereich widerlegt.**
4. **Minimieren + Wiederherstellen (erzwingt vollen Expose):** Symptom bleibt
   **unverändert** — die weißen Zeilen kommen nicht zurück, obwohl derselbe volle
   `(0,0 1400x436)`-Zyklus erneut durchläuft. Spricht gegen eine reine Trigger-Frage.

### 3.3 Root-Cause-Kandidat (Code-Vergleich, NICHT gefixt)

`wx/qt/canvas.rkt`s `begin-refresh-sequence`/`end-refresh-sequence` sind `(void)`-No-ops.
Bei win32 (`wx/win32/canvas.rkt:327-330`) und gtk (`wx/gtk/canvas.rkt:644-647`) verdrahten
beide `(send dc suspend-flush)`/`(send dc resume-flush)`; beide rufen zusätzlich einmalig
`(send dc start-backing-retained)` direkt nach der DC-Erzeugung (`wx/win32/canvas.rkt:266`,
`wx/gtk/canvas.rkt:672`). Im Qt-Backend fehlt dieser Aufruf komplett.

Ohne diese Klammerung bleibt `retained-counter` in `backing-dc%` permanent 0, sodass
`on-backing-flush` bei **jedem** `release-cr` sofort `reset-backing-retained` aufruft —
das setzt `retained-cr` auf `#f` zurück. Der nächste `get-cr`-Aufruf legt zwangsläufig
eine **neue, leere** Bitmap an. Eine Teil-Invalidierung (z. B. nur die Caret-Zeile bei
reinem Blinken) geht davon aus, dass der Rest der vorherigen Bitmap noch gültig ist — bei
win32/gtk/cocoa stimmt das (offene `retained`-Sitzung), im Qt-Backend nicht (Bitmap ist
zu diesem Zeitpunkt schon leer). Nur die neu gezeichnete Teil-Region bekommt Inhalt, der
Rest bleibt weiß. Erklärt alle vier Messungen konsistent (voller Trigger + volle Größe,
aber nur teilweise gefüllter Inhalt).

**Einordnung zu den vorgegebenen Hypothesen A-D:** am nächsten an (D) „Racket invalidiert
nur Teilregion" — ergänzt um den strukturellen Befund, warum das bei diesem Backend
(anders als bei win32/gtk/cocoa) sichtbare Lücken hinterlässt.

**Kein Fix in dieser Session.** Naheliegender Fix für die nächste Session:
`start-backing-retained` einmalig nach `qt-dc%`-Erzeugung, plus
`begin-/end-refresh-sequence` auf `suspend-flush`/`resume-flush` — Muster 1:1 aus
`wx/win32/canvas.rkt:266-330` übernehmbar, noch nicht verifiziert.

## 4. Guardrails eingehalten

- Kein `exec()`/`QEventLoop`, keine geschachtelte Schleife.
- cocoa/gtk/win32 nicht angefasst (nur gelesen, zum Vergleich).
- Redraw-Bug: gemessen, nicht gefixt.
- Zwei-Repo-Commits (Submodul zuerst).
- Gated Diagnose bleibt gated (`PLT_QT_DEBUG`).
- Report-Header nutzt gemessene `racket --version`.

## 5. Nebenbefund (kein Bug im Produkt)

Der erste Tipp-Versuch nutzte Windows-`SendKeys` mit unescaped `(`/`)` — SendKeys
interpretiert diese als Sondersyntax, nicht als literale Zeichen. Die Klammern gingen
verloren, und die Tastatureingabe landete zudem (mangels vorherigem expliziten Klick in
den Editor) in der Interactions-Konsole statt im Definitions-Editor, was zu `bad syntax`-
Fehlern in der REPL führte. Kein Produkt-Bug — reiner Fehler im Automatisierungsskript
dieser Session, mit escaped Klammern (`{(}`/`{)}`) und explizitem Fokus-Klick behoben.

## 6. Nächste Schritte

- Redraw-Bug-**Fix** (eigene Session): `start-backing-retained` +
  `suspend-flush`/`resume-flush`-Verdrahtung in `wx/qt/canvas.rkt`, dann erneut mit den
  hier gebauten gated Diskriminatoren verifizieren (Vorher/Nachher-Vergleich).
- Nach Fix: Checkpoint E (Widget-Breite: dialog%, message%, … nach konkretem App-Bedarf).
- macOS/Linux: kein Handlungsbedarf aus dieser Session (keine Fix-Commits, nur Windows-
  seitige Diagnose-Hooks in gemeinsamen `wx/qt/`-Dateien, die beim nächsten Re-Sync
  automatisch mitkommen).

## 7. Commits & Stand

- gui-Submodul (`qt-backend`): gated Diagnose-Hooks in `canvas.rkt` (`refresh`, `flush`,
  `begin-/end-refresh-sequence`, `queue-backing-flush`).
- Umbrella (`main`): gated Diagnose-Hooks in `qt-shim/src/shim.cpp` (`paintEvent`,
  `shim_canvas_blit_argb`), `docs/HACKING.md` §16, `CLAUDE.md`-Checkpoint-Tabelle +
  narrativer Absatz, `STATUS.md`-Eintrag, Submodul-Zeiger-Bump, dieser Bericht
  (`docs/2026-07-09_report.md`).

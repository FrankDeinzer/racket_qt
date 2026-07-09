# Bericht — Redraw-Bug-Validierung + macOS-Nebenbefunde (2026-07-10_prompt, Phase 5/6, macOS)

**Datum:** 2026-07-10
**Plattform:** macOS arm64 (Darwin 25.5.0, `aarch64-macosx/cs`)
**Racket:** v9.2 [cs] (gemessen via `racket --version`)
**Repro:** echtes `PLT_QT=1 PLT_QT_DEBUG=1 racket -S third_party/gui/gui-lib -S third_party/draw/draw-lib -l drracket`,
Tastatureingabe über echte synthetische CGEvent-Keystrokes/-Klicks (kein Accessibility-Klick,
siehe Abschnitt 2).

**Kurzfassung:** Der auf Windows gefixte und auf Linux validierte Redraw-Bug (`docs/HACKING.md`
§16) ist auf macOS **ebenfalls validiert und grün** — alle sieben Zeilen (`#lang racket/base` +
sechs `define`-Zeilen) bleiben durchgehend sichtbar, auch nach Resize und einem
Occlusion-Zyklus. Die macOS-Nebenbefunde aus `docs/2026-07-09_report-macos.md` wurden unter
bestätigtem Light Mode erneut geprüft: **Befund B (Editor-Garble beim ersten Paint) tritt unter
korrekt identifiziertem Light Mode nicht mehr auf** (siehe Abschnitt 3 zur Korrektur der
Theme-Prüfung selbst); **Befund A (8 statt 9 Menüs, „Windows" fehlt) besteht weiterhin**,
unverändert zum 07-09-Befund. Reine Validierungssession, keine Fix-Commits in `wx/qt/`.

## 1. Phase 5 — Sync + Rebuild

- Vor dem Pull verifiziert: einziger Remote `origin`, lokales HEAD (`87ebd078`) strikter
  Vorfahre von `origin/qt-backend` (`04935cb6`), keine lokalen Extra-Commits, Working
  Tree/Index clean, kein zweites Worktree. Nach Nutzer-Bestätigung: `git -C third_party/gui
  pull --ff-only origin qt-backend` → `87ebd078` → `04935cb6`.
- Diff-Check: `git diff --stat 87ebd078 04935cb6` zeigt ausschließlich
  `gui-lib/mred/private/wx/qt/canvas.rkt` (23 Zeilen) — kein `shim.cpp`-Anteil, deckungsgleich
  mit dem im Windows-/Linux-Report beschriebenen Vier-Änderungen-Diff (`start-backing-retained`
  vor dem Seed-`set-size`, `suspend-/resume-flush`-Verdrahtung, `reset-backing-retained` in
  `set-size`, `dc`-Definition vor den Seed-Aufruf verschoben).
- Shim: `cmake --build qt-shim/build/macos-arm64` → „ninja: no work to do" (Fix ist rein
  Racket-seitig, `shim.cpp` unverändert).
- Bytecode: stale `compiled/`-Verzeichnisse in `third_party/gui` + `third_party/draw` entfernt,
  dann `racket -S third_party/gui/gui-lib -S third_party/draw/draw-lib -l raco -- make
  third_party/gui/gui-lib/mred/mred.rkt` — läuft ohne Fehler/Warnungen durch.
- Re-Smoke: **3/3 grün** (einzige Nebenwirkung: harmlose `QThreadStorage: entry 0 destroyed
  before end of thread`-Teardown-Meldung, bereits aus früheren Sessions bekannt).

## 2. Theme-Prüfung — eigener Fehler korrigiert, Light Mode war die ganze Zeit korrekt gesetzt

Bevor der eigentliche Redraw-Test lief, wurde die Vorbedingung „Light Mode explizit gesetzt"
geprüft. **Erster Check war falsch positiv für „Dark Mode":** `~/Library/Preferences/
org.racket-lang.prefs.rktd` zeigt `framework:color-scheme` = `white-on-black` und
`framework:color-scheme-dark` = `white-on-black`. Auf dieser Basis wurde dem Nutzer
fälschlich „Dark Mode aktiv" gemeldet.

**Korrektur nach Quellcode-Lektüre** (`framework/private/color-prefs.rkt`,
`framework/private/wob-color-scheme.rkt`, `framework/private/main.rkt`): `framework:color-scheme`
ist ein **Legacy-Key** (Code-Kommentar: „this preference shouldn't be used any more; we keep it
here only so we can access it's old value"). Der tatsächlich maßgebliche Schalter ist
`framework:white-on-black-mode?` (`#t`/`#f`/`'platform`), ausgewertet in
`white-on-black-color-scheme?`. Dieser Key stand bereits auf **`#f`** — explizit Light Mode,
nicht `'platform`/OS-gesteuert. Die Vorbedingung war also die ganze Zeit erfüllt; kein
Theme-Fix nötig. Dieselbe Verwechslung (Legacy-`color-scheme`-Key statt
`white-on-black-mode?`) erklärt plausibel, warum ein manueller Versuch des Nutzers, das Theme
über die DrRacket-Preferences-UI umzustellen, als „nicht gespeichert" erschien — vermutlich
wurde derselbe falsche Key beobachtet.

**Für künftige Sessions:** der korrekte Diagnosebefehl ist
`(preferences:get 'framework:white-on-black-mode?)`, nicht `framework:color-scheme`.

## 3. Redraw-Repro — grün

### 3.1 Klick-Methode: `System Events click at` erreicht den Qt-Canvas nicht

Der erste Versuch, per `osascript`/System Events (`click at {x, y}`) in den
Definitions-Editor zu klicken, hat den Tastaturfokus **nicht** verschoben — nachfolgende
Keystrokes landeten weiterhin im REPL/Interactions-Fenster (verifiziert per Test-Keystroke
`"X"`, erschien im REPL, nicht im Definitions-Editor). `System Events click at` scheint für
den custom-gezeichneten Qt-Canvas nicht zu funktionieren (vermutlich fehlende/unvollständige
NSAccessibility-Repräsentation des Canvas-Widgets).

**Fix:** kleiner CoreGraphics-Klick-Helfer selbst gebaut (`click.c`, gegen
`ApplicationServices` gelinkt, `CGEventCreateMouseEvent`/`CGEventPost` auf
`kCGHIDEventTap` — echte synthetische Maus-Events, analog zum XTest-Helfer aus der
Linux-Session). Damit hat der Klick den Fokus korrekt in den Definitions-Editor verschoben
(verifiziert: Test-Keystroke landete an der erwarteten Position).

### 3.2 Repro-Ergebnis

6× `(define line-N N)` + `#lang racket/base` (Zeile 1, vorhanden) über echte
`keystroke`-Events (System Events, nach korrektem Fokus-Wechsel via CGEvent-Klick) in ein
frisches `Untitled`-Fenster getippt.

- **Alle sieben Zeilen bleiben durchgehend sichtbar** (`#lang racket/base`,
  `line-one` … `line-six`), korrektes Gutter 1–8, kein weißer Bereich.
- **Debug-Log bestätigt den Fix-Pfad aktiv:** `[qt-canvas] begin-refresh-sequence ->
  suspend-flush` / `end-refresh-sequence -> resume-flush` feuern (1870 Treffer über die
  Session) statt der alten `(no-op)`-Meldungen.
- **Diskriminator:** `bm=`-Größe in den `on-backing-flush`-Logs bleibt bei der vollen
  Widget-Größe (`bm=1363x405`) und fällt nie auf eine Platzhaltergröße zurück — identisch
  zum Windows-/Linux-Nachher-Ergebnis.
- **Resize** (1440×900 → 1100×750 via System-Events-Fenstergröße): Inhalt bleibt
  vollständig erhalten.
- **Occlusion-Zyklus** (Finder aktivieren → wieder DrRacket frontmost): Inhalt bleibt
  pixelidentisch erhalten.
- **Minimieren nicht sauber testbar:** `set minimized of window 1` schlägt mit einem
  AppleScript-Typkonvertierungsfehler fehl (-1700); das Qt-Fenster exponiert die
  Standard-`AXMinimizeButton`-Semantik der Titelleiste offenbar nicht vollständig gegenüber
  Accessibility. Ein blinder `click button 2 of window 1`-Versuch traf stattdessen einen
  echten, aber unabhängigen internen „Undock"-Button eines Test-Engine-Panels und löste
  einen `DrRacket Internal Error`-Dialog aus (`preferences:set: new value doesn't satisfy
  preferences:set-default predicate`, `pref symbol: 'test-engine:test-dock-size`) — **ein
  Artefakt der eigenen Automatisierung** (falscher Button-Index), kein durch normale
  Nutzung erreichbarer Pfad, nicht weiter verfolgt (Dialog geschlossen, Editor-Inhalt
  dabei unangetastet). Der eigentliche Minimieren/Wiederherstellen-Test wurde durch den
  Occlusion-Zyklus (Finder-Fokus-Wechsel) ersetzt, der dasselbe Expose-Verhalten prüft
  und eindeutig grün ist.
- **Re-Smoke nach dem gesamten Test:** **3/3 grün.**

## 4. macOS-Nebenbefunde erneut geprüft (Phase 6)

### 4.1 Befund B (Editor-Garble beim ersten Paint) — reproduziert sich unter bestätigtem Light Mode NICHT

Der Clean-Start-Screenshot (vor jeder Eingabe) zeigt einen sauberen Editor: `#lang
racket/base`, korrektes Gutter, keine schwarzen Balken, kein überlappender Text — identisch
zum erwarteten Windows-/Linux-Baseline-Bild. Der ursprüngliche 07-09-Befund („schwarzer
Balken über der `#lang`-Zeile, verschachtelte Statuszeile") lässt sich mit derselben
Maschine, demselben Submodul-Stand-Familie und jetzt korrekt identifiziertem Light Mode
**nicht reproduzieren**. Plausibelste Erklärung: derselbe Legacy-Key-Fehlgriff wie in
Abschnitt 2 — der 07-09-Bericht dürfte ebenfalls den falschen `color-scheme`-Key geprüft und
tatsächlichen Dark-Mode-Zustand als „Light Mode, aber verzerrt" fehlgedeutet haben. Dies ist
eine Einordnung, keine lückenlos rekonstruierte Kausalkette (der exakte Theme-Zustand der
07-09-Session ist nicht mehr nachträglich feststellbar) — aber sie passt zum jetzt beobachteten
Bild besser als eine separate, seitdem verschwundene Rendering-Regression.

### 4.2 Befund A (8 statt 9 Menüs, „Windows" fehlt) — besteht weiterhin, unverändert

`osascript -e '… get name of menu bar items of menu bar 1'` liefert weiterhin:
`Apple, racket, File, Edit, View, Language, Racket, Insert, Scripts, Help` — **8** App-Menüs,
identisch zum 07-09-Befund. Kein Fix versucht (Guardrail: nur beobachten). Einordnung aus dem
Prompt geprüft: Cocoa befüllt das „Window"-Menü bei einem Qt-Backend nicht automatisch (das ist
kein natives Cocoa-`NSApplication`-Feature, das hier greifen würde, da die Menüleiste komplett
über den Qt-Shim aufgebaut wird, nicht über natives `NSMenu`-Autofill) — die „bei nur einem
offenen Fenster ist ein fehlendes Windows-Menü normal"-Erklärung aus dem Prompt passt hier nicht
sauber, weil dieses Menü hier durch Racket-Code (Insert/Scripts/Windows/Help-Konstruktion in
`framework`/`drracket`) explizit erzeugt werden sollte, nicht von macOS injiziert wird. Bleibt
damit ein **ungeklärter Datenbefund**, nicht als „plausibel normal" eingeordnet — weiterhin
offener Punkt für eine eigene, kleine Diagnose-Session (out of scope hier, Guardrail: nicht
fixen).

## 5. Guardrails eingehalten

- Kein `exec()`/`QEventLoop`, keine geschachtelte Schleife.
- cocoa/gtk/win32 nicht angefasst (nur zum Vergleich gelesen im Rahmen der
  Theme-Pref-Recherche, `framework/private/*.rkt` sind Backend-unabhängiger
  Framework-Code, kein Platform-Backend).
- Sync-Schritt (`pull --ff-only`) vorab per `AskUserQuestion` bestätigt.
- Theme-Fehleinschätzung wurde vor jeder Fix-Handlung korrigiert und dem Nutzer
  transparent gemeldet, bevor weitergemacht wurde.
- Gated Diagnose bleibt gated (`PLT_QT_DEBUG`); keine neuen Diagnose-Hooks im Code
  hinzugefügt (nur externe Test-Tooling in der Scratchpad, nicht im Repo).
- Beide macOS-Nebenbefunde: nur beobachtet, nicht gefixt.
- Reine Validierung — keine Fix-Commits in `wx/qt/`.
- Report-Header nutzt gemessene `racket --version`.

## 6. Commits & Stand

- gui-Submodul (`qt-backend`): ff-Pull `87ebd078` → `04935cb6`, keine neuen Commits.
- Umbrella (`main`): dieser Bericht, `docs/HACKING.md` §16 (macOS-Validierung ergänzt,
  Redraw-Zeile auf allen drei Plattformen grün), `CLAUDE.md`-Checkpoint-Update (Redraw
  geschlossen, E-0 vollständig), `STATUS.md`-Eintrag.

## 7. Nächste Schritte

- Redraw-Bug ist jetzt auf allen drei Plattformen (Windows/macOS/Linux) validiert und
  geschlossen. **E-0 damit vollständig** (Menüs + Redraw).
- Offene Nebenbefunde für eigene, spätere Sessions:
  - macOS Befund A (fehlendes „Windows"-Menü, 8 statt 9) — eigener Diagnose-Schritt.
  - Linux Resize-/Minimieren-Verhalten unter KWin/X11 — ungeklärt, siehe
    `docs/2026-07-10_report-linux.md` Abschnitt 3.
  - Vorbestehender Windows-Nebenbefund (Toolbar-Save-Icon-Timing) — `wx/qt/button.rkt`,
    separates Thema.
- **Checkpoint E** (Widget-Breite: `dialog%`, `message%`, …) ist der nächste
  Haupt-Meilenstein.

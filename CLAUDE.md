# CLAUDE.md — racket-qt

Qt Widgets backend ("wx/qt/") für `racket/gui`. Additiver Spike: aktiviert via `PLT_QT=1`, bestehende Backends (cocoa/gtk/win32) **nicht anfassen**.

## Fixe Regeln — niemals brechen

1. **Kein `QApplication::exec()`**, kein eigenes `QEventLoop`. Racket treibt die Loop; Qt wird gepumpt via `shim_pump(int max_ms)`.
2. **C→Racket-Callbacks** immer mit `#:atomic? #t` + `#:async-apply`. Sie dürfen **nur** Events in den Eventspace **posten**, niemals synchron aufrufen.
3. **`public*`/`override*`-Invariante:** Methoden, die ein Glue-Layer via `public*` hinzufügt, dürfen **nicht** in Platform-Klassen definiert sein (→ `method already defined`). Methoden, die via `override*` erwartet werden, **müssen** in der Platform-Klasse stehen (→ `no method to override`). Volle Tabelle: `docs/HACKING.md §1`.
4. **`queue-backing-flush` gibt `(void)` zurück** — nicht den Rückgabewert von `on-backing-flush`, sonst bricht `resume-flush`s `(->m void?)`-Kontrakt.
5. **`frame%.direct-show` ruft `register-frame-shown`** auf — sonst beendet sich das Programm sofort, weil der Eventspace keine offenen Fenster sieht.
6. **Zwei-Repo-Commits:** Änderungen an `wx/qt/` landen im gui-Submodul (`third_party/gui`, Branch `qt-backend`), dann Submodul-Zeiger im Umbrella (`main`) nachziehen.
7. **Drei-Maschinen-Sync ist immer Teil der Aufgabe:** Es gehört zu jeder Session dazu, sicherzustellen, dass Umbrella (`main`) und gui-Submodul (`qt-backend`) über alle drei Entwicklungsmaschinen (Windows/macOS/Linux) hinweg synchron sind — nicht nur lokal committen und den Sync als offenen Punkt stehen lassen. **Vor jedem Sync-Schritt (Pull/Push/Rebase auf einer Maschine) den Nutzer fragen, ob das jetzt gemacht werden soll** — nicht automatisch durchziehen und nicht als TODO für später notieren.
8. **Submodul-Commit-Reihenfolge:** Der Umbrella-Zeiger auf `third_party/gui` darf **nur** auf einen SHA zeigen, der bereits auf `origin/qt-backend` existiert. Reihenfolge zwingend: (1) Submodul-Branch syncen, **bevor** ein neuer Submodul-Commit entsteht, (2) im Submodul committen, (3) Submodul **pushen**, (4) erst dann den Umbrella-Pointer-Commit erstellen+pushen. Sobald ein Submodul-Commit von irgendeinem Umbrella-Commit referenziert wurde (auch nur lokal, noch ungepusht), darf er **nie mehr umgeschrieben werden** (kein `rebase`/`commit --amend`), ohne den alten SHA vorher als Tag zu pushen — sonst friert der Umbrella dauerhaft einen nicht mehr fetchbaren Commit ein (`fatal: remote error: upload-pack: not our ref …` bei jedem künftigen `git pull --recurse-submodules`). Incident + Fix: `docs/HACKING.md §17`.

## Umgebung

### Windows (primäre Entwicklungsmaschine)

| | |
|---|---|
| Racket | v9.2 [cs], x86-64 |
| Qt | 6.11.0, `C:\Qt\6.11.0\msvc2022_64` |
| CMake | 4.2.3, Generator "Visual Studio 17 2022" |
| Preset | `windows-x64` → `qt-shim/build/windows-x64` |

### macOS arm64

| | |
|---|---|
| Racket | v9.2 [cs], arm64 (Homebrew) |
| Qt | 6.11.0, `~/Qt/6.11.0/macos` |
| CMake | Ninja, Generator "Ninja" |
| Preset | `macos-arm64` → `qt-shim/build/macos-arm64` |

## Build

**Windows:**
```powershell
cmake --preset windows-x64 -S qt-shim
cmake --build qt-shim/build/windows-x64 --config Debug
```

**macOS:**
```bash
cmake --preset macos-arm64 -S qt-shim
cmake --build qt-shim/build/macos-arm64
```

**Linux:**
```bash
cmake --preset linux-x64 -S qt-shim
cmake --build qt-shim/build/linux-x64
```

## Run / Smoke-Test

**Windows:**
```powershell
$env:PLT_QT = "1"
$env:PATH   = "C:\Qt\6.11.0\msvc2022_64\bin;" + $env:PATH
racket examples/hello.rkt
```

**Windows — echtes DrRacket (seit Fork == gui-lib 1.80, verlinktes User-Paket):**
```powershell
$env:PLT_QT = "1"
$env:PATH   = "C:\Qt\6.11.0\msvc2022_64\bin;" + $env:PATH
& "C:\Program Files\Racket\DrRacket.exe"
```
Kein `-S`-Flag mehr nötig — der Fork ersetzt die System-`gui-lib` per Link
(`raco pkg update --link third_party/gui/gui-lib`, einmalig, braucht Admin-Rechte).
Gate-Test dafür: DrRacket **ohne** `PLT_QT` muss weiterhin nativ starten (kein
Linklet-Mismatch). Single-Instance-Falle: ein zweiter Aufruf bei bereits laufender
Instanz startet nichts Neues (Exit 0, kein Fenster) — vorher `tasklist | grep drracket`
prüfen. Details/Fallstricke (Autosave-Recovery bei hartem Kill etc.): `docs/HACKING.md §13`.

**macOS / Linux:**
```bash
PLT_QT=1 QT_PLUGIN_PATH=~/Qt/6.11.1/gcc_64/plugins \
  racket -S third_party/gui/gui-lib -S third_party/draw/draw-lib examples/hello.rkt
# Smoke tests:
PLT_QT=1 QT_PLUGIN_PATH=~/Qt/6.11.1/gcc_64/plugins \
  racket -S third_party/gui/gui-lib -S third_party/draw/draw-lib -l raco -- test tests/smoke.rkt
```
(macOS: QT_PLUGIN_PATH nicht nötig; Linux: xcb-Plugin über `QT_PLUGIN_PATH` setzen)

## Aktueller Checkpoint-Status

| Checkpoint | Status |
|---|---|
| A – Stub-Shim lädt via FFI | ✅ |
| B – Architektur dokumentiert | ✅ |
| C – frame% + canvas% + button% laufend | ✅ 2026-06-24 |
| **D – Eingabe-Rückgrat + Editor-Smoke** | **✅ 2026-06-25** |
| **macOS Smoke** | **✅ 2026-06-25** |
| **Linux Smoke** | **✅ 2026-06-29** |
| **E-0 – Widget-Stubs + text-field% fix** | **✅ 2026-06-30** |
| **E-0 – gui-lib-Angleich 1.78→1.80 + echtes DrRacket** | **✅ 2026-07-08 (E-0-Menü geschlossen: Tippen/Enter/Ausführen funktioniert; Menüleiste sichtbar+horizontal [Titel-Fix] UND gefüllt [addAction-Fix] UND Popups korrekt platziert [mapToGlobal-Fix], auf Windows+macOS+Linux bestätigt; je ein zusätzlicher Startup-Crash auf macOS [`tab-panel%` `set-label`-Arity] und Linux [`frame%` `set-icon` fehlte] gefunden+gefixt; Redraw-Bug separat offen, eigene Session)** |
| **Redraw-Bug — Windows gefixt, Linux/macOS-Validierung offen** | **🟡 2026-07-10 (Windows: gefixt + visuell bestätigt — `start-backing-retained` + `suspend-/resume-flush` [Prompt] plus zwei zusätzlich nötige Änderungen: `reset-backing-retained` bei `set-size`-Resize, Konstruktor-Reihenfolge-Fix für `dc`. Details `docs/HACKING.md` §16, `docs/2026-07-10_report-win.md`. Linux/macOS müssen denselben Codepfad noch nachziehen+validieren, dann E-0 vollständig geschlossen [Menüs + Redraw])** |
| E – Widget-Breite (dialog%, message%, …) | ⬜ |

**Checkpoint D — erledigt:**
- **D-0:** Layout-Refactor — `QVBoxLayout` raus, `shim_widget_set_geometry()` rein, `panel%` real
- **D-1:** Maus/Tastatur/Fokus-Callbacks + `key-map.rkt` + Timer-Smoke + `examples/input.rkt`
- **D-2:** `editor-canvas%` + `text%` tippen/selektieren/Caret blinkt ✅

**macOS Smoke — erledigt:**
- CMake `macos-arm64` Preset + Ninja Build funktioniert
- Shim lädt via FFI (full absolute path inkl. `lib`-Prefix nötig)
- `designate-root-frame` Stub für Racket 9.2 Kompatibilität
- CPU-Spin-Fix: `shim_pump(0)` statt `shim_pump(10)` — verhindert CFRunLoopRunInMode-Konflikt mit Racket CS mach-port sleep
- 3/3 Smoke-Tests pass; hello/input/editor laufen bei <5% Idle-CPU

**Linux Smoke — erledigt:**
- CMake `linux-x64` Preset: Qt-Pfad auf `~/Qt/6.11.1/gcc_64` korrigiert (war `/opt/Qt/6.11.0/gcc_64`)
- QPA-Plugin: xcb (`libqxcb.so`) lädt sauber via `QT_PLUGIN_PATH`; kein libxcb-cursor-Problem
- Loop-Dritter-Datenpunkt: `shim_pump(0)` funktioniert auf Linux (glib/epoll) — <2% Idle-CPU nach Startup
- Startup-CPU-Spike ist Bytecode-Kompilation (fallend: 85% → 1% über 12s); kein Loop-Spin
- Kein neuer Racket-Code nötig: macOS-Fixes (`.so`-Pfad, shim_pump(0), events_pending→0) direkt geerbt
- 3/3 Smoke-Tests pass; hello/input/editor starten fehlerfrei

**Checkpoint E-0 — erledigt (2026-06-30):**
- `make-stub-class`: Parent aus `args` extrahiert, `(error ...)` entfernt, `on-combo-select(i)` + `set-callback` Stubs
- `canvas.rkt`: `get-width`/`get-height` Override entfernt (Qt-Default 100×30 auf Windows fälschlich als "same" erkannt); Seed-Call in Konstruktor setzt `window%`'s `w/h` korrekt
- `canvas.rkt`: Combo-Box-Interface (`on-combo-select`, `popup-combo`, `clear-combo-items`, `append-combo-item`, `set-combo-text`) für `text-field%`
- `message.rkt`: Echte Implementierung (QLabel via `shim_label_create`)
- `utils.rkt`: FFI-Bindings `shim_label_create`/`shim_label_set_text`
- Widget-Probe 8/8 pass: `message%`, `check-box%`, `choice%`, `list-box%`, `slider%`, `radio-box%`, `tab-panel%`, `text-field%`
- 3/3 Smoke-Tests weiterhin pass

**Checkpoint E-0 / gui-lib-Angleich — erledigt (2026-07-02):**
- Fork gemergt auf exakten Upstream-Commit von System-gui-lib 1.80 (`3f0037c0`), 0 Konflikte, `wx/qt/**` unberührt
- `gui-lib` als Installation-scope-Link aktiv; Gate-Test bestanden (natives DrRacket ohne `PLT_QT` startet ohne Linklet-Mismatch)
- `PLT_QT=1 drracket` läuft: 9 Crashes + 2 grundlegende Key/Focus-Bugs gefunden und gefixt (Details: `docs/CHECKPOINT-E0-ledger.md`) — u.a. doppelte Zeichen beim Tippen (Key-Release-Kontrakt) und Enter ohne Wirkung (`get-focus-window` nie getrackt)
- Tippen, Enter/Zeilenumbruch und Code-Ausführung funktionieren in Definitions- und Interactions-Editor
- **Offen (Flags für E-1):** Menüleiste visuell nicht sichtbar (Daten/Wiring nachweislich korrekt — 165 Menüpunkte gebaut); Popup-Positionierung falsch (`client-to-screen` No-op, fehlender `mapToGlobal`-Shim); teilweises Neuzeichnen im Editor-Bereich (nicht root-caused)
- **Drei-Maschinen-Pflicht-Folgeschritt:** macOS/Linux müssen `qt-backend` (jetzt `381425d5`) + Umbrella `main` neu ziehen und **beide** `raco setup` laufen lassen (gui-lib hat sich strukturell verändert), dann re-smoken

**Checkpoint E-0 / Menüleiste — erledigt + neu diagnostiziert (2026-07-08):**
- **Titel-Fix erledigt (Windows bestätigt, gepusht):** leerer `QMenu`-Titel kollabierte den Balken auf Höhe 0 (gemeinsamer Racket-Pfad); Fix = Titel via `shim_menu_set_title` durchreichen (`wx/qt/menu-bar.rkt` `append`). Balken jetzt horizontal sichtbar in `menu-frame.rkt` UND echtem DrRacket.
- **Klick-Bug neu diagnostiziert (weiterhin offen, NICHT gefixt):** ursprüngliche Annahme „Klick öffnet nie ein Dropdown" war ein Artefakt eines Blatt-only-Testmenüs. Realer Befund: Dropdowns erscheinen für Menüs mit Submenü-Kindern, aber nur die Submenü-Einträge sind sichtbar — Blatt-Items fehlen komplett, weil `shim_action_create` (`qt-shim/src/shim.cpp`) seine `QAction` nie per `addAction`/`insertAction` zum `QMenu` hinzufügt (nur `shim_menu_add_submenu`s `addMenu()` tut das). Verifiziert per gated Probe (`examples/menu-click-probe.rkt`), Details: `docs/HACKING.md` §14.
- **mapToGlobal/Redraw:** weiterhin offen, unverändert.
- **Fix für den Klick-Bug ist Spur 2** (nächste Session, Cross-Platform-Daten + Review nötig — Guardrail dieser Session war „messen, nicht fixen").

**Checkpoint E-0 / Spur 2 — addAction-Fix + mapToGlobal-Fix erledigt (2026-07-08, 2026-07-08_prompt-3, Windows bestätigt):**
- **addAction-Fix (gui `0be24d85`, Umbrella `71b7347`):** `shim_action_create` fügte die `QAction` nie per `addAction()` zum Menü hinzu (Root Cause aus `docs/HACKING.md` §14 bestätigt). Fix: Signatur bekommt `menu`-Parameter, Action wird ans Menü geparentet (Lifetime/Ownership — `addAction` übernimmt laut Qt-Doku kein Ownership) und per `menu->addAction(a)` eingefügt, gespiegelt am `shim_menu_add_submenu`-Pfad. Verifiziert per Probe (`direct`/`mixed`/neuem `dynamic`-Modus) und echtem DrRacket (File-/Edit-Menü vollständig gefüllt, Separatoren/Checkables/Enable-Disable korrekt) — Details `docs/HACKING.md` §15.
- **mapToGlobal-Fix (gui `1641f888`, Umbrella `8e0bfac`):** neue Shim-Funktion `shim_widget_client_to_screen` (`QWidget::mapToGlobal`), verdrahtet in `wx/qt/window.rkt`s `client-to-screen`. Verifiziert: Rechtsklick-Kontextmenü in echtem DrRacket öffnet jetzt am Klickpunkt statt am Fensterrand. `screen-to-client` bleibt No-op (ungenutzt in diesem Backend). Details `docs/HACKING.md` §15.
- Smoke 3/3 weiterhin grün nach beiden Fixes, kein Ownership-Crash/-Warning.
- **OFFEN:** macOS/Linux müssen `qt-backend` (jetzt `1641f888`) + Umbrella `main` (jetzt `8e0bfac`) neu ziehen, Shim **neu bauen** (beide Fixes ändern `shim.cpp` — stale-Shim-Falle 07-07) und re-smoken; Nutzer-Visual-Bestätigung (Checkpoint B) für beide Fixes steht noch aus. Redraw-Bug weiterhin separat offen (eigene Session).

**Checkpoint E-0 / Spur 2 — Cross-Platform-Validierung abgeschlossen (2026-07-08, 2026-07-08_prompt-4, macOS + Linux bestätigt, E-0-Menü geschlossen):**
- **macOS** (`docs/2026-07-08_report-4-macos.md`): addAction-/mapToGlobal-Fix per Probe + echtem DrRacket bestätigt (grün). Dabei neuer, unabhängiger Startup-Crash gefunden: `tab-panel%`-Stub-`set-label` erwartete 1 Arg, DrRacket ruft mit 2 (Index+Label) — Fix macht `set-label` variadic (gui `ba2dacc9`), auf Nutzer-Anweisung.
- **Linux** (`docs/2026-07-08_report-4-linux.md`): addAction-/mapToGlobal-Fix per Probe + echtem synthetischem Klick (`libXtst`) in echtem DrRacket bestätigt (grün, Debug-Dump + `xwininfo`-Geometrie als Nachweis). Dabei neuer, unabhängiger Startup-Crash gefunden: `wx/qt/frame.rkt` hatte **keine** `set-icon`-Methode (win32/gtk/cocoa haben sie alle), `framework/splash.rkt` ruft sie bei jedem Start — Fix fügt variadic No-op-Stub hinzu (gui `6df80516`), auf Nutzer-Anweisung (`AskUserQuestion`).
- Beide Zusatz-Crashes betreffen ausschließlich `wx/qt/` und sind reine No-op-Stubs für Methoden, die dieses Backend bisher schlicht nicht kannte — kein Verhalten für bestehende Aufrufer geändert.
- **E-0-Menü damit auf allen drei Plattformen (Windows/macOS/Linux) vollständig geschlossen.** Redraw-Bug bleibt separat offen (eigene Session). Windows sollte vor nächstem Re-Sync über die beiden neuen Fixes informiert werden.

**Redraw-Bug — Windows-Messung, kein Fix (2026-07-09, `docs/2026-07-09_prompt.md`):**
- **Repo-Sync (Phase 0):** Windows war bereits auf `qt-backend` `b2369d48` (enthält alle vier Menü-/Startup-Fixes); Shim neu gebaut (`shim.cpp`-Kommentar-Fix war neuer als die DLL), `raco setup mred framework` neu kompiliert. Smoke 3/3 grün.
- **Clean-Start-Check (Phase 1): sauber beim ersten Start.** Echtes `PLT_QT=1 DrRacket.exe`: 9 Menüs, Editor sichtbar, kein Crash — keine neue Landmine gezündet.
- **Redraw-Bug gemessen (Phase 2), vier gated Diskriminatoren hinter `PLT_QT_DEBUG` (additiv, in `qt-shim/src/shim.cpp` + `wx/qt/canvas.rkt` — bleiben im Code, wie die bestehende Menü-Diagnose):**
  1. `paintEvent`-Requested- vs. Blit-Rechteck: Blit deckt **immer** die volle Widget-Fläche ab (nie zu klein) — (A) widerlegt.
  2. Backing-QImage-Größe über Zyklen: bleibt **immer** voll widget-groß, schrumpft nie — (B) im Sinne „falsche Größe" widerlegt.
  3. Racket-seitige Aufrufkette: jeder Editor-Repaint (auch reines Caret-Blinken) läuft vollständig `refresh → queue-paint → queue-backing-flush → blit_argb`, kein isolierter `request_repaint` ohne frischen Blit für die Editor-Canvas — (C) widerlegt.
  4. Fenster minimieren+wiederherstellen (voller Expose): Symptom **bleibt unverändert** — spricht gegen „falscher Trigger" und für einen strukturellen Bitmap-Lifecycle-Fehler.
- **Root-Cause-Kandidat (Code-Vergleich, noch nicht gefixt):** `wx/qt/canvas.rkt`s `begin-refresh-sequence`/`end-refresh-sequence` sind No-ops; win32/gtk/cocoa verdrahten beide auf `dc.suspend-flush`/`resume-flush`. Zusätzlich fehlt der einmalige `(send dc start-backing-retained)`-Aufruf nach DC-Erzeugung (bei den drei anderen Backends vorhanden). Ohne diese Klammerung wird `retained-cr` nach jedem einzelnen Flush verworfen (`backing-dc%`s `reset-backing-retained`) statt über eine ganze Repaint-Sequenz hinweg erhalten — jede Teil-Invalidierung (z. B. nur die Caret-/aktuelle Zeile) landet dadurch auf einer frisch geleerten Bitmap, der Rest bleibt weiß. Details/Messwerte: `docs/HACKING.md` §16.
- **Kein Fix in dieser Session (Guardrail eingehalten).** Fix ist die nächste Session, mit diesem gemessenen Mechanismus als Ausgangspunkt.
- **Linux (2026-07-09, `docs/2026-07-09_report-linux.md`):** Phase 0/1 desselben Prompts nachgezogen — Submodul-Sync (`6df80516`→`87ebd078`, nach Rückfrage), Shim neu gebaut, Bytecode neu, Re-Smoke 3/3 grün, echter `PLT_QT=1`-DrRacket-Start sauber (9 Menüs, kein Crash, keine neue Landmine). Phase 2 (Redraw-Messung) ist laut Prompt Windows-exklusiv, hier nicht wiederholt.
- **macOS (2026-07-09, `docs/2026-07-09_report-macos.md`): Phase 0 grün, Phase 1 NICHT sauber — zwei Befunde, kein Fix (Guardrail).** Submodul-Sync (`ba2dacc9`→`87ebd078`, nach ausführlicher Sicherheitsprüfung + Rückfrage), Shim neu gebaut, Bytecode neu, Re-Smoke 3/3 grün. Echter `PLT_QT=1`-DrRacket-Start zeigt **kein** Missing-Method-Crash, aber zwei unabhängige Abweichungen: (1) Menüleiste zeigt nur 8 statt 9 Menüs (`Windows` fehlt, per `osascript` gegen die native `NSMenu` verifiziert — Daten-Befund, keine Regression durch den heutigen Sync laut Code-Diff, Ursache offen); (2) Editor-Bereich ist bereits beim allerersten Paint (vor jeder Eingabe) verzerrt (schwarze Balken, überlappender Text, pixelidentisch über 2 Screenshots) — plausibel dieselbe Bug-Familie wie der Windows-Redraw-Bug, aber früher/anders manifestierend; Diagnose-Hooks aus dem Pull als Ursache per Code-Diff ausgeschlossen (strikt `PLT_QT_DEBUG`-gated). Beide Befunde fließen als Cross-Platform-Datenpunkte in die geplante Redraw-Fix-Session ein.

**Redraw-Bug — Windows gefixt (2026-07-10, `docs/2026-07-10_prompt.md`):**
- **Fix ist vier Änderungen, nicht zwei.** Der im Prompt vorgeschriebene 2-Schritt-Fix
  (`start-backing-retained` einmalig + `begin-/end-refresh-sequence` → `suspend-/resume-
  flush`) reichte **allein nicht** — angewendet ohne die beiden folgenden Ergänzungen
  rendert bereits der normale Programmstart (vor jeder Eingabe) einen leeren Editor statt
  `#lang racket`, weil win32/gtk noch einen dritten Baustein haben, den die
  Kandidaten-Analyse vom 07-09 nicht nannte:
  1. `(send dc reset-backing-retained)` im `set-size`-Override — sonst bleibt die jetzt
     retained Bitmap für immer auf der allerersten (oft winzigen Platzhalter-)Größe
     eingefroren, die vor dem ersten Layout-Durchlauf existierte. win32/gtk lösen das über
     ihre eigenen Resize-Hooks (`on-resized`/`internal-on-client-size` → `reset-dc`).
  2. Konstruktor-Reihenfolge: `(define dc ...)` musste vor den Seed-`set-size`-Aufruf im
     Konstruktor verschoben werden — sonst `dc: undefined; cannot use field before
     initialization`-Crash beim Start (reines Racket-Klassenfeld-Ordering, kein
     Qt-Problem, aber nur sichtbar, weil `set-size` jetzt `dc` anfasst).
- **Vorher/Nachher visuell bestätigt (Nutzer):** identischer Tipp-Repro (6× echte
  Keystrokes) — vorher nur letzte Zeile sichtbar, Rest weiß; nachher alle Zeilen +
  `#lang racket` durchgehend sichtbar. Zusätzlich verifiziert: Resize, Minimieren/
  Wiederherstellen, Smoke 3/3. Diskriminator: `bm=`-Größe in den Flush-Logs wächst jetzt
  mit dem Inhalt (`854x316`→`854x377`→`854x437`) statt bei jedem Zyklus auf eine
  Platzhaltergröße zurückzufallen. Details `docs/HACKING.md` §16,
  `docs/2026-07-10_report-win.md`.
- Nebenbefund (nicht verfolgt, vorbestehend, nicht durch diesen Fix verursacht): ein
  Toolbar-Icon (Save) erscheint abhängig vom Zeitpunkt des letzten vollen Repaint-Zyklus
  — betrifft `wx/qt/button.rkt` (native Widget-Klasse, nicht `canvas%`/`backing-dc%`).

**Nächster Schritt: Linux (Validierung) → macOS (Validierung + macOS-Nebenbefunde) laut
`docs/2026-07-10_prompt.md` Phase 4/5 → danach Checkpoint E** — Widget-Breite nach
konkretem App-Bedarf. Da der Fix vier statt zwei Änderungen umfasst, müssen die
Validierungs-Sessions gegen den tatsächlichen Diff prüfen, nicht nur gegen die
ursprüngliche 2-Schritt-Beschreibung. Zusätzlich offen: macOS-Menüleisten-Diskrepanz
(8 statt 9 Menüs, `Windows` fehlt) separat klären, siehe `docs/2026-07-09_report-macos.md`.

## Dokumentation

| Datei | Inhalt |
|---|---|
| `docs/ARCHITECTURE.md` | Widget-Mapping, Shim-API, Event-Loop-Verdrahtung, Pixel-Format |
| `docs/HACKING.md` | `public*/override*`-Tabellen, Klassen-Ketten, Debugging-Guide, Checkliste neue Widgets |
| `docs/CHECKPOINT-D.md` | Detaillierter Plan für D-0 / D-1 / D-2 |
| `docs/BRIEF.md` | Originalbrief mit allen fixen Entscheidungen |

**Namenskonvention für datierte Prompt-/Report-Dateien:** `docs/JJJJ-MM-TT_prompt[-N].md` /
`docs/JJJJ-MM-TT_report[-N][-plattform].md` (ISO-Datum zuerst, damit Name-Sortierung =
Zeit-Sortierung). Reports bekommen **immer** ein Plattform-Suffix (`-win`, `-macos`,
`-linux`), auch wenn die Session nur auf einer Maschine lief — z. B.
`2026-07-09_report-win.md`. Zu jedem `*_prompt*.md` gehört ein passendes `*_report*.md`.

## Shim-Konventionen

- Shim-Handles (`void*`) im `handle`-Feld von `window%` (aus `wx/qt/window.rkt`)
- Alle FFI-Bindings in `wx/qt/utils.rkt`
- Shim bleibt minimal: nur das, was der aktuelle Milestone braucht
- Pixelformat: `CAIRO_FORMAT_ARGB32` ↔ `QImage::Format_ARGB32_Premultiplied`; `stride` aus `cairo_image_surface_get_stride()` (nie `width*4` annehmen)

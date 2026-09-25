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

## Subagent-Modellwahl

Bei Agent-Aufrufen (Tool `Agent`, `subagent_type` ≠ `fork`) bewusst das schwächste
Modell wählen, das für die Aufgabe ausreicht — nicht pauschal, sondern nach Art der
Aufgabe:

- **Haiku genügt** für rein mechanische, deterministische Schritte: ein Build-/Test-
  Kommando ausführen und dessen Exit-Code/Output stumpf auf Pass/Fail prüfen
  (`raco test`, `cmake --build`, Smoke-Test-Skripte mit klarer Erfolgsmeldung),
  Datei-Existenz-/Grep-Checks, stures Ausführen einer exakt vorgegebenen Befehlsfolge.
- **Sonnet (Default) oder stärker** für alles, was Interpretation oder Urteilsvermögen
  braucht: GUI-Automatisierung (`xdotool`/AppleScript/UI Automation), Screenshots
  visuell auswerten, entscheiden ob ein Befund ein echter Bug oder ein
  Automatisierungsartefakt ist, Root-Cause-Suche, Diffs/Code reviewen, Reports
  schreiben. Dieses Projekt hat wiederholt gezeigt, dass genau diese Unterscheidung
  (Artefakt vs. echter Bug) nicht trivial ist — mehrere §-Einträge im Status unten
  wurden erst nach Nachmessen korrekt eingeordnet (z. B. Tools-Listbox-Klick,
  `docs/HACKING.md §51.2`). Im Zweifel hierher tendieren.
- Modellwahl über den `model`-Parameter des `Agent`-Tools setzen (`haiku`, `sonnet`,
  `opus`). Bei Unsicherheit, ob eine Testaufgabe rein mechanisch ist: lieber Sonnet
  nehmen. Forks (`subagent_type: "fork"`) laufen immer mit dem Modell der aufrufenden
  Session — dort ist `model` kein Hebel.

## Umgebung

### Windows (primäre Entwicklungsmaschine)

| | |
|---|---|
| Racket | v9.3 [cs], x86-64 — seit 2026-09-11 migriert (`docs/HACKING.md` §24.1) |
| Qt | 6.11.0, `C:\Qt\6.11.0\msvc2022_64` |
| CMake | 4.2.3, Generator "Visual Studio 17 2022" |
| Preset | `windows-x64` → `qt-shim/build/windows-x64` |

### macOS arm64

| | |
|---|---|
| Racket | v9.3 [cs], arm64 (Homebrew) — seit 2026-08-19 automatisch von v9.2 aktualisiert (Cask hält keine ältere Version vor, s. `docs/HACKING.md` §23.2) |
| Qt | 6.11.0, `~/Qt/6.11.0/macos` |
| CMake | Ninja, Generator "Ninja" |
| Preset | `macos-arm64` → `qt-shim/build/macos-arm64` |
| gui-lib/draw-lib | seit 2026-09-13 als Installation-scope-Link aktiv (`raco pkg update --link`, kein `sudo` nötig — `/Applications/Racket v9.3/share/pkgs/` ist user-owned), kein `-S` mehr nötig — Angleich an Windows/Linux abgeschlossen (§29.1) |

### Linux x64

| | |
|---|---|
| Racket | v9.3 [cs], x86-64 (`~/racket`) — seit 2026-09-13 migriert (`docs/HACKING.md` §28), `racket`/`raco` nicht im PATH, vollen Pfad verwenden |
| Qt | 6.11.1, `~/Qt/6.11.1/gcc_64` (Hinweis: 6.11.**1**, nicht 6.11.0 wie Windows/macOS) |
| CMake | Ninja, GCC 13.3.0 |
| Preset | `linux-x64` → `qt-shim/build/linux-x64` |
| gui-lib/draw-lib | seit 2026-07-14 als Installation-scope-Link aktiv (`raco pkg update --link`, kein `sudo` nötig — `~/racket` ist user-owned), kein `-S` mehr nötig |

## Build

> **Shim-Rebuild-Historie abgeschlossen (Stand 2026-09-19, alle drei Plattformen).**
> Acht Fixes zwischen §32 und §43 hatten je neue Exporte eingeführt
> (`resizeEvent`, Scroll-Block, Zwischenablage, Menü-Enable-States,
> `cursor-driver%`, `gauge%`, `get-current-mouse-state`, `printer-dc%`).
> Windows (2026-09-17) und macOS (2026-09-18) waren zuerst dran; **Linux hat am
> 2026-09-19 nachgezogen** (alle 27 Exporte per `nm -D` verifiziert, §52.1) —
> damit sind alle drei Maschinen auf demselben Shim-ABI-Stand. Bei künftigen
> neuen Shim-Exporten hier wieder einen Banner dieser Art einfügen, bis alle drei
> Maschinen nachgebaut haben (gleiche Klasse wie §27/§52.1).
>
> **Shim-ABI-Stand seit 2026-09-22 (Block C) — abgeschlossen, alle drei Maschinen
> nachgebaut+validiert (Windows 2026-09-22, macOS 2026-09-25).** Elf neue Exporte
> aus dem Vertrags-Audit:
> `shim_control_font_face`, `shim_control_font_size`, `shim_bell`,
> `shim_double_click_time`, `shim_clipboard_supports_selection`,
> `shim_clipboard_set_image`, `shim_clipboard_has_image`, `shim_clipboard_image_size`,
> `shim_clipboard_get_image_argb`, `shim_get_x11_display`, `shim_widget_get_x11_window`
> (docs/2026-09-22_report-linux.md §2.1/§2.3/§2.4/§2.6/§2.7/§2.10). **Zusätzlich
> Arity-Änderung** (kein neuer Name, aber ABI-relevant):
> `shim_clipboard_set_text`/`_get_text`/`_has_text` haben jetzt einen zusätzlichen
> `mode`-Int-Parameter (§2.6) — ein altes Binary mit der alten 1-Parameter-Signatur
> würde beim `get-ffi-obj`-Aufruf mit der neuen Racket-Bindung crashen, nicht still
> falsch laufen. `shim_get_x11_display`/`shim_widget_get_x11_window` sind
> Linux/X11-spezifisch (§55.5) — auf macOS/Windows kompilieren sie mit, laufen aber
> ins No-op/degradieren sauber (kein XCB dort), das ist erwartet, kein Bug.
>
> **Windows-spezifischer Build-Fix nötig beim Nachbauen (bereits gefixt, Commit
> `2e91ee3`):** `shim_clipboard_get_image_argb` nutzte `std::min`/`std::max` ohne
> die schützenden Klammern — kollidiert mit den `min`/`max`-Makros aus
> `<windows.h>` (MSVC C2589). Datei hat an anderer Stelle bereits die Hauskonvention
> dafür (`(std::max)(...)`), jetzt konsequent angewendet. **Auf macOS/Clang tritt
> diese Kollision nicht auf** — kein Analogon zu erwarten dort, aber beim Rebuild
> im Hinterkopf behalten, falls doch ein `min`/`max`-Konflikt auftaucht.
>
> **Alle 11 Exporte + Arity-Änderung auf Windows per `dumpbin /exports` verifiziert**
> (`docs/2026-09-22_report-win.md`) **und auf macOS per `nm -gU` verifiziert**
> (`docs/2026-09-22_report-macos.md`, §57). Kein AppleClang-Äquivalent zum MSVC-Fix
> nötig — Build lief sauber durch. Damit sind alle drei Maschinen auf demselben
> Shim-ABI-Stand (gleiche Klasse wie §27/§52.1).

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

**Windows:** `racket` liegt seit der 9.3-Migration (2026-09-11, §24.1) auf dieser
Maschine **nicht** im Machine- oder User-PATH — immer vollen Pfad verwenden oder
`$env:PATH` wie unten setzen.
```powershell
$env:PLT_QT = "1"
$env:PATH   = "C:\Qt\6.11.0\msvc2022_64\bin;C:\Program Files\Racket;" + $env:PATH
racket examples/hello.rkt
```

**Windows — echtes DrRacket (seit Fork == gui-lib 1.80, verlinktes User-Paket):**
```powershell
$env:PLT_QT = "1"
$env:PATH   = "C:\Qt\6.11.0\msvc2022_64\bin;" + $env:PATH
& "C:\Program Files\Racket\DrRacket.exe"
```
Voller Pfad zu `DrRacket.exe` — deshalb hier kein `C:\Program Files\Racket`-Eintrag im
`$env:PATH` nötig (anders als beim bloßen `racket`-Aufruf oben).
Kein `-S`-Flag mehr nötig — der Fork ersetzt die System-`gui-lib` per Link
(`raco pkg update --link third_party/gui/gui-lib`, einmalig, braucht Admin-Rechte).
Gate-Test dafür: DrRacket **ohne** `PLT_QT` muss weiterhin nativ starten (kein
Linklet-Mismatch). Single-Instance-Falle: ein zweiter Aufruf bei bereits laufender
Instanz startet nichts Neues (Exit 0, kein Fenster) — vorher `tasklist | grep drracket`
prüfen. Details/Fallstricke (Autosave-Recovery bei hartem Kill etc.): `docs/HACKING.md §13`.

**macOS — echtes DrRacket (seit 2026-09-13 verlinktes Paket, `-S` nicht mehr nötig):**
```bash
PLT_QT=1 racket examples/hello.rkt
# Smoke tests:
PLT_QT=1 raco test tests/smoke.rkt
# Echtes DrRacket:
PLT_QT=1 racket -l drracket
```
`raco pkg update --link third_party/gui/gui-lib` + `--link third_party/draw/draw-lib`
(einmalig, kein `sudo` nötig — Homebrews `/Applications/Racket v9.3/share/pkgs/` ist
user-owned, wie bei Linux und anders als Windows' `Program Files`). Gate-Test: DrRacket
**ohne** `PLT_QT` startet weiterhin nativ (bestätigt, `raco test tests/smoke.rkt` ohne
`PLT_QT` grün). Rückfallpfad falls je nötig: Backup der vorherigen `gui-lib`/
`draw-lib`-Installation + `pkgs.rktd` liegt unter `~/racket-link-backup-2026-09-13/`
auf dieser Maschine. Details: `docs/HACKING.md` §29.1.

**Linux — echtes DrRacket (seit 2026-07-14 verlinktes Paket, `-S` nicht mehr nötig):**
`racket`/`raco` liegen seit der 9.3-Migration (2026-09-13, §28) nicht im PATH — vollen
Pfad `~/racket/bin/...` verwenden (analog zum Windows-PATH-Fund, §24).
```bash
PLT_QT=1 QT_PLUGIN_PATH=~/Qt/6.11.1/gcc_64/plugins ~/racket/bin/racket examples/hello.rkt
# Smoke tests:
PLT_QT=1 QT_PLUGIN_PATH=~/Qt/6.11.1/gcc_64/plugins ~/racket/bin/raco test tests/smoke.rkt
# Echtes DrRacket:
PLT_QT=1 QT_PLUGIN_PATH=~/Qt/6.11.1/gcc_64/plugins ~/racket/bin/racket -l drracket
```
`raco pkg update --link third_party/gui/gui-lib` + `--link third_party/draw/draw-lib`
(einmalig, kein `sudo` nötig — `~/racket` ist user-owned, anders als Windows' `Program
Files`). Löste ein `-S`-spezifisches Errortrace/Namespace-Mismatch-Problem (Facette 2 in
`docs/2026-07-14_report-linux.md`/`docs/HACKING.md` §23.1) strukturell. Gate-Test:
DrRacket **ohne** `PLT_QT` muss weiterhin nativ starten (bestätigt, `raco test
tests/smoke.rkt` ohne `PLT_QT` grün). Rückfallpfad falls je nötig: Backup der
vorherigen `gui-lib`/`draw-lib`-Installation + `pkgs.rktd` liegt unter
`~/racket-link-backup-2026-07-14/` auf dieser Maschine.

## Aktueller Checkpoint-Status

Diese Tabelle nennt nur den aktuellen Stand, keine Herleitung. Volle Session-Historie
(Vorgehen, Messungen, Verifikation): `STATUS.md` (chronologisches Log, ein Eintrag pro
Session) und `docs/JJJJ-MM-TT_report*.md`. Root-Cause-Tiefenanalysen: `docs/HACKING.md`,
nummerierte §-Abschnitte (unten referenziert — dort nachschlagen für Details).

### Meilensteine A–E

| Checkpoint | Status |
|---|---|
| A – Stub-Shim lädt via FFI | ✅ |
| B – Architektur dokumentiert | ✅ |
| C – frame%/canvas%/button% laufend | ✅ 2026-06-24 |
| D – Eingabe-Rückgrat + Editor-Smoke | ✅ 2026-06-25 |
| macOS Smoke | ✅ 2026-06-25 |
| Linux Smoke | ✅ 2026-06-29 |
| E-0 – Widget-Stubs + gui-lib-Angleich 1.78→1.80 + echtes DrRacket | ✅ 2026-06-30/07-02 |
| Linux – gui-lib/draw-lib Installation-scope-Link (kein `-S` mehr nötig) | ✅ 2026-07-14 (§23.1) |
| E-0 – Menüs (Titel-/addAction-/mapToGlobal-Fix) | ✅ 2026-07-08, alle 3 Plattformen (§14/§15) |
| E-0 – Redraw-Bug (retained-bitmap-Fix) | ✅ 2026-07-10, alle 3 Plattformen (§16) |
| E – list-box%/check-box% echt | ✅ 2026-07-10, Windows (§18) |
| E – Panel-Sizing-Fix + Modalitäts-Fix | ✅ 2026-07-10, alle 3 Plattformen (§18.2/§18.3) |
| E – `file-selector` (get-file/put-file) | ✅ 2026-07-12/13, alle 3 Plattformen, Qt×nativ-Matrix komplett (§19) |
| E – `choice%`/`radio-box%`/`slider%` echt | ✅ 2026-07-13, alle 3 Plattformen (§20) |
| E – `tab-panel%`/`canvas-panel%`/`group-panel%` echt | ✅ 2026-07-14, alle 3 Plattformen (§21) |
| E – Preferences Ende-zu-Ende | 🟡 alle 9 Kategorien × 3 Plattformen durchgesehen, keine funktionalen Defekte mehr; die 4 ursprünglichen §21.6-Befunde alle gefixt (§24.2 Slider-Zahl, §24.3 Colors-Rahmen, §33 Editor-Scrollbars, §34 Colors-Scroll); macOS Preferences initial bereits erreichbar, Windows/Linux via §31-Fix; Browser-Tab seit 2026-07 nicht erneut geprüft |
| Windows Racket 9.2→9.3 | ✅ 2026-09-11 (§24.1) |
| Linux Racket 9.2→9.3 + Fix-Validierung | ✅ 2026-09-13 (§28) |
| macOS Racket-9.3-Validierung + Preferences-Sweep | ✅ 2026-09-13 (§29) |
| macOS – gui-lib/draw-lib Installation-scope-Link | ✅ 2026-09-13 (§29.1) |
| htdp-Lackmustest (`2htdp/image`, big-bang, `test-engine`) | ✅ trägt htdp auf allen 3 Plattformen (§23/§23.1/§23.2). `test-dock-size`-Crash war echte `wx/qt`-Lücke (hartcodiertes `is-shown? #t`), **gefixt** §30 (Linux) + validiert Windows/macOS 2026-09-17/18; `enable`-Kaskade (§26) mitvalidiert. `2htdp/image`-4-von-6-Bug war reiner Viewport-Effekt, erledigt durch §32-Resize-Fix |
| `frame%`-Zustand (Maximize/Iconize/Fullscreen) | ✅ 2026-09-12, Windows (§27), Shim-ABI-Änderung — macOS/Linux Rebuild nötig. Nicht getestet: Zustands-Kombinationen, Fenster-Chrome |
| Resize/Reflow-Bug (Kind-Controls folgen bei Fenster-Resize nicht) | ✅ 2026-09-14, Linux, 4. Anlauf (§21.7→§32) — Root-Cause: gtks `remember-size`-Dedup fehlte, ABI-Änderung. Validiert Windows 2026-09-17, macOS 2026-09-18 (§44.4) |
| Linux Resize/Minimieren unter echter KWin-Window-Manager-Integration | ✅ 2026-09-22 — 3/3 PASS (Extremresizes 200×150/1000×700, `xdotool windowminimize`/`windowactivate` via `_NET_WM_STATE_HIDDEN`/`_FOCUSED`, 5×-Stresstest), keine ABI-Änderung, reiner Validierungslauf |
| Editor-Canvas-Scrollbars (Scroll Fall 1: `canvas%`/`editor-canvas%`) | ✅ 2026-09-14, Linux (§33) — fehlender `on-size`-Aufruf war Root-Cause, nicht Scrollbar-Code; ABI-Änderung (Mausrad). Validiert Windows 2026-09-17(4) inkl. Streifenrechteck-Altbefund (§24.5/§35-Hyp.1) geschlossen, macOS 2026-09-18(2) vertikal+horizontal (§45.7/§46.1) |
| Scroll Fall 2 (`'(auto-vscroll)`-Panels: Kind-Widgets bewegen sich) | ✅ 2026-09-14, Linux (§34) — eigenes Content-Widget, keine ABI-Änderung. Validiert Windows/macOS 2026-09-17/18(2) (§45.6), inkl. Mausrad |
| Zwischenablage (Copy/Paste, `clipboard-driver%`) | ✅ 2026-09-16, Linux (§36) — war No-op-Stub mit falschem Methodenvertrag; Text-only, ABI-Änderung. Validiert Windows (Cross-Process OLE) + macOS (Cross-Toolkit) 2026-09-17/18(2) (§45.2). Bild-Zwischenablage bewusst außen vor |
| Menü-Enable/Check-States vor dem Öffnen nicht nachgeführt | ✅ 2026-09-16, Linux (§37) — `QMenu::aboutToShow` war nirgends verdrahtet, ABI-Änderung. Validiert Windows/macOS 2026-09-17/18(2) (§45.3) |
| Toolbar-Überlappung (`'deleted`-Stil wurde ignoriert) | ✅ 2026-09-14, Linux (§35), keine ABI-Änderung. Validiert macOS 2026-09-18(2) (§45.4), Windows 2026-09-19(2) (§53) — alle 3 Plattformen abgeschlossen |

### Weitere Widget-/Feature-Implementierungen

- `gauge%` (echter `QProgressBar`) — ✅ 2026-09-17, Windows (§41), ABI-Änderung. Validiert macOS (§49.2) + Linux (§52.2)
- `cursor-driver%` (Standard-Cursor + `set-image`) — ✅ 2026-09-17, Windows (§40), ABI-Änderung; dabei Bugfix `wx/qt/window.rkt` fehlender `local.rkt`-Require. Validiert macOS (§49.3) + Linux (§52.2, Cursor-Form fotografisch nicht prüfbar, Werkzeuglücke)
- `get-current-mouse-state` — ✅ 2026-09-17, Windows (§42), ABI-Änderung, volle Symbol-Menge (mehr als win32). Validiert macOS (§49.5, Cmd/Ctrl-Swap bewusst nicht korrigiert) + Linux (§52.3, X11 `XQueryPointer`)
- `printer-dc%` (Raster-Bridge, kein Vektor-Pfad) — ✅ 2026-09-17, Windows (§43), 11 neue Exporte, Dialoge non-modal (Regel 1). PDF-Pfad auf allen 3 Plattformen grün (§52.2). macOS: eigener Teardown-Crash im Dialog-Pfad gefunden **und gefixt** (§49.4→§50, `shim_app_quit` fehlte als `exit`-Hook, Plumber-Fix, keine ABI-Änderung). Windows `QPrintDialog`-Automatisierung offen, s. u.
- Block-C-Vertrags-Audit (elf Prompt-Kandidaten geprüft, drei davon kein Befund, ein neuer Fund) — ✅ 2026-09-22, Linux (§55), zehn Fixes: Control-Font-Metrik (höchste Wirkung), `find-graphical-system-path` (neuer Fund, maskierte `.gracketrc`-Fallback), `bell`, `get-double-click-time`, `flush-display` (Regel-1-Fall, `shim_pump(0)`), `has-x-selection?` + X11-Selection-Mode-Threading, Bild-Zwischenablage, `location->window`, `make-stub-class`-Aufräumen, `register-/unregister-collecting-blit` (DrRacket-GC-Indikator, Port von gtks rohem Xlib-GC-Callback-Protokoll auf Qt6.11, GC-Sicherheit live verifiziert). Elf neue Shim-Exporte + eine Arity-Änderung an drei bestehenden. Gate PASS (Suite A + neue Suite C + Akzeptanztest). **Windows nachgebaut+validiert 2026-09-22** (`docs/2026-09-22_report-win.md`, §56): 9/10 Fixes vollständig PASS, ein Windows-spezifischer MSVC-Build-Fix nötig (`min`/`max`-Makro-Kollision, Commit `2e91ee3`), Bild-Zwischenablage-Cross-Toolkit-Test **pixelgenau PASS** (stützt die Linux-Klipper-Hypothese: Windows hat kein Klipper-Äquivalent und läuft sauber durch, wo Linux 3× scheiterte). **Akzeptanztest `test-dock-size` auf Windows nicht abgeschlossen** — reiner Automatisierungsblocker (Klick-Automatisierung traf den Run-Knopf in echtem DrRacket wiederholt nicht, RCA nicht isoliert, Empfehlung: dediziertes/unbeobachtetes Desktop für einen Nachtest), kein Produktbefund. **macOS nachgebaut+validiert 2026-09-25** (`docs/2026-09-22_report-macos.md`, §57): alle zehn Fixes PASS, inkl. Akzeptanztest (0/3 Crash, Run per Menü-Äquivalent — Toolbar-Button ohne AX-Repräsentation). Bild-Zwischenablage-Tie-Breaker (Qt→nativ) läuft auch auf macOS sauber durch, stützt die Klipper-Hypothese weiter (2:1 gegen einen racket-qt-Bug, Linux bleibt ungeklärt). Zusätzlich erstmals validiert: §55.6 (Clipboard-`eq?`-Fix, auf gtk No-op, auf macOS/win32 tatsächlich wirksam, Risikofall strukturell ausgeschlossen). **Zwei neue, offene macOS-Befunde** (Fixversuch unternommen, beide Regel-4-Budgets ausgeschöpft, geparkt — Details §57.3/§57.5): native Menüleiste kollabiert bei offenem `QFileDialog` (kein natives Panel — `DontUseNativeDialog` ist Default —, läuft nie durch `frame%`/`dialog%`; zwei Fix-Hypothesen widerlegt, vermutlich Qt-Cocoa-internes Key-Window-Menü-Tracking, bräuchte natives `NSApplication`-API); Nativ→Qt-Bildzwischenablage meldet Retina-Inhalte bei doppelter Pixelgröße (`40×40` statt `20×20`@Scale2 — DPI-Metadaten gehen im Qt-Pasteboard-Lesepfad vollständig verloren, `dotsPerMeterX/Y()`=0, bräuchte natives Pasteboard-API). **Block C damit auf allen drei Plattformen abgeschlossen**, die beiden Zusatzbefunde bleiben offen für eine künftige Session mit Cocoa/Objective-C++-Erweiterung des Shims.

### Weitere Bugfixes

- Linux Crash B (Teardown, „invalid memory reference" nach `QFileDialog`) — ✅ 2026-09-16 (§39), fehlender Pump-Zyklus vor `exit`, keine ABI-Änderung. Validiert Windows + macOS 2026-09-17/18(2) (§45.5)
- macOS: Preferences-Menüpunkt löste falschen Callback aus — ✅ 2026-07-14 (§22), `setMenuRole(NoRole)` + `current-eventspace-has-standard-menus?`-Gate
- macOS: „8 statt 9 Menüs" (leeres `Windows`-Menü unsichtbar) — ✅ 2026-09-18(7) (§51.1), Platzhalter-`QAction`, keine ABI-Änderung
- macOS: Menüband kollabiert nicht korrekt beim Schließen des letzten Fensters — ✅ 2026-09-18(4) (§46.2/§47), reines `wx/qt`-lokal, keine ABI-Änderung
- Linux: stdout-Rauschen beim Laden (`qt-init!`/`qt-start-event-pump` ungevoidet) — ✅ 2026-09-19 (§52.4), rein kosmetisch, keine ABI-Änderung. Validiert Windows 2026-09-19(2) (§53)
- `wx/common/clipboard.rkt`-Dead-Code-`if`-Bug (§55.6) — ✅ 2026-09-22 (Linux), Ein-Zeilen-Fix (`(has-x-selection?)` statt `has-x-selection?`), gui-Submodul `6bae83df`. Shared Code, betrifft alle vier Backends identisch, keine ABI-Änderung (reiner Racket-Code). Smoke getestet Linux Qt + nativ (gtk), Windows/macOS noch nicht validiert.

### Reklassifiziert (kein Produktbefund)

- Tools-Listbox-Klick (macOS) — reines AppleScript/AX-Automatisierungsartefakt, kein Bug (§51.2)
- „Zombie-Prozess" beim Schließen des letzten Fensters (Linux §38, macOS §44.5/§47.1) — `xdotool windowclose` liefert Close-Event nie aus (Linux, backend-unabhängig, auch nativ reproduzierbar); auf macOS Standard-Cocoa-Konvention (`framework:exit-when-no-frames` bewusst `#f`), kein Qt-Bug. Bare-Skript-Variante (§47.1-Nebenbefund) auf macOS mit belegter Klick-Methodik **nicht reproduzierbar** (§48)
- Windows Toolbar-Save-Icon-Timing — 2026-09-11 systematisch gegen echtes DrRacket getestet, nicht reproduziert (§24.4)
- Linux Crash A („arity mismatch") — nach macOS-Menü-Dispatch-Fixes (§19) in 4 Versuchen nicht mehr reproduziert, plausibel behoben (nicht absolut bewiesen, Original war n=1-intermittierend)
- **Windows Zombie-Prozess beim Schließen des letzten Fensters** — war 4/4 Qt-spezifisch reproduziert (§ „Session 2026-09-17 (Windows, 10)", `docs/2026-09-17-7_report-win.md`). Auf dem 2026-09-19 gepullten HEAD (`278ef9c1`) **4/4 + 1 nativer Kontrolllauf sauber**, Symptom nicht mehr reproduzierbar (`docs/2026-09-19_report-win.md`, §53). Root Cause **nicht isoliert** (kein Bisect) — wahrscheinlich einer von `f3e0dec0`/`5a6da709` (beide ursprünglich für macOS gefixt), welcher genau ist offen. Bewusst nicht als "gefixt" markiert, da kein zugeordneter Fix-Commit; falls das Symptom in einer künftigen Session wieder auftritt, ist das kein Widerspruch zu diesem Eintrag.
- Windows `printer-dc%`: `QPrintDialog` — **§43.7/§53.2/§54–§54.3 vollständig zurückgezogen, Messfehler statt Befund** (§54.4, 2026-09-19). Nutzer beobachtete einen weiteren manuellen Testlauf **live und in Echtzeit**: „Seite einrichten" → OK → Print-Dialog „Racket-Drucken" öffnet sich normal und ist **voll bedienbar**. Root Cause der ganzen Fehlserie: `MainWindowHandle=0`/`IsWindowVisible=False`-Snapshots (1,5–2,5s Wartezeit, danach `Stop-Process -Force`) können nicht unterscheiden zwischen „Fenster ist nie erschienen", „Fenster erscheint noch nicht" (paketierte Apps starten langsam/kalt) und „Fenster wurde bereits benutzt und geschlossen, COM-Server läuft nur noch in seiner Idle-Timeout-Phase nach". Alle bisherigen "unsichtbar"-Messungen (inkl. der vermeintlich vom Nutzer bestätigten in §54.3) waren zu ungeduldig/haben zu früh abgebrochen. **Es gibt keinen Hinweis mehr auf einen echten Defekt** — `QPrintDialog` funktioniert. RDP-Hypothese (§43.7 ursprünglich vermutet) bleibt als einziger Nebenaspekt widerlegt, aber gegenstandslos, da kein Befund mehr existiert, den sie erklären müsste. Keine racket-qt-Aktion nötig.

### Offene Befunde (künftige Session nötig)

- §33.7 — einmaliger, seither in 17 Wiederholungen nicht reproduzierter Tab-2-Zeilennummern-Defekt (Linux, `editor-canvas%`), Rate ≤1-in-18, `PLT_QT_SCROLL_DEBUG=1` für künftige Diagnose vorbereitet
- Bild-Zwischenablage Cross-Toolkit (Qt→gtk) auf **Linux weiterhin ungeklärt fehlgeschlagen** (§2.7/§55.3, vermutete KDE-Klipper-Interferenz, nicht bestätigt) — auf Windows **und** macOS lief derselbe Test (Qt→nativ) sauber durch (§56.3/§57.3), stützt die Klipper-Hypothese 2:1, beweist sie aber nicht (andere Qt-Platform-Plugins auf Windows/macOS als auf Linux). Nur noch Linux offen.
- `register-/unregister-collecting-blit` ist bewusst **nur für X11 implementiert** (§55.5) — Wayland/Windows/macOS bleiben ohne GC-Indikator-Sichtbarkeit (kein Regressionsschaden, aber auch kein neuer Fortschritt dort); ein echter macOS/Windows-Pfad wäre ein eigener künftiger Block. Auf macOS zusätzlich strukturell bestätigt: sauberer No-op auch bei installierter/laufender XQuartz (§57.4, Compile-Guard `#ifdef __linux__`).
- **macOS: native Menüleiste kollabiert bei offenem `QFileDialog`** auf den reduzierten Drei-Menü-Zustand (`racket, File, Help`), bereits während der Dialog offen ist (nicht erst beim Schließen). **Zwei Fix-Hypothesen widerlegt** (2026-09-25 (2), Regel-4-Budget ausgeschöpft): weder das `shim_widget_set_enabled`-Deaktivieren des Parent-Fensters während des Dialogs (`filedialog.rkt:93/99`, testweise entfernt — Kollaps trat trotzdem ein) noch ein erzwungenes `activateWindow()`/`QMenuBar`-Hide-Show im C++-`finished`-Handler heilten den Zustand. `QFileDialog` läuft **nie** durch `frame%`/`dialog%`/`direct-show` (kein natives Panel — `DontUseNativeDialog` ist Default) — die ursprüngliche `shown-real-frames`-Hypothese war falsch. Vermutlich Qt-Cocoa-internes Key-Window-Menü-Tracking (welches `QMenuBar` beim Fokuswechsel als Systemmenü installiert wird), über Qts öffentliche `QWidget`-API nicht beeinflussbar — ein Fix bräuchte natives `NSApplication`/`NSMenu`-API (Objective-C++, neue Build-Komplexität). Details: §57.5.
- **macOS: Nativ→Qt-Bildzwischenablage meldet Retina-Inhalte bei doppelter Pixelgröße** (`40×40` statt korrekt skaliertem `20×20`@Scale2) — `shim_clipboard_image_size`/`_get_image_argb` geben Cocoas 2×-Backing-Repräsentation ohne Skalierungskorrektur weiter, API-sichtbar falsch. Tritt nur in dieser Richtung auf (Qt schreibt selbst nur 1×). **Kein Qt-API-only-Fix möglich** (2026-09-25 (2)): `QImage::dotsPerMeterX/Y()` liefert `0`, DPI-/Skalierungsmetadaten gehen im Qt-Pasteboard-Lesepfad vollständig verloren — ein Fix bräuchte natives Pasteboard-API (Carbon `PasteboardRef` oder Objective-C++ `NSPasteboard`/`NSImage`). Details: §57.3.

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

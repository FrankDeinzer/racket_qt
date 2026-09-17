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

> **⚠ Offener Shim-Rebuild für macOS und Linux (Stand 2026-09-17, Windows erledigt).**
> Acht Fixes haben je neue Exporte eingeführt: `shim_window_set_resize_cb`
> (`resizeEvent`-Fix, §32), `shim_canvas_set_wheel_cb` (Scroll-Block, §33),
> `shim_clipboard_set_text`/`shim_clipboard_get_text`/`shim_clipboard_has_text`
> (Zwischenablage, §36), `shim_menu_set_about_to_show_cb` (Menü-Enable-States, §37),
> `shim_cursor_create_standard`/`shim_cursor_create_from_argb`/`shim_widget_set_cursor`/
> `shim_widget_unset_cursor` (`cursor-driver%`, §40), `shim_gauge_create`/
> `shim_gauge_set_range`/`shim_gauge_get_range`/`shim_gauge_set_value`/
> `shim_gauge_get_value` (`gauge%`, §41), `shim_get_mouse_state`
> (`get-current-mouse-state`, §42) und die zehn `shim_printer_*`-Exporte plus
> `shim_printer_set_output_pdf` (`printer-dc%`, §43 — braucht zusätzlich die
> Qt-Komponente `PrintSupport`, s. `qt-shim/CMakeLists.txt`). Windows hat `qt-shim`
> zuletzt am 2026-09-17 neu gebaut (alle sechsundzwanzig Exporte per `dumpbin`
> verifiziert). Linux war bis §37 aktuell, hat aber weder die vier §40-Cursor- noch die
> fünf §41-Gauge- noch den einen §42-Mouse-State- noch die elf §43-Printer-Exporte —
> braucht also jetzt ebenfalls einen Rebuild, nicht nur macOS. Auf **beiden** Maschinen
> muss `qt-shim` nach dem nächsten Pull noch **einmalig neu gebaut** werden — **ein**
> Rebuild deckt jeweils alle ausstehenden Exporte ab. Ohne Rebuild schlägt schon das
> Laden des Forks fehl, laut und sofort: `ffi-obj: could not find export … undefined
> symbol: shim_window_set_resize_cb` (oder `shim_cursor_create_standard`/
> `shim_gauge_create`/`shim_get_mouse_state`/`shim_printer_create` auf Linux).
> Diesen Hinweis entfernen, sobald beide gebaut haben. Gleiche Klasse wie der
> §27-Rebuild.

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

Diese Tabelle nennt nur den aktuellen Stand. Volle Session-Historie (Vorgehen, Messungen,
Verifikation): `STATUS.md` (chronologisches Log, ein Eintrag pro Session) und
`docs/JJJJ-MM-TT_report*.md` (ein Report pro Session/Plattform). Technische
Tiefenanalysen/Root-Causes: `docs/HACKING.md`, nummerierte §-Abschnitte (im Text unten
referenziert).

| Checkpoint | Status |
|---|---|
| A – Stub-Shim lädt via FFI | ✅ |
| B – Architektur dokumentiert | ✅ |
| C – frame%/canvas%/button% laufend | ✅ 2026-06-24 |
| D – Eingabe-Rückgrat + Editor-Smoke | ✅ 2026-06-25 |
| macOS Smoke | ✅ 2026-06-25 |
| Linux Smoke | ✅ 2026-06-29 |
| E-0 – Widget-Stubs + gui-lib-Angleich 1.78→1.80 + echtes DrRacket | ✅ 2026-06-30/2026-07-02 |
| Linux – gui-lib/draw-lib als Installation-scope-Link (kein `-S` mehr nötig, wie Windows) | ✅ 2026-07-14 — löste das Facette-2-Errortrace-Problem strukturell (§23.1), Gate-Test (nativ ohne `PLT_QT`) bestanden |
| E-0 – Menüs (Titel-/addAction-/mapToGlobal-Fix) | ✅ 2026-07-08, alle 3 Plattformen (§14/§15) |
| E-0 – Redraw-Bug (retained-bitmap-Fix) | ✅ 2026-07-10, alle 3 Plattformen (§16) |
| E – list-box%/check-box% echt | ✅ 2026-07-10, Windows (§18) |
| E – Panel-Sizing-Fix + Modalitäts-Fix | ✅ 2026-07-10, alle 3 Plattformen (§18.2/§18.3) |
| E – `file-selector` (get-file/put-file, Qt-eigener Dialog) | ✅ 2026-07-12, alle 3 Plattformen; Qt-eigen×nativ-Matrix (3×2) komplett 2026-07-13 (§19) |
| E – `choice%`/`radio-box%`/`slider%` echt | ✅ 2026-07-13, alle 3 Plattformen (§20) |
| E – `tab-panel%`/`canvas-panel%`/`group-panel%` echt (Widget-Breite abgeschlossen) | ✅ 2026-07-14, alle 3 Plattformen (§21; macOS via `tab-panel%` real + isolierter Proben für `canvas-panel%`/`group-panel%`, §21.8) |
| E – Preferences Ende-zu-Ende | 🟡 Windows: alle 9 Kategorien durchgesehen (Font/Colors/Browser bereits vorher, Editing/Warnings/General/Profiling/Tools/Background Expansion 2026-09-12, §25) — **keine der sechs neu geprüften Kategorien zeigt einen funktionalen Defekt**. Von den 4 ursprünglichen §21.6-Einzelbefunden sind 2 gefixt (Font-Size-Slider-Zahl — generalisiert auf alle `slider%`, §24.2; Colors-Tab-Rahmen, §24.3); die übrigen 2 (Editor-Canvas-Scrollbars, §24.5, und Colors-Tab rechte Spalte, §25.2) galten als **dieselbe Root-Cause**; **beide sind 2026-09-14 gefixt** — der Editor-Canvas-Teil als Fall 1 (§33), der Colors-Tab-Teil (Fall 2, `'(auto-vscroll)`-Panels mit echten Kind-Widgets) als §34; damit ist der Cluster geschlossen. **Vormessung 2026-09-14 nach §31/§32 (`examples/scroll-probe.rkt`):** die Rendering-Hälfte des Linux-Symptoms ist verschwunden (Inhalt rendert sauber, Reflow beim Vergrößern funktioniert) — der frühere Stride-Verdacht ist damit erledigt; Linux und macOS zeigen jetzt **dasselbe** Symptom (korrektes Rendering, Scrollen wirkungslos, kein Scrollbar). Was blieb, war eine schlichte Lücke: `wx/qt/canvas.rkt:300-307` führte alle Scroll-Methoden als ausdrückliche Stubs („no scrollbars in the spike") — **2026-09-14 geschlossen (§33)**, s. eigene Tabellenzeile. Resize/Reflow-Bug (§21.7) **gefixt 2026-09-14 (§32)**. **Der Dialog-Befund „öffnet initial mit unerreichbarer OK/Undo/Revert-Button-Zeile" (§25.1) ist gefixt (2026-09-14, Linux, §31) — und gehörte nie zu §21.7:** kein Resize beteiligt, sondern `get-client-size` lieferte unter Qt das Außenmaß statt des Clients und unterschlug die Menüleistenhöhe, wodurch `wxtop.rkt:302`s Chrome-Reserve immer 0 war (Frame-Mindesthöhe zu klein **und** Panel 22 px zu hoch gesetzt). Fix rein Racket-seitig in `wx/qt/frame.rkt` über das bereits existierende `shim_widget_get_size_hint` — **keine Shim-ABI-Änderung**. Dialog 1060×641 → 1060×663, Button-Zeile sichtbar und klickbar beim ersten Öffnen, Akzeptanztest n=3 3/3, `test-dock-size`-Regressionswache 2/2 crashfrei. Nur auf Linux gefixt/getestet (Cross-Platform-Modell, gebündelte Validierung). **Linux: alle 9 Kategorien durchgesehen** (2026-09-13, §28) — Font/Colors/Editing/Warnings/General/Profiling/Tools/Background Expansion **keine funktionalen Defekte**, deckt sich 1:1 mit Windows; Browser-Tab nicht erneut geprüft (unverändert seit 2026-07-13/14). **macOS: alle 9 Kategorien durchgesehen** (2026-09-13, §29) — Font/Colors/Editing/Warnings/General/Profiling/Tools/Background Expansion **keine eindeutigen funktionalen Defekte** (Tools-Listbox-Klick automatisierungsbedingt nicht abschließend verifizierbar, s. §29), deckt sich mit Windows/Linux; Menüzugang weiterhin über §22-Fix (Preferences im Edit-Menü). Positive Divergenz: Preferences-Button-Zeile ist auf macOS bereits initial erreichbar (anders als Windows/Linux, §25.1-Cluster) |
| Windows Racket 9.2 → 9.3 Migration | ✅ 2026-09-11 (`docs/HACKING.md` §24.1) — kein gui-lib/draw-lib-Versionsangleich nötig, `raco pkg update --link` (Nutzer-elevated), Gate-Test (nativ ohne `PLT_QT`) grün |
| Linux Racket 9.2 → 9.3 Migration + Fix-Validierung | ✅ 2026-09-13 (`docs/HACKING.md` §28) — 9.3 war bereits vorinstalliert, aber noch nicht verlinkt; Link ohne `sudo` (`~/racket` user-owned), Shim-Rebuild zwingend (§27-ABI), Gate-Test grün. §24.2/§24.3/§27 auf Linux funktional bestätigt, keine Divergenz zu Windows. Baseline (§23.1: Linux 4/6 bzw. 4/5 statt 6/6 bzw. 5/5) unverändert bestätigt, keine 9.3-Regression |
| macOS Racket-9.3-Fix-Validierung + Preferences-Sweep | ✅ 2026-09-13 (`docs/HACKING.md` §29) — kein Versionswechsel nötig (bereits seit 2026-08-19 auf 9.3, §23.2), nur Submodul-Fast-Forward (5 Commits) + Shim-Rebuild (zwingend, wie Linux) + Fork-Recompile (`raco make`, macOS-spezifischer expliziter Schritt, kein Link). §24.2/§24.3/§27 funktional bestätigt, keine Divergenz. Preferences-Sweep (6 Kategorien) keine funktionalen Defekte (Tools-Listbox-Klick automatisierungsbedingt unklar) |
| macOS – gui-lib/draw-lib als Installation-scope-Link (kein `-S` mehr nötig, wie Windows/Linux) | ✅ 2026-09-13 (§29.1) — Versionscheck grün (installierte 1.80/1.24 identisch zum Fork), kein `sudo` nötig (`/Applications/Racket v9.3/share/pkgs/` user-owned), Backup unter `~/racket-link-backup-2026-09-13/`, Gate-Test (nativ **und** Qt DrRacket ohne/mit `PLT_QT`, beide ohne `-S`) bestanden |
| htdp-Lackmustest (`2htdp/image`, big-bang, `test-engine`) | ✅ **DrRacket-auf-Qt trägt htdp** — auf allen drei Plattformen validiert (Windows/Linux 2026-07-14, macOS 2026-09-10, §23/§23.1/§23.2). `test-engine`-Dock-Crash (`test-dock-size`) reproduziert bei 1→2-Tab-Sequenz **10/10 unter Qt, 0/10 nativ** (Windows 4/4+3/3, Linux 3/3+3/3, macOS 3/3+3/3) — **kein htdp-lib-Bug, sondern echte `wx/qt`-Lücke**, auf allen drei Plattformen bestätigt/generalisiert. **Root-Cause präzise lokalisiert (2026-09-12, §23.3, Stretch-Messung):** `wx/qt/panel.rkt:58` überschreibt `is-shown?` hartcodiert auf `#t` (win32 erbt stattdessen die Basisimplementierung — per Grep bestätigt ein echtes, dynamisches `shown?`-Feld, `wx/win32/window.rkt:284/287/327`, gestützt durch §23s Laufzeitmessung: nativ 0/10 Crashes, `remove`-Pfad nie durchlaufen) — dasselbe Muster in praktisch jeder `wx/qt`-Widget-Klasse außer `canvas%`/`frame%`. **Vertieft 2026-09-12 (§26):** die eigentliche Root-Cause liegt in `wx/qt/window.rkt`s `is-shown-to-root?`/`is-enabled-to-root?`, die (anders als bei win32/cocoa/gtk) nicht rekursiv die Elternkette prüfen — Shared Code (`wxwindow.rkt`, `wxpanel.rkt`, `helper.rkt`, `wxme/editor-canvas.rkt`) hängt direkt davon ab; ungeprüfte Hypothese einer Verbindung zu §24.5s Editor-Weißmal-Regression. **Fix-Versuch durchgeführt (§26.1):** Rekursion in `wx/qt/window.rkt` + terminierende Overrides in `wx/qt/frame.rkt` (is-shown-to-root? mirrored win32; is-enabled-to-root? bewusst NICHT mirrored — win32s unbedingtes `#t` verlässt sich auf echtes `EnableWindow`, das Qt-seitige `enable` cascadet nicht nativ, per Advisor-Review vor Commit gefunden und auf `is-window-enabled?` korrigiert) — Gate grün (3/3+3/3, deckt die geänderte Dispatch-Semantik selbst nicht ab), aber `test-dock-size` reproduziert weiterhin 2/2 identisch, da `panel%`s `is-shown?` (§23.3) weiterhin hartcodiert `#t` bleibt (bewusst nicht angefasst). Änderung behalten (regressionsfreie Korrektheitsverbesserung, Parität mit den anderen Backends), Crash selbst bleibt offen — bräuchte zusätzlich eine echte `panel%`-`is-shown?`-Implementierung, eigene künftige Session. **„Lokal und klein" bestätigt, nicht das riskantere Pump-Modell** (`wx/qt/queue.rkt`s 50ms-Poll war die zweite, jetzt nachrangige Hypothese) — **Fix selbst bleibt offen, eigene künftige Session**, aber deutlich risikoärmer eingeschätzt als zuvor. `2htdp/universe` big-bang: Kern-Wette „Racket treibt, Pump blockiert nie" auf allen drei Plattformen bestätigt. Auf Linux zunächst nur über `racket` direkt möglich (DrRacket-Pfad durch ein `-S`/errortrace-Package-Problem blockiert, kein Qt-Bezug) — nach dem Linux-DrRacket-Link läuft big-bang auch über echtes DrRacket unter Qt sauber; auf macOS trat dieses Problem trotz weiterhin genutztem `-S`-Rezept gar nicht erst auf. `2htdp/image`: Windows + macOS einwandfrei (alle 5 Bilder sofort korrekt); Linux Interactions-REPL rendert reproduzierbar (3/3) nur die ersten 4 Top-Level-Bildwerte einer `Run`-Sitzung, danach dauerhaft nichts mehr — Pump-Hypothese widerlegt (Poll läuft unbedingt alle 50ms, erklärt keine Mehrminuten-Hänger), kein Scroll-/Compute-/Deadlock-Problem, vermutlich `framework`-Interactions-Insert-Pfad oder Qt-Canvas-Kapazitätsgrenze (§23.1), auf macOS nicht reproduziert — **erledigt 2026-09-14 durch §32: kein eigener Befund mehr.** Nachgemessen in `docs/2026-09-14-2_report-linux.md` (Phase 0, „Fall 4"): bei 600×500 sind 4 von 6 Bildern sichtbar, das Fenster **ohne erneutes Run** auf 1000×900 vergrößert zeigt **alle 6** — ein reiner Viewport-Effekt, den der Reflow-Fix auflöst; weder Insert-Pfad noch Kapazitätsgrenze. macOS lief auf Racket **v9.3** statt v9.2 (Homebrew-Auto-Update 2026-08-19, s. Umgebungstabelle + §23.2) — Fork neu kompiliert, Ergebnis unverändert. **`test-dock-size`-Crash gefixt (2026-09-13, Linux, §30):** systematisches Vertrags-Audit fand dasselbe hartcodierte `is-shown? #t` in neun weiteren Klassen (`list-box%`/`tab-panel%`/`slider%`/`radio-box%`/`group-panel%`/`button%`/`choice%`/`check-box%`/`message%`) — alle zehn Overrides entfernt, nachdem gemessen wurde, dass `wx/qt/window.rkt`s reales `shown?`-Feld bereits korrekt gepflegt wird (Basis zuerst verifiziert, nicht blind gelöscht). Akzeptanztest 1→2-Tab-Sequenz **n=3, 0/3 Crash** (vorher 10/10 auf allen drei Plattformen), Regressions-Gate grün. Gefixt auf Linux (bewusst, neues Cross-Platform-Modell: Divergenzmessung nur bei bekannten Plattformunterschieden, hier reine Racket-Logik ohne solche — Validierung auf Windows/macOS gebündelt vorgemerkt, s. `docs/2026-09-13_report-linux.md`). **Auf Windows validiert, 2026-09-17** (`docs/2026-09-17_report-win.md`): identische 1→2-Tab-Sequenz per echter Maus-Automatisierung (Toolbar-Run-Klick, File→Open-Dialog), **n=3, 0/3 Crash** — Fix generalisiert, historisch war das 10/10 auf Windows. **macOS weiterhin offen.** Im selben Block: `enable` cascadet jetzt nativ via `shim_widget_set_enabled` (§26 Fund 2, `parent-enable` bleibt bewusst ungenutzter No-op, s. §30) — **per echtem Klick verifiziert 2026-09-14, n=3 3/3 PASS** (Positivkontrolle zählt, deaktivierter Button feuert nicht; die frühere „clicks = 0"-Messung war ein Instrumentenartefakt, §21.10). |
| `frame%`-Zustand (Maximize/Iconize/Fullscreen) | ✅ 2026-09-12, Windows (§27) — `wx/qt/frame.rkt` überschrieb `maximize`/`is-maximized?`/`iconized?`/`fullscreen`/`fullscreened?` vorher gar nicht (§26 Fund 3), erbte hartcodierte `#f`/No-op-Basis. Sechs neue Shim-Funktionen (`qt-shim/src/shim.cpp`, Umbrella). **Erster Entwurf (Convenience-Methoden `showMaximized`/`showMinimized`/`showFullScreen`/`showNormal`) per Advisor-Review vor Commit verworfen und empirisch als fehlerhaft bestätigt:** hätte ein noch nicht gezeigtes Fenster bei `maximize #t` sofort sichtbar gemacht (`IsWindowVisible=True` trotz `is-shown?=#f`) und `iconize #f` hätte einen zuvor gesetzten Maximize-Zustand mitgelöscht. **Korrigiert** auf direkte `Qt::WindowStates`-Bit-Manipulation via `setWindowState()` — beide Bugs danach nicht mehr reproduzierbar, identisch zur nativen Oracle-Messung. Gate 3/3+3/3 grün (vor und nach der Korrektur). **Erste Änderung dieser Sitzung mit hartem Shim-ABI-Bedarf** — macOS/Linux müssen `qt-shim` nach Pull neu bauen, sonst bricht der Fork beim Laden (`get-ffi-obj`-Fehler). `set-size`/`resize` während `maximize`d zusätzlich geprüft (dritter Advisor-Regressionstest) — keine Divergenz zu win32 gefunden, kein Guard nötig. Nicht getestet: Zustands-Kombinationen, Fenster-Chrome (nur programmatische API). |
| Zwischenablage (Copy/Paste, `clipboard-driver%`) | ✅ 2026-09-16, Linux (§36) — `clipboard-driver%` war ein reiner No-op-Stub, dazu mit falschem Methodenvertrag (`get-data`/`set-data`/`clear-data`/`same-client?` — nie von `wx/common/clipboard.rkt` aufgerufen, das stattdessen `get-client`/`set-client`/`get-data`/`get-text-data`/`get-bitmap-data`/`set-bitmap-data` erwartet, 1:1 wie bei gtk/cocoa). Neu implementiert: Text-only, eager statt Ownership-Callback (`QClipboard` ist synchron, schreibt/liest sofort über drei neue Shim-Exporte `shim_clipboard_{set,get,has}_text`, **ABI-Änderung**), WXME-Rich-Paste-Cache nur gültig solange die native Zwischenablage seit dem letzten `set-client` unverändert ist (kein Stale-Paste bei externem Kopiervorgang dazwischen). Verifiziert: `examples/clipboard-probe.rkt` 3/3 (direkter Round-trip, echtes Editor-Copy, echtes Editor-Paste) unter Qt und nativ; Cross-Prozess/Cross-Toolkit (Qt-Schreiber → nativer gtk-Leser); echter laufender DrRacket-Prozess über die Interactions-REPL (`the-clipboard`-Round-trip). GUI-Bedienung (Edit-Menü → Copy) blieb zum Zeitpunkt dieses Fixes unverifiziert — Copy/Cut dort durchgehend ausgegraut trotz aktiver Selektion, deckte sich mit §34.7s damals offenem Befund zu nicht nachgeführten Menü-Enable-States; **dieser Folgebefund ist seit §37 (s. eigene Tabellenzeile) gefixt**, die GUI-Bedienung damit inzwischen ebenfalls bestätigt. Bild-Zwischenablage (`get-bitmap-data`/`set-bitmap-data`) bewusst außen vor, bleiben No-op-Stubs. **Auf Windows validiert, 2026-09-17 (2)** (`docs/2026-09-17-2_report-win.md`): in-process 3/3 sowie **beide Cross-Process-Richtungen** 1/1 (`racket`↔PowerShell `Get-Clipboard`/`Set-Clipboard`, natives OLE-Clipboard) — Fix generalisiert. **macOS weiterhin offen.** Nur auf Linux gefixt/getestet (Cross-Platform-Modell). |
| Menü-Enable/Check-States werden vor dem Öffnen nicht nachgeführt (§34.7-Folgebefund) | ✅ 2026-09-16, Linux (§37) — win32 hookt `WM_INITMENU`, gtk die `GtkMenuItem`-„select"-Signale, beide rufen einmalig `on-menu-click` → `on-demand` (kaskadiert rekursiv durch die ganze Menü-Bar-Baumstruktur, `mrmenu.rkt`) kurz bevor irgendein Menü sichtbar wird. `wx/qt/frame.rkt` definierte `on-menu-click`/`on-menu-command` korrekt als `override*`-Ziele (CLAUDE.md Regel 3), aber **nichts rief `on-menu-click` je auf** — Qt-Äquivalent `QMenu::aboutToShow` war nirgends verdrahtet. Root-Cause verifiziert durch Quelltextvergleich win32/gtk/qt, nicht geraten. **Fix:** neue `RacketMenu : public QMenu`-Subklasse trägt ein `about_to_show_cb`-Funktionszeiger-Paar (gleiches Cast-Muster wie `RacketWindow`/`QWidget*`, an vielen Stellen in `shim.cpp` bereits etabliert), neuer Export `shim_menu_set_about_to_show_cb` (**ABI-Änderung**), in `wx/qt/menu.rkt` pro `menu%`-Instanz registriert — findet über das bestehende `find-top-frame` den Frame und postet `on-menu-click` async in dessen Eventspace (Regel 2: der C-Callback ruft nie synchron nach Racket zurück). Ein einziger Trigger pro Menü-Bar-Baum reicht, weil `menu-bar%`/`menu%`s `on-demand` in `mrmenu.rkt` bereits rekursiv durch alle Submenüs läuft — kein Sonderfall für verschachtelte Menüs nötig. **Verifiziert:** neue Probe `examples/menu-demand-probe.rkt` (`demand-callback` feuert 2/2 bei echtem `QMenu::popup()`, ein `checkable-menu-item%` togglet und der native Zustand liest über `shim_action_is_checked` korrekt zurück); Smoke 3/3 beide Wege, mehrfach wiederholt. **Akzeptanztest in echtem DrRacket:** Edit-Menü Copy/Cut greyed-out bei fehlender Selektion, aktiviert sofort nach Select All (screenshot-belegt); Tabs-Menü „Previous/Next Tab" bleibt bei einem Tab greyed-out, aktiviert sich sofort nach dem Öffnen eines zweiten Tabs (File → New Tab) — beide ursprünglich in §34.7 bzw. dem Zwischenablage-Nachtrag dokumentierten Symptome direkt behoben. **Auf Windows validiert, 2026-09-17 (2)** (`docs/2026-09-17-2_report-win.md`): Enable-States per UI Automation (`IsEnabled`) statt visueller Interpretation gelesen — Edit-Menü Copy/Cut `False`→`True` nach Select All, Tabs-Menü Previous/Next Tab `False`→`True` nach zweitem Tab, je per echtem Mausklick ausgelöst. Fix generalisiert. **macOS weiterhin offen.** Nur auf Linux gefixt/getestet (Cross-Platform-Modell). Details: `docs/HACKING.md` §37. |
| Toolbar-Überlappung (`Untitled`/`Undock`) — `'deleted`-Stil wird beachtet | ✅ 2026-09-14, Linux (§35) — **keine Shim-ABI-Änderung**, `shim_widget_set_visible` existierte bereits. **Nativ-Gate zuerst** (die Pflichtmessung, die §35 vorgeschrieben hatte): DrRacket ohne `PLT_QT` zeigt keine Überlappung und kennt den Text `Undock` gar nicht → Befund ist Qt-spezifisch. **Root-Cause:** `wx/qt` kannte den Fensterstil `'deleted` überhaupt nicht (`grep -rn deleted wx/qt/*.rkt` leer), während win32 (`window.rkt:291`) und gtk (`window.rkt:582/714`) ihn je ausdrücklich behandeln. DrRackets Test-Report-Dock entsteht bei jedem Frame-Aufbau mit genau diesem Stil (`htdp-lib/test-engine/test-tool.rkt:100`), seine Knöpfe `Hide`/`Undock` aber ohne; unter Qt trägt ein QWidget, dessen Parent bei der Erzeugung noch nicht sichtbar ist, kein Hide-Flag, und `QWidget::show()` auf dem Frame kaskadiert nach unten. Die Racket-Seite war beweisbar unbeteiligt — die neue Probe `examples/deleted-style-probe.rkt` meldet unter Qt und nativ **identische** `is-shown?`-Zustände, nur das gezeichnete Bild unterschied sich. `Undock` ist ein gewöhnliches `button%` → **§35-Hypothese 2 (`switchable-button%`) erledigt**; Hypothese 1 (Windows-Streifenrechteck, §24.5) bleibt offen, von Linux aus nicht entscheidbar. **Fix:** `no-show?`-Init in `wx/qt/window.rkt` + Hide-on-Create, durchgereicht von elf Platform-Klassen als `(memq 'deleted style)`. Dass der Glue-Layer fast alles mit `'deleted` erzeugt und sofort per `show-control` wieder anzeigt, trägt win32 seit jeher — und `really-show` landet auf `show`, nicht auf dem `(void)`-Stub `direct-show`; beides vor der ersten Zeile Code verifiziert. Akzeptanz: Toolbarzeile in echtem DrRacket **n=3 3/3** sauber (Belegbilder `docs/2026-09-14-4_toolbar-overlap-{before,after}-linux.png`). Gate: Smoke 3/3 beide Wege, `live-resize-probe`/`minsize-resize-probe` unverändert, Fall 1 + Fall 2 unverändert, §31-Akzeptanztest 1060×663 mit funktionierendem OK, `test-dock-size` 3× crashfrei; dazu die für diesen Fix entscheidenden Wachen: nachträgliches `add-child` auf das `'(deleted)`-Panel macht es sichtbar **und** korrekt platziert, und ein Scroll-`canvas%` darin kommt samt Inhalt und **beiden Scrollbars** zurück (dessen Content-Widget/Scrollbars entstehen erst nach dem Hide-on-Create, §33/§34). `frame%`/`dialog%` bleiben bewusst außen vor — nachgesehen, nicht angenommen: win32 konstruiert den Frame selbst mit `'deleted` (`wx/win32/frame.rkt:257`), Top-Level-`show` ist immer explizit. **Gemessen statt angenommen:** der Test-Report-Dock taugt in dieser htdp-lib-Version nicht als Wache — Andocken hängt allein an der Preference `test-engine:test-window:docked?`, und mit `docked? = #t` erscheint der Dock **auch nativ nicht** (Preference gesichert und bitgleich zurückgespielt). Nur auf Linux gefixt/getestet (Cross-Platform-Modell) |
| Scroll — Fall 2 (`'(auto-vscroll)`-Panels): Kind-Widgets bewegen sich | ✅ 2026-09-14, Linux (§34) — **keine Shim-ABI-Änderung**, `shim_panel_create`/`shim_widget_set_geometry` existierten bereits. **Vormessung widerlegt §25.2s vermutete Root-Cause:** `do-set-scrollbars` feuert auf dem Panel sehr wohl (`len=0/349 page=0/260 pos=-1/-1`, also aus `reset-auto-scroll`) — der Pfad war vollständig da; es fehlten die Scrollbars (§33s bewusstes `(not (is-panel?))`-Gate) und ein verschiebbares Widget. Implementiert: eigenes Content-QWidget in `qt-canvas-scroll-mixin`, von `get-content-hwnd` an die Panel-Kinder ausgegeben, in `reset-dc-for-autoscroll` um den Scroll-Offset verschoben (Qt-Äquivalent zu win32s `content-hwnd`). Drei begründete Abweichungen von win32: Erzeugung **vor** den Scrollbars (Qt stapelt zuletzt Erzeugtes oben, das Content-Widget würde sie sonst verdecken; kein `raise`-Primitiv im Shim); nur für Panels, die wirklich einen Scrollbar bekommen (grenzt die Handle-Identitätsänderung auf `vscroll`/`auto-vscroll` ein, `hide-*`-Panels wie `canvas:color%` unverändert — nachgemessen); Größe aus `get-client-size`, gegen das `wxpanel.rkt`s `panel-redraw` seine Kinder platziert. Zweiter, getrennter Schritt: Mausrad über dem Panel (`qt-wheel-scroll`-Vorrecht-Hook, ein Zehntel Page pro Raste — Qts eigene, gemessene 3 px/Raste sind gegen 349 px Range unbrauchbar). **Akzeptanzkriterium wörtlich erfüllt:** in echtem DrRacket (Preferences → Colors → Color Schemes) sind die drei Buttons sichtbar **und** klickbar (getrennt geprüft, Klick öffnet den „color names:"-Dialog); isolierte Probe 3/3. Gate: Smoke 3/3 beide Wege, Fall 1 unverändert, `live-resize-probe`/`minsize-resize-probe` unverändert, `test-dock-size` 3× crashfrei (Zwei-Tab-Bedingung je Lauf einzeln belegt), §31-Akzeptanztest 1060×663 mit funktionierendem OK. **Auf Windows validiert, 2026-09-17 (2)** (`docs/2026-09-17-2_report-win.md`): Colors → Color Schemes, alle drei Buttons nach Scrollen sichtbar (UIA meldete hier fälschlich `IsOffscreen=False` — Screenshot-Vergleich als Korrektiv nötig) **und** klickbar (echter Klick öffnete den „Style & Color Names"-Folgedialog). Preferences-Button-Zeile (§31) initial erreichbar bei 1076×773. Fix generalisiert. **macOS weiterhin offen.** **Zwei vorbestehende Automatisierungsfallen dabei erstmals belegt (§34.7, eigener offener Nebenbefund):** `ctrl+o`/`ctrl+t` erreichen DrRacket per `xdotool` nicht (`F5` schon, nur Menüklick zuverlässig), und das Tabs-Menü zeigt „Previous/Next Tab" auch bei zwei offenen Tabs ausgegraut — beides führt sonst zu einer Wache, die eine andere Sequenz misst als behauptet. Klickkoordinaten aus `client->screen` der Probe, nicht aus dem Screenshot (§21.10) — die erste Runde geschätzter Koordinaten traf daneben und wäre als „nicht klickbar" fehldeutbar gewesen. Nur auf Linux gefixt/getestet (Cross-Platform-Modell). |
| Scroll — Fall 1 (`editor-canvas%`/`canvas%`): echte Scrollbars | ✅ 2026-09-14, Linux (§33) — **Root-Cause von §24.5 war kein Scrollbar-Bug, sondern ein fehlender Aufruf:** `wx/qt/canvas.rkt`s `set-size` rief nie `on-size` auf (win32 `canvas.rkt:306-309`, gtk `canvas.rkt:450-454` tun es), und dessen Override in `editor-canvas%` (`wxme/editor-canvas.rkt:313`) ist der **einzige** Auslöser der Scrollbar-Buchführung — daher §24.5s „`do-set-scrollbars` feuert einmal bei 30×30 und nie wieder". **Isoliert nachgewiesen, bevor eine Zeile Scrollbar-Code entstand.** Implementiert: eigene Mixin-Schicht `qt-canvas-scroll-mixin` (erzwungen durch die gegenüber win32/gtk invertierte Klassenkette, §1), echte QScrollBar-Kinder über die seit `7d1231e0` bereitliegenden Primitiven, volle wx-Scroll-API mit win32/gtk-identischem Gating, `get-client-size` zieht die Scrollbar-Dicke ab. **Mausrad** brauchte den einzigen neuen Export (`shim_canvas_set_wheel_cb`, **ABI-Änderung**). Akzeptanzkriterium wörtlich erfüllt: beide Scrollbars sichtbar, Mausrad 0→10, PageDown 10→40, Zeile 99 per Thumb, horizontal analog; in echtem DrRacket haben Definitions- und Interactions-Pane jetzt Scrollbars. Gate: Smoke 3/3 beide Wege, `live-resize-probe`/`minsize-resize-probe` unverändert, `test-dock-size` 3× crashfrei, §31-Akzeptanztest 3/3 bei unverändertem 1060×663. **Mausrad auf Windows validiert, 2026-09-17 (2)** (`docs/2026-09-17-2_report-win.md`): Richtung korrekt (Notch scrollt vorwärts, Windows-Konvention), Schrittweite sinnvoll (~15 px/Notch, kein degenerierter Wert) — Fix generalisiert, **macOS weiterhin offen.** **Fall 2 (`'(auto-vscroll)`-Panels, §25.2) in dieser Sitzung bewusst ausgeklammert** (Nutzerentscheidung: dessen Inhalt sind echte Kind-Widgets, die ein Zeichen-Offset nicht bewegt) — **inzwischen gefixt, s. eigene Tabellenzeile (§34)**. Ein **einmaliger, in drei Wiederholungen nicht reproduzierbarer** Tab-2-Befund (falsche Zeilennummern) ist offen dokumentiert (§33.7); zwei Hypothesen dazu wurden gemessen und **beide widerlegt**, der dafür versuchsweise eingebaute `on-size`-Dedup deshalb **wieder entfernt** — dabei fiel aber ein echter Defekt auf und wurde behoben (`show-scrollbars` invalidierte die Backing-Bitmap ohne Repaint-Anforderung). **Nachgemessen 2026-09-16 (Linux, §33.7-Nachtrag):** 14 weitere gültige Wiederholungen derselben Sequenz mit `PLT_QT_SCROLL_DEBUG=1`, **0/14 zeigten das Symptom** (3 zusätzliche Automatisierungsfehlschläge davor zählen nicht mit, s. `docs/HACKING.md` §33.7-Nachtrag) — Rate zusätzlich auf ≤1-in-18 eingegrenzt, weiterhin offen, kein Fix-Versuch diese Session. Nur auf Linux gefixt/getestet (Cross-Platform-Modell, gebündelte Validierung). |

**Offene Nebenbefunde, je eigene Session:** macOS-Menüleiste zeigt teils 8 statt 9
Einträge (`Windows`-Menü fehlt manchmal, Ursache offen — evtl. verwandt mit §22, nicht
bestätigt, durch den §22-Fix nicht berührt). **Präzisiert 2026-09-13 (§29.2):**
innerhalb einer einzelnen Session ist der Zustand stabil (3/3 Neustarts identisch 8
Menüs) — die Intermittenz zeigt sich vermutlich nur **zwischen** Sessions, nicht
während einer laufenden. **Zombie-Prozess beim Schließen des letzten Fensters
explizit reproduziert** (§29.2, 2026-09-13, macOS): Fenster schließt, Prozess läuft
>13s unverändert weiter, kein Crash — deckt sich mit dem unten dokumentierten Befund.
**Auf Linux 2026-09-16 (§38) root-caused und als Testmethodik-Artefakt entlarvt, nicht
als echter Backend-Bug:** `xdotool windowclose` liefert die Close-Anfrage unter dieser
KWin/Plasma-X11-Session nie an die Anwendung aus (Fenster wird von außen zerstört, kein
`closeEvent`, kein `on-close`) — identisch reproduziert unter Qt **und** nativem gtk
(GTK meldet selbst `Gdk-WARNING: GdkWindow unexpectedly destroyed`), also
backend-unabhängig. Ein echter simulierter Klick auf den sichtbaren Schließen-Button
(Koordinaten aus der Fenstergeometrie, nicht geschätzt) beendet den Prozess dagegen
zuverlässig (n=3/3 isolierte Probe, n=2/2 echtes DrRacket, `PLT_QT=1`). **Diese
macOS-Zeile hier bleibt trotzdem offen** — dort lief die Messung über eine andere
Automatisierung (kein `xdotool`) und wurde nicht mit einem äquivalenten „echter Klick"-
Test wiederholt; erst danach ließe sie sich ebenfalls als Artefakt einordnen oder nicht.
Details: `docs/HACKING.md` §38. **Als Lehre für künftige Sessions: `xdotool windowclose`
nicht mehr als Ersatz für „Klick auf den nativen Schließen-Button" verwenden** — wie bei
jeder anderen Widget-Interaktion (§21.10/§34.7) echte Klickkoordinaten aus der
Fenstergeometrie ableiten und per `xdotool mousemove`+`click` simulieren.
**Windows: seit 2026-09-17 (7) reproduziert (4/4), Qt-spezifisch, root cause offen**
(`docs/2026-09-17-7_report-win.md`). Vorgeschichte: `2026-09-17-2` meldete einen
n=1-Befund (echter Klick auf Schließen + „Don't Save", `DrRacket.exe` blieb ohne
sichtbares Fenster am Leben), gestützt allein auf `Process.Responding = True` — `2026-
09-17 (3)` entwertete diesen Beleg (`Responding` ist für ein fensterloses Fenster
trivial `True`) und fand in fünf gezielten Versuchen 5/5 saubere Exits; `2026-09-17 (5)`
bestätigte das für eine lange, ~20-minütige Live-Sitzung (6/6 sauber), aber deckte nur
die Ein-Prozess-Variante ab. **`2026-09-17 (7)` hat den offen gebliebenen
Mehrprozess-Schritt nachgeholt und den Befund reproduziert:** vier Versuche (2× mit drei
parallel laufenden/endenden `racket`-Probenprozessen neben der offenen DrRacket-Instanz,
2× ganz ohne) zeigten **alle** denselben Zombie — **die Mehrprozess-Bedingung ist damit
widerlegt als notwendige Ursache**, reproduziert auch im reinen Einzelprozess-Fall.
Messung (zwei Versuche): CPU-Delta über 5 s = 0 ms, ein Thread, `WaitReason=UserRequest`
— kein Hang an einer blockierenden Ressource, sondern ein Prozess, der im normalen
Pump-Leerlauf weiterläuft, weil ihm nie gesagt wird, dass er beenden soll. **Nativer
Kontrollversuch** (kein `PLT_QT`, identische Schließ-Methodik) beendete sich sauber in
3 s — grenzt den Befund klar auf das **Qt-Backend** ein. Automatisierungshürde dieser
Sitzung: echte Mausklicks trafen wiederholt das falsche Fenster (ein anderes Fenster
stahl in dieser RDP-Sitzung wiederholt den Vordergrund zurück), daher `UIAutomation.
InvokePattern.Invoke()` bzw. `WM_SYSCOMMAND`/`SC_CLOSE` statt echtem Klick verwendet —
der native Kontrollversuch mit derselben Methodik spricht gegen ein Methodik-Artefakt,
schließt einen Qt-spezifischen Unterschied zwischen echtem Klick und `SC_CLOSE` aber
nicht hundertprozentig aus (einziger noch unkontrollierter Unterschied zu `-3`s 5/5
sauberen Real-Klick-Versuchen). Nebenfund: jede Zombie-Instanz behielt ein zusätzliches
`ConsoleWindowClass`-Fenster (Artefakt des `Start-Process`-Starts aus PowerShell, nicht
von `wx/qt` erzeugt) — dessen Schließen beendete den Prozess (Windows'
`CTRL_CLOSE_EVENT`-Default-Handler), ein normal per Doppelklick gestarteter Prozess hat
dieses Sicherheitsnetz nicht. **Root cause nicht lokalisiert** — nur
reproduziert/eingegrenzt, keine Code-Änderung; nächster Schritt für eine künftige
Session: `wx/qt/frame.rkt`s `on-close`/`direct-show`-Kette gegen `register-frame-shown`
prüfen.
**gefixt 2026-07-14 (§22):**
macOS-App-Menü-Eintrag an der „Preferences"-Stelle löste den falschen Callback aus
(DrRackets Help-Menü-Punkt „Configure Command Line for Racket…" statt
`preferences:show-dialog`) — behoben durch `setMenuRole(NoRole)` in `shim.cpp` +
PLT_QT-gated `current-eventspace-has-standard-menus?` in `mred/private/app.rkt` (unser
Fork). **Neuer, ungeklärter Nebenbefund aus demselben Fix (macOS, 2026-07-14):** die
erhoffte Exit-Bestätigung + tatsächliche Prozessbeendigung beim Schließen des letzten
Fensters trat NICHT ein (Prozess läuft weiter, kein Crash) — nicht root-caused, zwei
Hypothesen (DrRacket-eigene Close-Logik vs. Qt-Pump-Loop-Bug bei `queue-callback`).
**Die zweite Hypothese ist seit 2026-09-16 (§38) auf Linux widerlegt** — der komplette
Pump-/`queue-callback`-Pfad funktioniert dort nachweislich, sobald der native
Close-Request die Anwendung überhaupt erreicht; das damalige macOS-Symptom könnte
also, wie auf Linux, ein Automatisierungsartefakt der jeweils verwendeten Close-Methode
sein, statt ein echter Pump-Bug — auf macOS aber nicht nachgemessen, weiterhin offen,
eigene künftige Session (s. `docs/HACKING.md` §38 für den Linux-Befund und die dort
empfohlene Methode: echter Klick auf den Schließen-Button statt einer
Automatisierungsabkürzung). Linux Resize/Minimieren unter
KWin nicht validiert; Linux Crash A
(„arity mismatch") nach den macOS-Menü-Dispatch-Fixes (§19) in 4 Versuchen nicht mehr
reproduziert — plausibel behoben, nicht absolut bewiesen (Original war
n=1-intermittierend). **Linux Crash B (Teardown, „invalid memory reference") gefixt
2026-09-16 (§39):** per gdb-Backtrace root-caused auf einen fehlenden Pump-Zyklus
zwischen `QFileDialog::deleteLater()` (im C-seitigen `finished`-Handler,
`qt-shim/src/shim.cpp`) und Racket-seitigem `(exit)` in einem frameless Skript — mit
offenem `frame%` drainiert der laufende Event-Pump das `DeferredDelete` längst vorher,
ohne offenes Fenster lieferte Qts eigener `atexit`-Flush es stattdessen aus, während
andere Qt-Globals schon abgebaut waren (Absturz tief in `QSettings::QSettings`). Fix:
ein expliziter `(atomically (shim_pump 0))`-Aufruf in `wx/qt/filedialog.rkt` nach dem
synchronen Warten — **keine Shim-ABI-Änderung**, per gdb-Breakpoint auf
`QFileDialog::~QFileDialog` verifiziert (Destruktor läuft jetzt nachweislich über
genau diesen neuen Aufruf, nicht mehr über `atexit`). Verifiziert: neue Probe
`examples/crash-b-teardown-probe.rkt` (Accept 3/3, Cancel 1/1), `examples/file-dialog-
probe.rkt` (frame-offen-Pfad, §19-Stresstest: 3× `put-file` + Cancel + Force GC) grün,
echtes DrRacket File → Save Definitions As grün, Smoke 3/3 beide Wege. **Auf Windows
validiert, 2026-09-17 (2)** (`docs/2026-09-17-2_report-win.md`): `examples/crash-b-
teardown-probe.rkt` Accept 1/1, Cancel 1/1, kein Absturz — Fix generalisiert. **macOS
weiterhin offen.** Nur auf Linux gefixt/getestet (Cross-Platform-Modell) —
Windows/macOS brauchen dafür keinen
Shim-Rebuild. Crash A bleibt von diesem Fix unberührt (anderer Codepfad). `test-dock-
size`-Crash (früher hier als `htdp-lib`-Contract-Bug geführt) **reklassifiziert 2026-07-14
(§23/§23.1/§23.2): echte `wx/qt`-Lücke, kein htdp-lib-Bug, auf allen drei Plattformen
bestätigt** — Windows+Linux+macOS je 1→2-Tab-Sequenz 10/10 Qt-Crash, 0/10 nativ; die
frühere Linux-Beobachtung „reicht schon 1 Tab" hat sich in der §23.1-Session nicht
reproduziert (3/3 sauber bei nur einem Tab, beide Backends), Root-Cause bis
`on-tab-change`/`wx/qt/queue.rkt`-Pump eingegrenzt, Fix offen; nativer
macOS-Save-Dialog hängt bei fehlender
Endung ein literales `.*` an den Dateinamen an (nur nativer Pfad, Qt-eigener Dialog
unbetroffen — Diskriminator bestätigt, §19), bewusst nicht gefixt, da native Pfad ohnehin
nicht der Standard ist. **Windows Toolbar-Save-Icon-Timing:** 2026-09-11 systematisch
gegen echtes DrRacket getestet, in keinem Fall reproduziert — kein offener Befund mehr;
korrigierte Datei-Zuordnung: `mrlib/switchable-button.rkt` + `wx/qt/canvas.rkt`, **nicht**
`wx/qt/button.rkt` (§24.4). Aus §21.6 (2026-07-14, backend-generisch, auf Linux identisch
reproduziert) weiterhin offen: Resize/Reflow-Bug (Kind-Controls wandern beim
Fenster-Vergrößern nicht mit, reproduziert sowohl im Preferences-Dialog als auch in einer
isolierten Probe, §21.7). **Dritter Fix-Versuch (Linux, 2026-09-13, §21.9):**
`resizeEvent` verdrahtet (plus neue `shim_window_get_size`-Live-Query, da
`get-width`/`get-height` zuvor reine Racket-Caches waren) — diesmal **kein Crash und
kein Hänger** bei mehreren diskreten `xdotool windowsize`-Resizes (anders als
Fix-Versuch 1/2), aber Kind-Reflow blieb trotzdem aus; vollständig zurückgerollt
(kein Commit). **Messinstrument als Ursache entlarvt und repariert (2026-09-14,
§21.10):** in einem bare-`racket`-Skript ist der Hauptthread **selbst** der
Handler-Thread des Eventspace (`wx/common/queue.rkt:357`), `yield` dispatcht nur aus
diesem Thread (Z. 464/475) und `(sleep n)` dispatcht gar nichts — geposteste Thunks
laufen erst beim Programmende über den `executable-yield-handler` (Z. 637). Damit ist
der Befund „gepostetes Thunk läuft nie" (`resizeEvent` **und** der
`closeEvent`-Diskriminator) ein **Instrumentenartefakt, kein Qt-Befund**: natives GTK
verhält sich ohne `PLT_QT` identisch (5019 ms statt 0,6 ms), mit `sleep/yield` läuft
das Thunk sofort. **Korrektur an §21.9:** „kein Crash/kein Hänger" bleibt gültig,
**„keine Rückkopplungsschleife" ist gestrichen** — die Schleife setzt voraus, dass
das Thunk läuft und `set-size` aufruft; der Pfad wurde nie durchlaufen, das Risiko
ist ungeprüft, nicht entkräftet. Repariert: neues `examples/pump-gate.rkt`
(`wait/pump` + `pump-gate!`), vier Proben umgestellt, **jede loggt jetzt
`PUMP OK (n ms)` als eigenen Gültigkeitsbeweis**. **✅ §21.7 gefixt 2026-09-14 im vierten Anlauf (§32), Shim-ABI-Änderung:**
entscheidend war nicht neue Messtechnik, sondern gtks `remember-size`-Dedup
(`wx/gtk/window.rkt:640`) — einen Resize nur weitermelden, wenn er die Größe wirklich
ändert; da `set-size` den Cache **vor** dem nativen Resize schreibt, läuft das Echo des
eigenen `set-size` ins Leere, und genau dort lief Fix-Versuch 1 endlos. Verifiziert bis
zum echten Mausziehen (auch unter die Mindestgröße: 6 Korrekturen bei 8 Drag-Schritten,
je ein sauberer Recheck, kein Kaskadieren) und bis zum Preferences-Dialog in echtem
DrRacket (1060×663 → 1200×820, alle Kinder folgen, OK klickt an neuer Position).
**macOS muss `qt-shim` nach dem Pull noch neu bauen** (`shim_window_set_resize_cb`
neu, wie §27 — seit §33 zusätzlich `shim_canvas_set_wheel_cb`, seit §36 zusätzlich
`shim_clipboard_{set,get,has}_text`; ein Rebuild deckt alle drei ab). **Windows hat
gebaut und validiert, 2026-09-17** (`docs/2026-09-17_report-win.md`): Fenster-Shrink
per echtem Maus-Drag in 9 Schritten reflowt Kind-Controls korrekt (horizontale
Scrollbar erscheint bei knappem Platz), Mindestgröße wird ohne Hänger verweigert
(`Responding=True` durchgehend), kein Kaskadieren. Wieder-Vergrößern per Drag ließ
sich automatisiert nicht zuverlässig reproduzieren (Cursor traf die Resize-Border nach
dem ersten Release nicht mehr) — **Automatisierungsgrenze, kein Produktbefund**
(Prozess blieb durchgehend reaktionsfähig).
Editor-Canvas-Scrollbars **gefixt 2026-09-14 (§33)** — der 2026-09-11 auf Windows
gemessene degenerierte Scroll-Range (Editor-Inhalt komplett weiß, §24.5) hatte als
Ursache einen fehlenden `on-size`-Aufruf, nicht den Scrollbar-Code; damit sind auch
macOS' abweichendes Symptom (§29.2, korrektes Rendering ohne Scrollwirkung) und der
Linux-Streifenbefund erledigt. **Auf Windows gegengeprüft, 2026-09-17: Editor-Inhalt
rendert in allen getesteten Tabs korrekt (kein Weißmal-Symptom mehr)** — Scrollbar-
Erscheinen unter echtem Platzmangel nur indirekt bestätigt (kurze Beispieldateien,
aber horizontale Scrollbar erschien beim Verkleinern zuverlässig). **macOS weiterhin
offen.** Der Colors-Tab
(Fall 2, §25.2, `'(auto-vscroll)`-Panels mit echten Kind-Widgets) ist **2026-09-14
gefixt (§34)** — das dort vermutete eigene Content-Widget war tatsächlich die Lösung,
ohne Shim-ABI-Änderung; damit ist dieser Cluster geschlossen.
Colors-Tab-Rahmen-Teil 2026-09-11 gefixt, §24.3. Font-Size-Slider-Zahl **gefixt 2026-09-11** (§24.2). Nebenbefund
(2026-09-11, inzident entdeckt, vorbestehend/unabhängig von den Scrollbar-Änderungen,
per `git stash` bestätigt): grafischer Störeffekt (orange/blau gestreiftes Rechteck) nahe
dem oberen Rand des DrRacket-Editor-Fensters, Root-Cause nicht untersucht. **§35-Hypothese
1, 2026-09-17 gegengeprüft: in keinem der drei `test-dock-size`-Läufe und keinem der drei
geöffneten Tabs sichtbar** — aber nur Abwesenheit in einem anderen Kontext beobachtet,
nicht der ursprüngliche Auslöseschritt selbst wiederholt. **Mit dem designierten Repro
geschlossen, 2026-09-17 (4)** (`docs/2026-09-17-4_report-win.md`):
`examples/scroll-probe.rkt` — exakt die isolierte `editor-canvas%`-Probe
(`'(auto-hscroll auto-vscroll)`, überlanger Inhalt), mit der Linux dasselbe
Symptom-Cluster am 2026-09-13 gezielt reproduziert hatte (dort als Farbstreifen, auf
Windows damals als Weißmalen, auf macOS als korrekt-aber-unscrollbar — alle drei
dieselbe Root-Cause, §33) — rendert nach dem §33-Fix (fehlender `on-size`-Aufruf in
`wx/qt/canvas.rkt`) sauber, kein Streifen-/Weißmal-Artefakt an irgendeiner Stelle,
Mausrad (10 Notches, echte `mouse_event`-Simulation) scrollt den Inhalt korrekt Zeile
für Zeile. Damit erstmals der tatsächliche Auslöseschritt 1:1 wiederholt statt nur
seiner Abwesenheit anderswo — **Hypothese 1 gilt als bestätigt erledigt**, keine
künftige Session mehr nötig.
**Zwischenablage: gefixt 2026-09-16 (§36).** `clipboard-driver%` war ein reiner
No-op-Stub, dazu mit Methodennamen, die `wx/common/clipboard.rkt` nie aufruft (falscher
Vertrag, nicht nur fehlende Implementierung — siehe §36.1). Neu implementiert nach
gtk/cocoa-Vorbild (eager statt Ownership-Callback, da `QClipboard` synchron ist), drei
neue Shim-Exporte (`shim_clipboard_{set,get,has}_text`, **ABI-Änderung**). Verifiziert:
`examples/clipboard-probe.rkt` (3/3, Qt und nativ), Cross-Prozess/Cross-Toolkit
(Qt-Schreiber → nativer gtk-Leser), und im echten laufenden DrRacket-Prozess über die
Interactions-REPL (`the-clipboard` set/get-Round-trip). Die GUI-Bedienung selbst
(Edit-Menü → Copy) blieb bei der Verifikation zunächst unbewiesen — Copy/Cut im
Edit-Menü waren trotz aktiver Selektion durchgehend ausgegraut, deckte sich mit §34.7s
damals offenem Befund zu nicht nachgeführten Menü-Enable-States; **seit §37 (2026-09-16,
gleicher Tag) gefixt**, GUI-Bedienung damit ebenfalls bestätigt. Scope bewusst nur Text — `get-bitmap-data`/
`set-bitmap-data` bleiben No-op-Stubs. Nur auf Linux gefixt/getestet. Im selben Zug
erhoben, eine von vier weiterhin offen, aus derselben Bestandsaufnahme:
`printer-dc%` (`platform.rkt:115`, Drucken tat nichts) war Stub — **seit 2026-09-17
implementiert, s. eigener Absatz (§43) weiter unten.** Bestandsaufnahme aus
dem Quelltext, nicht untersucht — Details und Tabelle:
`docs/2026-09-14-4_report-linux.md`, Abschnitt „Nachtrag nach Abschluss".
**`gauge%` implementiert, 2026-09-17, Windows (§41)** — echter `QProgressBar`, dessen
Ganzzahl-`min`/`max`/`value`-API direkt wx' `0..range`-Vertrag entspricht (keine
Fraction-Umrechnung wie bei gtk nötig, `get-range`/`get-value` fragen den nativen
Zustand live ab statt Racket-seitig zu cachen). Fünf neue Shim-Exporte (ABI-Änderung,
s. Build-Banner oben). Eigene `wx/qt/gauge.rkt`-Datei (Konvention aller echten
Widget-Klassen dieses Backends), `message.rkt` als nähere Vorlage als `slider.rkt`
(beide nicht-interaktiv, kein Container/Label-Wrapper nötig). Verifiziert: neue Probe
`examples/gauge-probe.rkt` (horizontaler + vertikaler Gauge, per Screenshot bei zwei
Ständen als echter, wachsender Balken bestätigt — vorher zeichnete der Stub gar
nichts). Smoke 3/3 beide Wege. **Nur auf Windows implementiert/getestet.**
**`printer-dc%` implementiert, 2026-09-17, Windows (§43)** — letzter der vier seit §36
bekannten Stubs. Qt6 hat `QPrinter::getDC()` ersatzlos gestrichen und bietet keinen
öffentlichen Weg von einem `cairo_t*` in einen `QPainter` — anders als win32
(`cairo_win32_printing_surface_create(HDC)`) und gtk (natives `GtkPrintOperation`-
Cairo-Fenster) bleibt hier also nur ein Raster-Bridge: jede aufgezeichnete Seite wird
in eine ARGB32-Cairo-Image-Surface (fest 300dpi) repliziert, der rohe prämultiplizierte
Puffer geht als `QImage` an `QPainter::drawImage`, gestreckt auf die volle Druckseite —
**Text/Vektorgrafik kommt auf diesem Backend als Raster aus dem Drucker, nicht vektoriell**
(bewusst offengelegt, nicht verschwiegen). `QPrintDialog`/`QPageSetupDialog` laufen
nicht-modal (`open()` + `finished`-Signal, exakt das `filedialog.rkt`-Muster) — `exec()`
öffnet einen verschachtelten `QEventLoop` und verstößt damit gegen Regel 1, ganz gleich
ob darunter ein natives Betriebssystem-Fenster hängt. Elf neue Shim-Exporte (ABI-
Änderung, s. Build-Banner oben, zusätzlich die Qt-Komponente `PrintSupport`). Eigene
Datei `wx/qt/printer-dc.rkt` (Konvention aller echten Widget-/DC-Klassen). Seitengeometrie
kommt direkt aus `ps-setup%`s eigenen `orientation`/`paper-name`-Feldern (Punkte, über
`paper-sizes`) statt aus einem nativen `PAGESETUPDLG`-artigen Objekt — Qt hat dafür kein
Äquivalent, und `show-print-setup` hält dieses Racket-seitige Feld ohnehin schon mit dem,
was der Nutzer im `QPageSetupDialog` wählt, synchron (Paper-Name-Rückweg nur für die vier
von `ps-setup%` akzeptierten Größen A4/A3/Letter/Legal, sonst bleibt der alte Name
stehen). **Ein nicht offensichtlicher Bug unterwegs gefunden:** `(class (dc-mixin
default-dc-backend%) (define/override (init-cr-matrix cr) ...) ...)` — 1:1 aus win32/
gtks eigenem Vorbild abgeschrieben — schlug mit `superclass does not provide an expected
method for override` fehl, reproduzierbar sogar in einem Zwei-Zeilen-Minimalskript ganz
ohne `wx/qt`-Bezug. Root-Cause per Bisektion gefunden, nicht geraten: `init-cr-matrix`/
`get-cr`/etc. sind in `racket/draw/private/local.rkt` als `define-local-member-name`
deklariert (Bindung an Lexikalische Identität, nicht an den bloßen Symboltext) — win32/
gtks `printer-dc.rkt` requiren `local.rkt` bereits, meine erste Fassung nicht; ohne
diesen Require griff `define/override` einen bloßen, öffentlichen, aber *anderen*
`init-cr-matrix` statt der lokalen Member-Name-Bindung, die `default-dc-backend%`
tatsächlich trägt. **Verifiziert:** neue Probe `examples/printer-probe.rkt` mit
`PLT_QT_PRINT_TO_PDF=<pfad>` (Test-Escape-Hatch, umgeht den echten Dialog für einen
reproduzierbaren Lauf) — zwei Seiten (Ellipse+Linie+Text, Rundrechteck+Text), per
ImageMagick zu PNG gerastert und sichtgeprüft: beide Seiten korrekt, MediaBox 612×792pt
(Letter, Default), Inhalt an der richtigen Position, kein Verzerren/Clipping. Echter,
interaktiver Pfad separat geprüft (`examples/printer-dialog-probe.rkt`): `QPageSetupDialog`
öffnet nicht-modal, per `WM_CLOSE` sauber geschlossen, Ergebnis (`#f`/`reject`) korrekt bis
`get-page-setup-from-user` zurückgereicht, kein Crash, kein Hänger. `QPrintDialog` selbst
erzeugt unter dieser RDP-Automatisierungssitzung zwar sein Fenster (Titel „Print“,
`GetWindowRect` liefert plausible Koordinaten), bleibt aber dauerhaft `IsWindowVisible=
False` und rendert nicht — Spooler-Dienst lief, zwölf Drucker installiert (u. a.
„Microsoft Print to PDF“), also kein Spooler-/Treiberproblem; plausibel eine
Automatisierungsgrenze des nativen `PrintDlgEx`-Fensters in dieser Fernwartungssitzung,
kein Produktbefund (Prozess blieb durchgehend `Responding=True`, kein Absturz) — nicht
abschließend bewiesen, da von hier aus nicht weiter diagnostizierbar. Smoke 3/3 beide
Wege. **Nur auf Windows implementiert/getestet.** Details: `docs/HACKING.md` §43.
**`get-current-mouse-state` implementiert, 2026-09-17, Windows (§42)** — Position aus
`QCursor::pos()`, Modifikatoren aus `QGuiApplication::queryKeyboardModifiers()` (echter
synchroner Hardware-Query laut Qt-Doku), Maustasten + Caps Lock aus `GetAsyncKeyState`
(Windows-spezifisch, wie win32s eigene Implementierung, da Qt dafür keinen portablen
Hardware-Query anbietet). Volle Symbol-Menge `left middle right shift control alt meta
caps` implementiert statt win32s unvollständiger Teilmenge (kein `middle`/`meta`) —
`wx/qt` läuft auf allen drei Plattformen, win32s Lücke war eine
Racket-Implementierungslücke, kein Windows-Limit. **Ein Messfehler unterwegs
gefunden:** `QGuiApplication::mouseButtons()` sah wie das portable Äquivalent für
Maustasten aus, spiegelt aber laut Test nur Events, die die eigene Anwendung tatsächlich
empfangen hat — ein synthetischer Klick ohne Fensterfokus tauchte darin nie auf, obwohl
`queryKeyboardModifiers()` (dieselbe Klasse) echtes Hardware-Polling ist und Shift/Strg
korrekt ohne Fokus erkannte. Ein neuer Shim-Export (ABI-Änderung, s. Build-Banner oben).
Verifiziert: neue Probe `examples/mouse-state-probe.rkt` + gezielte Einzel-Checks
(Position exakt, Shift/Strg über `keybd_event`, alle drei Maustasten über `mouse_event`
— erst nach dem Fix korrekt, vorher blieb `mods` bei jeder Maustaste leer). Caps Lock
nicht live getestet (hätte den System-Zustand umgeschaltet), Code-Pfad ist wortwörtlich
win32s eigener. Smoke 3/3 beide Wege. **Nur auf Windows implementiert/getestet** —
Positions-/Modifikator-Teil ist bereits Qt-seitig portabel, nur Maustasten/Caps Lock
brauchen bei macOS/Linux noch eine eigene plattformspezifische Ergänzung im Shim.
**`cursor-driver%` implementiert, 2026-09-17, Windows (§40)** — echte Standard-Cursor
(`Qt::CursorShape`, symbolisch per Namensstring aus Racket ausgewählt statt rohem Enum-
Wert) plus `set-image`/`'bullseye` über eine ARGB-`QCursor(QPixmap, hotX, hotY)`, ohne
win32s AND/XOR-Masken-Komplexität. Vier neue Shim-Exporte (ABI-Änderung, s. Build-Banner
oben). Dabei ein echter, nicht offensichtlicher Bug gefunden und gefixt: `wx/qt/
window.rkt` fehlte `(require "../common/local.rkt")` — `get-driver` ist ein
`define-local-member-name` (an die Modul-Identität gebunden, nicht an den Methodennamen-
String), ohne diesen Require schlägt jeder Aufruf über die öffentliche `set-cursor`-API
mit `send: no such method` fehl, obwohl `wx/common/cursor.rkt` die Methode sichtbar
`define/public` definiert — win32/gtk/cocoa requiren `local.rkt` bereits, `wx/qt` tat es
nie (nie gebraucht, solange der Stub ein No-op war). Verifiziert: neue Probe
`examples/cursor-probe.rkt` (zwölf Standard-Cursor + ein selbstgebauter Bitmap-Cursor,
per echtem `SetCursorPos` und `GetCursorInfo`+`DrawIcon`-Screenshot visuell bestätigt),
echtes DrRacket zeigt jetzt einen I-Beam über der Definitions-Pane (vorher durchgehend
Pfeil) und fällt beim Verlassen automatisch auf den Pfeil zurück — bestätigt, dass Qts
native `QWidget::setCursor()`-Kaskade win32/gtks manuelle `mouse-in?`/`reset-cursor-in-
child`-Buchführung überflüssig macht. Smoke 3/3 beide Wege. **Nur auf Windows
implementiert/getestet** — macOS/Linux brauchen den Shim-Rebuild (s. Build-Banner).

Die übereinander gezeichneten Toolbar-Controls (`Untitled`/`Undock`) sind **2026-09-14
gefixt (§35)** — Nativ-Gate bestand, Ursache war der unter Qt nie beachtete Fensterstil
`'deleted`; §35-Hypothese 2 (`switchable-button%`) ist damit erledigt, Hypothese 1 (das
gestreifte Rechteck auf Windows) bleibt offen und ist erst beim gebündelten
Windows-Durchlauf entscheidbar. **§34.7 (Menü-Enable-States, u. a. DrRackets Tabs-Menü
„Previous/Next Tab" bei zwei offenen Tabs) ist gefixt (2026-09-16, §37)** — s. eigene
Tabellenzeile oben; `QMenu::aboutToShow` war unter Qt nirgends verdrahtet, `on-demand`
lief deshalb nie vor dem Öffnen eines Menüs. Details je
Fund: `STATUS.md`, `docs/HACKING.md`.

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

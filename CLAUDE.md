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
9. **Fehlende Komponenten, Installationen, Klone und Forks macht der Nutzer.** Claude Code installiert, aktualisiert oder entfernt nichts außerhalb des Projekt-Repos, klont keine fremden Repositories (auch nicht nur lesend) und legt keine Forks, Repositories oder Remotes an. Fehlt etwas, stoppt Claude Code den betroffenen Strang und stellt per `AskUserQuestion` eine **fertige** Anforderung: was, welche Version, Quelle, Zielpfad, Zweck, und wie Claude Code es danach prüft. Unabhängige Arbeit läuft weiter. Nach der Bestätigung prüft Claude Code Vorhandensein und Version, bevor es die Komponente benutzt.
   - **Gilt für:** Toolchains, SDKs und Compiler (z. B. Emscripten), Qt-Kits, Racket-Versionen, jeden Paketmanager (apt, brew, winget, pip, npm, `raco pkg install`/`update`/`remove`, `raco pkg update --link`), Browser und Testwerkzeuge, alles mit sudo-/Admin-Rechten, persistente System- und Umgebungskonfiguration, `git clone` fremder Repositories, GitHub-Forks/-Repos/-Remotes/-Tokens.
   - **Kein Beschaffen auf Umwegen:** keine heruntergeladenen Binaries oder Archive, kein `pip --user`, kein `npx`, kein `curl … | sh`, keine Container-Images, kein Vendoring fremder Werkzeuge oder Quellen ins Repo. Eine Verweigerung (durch den Nutzer oder den Auto-Mode-Classifier) wird nie über ein anderes Werkzeug umgangen.
   - **Erlaubt bleibt:** Lesen und Versionsprüfung (`which`, `--version`, Verzeichnislisten); Bauen des eigenen Codes (`cmake --build` des Shims, `raco make`/`raco setup` der bereits verlinkten Forks); temporäre Diagnose-Instrumentierung nur mit ausdrücklicher Freigabe im Prompt (Backup + Hash vorher, Original zurückspielen + Hash prüfen nachher).
   - **Neue Forks** legt der Nutzer an (GitHub-Account `FrankDeinzer`, inklusive Arbeits-Branch). Danach bindet Claude Code den Fork **nach `AskUserQuestion`** als Submodul unter `third_party/` ein — gleiches Muster wie `third_party/gui` (eigener Branch, Regel 6/8).

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
>
> **Shim-ABI-Stand seit 2026-09-26 (§59.2) — macOS gebaut+validiert, Windows/Linux
> noch offen, Rebuild dort zwingend vor dem nächsten Start.** Ein neuer Export:
> `shim_menu_set_about_to_hide_cb` (wired auf `QMenu::aboutToHide`, Gegenstück zu
> `shim_menu_set_about_to_show_cb`) — behebt den Abbruch-Pfad für standalone
> Popup-Menüs (Klick außerhalb schließt das Menü ohne Auswahl, bis dahin
> unbehandelt, s. §59.1). **Das ist kein rein additiver Fall ohne Konsequenz für
> ein altes Binary:** `wx/qt/utils.rkt` bindet `shim_menu_set_about_to_hide_cb`
> unbedingt per `get-ffi-obj` beim Laden des Backends — ein altes Shim-Binary ohne
> diesen Export lässt das Backend **beim Start fehlschlagen** (Modul-Instantiierung
> bricht ab, kein DrRacket-Fenster, kein Absturz-Symptom wie bei §59.1, sondern ein
> Sofort-Fehler beim Laden), nicht nur eine fehlende Einzelfunktion. Windows/Linux
> **müssen den Shim neu bauen, bevor sie danach `PLT_QT=1` erneut starten** (der
> `git pull` des Submoduls allein reicht nicht — erst rebuilden, dann starten).
> Auf macOS/Clang kein Build-Fix nötig, `nm -gU` bestätigt den Export.
> **Windows nachgebaut+validiert 2026-09-28** (`docs/2026-09-28_report-win.md`):
> `dumpbin /exports` bestätigt `shim_menu_set_about_to_hide_cb`, Popup-Menü-Funktionalität
> (§59.1) + Abbruch-Pfad bei Außenklick (§59.2) per echtem DrRacket-Kontextmenü verifiziert,
> kein Absturz. Kein MSVC-Build-Fix nötig. **Linux nachgebaut+validiert 2026-09-28**
> (`docs/2026-09-28_report-linux.md`, `docs/HACKING.md` §63): `nm -D` bestätigt
> `shim_menu_set_about_to_hide_cb`, Popup-Menü-Funktionalität (§59.1) + Abbruch-Pfad bei
> Außenklick (§59.2) per echtem DrRacket-Kontextmenü verifiziert, kein Absturz. Kein
> Linux-spezifischer Build-Fix nötig. **Damit auf allen drei Maschinen abgeschlossen.**
>
> **Shim-ABI-Stand seit 2026-09-26 (§60.3) — nur macOS gebaut+validiert, Windows/Linux
> noch offen, Rebuild dort zwingend vor dem nächsten Start.** Ein neuer Export:
> `shim_button_set_label` (→ `QPushButton::setText()`) — behebt `button%`s `set-label`,
> das bis dahin ein reiner No-op-Stub war (z. B. DrRacket-„Choose Language…"s
> „Show Details"/„Hide Details"-Button wechselte nie sein Label). **Kein rein
> additiver Fall ohne Konsequenz:** `wx/qt/utils.rkt` bindet `shim_button_set_label`
> unbedingt per `get-ffi-obj` — ein altes Shim-Binary ohne diesen Export lässt das
> Backend beim Laden fehlschlagen (Modul-Instantiierungsfehler, kein Fenster), nicht
> nur eine fehlende Einzelfunktion. Windows/Linux müssen den Shim neu bauen, bevor sie
> danach `PLT_QT=1` erneut starten. Gleichzeitig zwei ABI-neutrale Fixes (kein neuer
> Export, aber Verhaltensänderung im bestehenden Code, daher nur wirksam nach Rebuild):
> `shim_file_dialog_create` (Enter im Datei-Dialog startet nicht mehr Inline-Rename,
> macOS-only via `#ifdef Q_OS_MACOS`) und `shim_list_box_create` (sizeHint auf 6 Zeilen
> gedeckelt, `RacketListWidget`). Details/Verifikation: `docs/HACKING.md` §60.
> **Windows nachgebaut+validiert 2026-09-28** (`docs/2026-09-28_report-win.md`):
> `dumpbin /exports` bestätigt `shim_button_set_label`. `button%`s `set-label` per
> echtem „Choose Language…"-Dialog verifiziert (Klick auf „Hide Details" toggelt
> Label korrekt zu „Show Details (Ctrl+D)", Dialog kollabiert wie erwartet). Die
> beiden ABI-neutralen Fixes (`shim_file_dialog_create`/`shim_list_box_create`) nicht
> gesondert nachgetestet (macOS-only bzw. bereits über §60.6-Test mitabgedeckt).
> **Linux nachgebaut+validiert 2026-09-28** (`docs/2026-09-28_report-linux.md`,
> `docs/HACKING.md` §63): `nm -D` bestätigt `shim_button_set_label`. `button%`s
> `set-label` per echtem „Choose Language…"-Dialog verifiziert (Klick auf „Hide
> Details" toggelt Label korrekt zu „Show Details (Ctrl+D)", Dialog kollabiert wie
> erwartet). Die beiden ABI-neutralen Fixes nicht gesondert nachgetestet (analog
> Windows). **Damit auf allen drei Maschinen abgeschlossen.**
>
> **Shim-ABI-Stand seit 2026-09-27 (§60.6) — auf allen drei Maschinen gebaut+validiert,
> abgeschlossen (Windows 2026-09-28, Linux 2026-09-28).** 24 neue Exporte für `list-box%`s Mehrspalten-/`QTreeWidget`-Pfad:
> `shim_list_tree_create`, `_set_headers_visible`, `_set_sections_movable`,
> `_set_header_clicked_cb`, `_set_column_label`, `_set_column_width`,
> `_get_column_width`, `_move_column`, `_column_at_visual_pos`, `_append_row`,
> `_set_cell`, `_clear`, `_delete_row`, `_count`, `_is_selected`, `_select`,
> `_set_current`, `_selected_count`, `_selected_at`, `_scroll_to`, `_first_visible`,
> `_visible_count`, `_append_column`, `_delete_column`. Rein additiv, **kein additiver Fall ohne Konsequenz für
> ein altes Binary:** `wx/qt/utils.rkt` bindet alle `shim_list_tree_*`-Funktionen
> unbedingt per `get-ffi-obj` — ein altes Shim-Binary ohne diese Exporte lässt das
> Backend beim Laden fehlschlagen (Modul-Instantiierungsfehler, kein Fenster), nicht
> nur eine fehlende Einzelfunktion. Windows/Linux müssen den Shim neu bauen, bevor sie
> danach `PLT_QT=1` erneut starten. Bestehende `shim_list_box_*`-Funktionen
> (einspaltiger Pfad, `RacketListWidget`) sind byte-für-byte unverändert — reine
> Ergänzung, keine Arity-/Signaturänderung an etwas Bestehendem. Verifiziert auf
> macOS per `nm -gU` (alle 24 vorhanden) + Laufzeittest gegen den echten Racket
> Package Manager (`pkg/gui`, 217 installierte Pakete, Mehrspalten-Anzeige +
> Spalten-Header-Klick-Sortierung beide funktional bestätigt). Details:
> `docs/HACKING.md` §60.6.
> **Windows nachgebaut+validiert 2026-09-28** (`docs/2026-09-28_report-win.md`):
> `dumpbin /exports` bestätigt alle 24 `shim_list_tree_*`-Exporte. Laufzeittest gegen
> den echten Package Manager (219 installierte Pakete): 5 Spalten mit Headern sichtbar,
> Klick auf „Name"-Header sortiert die Liste sichtbar alphabetisch um. Einspaltiger
> Pfad nicht separat gegengeprüft (kein Anlass, unverändert laut Diff).
> **Linux nachgebaut+validiert 2026-09-28** (`docs/2026-09-28_report-linux.md`,
> `docs/HACKING.md` §63): `nm -D` bestätigt alle 24 `shim_list_tree_*`-Exporte.
> Laufzeittest gegen den echten Package Manager (213 installierte Pakete): 5 Spalten
> mit Headern sichtbar, Klick auf „Name"-Header sortiert die Liste sichtbar
> alphabetisch um. **Damit sind alle drei offenen Rebuild-Pflichten (§59.2/§60.3/§60.6)
> auf allen drei Maschinen (macOS, Windows, Linux) abgeschlossen.**
>
> **Shim-ABI-Stand seit 2026-09-30 (Block D, §64) — nur Linux gebaut+validiert, Windows/macOS
> offen: Rebuild dort zwingend, sonst fehlen die Fixes (kein Startfehler).** Drei neue Exporte:
> `shim_key_keysym` (XKB, nur Linux wirksam; anderswo Stub mit Rückgabe 0),
> `shim_window_set_drop_cb`, `shim_window_set_size_limits`. Anders als bei §59.2/§60.3/§60.6
> sind alle drei in `wx/qt/utils.rkt` **tolerant** gebunden (`get-ffi-obj` mit Fail-Thunk) — ein
> altes Binary startet weiter, verliert nur die Features. **Wirksam nur nach Rebuild** (ABI-neutrale
> Verhaltensänderungen in `shim.cpp`): Fokus-Reason-Filter (`PopupFocusReason` weder In noch Out;
> `MenuBarFocusReason` beim Canvas-Out, Fokus-Rückgabe nach Menü per `QMenu::aboutToHide`),
> `RacketCanvas::focusNextPrevChild=false` + `ClickFocus` (Tab erreicht den Editor),
> `QPushButton::setAutoDefault(true)` (Return auf fokussiertem Button), Scancode in den oberen
> Bits der Key-`mods` (`<< 8`, Linux). Windows: `min`/`max` und `X11`-Includes sind
> `#ifdef __linux__`-geschützt; kein Build-Fix erwartet. Details/Validierungsliste:
> `docs/2026-09-30_report-linux.md`, `docs/HACKING.md` §64.
> **Nachtrag aus dem freien Test (gleicher Stand, nur Linux gebaut):** ein weiterer tolerant
> gebundener Export `shim_widget_set_nav_key_cb` (Escape/Return aus nativen Steuerelementen,
> `NavKeyFilter`); ABI-neutrale Änderungen nur nach Rebuild wirksam: Panels starten 0×0
> (`shim_panel_create`), `PLT_QT_DEBUG`-Mausfilter. Reiner Racket-Code: `tab-panel.rkt`
> (Chrome-Höhe seeden), `panel.rkt` (Null-Größe anwenden), `window.rkt`/Steuerelement-Klassen
> (`qt-forward-nav-keys!`). Windows: X11-`#undef KeyPress/KeyRelease` steht im
> `#ifdef __linux__`-Block. Befunde/Triage: `docs/HACKING.md` §64.5.
>
> **Shim-ABI-Stand seit 2026-10-01 (§64.7/§64.8) — nur Linux gebaut+validiert, Windows/macOS
> offen: Rebuild dort nötig, sonst fehlen die Features (kein Startfehler).** Drei neue,
> **tolerant** gebundene Exporte (`get-ffi-obj` mit Fail-Thunk, ein altes Binary startet weiter):
> `shim_tab_panel_set_options` (`tab-panel%` `'can-close`/`'can-reorder`: [x] pro Tab,
> Drag-Umsortieren, `QTabBar::setTabsClosable/setMovable`), `shim_window_set_style_flags`
> (`frame%` `'no-caption`/`'float`, z. B. DrRackets Tooltip-Frame), `shim_widget_set_no_focus`
> (`canvas%` `'no-focus`). ABI-neutral, **ohne Rebuild wirksam (reiner Racket-Code)**:
> `frame.rkt` startet ohne explizite Größe mit 1×1 statt 400×300 (behebt die grauen Balken am
> Splash-Screen; betrifft jedes Fenster ohne feste Größe — auf Windows/macOS gegenprüfen).
>
> **Nachtrag 2026-10-01 (Screenshot-Sweep, §64.9/§64.10) — Shim-Rebuild nötig, kein Startfehler,
> nur das Verhalten fehlt ohne Rebuild:** `shim_tab_panel_create` (`setExpanding(false)`: kompakte
> Tabs), `shim_menu_popup` (klappt am Bildschirmrand nach oben, `availableGeometry`),
> `RacketListWidget::sizeHint` (Breite ≤ 180 px). Reiner Racket-Code (ohne Rebuild wirksam):
> 1-px-Rahmen für `canvas%` `'border`/`'control-border`, `'transparent`-Canvas ohne Hintergrund.
> Screenshot-Sweep: `tests/sweep/sweep.sh <szene>` und `tests/sweep/dr-dialogs.sh` (Linux/X11).

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

**Stub-Audit (alle drei Plattformen — NACH jeder Änderung an `wx/qt/*.rkt`, bevor der
Submodul-Commit entsteht; nicht nur bei neuen Widget-Klassen, s. §5-Checkliste, denn §60.3
war selbst eine Änderung an einer bestehenden Klasse):**
```bash
# macOS:
raco test tests/stub-audit.rkt
# Linux (racket/raco nicht im PATH, s.u.):
~/racket/bin/raco test tests/stub-audit.rkt
```
```powershell
# Windows (Racket nicht im PATH, s.u.):
& "C:\Program Files\Racket\raco.exe" test tests/stub-audit.rkt
```
Braucht kein `PLT_QT`, keinen gebauten Shim, keinen Qt-Pfad — reine Textanalyse plus `git`
(für zwei der Testfälle: Recall-Regressionstests gegen historische Commits im
gui-Submodul, s.u. — `git` muss auf PATH sein). Findet Kandidaten für stille No-op-Stubs
(Methode tut strukturell nichts, obwohl ein Referenz-Backend sie substantiell
implementiert) durch Vergleich gegen `gtk`/`cocoa`/`win32` — Hintergrund:
`docs/HACKING.md` §60.9. Schlägt fehl bei einem neuen Fund (Methodenname + betroffene
Dateien stimmen mit keinem Eintrag in `tests/stub-audit-allowlist.rktd` überein), oder
wenn ein Allowlist-Eintrag plötzlich nicht mehr (in denselben Dateien) auftaucht. Ergänzt
(ersetzt nicht) die `raco test tests/smoke.rkt`-Läufe unten. **Enforcement ist rein
konventionsbasiert** (diese CLAUDE.md-Zeile), nicht mechanisch erzwungen — kein
Pre-Commit-Hook im gui-Submodul vorhanden; bei Bedarf als eigener Schritt einrichten, nicht
stillschweigend voraussetzen.

**Style-Flag-Audit (alle drei Plattformen, ebenfalls nach jeder Änderung an `wx/qt/*.rkt`):**
`~/racket/bin/raco test tests/style-audit.rkt` (macOS: `raco test …`; Windows analog zum
Stub-Audit). Findet Style-Flags (`'can-close`, `'no-focus`, …), die ein Referenz-Backend in der
gleichnamigen Datei per `memq`/`member` liest, die Qt-Datei aber nie — die Lücken-Klasse, die das
Stub-Audit strukturell nicht sieht (§64.7/§64.8). Allowlist: `tests/style-audit-allowlist.rktd`
(`backlog`/`harmless` mit Begründung; behobene Flags brauchen keinen Eintrag). Reine Textanalyse,
braucht weder `PLT_QT` noch Shim; ein Recall-Test prüft gegen den Stand vor dem Tab-Fix (`git`).

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
Kurzform für freie manuelle Tests: `bin/run_macos.sh` (kein Argument → echtes
DrRacket unter `PLT_QT=1`; mit Argument → an `racket` durchgereicht, z. B.
`bin/run_macos.sh examples/hello.rkt`).

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
- Block-C-Vertrags-Audit (elf Prompt-Kandidaten geprüft, drei davon kein Befund, ein neuer Fund) — ✅ 2026-09-22, Linux (§55), zehn Fixes: Control-Font-Metrik (höchste Wirkung), `find-graphical-system-path` (neuer Fund, maskierte `.gracketrc`-Fallback), `bell`, `get-double-click-time`, `flush-display` (Regel-1-Fall, `shim_pump(0)`), `has-x-selection?` + X11-Selection-Mode-Threading, Bild-Zwischenablage, `location->window`, `make-stub-class`-Aufräumen, `register-/unregister-collecting-blit` (DrRacket-GC-Indikator, Port von gtks rohem Xlib-GC-Callback-Protokoll auf Qt6.11, GC-Sicherheit live verifiziert). Elf neue Shim-Exporte + eine Arity-Änderung an drei bestehenden. Gate PASS (Suite A + neue Suite C + Akzeptanztest). **Windows nachgebaut+validiert 2026-09-22** (`docs/2026-09-22_report-win.md`, §56): 9/10 Fixes vollständig PASS, ein Windows-spezifischer MSVC-Build-Fix nötig (`min`/`max`-Makro-Kollision, Commit `2e91ee3`), Bild-Zwischenablage-Cross-Toolkit-Test **pixelgenau PASS** (stützt die Linux-Klipper-Hypothese: Windows hat kein Klipper-Äquivalent und läuft sauber durch, wo Linux 3× scheiterte). **Akzeptanztest `test-dock-size` auf Windows nachgeholt 2026-09-23** (§56.6): natives Windows (kein RDP), DrRacket bewusst auf einem 100%-DPI-Monitor gehalten; `F5` per `SendKeys` statt Klick auf den Run-Knopf umgeht den §56.4-Blocker zuverlässig. 3/3 unabhängige Durchläufe crashfrei, Zwei-Tab-Bedingung direkt per Tab-Leisten-Beschriftung belegt. Nebenbefund: synthetisch geöffnete Dialoge aktivieren sich nicht automatisch im Vordergrund (`ShowWindow`+`SetForegroundWindow` nötig) — relevant für künftige GUI-Automatisierung. **macOS nachgebaut+validiert 2026-09-25** (`docs/2026-09-22_report-macos.md`, §57): alle zehn Fixes PASS, inkl. Akzeptanztest (0/3 Crash, Run per Menü-Äquivalent — Toolbar-Button ohne AX-Repräsentation). Bild-Zwischenablage-Tie-Breaker (Qt→nativ) läuft auch auf macOS sauber durch, stützt die Klipper-Hypothese weiter (2:1 gegen einen racket-qt-Bug, Linux bleibt ungeklärt). Zusätzlich erstmals validiert: §55.6 (Clipboard-`eq?`-Fix, auf gtk No-op, auf macOS/win32 tatsächlich wirksam, Risikofall strukturell ausgeschlossen). **Zwei neue, offene macOS-Befunde** (Fixversuch unternommen, beide Regel-4-Budgets ausgeschöpft, geparkt — Details §57.3/§57.5): native Menüleiste kollabiert bei offenem `QFileDialog` (kein natives Panel — `DontUseNativeDialog` ist Default —, läuft nie durch `frame%`/`dialog%`; zwei Fix-Hypothesen widerlegt, vermutlich Qt-Cocoa-internes Key-Window-Menü-Tracking, bräuchte natives `NSApplication`-API — Websuche stützt Einordnung als bekannte, wiederkehrende Qt/Cocoa-Schwachstelle statt racket-qt-Regression, kein exakter QTBUG-Treffer, s. §57.5); Nativ→Qt-Bildzwischenablage meldet Retina-Inhalte bei doppelter Pixelgröße (`40×40` statt `20×20`@Scale2 — DPI-Metadaten gehen im Qt-Pasteboard-Lesepfad vollständig verloren, `dotsPerMeterX/Y()`=0, bräuchte natives Pasteboard-API). **Block C damit auf allen drei Plattformen abgeschlossen**, die beiden Zusatzbefunde bleiben offen für eine künftige Session mit Cocoa/Objective-C++-Erweiterung des Shims.

- `list-box%` Mehrspalten-/`QTreeWidget`-Pfad (§60.6, Package Manager) — ✅ 2026-09-27,
  macOS. Dual-Path additiv: neue `RacketTreeWidget`-Klasse + 24 neue
  `shim_list_tree_*`-Exporte in `qt-shim/src/shim.cpp`, dispatcht in
  `wx/qt/list-box.rkt` per `tree?` (`(or (> (length columns) 1) (memq
  'column-headers style))`) — der bestehende einspaltige `RacketListWidget`/
  `shim_list_box_*`-Pfad (inkl. §60.4-sizeHint-Deckel) bleibt byte-für-byte
  unverändert. Voller Vertrag real implementiert: `get/set-column-order`
  (`QHeaderView::moveSection`/`visualIndex`/`logicalIndex`), `get/set-column-size`
  (echte Werte, RacketTreeWidget trackt eigenes Spalten-Min/Max, da `QHeaderView`
  das nativ nicht kann), `set-column-label`, `append-column`/`delete-column` (echte
  Spaltenzahl-Änderung inkl. Datenreflow, obwohl kein Aufrufer in `/Applications/
  Racket v9.3/share/pkgs/` gefunden — Grep über `gui-pkg-manager-lib`/`framework`/
  `drracket-core-lib` ergebnislos, nur öffentliche API-Fläche/Typstubs/Doku
  referenzieren sie), `set` mit mehreren Spalten-Listen gleichzeitig, `set-string`
  auf beliebiger Spalte, Header-Klick → `column-control-event%` per
  `QHeaderView::sectionClicked` (nur bei `'clickable-headers`, Regel-2-konform nur
  `queue-event`), `'reorderable-headers` via `setSectionsMovable`. `tests/stub-audit.rkt`:
  alle 7 zuvor als `backlog` markierten Spalten-Stubs (`get-column-order`,
  `set-column-order`, `get-column-size`, `set-column-size`, `set-column-label`,
  `append-column`, `delete-column`) sind aus der Allowlist entfernt, ein
  historischer Recall-Regressionstest (gegen `9b955ee0`) ersetzt den alten
  "aktuell unbehoben"-Test. Verifiziert: `raco test tests/stub-audit.rkt` 9/9,
  `PLT_QT=1 raco test tests/smoke.rkt` 3/3 (keine Regression), Einzelspalten-Pfad
  gegengeprüft (`examples/list-box-sizehint-probe.rkt`, §60.4-Deckel weiterhin
  aktiv), neuer `examples/multi-column-list-box-probe.rkt`, und **Ende-zu-Ende
  gegen den echten Package Manager** (`racket -l- pkg/gui`, „Currently Installed"
  mit 217 echten installierten Paketen: 5 Spalten mit Headern sichtbar, Klick auf
  „Name"-Header sortiert die Liste sichtbar um — bestätigt `sort-by!`/
  `sort-pkg-list!` laufen tatsächlich). **Auf allen drei Maschinen gebaut+validiert**
  (macOS 2026-09-27, Windows + Linux 2026-09-28, `docs/2026-09-28_report-win.md` /
  `docs/2026-09-28_report-linux.md`).

### Weitere Bugfixes

- Linux Crash B (Teardown, „invalid memory reference" nach `QFileDialog`) — ✅ 2026-09-16 (§39), fehlender Pump-Zyklus vor `exit`, keine ABI-Änderung. Validiert Windows + macOS 2026-09-17/18(2) (§45.5)
- macOS: Preferences-Menüpunkt löste falschen Callback aus — ✅ 2026-07-14 (§22), `setMenuRole(NoRole)` + `current-eventspace-has-standard-menus?`-Gate
- macOS: „8 statt 9 Menüs" (leeres `Windows`-Menü unsichtbar) — ✅ 2026-09-18(7) (§51.1), Platzhalter-`QAction`, keine ABI-Änderung
- macOS: Menüband kollabiert nicht korrekt beim Schließen des letzten Fensters — ✅ 2026-09-18(4) (§46.2/§47), reines `wx/qt`-lokal, keine ABI-Änderung
- Linux: stdout-Rauschen beim Laden (`qt-init!`/`qt-start-event-pump` ungevoidet) — ✅ 2026-09-19 (§52.4), rein kosmetisch, keine ABI-Änderung. Validiert Windows 2026-09-19(2) (§53)
- `wx/common/clipboard.rkt`-Dead-Code-`if`-Bug (§55.6) — ✅ 2026-09-22 (Linux), Ein-Zeilen-Fix (`(has-x-selection?)` statt `has-x-selection?`), gui-Submodul `6bae83df`. Shared Code, betrifft alle vier Backends identisch, keine ABI-Änderung (reiner Racket-Code). Smoke getestet Linux Qt + nativ (gtk); **macOS erstmals empirisch validiert 2026-09-25** (§57.2, Fix wirkt sich dort — anders als auf gtk — tatsächlich aus, Risikofall strukturell ausgeschlossen); **Windows validiert 2026-09-23** (§56.7): `the-x-selection-clipboard` aliast jetzt korrekt `the-clipboard` unter Qt (statt phantomer zweiter `clipboard%`-Instanz), da `has-x-selection?` auf Windows über `shim_clipboard_supports_selection` `#f` liefert.
- macOS: Cmd/Ctrl in jedem Modifier-Keyboard/Maus-Event vertauscht (§49.5-Root-Cause, jetzt gefixt) — ✅ 2026-09-26 (§58.1), `QCoreApplication::setAttribute(Qt::AA_MacDontSwapCtrlAndMeta)` in `shim_app_init`, ABI-neutral (kein neuer Export). Machte jeden Cmd-Menü-Shortcut (Cmd+A/C/V/…) funktionslos — funktional in echtem DrRacket verifiziert (Select-All+Copy+Paste dupliziert Text korrekt). Zusammen mit einem zweiten, unabhängigen Fix (Menü-Shortcut-**Anzeige**, reiner Racket-Code in `wx/qt/menu.rkt`, kein Rebuild nötig, §58.2) aus einem freien manuellen Test nach Block C entdeckt.
- Popup-/Kontextmenüs (`popup-menu%`) im gesamten Backend funktionslos + Absturz bei GC — ✅ 2026-09-26, macOS (§59.1), gefunden über DrRacket „Choose Language…" (Statuszeile → Sprachauswahl-Dialog öffnete sich nie, nach mehreren Versuchen Absturz `terminated in atomic mode!`). Root Cause zwei unabhängige Bugs in `wx/qt/menu.rkt`: (1) `find-top-frame` liefert für standalone Popup-Menüs immer `#f`, das dafür vorgesehene `popup-callback`-Dispatch-Protokoll wurde komplett verworfen; (2) `QMenu::popup()` ist nicht-blockierend, nichts hielt das Menü-Objekt am Leben, GC zwischen Öffnen und Klick führte zu Use-after-free im atomaren FFI-Callback. Fix: `popup-callback` als Fallback verdrahtet + Ein-Slot-GC-Pin (spiegelt gtks `do-selected`/`global-prevent-gc`), reiner Racket-Fix, kein Rebuild nötig. Verifiziert per Minimal-Repro (erzwungener GC-Timer) + echtem DrRacket, Smoke 3/3. **Abbruch-Pfad (Klick außerhalb) direkt im Anschluss nachgerüstet** — ✅ 2026-09-26, macOS (§59.2): neuer Shim-Export `shim_menu_set_about_to_hide_cb` (`QMenu::aboutToHide`) + `cancel-none-box`-Muster (spiegelt gtks `cancel-none-box`/`do-no-selected`, order-unabhängig korrekt egal ob `aboutToHide` vor oder nach `triggered` feuert). ABI-Änderung, kein additiver Fall ohne Konsequenz (altes Binary lässt das Backend beim Laden fehlschlagen). **Windows nachgetestet 2026-09-28** (`docs/2026-09-28_report-win.md`): Kontextmenü öffnet + schließt bei Außenklick sauber ohne Absturz. **Linux nachgetestet 2026-09-28** (`docs/2026-09-28_report-linux.md`, §63): identisches Verhalten, kein Absturz. Beide Teilfixe (§59.1+§59.2) damit auf allen drei Maschinen verifiziert.

- Freier Test (Nutzer, vier Symptome in einer Nachricht): Datei-Dialog-Enter-Rename ✅ (§60.1, macOS-only Qt-Upstream-Verhalten, `EnterAcceptsFilter`, ABI-neutral), „Open Recent" beim ersten Öffnen leer ✅ (§60.2, Async-Race zwischen `aboutToShow` und Regel-2-konformem Rebuild, proaktiver Timer-Refresh in `wx/qt/queue.rkt`, reiner Racket-Fix, ~1%-Punkt CPU-Overhead gemessen), „Show Details"-Button-Label ✅ (§60.3, `button%`s `set-label` war reiner No-op-Stub, neuer Export `shim_button_set_label`, **ABI-Änderung**). Alle drei 2026-09-26, macOS, per sauberem Einzelprozess (`ps`-verifiziert) und `keystroke`-Tastatureingabe verifiziert (`key code`/`cliclick kp:` kamen im Datei-Dialog nicht an, s. §60-Methodik-Lehren). Smoke 3/3 grün. **„Show Details"-Button-Label (§60.3) auf Windows nachgetestet 2026-09-28** (`docs/2026-09-28_report-win.md`): Label wechselt korrekt zwischen „Hide Details (Ctrl+D)"/„Show Details (Ctrl+D)". Eigener Windows-Methodik-Befund dabei: synthetische `Ctrl+<Taste>`-Kombinationen (sowohl `SendKeys` als auch rohes `keybd_event`) erreichen das Qt-Fenster nicht — reine Zeichen-Eingabe (`SendKeys` ohne Modifier) funktioniert einwandfrei. Alle Menü-/Dialog-Interaktionen mussten daher über Maus-Koordinaten laufen statt über Tastatur-Shortcuts. **Auf Linux nachgetestet 2026-09-28** (`docs/2026-09-28_report-linux.md`, §63): identischer Label-Toggle verifiziert, keine der Windows-spezifischen Tastatur-Einschränkungen relevant (Maus-Navigation ohnehin verwendet).
- Zwei der 17 §60.9-`needs-triage`-Stubs gefixt und per echter GUI-Interaktion verifiziert (§61, 2026-09-27, macOS, beide reiner Racket-Code, keine ABI-Änderung): `get-canvas-background-for-backing` (`wx/qt/canvas.rkt`) war hartcodiert `#f`, machte `set-canvas-background` für den regulären Auto-Repaint-Backing-Fill wirkungslos — jetzt `(and clear-bg? bg-col)` wie gtk/cocoa/win32. `get-dialog-level` (`wx/qt/window.rkt`) war für jedes Nicht-Frame-Widget hartcodiert `0` statt an `parent` zu delegieren — Tastatur-/Mausevents an `canvas%`-Kindern innerhalb eines offenen modalen `dialog%` wurden verschluckt (`other-modal?`), jetzt Delegation wie gtk/win32. Neue Probes: `examples/canvas-background-backing-probe.rkt`, `examples/dialog-level-probe.rkt`.
- **Choose-Language-Dialog „Collection Paths"-Buttons vollständig gefixt** (§60.4/§61.1, 2026-09-27, macOS, reiner Racket-Code, keine ABI-Änderung) — zweite Ursache gefunden: `group-panel%`s `get-client-size` berechnet den `QGroupBox`-Chrome-Overhead als `get-height`/`get-width` minus Content-Margins, aber bei der allerersten Layout-Abfrage (vor jedem echten `set-size`-Aufruf) lesen diese noch `0` — kollabiert das gemeldete Minimum um genau die Titelleistenhöhe, drängt die nicht-stretchbare Button-Reihe aus dem sichtbaren Bereich. Fix: Chrome-only-Größe direkt nach Konstruktion seeden (spiegelt win32s Konstruktor-`set-size`). Vorab per nativer-vs-Qt-Vergleich bestätigt, dass es sich um eine echte qt-Regression handelt (nativ rendert korrekt). Neue Probe: `examples/collection-paths-clip-probe-dialog.rkt`. **Windows nachgetestet 2026-09-28** (`docs/2026-09-28_report-win.md`): alle fünf Collection-Paths-Buttons (Add/Add Default/Remove/Raise/Lower) im echten Choose-Language-Dialog vollständig sichtbar, kein Clipping. **Linux nachgetestet 2026-09-28** (`docs/2026-09-28_report-linux.md`, §63): identisch, alle fünf Buttons vollständig sichtbar.
- **Choose-Language-Dialog Hintergrundfarbe links bestätigt, aber Styling statt Bug** (§60.5/§61.1) — `QGroupBox`s Standard-macOS-Rahmen+Füllung (229–236/255) vs. `NSBox`s randlose moderne Optik (255/255 weiß). Echter, systematischer Unterschied, aber kein hartcodierter-Farb-Bug — ein Fix bräuchte ein eigenes Stylesheet, nicht versucht.

- **Block D — Eingabeschicht** — ✅ 2026-09-30, Linux (§64), Windows/macOS-Validierung offen.
  Gefunden per Nativ-Vergleich (neue Prozessregel: Automatisierungsbefund erst nach gtk-Gegenprobe):
  Ctrl+<Zeichen> wurde verworfen (jeder Ctrl-Shortcut tot), Menü-Öffnen als Fokusverlust
  (Edit-Menü grau nach < 1 s), Fokus kam nach Menü+Escape nicht zurück, Ctrl+Shift+Z fügte `Z`
  ein (`other-*-key-code` fehlten), Tab im Editor von Qts Fokuskette gefressen, Delete/Backtab/
  Alt-Mapping falsch, `set-focus` No-op, Return auf fokussiertem Button, Datei-Drop, `enforce-size`,
  Popup-Submenüs. Neue Testinfrastruktur: `tests/key-map.rkt` (GUI-frei), `tests/input-matrix.sh`
  + `tests/input-matrix-gtk.tsv` (16 Zeilen, Qt == gtk), `examples/key-probe.rkt`,
  `dialog-keys-probe.rkt`, `popup-submenu-probe.rkt`; `tests/smoke.rkt` 4 Tests. **Offen:**
  `combo-field%`-Dropdown (Größen-Gate, s. Report), Drop per echtem Dateimanager-Drag nicht
  automatisierbar (Prüfpunkt im freien Test), `other-*-key-code` nur Linux/X11.

- **Freier Test 2 (2026-10-01, Linux, §64.7/§64.8):** (1) Splash-Screen mit grauen Balken — Ursache `frame.rkt`-Fallback 400×300 (wxtops `correct-size` schrumpft dehnbare Panels nie), jetzt 1×1 wie gtk; (2)+(3) Tabs ohne [x] und ohne Drag-Reorder — `tab-panel.rkt` las `'can-close`/`'can-reorder` nie, jetzt echt (`QTabBar`, neuer tolerant gebundener Export). Dazu per neuem **Style-Flag-Audit** (`tests/style-audit.rkt`) gefunden und behoben: `frame%` `'no-caption`/`'float` (Tooltip-Frame war ein normales Fenster), `canvas%` `'no-focus` (ignoriert). Offene Audit-Funde als `backlog`: `'gl`-Canvas, `'border`/`'control-border` (optisch zu prüfen), `'hide-menu-bar`. **Windows/macOS: Rebuild + Validierung offen.** Proben: `examples/splash-width-probe.rkt`, `tab-close-reorder-probe.rkt`, `frame-float-probe.rkt`.

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
- **Popup-Menü-Submenüs** (§59.1): `append` ruft nie `set-parent` auf ein Submenü innerhalb eines Popup-Menüs — dessen Items finden weder einen Frame noch den `on-popup`-Fallback. Für den gemeldeten Fall (kein Submenü) irrelevant, aber ein bekannter blinder Fleck.
- **macOS: Nativ→Qt-Bildzwischenablage meldet Retina-Inhalte bei doppelter Pixelgröße** (`40×40` statt korrekt skaliertem `20×20`@Scale2) — `shim_clipboard_image_size`/`_get_image_argb` geben Cocoas 2×-Backing-Repräsentation ohne Skalierungskorrektur weiter, API-sichtbar falsch. Tritt nur in dieser Richtung auf (Qt schreibt selbst nur 1×). **Kein Qt-API-only-Fix möglich** (2026-09-25 (2)): `QImage::dotsPerMeterX/Y()` liefert `0`, DPI-/Skalierungsmetadaten gehen im Qt-Pasteboard-Lesepfad vollständig verloren — ein Fix bräuchte natives Pasteboard-API (Carbon `PasteboardRef` oder Objective-C++ `NSPasteboard`/`NSImage`). Details: §57.3.
- **Qt-`frame%`/`dialog%` ohne explizite Größe: hartcodierter `400×300`-Fallback** (Nebenbefund aus §61.1) — `wx/qt/frame.rkt:91-92`, statt sich wie nativ am Inhalt zu orientieren. Kein bekannter aktueller Symptomfall (der einzige beobachtete Dialog wächst ohnehin über `400×300` hinaus korrekt), aber eine echte, separate Divergenz.
- **`tab-panel%`s `get-client-size`** hat dasselbe latente 0-Höhe-Klemm-Muster, das `group-panel%` vor §61.1 hatte — nicht gefixt (kein gemeldetes Symptom), nur geflaggt.
- **Stub-Inventar** — nicht mehr per Ad-hoc-Grep, sondern per wiederholbarem Tool
  (`tests/stub-audit.rkt` + `tests/stub-audit-allowlist.rktd`, §60.9). Alle 17 aus §60.9
  offen gelassenen `needs-triage`-Kandidaten sind seit §61 (2026-09-27) einzeln triagiert:
  2 gefixt (s. Bugfix-Eintrag oben), 6 `harmless`, 9 `backlog`. `set-focus` bleibt der
  größte Einzelfund (`backlog`): auf praktisch jedem Basis-Widget (button/choice/
  radio-box/slider/list-box/tab-panel/check-box/message/group-panel) ein No-op, obwohl
  der Shim es kann (nur `canvas%` nutzt es echt). Weitere `backlog`-Kandidaten: `frame%`s
  `set-icon`, `message%`s `set-color`/`get-color`, `panel%`s `get/set-label-position`
  (immer `'horizontal`) und `adopt-child`, `drag-accept-files`/`enforce-size` (beide
  brauchen neue Shim-Exporte), `refresh`/`register-child` (zusammengehöriges Paar),
  `do-canvas-backing-flush`, und die vier Combo-Methoden (`popup-combo`/
  `clear-combo-items`/`append-combo-item`/`set-combo-text` — §61 bestätigt:
  `combo-field%` ist entgegen §60.7s Annahme kein totes Feature, DrRackets
  Multi-File-Search nutzt es real, daher Prioritäts-Hochstufung innerhalb `backlog`,
  vergleichbare Größenordnung wie §60.6 war). Details/vollständige Liste:
  `tests/stub-audit-allowlist.rktd`, `docs/HACKING.md` §60.9/§61. Das komplette
  Mehrspalten-`list-box%`-Feature (§60.6, Package Manager) ist seit 2026-09-27
  implementiert (echter `QTreeWidget`-Pfad, `get-column-order`/`set-column-order`/
  `get-column-size`/`set-column-size`/`set-column-label`/`append-column`/
  `delete-column` alle real, nicht mehr in der Allowlist) — s. Build-Banner + Bugfix-
  Eintrag oben. **Auf allen drei Maschinen nachgebaut+validiert** (macOS 2026-09-27,
  Windows + Linux 2026-09-28, `docs/2026-09-28_report-win.md` /
  `docs/2026-09-28_report-linux.md`), echter Package Manager mit 219 (Windows) bzw. 213
  (Linux) Paketen, Header-Klick-Sortierung funktional auf beiden.

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

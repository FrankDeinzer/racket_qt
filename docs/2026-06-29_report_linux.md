# Linux x64 Smoke-Report — 2026-06-29

## Ziel

Denselben Stand wie Windows/macOS (Checkpoint D: frame%, canvas%, button%, input, editor)
auf Linux x64 zum Laufen bringen — Shim bauen, von Racket laden, hello/input/editor + Smoke-Test
auf Parität bringen. Keine neuen Features.

---

## Umgebung

| | |
|---|---|
| OS | Linux x86_64 (Ubuntu 24.04) |
| Racket | v9.2 [cs], `/home/deinzer/racket/bin/racket` (nicht im System-PATH) |
| Qt | 6.11.1, `~/Qt/6.11.1/gcc_64` |
| CMake / Generator | CMake 3.x, Ninja, GCC 13.3.0 |
| Display | X11, `DISPLAY=:0` |
| gui-Fork-Commit | `6169a245` (macOS-Commit — alle macOS-Fixes geerbt) |

---

## Schritt 0 — Umgebungsprüfung

- Arch x86_64, Linux: ✅
- Racket v9.2 [cs]: ✅ (Projekt-Standard)
- Qt 6.11.1 unter `~/Qt/6.11.1/gcc_64`: ✅ (Hinweis: 6.11.**1**, nicht 6.11.0 wie Windows/macOS)
- Display: X11 aktiv, kein Wayland: ✅
- gui-Fork auf `6169a245` (macOS-Commit): ✅ — `.so`-Ladepfad, `shim_pump(0)`, `events_pending→0`,
  `designate-root-frame`-Stub alle geerbt; kein neuer Racket-Code nötig.

---

## Schritt 1 — Stand erben

Submodule waren aktuell; gui-Fork auf Spitze von `qt-backend` (`6169a245`). Kein einziger
Racket-Code-Eingriff notwendig — alle macOS-Fixes direkt übernommen:

- FFI-Ladepfad `else`-Zweig → `.so` (Linux/macOS)
- `shim_pump(0)` in `queue.rkt`
- `shim_events_pending → 0` auf Nicht-Windows
- `designate-root-frame`-Stub für Racket 9.2

---

## Schritt 2 — Linux-Preset korrigiert

Das `linux-x64`-Preset in `qt-shim/CMakePresets.json` enthielt Platzhalterpfade:

```
vorher:  /opt/Qt/6.11.0/gcc_64
nachher: /home/deinzer/Qt/6.11.1/gcc_64
```

Sowohl `CMAKE_PREFIX_PATH` als auch `CMAKE_BUILD_RPATH` angepasst. Das ist die einzige
Änderung dieser Session.

---

## Schritt 3 — Shim-Build

```
cmake --preset linux-x64 -S qt-shim
cmake --build qt-shim/build/linux-x64
```

Ergebnis: 4/4 Targets, `libracketqtshim.so` erzeugt.

**RUNPATH-Verifikation:**
```
readelf -d libracketqtshim.so | grep RUNPATH
→ RUNPATH: /home/deinzer/Qt/6.11.1/gcc_64/lib
```

**ldd-Verifikation:**
```
libQt6Widgets.so.6 → ~/Qt/6.11.1/gcc_64/lib/libQt6Widgets.so.6  ✅
libQt6Gui.so.6    → ~/Qt/6.11.1/gcc_64/lib/libQt6Gui.so.6       ✅
libQt6Core.so.6   → ~/Qt/6.11.1/gcc_64/lib/libQt6Core.so.6      ✅
libQt6DBus.so.6   → ~/Qt/6.11.1/gcc_64/lib/libQt6DBus.so.6      ✅
```

Kein „not found" — Qt-Libs lösen ohne `LD_LIBRARY_PATH` auf.

---

## Schritt 4 — Bytecode + FFI-Load-Test

Bytecode vorkompiliert:
```bash
raco make -v third_party/gui/gui-lib/mred/mred.rkt
raco make -v third_party/draw/draw-lib/racket/draw.rkt
PLT_QT=1 raco make -v third_party/gui/gui-lib/mred/private/wx/qt/queue.rkt
```

FFI-Load isoliert geprüft:
```racket
(define lib (ffi-lib ".../libracketqtshim.so"))
(define shim-version (get-ffi-obj "shim_version" lib (_fun -> _string)))
(shim-version)  →  "racketqtshim 0.2.0"  ✅
```

---

## Schritt 5 — Beispiele + Smoke

Startbefehl (Linux):
```bash
PLT_QT=1 QT_PLUGIN_PATH=~/Qt/6.11.1/gcc_64/plugins \
  racket -S third_party/gui/gui-lib -S third_party/draw/draw-lib examples/hello.rkt
```

### QPA-Plugin

Qt lädt `libqxcb.so` aus `QT_PLUGIN_PATH` (notwendig, da kein Qt-Launcher). Plugin lädt
fehlerfrei; kein `libxcb-cursor0`-Problem auf diesem System.

### hello.rkt ✅

- Fenster erscheint mit Cairo-Text und -Linie
- „Click me"-Button zählt Klicks hoch
- Keine Last in `top` im Idle

### input.rkt ✅

- Mausbewegung: Koordinaten live ohne Klick
- Mausklicks: Left/Right/Middle mit Koordinaten
- Tastatur: Zeichen + Modifier korrekt
- Fokuswechsel: funktioniert
- Timer-Box: bewegt sich flüssig (20-Hz-Redraw)

### editor.rkt ✅

- Text initial sichtbar
- Caret blinkt nach Klick
- Klick setzt Caret zur Klickposition
- Tippen: Text erscheint
- Drag-Selektion: funktioniert

### raco test tests/smoke.rkt

```
3 tests passed  ✅
```

---

## Der entscheidende Punkt — Event-Loop auf Linux

### Messung

`ps %cpu` meldet nach 5s ca. 45–85 % — das ist der **kumulative** Durchschnitt seit
Prozessstart und spiegelt die Bytecode-Kompilationsphase wider, nicht den Steady-State.

Instantane Messung (`top -b -n 2 -d 1`) nach 12s Startup:

```
racket  S   1,0 %
```

**→ ~1 % Idle-CPU. Kein Loop-Spin.**

### Befund

`shim_pump(0)` + Qt's glib/epoll-Backend verhält sich identisch zu macOS mit
CFRunLoop — der dritte unabhängige Datenpunkt bestätigt:

> **„Nie blockieren" (Timeout 0) ist die korrekte plattformübergreifende Invariante.**

Auf Linux registriert Qt intern glib-Quellen und epoll-FDs; da `shim_pump(0)` sofort
zurückkehrt, gerät der Racket-CS-Scheduler nicht in Konflikt mit diesen Primitiven.
`shim_events_pending()` gibt auf Linux 0 zurück, sodass Racket zwischen Pump-Thread-
Wakeups (alle 50 ms) schlafen kann.

---

## Bekannte Linux-Fallstricke (keine Probleme in dieser Session)

| Fallstrick | Status |
|---|---|
| Qt-Platform-Plugin xcb nicht gefunden | ✅ via `QT_PLUGIN_PATH` gelöst |
| `libxcb-cursor0` fehlt | ✅ vorhanden, kein Problem |
| Startup-CPU-Spike fehlgedeutet | ✅ dokumentiert — ist Kompilation, kein Spin |
| Wayland-Eigenheiten | ✅ nicht relevant — X11-Session |

---

## Commits

| Repo | Commit | Inhalt |
|---|---|---|
| Umbrella (main) | `5d7584c` | CMakePresets.json linux-x64, CLAUDE.md, HACKING.md §9 |
| gui-Fork (qt-backend) | `6169a245` | geerbt — keine Änderung nötig |

---

## Fazit

Das Qt-Backend ist jetzt auf drei Plattformen rauchgetestet:

| Plattform | Commit | Status |
|---|---|---|
| Windows x64 | Checkpoint D | ✅ |
| macOS arm64 | `6169a245` | ✅ |
| **Linux x64** | **`5d7584c`** | **✅** |

Der gepumpte Event-Loop ohne `QEventLoop::exec()` funktioniert plattformübergreifend.
Nächster Schritt: **Checkpoint E** — Widget-Breite (dialog%, message%, …) nach konkretem
App-Bedarf.

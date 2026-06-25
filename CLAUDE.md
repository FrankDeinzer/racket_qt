# CLAUDE.md — racket-qt

Qt Widgets backend ("wx/qt/") für `racket/gui`. Additiver Spike: aktiviert via `PLT_QT=1`, bestehende Backends (cocoa/gtk/win32) **nicht anfassen**.

## Fixe Regeln — niemals brechen

1. **Kein `QApplication::exec()`**, kein eigenes `QEventLoop`. Racket treibt die Loop; Qt wird gepumpt via `shim_pump(int max_ms)`.
2. **C→Racket-Callbacks** immer mit `#:atomic? #t` + `#:async-apply`. Sie dürfen **nur** Events in den Eventspace **posten**, niemals synchron aufrufen.
3. **`public*`/`override*`-Invariante:** Methoden, die ein Glue-Layer via `public*` hinzufügt, dürfen **nicht** in Platform-Klassen definiert sein (→ `method already defined`). Methoden, die via `override*` erwartet werden, **müssen** in der Platform-Klasse stehen (→ `no method to override`). Volle Tabelle: `docs/HACKING.md §1`.
4. **`queue-backing-flush` gibt `(void)` zurück** — nicht den Rückgabewert von `on-backing-flush`, sonst bricht `resume-flush`s `(->m void?)`-Kontrakt.
5. **`frame%.direct-show` ruft `register-frame-shown`** auf — sonst beendet sich das Programm sofort, weil der Eventspace keine offenen Fenster sieht.
6. **Zwei-Repo-Commits:** Änderungen an `wx/qt/` landen im gui-Submodul (`third_party/gui`, Branch `qt-backend`), dann Submodul-Zeiger im Umbrella (`main`) nachziehen.

## Umgebung

### Windows (primäre Entwicklungsmaschine)

| | |
|---|---|
| Racket | v8.18 [cs], x86-64 |
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

## Run / Smoke-Test

**Windows:**
```powershell
$env:PLT_QT = "1"
$env:PATH   = "C:\Qt\6.11.0\msvc2022_64\bin;" + $env:PATH
racket examples/hello.rkt
```

**macOS:**
```bash
PLT_QT=1 racket -S third_party/gui/gui-lib -S third_party/draw/draw-lib examples/hello.rkt
# Smoke tests:
PLT_QT=1 racket -S third_party/gui/gui-lib -S third_party/draw/draw-lib -l raco -- test tests/smoke.rkt
```

## Aktueller Checkpoint-Status

| Checkpoint | Status |
|---|---|
| A – Stub-Shim lädt via FFI | ✅ |
| B – Architektur dokumentiert | ✅ |
| C – frame% + canvas% + button% laufend | ✅ 2026-06-24 |
| **D – Eingabe-Rückgrat + Editor-Smoke** | **✅ 2026-06-25** |
| **macOS Smoke** | **✅ 2026-06-25** |
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

**Nächster Schritt: Checkpoint E** — Widget-Breite nach konkretem App-Bedarf.

## Dokumentation

| Datei | Inhalt |
|---|---|
| `docs/ARCHITECTURE.md` | Widget-Mapping, Shim-API, Event-Loop-Verdrahtung, Pixel-Format |
| `docs/HACKING.md` | `public*/override*`-Tabellen, Klassen-Ketten, Debugging-Guide, Checkliste neue Widgets |
| `docs/CHECKPOINT-D.md` | Detaillierter Plan für D-0 / D-1 / D-2 |
| `docs/BRIEF.md` | Originalbrief mit allen fixen Entscheidungen |

## Shim-Konventionen

- Shim-Handles (`void*`) im `handle`-Feld von `window%` (aus `wx/qt/window.rkt`)
- Alle FFI-Bindings in `wx/qt/utils.rkt`
- Shim bleibt minimal: nur das, was der aktuelle Milestone braucht
- Pixelformat: `CAIRO_FORMAT_ARGB32` ↔ `QImage::Format_ARGB32_Premultiplied`; `stride` aus `cairo_image_surface_get_stride()` (nie `width*4` annehmen)

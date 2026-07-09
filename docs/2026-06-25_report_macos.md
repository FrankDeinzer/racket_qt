# Bericht: macOS arm64 Bring-up
**Stand: 2026-06-25 — macOS Smoke abgeschlossen**

Dieser Bericht dokumentiert die macOS-Bring-up-Session vom 25.06.2026.
Ausgangspunkt: Checkpoint D war auf Windows abgeschlossen; das Ziel war,
denselben Stand auf macOS arm64 zum Laufen zu bringen (3/3 Smoke-Tests,
vertretbare CPU-Last bei laufenden Beispielen).

---

## 1. Umgebung

| | |
|---|---|
| Racket | v9.2 [cs], arm64 (Homebrew) |
| Qt | 6.11.0, `~/Qt/6.11.0/macos` |
| CMake | Ninja-Generator |
| Preset | `macos-arm64` → `qt-shim/build/macos-arm64` |
| Shim | `libracketqtshim.dylib` |

---

## 2. Änderungen im Einzelnen

### 2.1 CMake-Preset (Umbrella: `qt-shim/CMakePresets.json`)

Der `macos-arm64`-Preset hatte einen falschen Qt-Präfix-Pfad
(`/usr/local/Qt/...` statt `~/Qt/6.11.0/macos`). Korrekte Werte:

```json
{
  "name": "macos-arm64",
  "generator": "Ninja",
  "binaryDir": "${sourceDir}/build/macos-arm64",
  "cacheVariables": {
    "CMAKE_BUILD_TYPE": "Debug",
    "CMAKE_PREFIX_PATH": "/Users/deinzer/Qt/6.11.0/macos",
    "CMAKE_OSX_ARCHITECTURES": "arm64",
    "CMAKE_BUILD_RPATH": "/Users/deinzer/Qt/6.11.0/macos/lib"
  }
}
```

`CMAKE_BUILD_RPATH` ist nötig, damit die Dylib die Qt-Frameworks zur
Laufzeit findet, ohne `install_name_tool` oder `DYLD_LIBRARY_PATH`.

Build-Befehl:
```bash
cmake --preset macos-arm64 -S qt-shim
cmake --build qt-shim/build/macos-arm64
```

---

### 2.2 FFI-Pfad (gui-submodule: `wx/qt/utils.rkt`)

`ffi-lib` auf macOS mit absolutem Pfad hängt den `lib`-Prefix **nicht**
automatisch an und ergänzt keine Dateiendung. Der Aufruf muss den vollen
Dateinamen enthalten:

```racket
; FALSCH — funktioniert nur auf Windows
(ffi-lib "/pfad/zu/racketqtshim")

; RICHTIG — expliziter lib-Prefix + Erweiterung
(ffi-lib "/pfad/zu/libracketqtshim.dylib")
```

`utils.rkt` ist jetzt plattformabhängig via `(case (system-type 'os) ...)`:

| Platform | Dateiname |
|---|---|
| `windows` | `racketqtshim.dll` |
| `macosx` | `libracketqtshim.dylib` |
| sonst | `libracketqtshim.so` |

---

### 2.3 `designate-root-frame`-Stub (gui-submodule: `wx/qt/frame.rkt`)

Racket 9.2 ruft in `mrtop.rkt:349` `(send wx designate-root-frame)` auf.
In Racket 8.18 (Windows) existiert dieser Aufruf nicht. Da Cocoa/GTK/Win32
den Stub jeweils in ihrer `frame%`-Klasse haben, wurde er in der Qt-Klasse
ergänzt:

```racket
(define/public (designate-root-frame) (void))
```

Ohne diesen Stub gibt Racket 9.2 einen `no method to override`-Fehler beim
Erstellen des ersten Fensters.

---

### 2.4 CPU-Spin-Fix (gui-submodule: `wx/qt/queue.rkt`)

**Symptom:** `PLT_QT=1 racket ... examples/hello.rkt` verbrauchte dauerhaft
97–98 % CPU auf macOS — auch ohne offene Fenster.

**Ursache:** Die Pump-Thread-Schleife rief `(atomically (shim_pump 10))` auf.
`shim_pump(10)` ruft `QApplication::processEvents(AllEvents, 10)` auf, das
intern `CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false)` aufruft.
Dieses blockiert den OS-Thread für bis zu 10 ms — **während die Racket-
Atomic-Sperre gehalten wird**. Racket CS auf macOS nutzt denselben OS-Thread
für seinen Scheduler und schläft über mach-Port-Primitiven. Beide Mechanismen
stören sich gegenseitig und verhindern, dass der Scheduler in den Sleep-Modus
wechselt; stattdessen dreht er sich im Busy-Wait.

**Diagnose-Schritte:**
- `shim_pump 0` (0 ms) statt 10 → CPU normal → zeigt, dass der Timeout die
  Ursache ist, nicht die Callbacks selbst.
- `sample`-Output: 56 % CPU in JIT-kompiliertem Racket-Code, 26 % in `kevent`,
  17 % GC → Scheduler spinnt, kein normaler Sleep.
- Paint-Callback feuert nur 1×/2 s → kein Paint-Loop als Ursache.
- `shim_events_pending` gab immer 1 zurück → auf macOS auf 0 fixiert, kein
  Einfluss auf den Spin (aber vermeidet unnötige Scheduler-Wakeups).

**Fix:**

```racket
; Vorher:
(atomically (shim_pump 10))

; Nachher:
; 0ms: draining without waiting avoids CFRunLoopRunInMode holding the
; atomic lock and conflicting with Racket CS's mach-port sleep on macOS.
(atomically (shim_pump 0))
```

`processEvents(0)` entspricht `CFRunLoopRunInMode(mode, 0, false)`: alle
aktuell anstehenden Quellen werden sofort abgearbeitet, dann kehrt die
Funktion zurück, ohne zu warten. Der 50-ms-Sleep liefert das `sync/timeout`
im selben Loop.

---

### 2.5 `shim_events_pending` auf nicht-Windows (Umbrella: `qt-shim/src/shim.cpp`)

Auf macOS gab die Funktion immer 1 zurück, was den `set-check-queue!`-Hook
dazu veranlasste, dem Scheduler ständig „Events pending" zu melden. Jetzt:

```cpp
int shim_events_pending(void)
{
#ifdef _WIN32
    return (GetQueueStatus(QS_ALLINPUT) != 0) ? 1 : 0;
#else
    return 0;
#endif
}
```

---

## 3. Ergebnisse

### 3.1 Smoke-Tests

```
PLT_QT=1 racket -S third_party/gui/gui-lib -S third_party/draw/draw-lib \
    -l raco -- test tests/smoke.rkt
3 tests passed
```

### 3.2 CPU-Last (nach Fix, ca. 4 s nach Start)

| Beispiel | CPU idle |
|---|---|
| `examples/hello.rkt` | ~1 % |
| `examples/input.rkt` | ~28 % |
| `examples/editor.rkt` | ~11 % |

`input.rkt` hat einen 50-ms-Timer (20 Hz), der pro Tick ein Cairo-Bitmap
erstellt und auf Qt blit — das erklärt die 28 %. Das ist kein Bug.

---

## 4. Bekannte Fallstricke

### Bytecode-Kompilierung vor dem ersten Lauf

Ohne vorkompilierte `.zo`-Dateien kompiliert Racket alle Quelldateien beim
Start — das sieht aus wie 97 % CPU, ist aber Macro-Expansion, kein Bug im
Event-Loop. **Einmalig nach dem Checkout ausführen:**

```bash
raco make -v third_party/gui/gui-lib/mred/mred.rkt
raco make -v third_party/draw/draw-lib/racket/draw.rkt
```

Danach starten alle Beispiele in < 2 s.

### `QThreadStorage`-Warnung beim Beenden

```
QThreadStorage: entry 0 destroyed before end of thread 0x…
```

Erscheint beim Beenden via SIGINT (Ctrl-C). Harmlos — Qt räumt seine
internen Thread-Locals auf, nachdem der Racket-Thread already gone ist.
Kein Handlungsbedarf.

---

## 5. Commits

| Repo | Commit | Branch |
|---|---|---|
| gui-submodule (`third_party/gui`) | `6169a245` | `qt-backend` |
| Umbrella (`racket_qt`) | `cd11af5` | `main` |

---

## 6. Nächster Schritt

**Checkpoint E** — Widget-Breite: `dialog%`, `message%` und weitere Widgets
nach konkretem App-Bedarf implementieren.

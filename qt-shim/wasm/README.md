# qt-shim/wasm — Qt-WASM und Racket CS 9.3 in einem Modul

Status: **S4b erreicht** (Qt-Fenster + Racket im pthread im selben WASM-Modul, `racket/base`-Ausdruck wird
ausgewertet). Der Shim (`../src/shim.cpp`) ist hier noch **nicht** eingebunden (S4c). Hintergrund und Messwerte:
`docs/2026-10-15_report-wasm-macos.md`, `docs/HACKING.md` §85.

## Aufbau

- `main.cpp`: Qt-`main()` auf dem Browser-Hauptthread (`QApplication`, `exec()`), startet Racket in einem pthread.
  Qt-WASM läuft nicht unter `-sPROXY_TO_PTHREAD` (S4a), deshalb ist die Rollenverteilung umgekehrt zum Racket-PoC.
- `CMakeLists.txt`: übernimmt alle Racket-Eingaben aus dem Build des Forks `third_party/racket-wasm-backend`
  (`.work/racket/racket/src/build/cs/c`): Objekte, `libkernel.a`/`liblz4.a`/`librktio.a`, die zwölf Native-Bibliotheken
  (aus `wasm-deps/.wasm-deps-linkflags.txt`), die Preload-Dateien (Boot-Images, `collects`, `etc`, Schrift). Racket-`main()`
  kommt aus der `main_em.c` des Forks, übersetzt mit `-Dmain=racket_em_main` (kein Eingriff in den Fork).
- `tools/serve-and-run.mjs`: statischer COOP/COEP-Server + Headless-Chrome per DevTools-Protokoll (nur Node-Bordmittel),
  wartet auf `document.title === "BENCH-DONE"`, schreibt Konsole und Screenshot.

## Bauen und testen (macOS, nach einem fertigen `app`-Build des Forks)

```bash
source ~/emsdk/emsdk_env.sh          # emcc 4.0.7 -- Qt 6.11.2 WASM prüft die Version exakt
~/Qt/6.11.2/wasm_multithread/bin/qt-cmake -S qt-shim/wasm -B build/wasm -G Ninja \
    -DCMAKE_MAKE_PROGRAM=/opt/homebrew/bin/ninja -DQT_HOST_PATH=$HOME/Qt/6.11.2/macos -DCMAKE_BUILD_TYPE=Release
cmake --build build/wasm
EXTRA_WAIT=25 node qt-shim/wasm/tools/serve-and-run.mjs build/wasm racketqt_wasm.html /tmp/wasm-out 90
cat /tmp/wasm-out/console.txt        # racket-in-pthread: hello / 3
```

Ergebnis: ~45 MB `.wasm`, ~61 MB `.data` (Boot-Images, Kern-`collects`). Die Seite braucht
`Cross-Origin-Opener-Policy: same-origin` und `Cross-Origin-Embedder-Policy: require-corp`.

## Befunde beim Zusammenlinken

- Qt bringt gebündelte Kopien von FreeType, HarfBuzz, libpng, zlib, pcre2 und libjpeg mit; der Link mit denselben
  Bibliotheken aus dem PoC (Racket-Archive zuerst, dann Qt) lief **ohne** Symbolkollisionen. Das ist nicht garantiert
  stabil (nur Archivmitglieder, die tatsächlich gezogen werden, können kollidieren) und sollte bei neuen Abhängigkeiten
  erneut geprüft werden.
- `-sEXPORTED_RUNTIME_METHODS`/`-sEXPORTED_FUNCTIONS` müssen Qts und Rackets Listen vereinen (das letzte `-s` gewinnt).
- Racket-`main()` setzt `exit_after = 1`: nach dem Auswerten beendet `exit()` den Prozess. Für eine laufende GUI
  muss Racket später in einer Ereignisschleife bleiben.

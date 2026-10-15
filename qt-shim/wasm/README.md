# qt-shim/wasm — Qt-WASM und Racket CS 9.3 in einem Modul

Status: **echtes DrRacket läuft im Browser** (HACKING §85.14: `app/app.rkt` mit `drracket-core`, `test/drracket-main.rkt`, Run → `3`). Davor **S4d erreicht**: ein echtes `racket/gui`-Programm (`frame%`, `message%`, `button%`) läuft auf dem Qt-Backend im Browser,
echte Mausklicks erreichen den Racket-Callback und `set-label` schreibt zurück (`test/hello-gui.rkt`). `racket/gui/base` lädt in 0,6 s
(`test/load-profile.rkt` misst die Aufteilung). `test/canvas-editor.rkt` + `KEYS=…` in `serve-and-run.mjs`: Canvas-Zeichnen und Editor mit echter Tastatur laufen, ~2–3 ms je Taste nach dem Blit-Fix (vorher ~290 ms, `docs/HACKING.md` §85.10/§85.11). `CHROME_GPU=1` misst mit echter GPU. **S4c**: der Shim (`../src/shim.cpp`, unverändert) ist im Modul; Racket ruft ihn über die FFI
(`(ffi-lib #f)`), jeder `shim_*`-Aufruf läuft per Proxy auf dem Qt-Hauptthread, Qt-Callbacks kommen über eine Queue
zurück in den Racket-Thread (echter Mausklick in Chrome → Racket-Closure, Test `test/ffi-smoke.rkt`). Noch offen:
`wx/qt` (`racket/gui`) in das Image bringen (S4d). Hintergrund und Messwerte:
`docs/2026-10-15_report-wasm-macos.md`, `docs/HACKING.md` §85.

## Aufbau

- `main.cpp`: Qt-`main()` auf dem Browser-Hauptthread (`QApplication`, `exec()`), startet Racket in einem pthread.
  Qt-WASM läuft nicht unter `-sPROXY_TO_PTHREAD` (S4a), deshalb ist die Rollenverteilung umgekehrt zum Racket-PoC.
- `CMakeLists.txt`: übernimmt alle Racket-Eingaben aus dem Build des Forks `third_party/racket-wasm-backend`
  (`.work/racket/racket/src/build/cs/c`): Objekte, `libkernel.a`/`liblz4.a`/`librktio.a`, die zwölf Native-Bibliotheken
  (aus `wasm-deps/.wasm-deps-linkflags.txt`), die Preload-Dateien (Boot-Images, `collects`, `etc`, Schrift). Racket-`main()`
  kommt aus der `main_em.c` des Forks, übersetzt mit `-Dmain=racket_em_main` (kein Eingriff in den Fork).
- `tools/gen-proxies.py`: liest `shim.cpp` (alle `extern "C"`-Funktionen und Callback-Typedefs) und erzeugt
  `shim_wasm_proxy.cpp` (Wrapper `W_shim_*` mit synchronem Proxy auf den Hauptthread, je ein Trampolin pro Callback-Typ,
  Callback-Queue, `W_shim_pump` als Dispatcher im Racket-Thread), `wasm_shim.inc` (`Sforeign_symbol` je Eintrag) und
  `rqt_wasm_extras.inc` (bindet die `wasm_extras.inc` des Forks plus `wasm_shim.inc` ein). `boot.c` wird deshalb hier
  selbst übersetzt (gleiche Flags wie im Fork, aber `RACKET_EXTRA_FOREIGN_INC` zeigt auf `rqt_wasm_extras.inc`).
- `test/ffi-smoke.rkt`: wird als `/app/main.rkt` vorgeladen und von `main.cpp` per `(load …)` ausgeführt.
- `tools/serve-and-run.mjs`: statischer COOP/COEP-Server + Headless-Chrome per DevTools-Protokoll (nur Node-Bordmittel),
  wartet auf `document.title === "BENCH-DONE"`, schreibt Konsole und Screenshot.

## Bauen und testen (macOS, nach einem fertigen `app`-Build des Forks)

```bash
source ~/emsdk/emsdk_env.sh          # emcc 4.0.7 -- Qt 6.11.2 WASM prüft die Version exakt
~/Qt/6.11.2/wasm_multithread/bin/qt-cmake -S qt-shim/wasm -B build/wasm -G Ninja \
    -DCMAKE_MAKE_PROGRAM=/opt/homebrew/bin/ninja -DQT_HOST_PATH=$HOME/Qt/6.11.2/macos -DCMAKE_BUILD_TYPE=Release
cmake --build build/wasm
CLICK_AT="120,40;120,40" CLICK_AFTER=22 EXTRA_WAIT=6 node qt-shim/wasm/tools/serve-and-run.mjs build/wasm racketqt_wasm.html /tmp/wasm-out 90
cat /tmp/wasm-out/console.txt        # version, RESIZE …, BUTTON-CLICK 1 / 2 (echte Mausklicks via DevTools)
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

## Proxy-Schicht (S4c)

- **Aufrufe Racket → Qt:** `W_shim_x(...)` führt `shim_x` per `emscripten::ProxyingQueue::proxySync` auf dem Hauptthread aus
  und blockiert, bis das Ergebnis da ist (gemessen ~35 µs, `docs/HACKING.md` §85.1). Argumente, die in Racket-Speicher
  zeigen (z. B. Pixelpuffer), bleiben gültig, weil beide Threads denselben WASM-Speicher teilen.
- **Callbacks Qt → Racket:** Der Shim bekommt statt des Racket-Funktionszeigers ein Trampolin und einen heap-allozierten
  Record `{racket_cb, racket_ud}` als `ud`. Das Trampolin stellt `racket_cb(racket_ud, args…)` in eine Queue (String-
  Argumente werden kopiert); `W_shim_pump` (Registriername `shim_pump`) arbeitet sie im Racket-Thread ab. Ein Racket-
  Closure darf nur dort laufen, wo es erzeugt wurde (libffi-Closure-Tabelle pro Worker). `shim_pump` ruft **nicht**
  `processEvents` auf, die Qt-Schleife gehört dem Browser. Records werden bei erneuter Registrierung bzw. `shim_*_destroy` freigegeben (Allowlist `RELEASABLE`, Refcount gegen wartende Aufrufe; HACKING §85.12), alle anderen bleiben ein kleines Leck pro Registrierung.
- **Besonderheiten:** `shim_app_init` wird einmal von `main()` auf dem Qt-Thread aufgerufen (spätere Aufrufe aus Racket
  sind No-ops); `shim_app_quit` ist ein No-op. Callback-Parameter müssen direkt von einem `void* ud` gefolgt werden
  (der Generator bricht sonst ab).

## racket/gui im Modul (S4d)

Das Paket-Image (`racket/gui` mit **unserer** `gui-lib` aus `third_party/gui`, `draw-lib` und Abhängigkeiten, alle als `tpb32l`-
Bytecode) entsteht mit dem Orchestrator des Forks und wird als Dateibaum in das Modul vorgeladen:

```bash
# 1. Image bauen (Submodul racket-wasm-backend, emsdk aktiv; erstes Mal mit Netz zum Release-Katalog, danach aus dem Cache)
cd third_party/racket-wasm-backend && source ~/emsdk/emsdk_env.sh
racket build/main.rkt app ../../qt-shim/wasm/app --dest <out> --racket /opt/homebrew/bin/racket \
       --scheme $PWD/.work/racket/racket/src/ChezScheme/tarm64osx/bin/tarm64osx/scheme
# 2. Nutzlast entpacken (share.data + share.data.js -> Dateibaum)
python3 qt-shim/wasm/tools/unpack-share.py <out>/share.data.js <out>/share.data <tree>
# 3. Modul linken, mit Nutzlast und Programm
~/Qt/6.11.2/wasm_multithread/bin/qt-cmake -S qt-shim/wasm -B build/wasm -G Ninja -DCMAKE_MAKE_PROGRAM=<ninja> \
    -DQT_HOST_PATH=$HOME/Qt/6.11.2/macos -DCMAKE_BUILD_TYPE=Release \
    -DRACKET_SHARE_DIR=<tree> -DRACKET_QT_MAIN=$PWD/qt-shim/wasm/test/hello-gui.rkt
cmake --build build/wasm
# 4. Test (Klicks nach dem Laden, ~12 s)
CLICK_AT="549,38;549,38" CLICK_AFTER=12 EXTRA_WAIT=5 node qt-shim/wasm/tools/serve-and-run.mjs build/wasm racketqt_wasm.html /tmp/out 200
```

Nach jedem App-Build die `.zo` je Paket im entpackten Image zählen (`gui-lib` ≈ 424): Fehlt Bytecode, kompiliert Racket zur Laufzeit
und `racket/gui/base` braucht ~90 s statt 0,6 s.

- `main.cpp` setzt `PLT_QT=1` (die `platform.rkt` der `gui-lib` wählt damit das Qt-Backend) und lädt `/app/main.rkt`.
- `gui-lib/mred/private/wx/qt/utils.rkt` nutzt unter WASM (`(system-type 'target-machine)` = `tpb32l`) `(ffi-lib #f)` statt eines
  Bibliothekspfads. Auf den anderen Plattformen ändert das nichts.
- Der Orchestrator stagt lokale Pakete ohne `compiled/` (`stage-local-pkg!`): sonst gelangen hostnative `.zo` (z. B. `tarm64osx`)
  ins Image („incompatible fasl-object machine-type").
- Preload-Verzeichnisse und das Programm sind für Ninja unsichtbar; `links.rktd` der Nutzlast und `RACKET_QT_MAIN` sind
  deshalb als `LINK_DEPENDS` gesetzt (neue Nutzlast ⇒ Relink).

Der Orchestrator verwirft seine wiederverwendeten Final-Pass-Schatten selbst, wenn sich lokale Pakete (`third_party/gui`) ändern, und
prüft, dass jedes Modul ein `.zo` hat (HACKING §85.11); manuelles Cache-Löschen ist nicht nötig.

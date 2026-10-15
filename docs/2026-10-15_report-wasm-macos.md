# Machbarkeitsstudie: racket-qt auf WebAssembly (2026-10-15, macOS)

Status: Recherche, Messungen (Qt-Spike S1, Demo-Lauf S0), Fork und Submodul eingerichtet.
Aussagen mit „(Quelle)" stammen aus Webrecherche bzw. aus dem Quelltext des PoC und sind **nicht**
selbst nachgebaut, sofern nicht ausdrücklich „gemessen" dasteht.

## 1. Kurzfazit

1. **Qt-Seite ist machbar.** Qt 6.11.2 WASM (single + multithread) läuft mit emsdk **4.0.7** (Qt prüft
   die Emscripten-Version hart, brew-Emscripten 6.0.12 bricht ab). `qt-shim/src/shim.cpp` (3695 Zeilen)
   **kompiliert unverändert** für WASM (206 `shim_*`-Exporte, 0 Fehler/Warnungen). Gelinkt und gelaufen
   ist der Shim selbst noch nicht.
2. **Racket-Seite:** Kein offizieller WASM-Port, aber ein Proof of Concept läuft:
   `bradlord/racket-wasm-backend` (Racket CS über Emscripten-Chez, interpretierter pb-Bytecode `tpb32l`,
   pbchunk-Boot). **Gemessen:** `racket/draw` (Cairo/Pango über FFI) läuft in der Demo
   (Headless-Chrome-Screenshot, Beispiel „Racket draw bitmaps", 31 s von Laden bis Bild).
3. **Der PoC bringt bereits ein `racket/gui`-Backend mit** (`gui-backend/wx-wasm`, 2565 Zeilen, canvas-only,
   alle Widgets in Racket gezeichnet) und einen DrRacket-Port (`apps/drracket`). Das ist Weg B.
4. **Entscheidung:** Weg **A (Qt-WASM-Shim)** ist das Ziel. Weg B bleibt Messlatte und Rückfallposition.
   Die ersten Schritte (Racket-Basis auf 9.3 heben, Build) sind für beide identisch.
5. **Die Threading-/Callback-Architektur trägt** (Messung S1, Abschnitt 3): ein synchroner Aufruf
   Worker → Hauptthread kostet ~30 µs, Callbacks per Queue ~150 µs. Offen ist die Geschwindigkeit des
   pb-Interpreters mit echtem Racket-Code.

## 2. Gemessen und geprüft

| Prüfung | Ergebnis |
|---|---|
| Qt 6.11.2 `wasm_singlethread` / `wasm_multithread` | beide vorhanden, Widgets, Gui, OpenGL (ES 2/3), PrintSupport |
| Qt-Versionscheck | harter `FATAL_ERROR` bei abweichender Emscripten-Version |
| emsdk 4.0.7 | `emcc` 4.0.7, Qt-Konfiguration ohne Fehler |
| Hello-Widgets (`Qt6::Widgets`+`Qt6::OpenGL`) | baut für beide Kits (17,1 / 17,2 MB `.wasm`) |
| `shim.cpp` → `em++ -c` | OK, 206 Exporte |
| Demo `racket-wasm.netlify.app` im Headless-Chrome 155 | `crossOriginIsolated=true`; `racket/draw`-Beispiel zeichnet drei Kreise (Cairo über FFI) |
| Racket-Version der Demo | **v9.2.0.5-2026-07-02 [cs]** (Pin `6917300a`, Mai 2026), nicht 9.3 |
| Claude-in-Chrome-Erweiterung | nach Neustart mit `--chrome` verbunden: Tab öffnen, JS ausführen, Screenshot |
| Headless-CDP-Testaufbau | Node-Skript (eingebauter `WebSocket`), eigenes Profil, COOP/COEP-Server; Skripte im Scratchpad |

## 3. Messung S1: Qt im Hauptthread, „Racket-Ersatz" im Worker

Aufbau: Qt-Widgets-Anwendung (`wasm_multithread`, emsdk 4.0.7, Release). Qt läuft im Browser-Hauptthread,
ein pthread (QThread) ruft den Hauptthread wie `shim_*` per `QMetaObject::invokeMethod(…,
BlockingQueuedConnection)` auf. Chrome 155 headless (SwiftShader), Apple-Silicon-Mac, einmalige Messung.

| Messung | Median | p95 | Max |
|---|---|---|---|
| Trivialer synchroner Aufruf Worker → Hauptthread (3000×) | 35 µs | 55 µs | 895 µs |
| Aufruf mit Rückgabewert `QPushButton::sizeHint` (1000×) | 25 µs | 40 µs | 105 µs |
| Blit 640×480 ARGB: Kopie in den Backing-Puffer + `update()` (120×) | 5,0 ms | 5,1 ms | 5,3 ms |
| Callback Hauptthread → Worker über Queue im geteilten Speicher (250×, Polling alle 200 µs) | 155 µs | 225 µs | 235 µs |

- Alle 250 Callbacks kamen an. Beim Blit wurden 84 von 120 Frames gezeichnet (Qt fasst `update()` zusammen).
- **Bewertung:** Der Hop zwischen den Threads ist billig (100 Abfragen ≈ 3 ms). Der Blit ist der größte Posten
  und skaliert mit der Fläche (grob 4× bei 1400×900). Dirty-Rects wären später sinnvoll.
- **Nicht abgedeckt:** Der Worker ist C++, nicht Racket. Der pb-Interpreter (Cairo-Zeichnen, Widget-Aufbau)
  ist ungemessen und wahrscheinlich der eigentliche Engpass. Software-GL im Headless-Chrome kann von echter
  GPU abweichen. Der Spike nutzt `exec()` (Qt-Standard), im Zieldesign gibt es im Hauptthread keine eigene
  Racket-Loop.
- **Callback-Folgerung:** Der PoC dokumentiert, dass die libffi-Closure-Tabelle pro Worker lebt (Quelle:
  `build-wasm.md`). Qt-Callbacks dürfen daher nicht als Funktionszeiger direkt in Racket gerufen werden,
  sondern müssen in eine Queue im geteilten Speicher gestellt werden (passt zu Regel 2). Der Spike zeigt
  die Queue-Seite auf C++-Ebene, mit Racket dazwischen ist es noch ungeprüft.

## 3a. Messung S3: Racket 9.3 als WASM (Node) gegen natives Racket 9.3

Aufbau: `apps/node-repl` aus dem Fork gebaut (Pin `v9.3` = `bbf7dea8`, emsdk 4.0.7, Racket-Pakete aus dem
9.3-Release-Katalog). Banner: `Welcome to Racket v9.3-2026-10-15-bbf7dea831* [cs].` Ablauf: Skript über stdin
in `node racket.js`; Vergleich mit `racket -I racket` (native, arm64). Je drei native und zwei WASM-Läufe,
Ergebnisse stabil. Skript: `bench.rktl` (Scratchpad). Boot ca. 2 s, `racket.wasm` 33,5 MB, `racket.data` 61 MB.

| Messung | native | WASM (Node) | Faktor |
|---|---|---|---|
| `fib 30` | 6 ms | 170 ms | ~28× |
| 200k-Liste sortieren | 22 ms | 402 ms | ~18× |
| 100k `number->string` + `string-append` | 5 ms | 43 ms | ~9× |
| 1000 Ellipsen auf `bitmap%` 640×480 (Cairo) | 58 ms | 212 ms | ~3,6× |
| 300× `draw-text` (Pango) | 87 ms | 131 ms | ~1,5× |
| `get-argb-pixels` 640×480 | 4 ms | 139 ms | ~35× |

- **Aussage:** Reiner Racket-Code im pb-Interpreter ist 9–30× langsamer, Zeichnen in Cairo/Pango (C nach
  WASM kompiliert) nur 1,5–4×. Eine GUI besteht aus beidem; Layout, Klassenaufrufe (`send`) und
  Ereignisbehandlung laufen im Interpreter. Absolutwerte bleiben klein (Millisekunden bis wenige 100 ms für
  die gemessenen Arbeiten), aber Bildaufbau mit großen Pixelschleifen in Racket ist teuer. Die
  Zeilen- und Ereignislogik von `wx/qt` ist ungemessen.
- **Einschränkungen:** Node, nicht Chrome; eine Maschine; Pixelzahlen unterscheiden sich (WASM nutzt die
  mitgelieferte DejaVu-Schrift, nativ die Systemschrift), das ist kein Fehler.

## 4. Hindernisse im Detail

### 4.1 Racket CS auf WASM
- Chez' Backend ist sprungorientiert, WASM blockstrukturiert; ein nativer Backend ist laut mflatt der
  Hauptblocker (Quelle). Gangbar ist der pb-Interpreter als C-Programm mit Emscripten. Langsam, Faktor
  **nicht gemessen**.
- **Basis:** Der PoC wendet 20 Patches (plus Overlay, 31 Dateien unter `patches/`) auf Racket `6917300a`
  (9.2.0.5) an und wird über einen Racket-Orchestrator (`build/main.rkt`: `sync`, `apply`, `app`) gebaut.
  Der Racket-Baum wird nicht vendored, sondern nach `.work/racket` (gitignored) geklont.
- **Anhebung auf 9.3:** Pin `upstream.lock` auf Tag `v9.3` = `bbf7dea8` gesetzt (1853 Commits weiter, 117
  geänderte Dateien). Von den 20 Patches betreffen nur 4 Dateien, die sich seither geändert haben
  (`Makefile` +2/−2, `main.zuo` +1/−1, `rktio_poll_set.c` +1, `rktio_process.c` +6/−6).
- **Ergebnis `sync` + `apply` auf `v9.3` (gemessen):** Klon `bbf7dea8`, Racket-Version im Baum 9.3.0.0
  (passt zum Host-Racket 9.3). **19 von 20 Patches passten unverändert.** Einer brach:
  `patches/main.zuo.patch` (eine Kontextzeile: Racket 9.3 hat in `main.zuo` `"-D"` zu `"-DK"` geändert,
  Upstream-Commit `7e5c51a1` „build: fix `also-bc` to not check pkg dependencies"). Fix: die Kontextzeile
  im Patch angepasst, danach alle 20 Patches + Overlay angewendet (`delta applied`). Die Patch-Semantik
  ist unverändert (der Patch ergänzt selbst das Überspringen der Paketabhängigkeitsprüfung).
  Der Klon (`.work/`, 130 MB, gitignored) lässt das Submodul sauber.
- **Beim Bauen gefunden und im Fork behoben** (Details `build-wasm.md`, Abschnitt „qt-wasm"): pb-Bootdateien
  kommen in 9.3 aus `racket/pb` (`make fetch-pb`); der Host-Chez-Fund nahm fälschlich das WASM-Ziel `tpb32l`;
  macOS-bash 3.2; ungepinntes fribidi und meson-Nachlader (jetzt gepinnt, `--wrap-mode=nodownload`);
  `ppoll` in emcc 4.0.7 deklariert aber nicht implementiert (glib); Paketkatalog musste der 9.3-Release-
  Katalog sein (Standardkatalog liefert Entwicklungsstände über `git://github.com`).
- **Host-Chez** wird vom Orchestrator selbst gebaut (`./configure --threads`), kein externer Chez nötig. Das
  Host-Racket muss dieselbe Version wie der Baum haben (versionsgestempelt), also 9.3.

### 4.2 FFI und Shim-Anbindung
- WASM kennt kein `dlopen`; alles muss statisch in ein Modul. Der PoC patcht `ffi.c`/`foreign.c`/`pb.ss` und
  nutzt libffi 3.5.2 mit Closures über eine Funktionstabelle. Für unseren Shim braucht es eine Symboltabelle
  für die 206 `shim_*`-Funktionen.
- Der PoC bindet Cairo, Pango, GLib, HarfBuzz, FreeType, Fontconfig, expat, pixman, libpng, libjpeg-turbo,
  pcre2 über Rezepte in `wasm-deps/` (zwölf Tarballs mit SHA-256, sieben davon mit meson).
- In einem zweiten pthread (Places) schlägt der erste Foreign-Call fehl; der PoC deaktiviert Places auf
  `tpb32l` (`place.ss.patch`). Relevant für uns: FFI nur im Racket-Hauptworker.

### 4.3 Event-Loop (Regel 1)
- Browser-Hauptthread darf nicht blockieren. Qt löst `exec()` mit Asyncify (eine Suspend-Ebene) oder JSPI
  (nicht überall) (Quelle). Unser Muster (kein `exec()`, nicht-blockierendes `processEvents`) vermeidet das
  für Qt. Racket muss dem Browser die Kontrolle geben: der PoC löst es mit einem Worker
  (`-sPROXY_TO_PTHREAD`) und `Atomics.wait`.
- JSPI-Stand (Sekundärquelle, unbestätigt): Chrome stabil, Safari 27 Beta, Firefox Nightly.

## 5. Architekturvarianten

| | A: alles im Hauptthread | **B: Racket im Worker, Qt im Hauptthread (gewählt)** | C: Racket nativ/serverseitig |
|---|---|---|---|
| Idee | Racket-Scheduler gibt per Asyncify/JSPI ab | `wasm_multithread`: geteilter Speicher, Racket im pthread (wie der PoC), `shim_*` synchron auf den Hauptthread geproxied | Racket nativ, Protokoll über WebSocket |
| Regel 1 | `shim_pump(0)` im Scheduler | Qt-Loop gehört dem Browser, `shim_pump` wird No-op | entfällt |
| Regel 2 | unverändert | Qt-Callbacks stellen nur in eine Queue im geteilten Speicher | entfällt |
| Messung | – | **Spike S1: Hop ~30 µs, Callback ~150 µs** | – |

Hinweis: Die Spalte „B" bezeichnet hier die Threading-Variante; sie ist unabhängig von der Backend-Wahl
„A: Qt-WASM / B: `wx/wasm`" in Abschnitt 6.

## 6. Backend-Wahl: Qt-WASM (A) oder `wx/wasm` des PoC (B)

| | A: Qt-WASM-Shim | B: `wx/wasm` (PoC) |
|---|---|---|
| Racket-Seite | `wx/qt`: 6532 Zeilen | `wx/wasm`: 2565 Zeilen |
| C++-Seite | `shim.cpp`: 3695 Zeilen | keine |
| Widgets | echte Qt-Widgets | selbst gezeichnet (`racket/draw`) |
| Stand | kompiliert, nicht gelinkt | laut README Playwright-getestet (nicht nachgeprüft), Editor flackert |
| Aufwand | groß, mehrere Unbekannte | klein, existiert schon |

**Entscheidung (Nutzer, 2026-10-15): A.** Begründung: ein Backend für vier Ziele, native Widget-Optik und
Verhalten, Korrekturen in `wx/qt` kommen dem Browser zugute, `wx/qt` hat umfangreiche Verhaltenstests. Auch
nützlich: Bei A stößt man früh auf Performanceprobleme. Lizenz: alles wird frei zur Verfügung gestellt
(LGPL-Statik-Link unkritisch). Risiken von A: Qt-WASM-Grenzen (Popups/Menüs innerhalb der Seite, nur
`open()`-Dialoge, keine nativen Datei-/Farb-/Schriftdialoge), Interpreter-Geschwindigkeit, Größe/Ladezeit.
B bleibt Messlatte für Interpreter-Speed und Draw-Pfad.

## 7. Repo-Stand und Abhängigkeiten

- Fork `FrankDeinzer/racket-wasm-backend`, Arbeits-Branch **`qt-wasm`**; Submodul
  `third_party/racket-wasm-backend` (Umbrella `eb1b5e3`, Submodul `5b2e805`). Lokaler Remote des
  Submoduls steht auf SSH (wie `gui`); `.gitmodules` bleibt HTTPS.
- **Racket-Pakete/Downloads beim Build** (Regel 9, Ausführung durch den Nutzer): `sync` klont
  `racket/racket` (shallow), `wasm-deps` lädt zwölf Tarballs, `app` holt Racket-Pakete per `raco pkg`.
- **Werkzeuge:** vorhanden: emsdk 4.0.7, meson 1.12.1, ninja, pkg-config, cmake, make, autoconf, python3, git,
  xz, curl, node. `automake` fehlt, wird laut Rezepten voraussichtlich nicht gebraucht.
- **`gui-lib`-Konflikt:** Der PoC patcht die Standard-`gui-lib` (`package-patches/gui-lib/`), wir haben einen
  eigenen Fork (`third_party/gui`). Für Weg A muss `wx/qt` (nicht `wx/wasm`) in den WASM-Build, und die
  Cairo-FFI-Fixes (`package-patches/draw-lib/`) gehören langfristig in `third_party/draw`.

## 8. Spike-Leiter

| # | Experiment | Stand |
|---|---|---|
| S0 | FFI/`racket/draw` im PoC | **erledigt, belegt** (Headless-Lauf) |
| S1 | Qt-Spike: Hop-, Callback-, Blit-Kosten | **erledigt, gemessen** (Abschnitt 3) |
| S2 | Basis klären: Racket-Version und Patch-Rebase | **erledigt:** Pin `v9.3`, `sync` + `apply` laufen, 19/20 Patches unverändert, 1 Kontextzeile angepasst |
| S3 | Erster Build mit `racket/draw`, Interpreter-Messung | **erledigt:** Racket 9.3 [cs] als WASM unter Node, `racket/draw` läuft, Messung siehe Abschnitt 3a |
| S4 | Shim linken (Symboltabelle), Mini-`frame%` + `button%` über Qt-WASM | offen |

## 9. Auswirkungen auf die Projektregeln (zur Entscheidung)

- Regel 1: bleibt (kein `exec()` im Zieldesign); `shim_pump` wird unter WASM wirkungslos.
- Regel 2: bleibt, aber „Post in den Eventspace" wird zum Queue-Post über Threads.
- „Release statt from-source" (BRIEF.md): fällt für den WASM-Pfad (gepatchtes Upstream-Racket).
- Qt-Version: WASM-Kits liegen als 6.11.2 vor (Desktop 6.11.0/6.11.1); ein Angleich ist keine Voraussetzung.

## Quellen

- Racket Discourse: [Web-based Racket REPL running on WASM](https://racket.discourse.group/t/web-based-racket-repl-running-on-wasm/4277), [Scope for Work on Racket -> WASM?](https://racket.discourse.group/t/scope-for-work-on-racket-wasm/3556)
- GitHub: [bradlord/racket-wasm-backend](https://github.com/bradlord/racket-wasm-backend), Fork [FrankDeinzer/racket-wasm-backend](https://github.com/FrankDeinzer/racket-wasm-backend)
- Demo: [racket-wasm.netlify.app](https://racket-wasm.netlify.app/)
- Cal Poly: [Rasm (Matejka)](https://digitalcommons.calpoly.edu/theses/2469/), [wasm-pbchunk (Perlin)](https://digitalcommons.calpoly.edu/cgi/viewcontent.cgi?article=4306&context=theses)
- Qt: [Qt for WebAssembly status update (2024-06)](https://lists.qt-project.org/pipermail/development/2024-June/045384.html), [Qt for WebAssembly docs](https://doc.qt.io/QT-6/wasm.html)
- V8: [JSPI new API](https://v8.dev/blog/jspi-newapi)

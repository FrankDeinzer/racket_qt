ROLLE & ZIEL
Du bist auf dem macOS-Entwicklungsrechner. Das Qt-Backend (wx/qt) + das C++-Shim sind auf
Windows bis Checkpoint D bewiesen (der Editor läuft). macOS ist bisher KOMPLETT ungetestet.
Ziel: ein macOS-Bring-up-SMOKE — das Shim auf macOS bauen, von Racket laden lassen und die
vorhandenen Beispiele (hello, input, editor) + den Smoke-Test auf Windows-Parität bringen.
KEINE neuen Features. Die thesenentscheidende Frage: Läuft die gepumpte processEvents-Schleife
auf macOS' nativer Run-Loop?

UMGEBUNG (gegeben)
- macOS, Qt 6.11 Developer-Build vorhanden, CMake/Ninja/clang. Racket 8.18 CS (Release).
- Das Repo ist vorhanden: Umbrella + Submodul gui-Fork (Branch qt-backend) + draw-Fork.
- Du baust/testest nur auf macOS. Cross-Build ist kein Ziel.

ARBEITSWEISE
- Kleine Schritte, an Checkpoints anhalten, auf Review warten.
- Bei Unklarheit oder Risiko ANHALTEN und fragen — besonders beim Event-Loop (siehe unten).
- cocoa/gtk/win32 NICHT anfassen. Alles additiv und PLT_QT-gegated.
- Windows NICHT brechen: jede plattformspezifische Änderung (Ladepfad in utils.rkt, RPATH,
  Preset) additiv und über (system-type) erkannt, nicht ersetzend.

GELTENDE FIXENTSCHEIDUNGEN (nicht ändern; siehe CLAUDE.md)
- Event-Loop: Racket treibt, Qt wird gepumpt (shim_pump → processEvents). KEIN QApplication::exec(),
  KEIN QEventLoop. Diese Entscheidung ist fix und muss WASM-kompatibel bleiben — ändere die
  Schleife NICHT ohne Checkpoint.
- Callbacks #:atomic? #t, nur posten. Cairo→QImage→paintEvent. HiDPI auf 1 gepinnt. Kein App-Bundle.

SCHRITT 0 — Umgebung erkennen (bei Mismatch ANHALTEN)
- Bestätige Darwin; ermittle die Mac-Arch (arm64/x86_64) UND die Arch des racket-Binaries
  (z. B. `file` auf die von racket gemeldete exec-file). KRITISCH: Shim-Arch muss zur racket-Arch
  passen, sonst lädt die FFI die dylib gar nicht.
- Finde den Qt-6.11-macOS-Prefix (typisch ~/Qt/6.11.0/macos; sonst via `qmake6 -query
  QT_INSTALL_PREFIX` oder suchen). Die Frameworks liegen unter <prefix>/lib.
- Berichte Arch, Qt-Pfad, Toolchain. Bei fehlendem Qt/racket oder Arch-Mismatch: ANHALTEN.

SCHRITT 1 — macOS-Preset prüfen/ergänzen
- In qt-shim/CMakePresets.json das Preset für die erkannte Arch (macos-arm64 bzw. macos-x64)
  prüfen. Fehlt es: nach Vorbild des windows-Presets ergänzen — Generator Ninja,
  CMAKE_PREFIX_PATH = erkannter Qt-Prefix, CMAKE_OSX_ARCHITECTURES = erkannte Arch,
  CMAKE_BUILD_RPATH = <prefix>/lib (damit die dylib die Qt-Frameworks ohne DYLD_* findet).
- Ein Rechner pro Arch → den Qt-Pfad ins Preset committen ist ok.

SCHRITT 2 — Shim bauen
- cmake --preset macos-<arch> && cmake --build build/macos-<arch>
- Erwartung: shim.cpp ist portabler Qt-C++; WINDOWS_EXPORT_ALL_SYMBOLS ist auf macOS ein No-op
  (Symbole sind dort ohnehin sichtbar, die extern-"C"-Funktionen exportieren). Bei Build-/Link-
  Fehlern berichten, nicht raten.
- dylib verifizieren: `otool -L build/macos-<arch>/libracketqtshim.dylib` (linkt sie die Qt-
  Frameworks via @rpath?) und `otool -l … | grep -A2 LC_RPATH` (zeigt der RPATH auf Qts lib?).

SCHRITT 3 — FFI-Ladepfad plattformfähig machen
- utils.rkt lädt die Shim-Bibliothek aktuell vermutlich mit Windows-Pfad/-Endung. Mach die
  ffi-lib-Auflösung über (system-type) erkannt: korrektes build/<preset>/-Verzeichnis +
  Dateiname (Windows racketqtshim.dll / macOS libracketqtshim.dylib / Linux libracketqtshim.so).
  Additiv — der Windows-Pfad muss erhalten bleiben.
- ISOLIERT verifizieren, BEVOR die GUI startet: ein racket-Einzeiler, der die dylib via ffi-lib
  lädt und shim_version() ruft.

SCHRITT 4 — Beispiele + Smoke laufen lassen (Kern)
Starte wie examples/hello.rkt auf Windows, an macOS angepasst (PLT_QT=1, dieselben -S-Collection-
Flags für gui-lib und draw-lib). hello.rkt ist bereits der erste Loop-Test — hängt es, SOFORT
anhalten. Verifiziere der Reihe nach und berichte je Punkt KONKRET:
- hello.rkt: Fenster erscheint? Cairo-Text/Linien sichtbar? Button-Klick löst aus?
- input.rkt: Live-Mausbewegung (auch OHNE gedrückte Taste)? Klicks mit Koordinaten? getippte
  Zeichen + Modifier? Fokuswechsel? Bewegt sich die Timer-Box flüssig?
- editor.rkt: Text sichtbar, Caret blinkt, Klick setzt Caret, Tippen, Drag-Selektion?
- raco test tests/smoke.rkt: 3/3 grün?

DER ENTSCHEIDENDE PUNKT — Event-Loop auf macOS
macOS' native Run-Loop (CFRunLoop/Cocoa) ist der historisch zickige Fall für "kein exec()".
Achte gezielt: Kommen Events nur beim Mausbewegen an? Friert das Fenster? Beachball/Hang? Werden
Tasten/Timer verschluckt? Dauerhafte CPU-Last durch den 50ms-Poll?
WENN die gepumpte Schleife zickt: ANHALTEN und berichten — das ist ein thesenrelevanter Befund,
kein Detail. Ändere die Schleife NICHT eigenmächtig; jeder Eingriff muss Windows erhalten,
exec()-frei/WASM-kompatibel bleiben und wird vorher mit mir besprochen.
ERWARTETE, HARMLOSE macOS-Eigenheit (NICHT "fixen"): Ein nicht-gebündelter CLI-Prozess bekommt
evtl. kein Dock-Icon und kommt nicht automatisch in den Vordergrund — einmal aufs Fenster klicken,
um Fokus zu geben, ist für den Smoke ok. KEIN .app-Bundle, KEIN Info.plist (Deployment kommt
später). Nur falls das Fenster wirklich unbenutzbar bleibt (unsichtbar/reagiert nie): berichten.
HINWEIS: Die Racket-/Shim-Logik ist plattformidentisch — die Qt-button()/buttons()-Falle, die
Keyword-Args und das (yield)-Thema sind bereits gelöst und sollten auf macOS nicht erneut
auftreten. Neu sind NUR Build, Ladepfad und Laufzeit-Loop-Verhalten.

CHECKPOINT macOS: Anhalten. Zeig mir die erkannte Arch/Pfade, dass der Shim baut und lädt, und das
Verhalten der vier Punkte aus Schritt 4 — insbesondere das ehrliche Urteil zum Event-Loop.

LIEFERUNG & COMMITS
- CMakePresets.json (macOS-Preset/RPATH) und ggf. shim.cpp im Umbrella; utils.rkt (plattform-
  fähiger Ladepfad) im gui-Fork. Zwei-Repo-Commit, Submodul-Zeiger im Umbrella aktualisieren.
- STATUS.md (bzw. ein docs/report…md) um einen macOS-Abschnitt ergänzen; HACKING.md um etwaige
  macOS-Lektionen; die Checkpoint-Tabelle in CLAUDE.md um "macOS-Smoke" erweitern. ARCHITECTURE.md
  nur, wenn sich eine Fixentscheidung ändert (mit Begründung).
- Falls für den Smoke etwas fehlt, das AUCH auf Windows fehlt (z. B. Mausrad, Clipboard): NICHT
  implementieren — das ist Checkpoint E. Nur herstellen, was nötig ist, damit hello/input/editor/
  smoke auf macOS dem Windows-Stand entsprechen.
# Projekt-Brief (Original-Prompt)

> Dieses Dokument ist das ursprüngliche Briefing, das den Spike gestartet hat.
> Es wurde als Prompt an Claude übergeben. Die daraus abgeleiteten Entscheidungen
> sind in ARCHITECTURE.md dokumentiert; praktische Hinweise stehen in HACKING.md.

---
ROLLE & ZIEL
Du arbeitest in einem leeren, git-verwalteten Projekt. Ziel ist ein Spike: ein viertes
GUI-Backend "qt" für Rackets GUI-Toolkit (racket/gui) auf Basis von Qt WIDGETS (NICHT QML),
nur Desktop, lauffähig auf Windows, macOS und Linux. Es geht NICHT um Vollständigkeit, sondern
um eine lauffähige dünne vertikale Scheibe und eine geklärte, dokumentierte Architektur.

UMGEBUNG (gegeben — nicht neu installieren)
- Qt 6.11 (Developer-Build) ist auf allen drei OS vorhanden. Pro Architektur gibt es genau einen
  Entwicklungsrechner.
- Buildsystem: CMake mit Presets.
- Du baust/testest immer nur auf dem AKTUELLEN OS. Die anderen OS teste ich selbst. Cross-Build
  ist kein Ziel.
- Racket wird als Release-Installation genutzt. racket/racket und drracket werden NICHT
  from-source gebaut.

ARBEITSWEISE (wichtig)
- Orientiere dich, bevor du Code schreibst. Rate nicht. Bei Unklarheit/Risiko: HALTE AN, frag mich.
- Kleine Schritte, häufige kleine Commits. Halte an den CHECKPOINTS an und warte auf mein Review.
- Ändere die bestehenden Backends (cocoa/gtk/win32) NICHT. Das qt-Backend ist rein additiv und
  wird über die Umgebungsvariable PLT_QT aktiviert.
- Halte das C++-Shim minimal: nur die Teilmenge, die das jeweilige Milestone braucht.

ENTSCHEIDUNGEN (FIX — so umsetzen, nicht neu aufrollen)
- Toolkit: Qt Widgets. Kein QML.
- Event-Loop: RACKET TREIBT, Qt wird gepumpt. KEIN QApplication::exec(), KEIN eigenes QEventLoop
  (das bleibt auch für späteres WASM kompatibel). Alles Qt läuft auf Rackets Haupt-OS-Thread
  (QApplication dort erzeugen; KEIN zweiter OS-Thread für Racket). Das Shim exportiert einen
  nicht-blockierenden Pump shim_pump(int max_ms) -> QApplication::processEvents(AllEvents, max_ms),
  dazu shim_app_init()/shim_app_quit(). wx/qt/queue.rkt wird nach dem Vorbild von gtk/queue.rkt
  gebaut (kooperatives Pumpen eines Fremd-Toolkits aus dem Eventspace-Scheduler). Für den Spike:
  Pumpen mit beschränktem Timeout (Events abarbeiten, wenige ms schlafen) ist ok; echtes
  Aufwecken aus Qts Dispatcher ist dokumentierte Folgeaufgabe.
- Callback-Disziplin (KRITISCH): Qt-Slots feuern synchron INNERHALB von processEvents auf dem
  Racket-Hauptthread in einem atomaren Moment. C->Racket-Callbacks sind FFI-Callbacks mit
  #:atomic? #t und #:async-apply und dürfen NUR ein Event in die Queue des Ziel-Eventspaces
  POSTEN, niemals den Handler synchron ausführen. Vorbild: cocoa/queue.rkt. (Verstoß => Deadlock
  mit dem Scheduler oder GC-Kollision.)
- Zeichnen (Cairo wiederverwenden, NICHT QPainter neu erfinden): doppelt gepuffert.
  Das Shim hält pro Canvas ein Backing-QImage. QWidget::paintEvent kopiert NUR das Backing aufs
  Widget (synchron, KEIN Racket-Aufruf). Racket zeichnet über den vorhandenen Cairo-dc<%>-Pfad in
  eine Cairo-Image-Surface, ruft shim_canvas_blit_argb(handle, data, w, h, stride) (das Shim
  KOPIERT die Pixel in seinen eigenen Backing-Puffer) und dann shim_canvas_request_repaint
  (-> QWidget::update()). Expose/Resize aus Qt postet einen (atomaren, nur einreihenden)
  Repaint-Request-Callback nach Racket. Pixelformat: Cairo CAIRO_FORMAT_ARGB32 (prämultipliziert,
  32-bit native-endian) <-> QImage::Format_ARGB32_Premultiplied; stride aus
  cairo_image_surface_get_stride() als bytesPerLine (NICHT width*4 annehmen). Alle Zielarchs sind
  little-endian -> kein Endianness-Sonderfall. Das Shim linkt KEIN eigenes Cairo.
- HiDPI: für den Spike Device-Pixel-Ratio fest auf 1 pinnen (Qt und Racket skalieren sonst
  doppelt). In shim_app_init High-DPI-Skalierung deaktivieren (Qt 6: QT_SCALE_FACTOR=1 bzw.
  Rundungsrichtlinie ohne Skalierung) und Cairo 1:1 in Gerätepixeln rendern. Echtes HiDPI später.
- Deployment ist NICHT Spike-Thema. Kein App-Bundle, kein windeployqt/macdeployqt, kein statischer
  Build. Host-Prozess ist racket, das die Shim-Shared-Library per FFI lädt. Qt-Auffindung zur
  Laufzeit über RPATH (macOS/Linux, siehe Presets) bzw. PATH (Windows).

SCHRITT 0 — Umgebung erkennen (bei Fehlen/Mismatch melden, nicht raten)
Auf dem aktuellen OS ermitteln und berichten:
- OS + Architektur; `racket --version` UND die Architektur des racket-Binaries.
  KRITISCH: Shim und Qt müssen zur racket-Architektur passen (macOS arm64 vs x86_64; Qt 6 ist
  64-bit-only). Passt es nicht zusammen: STOPPEN und mich fragen.
- Exakter Qt-6.11-Prefix-Pfad dieses OS (z. B. Windows .../msvc2022_64, Linux .../gcc_64,
  macOS .../macos), CMake-Version, Ninja, C++-Compiler (MSVC/clang/gcc).

SCHRITT 1 — Projektstruktur, Submodule, Einhängen
Lege an:
- third_party/gui   -> git submodule: https://github.com/FrankDeinzer/racket_gui.git
- third_party/draw  -> git submodule: https://github.com/FrankDeinzer/racket_draw.git
  (racket/racket und drracket NICHT als Submodul bauen/einhängen.)
- qt-shim/   -> C++/Qt-Shim (CMake, baut eine Shared Library)
- examples/  -> kleine racket/gui-Testprogramme
- docs/      -> Notizen inkl. ARCHITECTURE.md
- README.md
Versionskompatibilität: gui-lib/draw-lib müssen zur laufenden Racket-Version passen. Ermittle die
Racket-Version und checke die Submodul-Forks auf dem passenden Release-Tag aus (z. B. v8.x),
NICHT blind auf master.
Hänge die zu bearbeitenden Pakete ins laufende Racket ein, sonst wirken Änderungen nicht: ersetze
das installierte gui-lib (und bei Bedarf draw-lib) durch den lokalen Submodul-Checkout via
`raco pkg update --link <pfad>`. Prüfe mit `raco pkg show gui-lib`, dass die lokale Version lädt.

SCHRITT 2 — CMake-Gerüst & Presets (Toolchain zuerst absichern)
qt-shim/CMakeLists.txt:
- cmake_minimum_required(VERSION 3.21); find_package(Qt6 REQUIRED COMPONENTS Core Gui Widgets)
  (6.11 wird über CMAKE_PREFIX_PATH aus dem Preset gefunden); qt_standard_project_setup()
  (aktiviert AUTOMOC — das Canvas ist ein QWidget mit paintEvent). C++17.
  add_library(racketqtshim SHARED ...); target_link_libraries(racketqtshim PRIVATE Qt6::Widgets).
- Symbol-Export portabel: set_target_properties(racketqtshim PROPERTIES
  WINDOWS_EXPORT_ALL_SYMBOLS ON) (Spike-tauglich; sonst exportiert Windows die extern-"C"-Symbole
  nicht und die DLL ist für die FFI leer). Das Shim linkt KEIN Cairo.
CMakePresets.json (committed, enthält Presets für ALLE drei OS; gebaut wird nur das aktuelle):
- Je OS ein configurePreset mit condition auf ${hostSystemName} (Windows / Darwin / Linux),
  benannt nach Architektur (windows-x64, macos-arm64 bzw. macos-x64, linux-x64 — nimm die in
  Schritt 0 erkannte Arch). binaryDir build/${presetName}. Generator: Windows ->
  "Visual Studio 17 2022" (findet MSVC selbst, kein vcvars nötig); macOS/Linux -> Ninja
  (CMAKE_BUILD_TYPE=Debug). cacheVariables je Preset:
  * CMAKE_PREFIX_PATH = der in Schritt 0 ermittelte Qt-6.11-Pfad dieses OS.
  * macOS: CMAKE_OSX_ARCHITECTURES = erkannte racket-Arch.
  * macOS/Linux: CMAKE_BUILD_RPATH = Qts lib-Verzeichnis (RPATH ins Shim backen, damit Qt ohne
    DYLD_*/LD_LIBRARY_PATH gefunden wird; CMake setzt den Build-Tree-RPATH meist ohnehin —
    explizit als Absicherung).
  Dazu passende buildPresets. (Windows-RPATH gibt es nicht: zum Start Qts bin auf den PATH.)
- Stub: exportiere zunächst EINE triviale extern-"C"-Funktion shim_version().
- Baue das Stub-Shim mit dem Preset des aktuellen OS und lade es testweise per Racket-FFI
  (ffi/unsafe -> ffi-lib mit ABSOLUTEM Pfad auf die gebaute .dll/.dylib/.so in build/<preset>/).
CHECKPOINT A: Stoppen. Zeig mir Struktur, erkannte Versionen/Pfade/Arch, die Presets, und dass das
Stub-Shim baut UND sich aus Racket laden lässt.

SCHRITT 3 — Orientierung (lesen, nicht schreiben), Ergebnis nach docs/ARCHITECTURE.md
- third_party/gui/gui-lib/mred/private/wx/common/ : die plattformunabhängige Backend-Schnittstelle
  = der VERTRAG, den "qt" erfüllen muss. Welche Klassen/Methoden?
- wx/gtk/ als Vorlage; für die Event-Loop zusätzlich queue.rkt aller drei Backends vergleichen
  (Linux: gtk, macOS: cocoa, Windows: win32) — Fokus auf das #:atomic?/#:async-apply-Callbackmuster.
- Backend-Auswahl: wo wählt racket/gui heute das Backend (plattformgesteuert)? PLT_GTK2 ist der
  Präzedenzfall für einen Env-Var-Schalter; finde die Dispatch-Stelle und plane das PLT_QT-Gate.
- Cairo-Surface/dc<%>-Pfad in gui (canvas/dc) und draw-lib soweit verstehen, dass der
  render-then-blit-Pfad (siehe ENTSCHEIDUNGEN) klar ist.
Lege in ARCHITECTURE.md fest: (1) Mapping racket/gui <-> Qt Widgets (frame% <-> QMainWindow/QWidget,
button% <-> QPushButton (Klick: Lambda an QPushButton::clicked, das den C-Callback ruft),
canvas% <-> QWidget+paintEvent, menu% <-> QMenu ...). (2) Die vorgeschlagene, bei CHECKPOINT B zu
fixierende extern-"C"-Shim-API (app_init/app_quit/pump, window_create/show, canvas_create/
blit_argb/request_repaint, button_create + Callback-Registrierung). (3) Die konkrete Verdrahtung
der FIX-Entscheidungen zu Event-Loop und Callbacks auf diesem OS. (4) offene Fragen.
CHECKPOINT B: Stoppen. Ich reviewe Vertrag, Mapping und Shim-API.

SCHRITT 4 — Erstes Milestone (dünne vertikale Scheibe)
Implementiere NUR so viel, dass dieses examples/-Programm mit PLT_QT=1 läuft:
- ein frame% öffnet ein Fenster
- darin ein canvas%, dessen on-paint über den Cairo-dc<%>-Pfad zeichnet (Linien/Text); Anzeige
  per Backing-QImage/render-then-blit wie unter ENTSCHEIDUNGEN
- ein button%, dessen Qt-Klick (Lambda an clicked -> atomarer, nur einreihender C-Callback) sichtbar
  etwas tut (Zähler erhöhen / Canvas neu zeichnen)
- lauffähig unter Rackets gepumptem Qt-Loop, zunächst mit EINEM Eventspace.
NICHT im Milestone: weitere Controls, Dialoge, Textfelder, Editor-Toolkit (text%/snip%), DrRacket,
mehrere Eventspaces, HiDPI.
CHECKPOINT C: Demonstriere das laufende Beispiel, committe, und fasse zusammen, was am
Backend-Vertrag, an der Event-Loop und an der Cairo<->Qt-Übergabe härter war als erwartet.

LIEFERUNG & COMMITS
- docs/ARCHITECTURE.md, third_party/gui/.../wx/qt/ (im gui-Fork committed), qt-shim/ (CMakeLists +
  CMakePresets.json + C++), examples/, README (Build/Run mit Preset und PLT_QT, inkl. Windows-PATH-
  bzw. RPATH-Hinweis).
- Commits landen in ZWEI Repos: Umbrella + gui-Submodul (mein Fork). Committe in beiden und
  aktualisiere den Submodul-Zeiger im Umbrella.
  
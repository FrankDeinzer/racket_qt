ROLLE & ZIEL
Linux-Bring-up-SMOKE. Das Qt-Backend (wx/qt) + C++-Shim sind auf Windows und macOS bis
Checkpoint D bewiesen (der Editor läuft). Ziel: denselben Stand auf Linux x64 — Shim bauen,
von Racket laden, hello/input/editor + Smoke-Test auf Parität bringen. KEINE neuen Features.
Thesenentscheidende Frage: der dritte unabhängige Datenpunkt zur gepumpten Schleife — läuft
shim_pump(0) + Racket-Sleep auf Linux (glib/epoll) sauber, oder zeigt Linux eine eigene Eigenheit?

WICHTIG — fast alles ist schon gelöst und wird VERERBT, nicht neu gebaut. Die macOS-Session hat
auf demselben Branch qt-backend bereits hinterlegt: den plattformfähigen FFI-Ladepfad in utils.rkt
(else-Zweig → .so), den Pump-Fix shim_pump(0) in queue.rkt, shim_events_pending→0 auf
nicht-Windows, und den designate-root-frame-Stub für Racket 9.2. Deine Aufgabe ist überwiegend:
aktuellen Stand ziehen, Linux-Preset stimmen, bauen, laufen lassen, das Loop-/CPU-Verhalten ehrlich
beobachten. Leite gelöste Dinge NICHT neu her.

UMGEBUNG (gegeben — nichts installieren)
- Linux x64, Qt 6.11 Developer-Build vorhanden, CMake/Ninja/gcc. Racket 9.2 CS (Projekt-Standard).
- Repo vorhanden: Umbrella + Submodul gui-Fork (Branch qt-backend) + draw-Fork.
- Nur Linux bauen/testen. Cross-Build kein Ziel.

ARBEITSWEISE
- Kleine Schritte, an Checkpoints anhalten, auf Review warten.
- Bei Unklarheit/Risiko ANHALTEN und fragen — besonders beim Event-Loop.
- cocoa/gtk/win32 NICHT anfassen. Additiv, PLT_QT-gegated. Windows/macOS NICHT brechen: jede
  plattformspezifische Änderung additiv und über (system-type) erkannt, nicht ersetzend.

GELTENDE FIXENTSCHEIDUNGEN (siehe CLAUDE.md; nicht ändern)
- Event-Loop: Racket treibt, Qt wird gepumpt. KEIN exec(), KEIN QEventLoop.
- Der Pump blockiert NIE: Timeout 0 (shim_pump(0)). Das ist die verallgemeinerte Lehre aus dem
  macOS-CPU-Spin (CFRunLoopRunInMode hielt die Atomic-Sperre und kollidierte mit dem mach-Port-
  Sleep des CS-Schedulers); auf Linux gilt sie genauso. Ändere die Schleife NICHT ohne Checkpoint;
  jeder Eingriff muss Windows+macOS erhalten und exec()-frei/WASM-kompatibel bleiben.
- Callbacks #:atomic? #t, nur posten. Cairo→QImage→paintEvent. HiDPI=1. Kein Bundle.

SCHRITT 0 — Umgebung erkennen (bei Mismatch ANHALTEN)
- Bestätige Linux + x86_64; ermittle die Arch des racket-Binaries.
- racket --version MUSS 9.2 [cs] sein (Projekt-Standard, identisch zu Windows/macOS). Weicht es ab
  (oft liefern Distro-Pakete eine ältere Version): ANHALTEN und melden — Versionsdrift ist ein
  bekannter, teurer Fallstrick (siehe designate-root-frame).
- Qt-6.11-Linux-Prefix finden (typisch ~/Qt/6.11.0/gcc_64; sonst `qmake6 -query QT_INSTALL_PREFIX`).
  Libs unter <prefix>/lib, Plugins unter <prefix>/plugins.
- GRAFISCHE SITZUNG prüfen: ist DISPLAY (X11) oder WAYLAND_DISPLAY (Wayland) gesetzt? Ohne Display
  können die visuellen Checks (Caret, Drag) nicht laufen. Melde, was aktiv ist.
- Berichte Arch, Racket-Version, Qt-Pfad, Session-Typ. Bei Versions-/Display-/Qt-Problem: ANHALTEN.

SCHRITT 1 — Stand angleichen (macOS-Fixes erben)
- Submodule initialisieren/aktualisieren. Stelle sicher, dass der gui-Fork auf der SPITZE von
  qt-backend steht — inkl. des macOS-Commits 6169a245 (oder neuer). Nur so erbst du utils.rkt(.so),
  shim_pump(0), events_pending→0 und den 9.2-Stub. Verifiziere den Commit-Hash git-seitig und melde
  ihn.
- Damit sollte am Racket-Code NICHTS Neues nötig sein. Falls beim Laden doch ein versionsbedingter
  „no method to override"/„already defined" auftaucht (9.2-Eigenheit, die auf macOS nicht ansprang):
  nach dem additiven-Stub-Muster aus §2.3 des macOS-Berichts lösen und melden.

SCHRITT 2 — Linux-Preset prüfen/ergänzen
- In qt-shim/CMakePresets.json das linux-x64-Preset prüfen. Fehlt es oder ist der Qt-Pfad falsch
  (das war auf macOS der Fall): nach Vorbild der anderen Presets setzen — Generator Ninja,
  CMAKE_PREFIX_PATH = erkannter gcc_64-Prefix, CMAKE_BUILD_RPATH = <prefix>/lib (damit die .so die
  Qt-Libs ohne LD_LIBRARY_PATH findet). Ein Rechner pro Arch → Pfad ins Preset committen ist ok.

SCHRITT 3 — Shim bauen
- cmake --preset linux-x64 -S qt-shim && cmake --build qt-shim/build/linux-x64
- Erwartung: shim.cpp ist portabler Qt-C++; WINDOWS_EXPORT_ALL_SYMBOLS ist auf Linux ein No-op
  (extern-"C"-Symbole sind mit Default-Visibility ohnehin sichtbar). Bei Build-/Link-Fehlern melden.
- Verifizieren: `ldd build/linux-x64/libracketqtshim.so` (löst es libQt6Widgets.so.6 etc. via RPATH
  auf?) und `readelf -d … | grep -E 'RPATH|RUNPATH'` (zeigt der Pfad auf <prefix>/lib?).

SCHRITT 4 — Bytecode vorkompilieren (DAMIT die CPU-Messung ehrlich ist)
KRITISCH vor jedem CPU-Urteil — sonst sieht Macro-Expansion beim ersten Start wie 97 % Spin aus
(genau die macOS-Falle, §4):
  raco make -v third_party/gui/gui-lib/mred/mred.rkt
  raco make -v third_party/draw/draw-lib/racket/draw.rkt
Danach den FFI-Ladepfad ISOLIERT prüfen: ein racket-Einzeiler, der die .so via ffi-lib lädt und
shim_version() ruft — BEVOR die GUI startet.

SCHRITT 5 — Beispiele + Smoke (Kern)
Starte wie auf den anderen Plattformen (PLT_QT=1, -S für gui-lib und draw-lib). Verifiziere und
berichte je Punkt KONKRET:
- hello.rkt: Fenster? Cairo-Text/Linien? Button-Klick? — UND die Idle-CPU nach ~4 s (Erwartung
  niedrig, ~1–wenige %).
- input.rkt: Live-Mausbewegung (auch OHNE Taste)? Klicks mit Koordinaten? getippte Zeichen +
  Modifier? Fokuswechsel? Timer-Box flüssig? (Erhöhte CPU hier ist erwartbar — 20-Hz-Redraw, kein
  Bug; auf macOS ~28 %.)
- editor.rkt: Text sichtbar, Caret blinkt, Klick setzt Caret, Tippen, Drag-Selektion?
- raco test tests/smoke.rkt: 3/3 grün?

DER ENTSCHEIDENDE PUNKT — Event-Loop auf Linux (dritter Datenpunkt)
Qt nutzt auf Linux unter der Haube glib/epoll — ein anderes Sleep-Primitiv als Windows oder macOS'
CFRunLoop. Zwei plausible Ausgänge: (a) mit shim_pump(0) läuft es sofort sauber (bestätigt „nie
blockieren" als richtige Verallgemeinerung), oder (b) eine dritte Eigenheit zeigt sich. Achte
gezielt: dauerhafte hohe Idle-CPU bei hello.rkt? Fenster friert/reagiert verzögert? Events nur bei
Mausbewegung? Tasten/Timer verschluckt?
WENN die Schleife zickt: ANHALTEN und berichten — thesenrelevanter Befund, kein Detail. Schleife
NICHT eigenmächtig ändern (siehe Fixentscheidungen).

LINUX-SPEZIFISCHE FALLSTRICKE (kennen, gezielt prüfen)
- Qt-Plattform-Plugin: Beim Start lädt Qt ein QPA-Plugin (xcb für X11, wayland für Wayland) aus
  <prefix>/plugins/platforms. Da wir die .so in den racket-Prozess laden, kann die Plugin-Suche
  fehlschlagen: „Could not load the Qt platform plugin 'xcb'/'wayland'". Fix dann:
  QT_QPA_PLATFORM_PLUGIN_PATH=<prefix>/plugins/platforms (oder QT_PLUGIN_PATH=<prefix>/plugins).
  Melde, welches Plugin aktiv ist.
- Bekannte Qt-6-Hürde: das xcb-Plugin braucht libxcb-cursor0 (xcb-util-cursor). Fehlt es, scheitert
  xcb mit „... even though it was found". Falls das auftritt: melden (Systempaket, nicht raten).
- X11 vs Wayland: Für den Smoke ist beides ok. Falls auf Wayland etwas seltsam ist (Platzierung,
  Fokus), zum Gegentest QT_QPA_PLATFORM=xcb erzwingen — nur diagnostisch, nicht als „Fix".
- Headless-Fallback: Ohne Display laufen die NICHT-visuellen Teile (raco-test-Konstruktion,
  Loop/CPU) unter QT_QPA_PLATFORM=offscreen; die visuellen Checks (Caret/Drag) brauchen ein echtes
  Display — diese dann als „nicht verifizierbar" melden, nicht überspringen-und-behaupten.

HINWEIS: Racket-/Shim-Logik ist plattformidentisch — die Qt-button()/buttons()-Falle, Keyword-Args
und das (yield)-Thema sind gelöst und sollten auf Linux nicht erneut auftreten. Neu sind NUR Build,
Plugin-/Display-Pfad und Laufzeit-Loop-Verhalten.

CHECKPOINT Linux: Anhalten. Zeig mir Arch/Racket-Version/Qt-Pfad/Session-Typ + den
gui-Submodul-Commit, dass der Shim baut und lädt, das aktive QPA-Plugin, und das Verhalten der vier
Checks aus Schritt 5 — insbesondere das ehrliche Loop-/CPU-Urteil.

LIEFERUNG & COMMITS
- Wahrscheinlich nur CMakePresets.json (linux-x64-Preset/RPATH) im Umbrella; der Racket-Code ist vom
  qt-backend-Branch geerbt. Falls doch ein 9.2-Stub o. Ä. nötig war, gehört der in den gui-Fork.
- Bei Code-Änderung: Zwei-Repo-Commit, Submodul-Zeiger im Umbrella aktualisieren.
- STATUS.md (bzw. docs/report…md) um einen Linux-Abschnitt; HACKING.md um etwaige Linux-Lektionen
  (Plugin-Pfad, libxcb-cursor); Checkpoint-Tabelle in CLAUDE.md um „Linux-Smoke". ARCHITECTURE.md
  nur bei geänderter Fixentscheidung.
- Was AUCH auf Windows/macOS fehlt (Mausrad, Clipboard): NICHT implementieren — das ist Checkpoint E.


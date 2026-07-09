# Beobachtung — Menüleisten-/Redraw-Diagnose auf Linux (Phase 3, 2026-07-07_prompt)

**Datum:** 2026-07-07
**Plattform:** Kubuntu 22.04 (Plasma/KDE, X11, `kwin_x11`), x86_64
**Racket:** v9.2 [cs] · **Qt:** 6.11.1 (`~/Qt/6.11.1/gcc_64`, xcb-Plugin)
**Repro:** `examples/menu-frame.rkt` (frame% + menu-bar% + menu% + menu-item% + editor-canvas% + text%)
**Startrezept:** `PLT_QT=1 QT_PLUGIN_PATH=~/Qt/6.11.1/gcc_64/plugins racket -S third_party/gui/gui-lib -S third_party/draw/draw-lib examples/menu-frame.rkt`

> Reine Diagnose — kein Fix, kein Geometrie-/Rendering-Eingriff. Screenshots liegen im
> Session-scratchpad (out-of-band an den Nutzer, NICHT im Repo).

## Re-Sync-Status (Phase 1/2)

- Repo-Check vor Beginn: Umbrella `main` sauber, `origin/main` aktuell (kein Pull nötig).
  gui-Submodul stand **detached** auf `6169a245` (vor-Merge-Stand, 1.78-Ära), Umbrella-Zeiger
  erwartete bereits `381425d5` (1.80) → Submodul war hinter dem Zeiger, kein lokaler
  `qt-backend`-Branch existierte (nur `master` lokal, `origin/qt-backend` vorhanden).
- `git -C third_party/gui checkout -b qt-backend --track origin/qt-backend` → sauberer
  Fast-Forward `6169a245` → `381425d5` (bestätigt: `6169a245` ist Vorfahre von
  `381425d5`/`origin/qt-backend`). `git submodule update --init` danach No-Op (Zeiger
  stimmte bereits überein).
- `gui-lib/info.rkt` version = **1.80**; Merge-Commit `2d6325d9` in der `qt-backend`-Historie
  bestätigt.
- Konsum-Modell auf dieser Maschine: **`-S`-Source-Override** (`raco pkg show gui-lib` zeigt
  das reguläre Katalog-Paket auf Upstream-Commit `3f0037c0`, NICHT verlinkt) → wie macOS.
- **10 stale `compiled/`-Verzeichnisse** gefunden (Datum 29. Juni, also vor dem 1.80-Merge
  vom 2. Juli) unter `third_party/gui` + `third_party/draw` → gelöscht.
- **Shim war stale:** `qt-shim/src/shim.cpp` zuletzt inhaltlich geändert am 30. Juni
  (E-0 Widget-Stubs: menu/dialog/label), gebaute `libracketqtshim.so` aber vom 29. Juni →
  fehlten dieselben Symbole wie im macOS-Fall. Neu gebaut via
  `cmake --build qt-shim/build/linux-x64`.
- Fork neu gebaut: `raco make` für `mred/mred.rkt`, `draw/racket/draw.rkt`,
  `PLT_QT=1 raco make .../wx/qt/queue.rkt` — alle drei sauber ohne Fehler.
- Re-Smoke: **3/3 pass** (`raco test tests/smoke.rkt`).
- **Keine neuen Commits durch den Sync** (reiner Branch-Checkout + Rebuild, kein Merge/Reset
  nötig).

## Vier Beobachtungspunkte

### 1. Menüleiste sichtbar? Wo?
- **Keine Menüleiste sichtbar — weder im Fenster noch irgendwo global.** Der Screenshot
  zeigt direkt unter der Titelleiste („E-0 Menu Test“, KDE-Fensterdekoration) sofort den
  `editor-canvas%`-Inhalt — kein reservierter Platz, keine leere Leiste, keine sichtbare
  `File`-Beschriftung. Anders als macOS gibt es unter Plasma/KWin **kein** systemweites
  globales Menüband an dieser Stelle (kein Panel-Widget für globale Menüs aktiv) — die
  Leiste fehlt also nicht nur "am falschen Ort", sie fehlt komplett.
- Auffälliger Fund währenddessen: `xwininfo -root -tree` zeigt ein Zusatzfenster
  `"Qt Selection Owner for gmenudbusmenuproxy"` (0x0-Overlay-Fenster) — Qt registriert den
  `QMenuBar` für den DBus-Menu-Export (analog zu Ubuntus/Unity globalem Menü), obwohl auf
  diesem Plasma-Desktop kein Consumer dafür läuft.
- **Diskriminierender Test:** Neustart mit `QT_QPA_PLATFORMTHEME=` (leer, deaktiviert das
  KDE-Platform-Theme-Plugin) → **kein Unterschied**, Menüleiste bleibt komplett unsichtbar.
  → Das Verschwinden ist **nicht** (allein) durch das KDE-Platformtheme-Plugin bzw. dessen
  Global-Menu-Redirect erklärbar; es scheint tiefer zu sitzen (z. B. QMenuBar bekommt nie
  eine reservierte Höhe > 0 im `QMainWindow`-Layout).

### 2. Öffnet ein Klick einen Top-Level-Titel?
- **Nicht automatisiert testbar in dieser Umgebung:** kein `xdotool`/`ydotool`/`wtype`
  installiert, kein passwortloses `sudo` verfügbar, um es nachzurüsten. Da ohnehin **kein**
  Top-Level-Titel sichtbar ist (Punkt 1), wäre ein Klick-Test auch bei vorhandenem Tool
  gegenstandslos — es gibt nichts anzuklicken. Manueller Test durch den Nutzer nötig, falls
  das noch relevant wird.

### 3. Rendering-Artefakte im oberen Bereich?
- **Keine** Überlappung, keine doppelten Elemente, keine weißen Rechtecke. Titelleiste sauber
  gezeichnet. Der Übergang Titelleiste → Editor-Inhalt ist nahtlos (kein Leerraum, kein
  Rest einer nicht gerenderten Leiste) — konsistent mit "Menüleiste hat Höhe 0", nicht mit
  "Menüleiste ist da, aber leer gezeichnet".

### 4. Zeichnet der zentrale editor-canvas% sauber?
- Da kein OS-Input-Simulationswerkzeug verfügbar war, wurde eine **programmatische
  Tipp-Simulation** verwendet (Diagnose-Kopie `menu-frame-observe.rkt` im Scratchpad,
  NICHT im Repo: `(send txt insert (string ch))` zeichenweise mit `sleep/yield` zwischen den
  Schritten) statt echter Tastatur-Events — exercisiert denselben Insert+Redraw-Pfad, ist
  aber kein 1:1-Ersatz für echte Keystroke-Events.
- **Live-„getippter" (programmatisch eingefügter) Text rendert korrekt und bleibt stabil**
  (`ABCD EFGH IJKL MNOP` vollständig sichtbar samt Caret nach mehreren Insert-Batches mit
  Pausen dazwischen) — kein Blank, keine Korruption in diesem Test beobachtet.
- **Der VOR der Interaktion per `insert` gesetzte Text (`"Hello from Qt + menu!\n"`)
  verschwindet stabil** nach den nachfolgenden Inserts und kommt nicht zurück; der neu
  eingefügte Text steht an oberster Zeilenposition (vertikaler Versatz) — **exakt dasselbe
  Muster wie im macOS-Bericht** (dort: „stabil verschwindet nur der VOR der ersten
  Tastatureingabe per insert gesetzte Text … getippter Text steht an oberster
  Zeilenposition"). Ob Modell-Überschreibung oder reiner Render-Verlust bleibt auch hier
  offen (Modell nicht ausgelesen).

## Shim-Mechanismus (Read von `qt-shim/src/shim.cpp`)

Wie auf macOS bereits festgestellt: kein Stub, echte Qt-Objekte, strukturell unauffällig:
- `RacketWindow : public QMainWindow` (Zeile 166) — `shim_window_set_menubar` ruft real
  `QMainWindow::setMenuBar(...)` auf einer echten `QMainWindow`-Subklasse auf (kein
  Typfehler, keine fehlgeschlagene Downcasts).
- `shim_menu_create`/`shim_menubar_add_menu`/`shim_action_create` — echte
  `QMenu`/`QAction`-Objekte, `addMenu`/`addAction` wie erwartet verdrahtet.
- Die FFI-Pfade laufen fehlerfrei (kein Missing-Symbol, `menu-item%`-Objekte werden
  gedruckt) — wie schon auf macOS notiert.

## Schlüssel-Interpretation — für die Fix-Session

- **Wichtigste Korrektur gegenüber der macOS-Hypothese:** Der macOS-Bericht vermutete, der
  Menü-Fix sei „voraussichtlich plattformspezifisch" (native NSMenu-Anbindung). Der
  Linux-Befund spricht dagegen: Hier gibt es **keine** native globale Menüleiste, die
  „nicht angebunden" sein könnte, und trotzdem fehlt die Leiste **genauso vollständig**.
  Zusätzlich macht der negative `QT_QPA_PLATFORMTHEME`-Test einen Linux-spezifischen
  Global-Menu-Redirect als alleinige Ursache unwahrscheinlich. Das spricht für eine
  **gemeinsame, plattformübergreifende Ursache** (z. B. `QMenuBar` bekommt nie eine Höhe
  im `QMainWindow`-Layout zugewiesen, oder `setMenuBar` wird zu einem Zeitpunkt relativ zu
  `show()`/Geometrie-Setzung aufgerufen, an dem Qt sie noch nicht einrechnet) — statt zwei
  getrennter, plattformspezifischer Fixes.
- **Redraw-Befund bestätigt sich cross-Plattform:** Der „VOR-Interaktion-Text verschwindet
  stabil + vertikaler Versatz"-Bug tritt auf macOS UND Linux mit demselben Muster auf →
  eher ein Bug im gemeinsamen `editor-canvas%`/`text%`-Redraw-Pfad (bzw. dessen
  Interaktion mit dem Qt-Shim) als ein Plattform-Sonderfall. Das transiente
  Total-Blank-Symptom aus dem macOS-Bericht wurde hier mangels echter Keystroke-Simulation
  nicht gezielt reproduziert (offene Lücke, s. u.).

## Bekannte Einschränkung dieser Session

- Kein OS-Input-Simulationswerkzeug (`xdotool`/`ydotool`/`wtype`) und kein passwortloses
  `sudo` verfügbar → Punkt 2 (Klick-Test) nicht automatisiert prüfbar; Punkt 4 nur über
  eine programmatische `insert`-Simulation statt echter Tastatur-Events geprüft. Für die
  Fix-Session ggf. `xdotool` nachrüsten (braucht `sudo apt install`, Nutzer-Passwort nötig).

## Screenshots (Session-scratchpad, out-of-band)
- `wide-check.png` — statisch nach Tipp-Simulation: Titelleiste direkt gefolgt vom
  Editor-Inhalt, keine Menüleiste, kein Leerraum
- `wide-noplatformtheme.png` — derselbe Zustand mit `QT_QPA_PLATFORMTHEME=` (Kontrolltest,
  kein Unterschied)

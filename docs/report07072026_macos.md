# Beobachtung — Menüleisten-/Redraw-Diagnose auf macOS (Phase 3, prompt07072026)

**Datum:** 2026-07-07
**Plattform:** macOS 15 (Darwin 25.5.0), arm64 (Apple M1 / T8103)
**Racket:** v9.2 [cs] · **Qt:** 6.11.0 (`~/Qt/6.11.0/macos`)
**Repro:** `examples/menu-frame.rkt` (frame% + menu-bar% + menu% + menu-item% + editor-canvas% + text%)
**Startrezept:** `PLT_QT=1 racket -S third_party/gui/gui-lib -S third_party/draw/draw-lib examples/menu-frame.rkt`

> Reine Diagnose — kein Fix, kein Geometrie-/Rendering-Eingriff. Screenshots liegen im Session-scratchpad
> (out-of-band an den Nutzer, NICHT im Repo — 7,5 MB PNGs bleiben aus der geteilten Historie).

## Re-Sync-Status (Phase 1/2)

- gui-Submodul `qt-backend` per `git pull --ff-only` von `6169a245` (1.78) → `381425d5` (1.80), sauberer Fast-Forward, 51 Commits.
- Umbrella `main` bereits synchron mit origin/main; Zeiger auf `381425d5`; `git submodule update --init` = No-Op.
- `gui-lib/info.rkt` version = **1.80**; Merge-Commit `2d6325d9` vorhanden.
- Konsum-Modell auf dieser Maschine: **`-S`-Source-Override** (gui-lib NICHT verlinkt) → alte `compiled/`-Caches (10 Verzeichnisse in gui+draw) gelöscht, Shim neu gebaut (shim.cpp war neuer als dylib → brachte die menu/dialog/label-Symbole), Fork neu gebaut (`raco make` draw/mred/qt-queue).
- Re-Smoke: **3/3 pass**.
- **Keine neuen Commits durch den Sync** (reiner Pull), wie erwartet.

## Vier Beobachtungspunkte

### 1. Menüleiste sichtbar? Wo?
- **Keine fensterinterne Menüleiste** am oberen Fensterrand — auf macOS erwartet (Qt mappt QMenuBar an den globalen Bildschirmrand).
- In der **globalen macOS-Menüleiste** (Bildschirmrand oben) erscheint **nur `🍎 racket`** — das definierte **`File`-Menü fehlt komplett**. `racket` ist die aktive App, trotzdem kein `File`-Top-Level-Eintrag.

### 2. Öffnet ein Klick einen Top-Level-Titel?
- **Gegenstandslos** — es gibt keinen `File`-Top-Level-Titel in der globalen Leiste. Siehe diskriminierenden Test unten.

### 3. Rendering-Artefakte im oberen Bereich?
- Im statischen Zustand **keine** Überlappung, doppelten Elemente oder weißen Rechtecke. Titelleiste sauber. (Am oberen Rand ohnehin keine Leiste, da global.)

### 4. Zeichnet der zentrale editor-canvas% sauber?
- **Statisch (kein Tippen): JA** — Text sauber und stabil (`menu-frame-macos-1/2.png`, `menu-probe-macos.png`).
- **Interaktiv (Tippen): differenziert** — Persistenz-Test (`redraw-A/B/C.png`):
  - Live-getippter Text rendert **korrekt und stabil**; wächst inkrementell sauber (B: `…KKKK LLLL`, C nach weiterem `x`: `…LLLLx`).
  - Ein Total-Blank (`menu-frame-macos-typed2.png`, erster Lauf) trat **nur transient** mitten im aktiven Tippen auf und **erholt sich nach ~2 s Ruhe vollständig** (B) → kein stabiler Verlust, sondern verpasster Zwischen-Repaint.
  - **Stabil** verschwindet nur der **VOR** der ersten Tastatureingabe per `insert` gesetzte Text (`Hello from Qt + menu!\n`): nach der ersten Interaktion nicht mehr sichtbar, kommt nicht zurück; getippter Text steht an oberster Zeilenposition (vertikaler Versatz). Ob Modell-Überschreibung oder reiner Render-Verlust ist **offen** (Modell nicht ausgelesen) — nicht überinterpretieren.

## Diskriminierender Menü-Test (scratchpad `menu-probe.rkt`)

Um Qt-`QuitRole`-Merging (Item "Quit" → wandert automatisch ins App-Menü, leeres File-Menü wird versteckt) vom „gar nicht angebunden" zu trennen: **File** mit Non-Role-Item `Open Something` **+** `Quit`, dazu zweites Menü **Edit** mit `Copy Thing`.

**Programmatisch via System Events ausgelesen** (robuster als Screenshot):
```
name of menu bar items of menu bar 1  →  {Apple, racket}
```
- Weder `File` noch `Edit` erscheinen — **obwohl beide Non-Role-Items enthalten**, die Qt NICHT mergen würde.
- **→ QuitRole-Merging ist NICHT (allein) die Ursache.** Wäre es das, müssten `File` (wegen "Open Something") und `Edit` in der Leiste bleiben. Tun sie nicht.
- Visuell bestätigt (`menu-probe-macos.png`): globale Leiste = `🍎 racket`, sonst nichts.

## Shim-Mechanismus (Read von `qt-shim/src/shim.cpp`)

Die Menü-FFI ist **kein Stub** — echte Qt-Objekte:
- `shim_menubar_create` → `new QMenuBar(nullptr)`; `shim_window_set_menubar` → `QMainWindow::setMenuBar(...)`.
- `shim_menu_create` → `new QMenu(title)`; `shim_menubar_add_menu` → `QMenuBar::addMenu(...)`.
- `shim_action_create` → `new QAction(label)` + `triggered`-Connect. **Kein `setMenuRole(...)`** irgendwo → Qt-Default `TextHeuristicRole`.

Die FFI-Pfade laufen (menu-frame startet ohne Missing-Symbol-Fehler; `menu-item%`-Objekte werden gedruckt). Der `QMenuBar` wird also real erstellt und via `setMenuBar` an das `QMainWindow` gehängt — **erscheint aber nicht in der nativen macOS-Leiste**.

## Schlüssel-Interpretation (macOS-Sonderfall) — für die Fix-Session

- Das Symptom sieht auf macOS **strukturell anders** aus als auf Windows/Linux: die Leiste ist global und konkurriert **nicht** mit dem editor-canvas% um Fenster-Geometrie. Trotzdem fehlt das Menü komplett.
- Ursache ist **nicht** Geometrie-Konkurrenz und (belegt) **nicht** QuitRole-Merging, sondern: der real erstellte + attached `QMenuBar` wird **nicht in die native macOS-Menüleiste (QMenuBar → QCocoaMenuBar/NSMenu) gemappt**. Kandidaten für die Fix-Session (nicht verifiziert): Timing der Menü-Konstruktion relativ zu Fenster-Show/-Aktivierung; fehlende Aktivierungs-Event-Zustellung über `shim_pump` statt `exec()`; QMenuBar-Ownership/Parent beim `setMenuBar`.
- **→ Der Menü-Fix auf macOS ist voraussichtlich plattformspezifisch** (native NSMenu-Anbindung), nicht identisch zum Windows/Linux-Pfad.
- **Redraw** ist ein **eigenständiges, milderes** Thema: kein „Canvas dauerhaft leer". Zu klären für den Fix: (a) verpasste Zwischen-Repaints während schnellem Tippen (transient), (b) der stabile Verlust des vor-Interaktion-`insert`-Inhalts + vertikaler Versatz.

## Screenshots (Session-scratchpad, out-of-band)
- `menu-frame-macos-1.png`, `-2.png` — statisch, Text sauber, globale Leiste nur `racket`
- `menu-probe-macos.png` — Probe (File+Edit, Non-Role): Leiste weiterhin nur `racket`
- `menu-frame-macos-typed.png`, `-typed2.png` — erster Tipp-Lauf (typed2 = transientes Blank)
- `redraw-A-direkt.png`, `redraw-B-nach2s.png`, `redraw-C-nach-keystroke.png` — Persistenz: Text erholt sich/bleibt stabil

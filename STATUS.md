# STATUS

Kurzer, laufend aktualisierter Stand für alle drei Entwicklungsmaschinen
(Windows / macOS arm64 / Linux x64). Details je Session in `docs/`.

---

## Session 2026-07-07 (3) — Windows Menü/Redraw-Diagnose (kein Re-Sync)

**Kontext:** `docs/prompt07072026.md`, Ergebnis: `docs/report07072026_win.md`.

- **Kein Re-Sync nötig** — der 1.78→1.80-Merge ist auf Windows entstanden und gepusht.
  Umbrella `main` sauber/aktuell, gui-Submodul `qt-backend` @ `381425d5`, `info.rkt` = **1.80**.
  Konsum via **Installation-wide Link** (nicht `-S`-Override wie macOS/Linux). Keine neuen
  Sync-Commits.
- **Menü-Beobachtung:** `menu-frame.rkt` reproduziert den **fehlenden Balken** (Höhe 0) als
  isolierten Minimal-Repro — deckt sich mit Linux. Echtes DrRacket zeigt zusätzlich
  **überlappende Menütitel** (gleiche x-Origin) + weißes Rechteck-Artefakt → zwei Fehlermodi,
  gemeinsame Ursache (Balken-Geometrie/Platzierung) wahrscheinlich, aber offen.
- **Redraw-Beobachtung:** mit **echten Keystrokes** (SendKeys, nur auf Windows möglich)
  reproduziert — nach Tippen mehrerer Zeilen rendert **nur die aktuelle Zeile** (mittig,
  weißes Band nur um sie), frühere Zeilen verschwinden. Verschärft den macOS/Linux-Befund und
  stützt einen Bug im gemeinsamen `editor-canvas%`/`text%`-Redraw-Pfad (fehlender
  Backing-Store-Persist).
- **Damit liegen alle drei Plattform-Beobachtungen vor** — Eingabe für den Rendering-Fix-Prompt.
- **Commit:** nur `docs/report07072026_win.md` + dieser STATUS-Eintrag (Screenshots out-of-band,
  nicht im Repo).

---

## Session 2026-07-07 — macOS auf 1.80 re-synced + Menü/Redraw-Diagnose

**Kontext:** `docs/prompt07072026.md`, Ergebnis: `docs/report07072026_macos.md`.

- **macOS auf 1.80 re-synced, Smoke 3/3.** gui-Submodul FF-Pull 1.78→**1.80**
  (`381425d5`), stale `compiled/`-Caches gelöscht, Shim + Fork (`raco make`) neu
  gebaut. Reiner Pull, keine Sync-Commits. gui-lib wird hier via **`-S`-Source-Override**
  konsumiert (nicht verlinkt) — daher `raco make` statt `raco setup`.
- **Menü-Beobachtung:** globale macOS-Leiste zeigt nur `{Apple, racket}`, kein
  `File`/`Edit`. Diskriminierender Test mit **Non-Role**-Items **widerlegt** Qt-
  QuitRole-Merging als Ursache; Shim erstellt echten `QMenuBar` + `setMenuBar`, aber
  die native **QMenuBar→NSMenu-Anbindung greift nicht** → Fix voraussichtlich
  macOS-spezifisch (nicht Geometrie, nicht QuitRole).
- **Redraw-Beobachtung:** Total-Blank nur **transient** (erholt sich nach Ruhe),
  Live-Tippen rendert stabil; stabil verloren nur der vor-Interaktion per `insert`
  gesetzte Text + vertikaler Versatz → milderes, eigenständiges Thema.
- **Commit:** Umbrella `main` `25a13cb` (nur `docs/report07072026_macos.md`), gepusht.

---

## Session 2026-07-07 (2) — Linux auf 1.80 re-synced + Menü/Redraw-Diagnose

**Kontext:** `docs/prompt07072026.md`, Ergebnis: `docs/report07072026_linux.md`.

- **Linux auf 1.80 re-synced, Smoke 3/3.** gui-Submodul stand detached auf altem
  `6169a245` ohne lokalen `qt-backend`-Branch → `checkout -b qt-backend --track
  origin/qt-backend`, sauberer FF `6169a245`→**1.80** (`381425d5`). 10 stale
  `compiled/`-Caches gelöscht, Shim (stale seit 29.6., Quelle vom 30.6.) neu gebaut,
  Fork (`raco make`) neu gebaut. Reiner Sync, keine neuen Commits. gui-lib auch hier via
  **`-S`-Source-Override** konsumiert.
- **Menü-Beobachtung:** Menüleiste fehlt **komplett** — weder im Fenster noch (anders als
  macOS) irgendwo global, da Plasma/KWin kein globales Menüband hat. `QT_QPA_PLATFORMTHEME=`-
  Kontrolltest macht Global-Menu-Redirect unwahrscheinlich → widerspricht der macOS-These
  „vermutlich plattformspezifisch"; spricht für **eine gemeinsame Ursache** (z. B. QMenuBar
  bekommt nie Höhe im QMainWindow-Layout).
- **Redraw-Beobachtung:** Vor-Interaktion per `insert` gesetzter Text verschwindet stabil +
  vertikaler Versatz — **identisches Muster wie auf macOS** → eher Bug im gemeinsamen
  `editor-canvas%`/`text%`-Pfad statt Plattform-Sonderfall. (Transientes Blank aus dem
  macOS-Bericht mangels Keystroke-Simulationswerkzeug hier nicht gezielt geprüft.)
- **Einschränkung:** kein `xdotool`/`ydotool`/`wtype`, kein passwortloses `sudo` → Klick-Test
  (Punkt 2) nicht automatisierbar, Tipp-Test nur via programmatischer `insert`-Simulation.
- **Damit sind alle drei Maschinen auf gui-lib 1.80 in Parität.**

---

## Session 2026-07-02 — gui-lib-Angleich 1.78→1.80 + echtes DrRacket

**Kontext:** `docs/prompt02072026.md`, Ergebnis: `docs/CHECKPOINT-E0-ledger.md`.

### Was passiert ist

1. Fork (`third_party/gui`, Branch `qt-backend`) war seit dem ursprünglichen Spike auf
   gui-lib **1.78**; das mit Racket 9.2 installierte System-`gui-lib` ist **1.80**. Das
   erzeugte einen Linklet-Mismatch, der DrRacket als Testharness verhinderte (Vorgänger-
   Session griff deshalb auf `examples/widget-probe.rkt` als Ersatz zurück).
2. Fork gemergt auf den exakten Upstream-Commit, aus dem das System-Paket gebaut wurde
   (`3f0037c0`, hash-verifiziert über `package-original-source`). 86 Dateien geändert,
   **0 Konflikte**, kein `wx/qt/**`-File betroffen.
3. `gui-lib` als Installation-scope-Link gesetzt (`raco pkg update --link
   third_party/gui/gui-lib`, braucht Admin-Rechte wegen `C:\Program Files\Racket`).
   **Gate-Test bestanden:** DrRacket startet nativ (ohne `PLT_QT`) ohne Linklet-Mismatch.
4. `PLT_QT=1 drracket` echt gestartet und durch die Crash-Reihe gearbeitet: 9 Crashes +
   2 grundlegende Key-/Focus-Bugs gefunden und gefixt. Ergebnis: Tippen, Enter/Zeilen-
   umbruch und Code-Ausführung funktionieren jetzt in Definitions- **und**
   Interactions-Editor. Details: `docs/CHECKPOINT-E0-ledger.md`.
5. **Offen (Flags für E-1):**
   - Menüleiste visuell nicht sichtbar — Daten/Wiring nachweislich korrekt (165 Menü-
     punkte real gebaut), Ursache ist ein Qt-Layout/Rendering-Problem, kein Racket-Bug.
   - Popup-Positionierung falsch (Kontextmenüs, Dropdowns) — `client-to-screen` ist
     No-op, fehlender Shim für Widget→Bildschirm-Koordinaten (`QWidget::mapToGlobal`).
   - Teilweises Neuzeichnen im Editor-/Interactions-Bereich — noch nicht root-caused.

### Commits

| Repo | Commit | Inhalt |
|---|---|---|
| gui-Submodul (`qt-backend`) | `2d6325d9` | Merge auf Upstream `3f0037c0` (1.78→1.80) |
| gui-Submodul (`qt-backend`) | `381425d5` | 9 Crash-Fixes + Key-Release-Kontrakt + Focus-Tracking + `popup-menu` |
| Umbrella (`main`) | `0b9f287` | Submodul-Zeiger auf `2d6325d9` |
| Umbrella (`main`) | `b902825` | Ledger-Update + Submodul-Zeiger auf `381425d5` |

**Push-Status:** `2d6325d9` / `0b9f287` sind auf `origin` gepusht (Gate-Test war grün).
`381425d5` (die Live-Fixes aus der DrRacket-Discovery) ist **nur lokal committet**,
noch nicht gepusht — offene Entscheidung, siehe Checkpoint-E-0-Bericht der Session.

### ⚠️ Pflicht-Folgeschritt: macOS + Linux

Der Merge in Schritt 2 rückt den **geteilten** `qt-backend`-Branch signifikant vor
(gui-lib-Kernversion geändert, nicht nur additive Dateien). Sobald `381425d5` gepusht
ist, MÜSSEN macOS und Linux (Claude Code läuft dort nicht automatisch mit):

```bash
git -C third_party/gui pull origin qt-backend
git pull origin main   # Umbrella-Zeiger nachziehen
git submodule update --init --recursive
raco setup             # auf BEIDEN Maschinen — gui-lib hat sich strukturell geändert
# dann re-smoken:
PLT_QT=1 QT_PLUGIN_PATH=<...>/plugins \
  racket -S third_party/gui/gui-lib -S third_party/draw/draw-lib -l raco -- test tests/smoke.rkt
```

Ohne `raco setup` auf beiden Maschinen bleiben sie auf altem Bytecode gegen die neue
gui-lib-Quelle stehen — potentiell subtile Inkonsistenzen statt eines klaren Fehlers.

**Status (2026-07-07):** `381425d5` ist auf `origin/qt-backend` gepusht. **macOS ✅ erledigt**
(re-synced auf 1.80, Smoke 3/3 — siehe Session-Eintrag oben; auf macOS läuft der Konsum
über `-S`-Source-Override, daher `raco make` statt `raco setup`). **Linux ✅ erledigt**
(re-synced auf 1.80, Smoke 3/3 — siehe Session-Eintrag oben; ebenfalls `-S`-Source-Override).
**Alle drei Maschinen jetzt in Parität auf gui-lib 1.80.**

---

## Frühere Sessions

Siehe `docs/report*.md` (chronologisch) und die Checkpoint-Tabelle in `CLAUDE.md`.

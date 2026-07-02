# STATUS

Kurzer, laufend aktualisierter Stand für alle drei Entwicklungsmaschinen
(Windows / macOS arm64 / Linux x64). Details je Session in `docs/`.

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

---

## Frühere Sessions

Siehe `docs/report*.md` (chronologisch) und die Checkpoint-Tabelle in `CLAUDE.md`.

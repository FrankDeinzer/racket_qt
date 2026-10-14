# Report — macOS, Pull + Shim-Rebuild + Validierung der Serie §64–§84 — 2026-10-14

**Kontext:** Seit dem letzten macOS-Stand (2026-09-27) sind auf Linux und Windows die Abschnitte
§64–§84 aufgelaufen (Eingabeschicht, Funktions-Sweeps, Audits, `canvas% 'gl`, Abdeckungs-Matrix,
Windows-Fensterposition). Auftrag: Repo-Stand prüfen, pullen, Shim neu bauen, auf macOS validieren,
soweit automatisierbar. Jeder Sync-Schritt wurde vorher mit dem Nutzer abgestimmt (Regel 7).

**Racket:** v9.3 [cs] (Homebrew). **Qt:** 6.11.0 (`~/Qt/6.11.0/macos`). Display 1440×900 (Retina ×2).

## 1. Pull und Shim-Rebuild

- Start: Umbrella `0bea8ae`, **40 Commits hinter** `origin/main`; Submodul `c986ba6a`, **25 Commits
  hinter** `origin/qt-backend`. Beide reine Fast-Forwards.
- Umbrella `git pull --ff-only` → `f535b40`; Submodul → `1efb2c03`. `git submodule update` lässt das
  Submodul im Detached HEAD zurück — danach `git checkout qt-backend && git merge --ff-only
  origin/qt-backend`, damit es wieder auf dem Branch steht.
- `cmake --preset macos-arm64 -S qt-shim` + `cmake --build`: sauber, kein AppleClang-Build-Fix nötig.
  `nm -gU`: 205 `shim_*`-Exporte; stichprobenartig bestätigt `shim_tab_panel_set_options`,
  `shim_button_set_icon`, `shim_label_set_standard_icon`, `shim_screen_available_geometry`.

## 2. Automatisierte Suiten

| Suite | Ergebnis |
|---|---|
| `tests/stub-audit.rkt` | 9/9 |
| `tests/api-audit.rkt` | 4/4 |
| `tests/callback-audit.rkt` | 5/5 |
| `tests/init-audit.rkt` | 3/3 |
| `tests/style-audit.rkt` | 3/3 |
| `tests/key-map.rkt` (`PLT_QT=1`) | 56/56 — alle `derived`-Zeilen auf macOS nachgemessen |
| `tests/smoke.rkt` (`PLT_QT=1`) | 4/4 |

## 3. Probes

Grün: `frame-position-probe` (`ON-MOVE 1 58` beim Start, programmatisches `move 300 200` meldet
`ON-MOVE`/`POS` korrekt), `is-shown-probe`, `message-color-probe`, `bitmap-label-probe` (PASS),
`splash-width-probe` (Dialog 310×324, kein 400-px-Fallback mehr), `set-focus-probe` (0 FAILS),
`display-changed-probe` (`display-size` 1440×900, kein hartcodiertes 1920×1080 mehr).
`tab-close-reorder-probe` ist interaktiv (wartete auf Eingabe, per Timeout beendet) — dessen
Funktion wurde stattdessen in echtem DrRacket geprüft (s. §5).

## 4. Verhaltensmatrix (nativ Cocoa gegen Qt)

`RACKET=$(command -v racket) T=60 tests/sweep/behavior-matrix.sh` — 51 Sektionen, 36 identisch,
15 mit Abweichung, davon 13 reine Fokus-Zähler. Das Skript ist auf Linux kalibriert
(`behavior-matrix-known.txt` ist gtk-Referenz), lief aber unverändert (`gtk`-Modus = nativ).

- **Fokus-Sektionen** (`button`, `canvas`, `check-box`, `choice`, `combo-field`, `editor-canvas`,
  `list-box`, `list-box-columns`, `list-box-multi`, `radio-box`, `slider`, `text-field`,
  `text-field-multi`): z. B. `button`/`check-box` nativ `has-focus #f`, `on-focus-in-count 0`; Qt
  `#t`/`1`. **Einordnung (nicht belegt):** Cocoa-Buttons nehmen ohne „Full Keyboard Access" keinen
  Tastaturfokus an; Qt verhält sich hier wie gtk/win32. Wahrscheinlich Eigenart der nativen Referenz,
  kein Qt-Fehler. Nicht gegen Windows-/Linux-Matrix gegengeprüft.
- **`popup-menu`:** nativ hängt (`SECTION-EXN user break`, rc=124, Timeout), Qt läuft durch
  (`gc-with-popup-open-no-crash => #t`). Qt besser als die Referenz.
- **`tab-order`:** nativ bleibt der Fokus im Probe auf dem Textfeld (`tf tf tf …`), Qt wandert
  korrekt durch alle Widgets (`tf cb ch b2 b1 tf`). Wieder Referenz-Eigenart (Cocoa-Tabbing hängt
  vom Systemschalter ab), nicht Qt.
- Fehlende macOS-Kalibrierung: `behavior-matrix-known.txt` sollte für macOS eine eigene Known-Liste
  bekommen, falls die Matrix hier regelmäßig laufen soll (nicht gemacht).

## 5. Echtes DrRacket unter `PLT_QT=1`

- Start: Fenster mit sichtbarer Titelleiste, Position `77,30`, Größe `1363×815`. Der in §67
  geflaggte Prüfpunkt „Titelleiste des ersten Fensters sichtbar" ist damit **erfüllt**.
- **Fensterposition über Neustart:** Fenster per AppleScript auf `200,120` / `900×600` gesetzt,
  Cmd+Q, Neustart → `200,120 900×600`. **PASS.**
- **Tabs:** Cmd+T öffnet Tab 2, kompakte Tab-Leiste (`setExpanding(false)`), [x] nur am aktiven Tab.
  Tab-Wechsel per Klick funktioniert. [x]-Klick: **AppleScript `click at` schließt den Tab nicht**
  (löst nur AX-Press auf dem Tab-Radiobutton aus) — Automatisierungsartefakt, vgl. §51.2. Mit
  echtem Mausklick (`cliclick c:x,y`) schließt das [x] den Tab, die Tab-Leiste verschwindet bei
  einem Tab. **PASS.**
- **Tab-Taste/Return:** Tippen ging versehentlich in die Interactions-Fläche (Fokus dort). Return
  und Tab verhalten sich dort plausibel (Folgezeile eingerückt, Fokus springt nicht weg). Im
  Definitions-Editor **nicht** getestet.

## 6. Nicht geprüft (offen für macOS)

- Fokus-Reasons: Edit-Menü öffnen, Eintrag wählen / Menü + Escape + Tippen (§64).
- Datei-Drop aufs Fenster (`shim_window_set_drop_cb`), Fenster unter Minimalgröße ziehen
  (`shim_window_set_size_limits`).
- `setAutoDefault` (Return auf fokussiertem Button), Tab im Definitions-Editor reindentet.
- Cmd-Shortcuts als §58.1-Regressionstest, echte Ctrl-Emacs-Belegungen (Ctrl+A/Ctrl+E).
- `message.rkt`/`tab-panel.rkt` `get-top-frame` (beschriftete Controls melden Fokus) — nur indirekt
  über `set-focus-probe` und Fokus-Zähler der Matrix abgedeckt.
- `shim_screen_available_geometry`: auf macOS laut Banner Rückgabe `0` (Stub) — nicht separat
  geprüft; Fenster liegt trotzdem korrekt unterhalb der Menüleiste.
- Die Linux-/X11-Sweeps (`tests/sweep/func-*.sh`, `sweep.sh`, `visual-matrix.sh`, `input-matrix.sh`)
  brauchen `xdotool`/`spectacle` und sind auf macOS nicht lauffähig.

## 7. Methodik-Fehler und Nebenwirkungen

- **Echte Preferences überschrieben.** `PLTADDONDIR` isoliert die Prefs auf macOS **nicht**
  (`find-system-path 'pref-file` → `~/Library/Preferences/org.racket-lang.prefs.rktd`, identisch mit
  und ohne gesetzte Variable). Der Positionstest hat Position/Größe des echten DrRacket-Fensters
  überschrieben. Vor dem Beenden auf `77,30 1363×815` (Wert beim ersten Start) zurückgesetzt; ein
  Backup der Prefs gab es nicht. **Künftig:** für macOS-Prefs-Tests die Datei vorher sichern oder
  `PLTADDONDIR` nicht als Isolation verwenden.
- Ein AppleScript-`click at {590, 0}` mit falscher Koordinate traf die Menüleiste; per Escape
  geschlossen, ohne Folgen.
- `pgrep -x` schlägt in dieser Shell mit „illegal byte sequence" fehl (Locale) — Prozessprüfung
  stattdessen über `ps -axo pid,lstart,command | grep`.

## 8. Befunde

Keine neuen Qt-Defekte. Kein Fix, keine ABI-Änderung in dieser Session; Repo-Änderungen nur Doku.

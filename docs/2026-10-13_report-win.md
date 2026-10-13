# Report — Windows, Pull + Shim-Rebuild + Validierung der Linux-Serie §64–§84 — 2026-10-13

**Kontext:** Auf Linux sind seit dem letzten Windows-Stand (2026-09-28) die Abschnitte §64–§84
aufgelaufen (Eingabeschicht, Funktions-Sweeps, Audits, `canvas% 'gl`, Abdeckungs-Matrix). Auftrag:
lokalen Stand prüfen, Submodul ziehen, Shim neu bauen, auf Windows validieren, soweit automatisierbar.
Ausführung sequentiell über Subagenten (Haiku für rein mechanische Läufe), Auswertung durch die
Hauptsession. Jeder Sync-/Push-Schritt wurde vorher mit dem Nutzer abgestimmt (Regel 7).

**Racket:** v9.3 [cs] (`C:\Program Files\Racket`). **Qt:** 6.11.0 (`C:\Qt\6.11.0\msvc2022_64`).
**Start:** Umbrella `1b5fb0c` = `origin/main` (aktuell). gui-Submodul lokal `c986ba6a`, **22 Commits hinter**
`origin/qt-backend` (`f2104dfa`), reiner Fast-Forward. Shim: Stand 2026-09-28, Rebuild fällig.

---

## 1. Pull und Shim-Rebuild

- `git pull --ff-only origin qt-backend` im Submodul → `f2104dfa`.
- `cmake --preset windows-x64 -S qt-shim`: `racketqtshim: canvas% 'gl support ON (Qt6::OpenGL)` — die neue
  harte Link-Abhängigkeit `Qt6OpenGL` ist vorhanden (Vulkan-Warnung unkritisch).
- **Erster Build scheiterte** mit MSVC C2589 (`min`/`max`-Makro-Kollision aus `<windows.h>`) an
  `shim.cpp:808`, `:1947`, `:1949` (`std::max` ohne Klammern). Fix nach Hauskonvention: `(std::max)(...)`.
  Gleiche Klasse wie der Fix `2e91ee3` (§56). Zweiter Build sauber.
- `dumpbin /exports` (Debug-Format `name = @ILT+…`): 204 `shim_*`-Symbole; alle 27 gezielt geprüften neuen
  Exporte aus §64–§84 vorhanden, dazu 7× `shim_gl_*` + `shim_canvas_gl_create`.

## 2. Statische Audits und Smoke

| Test | Ergebnis |
|---|---|
| `stub-audit` | 9/9 |
| `style-audit` | 3/3 |
| `init-audit` | 3/3 |
| `callback-audit` | 5/5 |
| `api-audit` | **1 Fehlschlag**, dann behoben (4/4), s. u. |
| `smoke` (`PLT_QT=1`) | 4/4 |

**API-Audit unter Windows falsch-positiv.** `tests/api-audit.rkt:151/:167` prüften `wx*.rkt` mit
`#rx"/wx[^/]*[.]rkt$"` gegen `(path->string f)`; unter Windows liefert das `\` → der Glue-Layer wurde nie
erkannt, `get-label`/`set-label` (in `wxlitem.rkt` per `define/public`) galten als „Qt fehlt". Zusätzlich
zählte `inherit` in `shared-callers` unter Windows nicht mit (stille Falsch-Negative möglich). Fix: Muster
`#rx"[/\\\\]wx[^/\\\\]*[.]rkt$"`. Gegenprobe: 11 → 9 Funde (genau die 9 Allowlist-Einträge), 4/4 Tests.
Andere Audits prüfen nur `[.]rkt$` und sind separatorunabhängig. (Commit `82e0748`.)

## 3. Verhaltens-Matrix nativ (win32) gegen Qt

Neu: `tests/sweep/behavior-matrix.ps1` — Windows-Gegenstück zu `behavior-matrix.sh`. Jede Sektion ein eigener
Prozess mit Timeout, nativ und `PLT_QT=1`, Diff der Protokolle (ohne `#px`/`#info` und Known-Liste).
Die Referenz ist hier **win32**, nicht gtk; `behavior-matrix-known.txt` ist gegen gtk triagiert.

**Ergebnis nach den Fixes: 52 von 55 Sektionen identisch.** Verbleibend:

| Sektion | Diff | Einordnung |
|---|---|---|
| `panel`, `vertical-panel`, `horizontal-panel` | `child-hidden` (… 560) Qt gegen (… 547) win32 | Pixelwert (natives Widgetmaß), Schlüssel hat kein `#px`; vermutlich kein Defekt |
| `popup-menu` | win32 läuft in den Timeout, Qt `rc=0` mit `popup-opened-no-crash`/`gc-with-popup-open-no-crash` `#t` | natives Popup blockiert; Qt besser als Referenz |
| `clipboard` | win32: `data-text` als UTF-16-Bytes, Bitmap 14×10; Qt: UTF-8, 7×5 | vermutlich win32-Eigenart (Kodierung/DPI), **nicht verifiziert** |

Ein einmaliger `radio-box`-Diff trat in einem Lauf auf und war in drei Wiederholungen plus Einzelproben nicht
reproduzierbar (Fensteraktivierungs-Race) — als flackernd behandelt, nicht als Befund.

## 4. Befund A — beschriftete Steuerelemente meldeten keinen Fokus (gefixt)

**Symptom:** `choice`, `list-box`(-multi/-columns), `radio-box`, `slider`: nach `(send w focus)` war
`get-focus-window` nicht das Widget, `on-focus` feuerte nie (nativ: 1×/1×).
**Eingrenzung:** Der Fokus wechselte (`pre has-focus` → `#f`), die Meldung fehlte. `'plain`-Slider (ohne
Label-Container) verhielt sich wie nativ → Container-Pfad. Temporäre Diagnose (Shim-`fprintf`, dann
`eprintf` in `window.rkt`, je mit Backup+Hash und Rückbau): `shim_widget_set_focus` landete auf dem
**`QLabel`**; die gemeinsame Schicht sendet `set-focus` bei `wx-label-panel%` an das erste Kind
(`wxpanel.rkt:121`) = das Label `wx-message%`, dessen `proxy` das Steuerelement ist. Unter win32 landet der
native Fokus ebenfalls auf dem Label-Fenster (`PLTSTATIC`), und `get-focus-window` liefert den Proxy.
**Ursache:** `qt/message.rkt` verdrahtete weder Fokus-In/-Out (`qt-forward-nav-keys!`) noch hatte es ein
`get-top-frame` (Basis liefert `this` → `record-focus-window` übersprungen), anders als `button.rkt` & Co.
**Fix:** beides in `message.rkt` ergänzt (14 Zeilen, reiner Racket-Code, kein Rebuild). Submodul `d9e847ea`.
**Verifikation:** Matrix-Sektionen alle OK; Audits 24/24, Smoke 4/4.

**Gleiche Klasse, gefunden über `set-focus-probe`:** `tab-panel.rkt` ohne `get-top-frame` →
`get-focus-window` `#f` bei `has-focus?` `#t`. 8 Zeilen nach `button.rkt`. Submodul `9fd54c40`.

## 5. Befund B — `frame%`-Position und Titelleiste (gefixt, nur Windows)

Der Prüfpunkt aus CLAUDE.md („Titelleiste des ersten DrRacket-Fensters sichtbar bei frischen Preferences")
**schlug fehl.** Gemessen mit `GetWindowRect` auf einem `frame%` 400×300:

| | nativ | Qt vorher | Qt jetzt |
|---|---|---|---|
| ohne x/y | Außenrechteck (1,1) | oberer Rand **−28**, Titelleiste außerhalb des Bildschirms | oberer Rand 1 |
| x=300, y=200 | (300,200) | (294,171) | oberer Rand 200, `get-x`/`get-y` 300/200 |
| `client->screen` bei Standardpos. | (7,30) | (1,1) | (1,30) |

Ursache: Qt-Backend behandelt Position als **Client-Ursprung** (auf Linux bewusst, §67; dort klemmt der WM),
win32 als Außenrahmen. **Fix** (`shim.cpp`, nur `#ifdef Q_OS_WIN`): `moveEvent`, `shim_window_get_pos`,
`shim_widget_set_geometry` (Top-Level `RacketWindow`) nutzen `frameGeometry()`; vor dem Setzen erzwingt
`winId()` die Fenstererzeugung, damit die Rahmenränder bekannt sind (Style-Flags sind zu dem Zeitpunkt
gesetzt). **Rest:** Qt zählt den unsichtbaren 7-px-Rand von Windows 10/11 nicht zum Rahmen, nativ
`GetWindowRect` schon → Qt-Fenster liegt visuell ~7 px weiter links; kosmetisch. **Größe bleibt Client-Maß**
(400×300 → Außenmaß 413×336 statt 400×300), nicht angefasst. Umbrella `b548023`.

## 6. Befund C — `get-display-size` (gefixt, nur Windows)

Nativ 1440×852 (Work-Area, ohne Taskleiste), Qt 1440×900. Neuer, **tolerant gebundener** Export
`shim_screen_available_geometry` (Windows: `availableGeometry`, sonst `0`); `display-size` nutzt ihn bei
`full-screen?` = `#f` für den Hauptmonitor, `display-origin` bei `avoid-bars?` (win32-Muster). Auf
Linux/macOS bleibt das Verhalten unverändert (Export gibt `0`, Racket fällt auf die volle Geometrie zurück).
Verifiziert: `hide-menu-bar-probe` meldet 1440×852 in beiden Backends. Submodul `1efb2c03`.

## 7. Weitere Proben (Gruppe A), nativ gegen Qt

| Probe | Ergebnis |
|---|---|
| `size-callback-probe` | PASS beide (`on-size` für Nicht-Canvas, Kind-Reflow bei `resize`) |
| `frame-position-probe` | identisch (`on-move`, `get-x`/`get-y`, `move`) |
| `tooltip-frame-probe` | PASS beide |
| `splash-width-probe` | Qt 310 breit (keine grauen Balken); Maß-Konvention wie Befund B (Client-Maß) |
| `set-focus-probe` | identisch nach Befund A |
| `frame-float-probe` | Qt vergibt automatisch Anfangsfokus an das Textfeld, nativ liegt er auf dem Frame — win32-Eigenart, kein Defekt |
| GL (`gl-canvas-probe`, `libGL` → `opengl32` in Scratch-Kopie) | **funktioniert unter Qt:** Kontext, `glReadPixels`-Farben identisch zu nativ, Resize, Hide/Show, zweiter Canvas, Display-Liste + Textur überleben. `button-dc-gl-context` ist unter Qt `#f` (laut Probe korrekt), nativ nicht |

Nicht lauffähig unter Windows (brauchen `xdotool`/`xrandr`/X11): `on-activate-probe`, `frame-activate-probe`,
`display-changed`, alle `tests/sweep/*.sh`, `input-matrix`/`visual-matrix`/`dialog-runtime`/`dnd-drop`.

## 8. Commits dieser Session

| Repo | Commit | Inhalt |
|---|---|---|
| Umbrella | `82e0748` | `(std::max)`-Klammern in `shim.cpp`; API-Audit-Separator-Regex |
| gui | `d9e847ea` | `message.rkt`: Fokus-Callback + `get-top-frame` |
| Umbrella | `3c14902` | `behavior-matrix.ps1`; Zeiger `d9e847ea` |
| gui | `9fd54c40` | `tab-panel.rkt`: `get-top-frame` |
| Umbrella | `8013e4f` | Zeiger `9fd54c40` |
| gui | `1efb2c03` | `display-size`/`-origin` Work-Area (`utils.rkt`, `frame.rkt`) |
| Umbrella | `b548023` | Windows-Frameposition + `shim_screen_available_geometry` in `shim.cpp`; Zeiger `1efb2c03` |

Alle Pushes in der Reihenfolge Submodul → Umbrella (Regel 8). Endstand: beide Repos sauber, `main` = `origin/main`,
Zeiger auf `origin/qt-backend`.

## 9. Methodik-Lehren (Windows)

- `powershell -File x.ps1 a b c` bindet bei `param([string[]]$x)` **nur das erste Argument**;
  `[Parameter(ValueFromRemainingArguments)]` nötig (das Matrix-Skript meldete zuerst still nur eine Sektion).
- Aus der Bash-Shell blockiert die Execution Policy `.ps1`-Aufrufe, aus dem PowerShell-Tool nicht.
- `Start-Process -PassThru`: `ExitCode` ist ohne `$null = $p.Handle` leer.
- Ein Probe-Lauf mit offenem Fenster und Ausnahme hängt ewig (Event-Loop läuft weiter) → jeder Lauf mit Timeout.
- Pixel-/Positionsfragen nie aus `get-x`/`client->screen` schließen, sondern mit `GetWindowRect` messen
  (Qt verwendet ein einziges natives Fenster, `GetFocus` ist für Fokusfragen unbrauchbar).
- Diagnose-Instrumentierung (Regel 9): Backup + SHA-256 vorher, Original zurück + Hash-Vergleich nachher,
  jeweils mit ausdrücklicher Freigabe pro Datei. Beide Rückbauten verifiziert (`shim.cpp` = `HEAD`,
  `window.rkt` Hash `cd059571…`).

## 10. Offen

- **Manuell (Gruppe C, nicht automatisierbar):** Find-Leiste „0 Matches", Return in Dialogen, Ctrl+D in
  „Choose Language", Fenster-Icons, Optik. Synthetische `Ctrl+<Taste>` und Koordinaten-Klicks erreichen das
  echte Qt-Fenster auf diesem Rechner unzuverlässig.
- Fensterposition: Neustart-Test mit gespeicherten DrRacket-Preferences (Position/Größe kommen am selben
  Ort zurück) nicht gelaufen; nur die Mechanik (`get-x`/`move`-Rundlauf) ist belegt.
- `clipboard`-Diff (UTF-16/Bitmapgröße) und `panel`-Pixeldiff: Ursache nur vermutet.
- Größen-Konvention `frame%` (Client- statt Außenmaß) bewusst unverändert.
- Linux/macOS: Pull; Shim-Rebuild für `shim_screen_available_geometry` (kein Startfehler ohne); Audits +
  Smoke; die Fokus-Änderungen an `message.rkt`/`tab-panel.rkt` gegen die dortige Referenz prüfen
  (`set-focus-probe`, `behavior-matrix`). macOS-Work-Area (Dock/Menüleiste) wurde nicht betrachtet.

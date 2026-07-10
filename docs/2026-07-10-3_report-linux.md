# Report: 2026-07-10-3_prompt (Linux, Phase 3 — Cross-Platform-Validierung)

**Racket-Version (gemessen):** Welcome to Racket v9.2 [cs].

## 1. Zusammenfassung

Reine Validierungssession (kein Fix-Code) für die beiden auf Windows gefixten
Fundament-Befunde `docs/HACKING.md` §18.2 (Panel-Sizing) und §18.3 (Modalität), plus
Erst-Sicht auf die schon gemergten `list-box%`/`check-box%`-Widgets, die diese Maschine
noch nie gebaut hatte. Beide Fixe sind auf Linux grün. Keine Fix-Commits in `wx/qt/`.

## 2. Phase 3 — Sync + Rebuild

- **Vor dem Pull geprüft** (CLAUDE.md Regel 7): Nutzer per `AskUserQuestion` gefragt, ob
  jetzt gepullt werden soll — bestätigt.
- gui-Submodul (`qt-backend`) lag 3 Commits hinter `origin/qt-backend`:
  `04935cb6` → `f92352e0` via `git pull --ff-only` (Fast-Forward, keine lokalen
  Extra-Commits). Enthaltene Commits: `08bf0af6` (list-box%/check-box% real),
  `8904b264` (Fix A — Panel-Sizing), `f92352e0` (Fix B — Modalität).
- Umbrella `main` war bereits mit `origin/main` deckungsgleich (`f86bb09`), Zeiger auf
  `third_party/gui` bereits `f92352e0` — kein Pull nötig, keine Diskrepanz.
- **Shim neu gebaut** (`cmake --preset linux-x64 -S qt-shim && cmake --build
  qt-shim/build/linux-x64`): sauberer Build, `shim.cpp` neu kompiliert (enthält jetzt
  `shim_widget_get_size_hint` und `shim_widget_set_enabled`), Link ohne Fehler/Warnings.
- **Bytecode neu:** `racket -S third_party/gui/gui-lib -S third_party/draw/draw-lib
  -l raco -- make -l mred` — durchgelaufen ohne Fehler/Warnungen.
- **Re-Smoke:** `PLT_QT=1 QT_PLUGIN_PATH=~/Qt/6.11.1/gcc_64/plugins racket -S ... -l raco
  -- test tests/smoke.rkt` → **3/3 grün**.
- **Light Mode bestätigt:** `~/.config/racket/racket-prefs.rktd` zeigt
  `plt:framework-pref:framework:white-on-black?` = `#f`.

## 3. Werkzeuge dieser Session

Keine grafische Automatisierung (`xdotool`/`wmctrl`/`scrot`/`imagemagick`) auf dieser
Maschine installiert — wie in den Vorsessions ein kleiner Scratch-Helfer gebaut
(`synth.c`, gegen `libX11`/`libXtst.so.6` gelinkt, `libxtst-dev` fehlt daher
Hand-Deklaration der drei `XTestFake*`-Funktionen):
- `move X Y` / `click BTN [X Y]` — `XTestFakeMotionEvent`/`XTestFakeButtonEvent`.
- `raise WINID` — `XRaiseWindow`+`XSetInputFocus` (WM gab neu gestarteten Fenstern nicht
  immer Fokus).
- `movewin WINID X Y` — `XMoveWindow`, um überlappende Fenster für einen sauberen
  Modalitäts-Test auseinanderzuziehen (siehe §5).

Screenshots: `xwd -id <winid>` + ein ca. 30-zeiliger selbstgeschriebener XWD→PNG-Parser
(Python, `X11/XWDFile.h`-Header als Referenz für das Binärformat) — auf dieser Maschine
weder `pnmtopng`/`xwdtopnm` (netpbm) noch `convert` (ImageMagick) installiert; `PIL` kann
`.xwd` nicht direkt öffnen.

Fensterkoordinaten wurden nicht geschätzt, sondern per Pixel-Scan (Hintergrundfarbe vs.
Widget-Rand) aus einem ersten Screenshot ermittelt, bevor geklickt wurde — ein erster
Blindversuch mit geschätzten Koordinaten traf keinen Button (kein Effekt, kein Log-Eintrag).

## 4. Fix A — Panel-Sizing (§18.2): validiert, grün

`examples/panel-sizing-probe.rkt` unverändert (keine `[min-width]`/`[min-height]`-
Workarounds im Skript). Screenshot nach Start: alle drei `button%` ("Button ONE"/"TWO"/
"THREE") stehen sauber vertikal untereinander, keine Überdeckung — identisch zum
Windows-Nachher-Ergebnis (`docs/2026-07-10-3_report-win.md` §3.3).

`examples/dialog-widgets-probe.rkt` (ebenfalls ohne Workaround, wie von Windows-Session
committet): Parent-Frame (Message-Text + 2 Buttons) UND der später geöffnete Dialog
(`list-box%` mit 4 Einträgen "Alpha"/"Beta"/"Gamma"/"Delta" + `check-box%` "Enable
feature X" + OK/Cancel) layouten korrekt ohne jede explizite Mindestgröße.

Smoke 3/3 weiterhin grün nach beiden Läufen.

## 5. Fix B — Modalität (§18.3): validiert, grün

**Ablauf:**
1. `dialog-widgets-probe.rkt` gestartet, Parent-Fenster-Geometrie per `xwininfo`
   ermittelt, "Open dialog"-Button-Position per Pixel-Scan lokalisiert (nicht geschätzt),
   per synthetischem `libXtst`-Klick geöffnet. Dialog erscheint, `list-box%`/
   `check-box%` sichtbar + funktional (Screenshot).
2. **Überlappungs-Komplikation:** Dialog- und Parent-Fenster überlappten sich
   vollständig im Bereich des Parent-Buttons (KWin platziert neue Top-Levels
   überlappend) — ein Klick "auf den Parent-Button" hätte in diesem Zustand
   den Dialog getroffen (X11-Pointer-Routing an das oberste Fenster an dieser
   Position), unabhängig davon, ob Modalität greift oder nicht. Das hätte einen
   falsch-positiven "Blockade bestätigt"-Befund erzeugt. Fix: Dialog-Fenster per
   `XMoveWindow` (`synth movewin`) an eine nicht überlappende Bildschirmposition
   verschoben — der Dialog bleibt dabei logisch offen (Qt-Fenstermodalität hängt
   nicht an der Bildschirm-Überlappung, sondern am toolkit-seitigen
   `setEnabled(false)` aus Fix A(a)), nur die Fensterposition ändert sich.
3. Mit freigelegtem Parent-Button: Klick auf den Parent-Button bei weiterhin offenem
   Modal → **kein** `"PARENT BUTTON CLICKED"`-Print im Log.
4. Dialog per Klick auf OK geschlossen (Button-Position ebenfalls per Pixel-Scan
   verifiziert, nicht geschätzt — ein erster Klick zwischen OK und Cancel traf
   keinen der beiden Buttons).
5. **Methodik-Gegenprobe:** derselbe Klick auf denselben Parent-Button, jetzt bei
   **geschlossenem** Dialog → Print feuert. Das bestätigt zweierlei gleichzeitig: die
   Klick-Mechanik (Koordinaten, `XTestFakeButtonEvent`) funktioniert einwandfrei, UND
   das Ausbleiben des Prints in Schritt 3 lag ursächlich an der aktiven Modalität, nicht
   an einem fehlerhaften Testaufbau.

**stdout-Pufferung als Stolperstein:** `racket`s `current-output-port` ist beim
Redirect in eine Datei (`> log 2>&1`) blockgepuffert, nicht zeilengepuffert — die
Printf-Ausgaben ("dialog closed …", "PARENT BUTTON CLICKED …") erschienen im Log-File
nicht sofort, sondern erst nach Prozessende (`SIGTERM`/`user break` flusht offenbar
beim Exit-Handler). Für künftige Sessions: nach jedem Klick-Schritt nicht auf sofortige
Log-Ausgabe verlassen, sondern entweder den Prozess am Ende sauber terminieren und dann
das Gesamtlog lesen, oder `(flush-output)` in den Test-Callback einbauen.

**Visueller Grau-Kontrast:** Pixel-Sampling der dunkelsten Text-Pixel im Parent-Button
(disabled) vs. im "Open dialog"-Button (enabled, während Parent disabled war) ergab
ähnliche Werte (RGB-Summe ~379 vs. ~387 auf einer 0–765-Skala) — in diesem
Qt-Stil/dieser Auflösung ist der Enabled/Disabled-Unterschied auf Screenshot-Ebene nicht
eindeutig zu erkennen. Das ist kein Widerspruch zum funktionalen Befund: `setEnabled`
liefert nachweislich keine Klick-Events mehr aus, unabhängig davon, wie stark sich das
optisch niederschlägt. Windows hatte hier einen deutlicheren visuellen Kontrast
beobachtet (`docs/2026-07-10-3_report-win.md` §4.4) — plausibel eine
Theme-/Style-Differenz zwischen den Plattformen, nicht Teil des Scopes dieser Session.

Smoke 3/3 grün nach dem gesamten Ablauf.

## 6. Guardrails eingehalten

- Kein `exec()`/`QEventLoop`, keine geschachtelte Schleife (Test lief vollständig über
  externe X11-Events + normale Racket-Eventspace-Pump).
- cocoa/gtk/win32 nicht angefasst.
- Nur Fast-Forward-Pull, vorher per `AskUserQuestion` bestätigt.
- Gated Diagnose bleibt gated (`PLT_QT_DEBUG` nicht verändert).
- Reine Validierung — keine Fix-Commits in `wx/qt/`.
- Report-Header nutzt gemessene `racket --version`.

## 7. Commits & Stand

- gui-Submodul (`qt-backend`): ff-Pull `04935cb6` → `f92352e0`, keine neuen Commits.
- Umbrella (`main`): `docs/HACKING.md` §18.2/§18.3 (Linux-Validierungsabsätze),
  `STATUS.md`-Eintrag, dieser Bericht.

## 8. Nächste Schritte

- **macOS** (Phase 4, `docs/2026-07-10-3_prompt.md`): gleiche zwei Validierungen
  (3-`button%`-Stapelung, Parent-Klickbarkeit bei offenem Modal) nach Sync + Shim-Rebuild.
- Nach grüner macOS-Validierung: Checkpoint E fortsetzen (choice%/radio-box%/slider%/
  tab-panel%), danach file-selector, danach Preferences.

# Report 2026-10-18 — Linux: Sync, Shim-Rebuild, Validierung der Windows-/macOS-/WASM-Commits

## 1. Sync

- Umbrella `main` == `origin/main` (`b29e255`), sauber.
- gui-Submodul `qt-backend`: Fast-Forward `f2104dfa` -> `64a1e7ef` (7 Commits: Fokus für beschriftete Controls,
  `tab-panel` get-top-frame, Windows-Arbeitsbereich, macOS-Cmd+Q, WASM-`ffi-lib #f`, `shim_canvas_blit_native`,
  `shim_window_set_owner`).
- `third_party/racket-wasm-backend` auf ausdrückliche Freigabe (Ausnahme von Regel 9, eigener Fork) per
  `git submodule update --init` initialisiert: `3e9cd142`, `qt-wasm`.

## 2. Rebuild und Audits

- Shim neu gebaut (Ninja, GCC), kein Fehler. `nm -D`: `shim_window_set_owner`, `shim_canvas_blit_native`,
  `shim_app_set_quit_cb`, `shim_screen_available_geometry` vorhanden. Alle vier tolerant gebunden; Linux-Wirkung nur
  beim Blit, die übrigen sind No-ops.
- Audits stub 9 / style 3 / api 4 / init 3 / callback 5 grün. `tests/smoke.rkt` 4/4 mit und ohne `PLT_QT`.

## 3. Behavior-Matrix (51 Sektionen, nativ gtk gegen Qt)

Sitzung ist **Wayland** (`XDG_SESSION_TYPE=wayland`); die Skripte sind für X11 gebaut. Erster Lauf: 41/51 identisch.

- Erneut mit `GDK_BACKEND=x11 QT_QPA_PLATFORM=xcb` (Xwayland): `check-box`, `clipboard`, `cursor`, `popup-menu`
  identisch -> reine Wayland-Artefakte (Popup-Grab-Warnung, `""` gegen `#f` in der Clipboard-Sektion, Gdk-Meldung).
- **Verbleibend, reproduzierbar (zweimal): `choice`, `slider`, `radio-box`, `list-box`, `list-box-columns`,
  `list-box-multi`.** Zeilen `focus:frame-focus-window-eq`, `focus:on-focus-in-count`, `focus:on-focus-out-count`:
  gtk meldet `#f`/0/0, Qt `#t`/1/1.
- **A/B-Test:** mit Submodul-Stand `f2104dfa` (vor den 7 Commits) sind `choice`, `slider`, `radio-box` identisch.
  Ursache ist daher **`d9e847ea`** (`message.rkt`: Fokus-Callback + `get-top-frame`), gefunden über den Windows-Vergleich
  gegen win32. Qt verhält sich jetzt wie win32; gtk meldet für beschriftete Controls in dieser Probe keinen Fokus.
  Das ist eine Divergenz der Referenz-Backends, kein Qt-Defekt nach bisherigem Stand. Ob gtk hier durch
  fehlende Fensteraktivierung unter Xwayland abweicht, ist nicht geklärt.
- `check-box` zeigte im ersten Lauf (Wayland) ebenfalls einen Fokus-Diff, unter X11 nicht (Flackern der
  Fensteraktivierung).

## 4. Echtes X11 (Xvfb + openbox) und Ergebnis

Nach Installation von `xvfb`/`openbox` (Nutzer): Xvfb `:99` 1600x1000 + openbox, `GDK_BACKEND=x11 QT_QPA_PLATFORM=xcb`.

- Dieselben sechs Sektionen weichen auch hier ab (`check-box` ist sauber): die Fokus-Diffs sind **keine** Wayland-/Xwayland-Artefakte.
- Ursache belegt: `gtk/message.rkt:119` `gets-focus? #f` — das gemeinsame `set-focus` der beschrifteten Controls geht an das
  Label und läuft unter gtk ins Leere (Zähler 0). Qt entspricht seit `d9e847ea` win32 und meldet den Fokus. Begründete
  Abweichung, kein Qt-Defekt.
- 18 Zeilen in `tests/sweep/behavior-matrix-known.txt` (3 Schlüssel x 6 Sektionen).
- **Danach `behavior-matrix.sh` unter Xvfb: 51/51 identisch** (Exit 0).

## 5. Offen

- Auf Linux ungeprüft: `shim_canvas_blit_native` im echten DrRacket (Tippen, Redraw), Wayland-Eingabe.
- Nichts committet. Submodul-Stand `64a1e7ef` (`qt-backend`).

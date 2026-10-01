# Report 2026-10-01 (Linux), Teil 3: Funktions-Sweeps, Restpunkte

Details: `docs/HACKING.md` §67. Skripte: `tests/sweep/func-{replaceall,saveas,autosave,winpos,stepper}.sh`, `func-run.sh` (OCR).

| Szene | Ergebnis |
|---|---|
| Replace All | identisch (6× foo → qux, Undo = ein Schritt); einmaliges fehlendes Rosa im Qt-Suchfeld nicht reproduziert (n=1/3) |
| Save As | identisch (Dialog-Theme verschieden, Überschreiben-Rückfrage in beiden) |
| Autosave-Recovery | identisch (SIGKILL, Recover Files, Recover, Done) |
| Fensterposition | **Qt-Bug gefixt**: kein `on-move`, `get-x`/`get-y` gecacht, Konstruktor platzierte nie, `display-size` hartcodiert 1920×1080. Qt restauriert jetzt exakt; gtk driftet +28 px (WM-Gravity, kein Qt-Befund) |
| Macro-Stepper-Schritte | identisch (visuell, 8 Schritte) |
| REPL per OCR | identisch |

Weitere Fixes: `message%` `set-color`/`get-color` real. Neue tolerante Shim-Exporte: `shim_label_set_color`, `shim_window_set_move_cb`, `shim_window_get_pos`, `shim_screen_count`, `shim_screen_geometry` (Banner in CLAUDE.md). Methodenvorfall: Escape ging einmal ins Konsole-Fenster (zu breiter `findwin`-Regex) — behoben (Konsole-Filter, Terminal-Verweigerung in `key`/`typ`/`click`).

Tests: stub-/style-/api-audit 16 grün; `PLT_QT=1 smoke.rkt` 4 grün. Sync (Regel 7/8): nicht ausgeführt (kein push/pull per Vorgabe). Offen: Windows/macOS Rebuild + Validierung; `center` No-op; `on-activate` ohne fokussierbares Kind.

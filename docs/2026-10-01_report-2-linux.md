# Report 2026-10-01 (Linux), Teil 2: Funktions-Sweeps

Aufgabe: typische DrRacket-Abläufe verhaltensmäßig nativ (gtk) gegen `PLT_QT=1` vergleichen. Details: `docs/HACKING.md` §66.

## Szenen und Ergebnis

Run+REPL, Datei bearbeiten/speichern/öffnen, Find/Replace, Kontextmenüs, Check Syntax + Tooltips, big-bang, Debug/Macro Stepper, Schließen mit Rückfrage (Skripte `tests/sweep/func-*.sh`, Helfer `func-lib.sh`). Identisch: REPL-Ausgabe/Eingabe, Speichern/Öffnen, Suchen/Ersetzen, Kontextmenü-Einträge, Check-Syntax-Pfeile, big-bang-Events, Debug-Leiste. Abweichungen (alle gefixt): Save-Knopf immer sichtbar, Titel ohne `*`, `on-activate` nie gefeuert (keine Tooltips), `frame%` `move` No-op (Tooltip-Position), Bitmap-Label-Knöpfe „Button" (Macro Stepper), Warn-Icon fehlte.

## Methodenfund

Preferences liegen unter `$XDG_CONFIG_HOME/racket`, nicht unter `PLTADDONDIR`; gtk-Läufe beeinflussten Qt-Läufe (Replace-Leiste). `start_dr`/`dr-dialogs.sh` setzen jetzt frisches `XDG_CONFIG_HOME`. Hinweis: frühere Sweeps haben `~/.config/racket` des Nutzers mitbeschrieben.

## Tests (Linux)

`raco test tests/stub-audit.rkt tests/style-audit.rkt tests/api-audit.rkt`: 16 grün; `PLT_QT=1 raco test tests/smoke.rkt`: 4 grün. Neue Proben: `examples/show-hide-probe.rkt`, `tooltip-frame-probe.rkt`, `frame-activate-probe.rkt`, `bitmap-label-probe.rkt`.

## Offen

- Windows/macOS: Pull, Shim-Rebuild (drei neue tolerant gebundene Exporte: `shim_button_set_icon`, `shim_label_set_standard_icon`, `shim_label_set_pixmap`), Validierung der Sweeps. Nichts gepusht.
- `on-activate` ohne fokussierbares Kind weiter nicht (bräuchte Shim-Ereignis); `message%` `set-color`; Frame-`get-x`/`get-y`.

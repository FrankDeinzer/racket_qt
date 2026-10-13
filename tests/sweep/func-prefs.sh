#!/usr/bin/env bash
# Funktions-Sweep 9: Preferences-Browser-Tab.  Browser-Tab -> "Firefox" waehlen, "Use proxy" + Host/Port tippen,
# OK; Wirkung: (1) Preferences-Datei unter $XDG_CONFIG_HOME/racket (Browser-/Proxy-Schluessel), (2) Dialog erneut
# oeffnen -> Werte noch gesetzt (Aufnahme), (3) Undo-Pfad: Aenderung + "Undo Changes and Close" -> Datei unveraendert.
# Koordinaten (relativ zum Dialog-Client) pro Toolkit aus den Aufnahmen dlg-prefs-6 abgelesen.
# Aufruf: tests/sweep/func-prefs.sh [gtk|qt|both]
SCENE=func-prefs; source "$(dirname "$0")/func-lib.sh"
prefs_dump() { # alle prefs-relevanten Zeilen (Browser/Proxy), normalisiert
  local f; for f in $(find "$XDG_CONFIG_HOME" "$PLTADDONDIR" -name 'racket-prefs.rktd' 2>/dev/null); do
    tr ' ' '\n' < "$f" | tr -d '()' | grep -iE 'browser|proxy|http|firefox|^8080|proxy\.invalid' | tr '\n' ' '; done; echo
}
open_prefs() { key $main ctrl+semicolon; dlg=$(findwin '^Preferences$' 10) || return 1; sleep 3; activate $dlg
  eval "$(xdotool getwindowgeometry --shell $dlg)"; DX=$X; DY=$Y; DW=$WIDTH; DH=$HEIGHT; }
for mode in $MODES; do
  echo "== $mode =="
  if [ $mode = qt ]; then TX=433 TY=37; FX=16 FY=261; PX=16 PY=447; HX=158 HY=476; RX=330 RY=476; OKX=677 OKY=620; UNX=500
  else TX=362 TY=44; FX=17 FY=270; PX=17 PY=436; HX=170 HY=464; RX=358 RY=464; OKX=666 OKY=628; UNX=497; fi
  start_dr $mode -l drracket "$HERE/files/a.rkt" || exit 1
  main=$(findwin '\.rkt.*DrRacket$' 90) || { echo "kein Fenster"; stop_dr; continue; }
  sleep 10
  open_prefs || { echo "  Preferences fehlt"; stop_dr; continue; }
  echo "  Dialog ${DW}x${DH}"
  click $dlg $((DX+TX)) $((DY+TY)); sleep 1.5; shot $dlg browser-0 $mode
  click $dlg $((DX+FX)) $((DY+FY)); sleep 0.5
  click $dlg $((DX+PX)) $((DY+PY)); sleep 0.5
  click $dlg $((DX+HX)) $((DY+HY)); sleep 0.3; typ $dlg "proxy.invalid"
  click $dlg $((DX+RX)) $((DY+RY)); sleep 0.3; typ $dlg "8080"; sleep 0.5
  shot $dlg browser-1 $mode
  # Undo-Pfad zuerst NICHT; OK
  click $dlg $((DX+OKX)) $((DY+OKY)); sleep 3
  echo "  Dialog nach OK: $(findwin '^Preferences$' 2 >/dev/null && echo offen || echo geschlossen)"
  echo "  Prefs nach OK: $(prefs_dump)"
  # erneut oeffnen: Werte persistent?
  open_prefs && { click $dlg $((DX+TX)) $((DY+TY)); sleep 1.5; shot $dlg browser-2 $mode
    tesseract "$OUT/$SCENE-browser-2-$mode.png" - 2>/dev/null | grep -E 'proxy|8080' | tr '\n' ' ' | sed 's/^/  OCR reopen: /'; echo
    # Undo-Pfad: Port aendern, Undo
    click $dlg $((DX+RX)) $((DY+RY)); sleep 0.3; key $dlg ctrl+a; typ $dlg "9999"; sleep 0.5; shot $dlg browser-3 $mode
    eval "$(xdotool getwindowgeometry --shell $dlg)"
    click $dlg $((DX+UNX)) $((DY+OKY)); sleep 3
    echo "  Dialog nach Undo: $(findwin '^Preferences$' 2 >/dev/null && echo offen || echo geschlossen)"
    echo "  Prefs nach Undo: $(prefs_dump)"; }
  stop_dr
  echo "  Prefs nach Beenden: $(prefs_dump)"
done
sidebyside browser-0 browser-1 browser-2 browser-3

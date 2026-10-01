#!/usr/bin/env bash
# Funktions-Sweep 8: Debug und Macro Stepper.  Debug-Knopf -> Debug-Leiste (Go/Step/...),
# Step-Klick; Macro-Stepper-Knopf -> eigenes Fenster (Aufnahme + Titel).  Koordinaten der Knoepfe
# gelten fuer das 600x650-Fenster (Klick y=38 trifft beide Toolkits).
SCENE=func-dbg; source "$(dirname "$0")/func-lib.sh"
for mode in $MODES; do
  echo "== $mode =="
  D=$FUNC_TMP/$mode; mkdir -p $D; cp "$HERE/files/run.rkt" $D/run.rkt
  start_dr $mode -l drracket $D/run.rkt || exit 1
  main=$(findwin 'run\.rkt.*DrRacket$' 90) || { echo "kein Fenster"; stop_dr; continue; }
  sleep 10; eval "$(xdotool getwindowgeometry --shell $main)"
  # Debug zuerst (der Stepper ueberdeckt sonst das Hauptfenster)
  click $main $((X+325)) $((Y+38)); sleep 8
  shot $main debug "$mode"
  echo "  Titel nach Debug: '$(title $main)'"
  activate $main; click $main $((X+458)) $((Y+38)); sleep 8
  ms=$(findwin 'Macro Stepper' 15) && { echo "  Macro-Stepper-Fenster: '$(title $ms)' $(xdotool getwindowgeometry $ms | tail -1)"; sleep 2; shot $ms macro "$mode"
     eval "$(xdotool getwindowgeometry --shell $ms)"; MSX=$X; MSY=$Y; MSH=$HEIGHT; } || echo "  KEIN Macro-Stepper-Fenster"
  shot $main after-macro "$mode"
  [ -n "${ms:-}" ] && { key $ms Next 2>/dev/null; sleep 1; shot $ms macro-next "$mode"; }
  stop_dr
done
sidebyside macro after-macro macro-next debug

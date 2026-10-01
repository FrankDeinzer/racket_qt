#!/usr/bin/env bash
# Funktions-Sweep 1: Run + REPL.  F5 auf run.rkt; Marker-Datei (Programm lief),
# Titel, Screenshot (REPL-Ausgabe), dann Eingabe im REPL ("(f 3)" -> 9), Screenshot.
# Aufruf: tests/sweep/func-run.sh [gtk|qt|both]
SCENE=func-run; source "$(dirname "$0")/func-lib.sh"
for mode in $MODES; do
  echo "== $mode =="
  MARK=$FUNC_TMP/mark-$mode; rm -f "$MARK"; export SWEEP_MARK=$MARK
  start_dr $mode -l drracket "$HERE/files/run.rkt" || exit 1
  main=$(findwin '\.rkt.*DrRacket$' 90) || { echo "kein Fenster"; stop_dr; continue; }
  sleep 10; echo "  Titel vor Run: $(title $main)"
  key $main F5; sleep 6
  [ -f "$MARK" ] && echo "  Marker: $(cat $MARK)" || echo "  Marker: FEHLT"
  shot $main run "$mode"
  eval "$(xdotool getwindowgeometry --shell $main)"
  click $main $((X+WIDTH/2)) $((Y+HEIGHT-60))
  typ $main "(f 3)"; key $main Return; sleep 2
  typ $main "(string-append \"a\" \"b\")"; key $main Return; sleep 2
  shot $main repl-input "$mode"
  # Stop-Taste im laufenden Programm: Endlosschleife per REPL, Ctrl+K? (Break = Ctrl+Break); hier nur Titel
  echo "  Titel nach Eingabe: $(title $main)"
  stop_dr
done
sidebyside run repl-input

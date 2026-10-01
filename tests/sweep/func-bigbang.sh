#!/usr/bin/env bash
# Funktions-Sweep 7: 2htdp/image + big-bang.  F5 -> World-Fenster; zwei Aufnahmen im Abstand
# (Tick-Animation), Tastendruck "a" und Mausklick (Marker-Datei: kommen die Events an?),
# "q" beendet die Welt; danach Run-Zustand des Hauptfensters (REPL-Prompt) per Aufnahme.
SCENE=func-bb; source "$(dirname "$0")/func-lib.sh"
for mode in $MODES; do
  echo "== $mode =="
  D=$FUNC_TMP/$mode; mkdir -p $D; cp "$HERE/files/bigbang.rkt" $D/bigbang.rkt
  MARK=$D/mark; rm -f $MARK; export SWEEP_MARK=$MARK
  start_dr $mode -l drracket $D/bigbang.rkt || exit 1
  main=$(findwin 'bigbang\.rkt.*DrRacket$' 90) || { echo "kein Fenster"; stop_dr; continue; }
  sleep 10; key $main F5
  w=$(findwin '^[0-9]+$|world|2htdp|big-bang' 40) || { echo "  World-Fenster nicht gefunden"; w=""; }
  if [ -n "$w" ]; then
    echo "  World-Fenster: '$(title $w)' $(xdotool getwindowgeometry $w | tail -1)"
    sleep 2; shot $w world1 "$mode"; sleep 2; shot $w world2 "$mode"
    key $w a; sleep 1
    eval "$(xdotool getwindowgeometry --shell $w)"; click $w $((X+30)) $((Y+20)); sleep 1
    echo "  Marker bisher: $(tr '\n' ' ' < $MARK 2>/dev/null)"
    key $w q; sleep 3
    echo "  Marker final: $(tr '\n' ' ' < $MARK 2>/dev/null)"
    echo "  World-Fenster nach q noch da: $(xdotool search --name "^$(title $w)\$" 2>/dev/null | wc -l)"
  fi
  shot $main after-q "$mode"
  stop_dr
done
sidebyside world1 world2 after-q

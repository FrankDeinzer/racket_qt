#!/usr/bin/env bash
# Funktions-Sweep 11: Debugger mit Breakpoint.  Debug-Knopf -> Debug-Leiste; Step-Klicks (Marker-Dateifortschritt
# je Schritt), Breakpoint per Rechtsklick auf einen Ausdruck ("Pause at this point"), Go -> Halt am
# Breakpoint (Marker + Stack/Variables-Aufnahme), Go bis Ende.  Vergleich gtk == Qt ueber Marker und Aufnahmen.
# Koordinaten relativ zum 600x650-Fenster (Client), pro Toolkit aus func-dbg-debug-side.png abgelesen.
# Aufruf: tests/sweep/func-debugger.sh [gtk|qt|both]
SCENE=func-dbgr; source "$(dirname "$0")/func-lib.sh"
mcount() { [ -f "$MARK" ] && wc -l < "$MARK" || echo 0; }
mlast() { [ -f "$MARK" ] && tail -1 "$MARK" || echo -; }
for mode in $MODES; do
  echo "== $mode =="
  if [ $mode = qt ]; then GOX=152 STX=208 BY=66 LY=268 MDY=13; else GOX=148 STX=205 BY=73 LY=277 MDY=18; fi
  MARK=$FUNC_TMP/mark-$mode; rm -f $MARK; export SWEEP_MARK=$MARK
  start_dr $mode -l drracket "$HERE/files/dbg.rkt" || exit 1
  main=$(findwin 'dbg\.rkt.*DrRacket$' 90) || { echo "kein Fenster"; stop_dr; continue; }
  sleep 10; eval "$(xdotool getwindowgeometry --shell $main)"
  click $main $((X+325)) $((Y+38)); sleep 8
  echo "  nach Debug: marker=$(mcount) last=$(mlast)"; shot $main d0 $mode
  for i in 1 2 3; do
    click $main $((X+STX)) $((Y+BY)); sleep 2.5
    echo "  Step $i: marker=$(mcount) last=$(mlast)"
  done
  shot $main d-step3 $mode
  # Breakpoint auf "(f 2)" (Zeile 8, x=144 trifft die oeffnende Klammer in beiden Toolkits; Menue-Eintrag
  # "Pause at this point" liegt gtk +18 px, Qt +13 px unter dem Klickpunkt)
  # Aufwaermen: erster Rechtsklick (x=140, Boundary davor) zeigt in beiden Toolkits nur das Standardmenue
  click $main $((X+140)) $((Y+LY)) 3; sleep 1.2; safe_key Escape; sleep 0.5
  click $main $((X+144)) $((Y+LY)) 3; sleep 1.5
  shot $main d-bp-menu $mode
  # Popup-Eintrag: kein activate (schliesst das Popup); nur wenn kein Terminal unter dem Zeiger aktiv ist
  not_terminal "$(xdotool getactivewindow)" && { xdotool mousemove $((X+144+94)) $((Y+LY+MDY)); sleep 0.3; xdotool click 1; }; sleep 1.5
  shot $main d-bp-set $mode
  click $main $((X+GOX)) $((Y+BY)); sleep 6
  echo "  Go bis Breakpoint: marker=$(mcount) last=$(mlast) [erwartet: Halt vor (f 2), 'f 1' geschrieben, kein 'f 2']"
  grep -q 'f 2' $MARK 2>/dev/null && echo "  Breakpoint NICHT gehalten (Setzen per Popup-Klick in beiden Toolkits unzuverlaessig: Rechtsklick-Treffer wechselt zwischen Pause-Menue und Rename-Menue, s. HACKING 74.6)" || echo "  Breakpoint hielt"
  shot $main d-bp-hit $mode
  click $main $((X+GOX)) $((Y+BY)); sleep 6
  echo "  Go bis Ende: marker=$(mcount) last=$(mlast) [erwartet 'end 102 104']"
  shot $main d-end $mode
  stop_dr
done
sidebyside d-bp-menu d0 d-step3 d-bp-set d-bp-hit d-end

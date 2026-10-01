#!/usr/bin/env bash
# Funktions-Sweep 13: Macro Stepper Einzelschritte.  Macro-Stepper-Knopf -> Fenster; dann Step (vor) x3,
# Previous (zurueck) x2, End, Start per Mausklick auf die Toolbar-Knoepfe; nach jedem Schritt Aufnahme + OCR.
# Verglichen werden die per OCR gelesenen Schritt-Titel ("[Macro transformation]", ...) und deren Anzahl.
# Knopfkoordinaten (relativ zum Stepper-Fenster) sind je Toolkit verschieden (Fensterbreite/Theme).
SCENE=func-stepper; source "$(dirname "$0")/func-lib.sh"
for mode in $MODES; do
  echo "== $mode =="
  D=$FUNC_TMP/$mode; mkdir -p $D; cp "$HERE/files/run.rkt" $D/run.rkt
  start_dr $mode -l drracket $D/run.rkt || exit 1
  main=$(findwin 'run\.rkt.*DrRacket$' 90) || { echo "kein Fenster"; stop_dr; continue; }
  sleep 10; eval "$(xdotool getwindowgeometry --shell $main)"
  click $main $((X+458)) $((Y+40)); sleep 6
  ms=$(findwin 'Macro Stepper' 8) || { echo "  (erster Klick ohne Wirkung, zweiter Versuch)"; click $main $((X+458)) $((Y+40)); sleep 6; }
  ms=$(findwin 'Macro Stepper' 20) || { echo "KEIN Macro-Stepper-Fenster"; stop_dr; continue; }
  sleep 3; eval "$(xdotool getwindowgeometry --shell $ms)"; MX=$X; MY=$Y
  echo "  Stepper: '$(title $ms)' ${WIDTH}x${HEIGHT}"
  if [ "$mode" = qt ]; then BY=38; BS=207; BP=290; BN=375; BE=460; else BY=46; BS=237; BP=303; BN=360; BE=435; fi
  ocr() { tesseract "$OUT/$SCENE-$1-$mode.png" - 2>/dev/null | tr '\n' ' ' | grep -o '\[[A-Za-z][^]]*\]' | tr '\n' ' '; }
  step() { # name x
    click $ms $((MX+$2)) $((MY+BY)); sleep 3; shot $ms "$1" "$mode"; echo "  $1: $(ocr $1)"
  }
  shot $ms s0 "$mode"; echo "  s0: $(ocr s0)"
  step n1 $BN; step n2 $BN; step n3 $BN
  step p1 $BP; step p2 $BP
  step end $BE
  step start $BS
  stop_dr
done
sidebyside s0 n1 n2 n3 p1 p2 end start

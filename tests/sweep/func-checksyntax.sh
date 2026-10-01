#!/usr/bin/env bash
# Funktions-Sweep 6+5: Check Syntax mit Pfeilen und Tooltips.  Klick auf den Check-Syntax-Knopf,
# Warten auf die Auswertung, Maus ueber ein gebundenes Symbol (Pfeile + Tooltip-Float-Frame),
# Aufnahme des Fensterbereichs mit 80 px Rand (der Tooltip kann ausserhalb liegen); danach Hover
# ueber die Definition und ueber ein Literal.  Zusaetzlich: Anzahl/Geometrie neuer Top-Level-Fenster.
SCENE=func-cs; source "$(dirname "$0")/func-lib.sh"
fullshot() { # win name mode : Fenster + 80px Rand
  eval "$(xdotool getwindowgeometry --shell "$1")"
  spectacle -b -n -f -o "$OUT/.full.png" >/dev/null 2>&1
  python3 - "$OUT/.full.png" "$OUT/$SCENE-$2-$3.png" "$X" "$Y" "$WIDTH" "$HEIGHT" <<'PY'
import sys
from PIL import Image
src,dst,x,y,w,h=sys.argv[1],sys.argv[2],*map(int,sys.argv[3:7])
im=Image.open(src); im.crop((max(x-80,0),max(y-80,0),min(x+w+80,im.width),min(y+h+80,im.height))).save(dst)
PY
}
hover() { # win absx absy
  activate "$1"; is_active "$1" && { xdotool mousemove "$2" "$3"; sleep 0.3; xdotool mousemove_relative 2 1; sleep 0.3; xdotool mousemove_relative -- -1 0; }
}
for mode in $MODES; do
  echo "== $mode =="
  D=$FUNC_TMP/$mode; mkdir -p $D; cp "$HERE/files/run.rkt" $D/run.rkt
  start_dr $mode -l drracket $D/run.rkt || exit 1
  main=$(findwin 'run\.rkt.*DrRacket$' 90) || { echo "kein Fenster"; stop_dr; continue; }
  sleep 10; eval "$(xdotool getwindowgeometry --shell $main)"
  before=$(xdotool search --onlyvisible --name '.' | wc -l)
  click $main $((X+243)) $((Y+38)); sleep 10
  fullshot $main after-cs "$mode"
  xdotool search --onlyvisible --class racket | sort > $FUNC_TMP/ids-before
  hover $main $((X+52)) $((Y+165))
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    sleep 0.25; xdotool search --onlyvisible --class racket | sort | comm -13 $FUNC_TMP/ids-before - | while read w; do echo "    t=$i neu: $w $(xdotool getwindowgeometry $w | tail -2 | tr '\n' ' ')"; done
  done
  fullshot $main hover-use "$mode"
  echo "  DrRacket-Fenster: $(xdotool getwindowgeometry $main | tr '\n' ' ')"
  echo "  Tooltip-/Float-Fenster (nur Klasse racket, ohne Hauptfenster):"
  xdotool search --onlyvisible --class racket | while read w; do [ "$w" = "$main" ] || echo "    $w '$(title $w)' $(xdotool getwindowgeometry $w | tail -2 | tr '\n' ' ')"; done
  hover $main $((X+120)) $((Y+141)); sleep 3; fullshot $main hover-def "$mode"
  hover $main $((X+75)) $((Y+142)); sleep 3; fullshot $main hover-x "$mode"
  stop_dr
done
sidebyside after-cs hover-use hover-def hover-x

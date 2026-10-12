#!/usr/bin/env bash
# Rosa Suchfeld nach Replace All (Treffer 6 -> 0, set-red wird NACH einer Dokumentaenderung gesetzt).
# Aufruf: func-nomatch-replace.sh [gtk|qt|both] [Laeufe] [Zyklen]  (Zyklus = Ctrl+Z, dann Replace All erneut per Menue)
SCENE=func-nomatch-replace; source "$(dirname "$0")/func-lib.sh"
N=${2:-3}; CYC=${3:-2}
pinkcount() { python3 - "$1" <<'PY'
import sys
from PIL import Image
im=Image.open(sys.argv[1]).convert('RGB'); px=im.load(); n=0
for y in range(im.height):
  for x in range(im.width):
    r,g,b=px[x,y]
    if abs(r-255)<=8 and abs(g-192)<=10 and abs(b-203)<=10: n+=1
print(n)
PY
}
for mode in $MODES; do
  echo "== $mode: $N Laeufe =="; yes=0
  for ((i=1;i<=N;i++)); do
    D=$FUNC_TMP/$mode-$i; mkdir -p $D; cp "$HERE/files/find.rkt" $D/find.rkt
    start_dr $mode -l drracket $D/find.rkt || exit 1
    main=$(findwin 'find\.rkt.*DrRacket$' 90) || { echo "kein Fenster"; stop_dr; continue; }
    sleep ${NM_WAIT:-8}; eval "$(xdotool getwindowgeometry --shell $main)"
    RY=438; [ "$mode" = gtk ] && RY=454
    click $main $((X+300)) $((Y+200))
    key $main ctrl+f; sleep 1; typ $main "foo"; sleep 1
    key $main ctrl+shift+r; sleep 1
    click $main $((X+290)) $((Y+HEIGHT-50)); typ $main "qux"; sleep 1
    for ((c=0;c<=CYC;c++)); do
      if [ $c -gt 0 ]; then click $main $((X+300)) $((Y+250)); key $main ctrl+z; sleep 1.5
        shot $main r${i}c${c}u "$mode"; echo "    c$c nach Undo: rosa-px=$(pinkcount "$OUT/$SCENE-r${i}c${c}u-$mode.png") (erwartet 0)"; fi
      click $main $((X+60)) $((Y+14)); sleep 1; click $main $((X+100)) $((Y+RY)); sleep ${NM_SETTLE:-2}
      shot $main r${i}c$c "$mode"; p=$(pinkcount "$OUT/$SCENE-r${i}c$c-$mode.png")
      res=NO; [ "$p" -gt 500 ] && res=YES; echo "  lauf $i zyklus $c: rosa-px=$p -> $res"
    done
    stop_dr
  done
done

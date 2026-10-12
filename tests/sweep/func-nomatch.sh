#!/usr/bin/env bash
# Funktions-Sweep: rosa Suchfeld bei 0 Treffern (searchable-canvas% set-red).  Pro Lauf: DrRacket starten,
# Ctrl+F, nicht vorhandenen Text tippen, Pixelprobe des Fensters auf Rosa (255,192,203 +-6).
# Aufruf: func-nomatch.sh [gtk|qt|both] [Laeufe] [Zyklen-pro-Lauf]   (Zyklen: Feld leeren + neu tippen im selben Prozess)
SCENE=func-nomatch; source "$(dirname "$0")/func-lib.sh"
N=${2:-10}; CYC=${3:-0}
pinkcount() { # png -> Anzahl rosa Pixel
  python3 - "$1" <<'PY'
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
    click $main $((X+300)) $((Y+200))
    key $main ctrl+f; sleep 1; typ $main "zzqq"; sleep ${NM_SETTLE:-2}
    shot $main r$i "$mode"; p=$(pinkcount "$OUT/$SCENE-r$i-$mode.png")
    res=NO; [ "$p" -gt 500 ] && { res=YES; yes=$((yes+1)); }
    echo "  lauf $i: rosa-px=$p -> $res"
    for ((c=1;c<=CYC;c++)); do
      key $main ctrl+a; key $main BackSpace; sleep 0.5; typ $main "zzqq"; sleep ${NM_SETTLE:-2}
      shot $main r${i}c$c "$mode"; p=$(pinkcount "$OUT/$SCENE-r${i}c$c-$mode.png")
      res=NO; [ "$p" -gt 500 ] && res=YES; echo "    zyklus $c: rosa-px=$p -> $res"
    done
    stop_dr
  done
  echo "  $mode: $yes/$N Laeufe rosa (erster Zyklus)"
done

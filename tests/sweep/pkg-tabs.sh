#!/usr/bin/env bash
# Package-Manager-Szene (alle Tabs): racket -l- pkg/gui nativ und mit PLT_QT=1,
# jeden Tab per Mausklick auf die Beschriftung aufnehmen (Koordinaten pro Toolkit,
# aus der Startseite von sweep.sh pkg-manager abgelesen).
# Ausgabe: out/pkgtab-<n>-{gtk,qt,side}.png.  Klicks nur bei aktivem Zielfenster.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); OUT=$HERE/out; mkdir -p "$OUT"
RACKET=${RACKET:-$HOME/racket/bin/racket}
QTP=${QT_PLUGIN_PATH:-$HOME/Qt/6.11.1/gcc_64/plugins}
shot() { # window-id name mode
  eval "$(xdotool getwindowgeometry --shell "$1")"
  spectacle -b -n -f -o "$OUT/.full.png" >/dev/null 2>&1
  python3 - "$OUT/.full.png" "$OUT/pkgtab-$2-$3.png" "$X" "$Y" "$WIDTH" "$HEIGHT" <<'PY'
import sys
from PIL import Image
src,dst,x,y,w,h=sys.argv[1],sys.argv[2],*map(int,sys.argv[3:7])
Image.open(src).crop((x,y,x+w,y+h)).save(dst)
PY
}
run_mode() {
  local mode=$1 pid w tx ty xs i=0
  if pgrep -x racket >/dev/null; then echo "FEHLER: racket läuft noch"; return 1; fi
  if [ "$mode" = qt ]; then
    (exec env PLT_QT=1 QT_PLUGIN_PATH="$QTP" "$RACKET" -l- pkg/gui >"$OUT/pkgtab-$mode.log" 2>&1) &
    xs="179 319 459 558"; ty=37
  else
    (exec "$RACKET" -l- pkg/gui >"$OUT/pkgtab-$mode.log" 2>&1) &
    xs="171 307 444 537"; ty=44
  fi
  pid=$!
  for _ in $(seq 1 60); do sleep 1; w=$(xdotool search --name '^Package Manager' 2>/dev/null | tail -1); [ -n "$w" ] && break; done
  [ -z "${w:-}" ] && { echo "[$mode] Fenster fehlt"; kill $pid; return 1; }
  sleep 12; xdotool windowactivate "$w"; sleep 1
  eval "$(xdotool getwindowgeometry --shell "$w")"; local WX=$X WY=$Y
  for tx in $xs; do
    i=$((i+1))
    xdotool windowactivate "$w"; sleep 0.5
    if [ "$(xdotool getactivewindow)" = "$w" ]; then xdotool mousemove $((WX+tx)) $((WY+ty)) click 1; else echo "  Klick $i übersprungen"; fi
    sleep $([ $i = 2 ] && echo 10 || echo 4)   # Catalog-Tab lädt Daten nach
    shot "$w" "$i" "$mode"; echo "[$mode] tab $i"
  done
  kill $pid 2>/dev/null; wait $pid 2>/dev/null; sleep 2
}
run_mode gtk; run_mode qt
python3 - "$OUT" <<'PY'
import sys,glob,os
from PIL import Image
out=sys.argv[1]
for a in sorted(glob.glob(out+'/pkgtab-*-gtk.png')):
    b=a.replace('-gtk.png','-qt.png')
    if not os.path.exists(b): continue
    A,B=Image.open(a).convert('RGB'),Image.open(b).convert('RGB')
    c=Image.new('RGB',(A.width+B.width+10,max(A.height,B.height)),(255,0,255)); c.paste(A,(0,0)); c.paste(B,(A.width+10,0)); c.save(a.replace('-gtk.png','-side.png'))
    print('side',os.path.basename(a))
PY

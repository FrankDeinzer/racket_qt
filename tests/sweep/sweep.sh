#!/usr/bin/env bash
# Screenshot-Sweep (Linux/X11): startet eine Szene nativ (gtk) und unter Qt,
# nimmt das Fenster auf und legt beide nebeneinander.  Ausgabe: tests/sweep/out/.
# Aufruf:  tests/sweep/sweep.sh gallery        (Szene = tests/sweep/<szene>.rkt)
# Hinweis: nur Fenster-Client-Bereich wird verglichen; Theme-Unterschiede (gtk vs Qt-Stil)
# sind erwartet -- gesucht werden fehlende/zusätzliche Elemente, Größen, Rahmen, Clipping.
set -u
SCENE=${1:?scene}
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$HERE/out; mkdir -p "$OUT"
RACKET=${RACKET:-$HOME/racket/bin/racket}
QTP=${QT_PLUGIN_PATH:-$HOME/Qt/6.11.1/gcc_64/plugins}
TITLE=${2:-sweep-$SCENE}
# Szene mit eigener Kommandozeile: tests/sweep/<szene>.args ({HERE} wird ersetzt);
# Titel dann als Regex (Argument 2), Wartezeit bis zum Screenshot via SETTLE.
SETTLE=${SETTLE:-3}
ARGS_FILE=$HERE/$SCENE.args
if [ -f "$ARGS_FILE" ]; then ARGS=$(sed "s|{HERE}|$HERE|g" "$ARGS_FILE"); else ARGS="$HERE/$SCENE.rkt"; TITLE="^$TITLE\$"; fi
capture() { # $1 = gtk|qt
  local mode=$1 pid
  if [ "$mode" = qt ]; then
    (exec env PLT_QT=1 QT_PLUGIN_PATH="$QTP" "$RACKET" $ARGS >"$OUT/$SCENE-$mode.log" 2>&1) &
  else
    (exec "$RACKET" $ARGS >"$OUT/$SCENE-$mode.log" 2>&1) &
  fi
  pid=$!
  local w=""
  for _ in $(seq 1 60); do
    sleep 1
    w=$(xdotool search --name "$TITLE" 2>/dev/null | tail -1)
    [ -n "$w" ] && break
  done
  if [ -z "$w" ]; then echo "[$mode] Fenster '$TITLE' nicht erschienen"; kill $pid 2>/dev/null; return 1; fi
  sleep "$SETTLE"
  xdotool windowactivate "$w" 2>/dev/null; sleep 1
  eval "$(xdotool getwindowgeometry --shell "$w")"   # X Y WIDTH HEIGHT = Client-Bereich
  spectacle -b -n -f -o "$OUT/$SCENE-$mode.full.png" >/dev/null 2>&1
  python3 - "$OUT/$SCENE-$mode.full.png" "$OUT/$SCENE-$mode.png" "$X" "$Y" "$WIDTH" "$HEIGHT" <<'PY'
import sys
from PIL import Image
src,dst,x,y,w,h=sys.argv[1],sys.argv[2],*map(int,sys.argv[3:7])
Image.open(src).crop((x,y,x+w,y+h)).save(dst)
PY
  rm -f "$OUT/$SCENE-$mode.full.png"
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
  echo "[$mode] ${WIDTH}x${HEIGHT}"
}
capture gtk; capture qt
python3 - "$OUT/$SCENE-gtk.png" "$OUT/$SCENE-qt.png" "$OUT/$SCENE-side.png" <<'PY'
import sys
from PIL import Image
a,b=Image.open(sys.argv[1]).convert("RGB"),Image.open(sys.argv[2]).convert("RGB")
W=a.width+b.width+10; H=max(a.height,b.height)
c=Image.new("RGB",(W,H),(255,0,255)); c.paste(a,(0,0)); c.paste(b,(a.width+10,0)); c.save(sys.argv[3])
print("side-by-side:",sys.argv[3],"(links gtk, rechts Qt)")
PY

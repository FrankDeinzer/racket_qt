#!/usr/bin/env bash
# canvas% 'gl (HACKING §78): examples/gl-canvas-probe.rkt nativ (gtk) und unter Qt.
# Je Phase (initial / resized / shown) Screenshot des Client-Bereichs und Pixelprüfung
# (Ecke = Löschfarbe der Phase, Mitte = rotes Dreieck); Resize per Window-Manager
# (xdotool windowsize), am Ende ein Mausklick (nur Maus, keine Tasten) auf die
# Canvas-Mitte -> muss beim canvas% ankommen (GL-Kind ist mausdurchlässig).
# Ausgabe: tests/sweep/out/gl-<mode>-<phase>.png, Logs gl-<mode>.log.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/../.." && pwd)
OUT=$HERE/out; mkdir -p "$OUT"
RACKET=${RACKET:-$HOME/racket/bin/racket}
QTP=${QT_PLUGIN_PATH:-$HOME/Qt/6.11.1/gcc_64/plugins}
export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$OUT/xdg-gl}; mkdir -p "$XDG_CONFIG_HOME"
declare -A COL=([initial]="26 77 204" [resized]="26 178 51" [shown]="153 26 153")
run() { # $1 = gtk|qt
  local mode=$1 log="$OUT/gl-$1.log" pid w=""
  local envs=(HOLD=4 RESIZE_EXTERNAL=1 PROBE_CLICK_WAIT=4)
  if [ "$mode" = qt ]; then envs+=(PLT_QT=1 QT_PLUGIN_PATH="$QTP"); fi
  (exec env "${envs[@]}" "$RACKET" "$ROOT/examples/gl-canvas-probe.rkt" >"$log" 2>&1) &
  pid=$!
  for phase in initial await-resize resized shown; do
    w=""
    for _ in $(seq 1 120); do
      w=$(xdotool search --name "^gl-probe $phase\$" 2>/dev/null | tail -1); [ -n "$w" ] && break; sleep 0.25
    done
    [ -z "$w" ] && { echo "[$mode] Phase $phase nicht erreicht"; break; }
    if [ "$phase" = await-resize ]; then xdotool windowsize "$w" 460 330; continue; fi
    for _ in $(seq 1 40); do grep -q "^R $phase/readback" "$log" && break; sleep 0.25; done
    xdotool windowactivate "$w" 2>/dev/null; sleep 1   # KWin: inaktive/gerade veränderte Fenster sind halbtransparent
    eval "$(xdotool getwindowgeometry --shell "$w")"
    spectacle -b -n -f -o "$OUT/gl-full.png" >/dev/null 2>&1
    local rb; rb=$(grep "^R $phase/readback" "$log" | sed -E 's/^R [^ ]+ [^ ]+ [^ ]+ [^ ]+ \(([0-9]+) ([0-9]+) .*/\1 \2/')
    python3 - "$OUT/gl-full.png" "$OUT/gl-$mode-$phase.png" "$X" "$Y" "$WIDTH" "$HEIGHT" $rb ${COL[$phase]} "$mode/$phase" <<'PY'
import sys
from PIL import Image
src,dst=sys.argv[1],sys.argv[2]; x,y,w,h,cw,ch,r,g,b=map(int,sys.argv[3:12]); tag=sys.argv[12]
im=Image.open(src).convert("RGB").crop((x,y,x+w,y+h)); im.save(dst)
corner=im.getpixel((6,6)); center=im.getpixel((cw//2,ch//2))
near=lambda p,q: all(abs(a-b)<=12 for a,b in zip(p,q))
ok=near(corner,(r,g,b)) and near(center,(255,0,0))
print(f"S {tag} {'PASS' if ok else 'FAIL'} corner={corner} center={center} canvas={cw}x{ch} win={w}x{h}")
PY
  done
  sleep 1
  if [ -n "$w" ]; then
    eval "$(xdotool getwindowgeometry --shell "$w")"
    xdotool mousemove $((X + 60)) $((Y + 60)) click 1
  fi
  wait $pid
  rm -f "$OUT/gl-full.png"
  grep '^R ' "$log" | sed "s/^/[$mode] /"
}
run gtk; run qt

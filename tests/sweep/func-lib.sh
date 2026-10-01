#!/usr/bin/env bash
# Gemeinsame Helfer der Funktions-Sweeps (func-<szene>.sh).  Wird mit `source` geladen.
# Jede Taste geht nur an ein verifiziert aktives Zielfenster (sonst Abbruch/Skip);
# frisches PLTADDONDIR pro Lauf; Abbruch, wenn noch ein racket-Prozess läuft.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); OUT=$HERE/out; mkdir -p "$OUT"
RACKET=${RACKET:-$HOME/racket/bin/racket}
QTP=${QT_PLUGIN_PATH:-$HOME/Qt/6.11.1/gcc_64/plugins}
FUNC_TMP=$(mktemp -d)
MODES=${1:-both}; [ "$MODES" = both ] && MODES="gtk qt"

findwin() { # regex timeout-s -> id (letzter Treffer)
  local w="" i
  for ((i=0;i<$2;i++)); do
    w=$(xdotool search --name "$1" 2>/dev/null | tail -1); [ -n "$w" ] && { echo "$w"; return 0; }
    sleep 1
  done; return 1
}
is_active() { [ "$(xdotool getactivewindow 2>/dev/null)" = "$1" ]; }
activate() { xdotool windowactivate "$1" 2>/dev/null; sleep 0.5; }
key() { # win keys...  -- nur wenn aktiv
  local w=$1; shift; activate "$w"
  if is_active "$w"; then xdotool key --delay 60 "$@"; else echo "  (key uebersprungen, $w nicht aktiv: $*)"; return 1; fi
}
typ() { # win text
  local w=$1; shift; activate "$w"
  if is_active "$w"; then xdotool type --delay 40 "$*"; else echo "  (type uebersprungen)"; return 1; fi
}
click() { # win absx absy [button]
  activate "$1"
  if is_active "$1"; then xdotool mousemove "$2" "$3"; sleep 0.2; xdotool click "${4:-1}"; else echo "  (click uebersprungen)"; return 1; fi
}
safe_key() { # Popup-Menues: nur wenn aktives Fenster nicht das Terminal ist
  local n; n=$(xdotool getwindowname "$(xdotool getactivewindow)" 2>/dev/null)
  case "$n" in *Konsole*|*claude*|"") echo "  (safe_key uebersprungen: '$n')"; return 1;; esac
  xdotool key --delay 60 "$@"
}
shot() { # win name mode  -> out/<scene>-<name>-<mode>.png (Client-Bereich)
  eval "$(xdotool getwindowgeometry --shell "$1")"
  spectacle -b -n -f -o "$OUT/.full.png" >/dev/null 2>&1
  python3 - "$OUT/.full.png" "$OUT/$SCENE-$2-$3.png" "$X" "$Y" "$WIDTH" "$HEIGHT" <<'PY'
import sys
from PIL import Image
src,dst,x,y,w,h=sys.argv[1],sys.argv[2],*map(int,sys.argv[3:7])
Image.open(src).crop((x,y,x+w,y+h)).save(dst)
PY
}
title() { xdotool getwindowname "$1" 2>/dev/null; }
# start_dr mode args...  -> setzt PID; frisches PLTADDONDIR
start_dr() {
  local mode=$1; shift
  if pgrep -x racket >/dev/null; then echo "FEHLER: racket-Prozess laeuft noch -- abbrechen"; return 1; fi
  export PLTADDONDIR=$(mktemp -d)
  # Preferences liegen NICHT unter PLTADDONDIR, sondern in $XDG_CONFIG_HOME/racket (sonst fliesst der
  # Zustand des gtk-Laufs in den Qt-Lauf: Replace-Leiste, Fenstergroessen, ...).
  export XDG_CONFIG_HOME=$(mktemp -d)
  if [ "$mode" = qt ]; then
    (exec env PLT_QT=1 QT_PLUGIN_PATH="$QTP" "$RACKET" "$@" >"$OUT/$SCENE-$mode.log" 2>&1) &
  else
    (exec "$RACKET" "$@" >"$OUT/$SCENE-$mode.log" 2>&1) &
  fi
  PID=$!
}
stop_dr() { kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; sleep 2; }
sidebyside() { # name...
  python3 - "$OUT" "$SCENE" "$@" <<'PY'
import sys,os
from PIL import Image
out,scene=sys.argv[1:3]
for n in sys.argv[3:]:
    a,b=f'{out}/{scene}-{n}-gtk.png',f'{out}/{scene}-{n}-qt.png'
    if not (os.path.exists(a) and os.path.exists(b)): continue
    A,B=Image.open(a).convert('RGB'),Image.open(b).convert('RGB')
    c=Image.new('RGB',(A.width+B.width+10,max(A.height,B.height)),(255,0,255)); c.paste(A,(0,0)); c.paste(B,(A.width+10,0)); c.save(f'{out}/{scene}-{n}-side.png')
    print('side',n,A.size,B.size)
PY
}

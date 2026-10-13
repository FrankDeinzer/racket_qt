#!/usr/bin/env bash
# Optik-Matrix (docs/COVERAGE.md "Optik (OP)", HACKING §84): je Szene von examples/visual-matrix-probe.rkt
# nativ (gtk, ohne PLT_QT) und mit PLT_QT=1 starten, Fensterausschnitt aufnehmen (xdotool + spectacle + Pillow)
# und das Geometrie-Protokoll (stderr der Probe) vergleichen: tests/sweep/visual-matrix-diff.py.
# Theme-Unterschiede (Breeze/Fusion vs. GTK) sind erwartet: bewertet wird Geometrie (Groesse, Clipping,
# Ueberlappung, Ausrichtung, fehlende Elemente); das Pixelmass ist nur ein Hinweis.
# Aufruf: tests/sweep/visual-matrix.sh [gtk|qt|both] [szene ...]   (ohne Szene: alle).  "gtk"/"qt" nehmen nur
#   diesen Modus auf (ohne Vergleich).  Ausgabe: tests/sweep/out/vm-<szene>-{gtk,qt,side}.png, .{gtk,qt}.proto
# Bekannte, begruendete Abweichungen: tests/sweep/visual-matrix-known.txt.  Exit 1 bei Bug-Kandidaten.
# Sicherheit: Tasten/Klicks nur nach Active-Window-Check, nie an Konsole; Preferences-Isolation per XDG_CONFIG_HOME.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/../.." && pwd); OUT=$HERE/out; mkdir -p "$OUT"
RACKET=${RACKET:-$HOME/racket/bin/racket}; QTP=${QT_PLUGIN_PATH:-$HOME/Qt/6.11.1/gcc_64/plugins}
MODES=${1:-both}; shift || true; [ "$MODES" = both ] && MODES="gtk qt"
SCENES=${*:-$("$RACKET" "$ROOT/examples/visual-matrix-probe.rkt" list)}
if pgrep -x racket >/dev/null; then echo "FEHLER: es laeuft noch ein racket-Prozess -- abbrechen"; exit 2; fi

findwin() { local w="" i c
  for ((i=0;i<$2;i++)); do
    w=$(for c in $(xdotool search --name "$1" 2>/dev/null); do case "$(xdotool getwindowname $c 2>/dev/null)" in *Konsole*) ;; *) echo $c;; esac; done | tail -1)
    [ -n "$w" ] && { echo "$w"; return 0; }; sleep 1
  done; return 1; }
is_active() { [ "$(xdotool getactivewindow 2>/dev/null)" = "$1" ]; }

capture() { # szene modus
  local s=$1 mode=$2 pid w X Y WIDTH HEIGHT pad=0 settle=3
  local proto=$OUT/vm-$s.$mode.proto png=$OUT/vm-$s-$mode.png
  export PLTADDONDIR=$(mktemp -d) XDG_CONFIG_HOME=$(mktemp -d)
  if [ "$mode" = qt ]; then
    (exec env PLT_QT=1 QT_PLUGIN_PATH="$QTP" "$RACKET" "$ROOT/examples/visual-matrix-probe.rkt" "$s" >"$OUT/vm-$s.$mode.log" 2>"$proto") &
  else
    (exec "$RACKET" "$ROOT/examples/visual-matrix-probe.rkt" "$s" >"$OUT/vm-$s.$mode.log" 2>"$proto") &
  fi
  pid=$!
  w=$(findwin "^vm-$s\$" 60) || { echo "[$s/$mode] Fenster nicht erschienen"; kill $pid 2>/dev/null; wait $pid 2>/dev/null; return 1; }
  case $s in popup-menu) pad=160; settle=4;; menubar-open) pad=160;; esac
  sleep $settle
  xdotool windowactivate "$w" 2>/dev/null; sleep 1
  eval "$(xdotool getwindowgeometry --shell "$w")"
  if [ "$s" = menubar-open ]; then   # Klick auf den ersten Menuetitel (Active-Window-Check)
    if is_active "$w"; then xdotool mousemove $((X+22)) $((Y+8)); sleep 0.3; xdotool click 1; sleep 1.2
    else echo "  (Klick uebersprungen: Fenster nicht aktiv)"; fi
  fi
  spectacle -b -n -f -o "$OUT/.vm-full.png" >/dev/null 2>&1
  python3 - "$OUT/.vm-full.png" "$png" "$X" "$Y" "$WIDTH" "$HEIGHT" "$pad" <<'PY'
import sys
from PIL import Image
src,dst,x,y,w,h,pad=sys.argv[1],sys.argv[2],*map(int,sys.argv[3:8])
im=Image.open(src); im.crop((x,y,min(im.width,x+w+pad),min(im.height,y+h+pad))).save(dst)
PY
  rm -f "$OUT/.vm-full.png"
  # Menue schliessen (Escape nur wenn das Probe-Fenster oder ein Nicht-Terminal aktiv ist)
  if [ $s = menubar-open ] || [ $s = popup-menu ]; then
    n=$(xdotool getwindowname "$(xdotool getactivewindow)" 2>/dev/null); case "$n" in *Konsole*|"") ;; *) xdotool key Escape;; esac
  fi
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
  echo "xwin $WIDTH $HEIGHT" >> "$proto"
  echo "[$s/$mode] ${WIDTH}x${HEIGHT}"
}

bad=0
for s in $SCENES; do
  for m in $MODES; do capture "$s" "$m"; sleep 0.5; done
  if [ "$MODES" = "gtk qt" ]; then
    python3 "$HERE/visual-matrix-diff.py" "$s" "$OUT/vm-$s.gtk.proto" "$OUT/vm-$s.qt.proto" \
      "$OUT/vm-$s-gtk.png" "$OUT/vm-$s-qt.png" "$OUT/vm-$s-side.png" "$HERE/visual-matrix-known.txt" || bad=1
  fi
done
exit $bad

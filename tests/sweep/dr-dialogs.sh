#!/usr/bin/env bash
# Dialog-Szenen des Screenshot-Sweeps: startet das echte DrRacket nativ (gtk) und
# mit PLT_QT=1 und nimmt nacheinander Preferences (alle Kategorien), Find-Leiste,
# Choose Language und Search in Files auf.  Ausgabe: out/dlg-<name>-{gtk,qt}.png
# und out/dlg-<name>-side.png.  Jede Taste/Klick nur, wenn das erwartete Fenster
# aktiv ist (ein Escape im falschen Fenster würde z. B. das Claude-Terminal erreichen).
# Aufruf: tests/sweep/dr-dialogs.sh [gtk|qt|both]
set -u
export PLTADDONDIR=${PLTADDONDIR:-}
HERE=$(cd "$(dirname "$0")" && pwd); OUT=$HERE/out; mkdir -p "$OUT"
RACKET=${RACKET:-$HOME/racket/bin/racket}
QTP=${QT_PLUGIN_PATH:-$HOME/Qt/6.11.1/gcc_64/plugins}
MODES=${1:-both}; [ "$MODES" = both ] && MODES="gtk qt"

findwin() { # regex timeout-seconds -> window id (letzter Treffer) oder leer
  local w="" i
  for ((i=0;i<$2;i++)); do
    w=$(xdotool search --name "$1" 2>/dev/null | tail -1); [ -n "$w" ] && { echo "$w"; return 0; }
    sleep 1
  done; return 1
}
activate() { xdotool windowactivate "$1" 2>/dev/null; sleep 1; }
is_active() { [ "$(xdotool getactivewindow 2>/dev/null)" = "$1" ]; }
key() { # window-id keys...
  local w=$1; shift
  xdotool windowactivate "$w" 2>/dev/null; sleep 0.4
  if is_active "$w"; then xdotool key "$@"; else echo "  (übersprungen: Fenster $w nicht aktiv: $*)"; return 1; fi
}
safe_key() { # Tasten an ein evtl. offenes Popup-Menü: nur wenn das aktive Fenster nicht das Terminal ist
  local n; n=$(xdotool getwindowname "$(xdotool getactivewindow)" 2>/dev/null)
  case "$n" in *Konsole*|*claude*|"") echo "  (safe_key übersprungen: aktives Fenster '$n')"; return 1;; esac
  xdotool key "$@"
}
click() { # window-id absx absy
  xdotool windowactivate "$1" 2>/dev/null; sleep 0.4
  if is_active "$1"; then xdotool mousemove "$2" "$3" click 1; else echo "  (Klick übersprungen)"; return 1; fi
}
shot() { # window-id name mode
  eval "$(xdotool getwindowgeometry --shell "$1")"
  spectacle -b -n -f -o "$OUT/.full.png" >/dev/null 2>&1
  python3 - "$OUT/.full.png" "$OUT/dlg-$2-$3.png" "$X" "$Y" "$WIDTH" "$HEIGHT" <<'PY'
import sys
from PIL import Image
src,dst,x,y,w,h=sys.argv[1],sys.argv[2],*map(int,sys.argv[3:7])
Image.open(src).crop((x,y,x+w,y+h)).save(dst)
PY
  echo "  shot $2 ${WIDTH}x${HEIGHT}"
}

run_mode() {
  local mode=$1 pid main dlg
  if pgrep -x racket >/dev/null; then echo "FEHLER: es laeuft noch ein racket-Prozess (altes DrRacket?) -- abbrechen"; return 1; fi
  echo "== $mode =="
  export PLTADDONDIR=$(mktemp -d)
  export XDG_CONFIG_HOME=$(mktemp -d)   # Preferences liegen unter $XDG_CONFIG_HOME/racket (nicht PLTADDONDIR): frischer Zustand pro Lauf
  if [ "$mode" = qt ]; then
    (exec env PLT_QT=1 QT_PLUGIN_PATH="$QTP" "$RACKET" -l drracket "$HERE/files/a.rkt" "$HERE/files/b.rkt" >"$OUT/dlg-$mode.log" 2>&1) &
  else
    (exec "$RACKET" -l drracket "$HERE/files/a.rkt" "$HERE/files/b.rkt" >"$OUT/dlg-$mode.log" 2>&1) &
  fi
  pid=$!
  main=$(findwin '\.rkt.*DrRacket$' 90) || { echo "DrRacket-Fenster fehlt"; kill $pid; return 1; }
  sleep 10; activate "$main"; eval "$(xdotool getwindowgeometry --shell "$main")"
  local MX=$X MY=$Y MW=$WIDTH MH=$HEIGHT

  # 1. Preferences: Ctrl+; und alle Kategorien per Pfeil-runter in der Liste
  key "$main" ctrl+semicolon
  if dlg=$(findwin '^Preferences$' 10); then
    sleep 3; activate "$dlg"; shot "$dlg" prefs-0 "$mode"
    # Tab-Beschriftungen (x im Dialog-Client, y) -- pro Toolkit anders, aus den Aufnahmen abgelesen
    local xs ty
    if [ "$mode" = qt ]; then xs="81 143 214 287 358 433 492 595"; ty=37; else xs="62 113 175 240 300 362 415 510"; ty=44; fi
    eval "$(xdotool getwindowgeometry --shell "$dlg")"; local DX=$X DY=$Y
    local i=0 tx
    for tx in $xs; do
      i=$((i+1)); click "$dlg" $((DX+tx)) $((DY+ty)); sleep 1.5; shot "$dlg" "prefs-$i" "$mode"
    done
    key "$dlg" Escape; sleep 2
  else echo "  Preferences nicht erschienen"; fi

  # 2. Find-Leiste: Ctrl+F im Hauptfenster
  activate "$main"; key "$main" ctrl+f; sleep 2; shot "$main" find "$mode"
  key "$main" Escape; sleep 1

  # 3. Choose Language: Klick auf die Sprachanzeige in der Statuszeile -> Popup (Aufnahme),
  #    dann 2x Runter (erster Eintrag ist eine Überschrift) + Return = "Choose Language..."
  activate "$main"; click "$main" $((MX+120)) $((MY+MH-14)); sleep 2
  shot "$main" lang-popup "$mode"
  safe_key Down Down; sleep 1; safe_key Return; sleep 4
  if dlg=$(findwin '^Choose Language' 8); then sleep 2; activate "$dlg"; shot "$dlg" lang "$mode"; key "$dlg" Escape; sleep 2
  else echo "  Choose Language nicht erschienen"; safe_key Escape; fi

  # 4. Search in Files: File-Menü öffnen, 3x Hoch (Quit, Close, Search in Files), Return
  activate "$main"; click "$main" $((MX+20)) $((MY+14)); sleep 1
  safe_key Up Up Up; sleep 1; safe_key Return; sleep 3
  if dlg=$(findwin '^Configure Search$' 8); then sleep 2; activate "$dlg"; shot "$dlg" search "$mode"; key "$dlg" Escape; sleep 2
  else echo "  Configure Search nicht erschienen"; safe_key Escape; fi

  kill $pid 2>/dev/null; wait $pid 2>/dev/null; sleep 2
}
for m in $MODES; do run_mode "$m"; done
python3 - "$OUT" <<'PY'
import sys,glob,os
from PIL import Image
out=sys.argv[1]
names=sorted({os.path.basename(p)[4:].rsplit('-',1)[0] for p in glob.glob(out+'/dlg-*-gtk.png')})
for n in names:
    a,b=out+f'/dlg-{n}-gtk.png',out+f'/dlg-{n}-qt.png'
    if not (os.path.exists(a) and os.path.exists(b)): continue
    A,B=Image.open(a).convert('RGB'),Image.open(b).convert('RGB')
    c=Image.new('RGB',(A.width+B.width+10,max(A.height,B.height)),(255,0,255)); c.paste(A,(0,0)); c.paste(B,(A.width+10,0)); c.save(out+f'/dlg-{n}-side.png')
    print('side',n,A.size,B.size)
PY

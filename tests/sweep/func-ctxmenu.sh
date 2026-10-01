#!/usr/bin/env bash
# Funktions-Sweep 4: Rechtsklick-Kontextmenüs.  Rechtsklick (a) in den Editor auf ein Wort,
# (b) in die REPL, (c) auf den Tab/Dateinamen-Button in der Toolbar; Aufnahme des Popups (voller
# Bildschirm, um Fenster herum beschnitten), Schließen mit Escape (nur wenn nicht Terminal aktiv).
SCENE=func-ctx; source "$(dirname "$0")/func-lib.sh"
popshot() { # name mode cx cy : 420x520 Ausschnitt um den Klickpunkt
  spectacle -b -n -f -o "$OUT/.full.png" >/dev/null 2>&1
  python3 - "$OUT/.full.png" "$OUT/$SCENE-$1-$2.png" "$3" "$4" <<'PY'
import sys
from PIL import Image
src,dst,x,y=sys.argv[1],sys.argv[2],int(sys.argv[3]),int(sys.argv[4])
im=Image.open(src); im.crop((max(x-20,0),max(y-20,0),min(x+420,im.width),min(y+520,im.height))).save(dst)
PY
}
for mode in $MODES; do
  echo "== $mode =="
  D=$FUNC_TMP/$mode; mkdir -p $D; cp "$HERE/files/run.rkt" $D/run.rkt
  start_dr $mode -l drracket $D/run.rkt || exit 1
  main=$(findwin 'run\.rkt.*DrRacket$' 90) || { echo "kein Fenster"; stop_dr; continue; }
  sleep 10; eval "$(xdotool getwindowgeometry --shell $main)"
  key $main F5; sleep 5
  click $main $((X+100)) $((Y+100)) 3; sleep 1.5; popshot editor "$mode" $((X+100)) $((Y+100))
  safe_key Escape; sleep 1
  click $main $((X+60)) $((Y+HEIGHT-150)) 3; sleep 1.5; popshot repl "$mode" $((X+60)) $((Y+HEIGHT-150))
  safe_key Escape; sleep 1
  click $main $((X+30)) $((Y+35)) 3; sleep 1.5; popshot toolbar "$mode" $((X+30)) $((Y+35))
  safe_key Escape; sleep 1
  echo "  Titel danach: '$(title $main)' (Fenster lebt: $(xdotool search --name 'run\.rkt.*DrRacket' | wc -l))"
  stop_dr
done
sidebyside editor repl toolbar

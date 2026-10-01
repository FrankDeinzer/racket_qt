#!/usr/bin/env bash
# Funktions-Sweep 12: Fensterposition/-groesse-Wiederherstellung.  Frisches Preferences-Verzeichnis, Hauptfenster per
# xdotool auf 700x500 @ (200,150) setzen, Ctrl+Q (sauberes Beenden schreibt die Prefs), Neustart MIT DEMSELBEN
# Preferences-Verzeichnis, Geometrie des neuen Fensters lesen.  Verglichen werden gtk und Qt (Fensterrahmen-/WM-Offsets
# sind bei gleichem Tool in beiden gleich).  Zusaetzlich: gespeicherte Werte in racket-prefs.rktd (framework:frame-sizes).
SCENE=func-winpos; source "$(dirname "$0")/func-lib.sh"
geom() { eval "$(xdotool getwindowgeometry --shell $1)"; echo "${WIDTH}x${HEIGHT}+${X}+${Y}"; }
for mode in $MODES; do
  echo "== $mode =="
  D=$FUNC_TMP/$mode; mkdir -p $D; cp "$HERE/files/a.rkt" $D/one.rkt
  unset KEEP_ENV
  start_dr $mode -l drracket $D/one.rkt || exit 1
  main=$(findwin 'one\.rkt.*DrRacket$' 90) || { echo "kein Fenster"; stop_dr; continue; }
  sleep 10; echo "  Start-Geometrie: $(geom $main)"
  xdotool windowsize $main 700 500; sleep 1; xdotool windowmove $main 200 150; sleep 2
  echo "  gesetzt:         $(geom $main)"
  key $main ctrl+q; sleep 6
  kill -0 $PID 2>/dev/null && { echo "  (Prozess lief nach Ctrl+Q noch)"; }
  stop_dr
  echo "  Prefs-Datei (frame-Eintraege): $(tr -d '\n' < $XDG_CONFIG_HOME/racket/racket-prefs.rktd | grep -o 'drracket:window-\(size\|position\) #hash[^)]*)[^)]*)[^)]*)[^)]*)' | head -c 400)"
  KEEP_ENV=1 start_dr $mode -l drracket $D/one.rkt || exit 1
  main=$(findwin 'one\.rkt.*DrRacket$' 90) || { echo "kein Fenster nach Neustart"; stop_dr; continue; }
  sleep 10; echo "  wiederhergestellt: $(geom $main)"
  shot $main restored "$mode"
  stop_dr
done

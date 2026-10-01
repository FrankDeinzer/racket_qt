#!/usr/bin/env bash
# Funktions-Sweep 3: Find/Replace.  Ctrl+F "foo" (inkrementell), Ctrl+G, Replace-Leiste (Ctrl+Shift+R),
# Tab in das Replace-Feld, "qux", Replace All (Ctrl+Shift+F), Ctrl+S; Verhalten per Dateiinhalt auf Platte.
SCENE=func-find; source "$(dirname "$0")/func-lib.sh"
for mode in $MODES; do
  echo "== $mode =="
  D=$FUNC_TMP/$mode; mkdir -p $D; cp "$HERE/files/find.rkt" $D/find.rkt
  start_dr $mode -l drracket $D/find.rkt || exit 1
  main=$(findwin 'find\.rkt.*DrRacket$' 90) || { echo "kein Fenster"; stop_dr; continue; }
  sleep 10; eval "$(xdotool getwindowgeometry --shell $main)"
  click $main $((X+300)) $((Y+200))
  key $main ctrl+f; sleep 1; typ $main "foo"; sleep 1; shot $main find-typed "$mode"
  key $main Return; sleep 1; shot $main find-next "$mode"
  key $main ctrl+shift+r; sleep 1; shot $main replace-bar "$mode"
  click $main $((X+290)) $((Y+HEIGHT-50)); typ $main "qux"; sleep 1; shot $main replace-typed "$mode"
  key $main ctrl+shift+f; sleep 2; shot $main replaced "$mode"
  key $main ctrl+s; sleep 2
  echo "  foo: $(grep -o foo $D/find.rkt | wc -l)  qux: $(grep -o qux $D/find.rkt | wc -l)  (Ctrl+Shift+F = Replace: erwartet 5/1)"
  stop_dr
done
sidebyside find-typed find-next replace-bar replace-typed replaced

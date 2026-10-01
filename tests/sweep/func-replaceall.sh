#!/usr/bin/env bash
# Funktions-Sweep 9: Replace All.  Ctrl+F "foo", Replace-Leiste, "qux" ins Ersetzen-Feld, dann
# Edit > Replace All per Menue-Klick (kein Shortcut; die Menue-Hoehe ist toolkitabhaengig, daher
# je Modus eigene y-Koordinate), Ctrl+S -> Dateiinhalt auf Platte (erwartet foo 0 / qux 6);
# danach Ctrl+Z (ein Undo-Schritt?) + Ctrl+S -> foo-Anzahl.  Zusaetzlich Find Case Sensitive: ohne Wirkung hier.
SCENE=func-replaceall; source "$(dirname "$0")/func-lib.sh"
for mode in $MODES; do
  echo "== $mode =="
  D=$FUNC_TMP/$mode; mkdir -p $D; cp "$HERE/files/find.rkt" $D/find.rkt
  start_dr $mode -l drracket $D/find.rkt || exit 1
  main=$(findwin 'find\.rkt.*DrRacket$' 90) || { echo "kein Fenster"; stop_dr; continue; }
  sleep 10; eval "$(xdotool getwindowgeometry --shell $main)"
  RY=438; [ "$mode" = gtk ] && RY=454   # Zeile "Replace All" im Edit-Menue (Aufnahme-Koordinaten, 600x650)
  click $main $((X+300)) $((Y+200))
  key $main ctrl+f; sleep 1; typ $main "foo"; sleep 1
  key $main ctrl+shift+r; sleep 1
  click $main $((X+290)) $((Y+HEIGHT-50)); typ $main "qux"; sleep 1
  shot $main before "$mode"
  click $main $((X+60)) $((Y+14)); sleep 1; shot $main menu "$mode"
  click $main $((X+100)) $((Y+RY)); sleep 2; shot $main replaced "$mode"
  echo "  Titel nach Replace All: '$(title $main)'"
  key $main ctrl+s; sleep 2
  echo "  nach Replace All: foo $(grep -o foo $D/find.rkt | wc -l)  qux $(grep -o qux $D/find.rkt | wc -l)  (erwartet 0/6)"
  click $main $((X+300)) $((Y+250)); key $main ctrl+z; sleep 1; key $main ctrl+s; sleep 2
  echo "  nach Undo: foo $(grep -o foo $D/find.rkt | wc -l)  qux $(grep -o qux $D/find.rkt | wc -l)"
  shot $main undone "$mode"
  stop_dr
done
sidebyside before menu replaced undone

#!/usr/bin/env bash
# Funktions-Sweep 10: Help Desk.  F1 auf einem Identifier (string-append) und Help-Menue "Help Desk" /
# "Racket Documentation".  Der externe Browser wird per Preferences auf ein Skript umgebogen
# ((external-browser (custom "echo '" "' >> MARKFILE"))), das die URL in eine Marker-Datei schreibt:
# Vergleich der URLs gtk == Qt (Port normalisiert), ausserdem Titel/Fensterliste.  Pref "Ask Later" (#f) startet auf dieser Maschine Konqueror (kein Dialog) -> bewusst nicht Teil des Sweeps.
# Aufruf: tests/sweep/func-help.sh [gtk|qt|both]
SCENE=func-help; source "$(dirname "$0")/func-lib.sh"
seed() { # $1 = browser-wert (sexp)
  export PLTADDONDIR=$(mktemp -d) XDG_CONFIG_HOME=$(mktemp -d); mkdir -p $XDG_CONFIG_HOME/racket
  printf '((external-browser %s))\n' "$1" > $XDG_CONFIG_HOME/racket/racket-prefs.rktd
}
for mode in $MODES; do
  echo "== $mode =="
  MARK=$FUNC_TMP/urls-$mode; rm -f $MARK
  printf '#!/bin/sh\nu=$1; f=${u#file://}; echo "URL $u" >> %s; cat "$f" >> %s; echo >> %s\n' $MARK $MARK $MARK > $FUNC_TMP/br-$mode.sh
  seed "(\"sh $FUNC_TMP/br-$mode.sh \" . \"\")"
  KEEP_ENV=1 start_dr $mode -l drracket "$HERE/files/help.rkt" || exit 1
  main=$(findwin 'help\.rkt.*DrRacket$' 90) || { echo "kein Fenster"; stop_dr; continue; }
  sleep 10; eval "$(xdotool getwindowgeometry --shell $main)"
  click $main $((X+WIDTH/2)) $((Y+200)); key $main ctrl+End; sleep 0.5
  key $main F1; sleep 12
  echo "  Fenster: $(listwins | grep -v "help.rkt" | tr '\n' ';')"
  echo "  URLs nach F1: $( [ -f $MARK ] && grep -aoE 'URL=[^"]+' $MARK | sed -E 's#localhost:[0-9]+#localhost:PORT#; s#[0-9]{10,}#N#g' | sort -u | tr '\n' ' ' || echo FEHLT)"
  [ -f $MARK ] && head -c 600 $MARK | tr "\n" " " | sed "s/^/  RAW: /"; echo
  shot $main f1 $mode
  # Help-Menue: "Help Desk" ueber Menueleiste (Alt+h)
  rm -f $MARK
  key $main alt+h; sleep 1; shot $main helpmenu $mode
  # Eintrag "Racket Documentation" anklicken (y toolkit-abhaengig: gtk 44, Qt 34 im Fenster-Client)
  if [ $mode = qt ]; then MY=34; else MY=44; fi
  click $main $((X+500)) $((Y+MY)); sleep 6
  echo "  Marker nach Menue-Klick: $( [ -f $MARK ] && grep -aoE 'URL=[^"]+|^URL [^ ]+' $MARK | sed -E 's#[0-9]{10,}#N#g' | sort -u | tr '\n' ' ' || echo FEHLT)"
  echo "  Menue noch offen? $(listwins | tr '\n' ';')"
  stop_dr
done
sidebyside f1 helpmenu

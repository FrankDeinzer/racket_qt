#!/usr/bin/env bash
# Funktions-Sweep 10: Save As.  one.rkt editieren, Ctrl+Shift+S (Save Definitions As...), neuen Pfad im Dialog
# tippen + Return -> Datei neu.rkt auf Platte (Marker), one.rkt unveraendert, Titel = neuer Name; weiteres Edit
# + Ctrl+S landet in neu.rkt; zweites Save As auf bestehende two.rkt -> Ueberschreiben-Rueckfrage (Aufnahme, Escape).
SCENE=func-saveas; source "$(dirname "$0")/func-lib.sh"
dlgwin() { findwin '^(Save|Racket: Save|Select|Choose|Please)' 6; }
for mode in $MODES; do
  echo "== $mode =="
  D=$FUNC_TMP/$mode; mkdir -p $D; cp "$HERE/files/a.rkt" $D/one.rkt; cp "$HERE/files/b.rkt" $D/two.rkt
  start_dr $mode -l drracket $D/one.rkt || exit 1
  main=$(findwin 'one\.rkt.*DrRacket$' 90) || { echo "kein Fenster"; stop_dr; continue; }
  sleep 10; eval "$(xdotool getwindowgeometry --shell $main)"
  click $main $((X+300)) $((Y+150)); key $main ctrl+End; typ $main ";; AS-MARK"; sleep 1
  key $main ctrl+shift+s; sleep 3
  dlg=$(dlgwin) && { echo "  Dialog: '$(title $dlg)'"; shot $dlg dialog "$mode"
    typ $dlg "$D/neu.rkt"; sleep 1; shot $dlg dialog-typed "$mode"; key $dlg Return; sleep 4; } || echo "  KEIN Save-Dialog"
  echo "  Titel nach Save As: '$(title $main)'"
  [ -f $D/neu.rkt ] && echo "  neu.rkt existiert, Marker: $(grep -c AS-MARK $D/neu.rkt)" || echo "  neu.rkt FEHLT"
  echo "  one.rkt Marker (erwartet 0): $(grep -c AS-MARK $D/one.rkt)"
  shot $main saved "$mode"
  click $main $((X+300)) $((Y+150)); key $main ctrl+End; typ $main ";; SECOND"; sleep 1; key $main ctrl+s; sleep 2
  echo "  nach Ctrl+S: neu.rkt SECOND $(grep -c SECOND $D/neu.rkt)  one.rkt SECOND $(grep -c SECOND $D/one.rkt)"
  echo "  Titel: '$(title $main)'"
  # Ueberschreiben bestehender Datei
  key $main ctrl+shift+s; sleep 3
  dlg=$(dlgwin) && { typ $dlg "$D/two.rkt"; sleep 1; key $dlg Return; sleep 3
    echo "  OCR Rueckfrage: $(fullshot overwrite "$mode" | grep -o -i 'already exists[^.]*\.\|replace[^.]*\.\|overwrite[^.]*' | head -3 | tr '\n' '|')"
    echo "  sichtbare Fenster: $(xdotool search --onlyvisible --name . | while read w; do echo -n "[$(title $w)] "; done | sed 's/\[[^]]*Konsole[^]]*\]//')"
    safe_key Escape; sleep 2; safe_key Escape; sleep 2;
    sleep 1; echo "  two.rkt SECOND nach Rueckfrage+Escape (erwartet 0): $(grep -c SECOND $D/two.rkt)"
  } || echo "  KEIN zweiter Save-Dialog"
  stop_dr
done
sidebyside dialog dialog-typed saved overwrite

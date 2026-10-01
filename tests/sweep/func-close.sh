#!/usr/bin/env bash
# Funktions-Sweep 9: Schliessen mit ungespeicherten Aenderungen.  Edit -> Ctrl+W -> Rueckfrage-Dialog
# (Aufnahme, Titel), Escape = Abbrechen -> Fenster bleibt, Datei unveraendert; Ctrl+W nochmals und
# Dialog-Default (Return) -> Verhalten (Datei gespeichert? Fenster weg?) wird protokolliert.
SCENE=func-close; source "$(dirname "$0")/func-lib.sh"
for mode in $MODES; do
  echo "== $mode =="
  D=$FUNC_TMP/$mode; mkdir -p $D; cp "$HERE/files/a.rkt" $D/one.rkt; before=$(md5sum < $D/one.rkt)
  start_dr $mode -l drracket $D/one.rkt || exit 1
  main=$(findwin 'one\.rkt.*DrRacket' 90) || { echo "kein Fenster"; stop_dr; continue; }
  sleep 10; eval "$(xdotool getwindowgeometry --shell $main)"
  click $main $((X+300)) $((Y+150)); key $main ctrl+End; typ $main ";; X"; sleep 1
  key $main ctrl+w; sleep 3
  echo "  sichtbare Fenster:"; xdotool search --onlyvisible --name '.' | while read w; do n=$(title $w); case "$n" in *Konsole*|*Plasma*|*Settings*) ;; *) echo "    '$n' $(xdotool getwindowgeometry $w | tail -1)";; esac; done
  dlg=$(xdotool search --onlyvisible --name '^(Warning|Save|Close|Unsaved|DrRacket$)' | tail -1)
  [ -z "$dlg" ] && dlg=$(xdotool search --onlyvisible --name '.' | while read w; do n=$(title $w); case "$n" in *one.rkt*|*Konsole*|*Plasma*|*Settings*|"") ;; *) echo $w;; esac; done | tail -1)
  if [ -n "$dlg" ]; then echo "  Dialog: '$(title $dlg)'"; shot $dlg dialog "$mode"; key $dlg Escape; sleep 2
    echo "  nach Escape: Fenster da=$(xdotool search --name 'one\.rkt' | wc -l), Datei unveraendert=$([ "$(md5sum < $D/one.rkt)" = "$before" ] && echo ja || echo NEIN)"
  else echo "  KEIN Dialog gefunden"; shot $main nodialog "$mode"; fi
  stop_dr
done
sidebyside dialog

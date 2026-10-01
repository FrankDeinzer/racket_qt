#!/usr/bin/env bash
# Funktions-Sweep 2: Datei bearbeiten/speichern/öffnen.  Kopie von run.rkt im Temp-Verzeichnis:
# Text anhängen -> Titel/Save-Button ("modified"), Ctrl+S -> Dateiinhalt auf Platte, Ctrl+O mit
# getipptem Pfad -> zweiter Tab (Tab-Beschriftung/Titel), Screenshot.  Prüft Verhalten per Platte+Titel.
SCENE=func-file; source "$(dirname "$0")/func-lib.sh"
for mode in $MODES; do
  echo "== $mode =="
  D=$FUNC_TMP/$mode; mkdir -p $D; cp "$HERE/files/a.rkt" $D/one.rkt; cp "$HERE/files/b.rkt" $D/two.rkt
  start_dr $mode -l drracket $D/one.rkt || exit 1
  main=$(findwin 'one\.rkt.*DrRacket$' 90) || { echo "kein Fenster"; stop_dr; continue; }
  sleep 10; echo "  Titel start: '$(title $main)'"
  eval "$(xdotool getwindowgeometry --shell $main)"
  click $main $((X+300)) $((Y+150)); key $main ctrl+End
  typ $main ";; EDITED-MARK"; sleep 1
  echo "  Titel nach Edit: '$(title $main)'"; shot $main edited "$mode"
  key $main ctrl+s; sleep 2
  echo "  Titel nach Save: '$(title $main)'"
  grep -c EDITED-MARK $D/one.rkt | sed 's/^/  Datei enthaelt Marker (Anzahl): /'
  shot $main saved "$mode"
  key $main ctrl+o; sleep 3
  echo "  sichtbare Fenster nach Ctrl+O:"; xdotool search --onlyvisible --name '.' 2>/dev/null | while read w; do echo "    $w '$(title $w)'"; done | grep -v "Konsole\|^    [0-9]* ''" | head -8
  dlg=$(findwin '^(Open|Select|Choose|Racket: Open)' 5) && { echo "  Dialog: '$(title $dlg)'"; shot $dlg open-dialog "$mode"
    typ $dlg "$D/two.rkt"; sleep 1; key $dlg Return; sleep 4; } || echo "  KEIN Open-Dialog"
  echo "  Fenster two.rkt: $(xdotool search --name 'two\.rkt' | wc -l)  Titel Haupt: '$(title $main)'"
  two=$(xdotool search --name 'two\.rkt.*DrRacket' | tail -1); [ -n "$two" ] && shot $two opened "$mode" || shot $main opened "$mode"
  # Save As ueber neuen Namen: File-Menue ist toolkit-abhaengig -> hier nur Ctrl+Shift+S gibt es nicht; ausgelassen.
  stop_dr
done
sidebyside edited saved open-dialog opened

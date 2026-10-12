#!/usr/bin/env bash
# Return/Escape im dialog% (examples/dialog-keys-probe.rkt) je Fokuszustand, gtk vs Qt (§73).
# Zustaende: a/b = text-field%, check, list, ok (Default-Button '(border)), cancel.
# Usage: tests/dialog-return-matrix.sh [OUTFILE]   -- Ausgabe je Zeile "<mode> focus=<f> key=<k>: <log>"
OUT="${1:-/tmp/dialog-return-matrix.out}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
export QT_PLUGIN_PATH="${QT_PLUGIN_PATH:-$HOME/Qt/6.11.1/gcc_64/plugins}"
export XDG_CONFIG_HOME=$(mktemp -d) PLTADDONDIR=$(mktemp -d)
: > "$OUT"
pgrep -x racket >/dev/null && { echo "racket laeuft noch -- Abbruch"; exit 1; }
one() {
  local mode=$1 focus=$2 key=$3 log
  log=$(mktemp)
  if [ "$mode" = qt ]; then export PLT_QT=1; else unset PLT_QT; fi
  ( cd "$HERE" && exec "$HOME/racket/bin/racket" examples/dialog-keys-probe.rkt "$log" "$focus" >/dev/null 2>&1 ) &
  local pid=$! W=""
  for _ in $(seq 1 60); do W=$(xdotool search --onlyvisible --name KeyDialog | head -1); [ -n "$W" ] && break; sleep 0.5; done
  sleep 1.5
  if [ -n "$W" ]; then
    xdotool windowactivate --sync "$W"; sleep 0.6
    if [ "$(xdotool getactivewindow)" = "$W" ]; then
      case "$key" in
        CLICKROW*) # Klick auf eine Listenzeile (CLICK_Y = Pixel ab Fensterober-kante), dann Taste(n) nach "CLICKROW "
          eval "$(xdotool getwindowgeometry --shell $W)"
          xdotool mousemove $((X+80)) $((Y+${CLICK_Y:-130})); sleep 0.3; xdotool click 1; sleep 0.4
          if [ "$(xdotool getactivewindow)" = "$W" ]; then xdotool key ${key#CLICKROW }; fi ;;
        DBLROW) # Doppelklick auf eine Listenzeile -> gtk: 'list-box-dclick
          eval "$(xdotool getwindowgeometry --shell $W)"
          xdotool mousemove $((X+80)) $((Y+${CLICK_Y:-130})); sleep 0.3; xdotool click --repeat 2 --delay 80 1 ;;
        *) xdotool key $key ;;
      esac
    else echo "(nicht aktiv, uebersprungen)" >> "$log"; fi
  fi
  sleep 1.2
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
  echo "$mode focus=$focus key=$key: $(tr '\n' ' ' < "$log")" >> "$OUT"
  rm -f "$log"
}
# MATRIX_FOCUS / MATRIX_KEYS (mit | getrennt) schraenken ein; "a Return" = Typeahead (gtk: Suchfeld-Popup!)
IFS='|' read -ra FOCI <<< "${MATRIX_FOCUS:-a|b|check|list|ok|cancel}"
IFS='|' read -ra KEYS <<< "${MATRIX_KEYS:-Return|KP_Enter|Escape|a Return|CLICKROW Return|CLICKROW Escape|CLICKROW KP_Enter}"
for focus in "${FOCI[@]}"; do
  for key in "${KEYS[@]}"; do
    for mode in gtk qt; do one $mode $focus "$key"; done
  done
done
echo DONE >> "$OUT"
cat "$OUT"

#!/usr/bin/env bash
# Block D: Escape/Return from native controls (list, check box, button) must
# reach racket/gui's dialog handling.  Uses examples/dialog-keys-probe.rkt.
# Usage: tests/dialog-nav-keys.sh [OUTFILE]   (default: /tmp/dialog-nav-keys.out)
# Expected: every Qt line ends with "closed"; Return lines also show "BUTTON OK".
OUT="${1:-/tmp/dialog-nav-keys.out}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
export QT_PLUGIN_PATH="${QT_PLUGIN_PATH:-$HOME/Qt/6.11.1/gcc_64/plugins}"
: > "$OUT"
one() {  # mode focus key
  local mode=$1 focus=$2 key=$3 log
  log=$(mktemp)
  if [ "$mode" = qt ]; then export PLT_QT=1; else unset PLT_QT; fi
  ( cd "$HERE" && exec "$HOME/racket/bin/racket" examples/dialog-keys-probe.rkt "$log" "$focus" >/dev/null 2>&1 ) &
  local pid=$! W=""
  for _ in $(seq 1 60); do
    W=$(xdotool search --onlyvisible --name KeyDialog | head -1); [ -n "$W" ] && break; sleep 0.5
  done
  sleep 1.5
  if [ -n "$W" ]; then xdotool windowactivate --sync "$W"; sleep 0.6; xdotool key "$key"; fi
  sleep 1.2
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
  echo "$mode focus=$focus key=$key: $(tr '\n' ' ' < "$log")" >> "$OUT"
  rm -f "$log"
}
for mode in gtk qt; do
  for focus in list check; do
    for key in Escape Return; do one $mode $focus $key; done
  done
done
echo DONE >> "$OUT"

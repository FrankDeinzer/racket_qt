#!/usr/bin/env bash
# Echter Datei-Drop (docs/COVERAGE.md, HACKING §83.2): tests/sweep/dnd-source.py (GTK3-Fenster, Xdnd-Quelle, text/uri-list)
# wird per xdotool-Mausziehen (mousedown/-move/-up, XTEST) auf examples/drop-probe.rkt gezogen; die Probe protokolliert
# "drop <ziel> => <datei>".  Ziele: canvas% mit accept-drop-files (eigenes on-drop-file), canvas% ohne (faellt auf frame% zurueck),
# message% (frame%).  Nativ (gtk) und PLT_QT=1 werden gediffed.  Keine Tasten, nur Maus; Quelle/Probe werden per PID beendet.
# Aufruf: tests/sweep/dnd-drop.sh [gtk|qt|both]     Ausgabe: tests/sweep/out/dnd-drop.{gtk,qt}; Exit 1 bei Abweichung.
SCENE=dnd-drop; source "$(dirname "$0")/func-lib.sh"
ROOT=$(cd "$HERE/../.." && pwd)
FIX=$(mktemp -d); echo a > "$FIX/a.txt"; echo b > "$FIX/b.txt"
bad=0
for MODE in $MODES; do
  if pgrep -x racket >/dev/null; then echo "FEHLER: racket-Prozess laeuft noch"; exit 1; fi
  CTL=$FUNC_TMP/ctl.$MODE; rm -f "$CTL"; mkfifo "$CTL"; exec 7<>"$CTL"
  POSF=$OUT/dnd-drop.$MODE.pos; LOGF=$OUT/dnd-drop.$MODE.log; : > "$POSF"; : > "$LOGF"
  export XDG_CONFIG_HOME=$(mktemp -d) PLTADDONDIR=$(mktemp -d)
  if [ "$MODE" = qt ]; then
    (cd "$ROOT"; exec env PLT_QT=1 QT_PLUGIN_PATH="$QTP" "$RACKET" examples/drop-probe.rkt <&7 >"$POSF" 2>>"$LOGF") &
  else (cd "$ROOT"; exec "$RACKET" examples/drop-probe.rkt <&7 >"$POSF" 2>>"$LOGF") & fi
  PID=$!
  W=$(findwin '^dnd-target$' 90) || { echo "kein Fenster"; kill -9 $PID; continue; }
  sleep 2; echo P >&7; for i in $(seq 1 40); do grep -q frame-ready "$POSF" && break; sleep 0.2; done
  (cd "$ROOT"; exec python3 -I tests/sweep/dnd-source.py "$FIX/a.txt" "$FIX/b.txt" >/dev/null 2>&1) &
  SPID=$!
  S=$(findwin '^dnd-src$' 30) || { echo "keine Quelle"; kill -9 $PID $SPID; continue; }
  sleep 1
  eval "$(xdotool getwindowgeometry --shell "$S")"; SX=$((X+WIDTH/2)); SY=$((Y+HEIGHT/2))
  dragto() { # name  -- Quelle -> Mitte des Ziels
    local l; l=$(grep "^POS $1 " "$POSF" | tail -1); set -- $l; local tx=$(($3+$5/2)) ty=$(($4+$6/2)) i n=12
    xdotool mousemove $SX $SY; sleep 0.4; xdotool mousedown 1; sleep 0.4
    for i in $(seq 1 $n); do xdotool mousemove $((SX+(tx-SX)*i/n)) $((SY+(ty-SY)*i/n)); sleep 0.08; done
    sleep 0.5; xdotool mousemove $((tx+1)) $((ty+1)); sleep 0.5; xdotool mouseup 1; sleep 1.2
  }
  for tgt in canvas-accept canvas-plain msg canvas-accept; do
    echo "step $tgt" >> "$LOGF"; dragto $tgt
  done
  echo X >&7; sleep 1; kill -9 $PID $SPID 2>/dev/null; wait 2>/dev/null; exec 7>&-
  grep -E '^(accept\?|step|drop)' "$LOGF" > "$OUT/dnd-drop.$MODE"
  echo "== $MODE"; cat "$OUT/dnd-drop.$MODE"
done
if [ "$MODES" = "gtk qt" ]; then
  if diff -q "$OUT/dnd-drop.gtk" "$OUT/dnd-drop.qt" >/dev/null; then echo "OK    dnd-drop"; else echo "DIFF  dnd-drop"; diff "$OUT/dnd-drop.gtk" "$OUT/dnd-drop.qt" | sed 's/^/      /'; bad=1; fi
fi
rm -rf "$FIX"; exit $bad

#!/usr/bin/env bash
# Verhaltens-Matrix (docs/COVERAGE.md, HACKING §81): examples/behavior-matrix-probe.rkt je Sektion
# nativ (gtk) und mit PLT_QT=1 ausfuehren und die Protokolle diffen.  Jede Sektion ein eigener
# Prozess (Absturz/Haenger bleibt der Sektion zuordenbar).  Zeilen mit Schluessel "...#px" sind
# reine Pixelwerte (Theme-/Font-abhaengig), "...#info" nur Information (Referenz-Eigenart/WM-abhaengig);
# beide werden nicht verglichen.  Bekannte, begruendete Abweichungen: tests/sweep/behavior-matrix-known.txt.
# Aufruf: tests/sweep/behavior-matrix.sh [sektion ...]     (ohne Argument: alle)
# Ausgabe: tests/sweep/out/behavior-matrix-<sektion>.{gtk,qt}; Exit 1 bei Abweichung.
# Kein xdotool noetig (programmatisch); die Fenster erscheinen kurz auf dem Bildschirm.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/../.." && pwd); OUT=$HERE/out; mkdir -p "$OUT"
RACKET=${RACKET:-$HOME/racket/bin/racket}; QTP=${QT_PLUGIN_PATH:-$HOME/Qt/6.11.1/gcc_64/plugins}
SECS=${*:-$("$RACKET" "$ROOT/examples/behavior-matrix-probe.rkt" list)}
bad=0
for s in $SECS; do
  for mode in gtk qt; do
    if [ $mode = qt ]; then export PLT_QT=1 QT_PLUGIN_PATH=$QTP; else unset PLT_QT; fi
    ( cd "$ROOT"; timeout "${T:-90}" "$RACKET" examples/behavior-matrix-probe.rkt "$s" 2>&1; echo "rc=$?" ) \
      | grep -v -e '#px' -e '#info' | grep -v -F -f "$HERE/behavior-matrix-known.txt" > "$OUT/behavior-matrix-$s.$mode"
  done
  if diff -q "$OUT/behavior-matrix-$s.gtk" "$OUT/behavior-matrix-$s.qt" >/dev/null; then echo "OK    $s"
  else echo "DIFF  $s"; diff "$OUT/behavior-matrix-$s.gtk" "$OUT/behavior-matrix-$s.qt" | sed 's/^/      /'; bad=1; fi
done
exit $bad

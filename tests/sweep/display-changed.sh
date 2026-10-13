#!/usr/bin/env bash
# display-changed (docs/COVERAGE.md, HACKING §83.3): aendert per `xrandr --output <primary> --mode <anderer Modus>` die Aufloesung
# des primaeren Ausgangs, wartet auf display-changed-Aufrufe der Probe (examples/display-changed-probe.rkt) und stellt den
# Ausgangsmodus WIEDER HER (auch per trap bei Abbruch; der Ausgangsmodus wird vorher gelesen, am Ende verifiziert).
# Nur X11 mit xrandr; keine Tasten.  Aufruf: tests/sweep/display-changed.sh [gtk|qt|both] [alternativer-modus, Default 1920x1080]
# Ausgabe: tests/sweep/out/display-changed.{gtk,qt}; Exit 1 wenn ein Modus nicht (rueck)gesetzt werden konnte oder nichts gemeldet wurde.
MODE0=${1:-both}; ALT=${2:-1920x1080}
set -- "$MODE0"; SCENE=display-changed; source "$(dirname "$0")/func-lib.sh"
ROOT=$(cd "$HERE/../.." && pwd)
OUTPUT=$(xrandr --current | awk '/ connected primary/ {print $1; exit}'); [ -n "$OUTPUT" ] || OUTPUT=$(xrandr --current | awk '/ connected/ {print $1; exit}')
ORIG=$(xrandr --current | awk -v o="$OUTPUT" '$1==o {f=1; next} f && /\*/ {print $1; exit} f && /^[^ ]/ {exit}')
[ -n "$OUTPUT" ] && [ -n "$ORIG" ] || { echo "kein Ausgang/Modus erkannt"; exit 1; }
xrandr --current | awk -v o="$OUTPUT" '$1==o {f=1; next} f && $1=="'"$ALT"'" {found=1} f && /^[^ ]/ {exit} END {exit !found}' || { echo "Modus $ALT fuer $OUTPUT nicht vorhanden"; exit 1; }
[ "$ALT" = "$ORIG" ] && { echo "alternativer Modus == Ausgangsmodus"; exit 1; }
restore() { xrandr --output "$OUTPUT" --mode "$ORIG" >/dev/null 2>&1; }
trap restore EXIT
echo "Ausgang $OUTPUT Ausgangsmodus $ORIG, Testmodus $ALT"
bad=0
for MODE in $MODES; do
  if pgrep -x racket >/dev/null; then echo "FEHLER: racket-Prozess laeuft noch"; exit 1; fi
  CTL=$FUNC_TMP/ctl.$MODE; rm -f "$CTL"; mkfifo "$CTL"; exec 7<>"$CTL"
  LOGF=$OUT/display-changed.$MODE.log; : > "$LOGF"
  export XDG_CONFIG_HOME=$(mktemp -d) PLTADDONDIR=$(mktemp -d)
  if [ "$MODE" = qt ]; then (cd "$ROOT"; exec env PLT_QT=1 QT_PLUGIN_PATH="$QTP" "$RACKET" examples/display-changed-probe.rkt <&7 >/dev/null 2>>"$LOGF") &
  else (cd "$ROOT"; exec "$RACKET" examples/display-changed-probe.rkt <&7 >/dev/null 2>>"$LOGF") & fi
  PID=$!
  findwin '^dc-probe$' 90 >/dev/null || { echo "kein Fenster ($MODE)"; kill -9 $PID; bad=1; continue; }
  sleep 3
  xrandr --output "$OUTPUT" --mode "$ALT" || { echo "xrandr --mode $ALT fehlgeschlagen"; bad=1; }
  sleep 5
  echo "--- nach Moduswechsel" >> "$LOGF"
  restore; sleep 5
  echo "--- nach Wiederherstellung" >> "$LOGF"
  echo X >&7; sleep 1; kill -9 $PID 2>/dev/null; wait $PID 2>/dev/null; exec 7>&-
  cp "$LOGF" "$OUT/display-changed.$MODE"
  echo "== $MODE"; cat "$LOGF"
  grep -q '^display-changed' "$LOGF" || { echo "KEIN display-changed-Aufruf ($MODE)"; bad=1; }
done
now=$(xrandr --current | awk -v o="$OUTPUT" '$1==o {f=1; next} f && /\*/ {print $1; exit}')
echo "Modus jetzt: $now (Ausgang war $ORIG)"; [ "$now" = "$ORIG" ] || bad=1
exit $bad

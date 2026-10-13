#!/usr/bin/env bash
# Dialoge zur Laufzeit (docs/COVERAGE.md, HACKING §83.1): examples/dialog-runtime-probe.rkt oeffnet je Aufruf einen Dialog
# (message-box, message-box/custom, get-text-from-user, get-choices-from-user, get-color-from-user, get-font-from-user,
# get-file, put-file, get-directory, get-file-list); dieses Skript bedient ihn mit echter X11-Eingabe (xdotool: Enter, Escape,
# Tippen, Klick auf Dialog-Buttons, Klick auf das gesperrte Hauptfenster) und die Probe protokolliert Titel, Buttonreihenfolge,
# Rueckgabewert, Fokus des Hauptfensters vor/nach dem Dialog und ob das Hauptfenster waehrend des Dialogs bedienbar war.
# Nativ (gtk) und PLT_QT=1 werden gediffed.  Tasten gehen nur an ein verifiziert aktives Dialogfenster (func-lib.sh: nie Terminal).
# Aufruf: tests/sweep/dialog-runtime.sh [gtk|qt|both] [szenario ...]    ("list" nennt die Szenarien)
# Ausgabe: tests/sweep/out/dialog-runtime.{gtk,qt}; Exit 1 bei Abweichung (nach Abzug von dialog-runtime-known.txt, grep -F, Zeilenpraefixe).
MODEARG=${1:-both}; [ $# -gt 0 ] && shift
SCNARGS=$*
set -- "$MODEARG"; SCENE=dialog-runtime; source "$(dirname "$0")/func-lib.sh"
ROOT=$(cd "$HERE/../.." && pwd); KNOWN=$HERE/dialog-runtime-known.txt
FIX=$(mktemp -d); mkdir -p "$FIX/sub"; echo a > "$FIX/a.txt"; echo '#lang racket' > "$FIX/b.rkt"; echo c > "$FIX/sub/c.txt"

# Szenario-Tabelle:  "<szenario>|<tag>|<aktion> <aktion> ..."   Aktionen: key:<Taste> type:<text> btn:<Label> modal wait:<s>  ($FIX wird ersetzt)
TABLE=(
"mb-ok|return|key:Return" "mb-ok|escape|key:Escape" "mb-ok|click-ok|btn:OK" "mb-ok|modal|modal key:Return"
"mb-ok-noparent|return|key:Return"
"mb-ok-cancel|return|key:Return" "mb-ok-cancel|escape|key:Escape" "mb-ok-cancel|click-cancel|btn:Cancel" "mb-ok-cancel|click-ok|btn:OK"
"mb-yes-no|return|key:Return" "mb-yes-no|escape|key:Escape" "mb-yes-no|click-no|btn:&No" "mb-yes-no|click-yes|btn:&Yes"
"mb-caution|return|key:Return" "mb-stop|escape|key:Escape"
"mb-custom|return|key:Return" "mb-custom|escape|key:Escape" "mb-custom|space|key:space" "mb-ok-cancel|space|key:space" "mb-custom|click-alpha|btn:Alpha" "mb-custom|click-gamma|btn:Gamma"
"mb-custom-noclose|escape|key:Escape" "mb-custom-noclose|return|key:Return"
"tf|type-return|type:hello key:Return" "tf|return|key:Return" "tf|escape|key:Escape" "tf|click-ok|btn:OK" "tf|click-cancel|btn:Cancel"
"tf-empty|return|key:Return"
"ch|return|key:Return" "ch|escape|key:Escape"
"color|return|key:Return" "color|escape|key:Escape"
"font|click-ok|btn:OK" "font|escape|key:Escape"
"gf|escape|key:Escape" "gf|type-path|type:\$FIX/b.rkt key:Return" "gf|modal|modal key:Escape"
"gf-name|escape|key:Escape" "gf-filter|escape|key:Escape" "gf-filter|type-path|type:\$FIX/a.txt key:Return"
"pf|return|key:Return" "pf|escape|key:Escape" "pf|type-name|key:ctrl+a type:other.txt key:Return"
"pf-ext|return|key:Return"
"gd|escape|key:Escape" "gd|type-sub|type:\$FIX/sub key:Return" "gd|return|key:Return"
"gfl|escape|key:Escape" "gfl|type-path|type:\$FIX/a.txt key:Return"
)
if [ "${SCNARGS%% *}" = list ]; then for e in "${TABLE[@]}"; do echo "${e%%|*}"; done | sort -u | tr '\n' ' '; echo; exit 0; fi

# Fenstertitel je Szenario (Regex)
title_of() { case "$1" in
  mb-ok-noparent) echo '^mb-ok-np$';; mb-custom-noclose) echo '^mb-custom-nc$';; font) echo '^Choose Font$';;
  color) echo '^(color|Choose Color)$';; *) echo "^$1\$";; esac; }

start_probe() { # mode
  local mode=$1
  if pgrep -x racket >/dev/null; then echo "FEHLER: racket-Prozess laeuft noch -- abbrechen"; return 1; fi
  NOTES=$OUT/dialog-runtime.$mode.notes; [ -n "${KEEPLOG:-}" ] || : > "$NOTES"; CTL=$FUNC_TMP/ctl.$mode; rm -f "$CTL"; mkfifo "$CTL"; exec 7<>"$CTL"
  POSF=$OUT/dialog-runtime.$mode.pos; LOGF=$OUT/dialog-runtime.$mode.log; [ -n "${KEEPLOG:-}" ] || { : > "$POSF"; : > "$LOGF"; }
  export XDG_CONFIG_HOME=$(mktemp -d) PLTADDONDIR=$(mktemp -d)
  if [ "$mode" = qt ]; then
    (cd "$ROOT"; exec env PLT_QT=1 QT_PLUGIN_PATH="$QTP" "$RACKET" examples/dialog-runtime-probe.rkt "$FIX" <&7 >>"$POSF" 2>>"$LOGF") &
  else
    (cd "$ROOT"; exec "$RACKET" examples/dialog-runtime-probe.rkt "$FIX" <&7 >>"$POSF" 2>>"$LOGF") &
  fi
  PID=$!
  W=$(findwin '^drt-main$' 90) || { echo "  kein Hauptfenster ($mode)"; stop_probe; return 1; }
  sleep 2; activate "$W"; sleep 1
  echo P >&7; local i; for i in $(seq 1 40); do grep -q frame-ready "$POSF" && break; sleep 0.2; done
  return 0
}
stop_probe() { echo X >&7 2>/dev/null; local i; for i in 1 2 3 4 5 6; do kill -0 "$PID" 2>/dev/null || break; sleep 0.5; done
  kill -9 "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; exec 7>&-; sleep 1; }
waitfor() { # pattern file offset timeout-s
  local i; for ((i=0;i<$4*5;i++)); do tail -n +"$3" "$1" | grep -q "$2" && return 0; sleep 0.2; done; return 1; }

RUN() { # mode szenario tag actions...
  local mode=$1 scn=$2 tag=$3 acts=$4 off dw a x y w h
  off=$(($(wc -l < "$POSF")+1))
  echo "R $scn $tag" >&7
  if ! waitfor "$POSF" "^INFO $scn/$tag\$" "$off" 15; then echo "  INFO fehlt: $scn/$tag"; fi
  dw=$(findwin "$(title_of "$scn")" 3) || dw=""
  echo "  [$mode] $scn/$tag dialog-window=${dw:-none}"
  for a in $acts; do
    a=${a//\$FIX/$FIX}
    case "$a" in
      key:*) if [ -n "$dw" ]; then key "$dw" "${a#key:}"; fi; sleep 0.6;;
      type:*) if [ -n "$dw" ]; then typ "$dw" "${a#type:}"; fi; sleep 0.4;;
      wait:*) sleep "${a#wait:}";;
      btn:*) # Dialog-Button per Mausklick (Koordinaten aus der Probe)
        l=$(tail -n +"$off" "$POSF" | awk -v L="${a#btn:}" '$1=="BTN" && $2==L {print $3,$4,$5,$6; exit}')
        if [ -n "$l" ] && [ -n "$dw" ]; then set -- $l; click "$dw" $(($1+$3/2)) $(($2+$4/2)); else echo "  (btn ${a#btn:} nicht gefunden)"; fi; sleep 0.6;;
      modal) # Klick auf das (gesperrte) Hauptfenster, sofern der Dialog diese Stelle nicht verdeckt
        l=$(grep '^POS pre ' "$POSF" | tail -1); set -- $l; x=$(($3+$5/2)); y=$(($4+$6/2))
        eval "$(xdotool getwindowgeometry --shell "$dw" 2>/dev/null)"
        if [ -n "$dw" ] && [ "$x" -ge "$X" ] && [ "$x" -le $((X+WIDTH)) ] && [ "$y" -ge "$Y" ] && [ "$y" -le $((Y+HEIGHT)) ]; then
          # Dialog verdeckt den Knopf (grosser Qt-Dateidialog): nach rechts schieben, dann klicken
          xdotool windowmove "$dw" 1000 300; sleep 1
          eval "$(xdotool getwindowgeometry --shell "$dw" 2>/dev/null)"
          if [ "$x" -ge "$X" ] && [ "$x" -le $((X+WIDTH)) ] && [ "$y" -ge "$Y" ] && [ "$y" -le $((Y+HEIGHT)) ]; then
            echo "  (modal-click uebersprungen: Dialog ${X},${Y} ${WIDTH}x${HEIGHT} verdeckt den Knopf bei $x,$y)"; echo "$scn/$tag modal-click => skipped" >> "$NOTES"
          else xdotool mousemove "$x" "$y"; sleep 0.25; xdotool click 1; sleep 0.5; fi
        else xdotool mousemove "$x" "$y"; sleep 0.25; xdotool click 1; sleep 0.5; fi;;
    esac
  done
  if ! waitfor "$POSF" "^DONE $scn/$tag\$" "$off" 6; then
    # Dialog schliesst nicht (z. B. yes-no: Return/Escape tun nichts): Notiz + Rettung ueber den ersten Button, dann Escape
    echo "$scn/$tag rescued => #t" >> "$NOTES"; echo "  haengt: $scn/$tag -- Rettung per Button"
    l=$(tail -n +"$off" "$POSF" | awk '$1=="BTN" {print $3,$4,$5,$6; exit}')
    if [ -n "$l" ] && [ -n "$dw" ]; then set -- $l; click "$dw" $(($1+$3/2)) $(($2+$4/2)); fi
    waitfor "$POSF" "^DONE $scn/$tag\$" "$off" 6 || { [ -n "$dw" ] && key "$dw" Escape; }
    waitfor "$POSF" "^DONE $scn/$tag\$" "$off" 6 || { echo "  haengt endgueltig: $scn/$tag"; return 1; }
  fi
  sleep 0.3; return 0
}

sanity() { # Der Hauptfenster-Knopf muss ohne Dialog klickbar sein, sonst sagt "parent-clicks 0" im Modalitaetstest nichts
  local l n; l=$(grep '^POS pre ' "$POSF" | tail -1); set -- $l; activate "$W"
  xdotool mousemove $(($3+$5/2)) $(($4+$6/2)); sleep 0.3; xdotool click 1; sleep 0.5
  echo K >&7; sleep 0.6; n=$(grep '^CLICKS ' "$POSF" | tail -1)
  echo "  [sanity] $MODE: Klick auf pre ohne Dialog -> $n"; echo "sanity/pre-click clicks => ${n#CLICKS }" >> "$NOTES"
}
bad=0; ALLS=$(for e in "${TABLE[@]}"; do echo "${e%%|*}"; done | awk '!s[$0]++' | tr '\n' ' ')
SELS=${SCNARGS:-$ALLS}
for MODE in gtk qt; do
  case " $MODES " in *" $MODE "*) ;; *) continue;; esac
  start_probe "$MODE" || { bad=1; continue; }
  sanity
  for e in "${TABLE[@]}"; do
    IFS='|' read -r scn tag acts <<< "$e"
    case " $SELS " in *" $scn "*) ;; *) continue;; esac
    RUN "$MODE" "$scn" "$tag" "$acts" || { stop_probe; KEEPLOG=1 start_probe "$MODE" || break; }
  done
  stop_probe
  { grep -hE "^[a-z-]+/[a-z0-9-]+ " "$LOGF" "$NOTES"; grep -E 'EXN' "$LOGF" | grep -vE '^[a-z-]+/[a-z0-9-]+ '; } | sed "s#$FIX#FIX#g" | sort -s -k1,1 -k2,2 > "$OUT/dialog-runtime.$MODE"
done
if [ "$MODES" = "gtk qt" ]; then
  for m in gtk qt; do grep -v -F -f "$KNOWN" "$OUT/dialog-runtime.$m" > "$OUT/dialog-runtime.$m.f" 2>/dev/null || cp "$OUT/dialog-runtime.$m" "$OUT/dialog-runtime.$m.f"; done
  n=$(wc -l < "$OUT/dialog-runtime.gtk.f")
  if diff -q "$OUT/dialog-runtime.gtk.f" "$OUT/dialog-runtime.qt.f" >/dev/null && [ "$n" -ge 1 ]; then echo "OK    dialog-runtime ($n Zeilen)"
  else echo "DIFF  dialog-runtime ($n Zeilen gtk)"; diff "$OUT/dialog-runtime.gtk.f" "$OUT/dialog-runtime.qt.f" | sed 's/^/      /'; bad=1; fi
fi
rm -rf "$FIX"
exit $bad

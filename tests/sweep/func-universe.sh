#!/usr/bin/env bash
# Funktions-Sweep 10: 2htdp/universe (Netzwerk, nur 127.0.0.1).  Server (headless, files/universe-server.rkt)
# + zwei big-bang-Clients A/B (files/universe-client.rkt, echte GUI-Fenster).  Prueft per Marker-Dateien:
#  1 Beitritt/Startzustand, 2 Space in A -> Server -> Broadcast an A UND B, 3 Mausklick in B,
#  4 Tick-Rate (Zeit je 10 Ticks, soll ~1000 ms), 5 "q" in A (stop-with) -> Server meldet gone, B laeuft weiter,
#  6 Fenster B schliessen (alt+F4), 7 Server-Stop -> Client beendet sich?, Neustart + Reconnect,
#  8 keine Zombie-Prozesse (pgrep -x racket).  Tasten nur an verifiziert aktive Zielfenster.
SCENE=func-universe; source "$(dirname "$0")/func-lib.sh"
F=$HERE/files
nlines() { grep -c "$2" "$1" 2>/dev/null || true; }
waitfor() { # file regex timeout-s
  local i; for ((i=0;i<$3;i++)); do grep -q -- "$2" "$1" 2>/dev/null && return 0; sleep 1; done; return 1; }
spawn() { # mode logname args... -> setzt SPID
  local mode=$1 ln=$2; shift 2
  if [ "$mode" = qt ]; then (exec env PLT_QT=1 QT_PLUGIN_PATH="$QTP" "$RACKET" "$@" >"$OUT/$SCENE-$mode-$ln.log" 2>&1) &
  else (exec "$RACKET" "$@" >"$OUT/$SCENE-$mode-$ln.log" 2>&1) & fi
  SPID=$!
}
alive() { kill -0 "$1" 2>/dev/null; }
tickstat() { # file name skip-lines -> Zeit je 10 Ticks (ms)
  python3 - "$1" "$2" "$3" <<'PY'
import sys,re
ts=[]
for l in open(sys.argv[1]).readlines()[int(sys.argv[3]):]:
    m=re.match(r"\(%s tick (\d+) (\d+)\)"%sys.argv[2],l)
    if m: ts.append(int(m.group(2)))
d=[b-a for a,b in zip(ts,ts[1:])]
d2=sorted(d)
print("  %s: %d Intervalle je 10 Ticks, min/Median/max/mittel = %s ms (Soll ~1000)"%(sys.argv[2],len(d),
      "%d/%d/%d/%d"%(min(d),d2[len(d)//2],max(d),sum(d)/len(d)) if d else "n/a"))
PY
}
BASEPORT=17890
for mode in $MODES; do
  echo "== $mode =="
  BASEPORT=$((BASEPORT+1)); export SWEEP_PORT=$BASEPORT
  D=$FUNC_TMP/$mode; mkdir -p $D; export SWEEP_MARK=$D/cl SWEEP_MARK_SRV=$D/srv; rm -f $SWEEP_MARK $SWEEP_MARK_SRV
  export PLTADDONDIR=$(mktemp -d) XDG_CONFIG_HOME=$(mktemp -d)
  if pgrep -x racket >/dev/null; then echo "FEHLER: racket-Prozess laeuft noch"; exit 1; fi
  echo "  racket-Prozesse vorher: $(pgrep -xc racket)"
  spawn $mode srv "$F/universe-server.rkt"; SRV=$SPID
  waitfor $SWEEP_MARK_SRV 'server-start' 60 || { echo "  Server startet nicht"; kill -9 $SRV; continue; }
  spawn $mode A "$F/universe-client.rkt" A; PA=$SPID
  waitfor $SWEEP_MARK '(A recv 0)' 60 || echo "  A: kein Startzustand"
  spawn $mode B "$F/universe-client.rkt" B; PB=$SPID
  waitfor $SWEEP_MARK '(B recv 0)' 60 || echo "  B: kein Startzustand"
  wA=$(findwin '^A$' 30) || { echo "  Fenster A fehlt"; wA=""; }
  wB=$(findwin '^B$' 30) || { echo "  Fenster B fehlt"; wB=""; }
  echo "  Fenster A: ${wA:-?} '$(title ${wA:-0})'  B: ${wB:-?} '$(title ${wB:-0})'"
  [ -n "$wA" ] && xdotool windowmove $wA 50 80; [ -n "$wB" ] && xdotool windowmove $wB 500 80
  sleep 2
  echo "  1) Beitritt: Server-Log: $(tr '\n' ' ' < $SWEEP_MARK_SRV)"
  # 2) Space in A
  [ -n "$wA" ] && { key $wA space; sleep 2; }
  echo "  2) Space in A -> A recv: $(nlines $SWEEP_MARK '(A recv 1)') B recv: $(nlines $SWEEP_MARK '(B recv 1)') (erwartet je 1); Server msg: $(nlines $SWEEP_MARK_SRV "msg")"
  [ -n "$wA" ] && shot $wA a-after-space "$mode"; [ -n "$wB" ] && shot $wB b-after-space "$mode"
  # 3) Klick in B
  if [ -n "$wB" ]; then eval "$(xdotool getwindowgeometry --shell $wB)"; click $wB $((X+60)) $((Y+60)); sleep 2; fi
  echo "  3) Klick in B -> A recv 2: $(nlines $SWEEP_MARK '(A recv 2)') B recv 2: $(nlines $SWEEP_MARK '(B recv 2)') (erwartet je 1); B click-Marker: $(grep -c '(B click' $SWEEP_MARK)"
  [ -n "$wA" ] && shot $wA a-after-click "$mode"
  # 4) Tick-Rate: ~25 s ohne jede Automatisierung (kein xdotool/spectacle) sammeln
  mark4=$(wc -l < $SWEEP_MARK); sleep 25
  tickstat $SWEEP_MARK A $mark4; tickstat $SWEEP_MARK B $mark4
  # 5) q in A
  [ -n "$wA" ] && { key $wA q; sleep 3; }
  echo "  5) q in A: final: $(grep '(A final' $SWEEP_MARK | tr '\n' ' ') Prozess A lebt: $(alive $PA && echo ja || echo nein); Server: $(grep -c gone $SWEEP_MARK_SRV) gone"
  echo "     Fenster A noch da: $(xdotool search --name '^A$' 2>/dev/null | wc -l)"
  if [ -n "$wB" ]; then eval "$(xdotool getwindowgeometry --shell $wB)"; click $wB $((X+60)) $((Y+60)); sleep 2; fi
  echo "     B lebt weiter, empfaengt Klick-Broadcast (B recv 3): $(nlines $SWEEP_MARK '(B recv 3)')"
  # 6) Fenster B schliessen
  [ -n "$wB" ] && { key $wB alt+F4; sleep 4; }
  echo "  6) alt+F4 auf B: Prozess B lebt: $(alive $PB && echo ja || echo nein); B final/exit: $(grep -c '(B exit' $SWEEP_MARK); Server gone: $(grep -c gone $SWEEP_MARK_SRV)"
  alive $PB && { echo "     (alt+F4 nicht ausgeliefert/ausgefuehrt -- Automatisierungsartefakt moeglich; B per SIGTERM beenden)"; kill $PB; sleep 2; kill -9 $PB 2>/dev/null; }
  alive $PA && kill -9 $PA 2>/dev/null
  # 7) Server-Stop mit laufendem Client C, dann Neustart + Reconnect D
  spawn $mode C "$F/universe-client.rkt" C; PC=$SPID
  waitfor $SWEEP_MARK '(C recv' 60 || echo "  C: kein Startzustand"
  wC=$(findwin '^C$' 30) || wC=""
  [ -n "$wC" ] && { key $wC space; sleep 2; }
  echo "  7) C vor Server-Stop: recv $(grep -c '(C recv' $SWEEP_MARK)"
  kill $SRV; sleep 4
  echo "     Server tot: $(alive $SRV && echo nein || echo ja); Client C lebt: $(alive $PC && echo ja || echo nein); C final: $(grep -c '(C final' $SWEEP_MARK)"
  [ -n "$wC" ] && xdotool getwindowname $wC >/dev/null 2>&1 && shot $wC c-after-server-stop "$mode" 2>/dev/null || true
  alive $PC && { echo "     C haengt/lebt weiter nach Server-Stop"; kill $PC; sleep 2; kill -9 $PC 2>/dev/null; }
  alive $SRV && kill -9 $SRV
  spawn $mode srv2 "$F/universe-server.rkt"; SRV=$SPID
  waitfor $SWEEP_MARK_SRV 'server-start' 60 >/dev/null; sleep 3
  spawn $mode D "$F/universe-client.rkt" D; PD=$SPID
  waitfor $SWEEP_MARK '(D recv 0)' 60 && echo "     Reconnect: D empfaengt Startzustand 0 vom neuen Server" || echo "     Reconnect: D ohne Startzustand"
  wD=$(findwin '^D$' 30) || wD=""
  [ -n "$wD" ] && { key $wD space; sleep 2; }
  echo "     D nach Space: recv 1: $(nlines $SWEEP_MARK '(D recv 1)')"
  kill $PD $SRV 2>/dev/null; sleep 3; kill -9 $PD $SRV 2>/dev/null; sleep 1
  # 8) Zombies
  echo "  8) racket-Prozesse nachher: $(pgrep -xc racket) $(pgrep -x racket | tr '\n' ' ')"
  kill -9 $SRV $PA $PB $PC $PD 2>/dev/null; sleep 1
  cp $SWEEP_MARK "$OUT/$SCENE-$mode-client.mark"; cp $SWEEP_MARK_SRV "$OUT/$SCENE-$mode-server.mark"
  echo "  Fehlerausgaben (stderr-Logs):"; for l in "$OUT/$SCENE-$mode"-*.log; do echo "    $(basename $l): $(grep -ci 'error\|exception\|terminated' $l) Treffer"; done
done
sidebyside a-after-space b-after-space a-after-click c-after-server-stop

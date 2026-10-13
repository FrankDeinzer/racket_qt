#!/usr/bin/env bash
# Echte Eingabe an Steuerelemente (docs/COVERAGE.md, HACKING §82): examples/input-matrix-probe.rkt zeigt je Sektion
# ein Fenster, dieses Skript speist echte X11-Eingaben (xdotool) ein, die Probe protokolliert, was Racket sieht
# ("<sektion> <ereignis> => <wert>" je Schritt + Zustand).  Nativ (gtk) und PLT_QT=1 werden gediffed.
# Tasten gehen nur an ein verifiziert aktives Testfenster (nie Terminal/Konsole, func-lib.sh); Mausklicks nur auf das Testfenster.
# Aufruf: tests/sweep/input-controls.sh [gtk|qt|both] [abschnitt ...]     (ohne Abschnitte: alle; "list" nennt sie)
# Ausgabe: tests/sweep/out/input-controls-<sektion>.{gtk,qt}; Exit 1 bei Abweichung.
# Bekannte, begruendete Abweichungen: tests/sweep/input-controls-known.txt (Zeilen werden vor dem Diff entfernt,
# Format: ganze Zeile "<sektion> <schluessel> =>" als Praefix -- grep -F).
# Nur Linux/X11, braucht xdotool (+ spectacle nur fuer das Kalibrierungs-Debugging).
MODEARG=${1:-both}; [ $# -gt 0 ] && shift
SECARGS=$*
ALL="button check-box radio-box choice slider list-single list-multiple list-extended list-columns text-field combo-field tab-panel tab-order menu popup canvas"
[ "${SECARGS%% *}" = list ] && { echo $ALL; exit 0; }
SECS=${SECARGS:-$ALL}
set -- "$MODEARG"; SCENE=input-controls; source "$(dirname "$0")/func-lib.sh"
ROOT=$(cd "$HERE/../.." && pwd); KNOWN=$HERE/input-controls-known.txt

# ---------- Probe-Steuerung ----------
start_probe() { # sektion mode
  SECT=$1; local mode=$2
  if pgrep -x racket >/dev/null; then echo "FEHLER: racket-Prozess laeuft noch -- abbrechen"; return 1; fi
  CTL=$FUNC_TMP/ctl.$SECT.$mode; rm -f "$CTL"; mkfifo "$CTL"; exec 7<>"$CTL"
  POSF=$OUT/input-controls-$SECT.$mode.pos; LOGF=$OUT/input-controls-$SECT.$mode.log; : > "$POSF"; : > "$LOGF"
  export XDG_CONFIG_HOME=$(mktemp -d) PLTADDONDIR=$(mktemp -d); QN=0
  if [ "$mode" = qt ]; then
    (cd "$ROOT"; exec env PLT_QT=1 QT_PLUGIN_PATH="$QTP" "$RACKET" examples/input-matrix-probe.rkt "$SECT" <&7 >"$POSF" 2>"$LOGF") &
  else
    (cd "$ROOT"; exec "$RACKET" examples/input-matrix-probe.rkt "$SECT" <&7 >"$POSF" 2>"$LOGF") &
  fi
  PID=$!
  W=$(findwin "^imx-$SECT\$" 90) || { echo "  kein Fenster ($SECT/$mode)"; stop_probe; return 1; }
  sleep 2; activate "$W"; sleep 1
  echo P >&7; local i; for i in $(seq 1 40); do grep -q frame-ready "$POSF" && break; sleep 0.2; done
  return 0
}
stop_probe() { echo X >&7 2>/dev/null; local i; for i in 1 2 3 4 5 6; do kill -0 "$PID" 2>/dev/null || break; sleep 0.5; done
  kill -9 "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; exec 7>&-; sleep 1; }
send() { echo "$*" >&7; }
step() { sleep 0.5; send "S $1"; sleep 0.35; }
# Kalibrierung: Zustand abfragen
qstate() { local n=$(date +%s%N); send "Q $n"; local i l; for i in $(seq 1 30); do l=$(grep "^Q $n " "$POSF" | head -1); [ -n "$l" ] && { echo "$l"; return; }; sleep 0.1; done; echo ""; }
repos() { send P; sleep 0.6; }                      # Positionen neu einlesen (Fenster kann sich verschoben haben)
pos() { local l; l=$(grep "^POS $1 " "$POSF" | tail -1); set -- $l; PX=$3; PY=$4; PW=$5; PH=$6; }
# Mausaktionen (absolute Koordinaten); activate nur wenn kein Popup offen sein darf (raw = ohne)
active_ok() { is_active "$W" && not_terminal "$W" >/dev/null; }
raw_click() { # x y [button]  -- ohne windowactivate (Popups!)
  xdotool mousemove "$1" "$2"; sleep 0.25; xdotool click "${3:-1}"; }
wclick() { # x y [button] -- aktiviert das Testfenster zuerst
  activate "$W"; if active_ok; then raw_click "$@"; else echo "  (click uebersprungen)"; fi; }
cclick() { pos "$1"; wclick $((PX + PW * ${2:-50} / 100)) $((PY + PH * ${3:-50} / 100)) "${4:-1}"; }   # Prozent der Steuerelementflaeche
dclick() { activate "$W"; if active_ok; then xdotool mousemove "$1" "$2"; sleep 0.25; xdotool click --repeat 2 --delay 90 1; fi; }
mclick() { # modifier x y  -- Strg-/Shift-Klick, Modifier immer wieder loslassen
  activate "$W"; if active_ok; then xdotool mousemove "$2" "$3"; sleep 0.25; xdotool keydown "$1"; sleep 0.1; xdotool click 1; sleep 0.1; xdotool keyup "$1"; fi; }
drag() { # x1 y1 x2 y2 -- mit Zwischenschritten
  activate "$W"; if active_ok; then
    xdotool mousemove "$1" "$2"; sleep 0.25; xdotool mousedown 1; sleep 0.2
    local n=6 i; for i in $(seq 1 $n); do xdotool mousemove $(( $1 + ($3-$1)*i/n )) $(( $2 + ($4-$2)*i/n )); sleep 0.08; done
    sleep 0.2; xdotool mouseup 1; fi; }
K() { key "$W" "$@"; }
TY() { typ "$W" "$@"; }
PK() { safe_key "$@"; }   # Tasten bei offenem Popup (Fenster darf nicht neu aktiviert werden)
# Zeilen eines Listenfelds: kalibrieren (Zeile 1 und 2 beginnen bei o1/o2 Pixel unter der Oberkante)
calib_rows() { # name
  pos "$1"; local x=$((PX + PW/2)) off sel o1="" o2="" r
  for off in $(seq 3 3 90); do
    raw_click $x $((PY+off)); r=$(qstate); sel=$(echo "$r" | sed -n 's/.*selections (\([0-9]*\).*/\1/p')
    [ "$sel" = 1 ] && [ -z "$o1" ] && o1=$off
    [ "$sel" = 2 ] && { o2=$off; break; }
    send Z; sleep 0.15
  done
  send Z; sleep 0.3
  [ -n "$o1" ] && [ -n "$o2" ] || { echo "  Kalibrierung fehlgeschlagen ($1 o1=$o1 o2=$o2)"; RH=24; R1=$o1; R1=${R1:-28}; return; }
  RH=$((o2 - o1)); R1=$o1; echo "  [kalibriert $1: Zeile1 ab $o1, Zeilenhoehe $RH]" >&2
}
rowy() { echo $(( PY + R1 + RH*($1-1) + RH/2 )); }     # y-Mitte von Zeile i (i>=1: R1 + (i-1)*RH + RH/2; Zeile 0: R1 - RH/2)
rowy0() { echo $(( PY + R1 - RH/2 )); }
rowc() { [ "$1" = 0 ] && rowy0 || rowy "$1"; }
rowx() { echo $((PX + 30)); }

# ---------- Sektionen ----------
sec_button() {
  step init
  cclick b1; step click-b1
  K space; step key-space
  K Return; step key-return
  cclick b2; step click-disabled-b2
  K Tab; step tab-after-b1
  K space; step space-on-b3
  K shift+Tab; step shift-tab
  K space; step space-on-b1
  # Druck, wegziehen, loslassen -> kein Klick
  pos b1; drag $((PX+PW/2)) $((PY+PH/2)) $((PX+PW/2+120)) $((PY+PH/2+80)); step press-drag-away-release
  cclick b1 50 50 3; step right-click-b1
}
sec_check_box() {
  step init
  cclick c1 20; step click-c1
  K space; step space-c1
  cclick c1 20; step click-c1-again
  cclick c2 20; step click-disabled-c2
  K Tab; step tab-after-c1
  K space; step space-on-focused
  cclick c3 20; step click-c3
}
sec_radio_box() {
  step init
  pos radio; local x=$((PX+14)) h=$PH
  wclick $x $((PY + h*5/6)); step click-item2
  wclick $x $((PY + h/6)); step click-item0
  K Tab; step tab-away
  K shift+Tab; step shift-tab-back
  # Pfeiltasten zuletzt: gtk-Racket nimmt sie fuer die Fokus-Traversierung (Auswahl bleibt), Qt aendert die Auswahl (known)
  K Down; step key-down
  K Down; step key-down-2
  K Up; step key-up
  K Right; step key-right
  K Left; step key-left
}
sec_choice() {
  step init
  cclick pre; K Tab; step tab-to-choice
  K Down; step key-down-closed
  K Up; step key-up-closed
  K Down; K Down; step key-down-x2
  send Z; sleep 0.3
  # Popup per Klick oeffnen, Escape
  cclick choice; sleep 0.8; PK Escape; step click-open-escape
  # Popup oeffnen, per Tastatur waehlen
  cclick choice; sleep 0.8; PK Down; PK Down; PK Return; sleep 0.5; step popup-keys-down2-return
  # Popup oeffnen, per Klick auf einen Eintrag (Zeile relativ zum Steuerelement)
  pos choice; local cy=$((PY+PH/2))
  wclick $((PX+PW/2)) $cy; sleep 0.8
  CHOICE_POPUP_SHOT=1 popup_shot choice-popup
  raw_click $((PX+PW/2)) $((cy + ${CH_ROW:-25})); sleep 0.6; step popup-click-row
  # Aufklappen mit alt+Down / F4
  K alt+Down; sleep 0.8; PK Escape; step alt-down-escape
}
popup_shot() { [ -n "${POPUP_SHOTS:-}" ] && spectacle -b -n -f -o "$OUT/$SCENE-$SECT-$1-$MODE.png" >/dev/null 2>&1; true; }
sec_slider() {
  step init
  pos slider; local l=$PX r=$((PX+PW)) y=$((PY+PH/2))
  cclick pre; K Tab; step tab-to-slider
  wclick $((r - 20)) $y; step click-track-near-right-end
  K Home; step reset-home
  # Ziehen: am Knauf (ganz links, Wert 0) anfassen und ueber das rechte Ende hinaus ziehen, dann umgekehrt
  drag $((l+8)) $y $((r+60)) $y; step drag-beyond-right-end
  drag $((r-8)) $y $((l-60)) $y; step drag-beyond-left-end
  K Home; step home-before-keys
  K Right; step key-right
  K Left; K Left; step key-left-x2
  K Up; step key-up
  K Down; step key-down
  K Prior; step page-up
  K Next; step page-down
  K End; step key-end
}
sec_list_any() { # Zeilenklick-Sequenz (Argument: single|multiple|extended)
  step init
  calib_rows lb; pos lb; local x; x=$(rowx)
  wclick $x $(rowc 2); step click-row2
  wclick $x $(rowc 5); step click-row5
  if [ "${1:-}" = extended ]; then
    # 'extended: Klick schaltet um (win32-Semantik, gtk kennt den Modus nicht) -- nur die Eckpunkte, Abweichung ist known
    wclick $x $(rowc 5); step click-row5-again
    wclick $x $(rowc 1); step click-row1
    dclick $x $(rowc 4); sleep 0.4; step double-click-row4
    cclick pre; step click-pre-focus-out
    return
  fi
  K Down; step key-down
  K Up; step key-up
  K Up; step key-up-2
  K End; step key-end
  K Home; step key-home
  mclick ctrl $x $(rowc 1); step ctrl-click-row1
  mclick ctrl $x $(rowc 3); step ctrl-click-row3
  mclick ctrl $x $(rowc 1); step ctrl-click-row1-again
  wclick $x $(rowc 2); step resync-click-row2
  mclick shift $x $(rowc 5); step shift-click-row5
  wclick $x $(rowc 3); step resync-click-row3
  K shift+Down; step shift-down
  K shift+Up; step shift-up
  wclick $x $(rowc 0); step click-row0
  K space; step key-space
  K Return; step key-return
  dclick $x $(rowc 4); sleep 0.4; step double-click-row4
  cclick pre; step click-pre-focus-out
}
sec_list_single() { sec_list_any single; }
sec_list_multiple() { sec_list_any multiple; }
sec_list_extended() { sec_list_any extended; }
sec_list_columns() {
  step init
  pos lb; local hy=$((PY+9))
  wclick $((PX + PW/6)) $hy; step header-click-colA
  wclick $((PX + PW*5/6)) $hy; step header-click-colB
  wclick $((PX + PW/6)) $hy; step header-click-colA-again
  calib_rows lb; pos lb; local x; x=$(rowx)
  wclick $x $(rowc 2); step click-row2
  K Down; step key-down
  dclick $x $(rowc 4); sleep 0.4; step double-click-row4
  cclick pre; step click-pre
}
sec_text_field() {
  step init
  cclick pre; K Tab; TY m; step tab-to-tf1-type-m
  K ctrl+a; K BackSpace; step clear
  cclick tf1; step click-tf1
  TY abc; step type-abc
  K BackSpace; step backspace
  K Return; step return-single-line
  K ctrl+a; TY Z; step ctrl-a-type-Z
  K Home; K Delete; step home-delete
  K Tab; step tab-to-tf2
  TY xy; K Return; TY z; step multi-type-return-type
  K shift+Tab; step shift-tab-to-tf1
  cclick tf2; K ctrl+a; K BackSpace; step multi-clear
}
sec_combo_field() {
  step init
  cclick pre; K Tab; TY q; step tab-to-combo-type-q
  K ctrl+a; K BackSpace; step clear
  cclick combo 30; TY ab; step type-ab
  K BackSpace; step backspace
  K Return; step return
  # Dropdown-Pfeil (rechte Kante): Popup oeffnen, Escape
  pos combo; wclick $((PX+PW-8)) $((PY+PH/2)); sleep 0.8; PK Escape; step arrow-escape
  wclick $((PX+PW-8)) $((PY+PH/2)); sleep 0.8; PK Down; PK Down; PK Return; sleep 0.5; step arrow-keys-down2-return
  wclick $((PX+PW-8)) $((PY+PH/2)); sleep 0.8; popup_shot combo-popup
  raw_click $((PX+40)) $((PY+PH + ${CF_ROW:-14})); sleep 0.6; step arrow-click-row
}
sec_tab_panel() {
  step init
  pos tabs; local y=$((PY-14)) x o1="" o2="" r sel
  for x in $(seq 6 6 300); do
    raw_click $((PX+x)) $y; r=$(qstate); sel=$(echo "$r" | sed -n 's/.*selection \([0-9]*\).*/\1/p')
    [ "$sel" = 1 ] && [ -z "$o1" ] && o1=$x
    [ "$sel" = 2 ] && { o2=$x; break; }
    send Z; sleep 0.15
  done
  send Z; sleep 0.3
  if [ -z "$o1" ] || [ -z "$o2" ]; then echo "  Tab-Kalibrierung fehlgeschlagen o1=$o1 o2=$o2"; o1=${o1:-80}; o2=${o2:-160}; fi
  local W2=$((o2-o1)); echo "  [kalibriert tabs: Tab1 ab $o1, Breite $W2]" >&2
  step init-after-calib
  wclick $((PX + o1 + W2/2)) $y; step click-tab1
  wclick $((PX + o2 + W2/2)) $y; step click-tab2
  wclick $((PX + o1 - W2/2)) $y; step click-tab0
  # Fokus nach Klick auf den Tab-Reiter, dann Tab/Shift+Tab ueber die Kinder
  K Tab; step tab-1
  K Tab; step tab-2
  K Tab; step tab-3
  K shift+Tab; step shift-tab-1
  # Tastatur-Umschalten auf der Tab-Leiste
  wclick $((PX + o1 - W2/2)) $y; K Right; step key-right-on-tabbar
  K Right; step key-right-2
  K Left; step key-left
  K ctrl+Next; step ctrl-pagedown
  K ctrl+Prior; step ctrl-pageup
  # Klick in ein Kind (Textfeld) + Tippen
  cclick p0t; TY k; step click-child-type
}
sec_tab_order() {
  step init
  cclick b0; step click-b0
  local i; for i in 1 2 3 4 5 6 7 8 9 10 11 12 13; do K Tab; step tab-fwd-$i; done
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13; do K shift+Tab; step tab-back-$i; done
}
sec_menu() {
  step init
  # Fenstergeometrie: Menueleiste liegt oberhalb des Client-Bereichs; Titel "File" ~ 20 px, "Edit" ~ 70 px
  eval "$(xdotool getwindowgeometry --shell $W)"; local wx=$X wy=$Y
  K ctrl+a; step accel-ctrl-a
  K ctrl+shift+d; step accel-ctrl-shift-d
  # Menue per Klick oeffnen, Escape
  raw_click $((wx + ${MB_X:-22})) $((wy + ${MB_Y:-10})); sleep 0.7; popup_shot menu-open; PK Escape; sleep 0.4; step open-escape
  # Menue oeffnen, Eintrag Alpha (erste Zeile) anklicken
  raw_click $((wx + ${MB_X:-22})) $((wy + ${MB_Y:-10})); sleep 0.7
  raw_click $((wx + ${MB_X:-22} + 20)) $((wy + ${MB_Y:-10} + ${MI_ROW1:-24})); sleep 0.6; step click-alpha
  # Beta (zweite Zeile, checkable) zweimal
  raw_click $((wx + ${MB_X:-22})) $((wy + ${MB_Y:-10})); sleep 0.7
  raw_click $((wx + ${MB_X:-22} + 20)) $((wy + ${MB_Y:-10} + ${MI_ROW1:-24} + ${MI_ROWH:-24})); sleep 0.6; step click-beta
  # per Tastatur: alt+f, Down (Alpha), Down (Beta), Return
  K alt+f; sleep 0.6; PK Down; PK Down; PK Return; sleep 0.6; step alt-f-down-down-return
  # alt+f, Escape
  K alt+f; sleep 0.6; PK Escape; sleep 0.4; step alt-f-escape
  # Klick ausserhalb (auf die Schaltflaeche) bei offenem Menue
  raw_click $((wx + ${MB_X:-22})) $((wy + ${MB_Y:-10})); sleep 0.7; cclick btn; sleep 0.5; step click-outside-closes
  # Menue-Aktion mit deaktiviertem Eintrag (Eps, dritte Zeile)
  raw_click $((wx + ${MB_X:-22})) $((wy + ${MB_Y:-10})); sleep 0.7
  raw_click $((wx + ${MB_X:-22} + 20)) $((wy + ${MB_Y:-10} + ${MI_ROW1:-24} + 2*${MI_ROWH:-24})); sleep 0.5; PK Escape; sleep 0.3; step click-disabled-eps
}
sec_popup() {
  step init
  pos canvas; local cx=$((PX+PW/2)) cy=$((PY+PH/2))
  wclick $cx $cy 3; sleep 0.8; popup_shot popup-open; PK Escape; sleep 0.5; step rclick-escape
  wclick $cx $cy 3; sleep 0.8; PK Down; PK Return; sleep 0.6; step rclick-down-return
  wclick $cx $cy 3; sleep 0.8; PK Down; PK Down; PK Return; sleep 0.6; step rclick-down2-return-check
  wclick $cx $cy 3; sleep 0.8; raw_click $((cx + 4 + ${PM_X:-25})) $((cy + ${PM_ROW1:-14})); sleep 0.6; step rclick-click-row1
  wclick $cx $cy 3; sleep 0.8; raw_click $((cx + 4 + ${PM_X:-25})) $((cy + ${PM_ROW1:-14} + ${PM_ROWH:-24})); sleep 0.6; step rclick-click-row2
  wclick $cx $cy 3; sleep 0.8; raw_click $((cx + 250)) $((cy + 100)); sleep 0.6; step rclick-click-outside
  wclick $cx $cy 3; sleep 0.8; raw_click $((cx + 4 + 25)) $((cy + ${PM_ROW1:-14} + 2*${PM_ROWH:-24})); sleep 0.6; step rclick-click-row3
}
sec_canvas() {
  step init
  cclick pre; step click-pre
  pos canvas; local cx=$((PX+PW/2)) cy=$((PY+PH/2))
  xdotool mousemove $((PX-40)) $((PY+PH/2)); sleep 0.3
  xdotool mousemove $cx $cy; sleep 0.3; step enter-canvas
  wclick $cx $cy; step left-click
  wclick $cx $cy 3; step right-click
  wclick $cx $cy 2; step middle-click
  dclick $cx $cy; step double-click
  drag $((cx-40)) $((cy-20)) $((cx+50)) $((cy+30)); step drag-left
  xdotool mousemove $((PX-60)) $cy; sleep 0.4; step leave-canvas
  xdotool mousemove $cx $cy; sleep 0.3; xdotool click 4; sleep 0.2; xdotool click 4; sleep 0.2; xdotool click 5; step wheel-up2-down1
  K a; K shift+a; K 1; K space; step keys-chars
  K Left; K Right; K Up; K Down; K Home; K End; K Prior; K Next; step keys-arrows
  K Return; K BackSpace; K Delete; K Tab; K Escape; step keys-special
  K ctrl+x; K ctrl+shift+z; K alt+x; K shift+Left; step keys-chords
  K ctrl+alt+x; step keys-ctrl-alt-x
  K F5; K F1; K ctrl+F5; step keys-function
  cclick post; step click-post-focus-out
  cclick canvas; step click-canvas-focus-in
}

# ---------- Lauf ----------
collect() { grep "^$SECT " "$LOGF" > "$OUT/input-controls-$SECT.$MODE"; grep -E 'EXN|CMD-EXN' "$LOGF" | grep -v "^$SECT " >> "$OUT/input-controls-$SECT.$MODE"; }
bad=0
for s in $SECS; do
  for MODE in gtk qt; do
    case " $MODES " in *" $MODE "*) ;; *) continue;; esac
    if start_probe "$s" "$MODE"; then "sec_${s//-/_}"; sleep 0.5; send "S end"; sleep 0.4; fi
    stop_probe; collect
  done
  if [ "$MODES" != "gtk qt" ]; then echo "DONE  $s (nur $MODES)"; continue; fi
  for m in gtk qt; do grep -v -F -f "$KNOWN" "$OUT/input-controls-$s.$m" > "$OUT/input-controls-$s.$m.f" 2>/dev/null || true; done
  n=$(wc -l < "$OUT/input-controls-$s.gtk.f")
  if diff -q "$OUT/input-controls-$s.gtk.f" "$OUT/input-controls-$s.qt.f" >/dev/null && [ "$n" -ge 1 ]; then echo "OK    $s ($n Zeilen)"
  else echo "DIFF  $s ($n Zeilen gtk)"; diff "$OUT/input-controls-$s.gtk.f" "$OUT/input-controls-$s.qt.f" | sed 's/^/      /'; bad=1; fi
done
exit $bad

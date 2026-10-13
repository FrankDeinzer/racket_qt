#!/usr/bin/env bash
# §33.7 / §76.2: Tab-2-Zeilennummern-Defekt (editor-canvas%).  Sequenz: Datei one.rkt -> F5 (Run) ->
# Ctrl+T (neuer Tab) -> Ctrl+O + getippter Pfad (tab2.rkt, 16 Zeilen ";; LINEnn ...") -> Aufnahme -> OCR:
# je Zeile muss die Gutter-Nummer == nn sein.  Tasten nur mit Active-Window-Check (func-lib.sh).
# Aufruf: tests/sweep/func-tab2lines.sh [gtk|qt|both] [Läufe]   (Qt mit PLT_QT_SCROLL_DEBUG=1, Log je Lauf)
SCENE=func-tab2; source "$(dirname "$0")/func-lib.sh"
RUNS=${2:-1}; RES="$OUT/tab2-results-$(date +%s).txt"
classify() { # png -> "PASS n=..", "BAD ..", "UNCLEAR .."
  python3 - "$1" <<'PY'
import sys,re,subprocess
from PIL import Image
im=Image.open(sys.argv[1]).convert('L'); w,h=im.size
im=im.crop((0,int(h*0.12),int(w*0.6),int(h*0.75))).resize((int(w*0.6)*2,int(h*0.63)*2)).point(lambda p: 0 if p<190 else 255)
im.save('/tmp/.tab2crop.png')
t=subprocess.run(['tesseract','/tmp/.tab2crop.png','-','--psm','6'],capture_output=True,text=True).stdout
ok=bad=0;seen=0
for l in t.translate(str.maketrans('@OS','005')).splitlines():
    m=re.search(r'LINE\s*(\d\d)',l)
    if not m: continue
    seen+=1; k=int(m.group(1))
    g=re.match(r'\s*[|\[]?\s*(\d+)\s',l)
    if g and int(g.group(1))==k: ok+=1
    elif g: bad+=1
print(('PASS' if ok>=6 and bad==0 else 'BAD' if bad>=2 or seen==0 else 'UNCLEAR'),f'lines_seen={seen} num_ok={ok} num_wrong={bad}')
PY
}
for mode in $MODES; do
  for ((r=1;r<=RUNS;r++)); do
    D=$FUNC_TMP/$mode-$r; mkdir -p $D; cp "$HERE/files/a.rkt" $D/one.rkt; cp "$HERE/files/tab2.rkt" $D/tab2.rkt
    [ "$mode" = qt ] && export PLT_QT_SCROLL_DEBUG=1 || unset PLT_QT_SCROLL_DEBUG
    start_dr $mode -l drracket $D/one.rkt || exit 1
    main=$(findwin 'one\.rkt.*DrRacket$' 90) || { echo "$mode#$r NOWIN" | tee -a $RES; stop_dr; continue; }
    sleep 8
    key $main F5; sleep 5
    key $main ctrl+t; sleep 2
    key $main ctrl+o; sleep 3
    dlg=$(findwin '^(Open|Select|Choose|Racket: Open)' 8) || { echo "$mode#$r NODIALOG" | tee -a $RES; stop_dr; continue; }
    typ $dlg "$D/tab2.rkt"; sleep 1; key $dlg Return; sleep 4
    main2=$(xdotool search --name 'tab2\.rkt.*DrRacket' | tail -1); [ -n "$main2" ] || main2=$main
    activate "$main2"; sleep 1; shot $main2 r$r "$mode"
    res=$(classify "$OUT/$SCENE-r$r-$mode.png")
    cp "$OUT/$SCENE-$mode.log" "$OUT/$SCENE-r$r-$mode.log" 2>/dev/null
    echo "$mode#$r $res title='$(title $main2)'" | tee -a $RES
    stop_dr
  done
done
echo "Ergebnisse: $RES"

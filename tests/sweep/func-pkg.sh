#!/usr/bin/env bash
# Funktions-Sweep 12: Package Manager (NUR LESEN/ANZEIGEN; nie Update/Remove/Install klicken -- Regel 9).
# racket -l- pkg/gui: Tab "Currently Installed", Filter tippen ("gui" -> "N/M match", "zzzzq" -> "0/M match", leeren),
# Zeile auswaehlen (Buttons Update/Remove werden aktiv, aber NICHT geklickt), Header-Klick-Sortierung,
# Tab Settings.  Vergleich gtk == Qt per Treffer-Zaehler (OCR), Fensterliste (kein Zusatzfenster) und Aufnahmen.
# Aufruf: tests/sweep/func-pkg.sh [gtk|qt|both]
SCENE=func-pkg; source "$(dirname "$0")/func-lib.sh"
matchtxt() { # win name mode -> OCR des Zaehlers "N/M match"
  shot $1 $2 $3; tesseract "$OUT/$SCENE-$2-$3.png" - 2>/dev/null | grep -oE '[0-9]+ ?/ ?[0-9]+ match' | head -1
}
for mode in $MODES; do
  echo "== $mode =="
  if [ $mode = qt ]; then TX=179 TY=37 FX=190 FY=63 RX=60 RY=149 HX=165 HY=109; else TX=171 TY=44 FX=350 FY=73 RX=100 RY=192 HX=100 HY=132; fi
  start_dr $mode -l- pkg/gui || exit 1
  main=$(findwin 'Package Manager|Racket Package' 60) || { echo "kein Fenster"; stop_dr; continue; }
  sleep 8; eval "$(xdotool getwindowgeometry --shell $main)"; echo "  Titel '$(title $main)' ${WIDTH}x${HEIGHT}"
  click $main $((X+TX)) $((Y+TY)); sleep 8
  echo "  Zaehler initial: $(matchtxt $main cur $mode)"
  click $main $((X+FX)) $((Y+FY)); typ $main "gui"; sleep 3
  echo "  Filter 'gui': $(matchtxt $main filter-gui $mode)"
  key $main ctrl+a; typ $main "zzzzq"; sleep 3
  echo "  Filter 'zzzzq': $(matchtxt $main filter-none $mode)"
  key $main ctrl+a; key $main BackSpace; sleep 3
  echo "  Filter leer: $(matchtxt $main filter-clear $mode)"
  click $main $((X+RX)) $((Y+RY)); sleep 2; shot $main select $mode
  click $main $((X+HX)) $((Y+HY)); sleep 3; shot $main sort $mode
  echo "  Fenster: $(listwins | tr '\n' ';')"
  stop_dr
done
sidebyside cur filter-gui filter-none select sort

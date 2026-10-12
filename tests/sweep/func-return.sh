#!/usr/bin/env bash
# Funktions-Sweep: Return in DrRackets Dialogen (Preferences, Choose Language, Configure Search,
# "Save changes?"-Rueckfrage), gtk vs Qt.  Protokolliert je Szene, ob der Dialog nach Return noch da ist
# (und bei der Rueckfrage: Datei gespeichert / Fenster weg).  Tasten nur an verifiziert aktive Fenster.
# Aufruf: func-return.sh [gtk|qt|both]
SCENE=func-return; source "$(dirname "$0")/func-lib.sh"
present() { xdotool search --onlyvisible --name "$1" 2>/dev/null | head -1; }
lang_dialog() { # main -> oeffnet Choose Language ueber das Statuszeilen-Popup, liefert Fensterid
  local main=$1; eval "$(xdotool getwindowgeometry --shell $main)"
  click $main $((X+120)) $((Y+HEIGHT-14)); sleep 2; safe_key Down Down; sleep 1; safe_key Return; sleep 4
  findwin '^Choose Language' 8
}
for mode in $MODES; do
  echo "== $mode =="
  D=$FUNC_TMP/$mode; mkdir -p $D; cp "$HERE/files/a.rkt" $D/one.rkt; cp "$HERE/files/a.rkt" $D/two.rkt; before=$(md5sum < $D/one.rkt)
  start_dr $mode -l drracket $D/one.rkt || exit 1
  main=$(findwin 'one\.rkt.*DrRacket' 90) || { echo "kein Fenster"; stop_dr; continue; }
  sleep 10; activate $main; eval "$(xdotool getwindowgeometry --shell $main)"; MX=$X; MY=$Y; MH=$HEIGHT
  # 1. Preferences: Return im Anfangszustand
  key $main ctrl+semicolon; if dlg=$(findwin '^Preferences$' 10); then sleep 3; activate $dlg
    key $dlg Return; sleep 2; echo "  prefs Return (Anfangsfokus): Dialog $([ -n "$(present '^Preferences$')" ] && echo OFFEN || echo geschlossen)"
    [ -n "$(present '^Preferences$')" ] && { key $(present '^Preferences$') Escape; sleep 1; }
  else echo "  Preferences nicht erschienen"; fi
  # 2. Choose Language: Return im Anfangszustand; Tab + Return; Escape
  activate $main
  if dlg=$(lang_dialog $main); then sleep 2; activate $dlg
    key $dlg Return; sleep 2; echo "  lang Return (Anfangsfokus): Dialog $([ -n "$(present '^Choose Language')" ] && echo OFFEN || echo geschlossen)"
    d2=$(present '^Choose Language')
    if [ -n "$d2" ]; then key $d2 Escape; sleep 1; fi
  else echo "  Choose Language nicht erschienen"; safe_key Escape; fi
  activate $main
  if dlg=$(lang_dialog $main); then sleep 2; activate $dlg
    key $dlg Tab Return; sleep 2; echo "  lang Tab+Return: Dialog $([ -n "$(present '^Choose Language')" ] && echo OFFEN || echo geschlossen)"; shot $dlg lang-tab-return "$mode"
    d2=$(present '^Choose Language'); [ -n "$d2" ] && { key $d2 Escape; sleep 1; }
  fi
  # 3. Configure Search (Search in Files): Return im Textfeld
  activate $main; click $main $((MX+20)) $((MY+14)); sleep 1; safe_key Up Up Up; sleep 1; safe_key Return; sleep 3
  if dlg=$(findwin '^Configure Search$' 8); then sleep 2; activate $dlg
    key $dlg Return; sleep 3; echo "  search Return: Dialog $([ -n "$(present '^Configure Search$')" ] && echo OFFEN || echo geschlossen), Fenster: $(for w in $(xdotool search --onlyvisible --name . 2>/dev/null); do case "$(title $w)" in *Konsole*|*Plasma*|"") ;; *) printf "'%s' " "$(title $w)";; esac; done)"
    d2=$(present '^Configure Search$'); [ -n "$d2" ] && { key $d2 Escape; sleep 1; }
  else echo "  Configure Search nicht erschienen"; safe_key Escape; fi
  # 4. Rueckfrage beim Schliessen: Return = Default-Button (Save?)
  activate $main; click $main $((MX+300)) $((MY+150)); key $main ctrl+End; typ $main ";; X"; sleep 1
  key $main ctrl+w; sleep 3
  dlg=$(xdotool search --onlyvisible --name '.' | while read w; do n=$(title $w); case "$n" in *one.rkt*|*Konsole*|*Plasma*|*Settings*|"") ;; *) echo $w;; esac; done | tail -1)
  if [ -n "$dlg" ]; then echo "  Rueckfrage: '$(title $dlg)'"; key $dlg Return; sleep 3
    echo "  nach Return: Datei $([ "$(md5sum < $D/one.rkt)" = "$before" ] && echo UNVERAENDERT || echo GESPEICHERT), Fenster one.rkt: $(xdotool search --onlyvisible --name 'one\.rkt' | wc -l)"
  else echo "  KEINE Rueckfrage"; fi
  stop_dr
done

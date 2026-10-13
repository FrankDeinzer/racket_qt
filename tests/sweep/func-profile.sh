#!/usr/bin/env bash
# Funktions-Sweep 13: Profiler.  Choose Language -> Ctrl+D (Details), Ctrl+P ("Debugging and profiling"), Return (OK),
# F5 (Run; Marker-Datei = Programm lief), dann erscheint der "Profile"-Knopf (Aufnahme der Symbolleiste);
# Klick darauf -> Profil-Auswertung im Fenster (Aufnahme + Fensterliste).  Dialog-Chords Ctrl+D/P gehen
# nur, wenn Ctrl+<Zeichen> aus nativen Steuerelementen weitergeleitet wird (HACKING 74.7).
# Aufruf: tests/sweep/func-profile.sh [gtk|qt|both]
SCENE=func-prof; source "$(dirname "$0")/func-lib.sh"
for mode in $MODES; do
  echo "== $mode =="
  MARK=$FUNC_TMP/mark-$mode; rm -f $MARK; export SWEEP_MARK=$MARK
  start_dr $mode -l drracket "$HERE/files/prof.rkt" || exit 1
  main=$(findwin 'prof\.rkt.*DrRacket$' 90) || { echo "kein Fenster"; stop_dr; continue; }
  sleep 10; eval "$(xdotool getwindowgeometry --shell $main)"
  click $main $((X+120)) $((Y+HEIGHT-14)); sleep 2
  safe_key Down Down; sleep 1; safe_key Return; sleep 4
  dlg=$(findwin '^Choose Language' 8) || { echo "  kein Sprachdialog"; stop_dr; continue; }
  sleep 2; key $dlg ctrl+d; sleep 2; key $dlg ctrl+p; sleep 1; shot $dlg lang-prof $mode
  key $dlg Return; sleep 3
  echo "  Dialog nach OK: $(findwin '^Choose Language' 2 >/dev/null && echo OFFEN || echo geschlossen)"
  shot $main after-ok $mode; echo "  Fenster: $(listwins | tr '\n' ';')"
  activate $main; key $main F5; sleep 6; shot $main run-6s $mode; sleep 24
  echo "  Marker: $( [ -f $MARK ] && cat $MARK || echo FEHLT)"
  shot $main after-run $mode
  # Hinweis: in DrRacket 9.3 erscheint weder nativ noch unter Qt ein "Profile"-Knopf (Symbolleiste unveraendert)
  stop_dr
done
sidebyside lang-prof after-ok run-6s after-run

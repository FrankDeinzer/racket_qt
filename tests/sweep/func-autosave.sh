#!/usr/bin/env bash
# Funktions-Sweep 11: Autosave-Wiederherstellung.  Frisches PLTADDONDIR+XDG_CONFIG_HOME (Autosave-Toc liegt im
# pref-dir), one.rkt editieren, auf den Autosave warten (framework:autosave-delay = 30 s), Autosave-Datei auf Platte
# pruefen, kontrollierter harter Kill (SIGKILL eigene PID), Neustart MIT DEMSELBEN Preferences-Verzeichnis ->
# "Recover autosave files"-Fenster (Aufnahme+OCR), "Recover" klicken -> wiederhergestellter Inhalt im Editor.
SCENE=func-autosave; source "$(dirname "$0")/func-lib.sh"
for mode in $MODES; do
  echo "== $mode =="
  D=$FUNC_TMP/$mode; mkdir -p $D; cp "$HERE/files/a.rkt" $D/one.rkt
  unset KEEP_ENV
  start_dr $mode -l drracket $D/one.rkt || exit 1
  main=$(findwin 'one\.rkt.*DrRacket$' 90) || { echo "kein Fenster"; stop_dr; continue; }
  sleep 10; eval "$(xdotool getwindowgeometry --shell $main)"
  click $main $((X+300)) $((Y+150)); key $main ctrl+End; typ $main ";; AUTOSAVE-MARK"; sleep 1
  echo "  Titel: '$(title $main)'"
  for i in $(seq 1 14); do ls $D/\#* >/dev/null 2>&1 && break; sleep 5; done
  echo "  Autosave-Dateien im Quellverzeichnis: $(ls -a $D | grep '^#' | tr '\n' ' ')"
  echo "  Toc: $(ls -a $XDG_CONFIG_HOME/racket | tr '\n' ' ')"
  for f in $D/\#*; do [ -f "$f" ] && echo "  Marker in Autosave-Datei: $(grep -c AUTOSAVE-MARK "$f")"; done
  echo "  one.rkt auf Platte unveraendert (Marker 0): $(grep -c AUTOSAVE-MARK $D/one.rkt)"
  kill_dr
  echo "  -- Neustart (gleiches Preferences-Verzeichnis)"
  KEEP_ENV=1 start_dr $mode -l drracket || exit 1
  sleep 5
  listwins | sed 's/^/  Fenster: /'
  rec=$(findwin '^Recover' 90) && { echo "  Recover-Fenster: '$(title $rec)'"; sleep 2; shot $rec recover "$mode"
      echo "  OCR: $(tesseract $OUT/$SCENE-recover-$mode.png - 2>/dev/null | tr '\n' ' ' | cut -c1-400)"
      RECOVER_XY=564,84; [ "$mode" = qt ] && RECOVER_XY=557,78   # Recover-Knopf (Aufnahme-Koordinaten, je Toolkit)
      if [ -n "${RECOVER_XY:-}" ]; then
        eval "$(xdotool getwindowgeometry --shell $rec)"
        click $rec $((X+${RECOVER_XY%,*})) $((Y+${RECOVER_XY#*,})); sleep 5
        shot $rec after-recover "$mode"
        echo "  nach Recover: one.rkt auf Platte Marker (erwartet 1 = Backup uebernommen): $(grep -c AUTOSAVE-MARK $D/one.rkt); Backup-Datei vorhanden: $(ls -a $D | grep -c '^#')"
        echo "  OCR nach Recover: $(tesseract $OUT/$SCENE-after-recover-$mode.png - 2>/dev/null | tr '\n' ' ' | cut -c1-250)"
        DONE_XY=573,127; [ "$mode" = qt ] && DONE_XY=562,114
        click $rec $((X+${DONE_XY%,*})) $((Y+${DONE_XY#*,})); sleep 8
        echo "  Fenster nach Done:"; listwins | sed 's/^/    /'
      fi
  } || { echo "  KEIN Recover-Fenster"; fullshot norecover "$mode" >/dev/null; }
  stop_dr
done
sidebyside recover after-recover

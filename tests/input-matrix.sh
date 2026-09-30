#!/usr/bin/env bash
# Block D Phase 3: DrRacket keyboard matrix, native gtk as the reference.
#
# For each row the same xdotool key sequence is injected into a real DrRacket
# (native gtk, then PLT_QT=1), the buffer is saved (scratch copy!), and the
# resulting file text is compared.  A row passes iff Qt == gtk.  Needs an X11
# session with xdotool; NOT part of `raco test` (GUI).  Linux only.
#
#   tests/input-matrix.sh gtk    record the native reference -> tests/input-matrix-gtk.tsv
#   tests/input-matrix.sh qt     run under PLT_QT=1 and compare with that file
#   tests/input-matrix.sh both   record into a temp file, then compare (default)
#   MATRIX_ROWS='name1 name2' to run a subset.
#
# tests/input-matrix-gtk.tsv is the checked-in native reference (layout-independent
# rows only; recorded 2026-09-30 on Linux/KDE, DrRacket 9.3 gtk).  Dropped as
# unreliable in the native run itself: ctrl+d / ctrl+e (buffer leakage), ctrl+k
# (Racket>Kill dialog), ctrl+t (New Tab).
#
# Row format in ROWS below:  name|action;action;...   where action is
#   k:<xdotool key spec>   or   t:<text to type>
# The document is reset to empty before every row; the row must end with the
# buffer holding the observable result.  Layout assumption: none of the rows
# depends on the layout (only ASCII letters/space).
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
RACKET="${RACKET:-$HOME/racket/bin/racket}"
export QT_PLUGIN_PATH="${QT_PLUGIN_PATH:-$HOME/Qt/6.11.1/gcc_64/plugins}"
TMP="${TMPDIR:-/tmp}/input-matrix.$$"; mkdir -p "$TMP"

ROWS=(
 'select-all-replace|t:abc;k:ctrl+a;t:Z'
 'copy-paste|t:ab;k:ctrl+a;k:ctrl+c;k:ctrl+End;k:ctrl+v'
 'cut-paste|t:ab;k:ctrl+a;k:ctrl+x;t:Q;k:ctrl+v'
 'undo|t:ab;k:ctrl+z;t:X'
 'undo-redo|t:ab;k:ctrl+z;k:ctrl+shift+z'
 'backspace|t:abc;k:BackSpace'
 'delete-key|t:abc;k:Home;k:Delete'
 'home-end|t:ab;k:Home;t:X;k:End;t:Y'
 'ctrl-left-word|t:foo bar;k:ctrl+Left;t:X'
 'shift-left-select|t:abc;k:shift+Left;t:Z'
 'ctrl-shift-left-select|t:foo bar;k:ctrl+shift+Left;t:Z'
 'ctrl-backspace|t:foo bar;k:ctrl+BackSpace'
 # ctrl+k is Racket > Kill in DrRacket (modal 'Evaluation Terminated' dialog): not a text row
 'auto-indent-return|t:(a;k:Return;t:b'
 'tab-reindent|t:(a;k:Return;t:b;k:Tab;t:c'
 'return-newline|t:a;k:Return;t:b'
 'paste-and-indent|t:(a;k:Return;t:b;k:ctrl+a;k:ctrl+c;k:ctrl+End;k:Return;k:ctrl+shift+v'
)

run_backend() {  # $1 = gtk|qt  -> writes $TMP/$1.<row>
  local mode=$1 f="$TMP/$1.rkt"
  : > "$f"; printf '#lang racket\n' > "$f"
  if [ "$mode" = qt ]; then export PLT_QT=1; else unset PLT_QT; fi
  "$RACKET" -l drracket -- "$f" >/dev/null 2>"$TMP/$1.err" &
  local pid=$! W=""
  for _ in $(seq 1 120); do
    W=$(xdotool search --onlyvisible --name "$(basename "$f")" | head -1); [ -n "$W" ] && break; sleep 1
  done
  [ -z "$W" ] && { echo "no window for $mode" >&2; kill $pid; return 1; }
  sleep 6; xdotool windowactivate --sync "$W"; sleep 0.5
  xdotool mousemove --window "$W" 400 200 click 1; sleep 0.4
  for row in "${ROWS[@]}"; do
    local name=${row%%|*} acts=${row#*|}
    if [ -n "${MATRIX_ROWS:-}" ] && [[ " $MATRIX_ROWS " != *" $name "* ]]; then continue; fi
    xdotool key ctrl+a; sleep 0.2; xdotool key BackSpace; sleep 0.2
    xdotool key ctrl+s; sleep 0.8
    IFS=';' read -ra A <<< "$acts"
    for a in "${A[@]}"; do
      case $a in
        k:*) xdotool key --delay 60 "${a#k:}" ;;
        t:*) xdotool type --delay 60 -- "${a#t:}" ;;
      esac
      sleep 0.25
    done
    sleep 0.3; xdotool key ctrl+s; sleep 1.0
    cp "$f" "$TMP/$mode.$name"
  done
  xdotool key ctrl+q; sleep 2; kill $pid 2>/dev/null; wait $pid 2>/dev/null
}

REF="$HERE/tests/input-matrix-gtk.tsv"
MODE=${1:-both}
wait_no_drracket() {
  for _ in $(seq 1 30); do pgrep -f "[r]acket -l drracket" >/dev/null || return 0; sleep 1; done
}
collect() {  # $1 = mode -> TSV "name<TAB>cat -A text" on stdout
  for row in "${ROWS[@]}"; do
    n=${row%%|*}; [ -f "$TMP/$1.$n" ] || continue
    printf '%s\t%s\n' "$n" "$(cat -A "$TMP/$1.$n" | tr -d '\n')"
  done
}
case $MODE in
  gtk)  run_backend gtk; collect gtk > "$REF"; echo "recorded $REF"; exit 0 ;;
  both) run_backend gtk; collect gtk > "$TMP/ref.tsv"; wait_no_drracket; REF="$TMP/ref.tsv" ;;
esac
run_backend qt
fail=0
printf '%-26s %-6s %s\n' ROW RESULT "gtk | qt"
while IFS=$'\t' read -r name g; do
  [ -f "$TMP/qt.$name" ] || { printf '%-26s %-6s %s | <none>\n' "$name" FAIL "$g"; fail=1; continue; }
  q=$(cat -A "$TMP/qt.$name" | tr -d '\n')
  if [ "$g" = "$q" ]; then r=PASS; else r=FAIL; fail=1; fi
  printf '%-26s %-6s %s | %s\n' "$name" "$r" "$g" "$q"
done < "$REF"
echo "(scratch: $TMP)"
exit $fail

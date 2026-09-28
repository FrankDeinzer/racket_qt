#!/usr/bin/env bash
# Starts the Qt backend on Linux for manual/free testing (docs/HACKING.md,
# CLAUDE.md "Run / Smoke-Test" Linux section).
#
# No args: launches real DrRacket under PLT_QT=1.
# With args: forwards them to `racket` (still under PLT_QT=1), e.g.
#   bin/run_linux.sh examples/hello.rkt
set -euo pipefail

export PLT_QT=1
export QT_PLUGIN_PATH="${QT_PLUGIN_PATH:-$HOME/Qt/6.11.1/gcc_64/plugins}"

RACKET="$HOME/racket/bin/racket"

if [ "$#" -eq 0 ]; then
  exec "$RACKET" -l drracket
else
  exec "$RACKET" "$@"
fi

#!/usr/bin/env bash
# Starts the Qt backend on macOS for manual/free testing (docs/HACKING.md,
# CLAUDE.md "Run / Smoke-Test" macOS section).
#
# No args: launches real DrRacket under PLT_QT=1.
# With args: forwards them to `racket` (still under PLT_QT=1), e.g.
#   bin/run_macos.sh examples/hello.rkt
set -euo pipefail

export PLT_QT=1

if [ "$#" -eq 0 ]; then
  exec racket -l drracket
else
  exec racket "$@"
fi

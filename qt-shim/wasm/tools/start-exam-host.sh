#!/bin/bash
# Starts the exam-host prototype (HACKING §85.16).
#   tools/start-exam-host.sh [build-dir]
# LOG_ENDPOINT=1 schaltet POST /__log ein (nur zur Diagnose, siehe qt-shim/wasm/README.md "Diagnose-Schalter").
# build-dir: a finished Qt+Racket WASM build (default qt-shim/build/wasm-drracket, i.e. the folder `tools/stage-build.sh` fills).
# It must contain racketqt_wasm.{html,js,wasm,data}; exam-host.html is copied in from this repo on every start.
set -e
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dir="${1:-$here/../../build/wasm-drracket}"
[ -f "$dir/racketqt_wasm.html" ] || { echo "Kein WASM-Build in '$dir' (racketqt_wasm.html fehlt)." >&2; echo "Build-Ordner als Argument angeben oder mit tools/stage-build.sh <build-dir> bereitstellen." >&2; exit 1; }
cp "$here/exam-host.html" "$dir/exam-host.html"
exec node "$here/serve.mjs" "$dir" "${PORT:-8123}"

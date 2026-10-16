#!/bin/bash
# Copies the files of a finished WASM build (cmake build dir) to qt-shim/build/wasm-drracket (gitignored), where start-exam-host.sh finds them.
#   tools/stage-build.sh <cmake-build-dir>
set -e
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="${1:?usage: stage-build.sh <cmake-build-dir>}"
dst="$here/../../build/wasm-drracket"
mkdir -p "$dst"
for f in racketqt_wasm.html racketqt_wasm.js racketqt_wasm.wasm racketqt_wasm.data qtloader.js qtlogo.svg; do [ -f "$src/$f" ] && cp "$src/$f" "$dst/$f"; done
ls -la "$dst" | sed 's/^/  /'
echo "bereit: $dst"

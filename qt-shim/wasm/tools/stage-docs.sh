#!/bin/bash
# Copies the HTML documentation of a local Racket installation into the exam server's doc/ folder (HACKING §85.20), so that the Help links of the
# WASM DrRacket (rewritten from docs.racket-lang.org/<manual>/... to <server>/doc/<manual>/...) work without network.
#   tools/stage-docs.sh [racket-doc-dir] [build-dir] [manual ...]
# defaults: "/Applications/Racket v9.3/doc", qt-shim/build/wasm-drracket, and the manuals below (about 70 MB; the full tree is 224 MB).
set -e
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="${1:-/Applications/Racket v9.3/doc}"
dst="${2:-$here/../../build/wasm-drracket}/doc"
shift 2 2>/dev/null || true
manuals=("$@")
[ ${#manuals[@]} -eq 0 ] && manuals=(reference guide gui draw math search teachpack htdp-langs syntax scribble images framework)
mkdir -p "$dst"
for m in "${manuals[@]}"; do
  [ -d "$src/$m" ] || { echo "uebersprungen (nicht vorhanden): $m" >&2; continue; }
  /bin/rm -rf "$dst/$m"; /bin/cp -R "$src/$m" "$dst/$m"
done
for f in "$src"/*.html "$src"/*.css "$src"/*.js "$src"/*.rktd; do [ -f "$f" ] && /bin/cp -f "$f" "$dst/"; done
du -sh "$dst" | sed 's/^/  /'
echo "bereit: $dst (im Browser: <server>/doc/reference/index.html)"

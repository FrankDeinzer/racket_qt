#lang racket/base
;; App manifest for the racket/gui-on-Qt-WASM payload (docs/HACKING.md §85.9). Built with the racket-wasm-backend
;; orchestrator, only to obtain the package payload (share.data) -- the runtime itself is linked by qt-shim/wasm/CMakeLists.txt:
;;
;;   cd third_party/racket-wasm-backend && source ~/emsdk/emsdk_env.sh
;;   racket build/main.rkt app ../../qt-shim/wasm/app --dest <out> --racket /opt/homebrew/bin/racket \
;;          --scheme $PWD/.work/racket/racket/src/ChezScheme/tarm64osx/bin/tarm64osx/scheme
;;   python3 qt-shim/wasm/tools/unpack-share.py <out>/share.data.js <out>/share.data <tree>
;;
;; drracket-core (HACKING §85.14): the real DrRacket; its dependency closure is resolved against the 9.3 release catalog.
;; gui-lib comes from OUR fork (wx/qt backend, third_party/gui), not from the catalog. draw-lib comes from the 9.3 release
;; catalog so that the fork's package patch for Cairo FFI types (cairo_pattern_reference, ...) applies to it.
(provide app)

(define app
  (hash 'pkgs       '(draw-lib drracket-core)
        'wasm-libs  '(draw)
        'local-pkgs '("../../../third_party/gui/gui-lib")
        'target     'node))

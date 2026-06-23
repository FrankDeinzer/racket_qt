#lang racket/base
(require ffi/unsafe)

(define shim-path
  (path->string
   (build-path (current-directory) "build" "windows-x64" "Debug" "racketqtshim.dll")))

(printf "Loading: ~a\n" shim-path)

(define shim (ffi-lib shim-path))

(define shim_version
  (get-ffi-obj "shim_version" shim (_fun -> _string)))

(printf "shim_version() => ~s\n" (shim_version))

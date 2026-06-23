#lang racket/base
(require ffi/unsafe
         racket/path)

(define here (path-only (path->complete-path (find-system-path 'run-file))))

(define shim-path
  (path->string
   (simplify-path (build-path here ".." "build" "windows-x64" "Debug" "racketqtshim.dll"))))

(printf "Loading: ~a\n" shim-path)

(define shim (ffi-lib shim-path))

(define shim_version
  (get-ffi-obj "shim_version" shim (_fun -> _string)))

(printf "shim_version() => ~s\n" (shim_version))

#lang racket/base
(require ffi/unsafe
         racket/path)

(define here (path-only (path->complete-path (find-system-path 'run-file))))

(define shim-path
  (path->string
   (simplify-path
    (case (system-type 'os)
      [(windows)
       (build-path here ".." "build" "windows-x64" "Debug" "racketqtshim.dll")]
      [(macosx)
       (build-path here ".." "build" "macos-arm64" "libracketqtshim.dylib")]
      [else
       (build-path here ".." "build" "linux-x64" "libracketqtshim.so")]))))

(printf "Loading: ~a\n" shim-path)

(define shim (ffi-lib shim-path))

(define shim_version
  (get-ffi-obj "shim_version" shim (_fun -> _string)))

(printf "shim_version() => ~s\n" (shim_version))

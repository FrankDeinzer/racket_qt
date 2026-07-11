#lang racket/gui
; Driver for the file-selector work (docs/2026-07-11_prompt.md): a frame with
; an "Open..." button that calls get-file and shows the returned path (or #f
; on cancel) both in a label and on stdout, so the return value is visible
; without extra tooling.

(define frame (new frame% [label "File-Dialog Probe"] [width 420] [height 160]))
(define panel (new horizontal-panel% [parent frame]))

(define result-msg
  (new message% [parent frame] [label "(no result yet)"] [stretchable-width #t]))

(define (show-result who path)
  (define text (format "~a -> ~a" who (or path "#f (cancel)")))
  (printf "[file-dialog-probe] ~a\n" text)
  (send result-msg set-label text))

(new button%
     [parent panel]
     [label "Open..."]
     [callback (lambda (b e)
                 (show-result 'get-file (get-file "Open a file" frame)))])

(send frame show #t)

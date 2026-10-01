#lang racket/gui
;; style-audit (§64.8): frame% '(no-caption float no-resize-border) is DrRacket's
;; tooltip frame -- must be frameless, above its parent and must not take focus;
;; canvas% 'no-focus must not enter the focus chain.  Prints the focus owner.
(define main (new frame% [label "float-main"] [width 360] [height 140]))
(define nf (new canvas% [parent main] [style '(no-focus)] [min-width 100] [min-height 30]))
(define tf (new text-field% [parent main] [label "field"]))
(define tip (new frame% [label "tip"] [style '(no-caption float no-resize-border)] [x 200] [y 200]))
(void (new message% [parent tip] [label "I am a tooltip"]))
(send main show #t)
(send tip show #t)
(thread (lambda () (sleep 3)
  (printf "focus owner main: ~a\n" (let ([w (send main get-focus-window)]) (and w (object-name w))))
  (printf "tip focus: ~a\n" (send tip get-focus-window)) (flush-output)))

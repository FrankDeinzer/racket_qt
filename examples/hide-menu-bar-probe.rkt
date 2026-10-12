#lang racket/gui
;; 'hide-menu-bar probe (HACKING §70): gtk fullscreens the frame at construction.
(define f (new frame% [label "hmb"] [width 300] [height 200] [style '(hide-menu-bar)]))
(send f show #t)
(sleep/yield 1.5)
(define-values (dw dh) (get-display-size))
(printf "frame ~ax~a display ~ax~a\n" (send f get-width) (send f get-height) dw dh)
(flush-output)
(send f show #f)

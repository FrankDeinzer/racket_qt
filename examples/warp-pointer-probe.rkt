#lang racket/gui
;; warp-pointer probe (HACKING §70): moves the pointer to client (50,40) of a
;; canvas; prints the expected screen position, then waits so xdotool can read it.
(define f (new frame% [label "warp"] [width 300] [height 200] [x 200] [y 200]))
(define c (new canvas% [parent f]))
(send f show #t)
(sleep/yield 1.5)
(define-values (sx sy) (send c client->screen 50 40))
(printf "expected ~a ~a\n" sx sy)
(flush-output)
(send c warp-pointer 50 40)
(sleep/yield 3)
(send f show #f)

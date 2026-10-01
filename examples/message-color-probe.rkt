#lang racket/gui
;; Probe: message% get-color/set-color (war Qt-Stub: get-color #f, set-color No-op).
;; Gibt get-color-Werte aus; optional Screenshot-Pruefung durch das aufrufende Skript (rote/blaue Pixel).
(define f (new frame% [label "message-color-probe"]))
(define a (new message% [parent f] [label "PLAIN plain plain"]))
(define b (new message% [parent f] [label "RED RED RED RED"] [color (make-object color% 255 0 0)]))
(define c (new message% [parent f] [label "BLUE BLUE BLUE"]))
(define d (new message% [parent f] [label "RESET RESET"] [color (make-object color% 0 160 0)]))
(send c set-color (make-object color% 0 0 255))
(send d set-color #f)
(send f show #t)
(sleep/yield 1)
(define (col o) (let ([x (send o get-color)]) (and x (list (send x red) (send x green) (send x blue)))))
(printf "get-color plain ~a red ~a blue ~a reset ~a\n" (col a) (col b) (col c) (col d))
(when (getenv "PROBE_WAIT") (sleep/yield (string->number (getenv "PROBE_WAIT"))))
(exit (if (equal? (list (col a) (col b) (col c) (col d)) '(#f (255 0 0) (0 0 255) #f)) 0 1))

#lang racket/gui
; Minimal probe for message% (static text label)
(define frame (new frame% [label "Message Probe"] [width 400] [height 200]))
(define msg (new message% [label "Hello, message%!"] [parent frame]))
(send frame show #t)
(sleep/yield 3)
(send msg set-label "Label updated.")
(sleep/yield 2)
(send frame show #f)

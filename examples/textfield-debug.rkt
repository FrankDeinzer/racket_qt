#lang racket/gui
; Debug text-field% instantiation crash
(define frame (new frame% [label "TF Debug"] [width 400] [height 300]))
(define tf (new text-field% [label "Name:"] [parent frame]))
(send frame show #t)
(sleep/yield 2)
(send frame show #f)

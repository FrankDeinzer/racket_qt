#lang racket/gui
; E-0 Fallback: minimal frame% + menu-bar% + menu% + menu-item% + editor-canvas%
; Entdeckt fehlende Platform-Klassen ohne DrRacket-Framework.

(define frame (new frame% [label "E-0 Menu Test"] [width 600] [height 400]))

(define mb (new menu-bar% [parent frame]))
(define m  (new menu% [label "File"] [parent mb]))
(new menu-item% [label "Quit"] [parent m]
     [callback (lambda (i e) (send frame show #f))])

(define ec (new editor-canvas% [parent frame]))
(define txt (new text%))
(send ec set-editor txt)
(send txt insert "Hello from Qt + menu!")

(send frame show #t)
(sleep/yield 5)
(send frame show #f)

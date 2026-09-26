#lang racket/gui
; Probe for button%'s set-label (docs/2026-09-26_prompt-macos.md): toggles a
; button's own label between two strings on each click, so a visual/screen-
; shot check can confirm the label actually changes on screen.

(define frame (new frame% [label "set-label Probe"] [width 240] [height 100]))

(define toggled? #f)

(define btn
  (new button%
       [parent frame]
       [label "Show Details"]
       [callback (lambda (b e)
                   (set! toggled? (not toggled?))
                   (send b set-label (if toggled? "Hide Details" "Show Details")))]))

(send frame show #t)

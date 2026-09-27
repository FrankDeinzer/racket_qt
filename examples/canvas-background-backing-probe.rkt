#lang racket/gui
; Probe for §61's get-canvas-background-for-backing fix
; (wx/qt/canvas.rkt): the regular auto-repaint path (canvas-mixin.rkt's
; do-on-paint) uses this method to fill the backing bitmap with
; set-canvas-background's color before the user's on-paint runs. Before the
; fix it was unconditionally #f, so the backing bitmap was only cleared to
; transparent -- invisible whenever on-paint covers the whole canvas (that's
; why this was masked in editor-canvas%/2htdp full-repaint cases), but
; visible as a white/transparent margin around a paint callback that only
; draws a small, non-covering shape.
;
; set-canvas-background is red; the paint callback draws only a small blue
; square in the top-left corner. Before the fix: the rest of the canvas is
; white/transparent. After the fix: the rest of the canvas is red.

(define frame (new frame% [label "canvas-background-for-backing Probe"] [width 300] [height 200]))

(define c
  (new canvas%
       [parent frame]
       [paint-callback
        (lambda (canvas dc)
          (send dc set-brush "blue" 'solid)
          (send dc set-pen "blue" 1 'solid)
          (send dc draw-rectangle 10 10 40 40))]))

(send c set-canvas-background (make-object color% "red"))

(send frame show #t)

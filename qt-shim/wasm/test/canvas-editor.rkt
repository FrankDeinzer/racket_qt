;; Praxistest racket/gui auf Qt-WASM: canvas% mit Zeichnen (on-paint) plus editor-canvas% mit text% und Tastatur.
;; Ausgabe (Konsole): PAINT <n> <ms>, KEY <char> <ms in on-char>, DONE-PAINTS. Fokus liegt per Programm auf dem Editor.
(define t0 (current-inexact-milliseconds))
(require racket/class racket/gui/base)
(printf "GUI-LIB-LOADED ~a ms\n" (round (- (current-inexact-milliseconds) t0)))

(define paints 0)
(define phase 0)
(define my-canvas%
  (class canvas%
    (define/override (on-paint)
      (define t (current-inexact-milliseconds))
      (define dc (send this get-dc))
      (send dc set-smoothing 'smoothed)
      (send dc set-brush "white" 'solid) (send dc set-pen "black" 1 'solid)
      (send dc draw-rectangle 0 0 400 200)
      (for ([i (in-range 60)])
        (send dc set-brush (make-color (modulo (* i 37) 256) (modulo (* i 91) 256) 160) 'solid)
        (send dc draw-ellipse (+ 10 (* 6 i)) (+ 20 (* (modulo (+ i phase) 7) 20)) 40 40))
      (send dc set-font (make-font #:size 16 #:family 'swiss))
      (send dc draw-text (format "paint ~a" paints) 10 4)
      (set! paints (add1 paints))
      (printf "PAINT ~a ~a ms\n" paints (round (- (current-inexact-milliseconds) t))))
    (super-new)))

(define timed-text%
  (class text%
    (define/override (on-char e)
      (define t (current-inexact-milliseconds))
      (super on-char e)
      (printf "KEY ~s ~a ms\n" (send e get-key-code) (round (- (current-inexact-milliseconds) t))))
    (super-new)))

(define f (new frame% [label "canvas + editor on Qt-WASM"] [width 420] [height 420]))
(define c (new my-canvas% [parent f] [min-width 400] [min-height 200] [stretchable-height #f]))
(define ed (new timed-text%))
(define ec (new editor-canvas% [parent f] [editor ed] [min-height 140]))
(send f show #t)
(send ec focus)
(printf "FRAME-SHOWN\n")
;; zweiter Paint nach programmatischer Änderung (misst Refresh-Pfad)
(thread (lambda () (sleep 6) (set! phase 3) (send c refresh) (printf "REFRESH-REQUESTED\n")))
(yield 'wait)
(printf "DONE\n")

#lang racket/gui
; Diagnose-/Akzeptanzprobe fuer gauge% (docs/HACKING.md §40-Bestandsaufnahme,
; jetzt §41). Ein horizontaler und ein vertikaler Gauge, ein Timer bewegt
; beide vorwaerts -- visuell per Screenshot zu pruefen, dass der Balken
; tatsaechlich waechst (vorher: reiner No-op-Stub, zeichnete nichts).
(require "pump-gate.rkt")

(define f (new frame% [label "gauge-probe"] [width 300] [height 220]))
(define row (new horizontal-panel% [parent f]))

(define hgauge (new gauge% [label "h"] [range 20] [parent row] [style '(horizontal)]))
(define vgauge (new gauge% [label "v"] [range 20] [parent row] [style '(vertical)]))

(new message% [parent f]
     [label (format "range=~a" (send hgauge get-range))])

(send f show #t)
(pump-gate!)

(let loop ([n 0])
  (define v (modulo n 21))
  (send hgauge set-value v)
  (send vgauge set-value v)
  (eprintf "[gauge-probe] tick ~a value=~a get-value=~a/~a\n"
           n v (send hgauge get-value) (send hgauge get-range))
  (when (< n 60) (wait/pump 0.3) (loop (add1 n))))

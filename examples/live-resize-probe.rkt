#lang racket/gui
; Diagnose-Probe fuer Block B (docs/HACKING.md §21.7): misst, ob ein natives,
; von AUSSEN ausgeloestes Resize (xdotool windowsize, kein Live-Drag) jetzt
; Kind-Controls tatsaechlich neu positioniert (resizeEvent -> queue-on-size ->
; wxtop.rkt's resized/correct-size). Stretchbarer Panel-Inhalt: ein Button soll
; nach dem Resize die neue Fensterbreite fuellen.
; ACHTUNG: die resizeEvent/shim_window_get_size-Verdrahtung, die diese Probe
; eigentlich pruefen soll, ist NICHT im Baum (vollstaendig zurueckgerollt, s.
; docs/HACKING.md §21.9). Diese Probe zeigt deshalb aktuell absichtlich den
; unveraenderten Ausgangsbefund: get-width/button-Groesse bleiben eingefroren.
(define f (new frame% [label "live-resize-probe"] [width 300] [height 200]))
(define p (new vertical-panel% [parent f]))
(define b (new button% [label "resize me"] [parent p]))
(send f show #t)
(let loop ([n 0])
  (define-values (w h) (values (send f get-width) (send f get-height)))
  (define-values (bw bh) (values (send b get-width) (send b get-height)))
  (eprintf "[probe] tick ~a: frame=~ax~a button=~ax~a\n" n w h bw bh)
  (when (< n 30)
    (sleep 1)
    (loop (add1 n))))

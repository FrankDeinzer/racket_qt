#lang racket/gui
; Diagnose-Probe fuer Block B (docs/HACKING.md §21.7): misst, ob ein natives,
; von AUSSEN ausgeloestes Resize (xdotool windowsize, kein Live-Drag) jetzt
; Kind-Controls tatsaechlich neu positioniert (resizeEvent -> queue-on-size ->
; wxtop.rkt's resized/correct-size). Stretchbarer Panel-Inhalt: ein Button soll
; nach dem Resize die neue Fensterbreite fuellen.
; STAND SEIT 2026-09-14 (§32): die resizeEvent-Verdrahtung ist im Baum, und
; diese Probe ist damit von der Ausgangsbefund-Probe zur Regressionswache
; geworden -- erwartet wird jetzt, dass der Button der Fensterbreite folgt
; (gemessen 296 -> 696 -> 896). Der frueher hier stehende Hinweis "Verdrahtung
; ist NICHT im Baum" stammte aus dem zurueckgerollten Versuch 3 (§21.9) und war
; seit §32 falsch.
; REPARIERT 2026-09-14 (docs/HACKING.md §21.10): die Vorversion wartete mit
; (sleep 1) im Hauptthread -- der IST der Handler-Thread des Eventspace, und
; (sleep n) dispatcht keine Events. Geposteste Thunks (u.a. der resize-cb aus
; einer kuenftigen resizeEvent-Verdrahtung) konnten deshalb strukturell nie
; laufen. Der §21.9-Befund "gepostetes Thunk laeuft nie" war ein Artefakt genau
; dieses Musters, kein Qt-Befund. Jetzt wird dispatchend gewartet, und das
; Pump-Gate weist die laufende Queue im Log nach.
(require "pump-gate.rkt")
(define f (new frame% [label "live-resize-probe"] [width 300] [height 200]))
(define p (new vertical-panel% [parent f]))
; stretchable-width MUSS gesetzt sein: ein button% ist per Default nicht
; stretchbar und wuerde auch bei perfektem Reflow konstant 80x25 bleiben --
; eine unstretchbare Probe kann Reflow grundsaetzlich nicht nachweisen.
(define b (new button% [label "resize me"] [parent p] [stretchable-width #t]))
(send f show #t)
(pump-gate!)
(let loop ([n 0])
  (define-values (w h) (values (send f get-width) (send f get-height)))
  (define-values (bw bh) (values (send b get-width) (send b get-height)))
  (eprintf "[probe] tick ~a: frame=~ax~a button=~ax~a\n" n w h bw bh)
  (when (< n 30)
    (wait/pump 1)
    (loop (add1 n))))

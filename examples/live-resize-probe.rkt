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
; ZUSATZ-ACHTUNG (Folgesession, §21.9): dieses Skript misst durch eine
; bare-racket-Hauptthread-(sleep 1)-Schleife -- ein closeEvent-Diskriminator-Test
; hat gezeigt, dass GENAU dieses Harness-Muster geposteste Eventspace-Thunks
; generell erst laufen laesst, wenn der Hauptthread fertig ist, nicht resize-
; spezifisch. Ein "eingefrorenes" Ergebnis aus dieser Probe beweist also NICHT,
; dass eine kuenftige resizeEvent-Verdrahtung wirkungslos waere -- es koennte
; ebenso gut nur dieses Instrument sein. Vor einer erneuten Nutzung: gegen echtes
; DrRacket oder eine yield-/eventspace-idle-basierte (nicht sleep-basierte)
; Harness validieren.
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

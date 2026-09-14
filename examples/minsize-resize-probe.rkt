#lang racket/gui
; Diagnose-Probe (docs/HACKING.md §21.7, Fix-Versuch 4): erzwingt wxtop.rkt's
; KORREKTUR-Zweig in `resized` (set-size), und zwar ausgeloest durch ein ECHTES
; natives Resize -- genau die Kette, an der Fix-Versuch 1 in eine
; Rueckkopplungsschleife lief: natives Resize -> queue-on-size -> correct-size
; -> set-size -> natives Resize -> ...
; Der Inhalt hat eine grosse Mindestgroesse; wird das Fenster von aussen
; kleiner gezogen, muss correct-size es genau einmal zurueckkorrigieren und
; danach zur Ruhe kommen (remember-size erkennt das Echo des eigenen set-size).
(require "pump-gate.rkt")
(define f (new frame% [label "minsize-resize-probe"] [width 700] [height 600]))
(define p (new vertical-panel% [parent f]))
(for ([i (in-range 12)])
  (new button% [label (format "Knopf ~a mit einem absichtlich sehr langen Label" i)] [parent p]))
(send f show #t)
(pump-gate!)
(let loop ([n 0])
  (eprintf "[probe] tick ~a: frame=~ax~a\n" n (send f get-width) (send f get-height))
  (when (< n 40) (wait/pump 1) (loop (add1 n))))

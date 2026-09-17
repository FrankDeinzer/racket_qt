#lang racket/gui
; Diagnose-/Akzeptanzprobe fuer get-current-mouse-state (docs/HACKING.md
; §36-Bestandsaufnahme, jetzt §42). Druckt Position + gedrueckte Tasten/
; Knoepfe alle 300ms -- waehrend die Probe laeuft, die Maus an eine bekannte
; Bildschirmposition bewegen und/oder Shift/Strg/Alt halten, um die Werte
; gegen echte Eingabe zu pruefen (keine automatisierte Zusicherung moeglich).
(require "pump-gate.rkt")

(define f (new frame% [label "mouse-state-probe"] [width 300] [height 100]))
(new message% [parent f] [label "watch stderr"])
(send f show #t)
(pump-gate!)

(let loop ([n 0])
  (define-values (pos mods) (get-current-mouse-state))
  (eprintf "[mouse-state-probe] tick ~a pos=(~a,~a) mods=~a\n"
           n (send pos get-x) (send pos get-y) mods)
  (when (< n 40) (wait/pump 0.3) (loop (add1 n))))

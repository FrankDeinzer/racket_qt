#lang htdp/bsl
; htdp-Lackmustest Facette 3 (docs/2026-07-14_prompt.md): test-engine (check-expect).
; #lang htdp/bsl statt racket + (test), um denselben test-engine/test-tool.rkt-
; Dock-Pfad wie ein echtes htdp-Programm zu treffen. Ein absichtlich
; fehlschlagender check-expect, damit der Test-Report-Dock mit Inhalt oeffnet
; (leerer/erfolgreicher Dock ist kein Test fuer den bekannten Absturz).
(define (square-it x) (* x x))

(check-expect (square-it 3) 9)
(check-expect (square-it 5) 25)
(check-expect (square-it 4) 17)

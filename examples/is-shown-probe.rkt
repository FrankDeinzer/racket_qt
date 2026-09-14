#lang racket/gui
; Diagnose-Probe (docs/2026-09-13_prompt.md Phase 2.1): misst, ob wx/qt/window.rkt's
; `shown?`-Feld beim normalen Show-Pfad (frame -> panel -> button) tatsächlich gesetzt
; wird. Instrumentierung in wx/qt/window.rkt's `show`-Methode via PLT_QT_DEBUG_SHOWN.
; Wartet dispatchend (docs/HACKING.md §21.10) -- der gemessene Show-Pfad selbst ist
; synchron, der Befund vom 2026-09-13 bleibt davon unberuehrt.
(require "pump-gate.rkt")
(define f (new frame% [label "is-shown-probe"] [width 300] [height 200]))
(define p (new vertical-panel% [parent f]))
(define b (new button% [label "probe-button"] [parent p]
                [callback (lambda (b e) (void))]))
(eprintf "[probe] before (send f show #t)\n")
(send f show #t)
(pump-gate!)
(eprintf "[probe] after (send f show #t)\n")
(wait/pump 1)
(eprintf "[probe] exiting\n")
(exit 0)

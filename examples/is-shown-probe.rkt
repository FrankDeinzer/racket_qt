#lang racket/gui
; Diagnose-Probe (docs/2026-09-13_prompt.md Phase 2.1): misst, ob wx/qt/window.rkt's
; `shown?`-Feld beim normalen Show-Pfad (frame -> panel -> button) tatsächlich gesetzt
; wird. Instrumentierung in wx/qt/window.rkt's `show`-Methode via PLT_QT_DEBUG_SHOWN.
(define f (new frame% [label "is-shown-probe"] [width 300] [height 200]))
(define p (new vertical-panel% [parent f]))
(define b (new button% [label "probe-button"] [parent p]
                [callback (lambda (b e) (void))]))
(eprintf "[probe] before (send f show #t)\n")
(send f show #t)
(eprintf "[probe] after (send f show #t)\n")
(sleep 1)
(eprintf "[probe] exiting\n")
(exit 0)

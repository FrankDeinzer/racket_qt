#lang racket/gui
; Checkpoint-E driver (2026-07-10-2_prompt, updated 2026-07-10-3_prompt):
; isolated dialog% + list-box% + check-box% probe, substituted for the
; autosave recovery dialog after confirming (framework/private/autosave.rkt)
; that the recovery dialog does not actually use either widget. Also
; exercises dialog% modality (Phase 1/2) against a real parent frame — click
; "Parent button" while the dialog is open to check that it's blocked.

; No explicit [min-width]/[min-height] anywhere below: the wxitem.rkt
; make-item% seed bug (docs/HACKING.md §18.2) that used to force this
; workaround is fixed (2026-07-10-3_prompt, Fix A) — window%'s w/h are now
; seeded from QWidget::sizeHint() right after construction, so panel-sizing
; sees each control's real natural size instead of 0/0.

(define frame (new frame% [label "E-0 Widget Driver — Parent"] [width 420] [height 160]))
(define frame-panel (new vertical-panel% [parent frame]))

(new message% [parent frame-panel]
     [label "Click \"Open dialog\", then try clicking the parent button below while it's open."])

(new button% [parent frame-panel]
     [label "Parent button (should be blocked while dialog is open)"]
     [callback (lambda (b e) (printf "PARENT BUTTON CLICKED — should NOT print while dialog is open~n"))])

(new button% [parent frame-panel] [label "Open dialog"]
     [callback
      (lambda (b e)
        (define dlg (new dialog% [parent frame]
                          [label "list-box% + check-box% driver"]
                          [width 360] [height 320]))
        (define dlg-panel (new vertical-panel% [parent dlg]))
        (define lb (new list-box% [parent dlg-panel]
                        [label "Items:"]
                        [choices '("Alpha" "Beta" "Gamma" "Delta")]
                        [callback
                         (lambda (l ev)
                           (printf "list-box selection changed: ~a~n" (send l get-selections)))]))
        (define cb (new check-box% [parent dlg-panel]
                        [label "Enable feature X"]
                        [callback
                         (lambda (c ev)
                           (printf "check-box toggled: ~a~n" (send c get-value)))]))
        (define btn-panel (new horizontal-panel% [parent dlg-panel] [stretchable-height #f]))
        (new button% [parent btn-panel] [label "OK"]
             [callback (lambda (b e) (send dlg show #f))])
        (new button% [parent btn-panel] [label "Cancel"]
             [callback (lambda (b e) (send dlg show #f))])
        (send dlg show #t)
        (printf "dialog closed — final list-box selections=~a check-box value=~a~n"
                (send lb get-selections) (send cb get-value)))])

(send frame show #t)

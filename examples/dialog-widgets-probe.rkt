#lang racket/gui
; Checkpoint-E driver (2026-07-10-2_prompt): isolated dialog% + list-box% +
; check-box% probe, substituted for the autosave recovery dialog after
; confirming (framework/private/autosave.rkt) that the recovery dialog does
; not actually use either widget. Also exercises dialog% modality (Phase 1)
; against a real parent frame — click "Parent button" while the dialog is
; open to check that other-modal? actually blocks it.

; Widgets go inside explicit vertical-panel%s (like autosave.rkt itself
; does), not straight on the frame%/dialog%, AND every control gets an
; explicit [min-width ...]/[min-height ...]. Both are a workaround for a
; separate, pre-existing bug (confirmed with a 3-plain-button% diagnostic,
; independent of this session's list-box%/check-box% work): wxitem.rkt's
; make-item% seeds a control's min-width/min-height from (get-width)/
; (get-height) right after construction, but our window%'s get-width/height
; only ever reflect a *previous* set-size call -- at this point in
; construction that's still 0, so every control reports zero min-size, the
; panel never advances the y-offset between children, and they all land on
; top of each other at Qt's untouched default geometry. Not fixed here (out
; of scope, and it also affects the already-"real" button%/message%, not
; just today's widgets) -- flagged in the report as a nebenbefund. Forcing
; explicit min sizes bypasses the broken seed so this driver can still show
; list-box%/check-box% distinctly and prove they work; it does not prove
; they auto-size correctly in a real dialog without this workaround.

(define frame (new frame% [label "E-0 Widget Driver — Parent"] [width 420] [height 160]))
(define frame-panel (new vertical-panel% [parent frame]))

(new message% [parent frame-panel] [min-height 24]
     [label "Click \"Open dialog\", then try clicking the parent button below while it's open."])

(new button% [parent frame-panel] [min-width 380] [min-height 30]
     [label "Parent button (should be blocked while dialog is open)"]
     [callback (lambda (b e) (printf "PARENT BUTTON CLICKED — should NOT print while dialog is open~n"))])

(new button% [parent frame-panel] [min-width 150] [min-height 30] [label "Open dialog"]
     [callback
      (lambda (b e)
        (define dlg (new dialog% [parent frame]
                          [label "list-box% + check-box% driver"]
                          [width 360] [height 320]))
        (define dlg-panel (new vertical-panel% [parent dlg]))
        (define lb (new list-box% [parent dlg-panel] [min-width 300] [min-height 150]
                        [label "Items:"]
                        [choices '("Alpha" "Beta" "Gamma" "Delta")]
                        [callback
                         (lambda (l ev)
                           (printf "list-box selection changed: ~a~n" (send l get-selections)))]))
        (define cb (new check-box% [parent dlg-panel] [min-width 200] [min-height 24]
                        [label "Enable feature X"]
                        [callback
                         (lambda (c ev)
                           (printf "check-box toggled: ~a~n" (send c get-value)))]))
        (define btn-panel (new horizontal-panel% [parent dlg-panel] [stretchable-height #f]))
        (new button% [parent btn-panel] [min-width 80] [min-height 28] [label "OK"]
             [callback (lambda (b e) (send dlg show #f))])
        (new button% [parent btn-panel] [min-width 80] [min-height 28] [label "Cancel"]
             [callback (lambda (b e) (send dlg show #f))])
        (send dlg show #t)
        (printf "dialog closed — final list-box selections=~a check-box value=~a~n"
                (send lb get-selections) (send cb get-value)))])

(send frame show #t)

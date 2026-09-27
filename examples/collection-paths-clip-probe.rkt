#lang racket/gui
; §60.4 root-cause probe (frame% variant -- see
; collection-paths-clip-probe-dialog.rkt for the fix-bearing dialog%
; variant, which is the faithful repro/regression test). This one uses a
; bare frame% with no explicit width/height, which surfaced a SEPARATE,
; still-open divergence noted alongside the real fix: under Qt, frame%/
; dialog% with no size args falls back to a hardcoded 400x300
; (wx/qt/frame.rkt:91-92) instead of auto-fitting to content like native
; cocoa does (which shrinks the frame down to exactly its content's
; min-size, e.g. 505x153 for this same tree). That fallback isn't the
; §60.4 root cause (the group-panel% chrome-delta bug, fixed in
; wx/qt/group-panel.rkt, is) -- it just means this particular probe doesn't
; reproduce clipping on its own (Qt's frame stays bigger than needed here),
; unlike the dialog%-based probe which matches module-language.rkt's actual
; container nesting (a non-stretchable wrapper panel) and does reproduce
; it. Kept as a probe for that frame%/dialog% auto-sizing divergence, not
; as the primary regression test for §60.4 itself.

(file-stream-buffer-mode (current-output-port) 'line)

(define frame (new frame% [label "Collection Paths Clip Probe"]))
(define outer (new vertical-panel% [parent frame]))

(define cp-panel (new group-box-panel% [parent outer] [label "Collection Paths"]))

(define lb
  (new list-box%
       [parent cp-panel]
       [choices '("<<default collection paths>>")]
       [label #f]
       [callback (lambda (x y) (void))]))

(define button-panel
  (new horizontal-panel% [parent cp-panel] [alignment '(center center)] [stretchable-height #f]))
(define add-button (new button% [parent button-panel] [label "Add"] [callback void]))
(define add-default-button (new button% [parent button-panel] [label "Add Default"] [callback void]))
(define remove-button (new button% [parent button-panel] [label "Remove"] [callback void]))
(define raise-button (new button% [parent button-panel] [label "Raise"] [callback void]))
(define lower-button (new button% [parent button-panel] [label "Lower"] [callback void]))

(send frame show #t)

(define (report)
  (printf "PLT_QT=~a\n" (getenv "PLT_QT"))
  (printf "frame:         ~ax~a\n" (send frame get-width) (send frame get-height))
  (printf "outer:         ~ax~a\n" (send outer get-width) (send outer get-height))
  (printf "cp-panel:      ~ax~a\n"
          (send cp-panel get-width) (send cp-panel get-height))
  (printf "list-box:      ~ax~a\n"
          (send lb get-width) (send lb get-height))
  (printf "button-panel:  ~ax~a\n"
          (send button-panel get-width) (send button-panel get-height))
  (printf "add-button:    ~ax~a\n"
          (send add-button get-width) (send add-button get-height))
  (define sum-children (+ (send lb get-height) (send button-panel get-height)))
  (printf "list-box.h + button-panel.h = ~a ; cp-panel.h = ~a ; diff (needed-vs-allocated) = ~a\n"
          sum-children (send cp-panel get-height) (- sum-children (send cp-panel get-height)))
  (flush-output))

; Give the eventspace thread time to settle initial layout before measuring.
(sleep 1)
(report)
(sleep 1)
(printf "---- second sample (after another second) ----\n")
(report)
(exit 0)

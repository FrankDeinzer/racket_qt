#lang racket/gui
; Companion to list-box-sizehint-probe.rkt (single-column §60.4 regression
; probe): verifies RacketTreeWidget's OWN sizeHint cap (§60.6) actually
; engages for the multi-column/tree path too -- neither the Package
; Manager probe above nor a `choices null` construction exercises this,
; since sizeHintForRow(0) is only meaningful once rows exist.

(define frame (new frame% [label "multi-column list-box sizeHint Probe"] [width 500 ] [height 220]))
(define panel (new vertical-panel% [parent frame]))

(define lb
  (new list-box%
       [label #f]
       [parent panel]
       [choices (for/list ([i (in-range 20)]) (format "row-~a" i))]
       [columns '("Name" "Note")]
       [style '(single column-headers)]))

(for ([i (in-range 20)]) (send lb set-string i (format "note ~a" i) 1))

(define button-panel (new horizontal-panel% [parent panel] [stretchable-height #f]))
(new button% [parent button-panel] [label "Add"])
(new button% [parent button-panel] [label "Remove"])
(new button% [parent button-panel] [label "Raise"])
(new button% [parent button-panel] [label "Lower"])

(send frame show #t)

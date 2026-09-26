#lang racket/gui
; Probe for list-box% sizeHint capping (docs/2026-09-26_prompt-macos.md):
; mirrors DrRacket's "Choose Language" Collection Paths panel -- a list-box%
; with many rows above a row of buttons, inside a small fixed-height frame.
; Before the fix, the list's seeded min-height (from Qt's unbounded
; QListWidget::sizeHint()) pushed the buttons out of the visible area.

(define frame (new frame% [label "list-box sizeHint Probe"] [width 400] [height 220]))
(define panel (new vertical-panel% [parent frame]))

(define lb
  (new list-box%
       [label #f]
       [parent panel]
       [choices (for/list ([i (in-range 20)]) (format "/some/long/path/entry-~a.rkt" i))]
       [style '(single)]))

(define button-panel (new horizontal-panel% [parent panel] [stretchable-height #f]))
(new button% [parent button-panel] [label "Add"])
(new button% [parent button-panel] [label "Remove"])
(new button% [parent button-panel] [label "Raise"])
(new button% [parent button-panel] [label "Lower"])

(send frame show #t)

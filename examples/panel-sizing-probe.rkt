#lang racket/gui
; Checkpoint-E, Fix A driver (2026-07-10-3_prompt): minimal repro for the
; wxitem.rkt make-item% seed bug (docs/HACKING.md §18.2) -- three plain
; button%s in a vertical-panel%, NO explicit [min-width]/[min-height], NO
; new widgets involved. Before the fix: all three land on top of each other
; (only the last-created is visible). After the fix: they stack vertically.

(define frame (new frame% [label "Panel-Sizing Probe"] [width 300] [height 220]))
(define panel (new vertical-panel% [parent frame]))

(new button% [parent panel] [label "Button ONE"])
(new button% [parent panel] [label "Button TWO"])
(new button% [parent panel] [label "Button THREE"])

(send frame show #t)

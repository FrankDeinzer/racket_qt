#lang racket/gui
(require framework)
; Isolated repro for the DrRacket "second File->Open -> new tab -> Internal
; Error dialog -> hard native crash" chain seen while validating file-selector
; (docs/2026-07-11_prompt.md macOS follow-up). The proximate trigger there was
; htdp-lib's test-tool.rkt calling (send parent get-percentages) then
; (send parent delete-child this) on a panel with only one live child -- NOT
; qt-backend code, out of scope to fix here. This script isolates only the
; qt-backend-relevant tail of that chain: delete-child on a panel, then GC
; pressure, then creating+showing a brand-new top-level frame (mimicking
; DrRacket's own internal-error dialog), to see whether the hard native crash
; reproduces WITHOUT the rest of DrRacket's stack.

(define frame (new frame% [label "Panel-Remove Crash Probe"] [width 400] [height 200]))
(define outer (new panel:vertical-dragable% [parent frame]))
(define child-a (new panel% [parent outer]))
(new message% [parent child-a] [label "child A"])
(define child-b (new panel% [parent outer]))
(new message% [parent child-b] [label "child B"])

(define status (new message% [parent frame] [label "(idle)"] [stretchable-width #t]))
(define (log! s) (printf "[probe] ~a\n" s) (flush-output) (send status set-label s))

(new button%
     [parent frame]
     [label "Repro: get-percentages + delete-child + GC + new frame"]
     [callback
      (lambda (b e)
        (log! "get-percentages...")
        (define pcts (send outer get-percentages))
        (printf "[probe] percentages=~a\n" pcts)
        (log! "delete-child child-b...")
        (send outer delete-child child-b)
        (log! "collect-garbage...")
        (collect-garbage)
        (log! "creating new top-level frame (mimics Internal Error dialog)...")
        (define popup (new frame% [label "Mimic: Internal Error"] [width 300] [height 150]))
        (new message% [parent popup] [label "some error text"])
        (send popup show #t)
        (log! "done -- popup should be visible, no crash if we got here"))])

(send frame show #t)

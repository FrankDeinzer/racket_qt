#lang racket/gui
; Checkpoint-E driver (2026-07-13-3_prompt): isolated tab-panel% probe.
; tab-panel% keeps exactly ONE wx-managed client area (docs/HACKING.md §21) --
; switching tabs does NOT swap native per-tab content, so this probe manages
; per-tab child panel visibility itself (show/hide), exactly mirroring how
; framework/private/preferences.rkt's make-tab/single-panel drives its own
; panel:single% off of tab-panel%'s callback + get-selection.
;
; Also exercises the "set-* must not re-trigger the callback" requirement,
; same convention as value-widgets-probe.rkt.

(file-stream-buffer-mode (current-output-port) 'line)

(define frame (new frame% [label "tab-panel% Driver"] [width 420] [height 360]))
(define outer (new vertical-panel% [parent frame]))

(new message% [parent outer]
     [label "Click tabs to switch; content below must follow the selection."])

(define tp (new tab-panel%
                 [choices '("Alpha" "Beta" "Gamma")]
                 [parent outer]
                 [callback
                  (lambda (t e)
                    (printf "tab-panel% callback fired: selection=~a (~a)~n"
                            (send t get-selection) (send t get-item-label (send t get-selection)))
                    (show-selected!))]))

; ---- per-tab child content --------------------------------------------
; Each pane is a direct child of tp (the single wx-managed client area);
; only the pane matching the current selection is shown.

(define pane-alpha (new vertical-panel% [parent tp]))
(new message% [parent pane-alpha] [label "Alpha content"])
(define alpha-clicks 0)
(new button% [parent pane-alpha] [label "Alpha button"]
     [callback (lambda (b e) (set! alpha-clicks (add1 alpha-clicks))
                 (printf "Alpha button clicked (~a)~n" alpha-clicks))])

(define pane-beta (new vertical-panel% [parent tp]))
(new message% [parent pane-beta] [label "Beta content"])
(new slider% [parent pane-beta] [label "Beta slider"] [min-value 0] [max-value 10] [init-value 3])

(define pane-gamma (new vertical-panel% [parent tp]))
(new message% [parent pane-gamma] [label "Gamma content"])
(new check-box% [parent pane-gamma] [label "Gamma checkbox"] [value #f])

(define panes (list pane-alpha pane-beta pane-gamma))

(define (show-selected!)
  (define sel (send tp get-selection))
  (for ([p (in-list panes)]
        [i (in-naturals)])
    (send p show (= i sel))))

; ---- "set via code must not re-trigger" buttons ------------------------

(define ctrl (new horizontal-panel% [parent outer]))

(new button% [parent ctrl] [label "set-selection 2 via code"]
     [callback (lambda (b e)
                 (send tp set-selection 2)
                 (show-selected!)
                 (printf "set-selection 2 done, now selection=~a~n" (send tp get-selection)))])

(new button% [parent ctrl] [label "set-item-label 0 -> 'Alpha!' via code"]
     [callback (lambda (b e)
                 (send tp set-item-label 0 "Alpha!")
                 (printf "set-item-label 0 done, now label=~a~n" (send tp get-item-label 0)))])

(new button% [parent ctrl] [label "append 'Delta' via code"]
     [callback (lambda (b e)
                 (send tp append "Delta")
                 (set! panes (append panes (list (new vertical-panel% [parent tp]))))
                 (new message% [parent (last panes)] [label "Delta content (appended)"])
                 (printf "append done, now count=~a~n" (send tp get-number)))])

(new button% [parent ctrl] [label "delete 1 (Beta) via code"]
     [callback (lambda (b e)
                 (send tp delete 1)
                 (define removed (list-ref panes 1))
                 (send removed show #f)
                 (set! panes (append (take panes 1) (drop panes 2)))
                 (show-selected!)
                 (printf "delete 1 done, now count=~a selection=~a~n"
                         (send tp get-number) (send tp get-selection)))])

(send frame show #t)
(show-selected!)
(printf "initial: count=~a selection=~a label0=~a~n"
        (send tp get-number) (send tp get-selection) (send tp get-item-label 0))

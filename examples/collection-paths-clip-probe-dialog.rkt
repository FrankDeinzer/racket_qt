#lang racket/gui
; §60.4 root-cause probe: mirrors DrRacket's "Choose Language" Collection
; Paths panel almost exactly -- a group-box-panel% (dialog%, non-stretchable
; wrapper, matching module-language.rkt's new-parent) containing a
; list-box% with ONE item above a horizontal-panel% with
; [stretchable-height #f] holding 5 buttons (Add/Add Default/Remove/Raise/
; Lower). Unlike list-box-sizehint-probe.rkt (many rows, already fixed via
; sizeHint cap), this is the ONE-row case that used to clip the button row
; under Qt.
;
; Root cause (confirmed via PLT_QT_DEBUG, see wx/qt/group-panel.rkt): at the
; very first do-get-graphical-min-size query (wxpanel.rkt), before any real
; set-size has ever run, group-panel%'s get-width/get-height read 0, so
; get-client-size's "(get-height) - t - b" clamps to 0 too, and
; do-graphical-size's delta-h ("get-height - client-h") collapses from the
; true (t+b) title/border chrome down to 0 -- silently starving cp-panel's
; reported min-height by exactly its title-bar height. Fixed by seeding a
; chrome-only size (zero content, just the margins) right after
; construction, mirroring win32's own group-panel% (which calls set-size
; directly in its constructor). Before the fix: cp-panel.h=144 for a
; children-sum of 140 (only 4px spare -- one bigger font away from
; clipping); after: cp-panel.h=169 (29px spare, matching the true t+b=25
; chrome + border). Prints get-height for every relevant widget after real
; placement so this is numeric, not eyeballed from a screenshot.
;
; Run once with PLT_QT=1, once without, and diff stdout.

(file-stream-buffer-mode (current-output-port) 'line)

(define frame (new dialog% [label "Collection Paths Clip Probe"]))
(define outer (new vertical-panel% [parent frame] [alignment (quote (center center))] [stretchable-height #f] [stretchable-width #f]))

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

; dialog% show #t is modal/blocking on the calling thread, so measure from a
; helper thread while the dialog is up, then close it. void'd so #lang
; racket/gui doesn't echo the thread object as a top-level result.
(void
 (thread
  (lambda ()
    (sleep 1)
    (report)
    (sleep 1)
    (printf "---- second sample (after another second) ----\n")
    (report)
    (queue-callback (lambda () (send frame show #f))))))

(send frame show #t)
(exit 0)

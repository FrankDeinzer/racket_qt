#lang racket/gui
; Probe for §61's get-dialog-level fix (wx/qt/window.rkt): every non-frame
; window used to report a hardcoded dialog-level of 0 instead of delegating
; to its parent (gtk/window.rkt:735, win32/window.rkt:855 always delegated).
; wx/common/queue.rkt's other-modal? compares a widget's get-dialog-level
; against the currently open dialog%'s own counter to decide whether to
; dispatch an event or swallow it -- a canvas%/editor-canvas% nested inside
; an open modal dialog% would see dl=0 < the dialog's real level, so its
; keyboard/mouse clicks were silently swallowed.
;
; This probe opens a modal dialog% containing a canvas%. Click inside the
; canvas and press a few keys while the dialog is open, then check the
; on-screen counters. Before the fix: both counters stay at 0 no matter how
; many clicks/keys are sent. After the fix: both counters increment.

(define counting-canvas%
  (class canvas%
    (init-field get-click-count get-key-count)
    (super-new)
    (define/override (on-event evt)
      (when (send evt button-down?)
        (get-click-count (add1 (get-click-count))))
      (send this refresh))
    (define/override (on-char evt)
      (get-key-count (add1 (get-key-count)))
      (send this refresh))))

; simple mutable-box-as-getter/setter helper so the paint-callback closure
; and the event overrides can share state without a class field dance here.
(define (make-counter)
  (define n 0)
  (case-lambda
    [() n]
    [(v) (set! n v)]))

(define main-frame (new frame% [label "get-dialog-level Probe"] [width 340] [height 120]))

(new button%
     [parent main-frame]
     [label "Open modal dialog, then click+type inside the canvas"]
     [callback
      (lambda (b e)
        (define clicks (make-counter))
        (define keys (make-counter))
        (define dlg (new dialog% [label "Modal child (click/type in the canvas below)"]
                          [width 360] [height 240]))
        (new message% [parent dlg] [label "Click and type inside the canvas below:"])
        (new counting-canvas%
             [parent dlg]
             [get-click-count clicks]
             [get-key-count keys]
             [style '(border)]
             [paint-callback
              (lambda (canvas dc)
                (send dc clear)
                (send dc draw-text
                      (format "clicks: ~a   keys: ~a" (clicks) (keys))
                      10 10))])
        (new button% [parent dlg] [label "Close"]
             [callback (lambda (b e) (send dlg show #f))])
        (send dlg show #t))])

(send main-frame show #t)

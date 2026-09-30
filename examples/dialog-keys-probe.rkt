#lang racket/gui
; Block D §2.1/§2.2: keyboard operation inside a dialog% (Tab traversal,
; Space on check-box, Enter = default button, Escape = cancel).
; Usage: [PLT_QT=1] racket examples/dialog-keys-probe.rkt LOGFILE
; Logs one line per interesting event; compare native vs Qt with the same
; xdotool sequence (see docs/2026-09-30_report-linux.md).
(define out (open-output-file (vector-ref (current-command-line-arguments) 0)
                              #:exists 'truncate))
(define (log! . xs) (fprintf out "~a\n" (apply format xs)) (flush-output out))
(define d (new dialog% [label "KeyDialog"] [width 320] [height 200]))
(define a (new text-field% [parent d] [label "A"]
               [callback (lambda (t e) (log! "A=~s" (send t get-value)))]))
(define b (new text-field% [parent d] [label "B"]
               [callback (lambda (t e) (log! "B=~s" (send t get-value)))]))
(define cb (new check-box% [parent d] [label "Check"]
                [callback (lambda (c e) (log! "check=~a" (send c get-value)))]))
(define lb (new list-box% [parent d] [label #f] [choices '("one" "two" "three")]
                [callback (lambda (l e) (log! "list=~a ~a" (send l get-selections) (send e get-event-type)))]))
(define row (new horizontal-panel% [parent d] [alignment '(right center)]))
(new button% [parent row] [label "Cancel"]
     [callback (lambda (b e) (log! "BUTTON Cancel") (send d show #f))])
(new button% [parent row] [label "OK"] [style '(border)]
     [callback (lambda (b e) (log! "BUTTON OK") (send d show #f))])
; Optional 2nd argument: programmatically focus a control before show
; (a|b|check|list|ok|cancel) -- Block D §2.1.
(define ctl-by-name
  (hash "a" a "b" b "check" cb "list" lb))
(define focus-arg
  (and (> (vector-length (current-command-line-arguments)) 1)
       (vector-ref (current-command-line-arguments) 1)))
(when (and focus-arg (hash-ref ctl-by-name focus-arg #f))
  (send (hash-ref ctl-by-name focus-arg) focus))
(log! "shown")
(send d show #t)
(log! "closed")

#lang racket/gui
;; set-focus-probe: (send w focus) must move focus for focusable controls.
;; Pass = frame get-focus-window is the widget (has-focus? is informational).
;; Labelled choice/radio/slider/list are skipped on purpose: gtk's label panel
;; dispatches focus to the (unfocusable) label message, so they are no-ops there too.
(define f (new frame% [label "focus-probe"]))
(define b  (new button% [parent f] [label "b"]))
(define c  (new check-box% [parent f] [label "c"]))
(define ch (new choice% [parent f] [label #f] [choices '("a" "b")]))
(define r  (new radio-box% [parent f] [label #f] [choices '("x" "y")] [selection 1]))
(define s  (new slider% [parent f] [label #f] [min-value 0] [max-value 10]))
(define l  (new list-box% [parent f] [label #f] [choices '("p" "q")]))
(define t  (new tab-panel% [parent f] [choices '("t1" "t2")]))
(define tf (new text-field% [parent f] [label "tf"]))
(define cv (new canvas% [parent f] [min-width 20] [min-height 20]))
(send f show #t)
(define (settle) (for ([i 30]) (sleep/yield 0.02)))
(settle)
(define fails 0)
(for ([w (list b c ch r s l t tf cv)] [n '(button check choice radio slider list tab text canvas)])
  (send w focus) (settle)
  (define ok (or (eq? n 'tab) ; tab-panel proxy identity differs on gtk too: informational
                 (eq? (send f get-focus-window) w)))
  (printf "~a: has-focus? ~a get-focus-window-eq ~a\n" n (send w has-focus?) (eq? (send f get-focus-window) w))
  (unless ok (set! fails (add1 fails))))
(printf "FAILS ~a\n" fails)
(exit 0)

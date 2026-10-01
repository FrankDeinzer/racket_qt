#lang racket/gui
;; Probe: frame% get-x/get-y/on-move/move gegen den echten Fensterort (X11).  Das Skript
;; tests/sweep/func-winpos.sh bewegt das Fenster von aussen (xdotool windowmove); hier wird bei jeder
;; Aenderung "POS x y" bzw. "ON-MOVE x y" ausgegeben.  Programmatisch: (send f move 300 200) nach 4 s.
(define f
  (new (class frame%
         (define/override (on-move x y) (printf "ON-MOVE ~a ~a\n" x y) (flush-output) (super on-move x y))
         (super-new [label "frame-position-probe"] [width 300] [height 200]))))
(send f show #t)
(define last #f)
(define (poll)
  (let ([p (list (send f get-x) (send f get-y))])
    (unless (equal? p last) (set! last p) (printf "POS ~a ~a\n" (car p) (cadr p)) (flush-output))))
(define t (new timer% [notify-callback poll] [interval 300]))
(sleep/yield 5)
(printf "MOVE 300 200\n") (send f move 300 200)
(sleep/yield (string->number (or (getenv "PROBE_WAIT") "12")))
(exit 0)

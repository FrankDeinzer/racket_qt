#lang racket/gui
;; display-changed (docs/COVERAGE.md, HACKING §83.3): frame% mit augmentiertem display-changed.  Protokoll auf stderr:
;; "display-changed <n> => (display-size w h)" je Aufruf; "start => (display-size w h)" beim Start.  Befehl auf stdin: X (beenden).
;; Treiber: tests/sweep/display-changed.sh (aendert per xrandr die Aufloesung und stellt sie wieder her).
(define n 0)
(define (sz) (let-values ([(w h) (get-display-size)]) (list w h)))
(define F (new (class frame%
                 (define/augment (display-changed) (set! n (add1 n)) (eprintf "display-changed ~a => ~s\n" n (sz)) (flush-output (current-error-port)))
                 (super-new [label "dc-probe"] [width 300] [height 120] [x 100] [y 80]))))
(send F show #t)
(eprintf "start => ~s\n" (sz)) (flush-output (current-error-port))
(void (thread (λ () (let loop () (define l (read-line)) (if (eof-object? l) (queue-callback (λ () (exit 0))) (begin (when (equal? (string-trim l) "X") (queue-callback (λ () (exit 0)))) (loop)))))))
(yield 'wait)

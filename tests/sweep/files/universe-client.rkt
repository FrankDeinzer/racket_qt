#lang racket
;; Client: racket universe-client.rkt NAME.  Zeigt "NAME: <zaehler> t<ticks>".
;; Space/Mausklick -> sendet 'inc.  "q" -> stop-with.  Marker in $SWEEP_MARK (Zeilen mit Name).
;; Tick-Statistik (Zeitstempel in ms) am Ende: 'ticks N 'elapsed-ms M.
(require 2htdp/universe 2htdp/image)
(define NAME (vector-ref (current-command-line-arguments) 0))
(define mark (or (getenv "SWEEP_MARK") "/dev/null"))
(define PORT (string->number (or (getenv "SWEEP_PORT") "17891")))
(define (log! . xs)
  (with-output-to-file mark #:exists 'append (lambda () (displayln (cons NAME xs)))))
(struct w (n ticks t0) #:transparent)
(define (draw s)
  (overlay (text (format "~a: ~a  t~a" NAME (w-n s) (w-ticks s)) 28 "black") (empty-scene 360 120)))
(define (tick s)
  (define t (add1 (w-ticks s)))
  (when (zero? (modulo t 10)) (log! 'tick t (inexact->exact (round (- (current-inexact-milliseconds) (w-t0 s))))))
  (w (w-n s) t (w-t0 s)))
(define (recv s m) (log! 'recv m) (w m (w-ticks s) (w-t0 s)))
(define (final s) (log! 'final (w-n s) 'ticks (w-ticks s)
                        'elapsed-ms (inexact->exact (round (- (current-inexact-milliseconds) (w-t0 s))))))
(log! 'start)
(define r
  (big-bang (w -1 0 (current-inexact-milliseconds))
    (name NAME)
    (register "127.0.0.1")
    (port PORT)
    (on-tick tick 0.1)
    (to-draw draw)
    (on-receive recv)
    (on-key (lambda (s k)
              (log! 'key k)
              (cond [(equal? k " ") (make-package s 'inc)]
                    [(equal? k "q") (stop-with s)]
                    [else s])))
    (on-mouse (lambda (s x y e)
                (cond [(equal? e "button-down") (log! 'click x y) (make-package s 'inc)] [else s])))
    ))
(final r)
(log! 'exit)

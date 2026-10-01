#lang racket
(require 2htdp/universe 2htdp/image)
(define mark (or (getenv "SWEEP_MARK") "/dev/null"))
(define (log! . xs)
  (with-output-to-file mark #:exists 'append (lambda () (displayln xs))))
(define (draw n)
  (overlay (text (number->string n) 36 "black")
           (empty-scene 240 120)))
(big-bang 0
  (on-tick add1 0.2)
  (to-draw draw)
  (on-key (lambda (w k) (log! 'key k) (if (equal? k "q") (begin (log! 'final w) (stop-with 'done)) w)))
  (on-mouse (lambda (w x y e) (when (equal? e "button-down") (log! 'click x y)) w)))

#lang racket
(define mk (getenv "SWEEP_MARK"))
(define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))
(define (work) (for/sum ([i (in-range 3)]) (fib 22)))
(define r (work))
(with-output-to-file mk #:exists 'truncate (lambda () (displayln r)))
r

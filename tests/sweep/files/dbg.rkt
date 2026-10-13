#lang racket
(define mk (getenv "SWEEP_MARK"))
(define (note s) (with-output-to-file mk #:exists 'append (lambda () (displayln s))))
(define (g y) (+ y 100))
(define (f x) (note (format "f ~a" x)) (g (* x 2)))
(note "start")
(define a (f 1))
(define b (f 2))
(note (format "end ~a ~a" a b))

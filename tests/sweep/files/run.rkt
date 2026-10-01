#lang racket
(call-with-output-file (or (getenv "SWEEP_MARK") "/dev/null") #:exists 'truncate
  (lambda (o) (displayln "ran" o)))
(define (f x) (* x x))
(f 12)
(display "hello\n")
(eprintf "err-output\n")
(list 1 2 3)

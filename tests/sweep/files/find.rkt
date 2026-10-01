#lang racket
(define foo 1)
(define bar foo)
(+ foo bar foo)
;; foo foo

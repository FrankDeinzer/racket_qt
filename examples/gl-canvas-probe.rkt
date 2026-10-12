#lang racket/gui
;; 'gl canvas triage probe (HACKING §70).
(define f (new frame% [label "gl"] [width 300] [height 200]))
(define c (new canvas% [parent f] [style '(gl)] [gl-config (let ([g (new gl-config%)]) g)]))
(send f show #t)
(sleep/yield 1)
(printf "gl-context: ~a\n" (send (send c get-dc) get-gl-context))
(printf "with-gl-context: ~a\n"
        (with-handlers ([void (lambda (e) (format "error: ~a" (exn-message e)))])
          (send c with-gl-context (lambda () 'ok))))
(flush-output)
(send f show #f)

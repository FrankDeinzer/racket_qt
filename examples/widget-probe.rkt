#lang racket/gui
; Systematic widget probe for Checkpoint E-0.
; Each widget wrapped in with-handlers so one crash doesn't stop the rest.
(define frame (new frame% [label "Widget Probe"] [width 500] [height 600]))

(define (try-widget name thunk)
  (with-handlers ([exn:fail?
                   (lambda (e)
                     (printf "CRASH ~a: ~a~n" name (exn-message e)))])
    (thunk)
    (printf "OK    ~a~n" name)))

; message% — already verified OK
(try-widget "message%"
  (lambda ()
    (new message% [label "Static text"] [parent frame])))

; check-box%
(try-widget "check-box%"
  (lambda ()
    (new check-box% [label "Check me"] [parent frame]
         [callback (lambda (c e) (void))])))

; choice%
(try-widget "choice%"
  (lambda ()
    (new choice% [label "Pick"] [parent frame]
         [choices '("A" "B" "C")]
         [callback (lambda (c e) (void))])))

; list-box%
(try-widget "list-box%"
  (lambda ()
    (new list-box% [label "List"] [parent frame]
         [choices '("One" "Two" "Three")]
         [callback (lambda (c e) (void))])))

; slider%
(try-widget "slider%"
  (lambda ()
    (new slider% [label "Volume"] [parent frame]
         [min-value 0] [max-value 100] [init-value 50]
         [callback (lambda (s e) (void))])))

; radio-box%
(try-widget "radio-box%"
  (lambda ()
    (new radio-box% [label "Options"] [parent frame]
         [choices '("Alpha" "Beta" "Gamma")]
         [callback (lambda (r e) (void))])))

; tab-panel%
(try-widget "tab-panel%"
  (lambda ()
    (new tab-panel% [choices '("Tab1" "Tab2")] [parent frame]
         [callback (lambda (t e) (void))])))

; text-field%
(try-widget "text-field%"
  (lambda ()
    (new text-field% [label "Name:"] [parent frame])))

(send frame show #t)
(sleep/yield 2)
(send frame show #f)

#lang racket/gui
; D-1 raco test smoke: instantiate every implemented platform class,
; show the frame, pump N events, close cleanly. Any exception = fail.
;
; Run: PLT_QT=1 raco test tests/smoke.rkt

(require rackunit)

(define PUMP-CYCLES 20)

; Yield to the eventspace handler so queued events (timer callbacks,
; expose callbacks, etc.) get processed.  sleep alone is insufficient
; from the handler thread — we also need explicit yield.
(define (pump-n n)
  (for ([_ (in-range n)])
    (sleep 0.01)
    (yield)))   ; yield to Qt pump thread

(test-case "frame% + canvas% + button% instantiate and show"
  (define frame (new frame% [label "smoke"] [width 300] [height 200]))
  (define canvas
    (new canvas%
         [parent frame]
         [paint-callback (lambda (c dc) (send dc clear))]))
  (define button
    (new button% [label "ok"] [parent frame] [callback (lambda (b e) (void))]))
  (send frame show #t)
  (pump-n PUMP-CYCLES)
  (check-true (send frame is-shown?))
  (send frame show #f)
  (pump-n 5)
  (check-false (send frame is-shown?)))

(test-case "timer% fires in eventspace"
  (define count 0)
  (define t
    (new timer%
         [notify-callback (lambda () (set! count (add1 count)))]
         [interval 20]))
  (pump-n 10)
  (send t stop)
  ; After ~200ms the timer should have fired several times.
  ; Require at least 1 firing (avoids flakiness on slow CI).
  (check > count 0))

(test-case "input-canvas% subclass compiles and instantiates"
  (define my-canvas%
    (class canvas%
      (define/override (on-event e) (void))
      (define/override (on-char  e) (void))
      (super-new)))
  (define frame (new frame% [label "input-smoke"] [width 200] [height 200]))
  (define c (new my-canvas% [parent frame]))
  (send frame show #t)
  (pump-n PUMP-CYCLES)
  (send frame show #f)
  (check-true #t))

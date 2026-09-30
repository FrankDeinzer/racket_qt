#lang racket/gui
; Free-test finding (2026-09-30): DrRacket's file-name dropdown (mrlib/name-message.rkt)
; does nothing under Qt.  Its on-event does `(refresh)` then `(yield paint-sema)` --
; waiting INSIDE the event handler for on-paint to post the semaphore -- before it
; pops the menu up.  This probe reproduces exactly that wait.
; Usage: [PLT_QT=1] racket examples/yield-paint-probe.rkt LOGFILE
; Click the canvas once.  Expected log: down, paint, yielded, popup-done.
(define out (open-output-file (vector-ref (current-command-line-arguments) 0)
                              #:exists 'truncate))
(define (log! s) (fprintf out "~a\n" s) (flush-output out))
(define sema #f)
(define pm (new popup-menu%))
(new menu-item% [parent pm] [label "item"] [callback (lambda (i e) (log! "item"))])
(define c%
  (class canvas%
    (inherit refresh popup-menu)
    (define/override (on-paint)
      (log! (format "paint ~ax~a" (send this get-width) (send this get-height)))
      (when sema (semaphore-post sema)))
    (define/override (on-event e)
      (log! (format "event ~a" (send e get-event-type)))
      (when (send e button-down?)
        (log! "down")
        (set! sema (make-semaphore))
        (refresh)
        (yield sema)
        (set! sema #f)
        (log! "yielded")
        (popup-menu pm 0 20)
        (log! "popup-done")))
    (super-new)))
(define f (new frame% [label "YieldProbe"] [width 300] [height 120]))
(new c% [parent f])
(send f show #t)

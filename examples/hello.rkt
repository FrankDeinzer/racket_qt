#lang racket/gui
; Hello-world smoke test for the Qt backend.
; Run with: PLT_QT=1 racket examples/hello.rkt

(define click-count 0)

(define frame
  (new frame%
       [label "Hello Qt"]
       [width 400]
       [height 300]))

(define canvas
  (new canvas%
       [parent frame]
       [paint-callback
        (lambda (c dc)
          (send dc set-background (make-object color% 30 30 50))
          (send dc clear)
          (send dc set-text-foreground (make-object color% 255 220 50))
          (send dc set-font (make-object font% 24 'default 'normal 'bold))
          (send dc draw-text "Hello, Qt!" 80 80)
          (send dc set-font (make-object font% 14 'default 'normal 'normal))
          (send dc set-text-foreground (make-object color% 180 180 255))
          (send dc draw-text (format "Clicks: ~a" click-count) 80 130))]))

(define button
  (new button%
       [label "Click me"]
       [parent frame]
       [callback
        (lambda (b e)
          (set! click-count (add1 click-count))
          (send canvas refresh))]))

(send frame show #t)

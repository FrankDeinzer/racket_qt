#lang racket/gui
; §73: Return with focus on a radio-box% inside a dialog% (DrRackets "Choose Language" starts there).
; Usage: [PLT_QT=1] racket examples/dialog-radio-return-probe.rkt LOGFILE [radio|ok]
(define out (open-output-file (vector-ref (current-command-line-arguments) 0) #:exists 'truncate))
(define (log! . xs) (fprintf out "~a\n" (apply format xs)) (flush-output out))
(define d (new dialog% [label "KeyDialog"] [width 320] [height 200]))
(define r (new radio-box% [parent d] [label #f] [choices '("One" "Two")]
               [callback (lambda (r e) (log! "radio=~a" (send r get-selection)))]))
(define row (new horizontal-panel% [parent d] [alignment '(right center)]))
(new button% [parent row] [label "Cancel"] [callback (lambda (b e) (log! "BUTTON Cancel") (send d show #f))])
(define ok (new button% [parent row] [label "OK"] [style '(border)]
                [callback (lambda (b e) (log! "BUTTON OK") (send d show #f))]))
(when (equal? (vector-ref (current-command-line-arguments) 1) "radio") (send r focus))
(log! "shown")
(send d show #t)
(log! "closed")

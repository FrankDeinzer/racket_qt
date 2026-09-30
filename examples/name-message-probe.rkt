#lang racket/gui
; Free-test finding (2026-09-30): DrRacket's file-name dropdown (mrlib/name-message.rkt)
; does not open under Qt.  This probe uses the REAL name-message% and logs its steps
; (subclass hooks only; the library is untouched).
; Usage: [PLT_QT=1] racket examples/name-message-probe.rkt LOGFILE
(require mrlib/name-message)
(define out (open-output-file (vector-ref (current-command-line-arguments) 0)
                              #:exists 'truncate))
(define (log! . xs) (fprintf out "~a\n" (apply format xs)) (flush-output out))
(define nm%
  (class name-message%
    (define/override (on-event e)
      (log! "event ~a" (send e get-event-type))
      (super on-event e)
      (log! "event ~a returned" (send e get-event-type)))
    (define/override (fill-popup menu reset)
      (log! "fill-popup")
      (super fill-popup menu reset))
    (define/override (on-paint)
      (log! "paint")
      (super on-paint))
    (super-new)))
(define f (new frame% [label "NameMsgProbe"] [width 400] [height 120]))
(define row (new horizontal-panel% [parent f] [stretchable-height #f]))
(define nm (new nm% [parent row] [label "file.rkt"]))
(send nm set-message #t (build-path (current-directory) "examples" "name-message-probe.rkt"))
(new canvas% [parent f])
(send f show #t)

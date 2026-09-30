#lang racket/gui
; Block D §1.1: logs every key-event% reaching a canvas% (fields as Racket
; sees them).  Usage: [PLT_QT=1] racket examples/key-probe.rkt LOGFILE
; Compare native (gtk) vs PLT_QT=1 with the same xdotool sequence.
(define log-path (vector-ref (current-command-line-arguments) 0))
(define out (open-output-file log-path #:exists 'truncate))
(define (show v) (if (char? v) (format "~s" v) (format "~a" v)))
(define probe%
  (class canvas%
    (define/override (on-char e)
      (fprintf out "~a\n"
               (string-join
                (list (show (send e get-key-code))
                      (show (send e get-key-release-code))
                      (format "S~a C~a M~a A~a K~a" 
                              (if (send e get-shift-down) 1 0)
                              (if (send e get-control-down) 1 0)
                              (if (send e get-meta-down) 1 0)
                              (if (send e get-alt-down) 1 0)
                              (if (send e get-caps-down) 1 0))
                      (format "oS=~a oAG=~a oSAG=~a oC=~a"
                              (show (send e get-other-shift-key-code))
                              (show (send e get-other-altgr-key-code))
                              (show (send e get-other-shift-altgr-key-code))
                              (show (send e get-other-caps-key-code))))
                " | "))
      (flush-output out))
    (define/override (on-focus on?)
      (fprintf out "FOCUS ~a\n" (if on? "in" "out")) (flush-output out))
    (super-new)))
(define f (new frame% [label "KeyProbe"] [width 300] [height 200]))
(define mb (new menu-bar% [parent f]))
(define m (new menu% [label "Edit"] [parent mb]))
(new menu-item% [label "Item"] [parent m] [callback void])
(define c (new probe% [parent f]))
(send f show #t)
(send c focus)

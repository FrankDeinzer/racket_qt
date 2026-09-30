#lang racket/gui
; Block D §2.5: an item inside a submenu of a standalone popup-menu% must fire.
; Usage: [PLT_QT=1] racket examples/popup-submenu-probe.rkt LOGFILE
; Right-click the canvas, then keyboard: Down, Right, Return -> logs "leaf".
(define out (open-output-file (vector-ref (current-command-line-arguments) 0)
                              #:exists 'truncate))
(define (log! s) (fprintf out "~a\n" s) (flush-output out))
(define f (new frame% [label "PopupSub"] [width 300] [height 200]))
(define pm (new popup-menu%))
(new menu-item% [parent pm] [label "Top item"] [callback (lambda (i e) (log! "top"))])
(define sub (new menu% [parent pm] [label "Sub"]))
(new menu-item% [parent sub] [label "Leaf"] [callback (lambda (i e) (log! "leaf"))])
(define c (new (class canvas%
                 (define/override (on-event e)
                   (when (eq? (send e get-event-type) 'right-down)
                     (send this popup-menu pm (send e get-x) (send e get-y))))
                 (super-new))
               [parent f]))
(send f show #t)

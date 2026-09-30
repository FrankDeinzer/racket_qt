#lang racket/gui
; Free-test finding (2026-09-30): DrRacket's tab bar never appears under Qt when a
; second file is opened.  DrRacket creates its tab-panel% with '(deleted ...) inside a
; vertical-pane% and adds it with `change-children` once there is more than one tab
; (drracket/private/unit.rkt ~2310).  This probe reproduces that pattern.
; Usage: [PLT_QT=1] racket examples/tab-bar-deleted-probe.rkt LOGFILE
; Logs sizes/visibility before and after the change-children; a screenshot shows
; whether the tab bar is painted.
(define out (open-output-file (vector-ref (current-command-line-arguments) 0)
                              #:exists 'truncate))
(define (log! . xs) (fprintf out "~a\n" (apply format xs)) (flush-output out))
(define f (new frame% [label "TabBarProbe"] [width 500] [height 300]))
(define pane (new vertical-pane% [parent f]))
(define tabs
  (new tab-panel% [parent pane] [choices '("1: a.rkt" "2: b.rkt")]
       [style '(deleted no-border can-close new-button)]
       [stretchable-height #f] [callback void]))
(define body (new canvas% [parent pane]))
(define (report what)
  (log! "~a: tabs shown?=~a size=~ax~a children=~a"
        what (send tabs is-shown?) (send tabs get-width) (send tabs get-height)
        (length (send pane get-children))))
(send f show #t)
(sleep/yield 1)
(report "before")
(send pane change-children (lambda (l) (cons tabs l)))
(sleep/yield 1)
(report "after")

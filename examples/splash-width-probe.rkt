#lang racket/gui
;; Free test 2026-10-01: the splash screen (framework/splash.rkt) is a dialog%
;; holding a non-stretchable vertical-pane with a 310x300 canvas and a gauge.
;; Qt showed 400 px wide (grey bars left/right); native fits the content.
(define d (new dialog% [label "splash-probe"] [style '(close-button)]))
(define p (new vertical-pane% [parent d]))
(define c (new canvas% [parent p] [min-width 310] [min-height 300] [style '(no-autoclear)]))
(define gp (new horizontal-pane% [parent p]))
(void (new gauge% [label #f] [range 100] [parent gp] [style '(horizontal)]))
(send d set-alignment 'center 'center)
(send p stretchable-width #f)
(send p stretchable-height #f)
(send c stretchable-width #f)
(send c stretchable-height #f)
(thread (lambda () (sleep 4) (define-values (w h) (send d get-size)) (printf "dialog size ~ax~a\n" w h) (flush-output) (exit)))
(send d show #t)

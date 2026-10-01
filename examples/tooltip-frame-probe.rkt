#lang racket/gui
;; Probe: DrRackets tooltip-frame% (style no-caption float, parent = Hauptframe) muss nach
;; show-over sichtbar sein, plausible Groesse haben und neben (x+w, y+h) liegen.
(require drracket/private/tooltip)
(define f (new frame% [label "tt-main"] [width 400] [height 300]))
(send f show #t)
(sleep/yield 1)
(define t (new tooltip-frame% [frame-to-track f]))
(send t set-tooltip '("imported from racket"))
(define-values (fx fy) (send f client->screen 0 0))
(send t show-over (+ fx 100) (+ fy 100) 20 20)
(sleep/yield 0.5)
(printf "main: x=~a y=~a client->screen=~a size=~ax~a\n" (send f get-x) (send f get-y) (call-with-values (λ () (send f client->screen 0 0)) list) (send f get-width) (send f get-height))
(define-values (tx ty) (send t client->screen 0 0))
(printf "tooltip shown?=~a size=~ax~a pos=~a,~a (erwartet ~a,~a)\n"
        (send t is-shown?) (send t get-width) (send t get-height) tx ty (+ fx 120) (+ fy 120))
(define ok (and (send t is-shown?) (> (send t get-width) 40) (> (send t get-height) 10)
                (<= (abs (- tx (+ fx 120))) 5) (<= (abs (- ty (+ fy 120))) 5)))
(printf "~a\n" (if ok "PASS" "FAIL"))
(sleep/yield (string->number (or (getenv "PROBE_HOLD") "0")))
(exit (if ok 0 1))

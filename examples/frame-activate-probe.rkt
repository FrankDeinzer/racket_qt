#lang racket/gui
(require racket/system)
;; Probe: frame%-on-activate muss beim Aktivieren/Deaktivieren des Fensters feuern (DrRackets
;; Check-Syntax-Tooltips werden NUR in on-activate eingeschaltet).  Braucht X11 + xdotool.
(define log '())
(define f (new (class frame%
                 (define/override (on-activate a?) (set! log (cons a? log)) (super on-activate a?))
                 (super-new [label "act-probe"] [width 300] [height 200]))))
(define c (new canvas% [parent f]))
(send f show #t)
(send c focus)
(sleep/yield 1)
(system "xdotool search --name '^act-probe$' windowactivate" )
(sleep/yield 1.5)
(printf "on-activate-Aufrufe nach Aktivieren: ~a \n" (reverse log))
(define ok (and (memq #t log) #t))
(printf "~a\n" (if ok "PASS" "FAIL"))
(exit (if ok 0 1))

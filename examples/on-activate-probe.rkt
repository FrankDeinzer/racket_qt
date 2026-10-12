#lang racket/gui
(require racket/system)
;; Probe (docs/HACKING.md §69): on-activate fuer Fenster OHNE fokussierbares Kind.
;; Zwei Frames mit nur einem message%; per xdotool windowactivate (nur Fenster dieser
;; Probe, keine Tasten) wechselt die Aktivierung.  Erwartet: A: (#t #f #t), B: (#t #f)
;; ohne Doppelmeldungen.  Vergleich: gtk (ohne PLT_QT) vs. PLT_QT=1.  Braucht X11 + xdotool.
(define (mk name)
  (define log '())
  (define f (new (class frame%
                   (define/override (on-activate a?) (set! log (cons a? log)) (super on-activate a?))
                   (super-new [label name] [width 260] [height 120]))))
  (new message% [parent f] [label name])
  (values f (lambda () (reverse log))))
(define (act name)
  (system (format "xdotool search --name '^~a$' windowactivate" name))
  (sleep/yield 1.2))
(define-values (a la) (mk "oa-probe-A"))
(define-values (b lb) (mk "oa-probe-B"))
(send a show #t) (sleep/yield 1)
(send b show #t) (sleep/yield 1)
(act "oa-probe-A")
(act "oa-probe-B")
(act "oa-probe-A")
(printf "A: ~a\nB: ~a\n" (la) (lb))
(define (no-dups? l) (for/and ([x l] [y (if (null? l) l (cdr l))]) (not (eq? x y))))
(define ok (and (pair? (la)) (pair? (lb)) (memq #t (la)) (memq #t (lb)) (memq #f (la))
                (no-dups? (la)) (no-dups? (lb)) (eq? #t (last (la)))))
(printf "~a\n" (if ok "PASS" "FAIL"))
(exit (if ok 0 1))

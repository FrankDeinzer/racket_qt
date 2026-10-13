#lang racket/gui
;; Datei-Drop (docs/COVERAGE.md, HACKING §83.2): frame% mit accept-drop-files + zwei canvas%
;; (eines akzeptiert Drops selbst, eines nicht).  Protokoll auf stderr: "drop <ziel> => <dateiname>"
;; (nur der Dateiname, Verzeichnis egal).  stdout "POS <name> x y w h" (Screen-Koordinaten) auf Befehl "P".
;; Befehle auf stdin: P (Positionen), X (beenden).  Treiber: tests/sweep/dnd-drop.sh (Xdnd-Quelle: tests/sweep/dnd-source.py)
;; Manueller Pruefpunkt (ohne Treiber): racket examples/drop-probe.rkt, Datei aus Dolphin auf das Fenster ziehen;
;; erwartet je abgelegter Datei eine Zeile "drop frame|canvas-accept => name" (Ziel = Bereich, auf den abgelegt wurde).
(define (nm p) (let-values ([(b n d) (split-path p)]) (path->string n)))
(define (log! who p) (eprintf "drop ~a => ~a\n" who (nm p)) (flush-output (current-error-port)))
(define F (new (class frame%
                 (define/override (on-drop-file p) (log! 'frame p))
                 (super-new [label "dnd-target"] [x 100] [y 80]))))
(send F accept-drop-files #t)
(define panel (new horizontal-panel% [parent F]))
(define ca (new (class canvas% (define/override (on-drop-file p) (log! 'canvas-accept p)) (super-new))
                [parent panel] [min-width 200] [min-height 160] [style '(border)]))
(send ca accept-drop-files #t)
(define cn (new canvas% [parent panel] [min-width 200] [min-height 160] [style '(border)]))
(define msg (new message% [parent F] [label "frame area (message%, no own drop target)"] [stretchable-width #t]))
(eprintf "accept? frame=~a canvas-accept=~a canvas-plain=~a\n" (send F accept-drop-files) (send ca accept-drop-files) (send cn accept-drop-files))
(define (print-pos)
  (for ([p (list (cons 'canvas-accept ca) (cons 'canvas-plain cn) (cons 'msg msg))])
    (define-values (sx sy) (send (cdr p) client->screen 0 0))
    (define-values (w h) (if (is-a? (cdr p) canvas%) (send (cdr p) get-client-size) (values (send (cdr p) get-width) (send (cdr p) get-height))))
    (printf "POS ~a ~a ~a ~a ~a\n" (car p) sx sy w h))
  (printf "POS frame-ready\n") (flush-output))
(send F show #t)
(void (thread (λ () (let loop ()
                (define l (read-line))
                (cond [(eof-object? l) (queue-callback (λ () (exit 0)))]
                      [else (queue-callback (λ () (case (string-trim l) [("P") (print-pos)] [("X") (exit 0)]))) (loop)])))))
(yield 'wait)

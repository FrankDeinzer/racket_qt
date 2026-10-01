#lang racket/gui
;; Probe: editor-canvas% mit eigenem on-paint, das VOR super on-paint ein Rechteck zeichnet
;; (DrRackets searchable-canvas% faerbt so das Suchfeld bei 0 Treffern rosa).  Qt zeigte kein Rosa; red? wird erst nach 3 s gesetzt + refresh (set-red-Muster).
(define pink (make-object color% 255 192 203))
(define red? #f)
(define ec%
  (class editor-canvas%
    (inherit get-dc get-client-size)
    (define/override (on-paint)
      (when red?
        (let ([dc (get-dc)])
          (let-values ([(cw ch) (get-client-size)])
            (send dc set-pen "black" 1 'transparent)
            (send dc set-brush pink 'solid)
            (send dc draw-rectangle 0 0 cw ch))))
      (super on-paint))
    (super-new)))
(define f (new frame% [label "pink-probe"] [width 300] [height 60]))
(define t (new text%))
(send t insert "foo")
(define c (new ec% [parent f] [editor t] [style '(no-hscroll no-vscroll)]))
(send f show #t)
(sleep/yield 3)
(set! red? #t)
(send c refresh)
(sleep/yield 11)
(exit 0)

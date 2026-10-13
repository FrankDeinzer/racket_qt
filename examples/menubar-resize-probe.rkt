#lang racket/gui
;; Probe (HACKING §80): gtks set-menu-bar ruft `resized`, damit ein Frame nicht um die
;; Menueleistenhoehe waechst.  Gemeldet wird die Frame-/Client-Groesse eines Frames ohne explizite
;; Groesse mit/ohne Menueleiste (nativ == Qt erwartet; die Differenz Frame-Client = Chrome).
(define (measure with-menu?)
  (define f (new frame% [label "mb-probe"]))
  (when with-menu?
    (define mb (new menu-bar% [parent f]))
    (new menu% [parent mb] [label "File"]))
  (define c (new canvas% [parent f] [min-width 200] [min-height 100]))
  (send f show #t)
  (sleep/yield 1)
  (define-values (cw ch) (send f get-client-size))
  (begin0 (list (send f get-width) (send f get-height) cw ch (send c get-width) (send c get-height))
          (send f show #f)))
(printf "ohne Menue: ~a\n" (measure #f))
(printf "mit Menue : ~a\n" (measure #t))
(exit 0)

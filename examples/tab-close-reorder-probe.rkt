#lang racket/gui
;; tab-panel% 'can-close / 'can-reorder.  Click a tab's [x] -> "close-request i",
;; the tab is then deleted here; drag a tab -> "reorder (...)".  Run with and
;; without PLT_QT=1 and compare.
(define f (new frame% [label "tab-probe"] [width 420] [height 160]))
(define tp
  (new (class tab-panel%
         (define/override (on-close-request i)
           (printf "close-request ~a\n" i) (flush-output)
           (send this delete i))
         (define/augment (on-reorder pos)
           (printf "reorder ~s sel=~a\n" pos (send this get-selection)) (flush-output))
         (super-new))
       [parent f] [choices '("one" "two" "three")]
       [style '(can-reorder can-close)]
       [callback (lambda (t e) (printf "select ~a\n" (send t get-selection)) (flush-output))]))
(void (new message% [parent tp] [label "content"]))
(send f show #t)

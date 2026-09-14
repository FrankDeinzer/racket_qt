#lang racket/base
;; Probe fuer docs/HACKING.md §35 -- uebereinander gezeichnete Toolbar-Controls.
;;
;; Baut die Schachtelung nach, die DrRacket beim Start erzeugt
;; (htdp-lib/test-engine/test-tool.rkt:100-103):
;;
;;   outer vertical-panel%
;;     +-- sichtbarer vertical-pane%  -> Button "SICHTBAR"
;;     +-- vertical-panel% '(deleted) -> horizontal-panel% -> Button "STRAY"
;;
;; Erwartung (nativ/GTK, win32): das '(deleted)-Panel und alles darin bleibt
;; unsichtbar, bis es per add-child eingehaengt wird. Die Frage der Probe ist,
;; ob unter Qt der Button "STRAY" trotzdem gezeichnet wird -- und wenn ja, an
;; welcher Stelle.
;;
;; Aufruf:
;;   PLT_QT=1 QT_PLUGIN_PATH=... ~/racket/bin/racket examples/deleted-style-probe.rkt
;;   (ohne PLT_QT fuer den Nativ-Vergleich)
(require racket/gui/base racket/class
         "pump-gate.rkt")

(define f (new frame% [label "deleted-style-probe"] [width 520] [height 260]))

(define outer (new vertical-panel% [parent f]))

(define visible-pane (new vertical-panel% [parent outer]))
(define b-visible (new button% [parent visible-pane] [label "SICHTBAR"]))

;; Genau das Konstrukt aus test-tool.rkt: ein Panel mit '(deleted), dessen
;; Kinder OHNE 'deleted erzeugt werden.
(define dead-panel (new vertical-panel% [parent outer] [style '(deleted)]))
(define dead-inner (new horizontal-panel% [parent dead-panel]))
(define b-stray (new button% [parent dead-inner] [label "STRAY"]))

;; Sonderfall canvas%: qt-canvas-scroll-mixin erzeugt Content-Widget und
;; QScrollBars ERST NACH window%s super-new (§33/§34), also nachdem ein
;; Hide-on-Create gelaufen waere. Der Canvas hier traegt SELBST kein 'deleted
;; (dann waere Unsichtbarkeit ja korrekt) -- er sitzt nur in einem
;; '(deleted)-Panel, genau wie der Test-Report-Canvas in test-tool.rkt:219.
;; Nach dem Einhaengen des Panels muss er samt Scrollbars da sein; ein
;; Scroll-Canvas, dessen Scrollbars nach dem Andocken fehlen, waere ein
;; Defekt, den keine der anderen Wachen sehen wuerde.
(define dead-canvas
  (new editor-canvas% [parent dead-panel] [style '(auto-hscroll auto-vscroll)]))
(define dead-text (new text%))
(for ([i (in-range 60)])
  (send dead-text insert
        (format "CANVAS-Zeile ~a -- absichtlich breit genug fuer einen Hscrollbar\n" i)))
(send dead-canvas set-editor dead-text)

(send f show #t)
(pump-gate!)
(wait/pump 2)

(define (report name w)
  (eprintf "[probe] ~a  is-shown?=~a  x=~a y=~a w=~a h=~a\n"
           name (send w is-shown?)
           (send w get-x) (send w get-y)
           (send w get-width) (send w get-height)))

(report "frame       " f)
(report "outer       " outer)
(report "visible-pane" visible-pane)
(report "b-visible   " b-visible)
(report "dead-panel  " dead-panel)
(report "dead-inner  " dead-inner)
(report "b-stray     " b-stray)
(report "dead-canvas " dead-canvas)

;; Zweite Phase: das '(deleted)-Panel nachtraeglich einhaengen -- genau das, was
;; test-tool.rkt's display-test-panel beim Andocken des Test-Reports tut
;; (add-child auf den Elterncontainer). Danach MUSS "STRAY" sichtbar werden;
;; sonst haette ein Hide-on-Create den Dock-Pfad kaputtgemacht.
(when (getenv "PROBE_ADD")
  (eprintf "[probe] --- add-child dead-panel ---\n")
  (send outer add-child dead-panel)
  (wait/pump 1)
  (report "dead-panel  " dead-panel)
  (report "b-stray     " b-stray)
  (report "dead-canvas " dead-canvas))

(wait/pump (if (getenv "PROBE_HOLD") 20 1))
(eprintf "[probe] done\n")
(send f show #f)

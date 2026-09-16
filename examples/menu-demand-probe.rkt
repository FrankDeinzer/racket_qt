#lang racket/gui
;; Probe fuer docs/HACKING.md §37 -- Menu-Enable/Check-States werden vor dem
;; Oeffnen eines Menues nicht nachgefuehrt (Folgebefund aus §34.7: DrRackets
;; Tabs-Menu "Previous/Next Tab" bleibt ausgegraut, Edit-Menu Copy/Cut
;; ebenso, s. docs/2026-09-16_report-linux.md). Root-Cause: wx/qt/frame.rkt
;; definierte on-menu-click nur als Stub (korrekt fuer die override*-Pflicht
;; aus CLAUDE.md Regel 3), aber nichts rief ihn je auf -- win32 hookt
;; WM_INITMENU, gtk die GtkMenuItem-"select"-Signale. Qt-Aequivalent ist
;; QMenu::aboutToShow, jetzt in shim_menu_create/shim_menu_set_about_to_show_cb
;; verdrahtet.
;;
;; Qt-spezifisch (requirt wx/qt/menu-bar direkt fuer debug-get-appended-menu,
;; laedt den Shim also so oder so -- kein sinnvoller Nativ-Vergleich ueber
;; dieses Skript). Dass der Mechanismus nativ laengst funktioniert, ist durch
;; win32/gtk-Quelltextvergleich belegt (WM_INITMENU bzw. GtkMenuItem "select"),
;; nicht gesondert re-verifiziert.
;;
;; Aufruf (debug-get-appended-menu ist hinter PLT_QT_DEBUG gated):
;;   PLT_QT_DEBUG=1 QT_PLUGIN_PATH=~/Qt/6.11.1/gcc_64/plugins ~/racket/bin/racket examples/menu-demand-probe.rkt
(require (only-in mred/private/wx/qt/menu-bar debug-get-appended-menu)
         "pump-gate.rkt")

(define demand-count 0)
(define toggle-state #f)

(define frame (new frame% [label "menu-demand-probe"] [width 400] [height 200]))
(define mb (new menu-bar% [parent frame]))

(define item-toggle #f)

(define m-file
  (new menu% [label "File"] [parent mb]
       [demand-callback
        (lambda (m)
          (set! demand-count (add1 demand-count))
          (set! toggle-state (not toggle-state))
          (when item-toggle (send item-toggle check toggle-state))
          (printf "[probe] demand-callback fired, count=~a toggle=~a\n"
                  demand-count toggle-state))]))

(set! item-toggle
      (new checkable-menu-item% [label "Toggle"] [parent m-file]
           [callback (lambda (i e) (void))]))

(send frame show #t)
(pump-gate!)
(wait/pump 1)

(printf "[probe] before any popup: demand-count=~a\n" demand-count)
(unless (zero? demand-count)
  (printf "[probe] UNEXPECTED: demand-callback already fired before any popup\n"))

(define file-wx-menu (debug-get-appended-menu "File"))
(cond
  [file-wx-menu
   (send file-wx-menu popup 50 50 #f #f)
   (wait/pump 1)
   (printf "[probe] after popup 1: demand-count=~a checked?=~a\n"
           demand-count (send item-toggle is-checked?))
   (send file-wx-menu popup 50 50 #f #f)
   (wait/pump 1)
   (printf "[probe] after popup 2: demand-count=~a checked?=~a\n"
           demand-count (send item-toggle is-checked?))
   (if (>= demand-count 2)
       (printf "[probe] RESULT: PASS -- on-menu-click/on-demand fired on real QMenu::aboutToShow, ~a times\n"
               demand-count)
       (printf "[probe] RESULT: FAIL -- demand-callback did not fire via native popup\n"))]
  [else
   (printf "[probe] ERROR: debug-get-appended-menu returned #f -- was PLT_QT_DEBUG=1 set?\n")])

(send frame show #f)
(printf "[probe] exiting\n")

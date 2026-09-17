#lang racket/gui
; Diagnose-/Akzeptanzprobe fuer printer-dc% (docs/HACKING.md, Session
; "printer-dc%"). Zeichnet zwei Seiten (Formen + Text), druckt sie via
; start-doc/start-page/.../end-doc.
;
; PLT_QT_PRINT_TO_PDF=<pfad> (siehe wx/qt/printer-dc.rkt) leitet den Job
; direkt in eine PDF-Datei um und umgeht damit den echten, nicht-modalen
; QPrintDialog -- ohne diese Variable zeigt end-doc unter Qt den echten
; Dialog (interaktiver Pfad, z. B. gegen "Microsoft Print to PDF").
(require racket/draw)

(define dc (new printer-dc%))

(define-values (page-w page-h) (send dc get-size))
(eprintf "[printer-probe] page-size = ~a x ~a pt\n" page-w page-h)

(send dc start-doc "printer-probe")

(send dc start-page)
(send dc set-pen "black" 4 'solid)
(send dc set-brush "blue" 'solid)
(send dc draw-ellipse 50 50 200 120)
(send dc set-font (make-object font% 24 'default))
(send dc draw-text "Seite 1 -- printer-probe" 50 200)
(send dc draw-line 0 0 page-w page-h)
(send dc end-page)

(send dc start-page)
(send dc set-pen "red" 2 'solid)
(send dc set-brush "yellow" 'solid)
(send dc draw-rounded-rectangle 80 80 300 150 20)
(send dc set-font (make-object font% 24 'default))
(send dc draw-text "Seite 2 -- printer-probe" 80 260)
(send dc end-page)

(send dc end-doc)
(eprintf "[printer-probe] end-doc returned\n")

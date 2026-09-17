#lang racket/gui
; Interactive counterpart to printer-probe.rkt: exercises the REAL, non-modal
; QPageSetupDialog / QPrintDialog path (printer-probe.rkt only covers the
; PLT_QT_PRINT_TO_PDF debug bypass). Meant to be driven by an external
; automation script that screenshots the dialog and sends Escape/Cancel.
(require "pump-gate.rkt")

(define f (new frame% [label "printer-dialog-probe"] [width 320] [height 120]))
(new message% [parent f] [label "printer-dialog-probe"])
(send f show #t)
(pump-gate!)

(eprintf "[printer-dialog-probe] can-get-page-setup-from-user? = ~a\n"
         (can-get-page-setup-from-user?))

(eprintf "[printer-dialog-probe] opening page-setup dialog...\n")
(define ps-result (get-page-setup-from-user #f f))
(eprintf "[printer-dialog-probe] page-setup result = ~a\n" ps-result)

(eprintf "[printer-dialog-probe] constructing printer-dc%, opening print dialog via end-doc...\n")
(define dc (new printer-dc% [parent f]))
(send dc start-doc "printer-dialog-probe")
(send dc start-page)
(send dc draw-text "printer-dialog-probe" 10 10)
(send dc end-page)
(send dc end-doc)
(eprintf "[printer-dialog-probe] end-doc returned\n")

(send f show #f)
(eprintf "[printer-dialog-probe] done\n")
(exit 0)

#lang racket/gui
; Diagnose-Probe fuer Block B (docs/HACKING.md §21.7): misst NUR, ob wxtop.rkt's
; resized/correct-size-Selbstkorrektur-Schleife (already-trying?/tried-sizes) fuer
; einen Qt-Frame mit nicht-stretchbarem Panel-Inhalt konvergiert -- rein synchron,
; OHNE natives resizeEvent/Shim-Aenderung. Ausloesung ueber reflow-container nach
; dynamischem Hinzufuegen eines Kindes, was force-redraw -> resized im bestehenden,
; bereits erreichbaren Shared-Code-Pfad ausloest (kein neuer Shim-Hook noetig).
; Wartet dispatchend (docs/HACKING.md §21.10) -- die gemessene Selbstkorrektur-Schleife
; ist synchron, der Konvergenz-Befund vom 2026-09-13 bleibt davon unberuehrt.
(require "pump-gate.rkt")
(define f (new frame% [label "resize-reflow-probe"] [width 400] [height 300]))
(define p (new vertical-panel% [parent f] [stretchable-width #f] [stretchable-height #f]))
(define b1 (new button% [label "small"] [parent p]))
(send f show #t)
(pump-gate!)
(eprintf "[probe] initial size: ~a\n" (call-with-values (lambda () (send f get-size)) list))
(wait/pump 1)
(eprintf "[probe] adding oversized children to force a grow-correction pass\n")
(for ([i (in-range 20)])
  (new button% [label (format "button number ~a with a long label to force width growth" i)] [parent p]))
(send f reflow-container)
(wait/pump 1)
(eprintf "[probe] size after reflow: ~a\n" (call-with-values (lambda () (send f get-size)) list))
(eprintf "[probe] exiting\n")
(exit 0)

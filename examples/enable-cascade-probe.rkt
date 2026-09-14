#lang racket/gui
; Diagnose-Probe (docs/2026-09-13_prompt.md Phase 2.2): misst, ob (send button enable #f)
; das native Klick-Signal unterdrueckt (Vertragslueck-Fix in wx/qt/window.rkt's `enable`).
;
; REPARIERT 2026-09-14 (docs/HACKING.md §21.10): die Vorversion wartete mit (sleep 8)
; im Hauptthread. Der Hauptthread IST der Handler-Thread des Eventspace, und (sleep n)
; dispatcht keine Events -- der Button-Callback konnte deshalb strukturell NIE
; hochzaehlen, egal ob der Klick ankam. Der "clicks = 0"-Befund vom 2026-09-13 war
; ein Instrumentenartefakt, kein Messergebnis. Jetzt wird dispatchend gewartet, und
; das Pump-Gate weist die laufende Queue im Log nach.
;
; Ablauf: Fenster 1 (enabled) ist die POSITIVKONTROLLE -- zaehlt sie nicht hoch, ist
; die Klick-Automatisierung defekt und das Ergebnis von Fenster 2 bedeutungslos.
(require "pump-gate.rkt")
(define clicks (box 0))
(define f (new frame% [label "enable-cascade-probe"] [width 300] [height 150]))
(define p (new vertical-panel% [parent f]))
(define lbl (new message% [parent p] [label "clicks: 0    "]))
(define b (new button% [label "click-me"] [parent p]
                [callback (lambda (b e)
                            (set-box! clicks (add1 (unbox clicks)))
                            (eprintf "[probe] CLICK CALLBACK ran, count = ~a\n" (unbox clicks))
                            (send lbl set-label (format "clicks: ~a" (unbox clicks))))]))
(send f show #t)
(pump-gate!)
; Exakte Bildschirmkoordinaten der Button-Mitte melden, damit die Klick-
; Automatisierung nicht schaetzen muss (Fehlerquelle in Block A).
(define (report-center! tag)
  (let-values ([(bw bh) (send b get-size)])
    (let-values ([(sx sy) (send b client->screen (quotient bw 2) (quotient bh 2))])
      (eprintf "[probe] BUTTON-CENTER-SCREEN-~a ~a ~a (size ~ax~a)\n" tag sx sy bw bh))))
(report-center! "SOFORT")
(wait/pump 1)
(report-center! "NACH-1S")
(eprintf "[probe] READY-FOR-CLICK-1 (enabled, Positivkontrolle)\n")
(wait/pump 8)
(define n1 (unbox clicks))
(eprintf "[probe] clicks after window 1 (enabled) = ~a\n" n1)
(eprintf "[probe] enabled? before disable = ~a\n" (send b is-enabled?))
(send b enable #f)
(eprintf "[probe] enabled? after disable = ~a\n" (send b is-enabled?))
(eprintf "[probe] READY-FOR-CLICK-2 (disabled)\n")
(wait/pump 8)
(define n2 (unbox clicks))
(eprintf "[probe] clicks after window 2 (disabled) = ~a\n" n2)
(eprintf "[probe] VERDICT: enabled=~a disabled-delta=~a -> ~a\n" n1 (- n2 n1)
         (cond
           [(zero? n1) "UNGUELTIG (Positivkontrolle hat nicht gezaehlt: Klick-Automatisierung defekt)"]
           [(= n2 n1) "PASS (enable #f unterdrueckt den Klick nativ)"]
           [else "FAIL (deaktivierter Button feuert weiterhin)"]))
(exit 0)

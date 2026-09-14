#lang racket/gui
; Diagnose-/Akzeptanzprobe fuer Scroll-Block Fall 2 (docs/HACKING.md §25.2):
; ein '(auto-vscroll)-Panel, dessen Inhalt echte Kind-Widgets sind.  Genau die
; Konfiguration des Colors-Tabs in DrRackets Preferences
; (framework/private/color-prefs.rkt:1267-1270 -- vertical-panel% mit
; '(auto-vscroll), am Ende eine Zeile mit drei Buttons).
;
; Fall 1 (examples/scroll-probe.rkt) ist seit §33 gefixt: dort bewegt ein
; Zeichen-Offset den Inhalt.  Hier nicht -- Kind-Widgets muessen wirklich
; verschoben werden.
;
; Akzeptanzkriterium (aus der Uebergabe, docs/2026-09-14-2_report-linux.md):
; der letzte Button ist durch Scrollen erreichbar UND klickbar.  Beides
; getrennt pruefen: der Klick meldet sich hier auf stdout.
;
; Wartet dispatchend (pump-gate) -- ohne "PUMP OK" im Log ist jede Beobachtung
; aus dieser Probe ungueltig, s. §21.10.
(require "pump-gate.rkt")

(file-stream-buffer-mode (current-output-port) 'line)

(define f (new frame% [label "panel-scroll-probe"] [width 320] [height 260]))
(define p (new vertical-panel% [parent f] [style '(auto-vscroll)]))

(define clicks (box 0))

(define (click! b)
  (set-box! clicks (add1 (unbox clicks)))
  (eprintf "[probe] CLICK auf ~a (Nr. ~a)\n" (send b get-label) (unbox clicks)))

(for ([i (in-range 20)])
  (new button% [parent p]
       [label (format "Button ~a" i)]
       [callback (lambda (b e) (click! b))]))

; Die "drei Buttons am Ende" des Colors-Tabs: nur ueber Scrollen erreichbar.
(define last-row (new horizontal-panel% [parent p] [stretchable-height #f]))
(define last-buttons
  (for/list ([s (in-list '("Revert" "Design" "Names"))])
    (new button% [parent last-row] [label s]
         [callback (lambda (b e) (click! b))])))

(send f show #t)
(pump-gate!)

; Exakte Bildschirmkoordinaten melden, damit die Klick-Automatisierung nicht
; schaetzen muss (Lehre aus §21.10/enable-cascade-probe). Zugleich die Messung,
; ob client->screen durch das verschobene Content-Widget hindurch stimmt.
(define (report-center! b)
  (let-values ([(bw bh) (send b get-size)])
    (let-values ([(sx sy) (send b client->screen (quotient bw 2) (quotient bh 2))])
      (eprintf "[probe] CENTER ~a: ~a ~a\n" (send b get-label) sx sy))))

(let loop ([n 0])
  (eprintf "[probe] tick ~a: frame=~ax~a panel=~ax~a clicks=~a\n"
           n (send f get-width) (send f get-height)
           (send p get-width) (send p get-height) (unbox clicks))
  (for-each report-center! last-buttons)
  (when (< n 120) (wait/pump 1) (loop (add1 n))))

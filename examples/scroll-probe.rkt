#lang racket/gui
; Diagnose-Probe fuer den Scroll-Cluster (docs/HACKING.md §24.5/§25.2).
; Isolierter editor-canvas% mit '(auto-hscroll auto-vscroll) und Inhalt, der in
; beide Richtungen groesser ist als das Fenster -- der kleinstmoegliche Fall, in
; dem wx/qt einen funktionierenden Scroll-Mechanismus liefern muesste.
;
; SEIT §33 (2026-09-14) ist das die Akzeptanzprobe des Scroll-Blocks, nicht
; mehr die Symptomprobe. Erwartet wird: beide Scrollbars sichtbar, Mausrad und
; PageDown bewegen den Inhalt, Zeile 99 ueber den Thumb erreichbar, horizontal
; analog.
;
; Bekannte Symptome VOR §33 (je Plattform verschieden, dieselbe Fundstelle --
; wx/qt/canvas.rkt hatte die Scroll-Methoden ueberhaupt nicht implementiert):
;   Windows (§24.5): Inhalt komplett weiss, nur blinkender Caret.
;   macOS   (§29.2): Inhalt rendert korrekt, Scrollen bleibt wirkungslos.
;   Linux   (§21.10-Session, Phase 3.4): Inhalt farblich verstuemmelt/gestreift,
;           kein Scrollbar sichtbar, Mausrad und PageDown ohne jede Wirkung.
;
; Wartet dispatchend (pump-gate) -- ohne "PUMP OK" im Log ist jede Beobachtung
; aus dieser Probe ungueltig, s. §21.10.
(require "pump-gate.rkt")

(define f (new frame% [label "scroll-probe"] [width 400] [height 300]))
(define c (new editor-canvas% [parent f] [style '(auto-hscroll auto-vscroll)]))
(define t (new text%))
(for ([i (in-range 100)])
  (send t insert (format "Zeile ~a von 100 -- absichtlich sehr breiter Inhalt, damit auch horizontal gescrollt werden muss\n" i)))
(send t set-position 0)
(send c set-editor t)
(send f show #t)
(pump-gate!)

(let loop ([n 0])
  (eprintf "[probe] tick ~a: frame=~ax~a canvas=~ax~a\n"
           n (send f get-width) (send f get-height)
           (send c get-width) (send c get-height))
  (when (< n 60) (wait/pump 1) (loop (add1 n))))

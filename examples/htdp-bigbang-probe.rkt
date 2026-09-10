#lang racket
; htdp-Lackmustest Facette 2 (docs/2026-07-14_prompt.md): 2htdp/universe big-bang.
; Kern-Wette: big-bang treibt eine interaktive Schleife -- laeuft sie unter
; "Racket treibt, Pump blockiert nie" sauber (Ticks, Redraw, Tastatur), ohne
; eigene geschachtelte Schleife? Unbedingter printf im Tick-Handler trennt
; "Loop laeuft" (stdout-Stream) von "Loop rendert" (Screenshot-Vergleich) --
; sonst aus einem Screenshot allein nicht unterscheidbar.
(require 2htdp/image 2htdp/universe)

(define (tick n)
  (printf "tick: ~a~n" n)
  (add1 n))

(define (draw n)
  (overlay (text (number->string n) 48 "black")
           (empty-scene 300 200)))

(define (key-handler n key)
  (cond [(equal? key "r") 0]
        [else n]))

(big-bang 0
  [on-tick tick 1]
  [to-draw draw]
  [on-key key-handler]
  [name "htdp-bigbang-probe"])

#lang racket
; Diagnose-Probe (docs/2026-07-14_report-linux.md, Nachtrag 2 / docs/HACKING.md §23.1):
; isoliert dieselbe text+above/align-Kombination, die als 5. Bild in
; htdp-image-probe.rkt nicht rendert, als einzige Top-Level-Expression.
; Ergebnis: rendert sofort korrekt -- kein text-spezifischer Rendering-Bug.
(require 2htdp/image)
(above/align "left"
             (text "isolated-test" 18 "black")
             (rectangle 120 10 "solid" "gray"))

#lang racket
; Diagnose-Probe (docs/2026-07-14_report-linux.md, Nachtrag 2 / docs/HACKING.md §23.1):
; 6 rein geometrische Bilder (bewusst kein `text`), um zu isolieren, ob der
; "nur die ersten 4 Interactions-Snips einer Run-Sitzung rendern"-Befund content-
; abhaengig ist. Ergebnis: nein -- Bild 5 und 6 fehlen identisch wie bei
; htdp-image-probe.rkt (dort mit `text` als 5. Bild).
(require 2htdp/image)
(circle 40 "solid" "red")
(rectangle 80 40 "outline" "blue")
(overlay (circle 30 "solid" "yellow")
         (square 70 "solid" "darkgreen"))
(beside (triangle 40 "solid" "purple")
        (ellipse 60 30 "solid" "orange"))
(circle 25 "solid" "magenta")
(circle 15 "solid" "cyan")

#lang racket
; htdp-Lackmustest Facette 1 (docs/2026-07-14_prompt.md): 2htdp/image-Rendering
; im Interactions-Fenster (Image-Snip ueber den Cairo->Backing-Pfad).
; Kein Fenstercode -- absichtlich reine Modul-Top-Level-Ausdruecke, deren
; Werte DrRacket beim Laden als Snips in Interactions druckt.
(require 2htdp/image)

(circle 40 "solid" "red")
(rectangle 80 40 "outline" "blue")
(overlay (circle 30 "solid" "yellow")
         (square 70 "solid" "darkgreen"))
(beside (triangle 40 "solid" "purple")
        (ellipse 60 30 "solid" "orange"))
(above/align "left"
             (text "htdp-image-probe" 18 "black")
             (rectangle 120 10 "solid" "gray"))

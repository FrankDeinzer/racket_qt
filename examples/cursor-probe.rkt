#lang racket/gui
; Diagnose-/Akzeptanzprobe fuer cursor-driver% (docs/HACKING.md, Stub-Inventar
; aus docs/2026-09-14-4_report-linux.md "Nachtrag nach Abschluss").
;
; Ein Streifen von Canvases, jedes mit einem anderen Standard-Cursor per
; set-cursor belegt, plus ein Canvas mit einem selbstgebauten 16x16-Bitmap-
; Cursor (set-image-Pfad). Erwartung: die Systemmaus-Form aendert sich beim
; Ueberfahren jedes Canvas -- keine automatisierte Zusicherung moeglich,
; visuell per Screenshot waehrend echtem Maus-Hover zu pruefen.
(require "pump-gate.rkt")

(define symbols '(arrow cross hand ibeam watch bullseye blank
                   size-n/s size-e/w size-ne/sw size-nw/se arrow+watch))

(define f (new frame% [label "cursor-probe"] [width (* 90 (length symbols))] [height 180]))
(define row (new horizontal-panel% [parent f]))

(for ([sym (in-list symbols)])
  (define p (new vertical-panel% [parent row]))
  (define c (new canvas% [parent p] [min-width 80] [min-height 80]
                  [paint-callback
                   (lambda (canvas dc)
                     (send dc set-background (make-object color% 230 230 230))
                     (send dc clear))]))
  (send c set-cursor (make-object cursor% sym))
  (new message% [parent p] [label (symbol->string sym)]))

; Custom 16x16 bitmap+mask cursor (set-image path, distinct from set-standard).
(define custom-panel (new vertical-panel% [parent row]))
(define custom-canvas
  (new canvas% [parent custom-panel] [min-width 80] [min-height 80]
       [paint-callback
        (lambda (canvas dc)
          (send dc set-background (make-object color% 230 230 230))
          (send dc clear))]))
; cursor%'s public constructor requires a monochrome bitmap (is-16x16? check
; in wx/common/cursor.rkt) -- unlike cursor-draw.rkt's make-cursor-image,
; which feeds set-image directly and skips that check.
(define custom-image (make-object bitmap% 16 16 #t))
(let ([dc (make-object bitmap-dc% custom-image)])
  (send dc set-brush "black" 'solid)
  (send dc draw-rectangle 6 0 4 16)
  (send dc draw-rectangle 0 6 16 4)
  (send dc set-bitmap #f))
(send custom-canvas set-cursor (make-object cursor% custom-image custom-image 8 8))
(new message% [parent custom-panel] [label "custom (plus)"])

(send f show #t)
(pump-gate!)

(let loop ([n 0])
  (eprintf "[cursor-probe] tick ~a\n" n)
  (when (< n 120) (wait/pump 1) (loop (add1 n))))

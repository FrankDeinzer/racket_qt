#lang racket/gui
; macOS-Validierung (2026-07-14, Fortsetzung von 2026-07-13-3): isolierte
; canvas-panel%-Probe. Auf Windows/Linux wurde canvas-panel% end-to-end über
; DrRackets echten Preferences-Dialog (Colors-Kategorie, color-prefs.rkt's
; hide-hscroll/hide-vscroll-Panels) validiert. Auf macOS blockiert ein
; unabhängiger Menü-Bug (Qt-Heuristik reißt "Configure Command Line for
; Racket…" ins App-Menü und ersetzt dort fälschlich die Preferences-Aktion)
; den Dialog-Pfad -- diese Probe reproduziert die relevante Konfiguration
; direkt: ein editor-canvas% mit 'hide-hscroll/'hide-vscroll-Stil, exakt wie
; color-prefs.rkt's canvas:color% (build-text-foreground-selection-panel).
; set-scrollbars ist keine öffentliche editor-canvas%-Methode -- der Absturz
; auf Windows kam aus der internen canvas-autoscroll-mixin-Neuberechnung, die
; die WX-Ebene automatisch aufruft, sobald der Editor-Inhalt die Canvas-Größe
; überschreitet. Also: genug Inhalt einfügen, damit dieser interne Pfad
; getriggert wird, statt set-scrollbars selbst aufzurufen.

(file-stream-buffer-mode (current-output-port) 'line)

(define frame (new frame% [label "canvas-panel% Driver"] [width 420] [height 320]))
(define outer (new vertical-panel% [parent frame]))

(new message% [parent outer]
     [label "Scrollable canvas-panel% below; content exceeds visible size."])

(define ed (new text%))

(define cp (new editor-canvas% [parent outer]
                [editor ed]
                [style '(hide-hscroll hide-vscroll)]
                [min-height 150]))

(printf "canvas-panel% created (editor-canvas% with hide-hscroll/hide-vscroll style)~n")

; Oversized content forces canvas-autoscroll-mixin's internal set-scrollbars
; recalculation (the call that crashed on the pre-fix Windows stub).
(for ([i (in-range 40)])
  (send ed insert (format "Row ~a of scrollable content\n" i)))
(printf "content inserted (no crash from internal set-scrollbars recalculation)~n")

(define ctrl (new horizontal-panel% [parent outer] [stretchable-height #f]))
(new button% [parent ctrl] [label "scroll to top"]
     [callback (lambda (b e)
                 (send ed scroll-to-position 0)
                 (printf "scroll to top done~n"))])
(new button% [parent ctrl] [label "scroll to bottom"]
     [callback (lambda (b e)
                 (send ed scroll-to-position (send ed last-position))
                 (printf "scroll to bottom done~n"))])

(send frame show #t)
(printf "frame shown~n")

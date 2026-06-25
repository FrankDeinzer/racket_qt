#lang racket/gui
; D-2 smoke: editor-canvas% + text% on the Qt backend.
; Proves: "Editor läuft auf Qt."
;
; Run with: PLT_QT=1 racket examples/editor.rkt
;
; Expected behaviour:
;   - Type text → appears
;   - Click → moves caret
;   - Drag → selects text
;   - Caret blinks

(define frame
  (new frame%
       [label "Editor — Qt Backend (D-2)"]
       [width 600]
       [height 400]))

(define editor (new text%))

(define canvas
  (new editor-canvas%
       [parent frame]
       [editor editor]
       [style '(no-hscroll)]))

; Pre-load some text so there is something to click/edit
(send editor insert "Hello from Qt!\n")
(send editor insert "Type here, click to move caret, drag to select.\n")
(send editor insert "Caret should blink.\n")

(send frame show #t)

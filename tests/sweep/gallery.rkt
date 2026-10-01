#lang racket/gui
;; Screenshot-Sweep, Szene "gallery": ein deterministisches Fenster mit allen
;; wichtigen Widget-Klassen und Style-Flags.  Läuft nativ (gtk) und mit PLT_QT=1;
;; tests/sweep/sweep.sh nimmt beide auf und legt sie nebeneinander.
;; Absichtlich ohne Timer/Animation, feste Größe, keine Zufallsdaten.
(define f (new frame% [label "sweep-gallery"] [width 900] [height 760]))

(define mb (new menu-bar% [parent f]))
(define m-file (new menu% [label "&File"] [parent mb]))
(new menu-item% [label "New"] [parent m-file] [callback void] [shortcut #\N])
(new menu-item% [label "Open..."] [parent m-file] [callback void] [shortcut #\O])
(new separator-menu-item% [parent m-file])
(void (new checkable-menu-item% [label "Checked item"] [parent m-file] [callback void] [checked #t]))
(define m-edit (new menu% [label "&Edit"] [parent mb]))
(new menu-item% [label "Copy"] [parent m-edit] [callback void] [shortcut #\C])
(send (new menu-item% [label "Disabled"] [parent m-edit] [callback void]) enable #f)

(define top (new horizontal-panel% [parent f]))
(define left (new vertical-panel% [parent top] [style '(border)]))
(define right (new vertical-panel% [parent top]))

;; ---- left column: simple controls ----
(new message% [parent left] [label "message%: plain label"])
(define row1 (new horizontal-panel% [parent left] [stretchable-height #f]))
(new button% [parent row1] [label "Button"])
(new button% [parent row1] [label "Default"] [style '(border)])
(new button% [parent row1] [label "Disabled"] [enabled #f])
(new check-box% [parent left] [label "check-box% on"] [value #t])
(new check-box% [parent left] [label "check-box% off"])
(new radio-box% [parent left] [label "radio-box% vertical"] [choices '("one" "two" "three")])
(new radio-box% [parent left] [label "horizontal"] [choices '("a" "b")] [style '(horizontal)])
(new choice% [parent left] [label "choice%"] [choices '("alpha" "beta" "gamma")])
(new slider% [parent left] [label "slider%"] [min-value 0] [max-value 100] [init-value 40])
(new gauge% [parent left] [label "gauge%"] [range 100])
(define g2 (new gauge% [parent left] [label "gauge 60%"] [range 100]))
(send g2 set-value 60)
(new gauge% [parent left] [label "vertical"] [range 100] [style '(vertical)] [stretchable-height #f] [min-height 60])
(new text-field% [parent left] [label "text-field%"] [init-value "hello"])
(new text-field% [parent left] [label "disabled"] [init-value "off"] [enabled #f])
(new combo-field% [parent left] [label "combo-field%"] [choices '("x" "y" "z")] [init-value "combo"])
(new text-field% [parent left] [label "multi"] [style '(multiple)] [init-value "line1\nline2"] [min-height 50])

;; ---- right column: containers & lists ----
(new list-box% [parent right] [label "list-box% single"] [choices '("red" "green" "blue" "cyan")]
     [min-height 80])
(new list-box% [parent right] [label "list-box% multi-col"] [choices '()]
     [style '(single column-headers)] [columns '("Name" "Kind" "Size")] [min-height 90])
(define lb (car (reverse (send right get-children))))
(send lb set '("alpha" "beta" "gamma") '("a" "b" "c") '("1" "2" "3"))
(define gp (new group-box-panel% [parent right] [label "group-box-panel%"]))
(new button% [parent gp] [label "inside group"])
(new check-box% [parent gp] [label "inside check"])
(define tp (new tab-panel% [parent right] [choices '("First" "Second" "Third")]
                [style '(can-close can-reorder)] [min-height 90]))
(new message% [parent tp] [label "tab-panel% content (can-close can-reorder)"])
(define cv1 (new canvas% [parent right] [style '(border)] [min-width 200] [min-height 40]
                 [paint-callback (lambda (c dc) (send dc draw-text "canvas% 'border" 4 4))]))
(define cv2 (new canvas% [parent right] [style '(control-border)] [min-width 200] [min-height 40]
                 [paint-callback (lambda (c dc) (send dc draw-text "canvas% 'control-border" 4 4))]))
(define ed (new text%))
(send ed insert "editor-canvas% (text%) content\nsecond line")
(new editor-canvas% [parent right] [editor ed] [min-height 60])
(send f show #t)

#lang racket/gui
; D-1 smoke: mouse coordinates, key chars, modifiers, animated box via timer.
; Run with: PLT_QT=1 racket examples/input.rkt

(define frame
  (new frame%
       [label "Input Test — Qt Backend"]
       [width 500]
       [height 400]))

(define mouse-x 0)
(define mouse-y 0)
(define mouse-event-str "—")
(define last-key "—")
(define focus-str "no focus")

; Animated box state
(define box-x 20)
(define box-dir 1)   ; 1 = right, -1 = left

(define input-canvas%
  (class canvas%
    (define/override (on-event e)
      (set! mouse-x (send e get-x))
      (set! mouse-y (send e get-y))
      (set! mouse-event-str
            (format "[~a L:~a M:~a R:~a]"
                    (send e get-event-type)
                    (send e get-left-down)
                    (send e get-middle-down)
                    (send e get-right-down)))
      (send this refresh))
    (define/override (on-char e)
      (define kc     (send e get-key-code))
      (define shift? (send e get-shift-down))
      (define ctrl?  (send e get-control-down))
      (define alt?   (send e get-alt-down))
      (define mods
        (string-join
         (filter string?
                 (list (and shift? "Shift") (and ctrl? "Ctrl") (and alt? "Alt")))
         "+"))
      (set! last-key
            (format "~a~a"
                    (if (string=? mods "") "" (string-append mods "+"))
                    kc))
      (send this refresh))
    (define/override (on-focus on?)
      (set! focus-str (if on? "focused" "unfocused"))
      (send this refresh))
    (super-new)))

(define canvas
  (new input-canvas%
       [parent frame]
       [paint-callback
        (lambda (c dc)
          (send dc set-background (make-object color% 20 25 40))
          (send dc clear)
          ; animated box
          (send dc set-brush (make-object brush% (make-object color% 80 160 255) 'solid))
          (send dc set-pen   (make-object pen%   (make-object color% 150 200 255) 1 'solid))
          (send dc draw-rectangle box-x 20 40 40)
          ; info text
          (send dc set-font (make-object font% 13 'modern 'normal 'normal))
          (send dc set-text-foreground (make-object color% 200 230 255))
          (send dc draw-text (format "Mouse: (~a, ~a)  ~a" mouse-x mouse-y mouse-event-str) 10 80)
          (send dc draw-text (format "Key:   ~a" last-key)   10 110)
          (send dc draw-text (format "Focus: ~a" focus-str)  10 140)
          (send dc set-text-foreground (make-object color% 120 180 100))
          (send dc draw-text "Move mouse, click, type — box animates via timer" 10 180))]))

; Timer: moves box left-right every 50ms
(new timer%
     [notify-callback
      (lambda ()
        (set! box-x (+ box-x (* box-dir 3)))
        (when (> box-x 420) (set! box-dir -1))
        (when (< box-x 10)  (set! box-dir  1))
        (send canvas refresh))]
     [interval 50])

(send frame show #t)

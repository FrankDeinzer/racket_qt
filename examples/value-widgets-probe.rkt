#lang racket/gui
; Checkpoint-E driver (2026-07-13-2_prompt): isolated choice%/radio-box%/
; slider% probe. Substituted for the DrRacket Preferences dialog because
; the dialog's own category switcher unconditionally instantiates
; tab-panel% (framework/private/preferences.rkt's make-tab/single-panel,
; called even for the top-level panel list) -- tab-panel% is still a stub
; (Block B, not this session), so the real dialog can't be exercised
; end-to-end here. This probe fills the gap, analogous to
; dialog-widgets-probe.rkt for list-box%/check-box%.
;
; Also exercises the "set-* must not re-trigger the callback" requirement:
; each "set via code" button calls set-value/set-selection and prints
; whether the widget's own callback fired as a side effect (it must not).

; Line-buffer stdout so prints are visible immediately when this runs under
; a redirecting harness (PowerShell block-buffers otherwise, per STATUS.md's
; Linux-session note on the same symptom).
(file-stream-buffer-mode (current-output-port) 'line)

(define frame (new frame% [label "choice%/radio-box%/slider% Driver"] [width 380] [height 420]))
(define panel (new vertical-panel% [parent frame]))

(new message% [parent panel]
     [label "Interact with each control, then use the \"set via code\" buttons."])

; ---- choice% --------------------------------------------------------------

(define ch (new choice% [parent panel]
                [label "Choice:"]
                [choices '("Alpha" "Beta" "Gamma")]
                [callback
                 (lambda (c e)
                   (printf "choice% callback fired: selection=~a (~a)~n"
                           (send c get-selection) (send c get-string-selection)))]))

(new button% [parent panel] [label "choice: set-selection 2 via code"]
     [callback (lambda (b e) (send ch set-selection 2)
                 (printf "choice: set-selection 2 done, now selection=~a~n" (send ch get-selection)))])

; ---- radio-box% ------------------------------------------------------------

(define rb (new radio-box% [parent panel]
                [label "Radio-box:"]
                [choices '("One" "Two" "Three")]
                [style '(vertical)]
                [callback
                 (lambda (r e)
                   (printf "radio-box% callback fired: selection=~a~n" (send r get-selection)))]))

(new button% [parent panel] [label "radio-box: set-selection 1 via code"]
     [callback (lambda (b e) (send rb set-selection 1)
                 (printf "radio-box: set-selection 1 done, now selection=~a~n" (send rb get-selection)))])

; Single-button radio-box with no initial selection -- the driver's real
; use case (color-prefs.rkt's mk-color-scheme-radio-buttons, [selection #f]
; on a 1-choice group) and the hard case for the exclusive-group "none
; checked" state (dummy-button trick, docs/HACKING.md).
(define rb1 (new radio-box% [parent panel]
                 [label "Single (no initial selection):"]
                 [choices '("Only choice")]
                 [selection #f]
                 [callback
                  (lambda (r e)
                    (printf "single radio-box% callback fired: selection=~a~n" (send r get-selection)))]))

(new button% [parent panel] [label "single radio-box: set-selection #f via code"]
     [callback (lambda (b e) (send rb1 set-selection #f)
                 (printf "single radio-box: set-selection #f done, now selection=~a~n" (send rb1 get-selection)))])

; ---- slider% ---------------------------------------------------------------

(define sl (new slider% [parent panel]
                [label "Slider:"]
                [min-value 0] [max-value 100] [init-value 20]
                [callback
                 (lambda (s e)
                   (printf "slider% callback fired: value=~a~n" (send s get-value)))]))

(new button% [parent panel] [label "slider: set-value 75 via code"]
     [callback (lambda (b e) (send sl set-value 75)
                 (printf "slider: set-value 75 done, now value=~a~n" (send sl get-value)))])

(send frame show #t)
(printf "initial: choice selection=~a, radio-box selection=~a, single radio-box selection=~a, slider value=~a~n"
        (send ch get-selection) (send rb get-selection) (send rb1 get-selection) (send sl get-value))

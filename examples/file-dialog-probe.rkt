#lang racket/gui
; Driver for the file-selector work (docs/2026-07-11_prompt.md): a frame with
; "Open..."/"Save..." buttons that call get-file/put-file and show the
; returned path (or #f on cancel) both in a label and on stdout, so the
; return value is visible without extra tooling.

(define frame (new frame% [label "File-Dialog Probe"] [width 420] [height 160]))
(define panel (new horizontal-panel% [parent frame]))

(define result-msg
  (new message% [parent frame] [label "(no result yet)"] [stretchable-width #t]))

; Heartbeat (docs/2026-07-13_prompt-macos.md): beweist, dass der Racket-Eventspace-Pump
; weiterläuft, während ein natives NSOpenPanel/NSSavePanel offen ist. Kein wx/qt-Code;
; rein Racket-seitig, additiv, kein Effekt auf den eigentlichen Dialog-Wertpfad. Gated
; hinter PLT_QT_DEBUG, damit ein normaler Probe-Lauf nicht dauerhaft alle 200ms loggt.
(when (getenv "PLT_QT_DEBUG")
  (define heartbeat-count 0)
  (define heartbeat-msg
    (new message% [parent frame] [label "heartbeat: 0"] [stretchable-width #t]))
  (define heartbeat-timer
    (new timer%
         [notify-callback
          (lambda ()
            (set! heartbeat-count (add1 heartbeat-count))
            (define text (format "heartbeat: ~a" heartbeat-count))
            (printf "[file-dialog-probe] ~a\n" text)
            (send heartbeat-msg set-label text))]))
  (send heartbeat-timer start 200))

(define (show-result who path)
  (define text (format "~a -> ~a" who (or path "#f (cancel)")))
  (printf "[file-dialog-probe] ~a\n" text)
  (send result-msg set-label text))

(new button%
     [parent panel]
     [label "Open..."]
     [callback (lambda (b e)
                 (show-result 'get-file (get-file "Open a file" frame)))])

(new button%
     [parent panel]
     [label "Save..."]
     [callback (lambda (b e)
                 (show-result 'put-file (put-file "Save a file" frame)))])

; Discriminator (docs/2026-07-11_prompt.md follow-up): does a NATIVE MENU click
; reach get-file the same way a button click does? Isolates menu-dispatch from
; DrRacket's framework/recovery layer.
(define mb (new menu-bar% [parent frame]))
(define menu (new menu% [label "File"] [parent mb]))
(new menu-item%
     [label "Open via menu..."]
     [parent menu]
     [callback (lambda (i e)
                 (show-result 'menu-get-file (get-file "Open a file" frame)))])
(new menu-item%
     [label "No-op (generic dispatch check)"]
     [parent menu]
     [callback (lambda (i e) (show-result 'menu-noop "clicked, no dialog"))])
(new menu-item%
     [label "Force GC (retention stress test)"]
     [parent menu]
     [callback (lambda (i e)
                 (collect-garbage)
                 (show-result 'force-gc "collect-garbage done"))])

(send frame show #t)

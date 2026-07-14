#lang racket/gui
; macOS-Validierung (2026-07-14, Fortsetzung von 2026-07-13-3): isolierte
; group-panel%-Probe. Auf Windows/Linux wurde group-panel% end-to-end über
; DrRackets echten Preferences-Dialog validiert (Browser-Tab-Proxy-Controls,
; color-prefs.rkt/browser-prefs.rkt). Auf macOS blockiert ein unabhängiger
; Menü-Bug den Dialog-Pfad (siehe canvas-panel-probe.rkt-Kommentar) -- diese
; Probe deckt denselben Fehlermodus ab, der auf Windows gefunden wurde: ein
; Stub-group-panel% ohne echtes Content-Widget liefert #f für
; get-content-hwnd, wodurch Qt aus parentless Kind-Controls eigene
; Top-Level-Fenster macht. Sichtbarer Erfolgstest: alle Kind-Controls bleiben
; INNERHALB des Group-Box-Rahmens, kein separates Fenster reißt aus.

(file-stream-buffer-mode (current-output-port) 'line)

(define frame (new frame% [label "group-panel% Driver"] [width 420] [height 300]))
(define outer (new vertical-panel% [parent frame]))

(new message% [parent outer]
     [label "All controls below must stay inside the group box -- none may pop out as a separate window."])

(define gp (new group-box-panel% [label "Proxy Settings"] [parent outer]))

(printf "group-panel% created (group-box-panel%, label=~a)~n" (send gp get-label))

(new radio-box% [parent gp] [label #f]
     [choices '("No Proxy" "System Proxy" "Manual Proxy")]
     [callback (lambda (r e)
                 (printf "proxy choice -> ~a~n" (send r get-item-label (send r get-selection))))])

(define manual (new horizontal-panel% [parent gp]))
(new message% [parent manual] [label "Host:"])
(new text-field% [parent manual] [label #f] [init-value "localhost"])

(new button% [parent gp] [label "set-label 'Network Proxy' via code"]
     [callback (lambda (b e)
                 (send gp set-label "Network Proxy")
                 (printf "set-label done, now label=~a~n" (send gp get-label)))])

(send frame show #t)
(printf "frame shown~n")

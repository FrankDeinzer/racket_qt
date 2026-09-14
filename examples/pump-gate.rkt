#lang racket/base
;; Pump-Gate fuer Diagnose-Proben (docs/HACKING.md §21.10).
;;
;; Hintergrund: In einem bare-`racket`-Skript ist der Hauptthread selbst der
;; Handler-Thread des Haupt-Eventspace (wx/common/queue.rkt:357). `yield`
;; dispatcht Events nur aus dem Handler-Thread (queue.rkt:464/475) -- (sleep n)
;; dispatcht gar nichts. Eine Probe, die mit (sleep n) auf GUI-Ereignisse
;; wartet, laesst deshalb KEIN gepostetes Event laufen; alles liegt bis zum
;; Programmende in der Queue und wird erst vom executable-yield-handler
;; (queue.rkt:637) abgearbeitet. Ergebnisse solcher Proben sind wertlos.
;;
;; wait/pump wartet stattdessen dispatchend und weist beim ersten Aufruf nach,
;; dass die Queue wirklich laeuft: jede Probe traegt ihren Gueltigkeitsbeweis
;; ab jetzt im eigenen Log.
(require racket/gui/base)

(provide pump-gate! wait/pump)

(define posted-at #f)
(define ran-after #f)
(define reported? #f)

;; Direkt nach (send frame show #t) aufrufen.
(define (pump-gate!)
  (set! posted-at (current-inexact-milliseconds))
  (set! ran-after #f)
  (set! reported? #f)
  (queue-callback
   (lambda () (set! ran-after (- (current-inexact-milliseconds) posted-at)))
   #t))

(define (report!)
  (unless reported?
    (set! reported? #t)
    (if ran-after
        (eprintf "[pump-gate] PUMP OK (~a ms)\n" (real->decimal-string ran-after 1))
        (eprintf "[pump-gate] PUMP FAIL -- Eventspace-Queue dispatcht nicht, jedes Ergebnis dieser Probe ist ungueltig\n"))))

;; Ersetzt (sleep secs) in jeder Probe, die auf GUI-Ereignisse wartet.
(define (wait/pump secs)
  (sleep/yield secs)
  (when posted-at (report!)))

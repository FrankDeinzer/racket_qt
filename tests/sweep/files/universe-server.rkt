#lang racket
;; Counter-Universe (nur localhost).  Clients senden 'inc; der Server zaehlt hoch und schickt den
;; neuen Zaehler an ALLE.  Log (append) in $SWEEP_MARK_SRV.  Port: $SWEEP_PORT (Default 17891).
(require 2htdp/universe)
(define mark (or (getenv "SWEEP_MARK_SRV") "/dev/null"))
(define PORT (string->number (or (getenv "SWEEP_PORT") "17891")))
(define (log! . xs)
  (with-output-to-file mark #:exists 'append (lambda () (displayln xs))))
(define count 0)
(define (msg u w m)
  (log! 'msg (iworld-name w) m)
  (cond [(equal? m 'inc)
         (set! count (add1 count))
         (make-bundle u (for/list ([x (in-list u)]) (make-mail x count)) '())]
        [else u]))
(define (gone u w) (log! 'gone (iworld-name w)) (remove w u))
(log! (quote server-start) PORT)
(universe '()
  (port PORT)
  (on-new (lambda (u w) (log! 'join (iworld-name w)) (make-bundle (cons w u) (list (make-mail w count)) '())))
  (on-msg msg)
  (on-disconnect gone))

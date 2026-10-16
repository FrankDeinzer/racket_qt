;; Start the real DrRacket inside the combined Qt+Racket WASM module (HACKING §85.14).
(require ffi/unsafe racket/class racket/gui/base)
(define t0 (current-inexact-milliseconds))
(printf "DRRACKET-START\n")

;; Selection mirror for the browser `copy` event (HACKING §85.18): SEB's private clipboard fires `copy` and wants the text synchronously,
;; so the shim has to know the focused editor's selection beforehand.  Poll it (cheap: one text per tick) and push changes.
(define set-selection
  (get-ffi-obj "shim_wasm_set_selection" (ffi-lib #f) (_fun _string -> _void) (lambda () #f)))
(define main-es (current-eventspace))
(define (focused-selection)
  (define w (get-top-level-focus-window))
  (define ed (and w (is-a? w top-level-window<%>)
                  (send w get-edit-target-object)))
  (if (is-a? ed text%)
      (let ([b (box 0)] [e (box 0)])
        (send ed get-position b e)
        (if (< (unbox b) (unbox e)) (send ed get-text (unbox b) (unbox e)) ""))
      ""))
(when set-selection
  (thread
   (lambda ()
     (let loop ([last #f])
       (sleep 0.1)
       (define result #f)
       (define done (make-semaphore))
       (queue-callback (lambda ()
                         (set! result (with-handlers ([void (lambda (e) (eprintf "selmirror error: ~a\n" (if (exn? e) (exn-message e) e)) "")]) (focused-selection)))
                         (semaphore-post done))
                       #f)
       (define t (and (sync/timeout 1 done) result))
       (cond [(and t (not (equal? t last))) (set-selection t) (loop t)]
             [else (loop last)])))))

(dynamic-require 'drracket/drracket #f)
(printf "DRRACKET-LOADED ~a ms\n" (round (- (current-inexact-milliseconds) t0)))
(yield 'wait)

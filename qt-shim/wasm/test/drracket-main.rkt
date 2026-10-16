;; Start the real DrRacket inside the combined Qt+Racket WASM module (HACKING §85.14).
(require ffi/unsafe racket/class racket/gui/base net/sendurl)
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

;; Documentation (HACKING §85.20): there is no browser to start.  Help links point to docs.racket-lang.org (no local doc tree in the image);
;; hand them to the exam page, which shows the same path from its own copy of the docs (<server>/doc/...).  Other URLs go to the page unchanged.
(define open-url
  (get-ffi-obj "shim_wasm_open_url" (ffi-lib #f) (_fun _string -> _void) (lambda () #f)))
;; send-url/contents (used for Help Desk searches) writes a small redirect page to the temp dir and sends its file: URL: read the target out of it.
(define (redirect-target url)
  (define m (regexp-match #rx"^file://(/tmp/plt-sendurl-contents-[^/]*[.]html)$" url))
  (define page (and m (with-handlers ([void (lambda (e) #f)])
                        (call-with-input-file (cadr m) (lambda (in) (read-string 100000 in))))))
  (cond [(not page) url]
        [else (eprintf "send-url redirect page: ~a\n" page)
              (cond [(regexp-match #rx"[Uu][Rr][Ll]=['\"]?([^'\"> ]+)" page) => cadr]
                    [(regexp-match #rx"location[.a-z]* *= *['\"]([^'\"]+)" page) => cadr]
                    [(regexp-match #rx"(https?://[^'\"<> ]+)" page) => cadr]
                    [else url])]))
(when open-url
  (external-browser
   (lambda (url)
     (define target (redirect-target url))
     (eprintf "send-url: ~a -> ~a\n" url target)
     (open-url (cond [(regexp-match #rx"^https?://docs\\.racket-lang\\.org/(.*)$" target)
                      => (lambda (m) (string-append "doc/" (cadr m)))]
                     [else target])))))

(dynamic-require 'drracket/drracket #f)
(printf "DRRACKET-LOADED ~a ms\n" (round (- (current-inexact-milliseconds) t0)))
(yield 'wait)

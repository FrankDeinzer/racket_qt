#lang racket/base
;; Writes <tree>/share/info-cache.rktd for the WASM package payload (docs/HACKING.md §85.19).
;;   racket make-info-cache.rkt <host-racket-share-dir> <tree>
;; DrRacket finds its tools (Check Syntax, Debug, Macro Stepper, ...) through `find-relevant-directory-records`, which reads the
;; installation's info cache (share/info-cache.rktd, written by `raco setup`).  The cross-installed payload has none, so DrRacket started
;; without ANY tool.  The host's 9.3 installation has the cache for the same package versions: keep the entries whose package is in the
;; payload and whose directory exists there.
(require racket/file racket/list racket/path)
(define-values (host-share tree) (apply values (vector->list (current-command-line-arguments))))
(define entries (file->value (build-path host-share "info-cache.rktd")))
(define pkgs-dir (build-path tree "share" "pkgs"))
(define (exists? e)
  ;; e = ((rel #"pkgs" #"name" #"sub" ...) keys lib 1 0)
  (define spec (car e))
  (and (pair? spec) (eq? (car spec) 'rel)
       (directory-exists? (apply build-path tree "share" (map bytes->path (cdr spec))))))
(define kept (filter exists? entries))
(with-output-to-file (build-path tree "share" "info-cache.rktd") #:exists 'truncate
  (lambda () (write kept)))
(printf "info-cache: ~a of ~a entries kept (~a with tools)\n" (length kept) (length entries)
        (length (filter (lambda (e) (memq 'tools (cadr e))) kept)))

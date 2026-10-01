#lang racket/base
;; Findet Style-Flags, die ein Referenz-Backend (gtk/cocoa/win32) in einer
;; Datei auswertet, die Qt-Entsprechung aber nie liest.
;;
;; Hintergrund: docs/HACKING.md §64.7.  Freier Test 2026-10-01: Tabs ohne [x] und
;; ohne Drag-Umsortieren (`'can-close`/`'can-reorder` wurden in wx/qt/tab-panel.rkt
;; nie gelesen).  tests/stub-audit.rkt findet das nicht: es sucht Methoden, die
;; strukturell leer sind -- hier ist aber keine Methode leer, ein *Flag* wird nur
;; nicht ausgewertet.
;;
;; Verfahren (reine Textanalyse, braucht weder PLT_QT noch Shim noch Qt):
;;   Pro qt-Datei F mit gleichnamiger Datei in mindestens einem Referenz-Backend
;;   werden alle Symbole gesammelt, die in der Form (memq|member|memv 'SYM <ausdruck>)
;;   vorkommen -- so liest ein Backend `style`-Listen.  Gemeldet wird jedes
;;   Symbol, das ein Referenz-Backend in der gleichnamigen Datei liest und F nicht.
;; Grenzen: Flags, die ein Backend nur über andere Formen auswertet (case, eq? auf
;; Listenelemente, shared code in wxcanvas.rkt etc.), werden nicht gesehen; und
;; ein gefundenes Flag kann im gemeinsamen Code bereits behandelt sein -- die
;; Allowlist-Spalte "Begründung" hält die Triage fest.
;;
;; Gate wie beim stub-audit: ein neuer Fund ohne Allowlist-Eintrag lässt den Test
;; scheitern, ebenso ein Allowlist-Eintrag, der nicht mehr (in denselben Dateien)
;; auftaucht.  Allowlist: tests/style-audit-allowlist.rktd, Einträge
;;   (flag (qt-datei ...) status "Begründung")   status: fixed | backlog | harmless

(require racket/file
         racket/list
         racket/path
         racket/port
         racket/runtime-path
         racket/set
         racket/system
         rackunit)

(provide find-style-gaps load-allowlist gate)

(define-runtime-path WX "../third_party/gui/gui-lib/mred/private/wx")
(define-runtime-path REPO-GUI "../third_party/gui")
(define-runtime-path ALLOWLIST-PATH "style-audit-allowlist.rktd")
(define BACKENDS '("gtk" "cocoa" "win32"))

(define (read-forms path)
  (call-with-input-file path
    (lambda (in)
      (read-line in) ; "#lang ..." verwerfen
      (let loop ([acc '()])
        (define s (read in))
        (if (eof-object? s) (reverse acc) (loop (cons s acc)))))))

(define (quoted-sym? e)
  (and (pair? e) (eq? (car e) 'quote) (pair? (cdr e)) (symbol? (cadr e))))

(define (file-style-syms path)
  (define acc (mutable-set))
  (let walk ([e (read-forms path)])
    (cond
      [(and (pair? e) (memq (car e) '(memq member memv))
            (pair? (cdr e)) (quoted-sym? (cadr e)))
       (set-add! acc (cadr (cadr e)))
       (walk (cddr e))]
      [(pair? e) (walk (car e)) (walk (cdr e))]
      [else (void)]))
  (set->list acc))

;; -> (listof (list flag (qt-basename ...) (backend ...)))  sortiert nach flag
(define (find-style-gaps [wx WX])
  (define per-flag (make-hasheq)) ; flag -> (cons files backends)
  (for ([qf (in-list (directory-list (build-path wx "qt") #:build? #t))]
        #:when (regexp-match? #rx"[.]rkt$" (path->string qf)))
    (define name (file-name-from-path qf))
    (define qt-syms (file-style-syms qf))
    (for ([b (in-list BACKENDS)])
      (define rf (build-path wx b name))
      (when (file-exists? rf)
        (for ([s (in-list (file-style-syms rf))] #:unless (memq s qt-syms))
          (define cur (hash-ref per-flag s (cons '() '())))
          (hash-set! per-flag s
                     (cons (remove-duplicates (cons (path->string name) (car cur)))
                           (remove-duplicates (cons b (cdr cur)))))))))
  (sort (for/list ([(f v) (in-hash per-flag)])
          (list f (sort (car v) string<?) (sort (cdr v) string<?)))
        symbol<? #:key car))

(define (load-allowlist)
  (if (file-exists? ALLOWLIST-PATH) (file->list ALLOWLIST-PATH) '()))

;; -> (values neue-funde veraltete-eintraege)
(define (gate gaps allowlist)
  (define (key flag files) (cons flag files))
  (define gap-keys (for/list ([g gaps]) (key (car g) (cadr g))))
  (define allow-keys (for/list ([e allowlist]) (key (car e) (map symbol->string (cadr e)))))
  (values (filter (lambda (g) (not (member (key (car g) (cadr g)) allow-keys))) gaps)
          (filter (lambda (e) (not (member (key (car e) (map symbol->string (cadr e))) gap-keys)))
                  allowlist)))

(module+ test
  (define gaps (find-style-gaps))
  (define allow (load-allowlist))
  (define-values (new-gaps stale) (gate gaps allow))
  (test-case "keine neuen Style-Flag-Lücken ohne Allowlist-Eintrag"
    (check-equal? new-gaps '()))
  (test-case "kein veralteter Allowlist-Eintrag"
    (check-equal? (map car stale) '()))
  (test-case "Recall: das Audit hätte 'can-close/'can-reorder gefunden (tab-panel.rkt vor §64.7)"
    ;; gui-Submodul-Stand 61509bb6 = letzter Stand ohne die Tab-Flags.  Braucht git.
    (define tmp (make-temporary-file "style-audit~a" 'directory))
    (for ([b (cons "qt" BACKENDS)])
      (copy-directory/files (build-path WX b) (build-path tmp b)))
    (define old-src
      (with-output-to-string
        (lambda ()
          (parameterize ([current-directory REPO-GUI])
            (system* (find-executable-path "git") "show"
                     "61509bb6:gui-lib/mred/private/wx/qt/tab-panel.rkt")))))
    (check-true (> (string-length old-src) 100))
    (with-output-to-file (build-path tmp "qt" "tab-panel.rkt") #:exists 'truncate
      (lambda () (write-string old-src)))
    (define old-gaps (find-style-gaps tmp))
    (delete-directory/files tmp)
    (for ([f '(can-close can-reorder)])
      (check-not-false (assq f old-gaps) (format "~a nicht gefunden" f)))))

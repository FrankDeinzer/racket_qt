#lang racket/base
;; Findet Methoden, die ein Referenz-Backend (gtk/cocoa/win32) in einer Datei
;; definiert, die Qt-Entsprechung aber GAR NICHT hat (weder selbst noch geerbt noch
;; vom Glue-Layer per public*/override* hinzugefügt).
;;
;; Hintergrund: docs/HACKING.md §65.  Dritte statische Audit-Klasse neben
;; tests/stub-audit.rkt (leere Stubs) und tests/style-audit.rkt (ungelesene
;; Style-Flags).  Solche Lücken fallen sonst erst zur Laufzeit als "no method"
;; auf, und zwar nur auf dem Codepfad, der die Methode aufruft.
;;
;; Verfahren (reine Textanalyse per `read`, braucht weder PLT_QT noch Shim noch Qt):
;;   * Methoden einer Datei = Namen aus (define/public|override|augment|pubment|
;;     overment|augride|... NAME ...) sowie (public|override|augment|pubment ...)-
;;     Klauseln (bei [intern extern] zählt der externe Name).  define/private zählt nicht.
;;   * "Qt hat M" für Datei F = M ist in F definiert, ODER in einer Qt-Klasse/einem
;;     Mixin, auf das F transitiv verweist (Oberklasse-Kette, Schlüssel: Toplevel-
;;     Namen, die auf % enden oder mixin/glue enthalten), ODER der Glue-Layer
;;     (mred/private/wx*.rkt, wx/common/*.rkt) definiert/fügt M per public*/override*/
;;     define/public usw. hinzu (HACKING §1: dann darf die Plattform-Klasse M gar
;;     nicht definieren -- keine Lücke).
;;   * Nur Methoden zählen, die der gemeinsame Code (mred/private/*.rkt, wx/common/
;;     *.rkt) per (send OBJ NAME ...)/inherit aufruft; der Rest ist Plattform-intern
;;     des Referenz-Backends (get-cocoa-content, get-hwnd, ...) und keine Lücke.
;;   * Gemeldet wird pro Methode: (name (qt-datei ...) (backend ...)).
;; Grenzen: Methoden, die ein Backend in Hilfsklassen derselben Datei definiert,
;; werden mitgezählt (False Positives -> Allowlist `harmless`); dynamisch erzeugte
;; Methoden und Init-Argumente (siehe `find-init-gaps`, nur informativ) werden nicht
;; geprüft; ein Fund heißt nur "Name fehlt", nicht "wird je aufgerufen" -- diese
;; Triage steht in der Allowlist.
;;
;; Gate wie beim stub-/style-audit: neuer Fund ohne Allowlist-Eintrag oder
;; veralteter Eintrag (Name/Dateien stimmen nicht mehr) -> Fehler.
;; Allowlist: tests/api-audit-allowlist.rktd, Einträge
;;   (methode (qt-datei ...) status "Begründung")   status: backlog | harmless

(require racket/file
         racket/list
         racket/path
         racket/port
         racket/runtime-path
         racket/set
         racket/system
         rackunit)

(provide find-api-gaps load-allowlist gate)

(define-runtime-path PRIV "../third_party/gui/gui-lib/mred/private")
(define-runtime-path WX "../third_party/gui/gui-lib/mred/private/wx")
(define-runtime-path REPO-GUI "../third_party/gui")
(define-runtime-path ALLOWLIST-PATH "api-audit-allowlist.rktd")
(define BACKENDS '("gtk" "cocoa" "win32"))

(define (read-forms path)
  (call-with-input-file path
    (lambda (in)
      (when (regexp-match? #rx"^#(lang|!)" (peek-string 5 0 in))
        (read-line in)) ; "#lang ..." verwerfen (manche Dateien starten mit (module ...))
      (let loop ([acc '()])
        (define s (read in))
        (if (eof-object? s) (reverse acc) (loop (cons s acc)))))))

(define DEFINERS
  '(define/public define/override define/augment define/pubment define/overment
    define/augride define/public-final define/override-final define/augment-final
    define/public* define/override* define/augment* define/pubment*))
(define CLAUSERS
  '(public override augment pubment overment augride public-final override-final
    augment-final public* override* augment* pubment* overment*))

(define (clause-name c)
  (cond [(symbol? c) c]
        [(and (pair? c) (symbol? (car c)))
         (if (and (pair? (cdr c)) (symbol? (cadr c)) (memq (car c) '()) ) (cadr c) (car c))]
        [else #f]))

;; [intern extern]: bei public/override ist der zweite Name der externe.
(define (clause-external c)
  (cond [(symbol? c) c]
        [(and (pair? c) (symbol? (car c)) (pair? (cdr c)) (symbol? (cadr c))
              (null? (cddr c)))
         (cadr c)]
        [(and (pair? c) (symbol? (car c))) (car c)]
        [else #f]))

;; alle Methodennamen, die irgendwo in `e` definiert werden
(define (methods-in e)
  (define acc (mutable-seteq))
  (let walk ([e e])
    (cond
      [(and (pair? e) (memq (car e) DEFINERS) (pair? (cdr e)))
       (define h (cadr e))
       (define n (let loop ([h h]) (cond [(symbol? h) h] [(pair? h) (loop (car h))] [else #f])))
       (when n (set-add! acc n))
       (walk (cdr e))]
      [(and (pair? e) (memq (car e) CLAUSERS) (list? e))
       (for ([c (in-list (cdr e))])
         (define n (clause-external c))
         (when n (set-add! acc n)))
       (walk (cdr e))]
      [(pair? e) (walk (car e)) (walk (cdr e))]
      [else (void)]))
  acc)

(define (symbols-in e)
  (define acc (mutable-seteq))
  (let walk ([e e])
    (cond [(symbol? e) (set-add! acc e)]
          [(pair? e) (walk (car e)) (walk (cdr e))]
          [else (void)]))
  acc)

(define (follow-name? s)
  (define str (symbol->string s))
  (or (regexp-match? #rx"%$" str) (regexp-match? #rx"mixin|glue" str)))

(define (toplevel-name f)
  (and (pair? f) (memq (car f) '(define define-values)) (pair? (cdr f))
       (let ([h (cadr f)])
         (cond [(symbol? h) (list h)]
               [(and (pair? h) (symbol? (car h))) (list (car h))]
               [(and (eq? (car f) 'define-values) (list? h)) h]
               [else #f]))))

(define (send-targets e acc [inherit? #t])
  (let walk ([e e])
    (cond
      [(and (pair? e) (memq (car e) '(send send/apply send/keyword-apply send+ send-generic))
            (list? e) (>= (length e) 3) (symbol? (caddr e)))
       (set-add! acc (caddr e))
       (walk (cdddr e))]
      [(and (pair? e) (eq? (car e) 'send*) (list? e) (>= (length e) 2))
       (for ([c (in-list (cddr e))] #:when (and (pair? c) (symbol? (car c))))
         (set-add! acc (car c)))
       (walk (cdr e))]
      [(and inherit? (pair? e) (eq? (car e) 'inherit) (list? e))
       (for ([c (cdr e)]) (let ([n (clause-external c)]) (when n (set-add! acc n))))]
      [(pair? e) (walk (car e)) (walk (cdr e))]
      [else (void)])))

;; Namen, die der gemeinsame Code (mred/private/*.rkt, wx/common/*.rkt) per send/inherit
;; aufruft.  Methoden, die niemand dort aufruft, sind Plattform-intern des Referenz-
;; Backends (z.B. get-cocoa-content) und keine Lücke der Qt-Oberfläche.
(define (shared-callers priv)
  (define acc (mutable-seteq))
  (for ([dir (list priv (build-path priv "wx" "common") (build-path priv ".."))])
    (for ([f (rkt-files dir)])
      ;; `inherit` zählt nur auf wx-Ebene (wx*.rkt, wx/common): in mr*.rkt meint es
      ;; mred-Methoden (z.B. set-parent), nicht die Plattform-Klasse.
      (send-targets (read-forms f) acc
                    (or (equal? dir (build-path priv "wx" "common"))
                        (regexp-match? #rx"/wx[^/]*[.]rkt$" (path->string f))))))
  acc)

(define (rkt-files dir)
  (for/list ([p (in-list (directory-list dir #:build? #t))]
             #:when (regexp-match? #rx"[.]rkt$" (path->string p)))
    p))

;; Glue-Layer: Methodennamen, die mred/private/*.rkt und wx/common/*.rkt hinzufügen
(define (glue-methods priv)
  (define acc (mutable-seteq))
  ;; nur die wx-Ebene: wx*.rkt und wx/common/*.rkt; die mr*.rkt-public* gehören zu den
  ;; mred-Klassen (window<%> usw.), nicht zur Plattform-Klasse.
  (for ([dir (list priv (build-path priv "wx" "common"))])
    (for ([f (rkt-files dir)]
          #:when (or (equal? dir (build-path priv "wx" "common"))
                     (regexp-match? #rx"/wx[^/]*[.]rkt$" (path->string f))))
      (for ([n (in-set (methods-in (read-forms f)))]) (set-add! acc n))))
  acc)

;; Toplevel-Graph des Qt-Backends: name -> (cons methoden-set verweise)
(define (qt-graph wx)
  (define g (make-hasheq))
  (define per-file (make-hash)) ; basename -> (listof name)
  (for ([f (rkt-files (build-path wx "qt"))])
    (define bn (path->string (file-name-from-path f)))
    (for ([form (read-forms f)])
      (define names (toplevel-name form))
      (when names
        (define ms (methods-in form))
        (define refs (for/list ([s (in-set (symbols-in form))] #:when (follow-name? s)) s))
        (for ([n names])
          (define cur (hash-ref g n (cons (mutable-seteq) '())))
          (for ([m (in-set ms)]) (set-add! (car cur) m))
          (hash-set! g n (cons (car cur) (append refs (cdr cur))))
          (hash-update! per-file bn (lambda (l) (cons n l)) '())))))
  (values g per-file))

(define (closure-methods g roots)
  (define seen (mutable-seteq))
  (define out (mutable-seteq))
  (let loop ([ns roots])
    (for ([n ns] #:unless (set-member? seen n))
      (set-add! seen n)
      (define e (hash-ref g n #f))
      (when e
        (for ([m (in-set (car e))]) (set-add! out m))
        (loop (cdr e)))))
  out)

;; -> (listof (list methode (qt-basename ...) (backend ...)))  sortiert
(define (find-api-gaps [wx WX] [priv PRIV] #:all? [all? #f])
  (define glue (glue-methods priv))
  (define callers (shared-callers priv))
  (define-values (g per-file) (qt-graph wx))
  (define per-m (make-hasheq))
  (for ([(bn roots) (in-hash per-file)])
    (define qt-has (closure-methods g roots))
    (for ([b (in-list BACKENDS)])
      (define rf (build-path wx b bn))
      (when (file-exists? rf)
        (for ([m (in-set (methods-in (read-forms rf)))]
              #:unless (set-member? qt-has m)
              #:unless (set-member? glue m)
              #:when (or all? (set-member? callers m)))
          (define cur (hash-ref per-m m (cons '() '())))
          (hash-set! per-m m
                     (cons (remove-duplicates (cons bn (car cur)))
                           (remove-duplicates (cons b (cdr cur)))))))))
  (sort (for/list ([(m v) (in-hash per-m)])
          (list m (sort (car v) string<?) (sort (cdr v) string<?)))
        symbol<? #:key car))

(define (load-allowlist)
  (if (file-exists? ALLOWLIST-PATH) (file->list ALLOWLIST-PATH) '()))

(define (key m files) (cons m files))
;; -> (values neue-funde veraltete-eintraege)
(define (gate gaps allowlist)
  (define gap-keys (for/list ([g gaps]) (key (car g) (cadr g))))
  (define allow-keys (for/list ([e allowlist]) (key (car e) (map symbol->string (cadr e)))))
  (values (filter (lambda (g) (not (member (key (car g) (cadr g)) allow-keys))) gaps)
          (filter (lambda (e) (not (member (key (car e) (map symbol->string (cadr e))) gap-keys)))
                  allowlist)))

(module+ main
  (printf "relevante Funde (vom gemeinsamen Code aufgerufen): ~a\n" (length (find-api-gaps)))
  (printf "Plattform-intern (nicht gemeldet): ~a\n"
          (- (length (find-api-gaps #:all? #t)) (length (find-api-gaps))))
  (for ([g (find-api-gaps)])
    (printf "~a ~a ~a\n" (car g) (cadr g) (caddr g))))

(module+ test
  (define gaps (find-api-gaps))
  (define allow (load-allowlist))
  (define-values (new-gaps stale) (gate gaps allow))
  (test-case "keine neuen API-Lücken ohne Allowlist-Eintrag"
    (check-equal? new-gaps '()))
  (test-case "kein veralteter Allowlist-Eintrag"
    (check-equal? (map car stale) '()))
  (test-case "Allowlist-Status gültig und begründet"
    (for ([e allow])
      (check-true (and (memq (caddr e) '(backlog harmless)) (string? (cadddr e))
                       (> (string-length (cadddr e)) 10))
                  (format "~a" (car e)))))
  (test-case "Recall: das Audit hätte destroy/set-label-top/scroll/get-client-handle/get-wheel-steps-mode gefunden (Stand vor §65)"
    ;; gui-Submodul-Stand d82585ad = letzter Stand ohne die §65-Fixes.  Braucht git.
    (define tmp (make-temporary-file "api-audit~a" 'directory))
    (for ([b (cons "qt" BACKENDS)])
      (copy-directory/files (build-path WX b) (build-path tmp b)))
    (for ([f '("frame.rkt" "menu-bar.rkt" "window.rkt" "canvas.rkt")])
      (define old-src
        (with-output-to-string
          (lambda ()
            (parameterize ([current-directory REPO-GUI])
              (system* (find-executable-path "git") "show"
                       (string-append "d82585ad:gui-lib/mred/private/wx/qt/" f))))))
      (check-true (> (string-length old-src) 100) f)
      (with-output-to-file (build-path tmp "qt" f) #:exists 'truncate
        (lambda () (write-string old-src))))
    (define old-gaps (find-api-gaps tmp))
    (delete-directory/files tmp)
    (for ([m '(destroy set-label-top scroll get-client-handle get-wheel-steps-mode)])
      (check-not-false (assq m old-gaps) (format "~a nicht gefunden" m)))))

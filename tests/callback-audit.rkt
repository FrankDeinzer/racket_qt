#lang racket/base
;; Findet Callbacks/Events, die ein Referenz-Backend (gtk/cocoa/win32) in einer Klasse
;; SELBST AUSLOEST (Aufruf `(on-size ..)`, `(queue-on-size)`, `(send this on-close)` ...), das
;; Qt-Backend in derselben Klasse (samt Oberklassen) aber NIE -- obwohl der gemeinsame Code
;; die Methode ueberschreibt/definiert.  Die Klasse des `canvas% on-size`-Bugs (HACKING §78.4):
;; die Methode existiert (der API-Audit ist gruen), wird aber nie aufgerufen, sodass
;; DrRacket/framework-Overrides nie laufen.  Hintergrund: docs/HACKING.md §80.
;;
;; Verfahren (reine Textanalyse per `read`, kein PLT_QT, kein Shim):
;;   * HOOKS = Namen, die dem Muster ^(on-|do-on-|queue-|pre-on|call-pre-on) folgen, vom
;;     gemeinsamen Code (mred/private/*.rkt, wx/common/*.rkt) per define/public|override|
;;     augment ... oder public*/override*-Klausel DEFINIERT werden und die mindestens ein
;;     Referenz-Backend irgendwo aufruft (Menge `hook-names`).
;;   * "Aufruf" einer Datei = Name steht in Kopfposition `(H ...)` oder als Methode in
;;     `(send OBJ H ...)` (auch in Lambdas/Thunks, z.B. fuer queue-window-event/qt-queue-
;;     window-event).  Nicht gezaehlt: Definitionskoepfe, `(super H ..)` (Weiterreichen),
;;     inherit/public/override-Klauseln.
;;   * Pro Datei F und Backend: R(F) = Aufrufe in allen Klassen, die F transitiv ueber
;;     %-/mixin-/glue-Namen erreicht (Oberklassen, z.B. window% in window.rkt -- dort steht
;;     gtks `queue-on-size` in `set-size`).  Q(F) = dasselbe fuer die Qt-Datei, ZUSAETZLICH
;;     ueber Hilfsfunktionen des Qt-Backends, deren Name `qt-` beginnt (Event-Posting-
;;     Helfer in utils.rkt/queue.rkt, z.B. qt-queue-window-event).
;;   * Fund = H in R(F), nicht in Q(F).  Aggregiert pro Hook: (hook (qt-datei ..) (backend ..)).
;; Blindstellen: Auslosung ueber Symbole/dynamischen Dispatch (`(send o (quote ..))`,
;; `dynamic-send`) wird nicht gesehen; ein Hook, der nur ueber eine Funktion ausserhalb des
;; Closure-Schemas erreicht wird, erscheint als Fund (Fehlalarm der sicheren Art -> Allowlist
;; `harmless`); umgekehrt zaehlt jeder Aufruf im Closure als Ausloesung, auch wenn er auf
;; einem Zweig liegt, der nie laeuft (zu gutmuetig).  Ein Fund heisst "Qt ruft H nie auf",
;; nicht "H wird gebraucht" -- die Triage steht in der Allowlist.
;;
;; Gate wie bei den anderen Audits: neuer Fund ohne Allowlist-Eintrag oder veralteter
;; Eintrag (Name/Dateien stimmen nicht mehr) -> Fehler.
;; Allowlist: tests/callback-audit-allowlist.rktd, Eintraege
;;   (hook (qt-datei ...) status "Begruendung")   status: backlog | harmless

(require racket/file
         racket/list
         racket/path
         racket/port
         racket/runtime-path
         racket/set
         racket/system
         rackunit)

(provide find-callback-gaps load-allowlist gate)

(define-runtime-path PRIV "../third_party/gui/gui-lib/mred/private")
(define-runtime-path WX "../third_party/gui/gui-lib/mred/private/wx")
(define-runtime-path REPO-GUI "../third_party/gui")
(define-runtime-path ALLOWLIST-PATH "callback-audit-allowlist.rktd")
(define BACKENDS '("gtk" "cocoa" "win32"))
(define HOOK-RX #px"^(on-|do-on-|queue-|pre-on|call-pre-on)")
;; Ereignis-Hooks ohne on-/queue-Praefix (vom gemeinsamen Code definiert, vom Backend selbst ausgeloest)
(define EXTRA-HOOKS '(display-changed resized))

(define (read-forms path)
  (call-with-input-file path
    (lambda (in)
      (when (regexp-match? #rx"^#(lang|!)" (peek-string 5 0 in)) (read-line in))
      (let loop ([acc '()])
        (define s (read in))
        (if (eof-object? s) (reverse acc) (loop (cons s acc)))))))

(define (rkt-files dir)
  (for/list ([p (in-list (directory-list dir #:build? #t))]
             #:when (regexp-match? #rx"[.]rkt$" (path->string p)))
    p))

(define DEFINERS
  '(define/public define/override define/augment define/pubment define/overment
    define/augride define/public-final define/override-final define/augment-final
    define/public* define/override* define/augment* define/pubment*))
(define PRIVATE-DEFINERS '(define/private))
(define CLAUSERS
  '(public override augment pubment overment augride public-final override-final
    augment-final public* override* augment* pubment* overment*))
(define NOCALL-CLAUSES '(inherit inherit-field inherit/super inherit/inner rename-super))

;; Namen, die in `e` als Methode DEFINIERT werden (Definer + Klauseln, externer Name)
(define (defined-names e)
  (define acc (mutable-seteq))
  (let walk ([e e])
    (cond
      [(and (pair? e) (memq (car e) DEFINERS) (pair? (cdr e)))
       (let loop ([h (cadr e)]) (cond [(symbol? h) (set-add! acc h)] [(pair? h) (loop (car h))]))
       (walk (cddr e))]
      [(and (pair? e) (memq (car e) CLAUSERS) (list? e))
       (for ([c (in-list (cdr e))])
         (cond [(symbol? c) (set-add! acc c)]
               [(and (pair? c) (symbol? (car c)))
                (set-add! acc (if (and (pair? (cdr c)) (symbol? (cadr c)) (null? (cddr c))) (cadr c) (car c)))
                (walk (cdr c))]))]
      [(pair? e) (walk (car e)) (walk (cdr e))]
      [else (void)]))
  acc)

;; Aufrufe: Kopfposition `(H ..)` und `(send o H ..)`; ueberspringt Definitionskoepfe,
;; super-Aufrufe und inherit-Klauseln, laeuft aber in Methodenkoerper und Lambdas.
(define (calls-in e)
  (define acc (mutable-seteq))
  (let walk ([e e])
    (cond
      [(and (pair? e) (or (memq (car e) DEFINERS) (memq (car e) PRIVATE-DEFINERS)) (pair? (cdr e)))
       (walk (cddr e))]
      [(and (pair? e) (memq (car e) CLAUSERS) (list? e))
       (for ([c (in-list (cdr e))]) (when (pair? c) (walk (cdr c))))]
      [(and (pair? e) (memq (car e) NOCALL-CLAUSES)) (void)]
      [(and (pair? e) (eq? (car e) 'super)) (when (list? e) (walk (if (pair? (cdr e)) (cddr e) '())))]
      [(and (pair? e) (memq (car e) '(send send/apply send/keyword-apply send+))
            (list? e) (>= (length e) 3) (symbol? (caddr e)))
       (set-add! acc (caddr e)) (walk (cadr e)) (walk (cdddr e))]
      [(and (pair? e) (eq? (car e) 'send*) (list? e) (>= (length e) 2))
       (walk (cadr e))
       (for ([c (cddr e)] #:when (pair? c))
         (when (symbol? (car c)) (set-add! acc (car c)))
         (walk (cdr c)))]
      [(pair? e)
       (when (symbol? (car e)) (set-add! acc (car e)))
       (walk (car e))
       (when (pair? (cdr e)) (walk (cdr e)))]
      [else (void)]))
  acc)

(define (symbols-in e)
  (define acc (mutable-seteq))
  (let walk ([e e])
    (cond [(symbol? e) (set-add! acc e)]
          [(pair? e) (walk (car e)) (walk (cdr e))]
          [else (void)]))
  acc)

(define (toplevel-name f)
  (and (pair? f) (memq (car f) '(define define-values defclass)) (pair? (cdr f))
       (let ([h (cadr f)])
         (cond [(symbol? h) (list h)]
               [(and (pair? h) (symbol? (car h))) (list (car h))]
               [(and (eq? (car f) 'define-values) (list? h)) h]
               [else #f]))))

(define (class-follow? s)
  (define str (symbol->string s))
  (or (regexp-match? #rx"%$" str) (regexp-match? #rx"mixin|glue" str)))

;; Qt-seitig zusaetzlich: Event-Posting-Helfer (`qt-...`)
(define (qt-helper? s) (regexp-match? #rx"^qt-" (symbol->string s)))

;; Graph eines Backends: name -> (cons aufrufe-set verweise); per-file: basename -> toplevel-namen
(define (backend-graph dir qt?)
  (define g (make-hasheq))
  (define per-file (make-hash))
  (for ([f (rkt-files dir)])
    (define bn (path->string (file-name-from-path f)))
    (for ([form (read-forms f)])
      (define names (toplevel-name form))
      (when names
        (define cs (calls-in form))
        (define refs
          (for/list ([s (in-set (symbols-in form))]
                     #:when (or (class-follow? s) (and qt? (qt-helper? s))))
            s))
        (for ([n names])
          (define cur (hash-ref g n (cons (mutable-seteq) '())))
          (for ([c (in-set cs)]) (set-add! (car cur) c))
          (hash-set! g n (cons (car cur) (append refs (cdr cur))))
          (hash-update! per-file bn (lambda (l) (cons n l)) '())))))
  (values g per-file))

(define (closure-calls g roots)
  (define seen (mutable-seteq))
  (define out (mutable-seteq))
  (let loop ([ns roots])
    (for ([n ns] #:unless (set-member? seen n))
      (set-add! seen n)
      (define e (hash-ref g n #f))
      (when e
        (for ([c (in-set (car e))]) (set-add! out c))
        (loop (cdr e)))))
  out)

;; Hook-Universum: vom gemeinsamen Code definierte Namen mit Hook-Muster, die ein Backend aufruft
(define (shared-defined priv)
  (define acc (mutable-seteq))
  (for ([dir (list priv (build-path priv "wx" "common"))])
    (for ([f (rkt-files dir)])
      (for ([n (in-set (defined-names (read-forms f)))]) (set-add! acc n))))
  acc)

(define (backend-called-anywhere wx)
  (define acc (mutable-seteq))
  (for ([b (in-list BACKENDS)])
    (for ([f (rkt-files (build-path wx b))])
      (for ([c (in-set (calls-in (read-forms f)))]) (set-add! acc c))))
  acc)

(define (hook-names wx priv)
  (define shared (shared-defined priv))
  (define called (backend-called-anywhere wx))
  (for/seteq ([n (in-set shared)]
              #:when (or (regexp-match? HOOK-RX (symbol->string n)) (memq n EXTRA-HOOKS))
              #:when (set-member? called n))
    n))

;; -> (listof (list hook (qt-basename ...) (backend ...)))  sortiert
(define (find-callback-gaps [wx WX] [priv PRIV])
  (define hooks (hook-names wx priv))
  (define-values (qg qper) (backend-graph (build-path wx "qt") #t))
  (define per-h (make-hasheq))
  (for ([b (in-list BACKENDS)])
    (define-values (rg rper) (backend-graph (build-path wx b) #f))
    (for ([(bn qroots) (in-hash qper)])
      (when (hash-ref rper bn #f)
        (define r (closure-calls rg (hash-ref rper bn)))
        (define q (closure-calls qg qroots))
        (for ([h (in-set hooks)]
              #:when (set-member? r h)
              #:unless (set-member? q h))
          (define cur (hash-ref per-h h (cons '() '())))
          (hash-set! per-h h (cons (remove-duplicates (cons bn (car cur)))
                                   (remove-duplicates (cons b (cdr cur)))))))))
  (sort (for/list ([(h v) (in-hash per-h)])
          (list h (sort (car v) string<?) (sort (cdr v) string<?)))
        symbol<? #:key car))

(define (load-allowlist)
  (if (file-exists? ALLOWLIST-PATH) (file->list ALLOWLIST-PATH) '()))

(define (key m files) (cons m files))
(define (gate gaps allowlist)
  (define gap-keys (for/list ([g gaps]) (key (car g) (cadr g))))
  (define allow-keys (for/list ([e allowlist]) (key (car e) (map symbol->string (cadr e)))))
  (values (filter (lambda (g) (not (member (key (car g) (cadr g)) allow-keys))) gaps)
          (filter (lambda (e) (not (member (key (car e) (map symbol->string (cadr e))) gap-keys)))
                  allowlist)))

(module+ main
  (define gaps (find-callback-gaps))
  (printf "Funde: ~a\n" (length gaps))
  (for ([g gaps]) (printf "~a ~a ~a\n" (car g) (cadr g) (caddr g))))
;; Recall (HACKING §80): gui 1f3c18e0 = Stand VOR §78; dort fehlte in canvas.rkt der queue-on-size-Aufruf
;; in `set-size`.  Der Audit muss queue-on-size fuer canvas.rkt finden.  Der Stand wird als Ganzes
;; (Verzeichnis qt/) aus git geholt; braucht `git` im PATH.
(module+ test
  (define gaps (find-callback-gaps))
  (define allow (load-allowlist))
  (define-values (new-gaps stale) (gate gaps allow))
  (test-case "keine neuen Callback-Luecken ohne Allowlist-Eintrag"
    (check-equal? new-gaps '()))
  (test-case "kein veralteter Allowlist-Eintrag"
    (check-equal? (map car stale) '()))
  (test-case "Allowlist-Status gueltig und begruendet"
    (for ([e allow])
      (check-true (and (memq (caddr e) '(backlog harmless)) (string? (cadddr e))
                       (> (string-length (cadddr e)) 10))
                  (format "~a" (car e)))))
  (test-case "Recall: das Audit haette canvas% on-size (queue-on-size) gefunden (Stand vor §78, 1f3c18e0)"
    (define tmp (make-temporary-file "callback-audit~a" 'directory))
    (for ([b BACKENDS])
      (copy-directory/files (build-path WX b) (build-path tmp b)))
    (make-directory (build-path tmp "qt"))
    (define names
      (with-output-to-string
        (lambda ()
          (parameterize ([current-directory REPO-GUI])
            (system* (find-executable-path "git") "ls-tree" "--name-only"
                     "1f3c18e0:gui-lib/mred/private/wx/qt/")))))
    (for ([f (regexp-split #rx"\n" names)] #:when (regexp-match? #rx"[.]rkt$" f))
      (define src
        (with-output-to-string
          (lambda ()
            (parameterize ([current-directory REPO-GUI])
              (system* (find-executable-path "git") "show"
                       (string-append "1f3c18e0:gui-lib/mred/private/wx/qt/" f))))))
      (with-output-to-file (build-path tmp "qt" f) #:exists 'truncate
        (lambda () (write-string src))))
    (define old-gaps (find-callback-gaps tmp))
    (delete-directory/files tmp)
    (define g (assq 'queue-on-size old-gaps))
    (check-not-false g "queue-on-size nicht gefunden")
    (when g (check-not-false (member "canvas.rkt" (cadr g)) "canvas.rkt fehlt in den Funden")))
  (test-case "Regression: window% set-size loest queue-on-size aus (§80), kein Fund mehr"
    (check-false (assq 'queue-on-size gaps))))

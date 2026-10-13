#lang racket/base
;; Findet Init-Argumente, die ein Referenz-Backend (gtk/cocoa/win32) in einer
;; Klasse deklariert UND im Klassenkörper benutzt, die gleichnamige Qt-Klasse in
;; der gleichnamigen Datei aber (a) gar nicht deklariert ("missing") oder
;; (b) deklariert und nie benutzt ("unused" -- der §74.1-Fall: `font` wurde in
;; sechs Steuerelementen entgegengenommen und verworfen).
;;
;; Hintergrund: docs/HACKING.md §74.1 / §79.  Dritte Lückenklasse neben
;; tests/style-audit.rkt (Style-Flags) und tests/api-audit.rkt (Methoden).
;;
;; Verfahren (reine Textanalyse, braucht weder PLT_QT noch Shim noch Qt):
;;   * Jede Liste, die direkt eine (init ...)/(init-field ...)/(init-rest ...)-Klausel
;;     enthält, gilt als Klassenkörper; der Klassenname ist das Symbol des nächsten
;;     umschließenden (define N ...)/(defclass N ...)/(define-mixin N ...).
;;   * Deklariert = Name in einer init/init-field-Klausel (`[(intern extern) dflt]`
;;     zählt unter beiden Namen).  Benutzt = Symbol kommt im Klassenkörper
;;     ausserhalb der init-Klauseln vor (auch als `[name name]`-Weitergabe an super-new).
;;   * Soll-Liste: das Referenz-Backend.  Gemeinsamer Code (mred/private/wx*.rkt) ruft
;;     die wx-Klassen per `make-object` POSITIONAL auf -- jedes dort deklarierte
;;     Init-Argument wird also tatsächlich übergeben; deshalb genügt die Deklaration
;;     der Referenzklasse als Soll.
;; Grenzen/Blindstellen: nur gleichnamige Klassen in gleichnamigen Dateien (fehlt die
;; Qt-Klasse ganz, ist das Sache des api-audit); Vererbung über Dateigrenzen wird nicht
;; verfolgt (ein in item.rkt behandeltes Init-Arg erscheint als "unused" in
;; gtk-Unterklassen nicht, in Qt aber schon -- dann Triage per Hand); eine reine
;; Weitergabe `[x x]` an window% zählt als "benutzt", auch wenn window% sie verwirft;
;; ein `init-field` zählt für Qt immer als "benutzt" (Feld wird gespeichert);
;; Umbenannte Init-Argumente (positional gleich, anderer Name) erscheinen als "missing".
;;
;; Allowlist: tests/init-audit-allowlist.rktd, Einträge
;;   (qt-datei klasse initarg kind status "Begründung")   status: backlog | harmless
;; Gate wie bei den anderen Audits: neuer Fund ohne Eintrag oder veralteter Eintrag
;; lässt den Test scheitern.

(require racket/file
         racket/list
         racket/path
         racket/port
         racket/runtime-path
         racket/system
         rackunit)

(provide find-init-gaps load-allowlist gate)

(define-runtime-path WX "../third_party/gui/gui-lib/mred/private/wx")
(define-runtime-path REPO-GUI "../third_party/gui")
(define-runtime-path ALLOWLIST-PATH "init-audit-allowlist.rktd")
(define BACKENDS '("gtk" "cocoa" "win32"))
(define INIT-HEADS '(init init-field init-rest))
(define DECL-HEADS '(define defclass define-mixin define-values))

(define (read-forms-from in)
  (read-line in) ; "#lang ..." verwerfen
  (let loop ([acc '()])
    (define s (read in))
    (if (eof-object? s) (reverse acc) (loop (cons s acc)))))

(define (read-forms path)
  (with-handlers ([exn:fail? (lambda (e) '())])
    (call-with-input-file path read-forms-from)))

(define (init-clause? c) (and (pair? c) (memq (car c) INIT-HEADS) #t))

;; -> (listof (cons internal-sym external-sym)) ; init-field zusätzlich markiert
(define (clause-decls c)
  (define field? (eq? (car c) 'init-field))
  (if (eq? (car c) 'init-rest)
      '()
      (for/list ([d (in-list (if (list? (cdr c)) (cdr c) '()))]
                 #:when (or (symbol? d) (and (pair? d) (or (symbol? (car d)) (pair? (car d))))))
        (define n (if (symbol? d) d (car d)))
        (define-values (in ex)
          (if (pair? n) (values (car n) (if (pair? (cdr n)) (cadr n) (car n))) (values n n)))
        (list in ex field?))))

(define SUPER-KEY '|#super|)
(define SUPER-HEADS '(super-new super-make-object))

;; Entfernt aus e alle `[key sym]`-Paare in super-new-Aufrufen, deren key kein
;; irgendwo in wx/qt deklariertes Init-Argument ist (reine Weitergabe ins Leere).
(define (strip-dead-passthrough e declared)
  (cond
    [(and (pair? e) (memq (car e) SUPER-HEADS) (list? e))
     (cons (car e)
           (for/list ([a (in-list (cdr e))]
                      #:unless (and (list? a) (= (length a) 2) (symbol? (car a))
                                    (symbol? (cadr a)) (not (memq (car a) declared))))
             a))]
    [(pair? e) (cons (strip-dead-passthrough (car e) declared)
                     (strip-dead-passthrough (cdr e) declared))]
    [else e]))

(define (count-sym e s)
  (cond [(eq? e s) 1]
        [(pair? e) (+ (count-sym (car e) s) (count-sym (cdr e) s))]
        [else 0]))

;; class-info: name -> hash(extern-sym -> 'field | 'used | 'unused)
;; (nur Namen; "used" heisst: im Körper ausserhalb der init-Klauseln vorhanden)
(define (collect-classes forms [declared #f])  ; roh: Tabellen enthalten SUPER-KEY
  (define classes (make-hasheq)) ; name -> (hasheq extern -> status)
  (let walk ([e forms] [name #f])
    (cond
      [(pair? e)
       (define l (if (list? e) e #f))
       (define new-name
         (if (and l (pair? l) (memq (car l) DECL-HEADS) (pair? (cdr l)) (symbol? (cadr l)))
             (cadr l) name))
       (when (and l (or (ormap init-clause? l) (eq? (car l) 'defclass)))
         (define clauses (filter init-clause? l))
         (define body0 (filter (lambda (c) (not (init-clause? c))) l))
         (define body (if declared (strip-dead-passthrough body0 declared) body0))
         (define tbl (hash-ref! classes (or new-name '<anon>) make-hasheq))
         (let ([sup (case (car l)
                      [(defclass) (and (pair? (cdr l)) (pair? (cddr l)) (caddr l))]
                      [(class class*) (and (pair? (cdr l)) (cadr l))]
                      [else #f])])
           (when (symbol? sup) (hash-set! tbl SUPER-KEY sup)))
         (for* ([c clauses] [d (clause-decls c)])
           (define used (> (count-sym body (car d)) 0))
           (define st (cond [used 'used] [(caddr d) 'field] [else 'unused]))
           (define old (hash-ref tbl (cadr d) #f))
           (hash-set! tbl (cadr d)
                      (if (or (eq? old 'used) (eq? st 'used)) 'used (or old st)))))
       (let loop ([x e])
         (when (pair? x) (walk (car x) new-name) (loop (cdr x))))]
      [else (void)]))
  classes)

;; Vererbung: eine Klasse erbt die Init-Argumente ihrer Oberklasse (gtk: button% erbt
;; `font` von button-core%, check-box% erbt es aus button.rkt).  Die Oberklasse wird
;; zuerst in derselben Datei, dann in allen Dateien desselben Backends gesucht
;; (`global`: name -> Tabelle).  Eine eigene Deklaration überschreibt die geerbte
;; (gtk gauge% deklariert `font` neu und gibt es nicht an item% weiter -> ignoriert).
(define (resolve-supers classes global)
  (define (lookup name) (or (hash-ref classes name #f) (hash-ref global name #f)))
  (define (effective name seen)
    (define t (lookup name))
    (cond
      [(not t) (make-hasheq)]
      [else
       (define sup (hash-ref t SUPER-KEY #f))
       (define base (if (and sup (not (memq sup seen)))
                        (effective sup (cons name seen))
                        (make-hasheq)))
       ;; Geerbtes 'used wird zu 'used-inh (Benutzung in der Oberklasse)
       (define out (make-hasheq))
       (for ([(k v) (in-hash base)]) (hash-set! out k (if (eq? v 'used) 'used-inh v)))
       (for ([(k v) (in-hash t)] #:unless (eq? k SUPER-KEY))
         (define old (hash-ref out k #f))
         (hash-set! out k (cond [(eq? v 'used) 'used] [(eq? v 'field) (or old 'field)] [else v])))
       out]))
  (for/hasheq ([name (in-list (hash-keys classes))])
    (values name (effective name '()))))

;; Alle Klassentabellen eines Backends (name -> Tabelle, roh).
(define (backend-global wx b declared)
  (define g (make-hasheq))
  (for ([f (in-list (directory-list (build-path wx b) #:build? #t))]
        #:when (regexp-match? #rx"[.]rkt$" (path->string f)))
    (for ([(n t) (in-hash (collect-classes (read-forms f) declared))])
      (unless (hash-ref g n #f) (hash-set! g n t))))
  g)

;; -> (listof (list qt-file class init kind (backend ...)))
(define (find-init-gaps [wx WX])
  (define acc (make-hash)) ; (file class init kind) -> backends
  ;; alle in wx/qt irgendwo deklarierten Init-Namen (für strip-dead-passthrough)
  (define declared
    (remove-duplicates
     (for*/list ([qf (in-list (directory-list (build-path wx "qt") #:build? #t))]
                 #:when (regexp-match? #rx"[.]rkt$" (path->string qf))
                 [(cls t) (in-hash (collect-classes (read-forms qf)))]
                 [k (in-hash-keys t)])
       k)))
  (define qt-global (backend-global wx "qt" declared))
  (define ref-globals (for/hash ([b BACKENDS]) (values b (backend-global wx b #f))))
  (for ([qf (in-list (directory-list (build-path wx "qt") #:build? #t))]
        #:when (regexp-match? #rx"[.]rkt$" (path->string qf)))
    (define name (path->string (file-name-from-path qf)))
    (define qt-classes (resolve-supers (collect-classes (read-forms qf) declared) qt-global))
    (for ([b (in-list BACKENDS)])
      (define rf (build-path wx b name))
      (when (file-exists? rf)
        (define ref-classes (resolve-supers (collect-classes (read-forms rf)) (hash-ref ref-globals b)))
        (for* ([(cls rtbl) (in-hash ref-classes)]
               #:when (hash-ref qt-classes cls #f)
               [(init rst) (in-hash rtbl)]
               #:when (memq rst '(used used-inh)))
          (define qtbl (hash-ref qt-classes cls))
          (define qst (hash-ref qtbl init #f))
          (define kind (cond [(and (not qst) (eq? rst 'used)) 'missing]  ; geerbte Ref-Inits sind meist backend-intern (gtk, hwnd, ...)
                             [(eq? qst 'unused) 'unused]
                             [else #f]))
          (when kind
            (define k (list name cls init kind))
            (hash-set! acc k (remove-duplicates (cons b (hash-ref acc k '())))))))))
  (sort (for/list ([(k v) (in-hash acc)]) (append k (list (sort v string<?))))
        string<? #:key (lambda (g) (format "~a ~a ~a ~a" (car g) (cadr g) (caddr g) (cadddr g)))))

(define (load-allowlist)
  (if (file-exists? ALLOWLIST-PATH) (file->list ALLOWLIST-PATH) '()))

(define (gap-key g) (list (car g) (symbol->string (cadr g)) (symbol->string (caddr g)) (cadddr g)))
(define (entry-key e)
  (list (symbol->string (car e)) (symbol->string (cadr e)) (symbol->string (caddr e)) (cadddr e)))

;; -> (values neue-funde veraltete-eintraege)
(define (gate gaps allowlist)
  (define gk (map gap-key gaps))
  (define ak (map entry-key allowlist))
  (values (filter (lambda (g) (not (member (gap-key g) ak))) gaps)
          (filter (lambda (e) (not (member (entry-key e) gk))) allowlist)))

(module+ main
  (for ([g (find-init-gaps)]) (writeln g)))

(module+ test
  (define gaps (find-init-gaps))
  (define allow (load-allowlist))
  (define-values (new-gaps stale) (gate gaps allow))
  (test-case "keine neuen Init-Argument-Lücken ohne Allowlist-Eintrag"
    (check-equal? new-gaps '()))
  (test-case "kein veralteter Allowlist-Eintrag"
    (check-equal? (map (lambda (e) (take e 3)) stale) '()))
  (test-case "Recall: das Audit hätte das verworfene `font` gefunden (Stand vor §74.1, gui 1f3c18e0)"
    ;; 1f3c18e0 = Parent von c3242ae7 (font-Fix).  Braucht git.
    (define tmp (make-temporary-file "init-audit~a" 'directory))
    (for ([b (cons "qt" BACKENDS)])
      (copy-directory/files (build-path WX b) (build-path tmp b)))
    (define files '("message" "button" "check-box" "choice" "radio-box" "list-box"))
    (for ([f files])
      (define old-src
        (with-output-to-string
          (lambda ()
            (parameterize ([current-directory REPO-GUI])
              (system* (find-executable-path "git") "show"
                       (format "1f3c18e0:gui-lib/mred/private/wx/qt/~a.rkt" f))))))
      (check-true (> (string-length old-src) 100))
      (with-output-to-file (build-path tmp "qt" (string-append f ".rkt")) #:exists 'truncate
        (lambda () (write-string old-src))))
    (define old-gaps (find-init-gaps tmp))
    (delete-directory/files tmp)
    (for ([f files])
      (check-not-false
       (for/or ([g old-gaps])
         (and (equal? (car g) (string-append f ".rkt")) (eq? (caddr g) 'font)))
       (format "font in ~a.rkt nicht gefunden" f)))))

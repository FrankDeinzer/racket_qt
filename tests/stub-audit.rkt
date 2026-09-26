#lang racket/base
;; Findet Kandidaten für stille No-op-Stubs im Qt-Backend: Methoden, die in
;; wx/qt/*.rkt strukturell nichts tun (void / Literal-Rückgabe / (values
;; <Literale>) / when|unless|case-lambda-Hüllen darum), obwohl dieselbe
;; Methode in einem Referenz-Backend (gtk/cocoa/win32) eine substantielle
;; Implementierung hat.
;;
;; Hintergrund: docs/HACKING.md §60.7 fand zwei echte Bugs (§60.6 `get-column-size`,
;; und der ältere §30-Bug `is-shown? #t`) nur durch Zufall/manuelles Testen, nicht
;; durch die dort verwendete grobe Grep-Suche nach `(void)`-Rümpfen -- keiner der
;; beiden Rümpfe enthält den Text `(void)`. Dieses Modul ersetzt den Grep durch
;; einen strukturellen Vergleich gegen die drei anderen Backends.
;;
;; Kein reader-abhängiger Analyseschritt braucht einen gebauten Shim oder
;; PLT_QT -- das Modul liest nur `.rkt`-Quelltext. Kann daher auf jeder der
;; drei Entwicklungsmaschinen ohne weitere Vorbereitung laufen.
;;
;; Vergleichsregel (pro qt-Datei F, nicht pro Methodenname global -- siehe
;; docs/HACKING.md §60.9 für die Begründung, warum eine namensglobale Regel
;; hier zu grob ist und reale Bugs wie `set-focus` oder `set-label` verdeckt
;; hätte):
;;   1. Gleicher Dateiname: wenn eine Referenz-Backend-Datei mit demselben
;;      Basisnamen (z.B. gtk/button.rkt für qt/button.rkt) dieselbe Methode
;;      substantiell implementiert, ist F ein Kandidat.
;;   2. Basisklassen-Schatten: wenn F nicht window.rkt ist und qt/window.rkt
;;      (die gemeinsame Basisklasse) dieselbe Methode bereits substantiell
;;      implementiert, überschreibt F sie mit einem Platzhalter -- ebenfalls
;;      ein Kandidat (die Instanzen von F bekommen nie die echte Basis-Logik).
;;   3. Nur wenn F in KEINEM Referenz-Backend eine gleichnamige Datei hat
;;      (z.B. qt-spezifische Dateien wie platform.rkt), wird namensglobal über
;;      alle Referenz-Dateien gesucht -- das ist der einzige Fall, in dem
;;      Dateiname keine sinnvolle Vergleichsbasis ist.
;; Der umgekehrte Fall (window.rkt selbst ist der Platzhalter, eine speziellere
;; qt-Klasse wie frame.rkt überschreibt real) wird NICHT geflaggt: das ist die
;; erwartete Form einer Basisklassen-Vorgabe für Widget-Typen, für die die
;; Methode nicht gilt (z.B. `maximize` auf einem einfachen `window%`).

(require racket/file
         racket/list
         racket/path
         racket/port
         racket/runtime-path
         racket/set
         racket/string
         racket/system
         rackunit)

(provide find-stub-gaps
         entry-file entry-line
         gap-file-basenames
         load-allowlist gate
         (struct-out gap))

(define-runtime-path REPO-GUI   "../third_party/gui")
(define-runtime-path REPO-QT    "../third_party/gui/gui-lib/mred/private/wx/qt")
(define-runtime-path REPO-GTK   "../third_party/gui/gui-lib/mred/private/wx/gtk")
(define-runtime-path REPO-COCOA "../third_party/gui/gui-lib/mred/private/wx/cocoa")
(define-runtime-path REPO-WIN32 "../third_party/gui/gui-lib/mred/private/wx/win32")
(define-runtime-path ALLOWLIST-PATH "stub-audit-allowlist.rktd")

(define BACKENDS (list (cons 'gtk REPO-GTK) (cons 'cocoa REPO-COCOA) (cons 'win32 REPO-WIN32)))

(define DEFINE-KEYWORDS '(define/public define/public* define/override define/override*))

;; ---- Racket-Quelltext lesen (kein `#lang`-Expander, nur der Reader) ----
;; Lese-Fehler werden NICHT verschluckt: eine Datei, die der Reader nicht
;; versteht, soll den Test laut scheitern lassen statt still 0 Methoden zu
;; liefern (das wäre ein sehr leiser Weg, die ganze Analyse zu entwerten).

(define (read-forms path)
  (call-with-input-file path
    (lambda (in)
      (port-count-lines! in)
      (read-line in) ; "#lang racket/base" verwerfen
      (let loop ([acc '()])
        (define stx (read-syntax path in))
        (if (eof-object? stx)
            (reverse acc)
            (loop (cons stx acc)))))))

;; ---- define/public|override-Formen an beliebiger Verschachtelungstiefe finden ----

(struct def-form (name body-stxs line) #:transparent)

;; `e` kann eine unechte Liste sein (z.B. `(apply f a b)`-artige Reader-Formen),
;; daher car/cdr-Rekursion statt `in-list`.
(define (walk-pair-tail e acc)
  (cond
    [(pair? e)
     (walk-pair-tail (cdr e) (if (syntax? (car e)) (collect-defs (car e) acc) acc))]
    [(syntax? e) (collect-defs e acc)]
    [else acc]))

(define (collect-defs stx acc)
  (define e (syntax-e stx))
  (cond
    [(and (pair? e) (identifier? (car e))
          (memq (syntax-e (car e)) DEFINE-KEYWORDS))
     (define spec (syntax-e (cadr e)))
     (define name (if (pair? spec) (syntax-e (car spec)) spec))
     (cons (def-form name (cddr e) (syntax-line stx)) acc)]
    [(pair? e) (walk-pair-tail e acc)]
    [else acc]))

;; ---- Strukturelle "tut nichts"-Klassifikation ----

(define (self-evaluating? x)
  (or (boolean? x) (number? x) (string? x) (char? x) (keyword? x) (regexp? x)
      (and (pair? x) (eq? (car x) 'quote))))

(define (vacuous-expr? e)
  (cond
    [(self-evaluating? e) #t]
    [(and (pair? e) (eq? (car e) 'void) (null? (cdr e))) #t]
    [(and (pair? e) (memq (car e) '(when unless)))
     (andmap vacuous-expr? (cddr e))]
    [(and (pair? e) (eq? (car e) 'begin))
     (andmap vacuous-expr? (cdr e))]
    [(and (pair? e) (eq? (car e) 'values))
     (andmap self-evaluating? (cdr e))]
    [(and (pair? e) (eq? (car e) 'case-lambda))
     (andmap (lambda (clause) (andmap vacuous-expr? (cdr clause))) (cdr e))]
    [else #f]))

(define (vacuous-body? body-stxs)
  (andmap vacuous-expr? (map syntax->datum body-stxs)))

;; ---- Pro Verzeichnis: Dateiname -> Methodenname -> Liste (vacuous? Pfad Zeile) ----

(define (analyze-dir dir)
  (define result (make-hash)) ; basename-string -> hash(name -> entries)
  (when (directory-exists? dir)
    (for ([path (in-list (directory-list dir #:build? #t))]
          #:when (regexp-match? #rx"\\.rkt$" (path->string path)))
      (define base (path->string (file-name-from-path path)))
      (define forms (read-forms path))
      (define defs (for/fold ([acc '()]) ([f (in-list forms)]) (collect-defs f acc)))
      (define file-table (hash-ref! result base make-hash))
      (for ([d (in-list defs)])
        (hash-update! file-table (def-form-name d)
                      (lambda (l) (cons (list (vacuous-body? (def-form-body-stxs d))
                                               path (def-form-line d))
                                         l))
                      '()))))
  result)

(struct gap (name qt-entries real-refs) #:transparent)
(define (entry-file e) (cadr e))
(define (entry-line e) (caddr e))

;; Ein Fund wird durch (Methodenname . Menge betroffener qt-Dateien) identifiziert,
;; nicht durch den Namen allein -- sonst würde ein Allowlist-Eintrag für
;; `set-border` in `button.rkt` auch einen ganz neuen, unabhängigen
;; `set-border`-Stub in `check-box.rkt` stillschweigend mit abdecken, sobald die
;; Vergleichsregel künftig auch dort einen Treffer fände (dateibezogene Erkennung,
;; siehe Kopfkommentar). Ebenso macht ein sich änderndes Dateiset denselben Fund
;; zu einem "neuen" bzw. der alte Allowlist-Eintrag zu einem "stale" Eintrag.
(define (gap-file-basenames g)
  (sort (remove-duplicates
         (map (lambda (e) (path->string (file-name-from-path (entry-file e)))) (gap-qt-entries g)))
        string<?))

(define (substantive-entries name file-table)
  (filter (lambda (e) (not (car e))) (hash-ref file-table name '())))

;; ---- Hauptanalyse ----

(define (find-stub-gaps [qt-dir REPO-QT])
  (define qt-by-file (analyze-dir qt-dir))
  (define ref-by-backend
    (for/list ([b (in-list BACKENDS)]) (cons (car b) (analyze-dir (cdr b)))))
  (define qt-window-table (hash-ref qt-by-file "window.rkt" (make-hash)))
  (define ref-basenames
    (for*/set ([bt (in-list ref-by-backend)] [k (in-hash-keys (cdr bt))]) k))

  (for*/fold ([gaps '()]) ([(base file-table) (in-hash qt-by-file)]
                           [(name entries) (in-hash file-table)])
    ;; Wenn dieselbe Datei den Namen weiter UNTEN (größere Zeilennummer) bereits
    ;; substantiell definiert (typisches Muster: eine Basisklasse wie
    ;; `base-canvas%` mit einem Platzhalter, ein Mixin weiter unten in
    ;; derselben Datei wie `qt-canvas-scroll-mixin` mit der echten
    ;; Implementierung), ist DIESER Platzhalter kein vergessenes Feature --
    ;; dieselbe Begründung wie Regel 2, nur dateiintern. Die Reihenfolge zählt:
    ;; ein Platzhalter UNTER einer echten Definition wäre der dateiinterne
    ;; Zwilling von "is-shown? #t überschreibt window.rkts echtes shown?-Feld"
    ;; (§30) und muss weiter geflaggt werden, nicht stillschweigend verschluckt.
    (define real-lines (map entry-line (filter (lambda (e) (not (car e))) entries)))
    (define (shadowed-from-below? e) (ormap (lambda (l) (> l (entry-line e))) real-lines))
    (define qt-vacuous (filter (lambda (e) (and (car e) (not (shadowed-from-below? e)))) entries))
    (cond
      [(null? qt-vacuous) gaps]
      [else
       ;; Regel 1: gleicher Dateiname in einem Referenz-Backend, substantiell.
       (define same-file-refs
         (for*/list ([bt (in-list ref-by-backend)]
                     [e (in-list (substantive-entries name (hash-ref (cdr bt) base (make-hash))))])
           (list (car bt) (entry-file e) (entry-line e))))
       (cond
         [(pair? same-file-refs) (cons (gap name qt-vacuous same-file-refs) gaps)]
         ;; Regel 2: window.rkt (Basisklasse) hat die Methode bereits echt --
         ;; F überschreibt sie mit einem Platzhalter und verdeckt sie damit.
         [(and (not (string=? base "window.rkt"))
               (pair? (substantive-entries name qt-window-table)))
          (define shadow-refs
            (for/list ([e (in-list (substantive-entries name qt-window-table))])
              (list 'qt-window.rkt (entry-file e) (entry-line e))))
          (cons (gap name qt-vacuous shadow-refs) gaps)]
         ;; Regel 3: F hat in KEINEM Referenz-Backend eine gleichnamige Datei
         ;; -- dann ist dateibasierter Vergleich sinnlos, stattdessen global.
         [(not (set-member? ref-basenames base))
          (define global-refs
            (for*/list ([bt (in-list ref-by-backend)]
                        [(other-base other-table) (in-hash (cdr bt))]
                        [e (in-list (substantive-entries name other-table))])
              (list (car bt) (entry-file e) (entry-line e))))
          (if (null? global-refs) gaps (cons (gap name qt-vacuous global-refs) gaps))]
         [else gaps])])))

;; ---- Allowlist: bereits triagierte Funde (harmlos oder bekannter Backlog) ----

(define (load-allowlist)
  (if (file-exists? ALLOWLIST-PATH)
      (with-input-from-file ALLOWLIST-PATH read)
      '()))

;; Ein Fund gilt nur dann als bereits triagiert, wenn Name UND die exakte Menge
;; betroffener qt-Dateien mit einem Allowlist-Eintrag übereinstimmen (siehe
;; `gap-file-basenames` oben und docs/HACKING.md §60.9 für die Begründung).
;; Als eigene Funktion exportiert, damit ein Test sie gegen einen synthetischen
;; Baum aufrufen kann, ohne die echte Allowlist-Datei anzufassen.
(define (allowlist-entry-for g allowlist)
  (findf (lambda (e) (and (eq? (car e) (gap-name g))
                          (equal? (sort (cadr e) string<?) (gap-file-basenames g))))
         allowlist))

(define (gate gaps allowlist)
  (define new-gaps (filter (lambda (g) (not (allowlist-entry-for g allowlist))) gaps))
  ;; Jeder Allowlist-Eintrag wird auf Staleness geprüft, unabhängig vom Status:
  ;; diese Datei enthält per Konvention NUR Namen, die der Lauf aktuell auch
  ;; findet (s. Kopfkommentar der Allowlist-Datei) -- ein Eintrag, der plötzlich
  ;; nicht mehr (in denselben Dateien) auftaucht, ist so oder so ein Signal:
  ;; entweder wurde der Stub gefixt (Eintrag entfernen) oder die Vergleichsregel
  ;; hat einen Regressionsschaden. Würde man z.B. 'needs-triage davon ausnehmen,
  ;; könnte ein später implementiertes `enforce-size` den Eintrag stumm veralten
  ;; lassen, und eine anschließende Regression zurück auf (void) würde vom immer
  ;; noch (Name+Datei-)passenden Allowlist-Eintrag stillschweigend wieder
  ;; verschluckt.
  (define (entry-matches-some-gap? e)
    (ormap (lambda (g) (and (eq? (gap-name g) (car e))
                            (equal? (sort (cadr e) string<?) (gap-file-basenames g))))
           gaps))
  (define stale-entries (filter (lambda (e) (not (entry-matches-some-gap? e))) allowlist))
  (values new-gaps stale-entries))

;; ---- Historische Bäume für Recall-Regressionstests ----
;; Kopiert den aktuellen qt-Baum in ein Temp-Verzeichnis und ersetzt darin EINE
;; Datei durch ihren Inhalt bei einem älteren gui-Submodul-Commit -- simuliert
;; "wäre dieser inzwischen gefixte Bug heute noch da, würde find-stub-gaps ihn
;; finden?". Braucht `git` auf PATH und die Commit-History des gui-Submoduls
;; (lokal bereits vorhanden, kein Netzwerkzugriff nötig).

(define (git-show->string sha repo-relative-path)
  (define out (open-output-string))
  (define err (open-output-string))
  (define ok?
    (parameterize ([current-output-port out]
                   [current-error-port err])
      (system* (or (find-executable-path "git") (error 'git-show "git nicht gefunden"))
               "-C" (path->string REPO-GUI)
               "show" (format "~a:~a" sha repo-relative-path))))
  (unless ok?
    (error 'git-show "git show ~a:~a fehlgeschlagen: ~a"
           sha repo-relative-path (get-output-string err)))
  (get-output-string out))

(define (make-historical-qt-tree overrides)
  ;; overrides: Liste von (dateiname . (sha . repo-relative-path))
  (define tmp (make-temporary-file "stub-audit-hist-~a" 'directory))
  (for ([path (in-list (directory-list REPO-QT #:build? #t))]
        #:when (regexp-match? #rx"\\.rkt$" (path->string path)))
    (copy-file path (build-path tmp (file-name-from-path path))))
  (for ([o (in-list overrides)])
    (define name (car o))
    (define sha (cadr o))
    (define rel-path (caddr o))
    (define content (git-show->string sha rel-path))
    (call-with-output-file (build-path tmp name) #:exists 'truncate/replace
      (lambda (out) (display content out))))
  tmp)

(module+ test

  ;; ---- Recall-Regressionstests: die fünf Fälle aus der Design-Diskussion
  ;; dieser Session (docs/HACKING.md §60.9). Diese müssen bei JEDER künftigen
  ;; Änderung an der Vergleichsregel weiter bestehen, sonst kann eine
  ;; "Verbesserung" der Regel wieder Recall verlieren, ohne dass es auffällt. ----

  (test-case "get-column-size (§60.6, aktuell unbehobener Bug): wird gefunden"
    (check-true (and (memq 'get-column-size (map gap-name (find-stub-gaps))) #t)))

  (test-case "set-focus (§60.7, aktuell unbehobener Bug): wird trotz canvas%'s echter Implementierung gefunden"
    (check-true (and (memq 'set-focus (map gap-name (find-stub-gaps))) #t)))

  (test-case "maximize/iconize/fullscreen: KEIN Fehlalarm (frame.rkt überschreibt window.rkts Platzhalter real)"
    (define names (map gap-name (find-stub-gaps)))
    (check-false (ormap (lambda (n) (memq n names)) '(maximize iconized? is-maximized? fullscreen fullscreened?))))

  (test-case "is-shown? #t (historischer §30-Bug, 2f0755bd~1): wäre gefunden worden"
    (define tmp (make-historical-qt-tree
                 (list (list "button.rkt" "2f0755bd~1" "gui-lib/mred/private/wx/qt/button.rkt"))))
    (check-true (and (memq 'is-shown? (map gap-name (find-stub-gaps tmp))) #t))
    (delete-directory/files tmp))

  (test-case "set-label No-op (historischer §60.3-Bug, 1430d19a~1): wäre gefunden worden"
    (define tmp (make-historical-qt-tree
                 (list (list "button.rkt" "1430d19a~1" "gui-lib/mred/private/wx/qt/button.rkt"))))
    (check-true (and (memq 'set-label (map gap-name (find-stub-gaps tmp))) #t))
    (delete-directory/files tmp))

  (test-case "neuer Stub in einer bestehenden Widget-Klasse wird erkannt (nicht nur bei neuen Klassen)"
    ;; §5-Checkliste löst den Audit nur "bei neuer Widget-Klasse" aus -- das hätte
    ;; §60.3 (eine ÄNDERUNG an button.rkt, keine neue Klasse) verfehlt. Dieser Test
    ;; simuliert genau das: `button.rkt` bekommt zusätzlich einen frischen No-op
    ;; `clicked` (den es dort vorher nicht gab -- `gtk/button.rkt` implementiert
    ;; `clicked` substantiell, `qt/button.rkt` kennt die Methode aktuell gar
    ;; nicht), was Regel 1 (gleicher Dateiname, Referenz-Backend substantiell)
    ;; treffen muss.
    (define tmp (make-temporary-file "stub-audit-inject-~a" 'directory))
    (for ([path (in-list (directory-list REPO-QT #:build? #t))]
          #:when (regexp-match? #rx"\\.rkt$" (path->string path)))
      (copy-file path (build-path tmp (file-name-from-path path))))
    (define target (build-path tmp "button.rkt"))
    (define original (call-with-input-file target port->string))
    (call-with-output-file target #:exists 'truncate/replace
      (lambda (out)
        (display original out)
        (display "\n    (define/public (clicked) (void))\n" out)))
    (define names-with-injection (map gap-name (find-stub-gaps tmp)))
    (check-true (and (memq 'clicked names-with-injection) #t))
    (delete-directory/files tmp))

  (test-case "Allowlist-Treffer sind dateibezogen, nicht nur namensbezogen"
    ;; Regressionstest für einen advisor-Fund: eine frühere Fassung glich
    ;; Allowlist-Einträge nur über den Methodennamen ab. Ein Eintrag für
    ;; `set-border` in `button.rkt` hätte damit einen UNABHÄNGIGEN neuen
    ;; `set-border`-Stub in einer ganz anderen Datei stillschweigend mit
    ;; abgedeckt. Hier: eine Datei, die in KEINEM Referenz-Backend existiert
    ;; (triggert Regel 3, den namensglobalen Fallback) bekommt ein frisches
    ;; `set-border` -- das muss trotz der bestehenden `set-border`/`button.rkt`-
    ;; Allowlist-Eintrag als NEUER Fund erscheinen.
    (define tmp (make-temporary-file "stub-audit-filekey-~a" 'directory))
    (for ([path (in-list (directory-list REPO-QT #:build? #t))]
          #:when (regexp-match? #rx"\\.rkt$" (path->string path)))
      (copy-file path (build-path tmp (file-name-from-path path))))
    (call-with-output-file (build-path tmp "zz-injected.rkt")
      (lambda (out)
        (display "#lang racket/base\n" out)
        (display "(define/public (set-border b) (void))\n" out)))
    (define real-allowlist (load-allowlist))
    ;; Sicherstellen, dass die reale Allowlist überhaupt so einen Eintrag hat --
    ;; sonst würde dieser Test aus dem falschen Grund grün sein.
    (check-not-false (findf (lambda (e) (and (eq? (car e) 'set-border) (member "button.rkt" (cadr e))))
                            real-allowlist))
    (define-values (new-gaps _stale) (gate (find-stub-gaps tmp) real-allowlist))
    (check-true (and (memq 'set-border (map gap-name new-gaps)) #t))
    (delete-directory/files tmp))

  ;; ---- Der eigentliche Gate: neue, nicht triagierte Funde im aktuellen Baum ----
  ;; Ein Fund gilt nur dann als "schon triagiert", wenn Name UND die genaue Menge
  ;; betroffener qt-Dateien mit einem Allowlist-Eintrag übereinstimmen -- siehe
  ;; Kommentar bei `gap-file-basenames` oben für die Begründung.

  (define gaps (find-stub-gaps))
  (define allowlist (load-allowlist)) ; Liste von (name (datei ...) status "begründung")
  (define-values (new-gaps stale-entries) (gate gaps allowlist))

  (unless (null? new-gaps)
    (eprintf "\n~a bisher NICHT triagierte Stub-Kandidat(en) gefunden:\n\n" (length new-gaps))
    (for ([g (in-list new-gaps)])
      (eprintf "  ~a (Dateien: ~a)\n    qt (trivial): ~a\n    Referenz (echt): ~a\n"
               (gap-name g)
               (string-join (gap-file-basenames g) ", ")
               (string-join (for/list ([e (in-list (gap-qt-entries g))])
                              (format "~a:~a" (file-name-from-path (entry-file e)) (entry-line e)))
                            ", ")
               (string-join (for/list ([r (in-list (gap-real-refs g))])
                              (format "~a:~a:~a" (car r) (file-name-from-path (cadr r)) (caddr r)))
                            ", "))
      (eprintf "    zum Eintragen in ~a:\n    (~a (~a) needs-triage \"...\")\n\n"
               ALLOWLIST-PATH
               (gap-name g)
               (string-join (map (lambda (f) (format "~s" f)) (gap-file-basenames g)) " ")))
    (eprintf "Status beim Eintragen ggf. auf 'harmless oder 'backlog anpassen (mit Begründung/§-Verweis)\n")
    (eprintf "und in docs/HACKING.md dokumentieren.\n\n"))

  (unless (null? stale-entries)
    (eprintf "\n~a Allowlist-Eintrag/Einträge werden vom aktuellen Lauf nicht mehr (in denselben Dateien) gefunden: ~a\n"
             (length stale-entries) (map car stale-entries))
    (eprintf "Entweder wurde der Stub inzwischen gefixt (Eintrag entfernen) oder die Vergleichsregel\n")
    (eprintf "hat ihn aus anderem Grund verloren (prüfen, bevor der Eintrag gelöscht wird).\n\n"))

  (check-equal? new-gaps '()
                "Neue, nicht triagierte Stub-Kandidaten gefunden -- siehe stderr-Ausgabe oben")
  (check-equal? stale-entries '()
                "Allowlist-Einträge, die der aktuelle Lauf nicht mehr findet -- siehe stderr-Ausgabe oben"))

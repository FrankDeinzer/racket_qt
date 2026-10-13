#lang racket/gui
;; Dialoge zur Laufzeit (docs/COVERAGE.md, HACKING §83.1): message-box, message-box/custom, get-text-from-user,
;; get-choices-from-user, get-color-from-user, get-font-from-user, get-file, put-file, get-directory, get-file-list.
;; Die Eingabe kommt von aussen (tests/sweep/dialog-runtime.sh, xdotool); die Probe protokolliert nur, was Racket sieht.
;;
;; Aufruf:  racket examples/dialog-runtime-probe.rkt <fixture-dir>   (Befehle auf stdin, Protokoll auf stderr)
;; Befehle (je eine Zeile):
;;   P                  "POS pre x y w h" des Hauptfensters (Modalitaetstest) + "POS frame-ready"
;;   R <szenario> <tag> Szenario in einem Callback starten.  Protokoll (stderr), je Zeile "<szenario>/<tag> <schluessel> => <wert>":
;;                        focus-before   fokussiertes Element des Hauptfensters vor dem Dialog
;;                        info           (nach 1.3 s, Dialog offen) Buttons des Dialogs links->rechts, Titel, Icon-Groesse
;;                        result         Rueckgabewert (Pfade relativ zur Fixture)
;;                        after          (0.7 s nach Rueckkehr) Fokus, enabled?, Klicks auf "pre" (Modalitaet)
;;                      stdout:  "INFO <szenario>/<tag>" und "BTN <label> x y w h" (Screen-Koordinaten der Dialog-Buttons),
;;                               "DONE <szenario>/<tag>" nach "after"
;;   K                  stdout "CLICKS n" (Klicks auf "pre" insgesamt; Treiber-Sanity: der Knopf ist ohne Dialog klickbar)
;;   X                  beenden
(define fixture (path->string (path->complete-path (vector-ref (current-command-line-arguments) 0))))
(define (rel v)
  (cond [(path? v) (rel (path->string v))]
        [(string? v) (if (and (>= (string-length v) (string-length fixture)) (string=? (substring v 0 (string-length fixture)) fixture))
                         (string-append "FIX" (substring v (string-length fixture)))
                         v)]
        [(pair? v) (map rel v)]
        [else v]))
(define (show-color c) (and c (list (send c red) (send c green) (send c blue) (send c alpha))))
(define (show-font f) (and f (list (send f get-point-size) (send f get-style) (send f get-weight) (send f get-underlined) (send f get-face))))
(define (out key v) (eprintf "~a ~a => ~s\n" current key v) (flush-output (current-error-port)))
(define current "?")

(define F (new frame% [label "drt-main"] [x 100] [y 80] [min-width 900] [min-height 400] [alignment '(left top)]))
(define clicks 0)
(define total-clicks 0)
(define pre (new button% [parent F] [label "pre"] [stretchable-width #f] [callback (λ (b e) (set! clicks (add1 clicks)) (set! total-clicks (add1 total-clicks)))]))
(define cv (new canvas% [parent F] [min-width 300] [min-height 100]))
(define (focused) (cond [(send pre has-focus?) 'pre] [(send cv has-focus?) 'canvas] [else 'none]))

(define (find-dialog)
  (for/first ([w (get-top-level-windows)] #:when (and (not (eq? w F)) (send w is-shown?))) w))
(define (walk w proc)
  (proc w)
  (when (is-a? w area-container<%>) (for ([c (send w get-children)]) (walk c proc))))
(define (report-info)
  (define d (find-dialog))
  (cond
    [d
     (define btns '()) (define msgs '())
     (walk d (λ (c) (cond [(is-a? c button%)
                           (define-values (sx sy) (send c client->screen 0 0))
                           (set! btns (cons (list (send c get-label) sx sy (send c get-width) (send c get-height)) btns))]
                          [(is-a? c message%)
                           (define l (send c get-label))
                           (set! msgs (cons (cond [(string? l) l] [(symbol? l) (list 'icon l)] [else (list 'bitmap (send l get-width) (send l get-height))]) msgs))])))
     (define sorted (sort btns < #:key (λ (b) (+ (cadr b) (* 100000 0)))))
     (out "info" (list 'title (send d get-label) 'buttons (map car sorted) 'messages (reverse msgs)
                       'focus-in-dialog (let ([f (send d get-focus-window)]) (and f (is-a? f button%) (send f get-label)))))
     (for ([b sorted]) (printf "BTN ~a ~a ~a ~a ~a\n" (car b) (cadr b) (caddr b) (cadddr b) (list-ref b 4)))]
    [else (out "info" 'native-or-no-dialog-window)])
  (printf "INFO ~a\n" current) (flush-output))

(define (scenario name)
  (case name
    [("mb-ok") (λ () (message-box "mb-ok" "Message line" F '(ok)))]
    [("mb-ok-noparent") (λ () (message-box "mb-ok-np" "Message line" #f '(ok)))]
    [("mb-ok-cancel") (λ () (message-box "mb-ok-cancel" "Message line" F '(ok-cancel)))]
    [("mb-yes-no") (λ () (message-box "mb-yes-no" "Message line" F '(yes-no)))]
    [("mb-yes-no-cancel") (λ () (message-box "mb-yes-no-cancel" "Message line" F '(yes-no-cancel)))]
    [("mb-caution") (λ () (message-box "mb-caution" "Message line" F '(ok caution)))]
    [("mb-stop") (λ () (message-box "mb-stop" "Message line" F '(ok-cancel stop)))]
    [("mb-custom") (λ () (message-box/custom "mb-custom" "Message line" "Alpha" "Beta" "Gamma" F '(default=2 caution) 3))]
    [("mb-custom-noclose") (λ () (message-box/custom "mb-custom-nc" "Message line" "Alpha" "Beta" #f F '(default=1)))]
    [("tf") (λ () (get-text-from-user "tf" "Enter text:" F "init"))]
    [("tf-empty") (λ () (get-text-from-user "tf-empty" "Enter text:" F ""))]
    [("ch") (λ () (get-choices-from-user "ch" "Pick:" '("one" "two" "three") F '(1)))]
    [("color") (λ () (show-color (get-color-from-user "color" F (make-object color% 10 120 200))))]
    [("font") (λ () (show-font (get-font-from-user "font" F (make-object font% 14 'default 'italic 'bold))))]
    [("gf") (λ () (rel (get-file "gf" F fixture)))]
    [("gf-name") (λ () (rel (get-file "gf-name" F fixture "b.rkt")))]
    [("gf-filter") (λ () (rel (get-file "gf-filter" F fixture #f #f '() '(("Racket" "*.rkt") ("Any" "*.*")))))]
    [("pf") (λ () (rel (put-file "pf" F fixture "new.txt")))]
    [("pf-ext") (λ () (rel (put-file "pf-ext" F fixture "noext" "txt")))]
    [("pf-existing") (λ () (rel (put-file "pf-existing" F fixture "a.txt")))]
    [("gd") (λ () (rel (get-directory "gd" F fixture)))]
    [("gfl") (λ () (rel (get-file-list "gfl" F fixture)))]
    [else (λ () 'unknown-scenario)]))

(define (run name tag)
  (set! current (format "~a/~a" name tag))
  (set! clicks 0)
  (send cv focus) (sleep/yield 0.4)
  (define name* current)
  (out "focus-before" (focused))
  (define t (new timer% [notify-callback (λ () (set! current name*) (report-info))]))
  (send t start 1300 #t)
  (define r (with-handlers ([void (λ (e) (list 'EXN (if (exn? e) (car (regexp-split #rx"\n" (exn-message e))) e)))])
              ((scenario name))))
  (set! current name*)
  (out "result" (if (or (string? r) (pair? r) (not r) (symbol? r) (number? r)) r r))
  (define t2 (new timer% [notify-callback (λ () (set! current name*)
                                             (out "after" (list 'focus (focused) 'enabled (send F is-enabled?) 'parent-clicks clicks 'dialog-gone (not (find-dialog))))
                                             (printf "DONE ~a\n" name*) (flush-output))]))
  (send t2 start 700 #t))

(define (handle line)
  (define m (regexp-match #rx"^([A-Z]) ?(.*)$" line))
  (when m
    (case (cadr m)
      [("P") (define-values (sx sy) (send pre client->screen 0 0))
             (printf "POS pre ~a ~a ~a ~a\n" sx sy (send pre get-width) (send pre get-height))
             (printf "POS frame-ready\n") (flush-output)]
      [("K") (printf "CLICKS ~a\n" total-clicks) (flush-output)]
      [("R") (define a (regexp-split #rx" " (caddr m))) (run (car a) (if (pair? (cdr a)) (cadr a) "x"))]
      [("X") (exit 0)])))
(send F show #t)
(void (thread (λ () (let loop ()
                (define l (read-line))
                (cond [(eof-object? l) (queue-callback (λ () (exit 0)))]
                      [else (queue-callback (λ () (with-handlers ([void (λ (e) (eprintf "CMD-EXN ~a\n" (if (exn? e) (exn-message e) e)))]) (handle l)))) (loop)])))))
(yield 'wait)

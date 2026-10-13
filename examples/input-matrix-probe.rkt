#lang racket/gui
;; Echte-Eingabe-Probe (docs/COVERAGE.md, HACKING §82): ein Fenster pro Sektion mit den Steuerelementen
;; einer Klasse.  Die Eingabe kommt NICHT aus diesem Programm, sondern von aussen (xdotool, Treiber
;; tests/sweep/input-controls.sh) -- die Probe protokolliert nur, was Racket davon sieht.
;;
;; Aufruf:  racket examples/input-matrix-probe.rkt <sektion>   (Befehle auf stdin, Protokoll auf stderr)
;; Befehle (je eine Zeile auf stdin):
;;   P            Positionen der Steuerelemente auf stdout:  "POS <name> <screen-x> <screen-y> <w> <h>"
;;   S <label>    Schritt abschliessen: die seit dem letzten S gesammelten Ereignisse und der Zustand
;;                werden auf stderr geschrieben:  "<sektion> <ereignis> => <wert>"  /  "<sektion> state:<label> => <zustand>"
;;                (Ereignisse mit gleichem Schluessel, die als "collapse" markiert sind, werden zur letzten
;;                Meldung verdichtet -- Zaehler sind toolkit-abhaengig, Endwerte nicht)
;;   Q <n>        Zustand auf stdout:  "Q <n> <zustand>"  (Kalibrierung der Treiber, kein Protokoll)
;;   Z            gesammelte Ereignisse verwerfen und Auswahl zuruecksetzen (nach Kalibrierung)
;;   X            beenden
;; Die Ausgabe nativ (gtk) und mit PLT_QT=1 wird vom Treiber gediffed.
(define section (vector-ref (current-command-line-arguments) 0))
(define pending '())
(define (ev! key val #:collapse [c #f])
  (define v (with-handlers ([(λ (x) #t) (λ (x) (format "EXN ~a" (if (exn? x) (car (regexp-split #rx"\n" (exn-message x))) x)))]) (if (procedure? val) (val) val)))
  (cond [(and c (assoc key pending)) (set! pending (map (λ (p) (if (equal? (car p) key) (cons key v) p)) pending))]
        [else (set! pending (cons (cons key v) pending))]))
(define (out key v) (eprintf "~a ~a => ~s\n" section key v))

(define F #f) (define CTRLS '()) (define STATE (λ () '())) (define RESET void)
(define (focused) (for/first ([p CTRLS] #:when (with-handlers ([void (λ (e) #f)]) (send (cdr p) has-focus?))) (car p)))
(define (mkframe) (new frame% [label (format "imx-~a" section)] [x 120] [y 90]))
(define (mods e) (list (and (send e get-shift-down) 'shift) (and (send e get-control-down) 'ctrl)
                       (and (send e get-alt-down) 'alt) (and (send e get-meta-down) 'meta)))

;; ---------------- Sektionen ----------------
(define (sec-button)
  (set! F (mkframe))
  (define p (new vertical-panel% [parent F] [alignment '(left top)] [min-width 260]))
  (define (b name [en #t]) (new button% [parent p] [label name] [enabled en]
                                [callback (λ (b e) (ev! (format "~a command" name) (send e get-event-type)))]))
  (define b1 (b "b1")) (define b2 (b "b2" #f)) (define b3 (b "b3"))
  (set! CTRLS (list (cons 'b1 b1) (cons 'b2 b2) (cons 'b3 b3)))
  (set! STATE (λ () (list 'focus (focused)))))

(define (sec-check-box)
  (set! F (mkframe))
  (define p (new vertical-panel% [parent F] [alignment '(left top)] [min-width 260]))
  (define (c name val [en #t]) (new check-box% [parent p] [label name] [value val] [enabled en]
                                    [callback (λ (c e) (ev! (format "~a command" name) (list (send e get-event-type) (send c get-value))))]))
  (define c1 (c "c1" #f)) (define c2 (c "c2" #f #f)) (define c3 (c "c3" #t))
  (set! CTRLS (list (cons 'c1 c1) (cons 'c2 c2) (cons 'c3 c3)))
  (set! STATE (λ () (list 'focus (focused) 'values (map (λ (c) (send c get-value)) (list c1 c2 c3))))))

(define (sec-radio-box)
  (set! F (mkframe))
  (define p (new vertical-panel% [parent F] [alignment '(left top)] [min-width 260]))
  (define pre (new button% [parent p] [label "pre"]))
  (define r (new radio-box% [parent p] [label #f] [choices '("r0" "r1" "r2")]
                 [callback (λ (r e) (ev! "radio command" (list (send e get-event-type) (send r get-selection))))]))
  (define post (new button% [parent p] [label "post"]))
  (set! CTRLS (list (cons 'pre pre) (cons 'radio r) (cons 'post post)))
  (set! STATE (λ () (list 'focus (focused) 'selection (send r get-selection)))))

(define (sec-choice)
  (set! F (mkframe))
  (define p (new vertical-panel% [parent F] [alignment '(left top)] [min-width 260]))
  (define pre (new button% [parent p] [label "pre"]))
  (define c (new choice% [parent p] [label #f] [choices '("c0" "c1" "c2" "c3")]
                 [callback (λ (c e) (ev! "choice command" (list (send e get-event-type) (send c get-selection))))]))
  (define post (new button% [parent p] [label "post"]))
  (set! CTRLS (list (cons 'pre pre) (cons 'choice c) (cons 'post post)))
  (set! RESET (λ () (send c set-selection 0)))
  (set! STATE (λ () (list 'focus (focused) 'selection (send c get-selection)))))

(define (sec-slider)
  (set! F (mkframe))
  (define p (new vertical-panel% [parent F] [alignment '(left top)] [min-width 340]))
  (define pre (new button% [parent p] [label "pre"]))
  (define s (new slider% [parent p] [label #f] [min-value 0] [max-value 100] [init-value 50] [style '(horizontal plain)] [min-width 320]
                 [callback (λ (s e) (ev! "slider command" (λ () (list (send e get-event-type) (send s get-value))) #:collapse #t))]))
  (set! CTRLS (list (cons 'pre pre) (cons 'slider s)))
  (set! RESET (λ () (send s set-value 50)))
  (set! STATE (λ () (list 'focus (focused) 'value (send s get-value)))))

(define (sec-list style [columns #f])
  (set! F (mkframe))
  (define p (new vertical-panel% [parent F] [alignment '(left top)] [min-width 300]))
  (define pre (new button% [parent p] [label "pre"]))
  (define lb
    (if columns
        (new list-box% [parent p] [label #f] [choices '()] [columns '("colA" "colB")] [style (cons style '(clickable-headers))]
             [min-width 280] [min-height 150] [stretchable-height #f]
             [callback (λ (lb e) (ev! (format "lb ~a" (send e get-event-type))
                                      (λ () (list (send lb get-selections)
                                                  (and (is-a? e column-control-event%) (send e get-column))))))])
        (new list-box% [parent p] [label #f] [choices (for/list ([i 8]) (format "i~a" i))] [style (list style)]
             [min-width 280] [min-height 150] [stretchable-height #f]
             [callback (λ (lb e) (ev! (format "lb ~a" (send e get-event-type)) (λ () (send lb get-selections))))])))
  (when columns (send lb set (for/list ([i 8]) (format "r~a" i)) (for/list ([i 8]) (format "x~a" i))))
  (set! CTRLS (list (cons 'pre pre) (cons 'lb lb)))
  (set! RESET (λ () (for ([i (send lb get-number)]) (send lb select i #f))))
  (set! STATE (λ () (list 'focus (focused) 'selections (send lb get-selections)))))

(define (sec-text-field)
  (set! F (mkframe))
  (define p (new vertical-panel% [parent F] [alignment '(left top)] [min-width 300]))
  (define pre (new button% [parent p] [label "pre"]))
  (define (cb name) (λ (t e) (ev! (format "~a ~a" name (send e get-event-type)) (λ () (send t get-value)) #:collapse #t)))
  (define t1 (new text-field% [parent p] [label #f] [callback (cb "tf1")] [min-width 250]))
  (define t2 (new text-field% [parent p] [label #f] [style '(multiple)] [callback (cb "tf2")] [min-width 250] [min-height 70]))
  (define post (new button% [parent p] [label "post"]))
  (set! CTRLS (list (cons 'pre pre) (cons 'tf1 t1) (cons 'tf2 t2) (cons 'post post)))
  (set! STATE (λ () (list 'focus (focused) 'values (list (send t1 get-value) (send t2 get-value))))))

(define (sec-combo-field)
  (set! F (mkframe))
  (define p (new vertical-panel% [parent F] [alignment '(left top)] [min-width 300]))
  (define pre (new button% [parent p] [label "pre"]))
  (define c (new combo-field% [parent p] [label #f] [choices '("alpha" "beta" "gamma")] [min-width 250]
                 [callback (λ (c e) (ev! (format "combo ~a" (send e get-event-type)) (λ () (send c get-value)) #:collapse #t))]))
  (define post (new button% [parent p] [label "post"]))
  (set! CTRLS (list (cons 'pre pre) (cons 'combo c) (cons 'post post)))
  (set! RESET (λ () (send c set-value "")))
  (set! STATE (λ () (list 'focus (focused) 'value (send c get-value)))))

(define (sec-tab-panel)
  (set! F (mkframe))
  (define tp (new tab-panel% [parent F] [choices '("tab0" "tab1" "tab2")] [min-width 360] [min-height 140]
                  [callback (λ (tp e) (ev! "tab command" (λ () (list (send e get-event-type) (send tp get-selection))))
                              (send tp change-children (λ (_) (list (list-ref panels (send tp get-selection))))))]))
  (define panels (for/list ([i 3]) (new vertical-panel% [parent tp] [style '(deleted)] [alignment '(left top)])))
  (define ctrls
    (for/list ([pn panels] [i 3])
      (list (cons (string->symbol (format "p~ab" i)) (new button% [parent pn] [label (format "btn~a" i)]))
            (cons (string->symbol (format "p~at" i)) (new text-field% [parent pn] [label #f])))))
  (send tp change-children (λ (_) (list (car panels))))
  (set! CTRLS (cons (cons 'tabs tp) (apply append ctrls)))
  (set! RESET (λ () (send tp set-selection 0) (send tp change-children (λ (_) (list (car panels))))))
  (set! STATE (λ () (list 'selection (send tp get-selection) 'focus (focused)))))

(define (sec-tab-order)
  (set! F (mkframe))
  (define p (new vertical-panel% [parent F] [alignment '(left top)] [min-width 360]))
  (define b0 (new button% [parent p] [label "b0"]))
  (define tf (new text-field% [parent p] [label #f]))
  (define cb (new check-box% [parent p] [label "cb"]))
  (define ch (new choice% [parent p] [label #f] [choices '("x" "y")]))
  (define rb (new radio-box% [parent p] [label #f] [choices '("ra" "rb")]))
  (define sl (new slider% [parent p] [label #f] [min-value 0] [max-value 10] [init-value 5] [style '(horizontal plain)]))
  (define lb (new list-box% [parent p] [label #f] [choices '("l0" "l1" "l2")] [min-height 60] [stretchable-height #f]))
  (define hp (new horizontal-panel% [parent p] [alignment '(left top)]))
  (define bh1 (new button% [parent hp] [label "h1"])) (define bh2 (new button% [parent hp] [label "h2"]))
  (define tp (new tab-panel% [parent p] [choices '("T0" "T1")] [min-height 60]))
  (define bt (new button% [parent tp] [label "inTab"]))
  (define bl (new button% [parent p] [label "last"]))
  (set! CTRLS (list (cons 'b0 b0) (cons 'tf tf) (cons 'cb cb) (cons 'ch ch) (cons 'rb rb) (cons 'sl sl) (cons 'lb lb)
                    (cons 'h1 bh1) (cons 'h2 bh2) (cons 'tabs tp) (cons 'inTab bt) (cons 'last bl)))
  (set! STATE (λ () (list 'focus (focused)))))

(define (sec-menu)
  (set! F (mkframe))
  (define mb (new menu-bar% [parent F]))
  (define (cmd name) (λ (i e) (ev! (format "menu ~a" name) (λ () (list (send e get-event-type) (and (is-a? i checkable-menu-item%) (send i is-checked?)))))))
  (define m-file (new menu% [parent mb] [label "&File"]))
  (define alpha (new menu-item% [parent m-file] [label "Alpha"] [shortcut #\a] [callback (cmd "alpha")]))
  (define beta (new checkable-menu-item% [parent m-file] [label "Beta"] [callback (cmd "beta")]))
  (define eps (new menu-item% [parent m-file] [label "Eps"] [callback (cmd "eps")]))
  (send eps enable #f)
  (define sub (new menu% [parent m-file] [label "Sub"]))
  (define gamma (new menu-item% [parent sub] [label "Gamma"] [callback (cmd "gamma")]))
  (define m-edit (new menu% [parent mb] [label "&Edit"]))
  (define delta (new menu-item% [parent m-edit] [label "Delta"] [shortcut #\d] [shortcut-prefix '(ctl shift)] [callback (cmd "delta")]))
  (define p (new vertical-panel% [parent F] [alignment '(left top)] [min-width 300] [min-height 120]))
  (define b (new button% [parent p] [label "btn"]))
  (set! CTRLS (list (cons 'btn b)))
  (set! STATE (λ () (list 'beta-checked (send beta is-checked?)))))

(define (sec-popup)
  (set! F (mkframe))
  (define pm (new popup-menu% [popdown-callback (λ (m e) (ev! "popdown" (send e get-event-type)))]))
  (define (cmd name) (λ (i e) (ev! (format "popup ~a" name) (λ () (list (send e get-event-type) (and (is-a? i checkable-menu-item%) (send i is-checked?)))))))
  (new menu-item% [parent pm] [label "PA"] [callback (cmd "pa")])
  (new checkable-menu-item% [parent pm] [label "PB"] [callback (cmd "pb")])
  (new menu-item% [parent pm] [label "PC"] [callback (cmd "pc")])
  (define cv (new (class canvas%
                    (define/override (on-event e)
                      (when (eq? (send e get-event-type) 'right-down)
                        (send this popup-menu pm (send e get-x) (send e get-y))))
                    (super-new))
                  [parent F] [min-width 300] [min-height 160]))
  (set! CTRLS (list (cons 'canvas cv)))
  (set! STATE (λ () (list 'focus (focused)))))

(define (sec-canvas)
  (set! F (mkframe))
  (define p (new vertical-panel% [parent F] [alignment '(left top)] [min-width 320]))
  (define pre (new button% [parent p] [label "pre"]))
  (define cv
    (new (class canvas%
           (define/override (on-event e)
             (define-values (w h) (send this get-client-size))
             (define t (send e get-event-type))
             (define rel (list (- (send e get-x) (quotient w 2)) (- (send e get-y) (quotient h 2))))
             (case t
               ;; reine Hover-Bewegung wird nicht protokolliert (gtk meldet vor einem Klick eine synthetische
               ;; Bewegung, Qt nicht -- ohne Bedeutung); Ziehen (dragging?) schon
               [(motion) (when (send e dragging?) (ev! "mouse motion drag=#t" rel #:collapse #t))]
               [(enter leave) (ev! (format "mouse ~a" t) #t)]
               [else (ev! (format "mouse ~a" t) (list rel (mods e)))]))
           (define/override (on-char e)
             ;; Modifier-Tasten selbst und Release-Ereignisse: gtk meldet den Zustand VOR dem Ereignis, Qt danach
             ;; (win32 wie Qt) -- die Flags werden dort nicht verglichen; Release zeigt den losgelassenen Code.
             (define code (send e get-key-code))
             (ev! "key" (cond [(eq? code 'release) (list 'release (send e get-key-release-code))]
                              [(memq code '(shift rshift control rcontrol menu alt capital numlock scroll)) (list code '-)]
                              [else (list code (mods e) (and (char? code) (char-alphabetic? code) (send e get-other-shift-key-code)))])))
           (define/override (on-focus on?) (ev! "focus" on?))
           (super-new))
         [parent p] [min-width 300] [min-height 150] [stretchable-height #f]))
  (define post (new button% [parent p] [label "post"]))
  (set! CTRLS (list (cons 'pre pre) (cons 'canvas cv) (cons 'post post)))
  (set! STATE (λ () (list 'focus (focused)))))

(define sections
  (hash "button" sec-button "check-box" sec-check-box "radio-box" sec-radio-box "choice" sec-choice
        "slider" sec-slider
        "list-single" (λ () (sec-list 'single)) "list-multiple" (λ () (sec-list 'multiple)) "list-extended" (λ () (sec-list 'extended))
        "list-columns" (λ () (sec-list 'single #t))
        "text-field" sec-text-field "combo-field" sec-combo-field "tab-panel" sec-tab-panel "tab-order" sec-tab-order
        "menu" sec-menu "popup" sec-popup "canvas" sec-canvas))

(when (equal? section "list")
  (displayln (string-join (sort (hash-keys sections) string<?) " ")) (exit 0))
((hash-ref sections section (λ () (error 'input-matrix-probe "unbekannte Sektion ~a" section))))

;; ---------------- Befehle ----------------
(define (flush-step label)
  ;; eine Zeile je Schritt:  <sektion> <label> => (Ereignisse state)
  ;; unmittelbar aufeinanderfolgende gleiche Ereignisse werden zusammengefasst (gtk meldet z. B. radio-box%-Klicks doppelt)
  (define evs (let loop ([l (reverse pending)] [acc '()])
                (cond [(null? l) (reverse acc)] [(and (pair? acc) (equal? (car acc) (car l))) (loop (cdr l) acc)] [else (loop (cdr l) (cons (car l) acc))])))
  (set! pending '())
  (out label (list evs (with-handlers ([void (λ (e) (format "EXN ~a" (exn-message e)))]) (STATE)))))
(define (print-pos)
  (for ([p CTRLS])
    (define c (cdr p))
    (define-values (sx sy) (send c client->screen 0 0))
    (define-values (w h) (if (is-a? c canvas%) (send c get-client-size) (values (send c get-width) (send c get-height))))
    (printf "POS ~a ~a ~a ~a ~a\n" (car p) sx sy w h))
  (printf "POS frame-ready\n") (flush-output))
(define (handle line)
  (define m (regexp-match #rx"^([A-Z]) ?(.*)$" line))
  (when m
    (case (cadr m)
      [("P") (print-pos)]
      [("S") (flush-step (caddr m))]
      [("Q") (printf "Q ~a ~s\n" (caddr m) (STATE)) (flush-output)]
      [("Z") (set! pending '()) (RESET)]
      [("X") (exit 0)])))
(send F show #t)
(void (thread (λ () (let loop ()
                (define l (read-line))
                (cond [(eof-object? l) (queue-callback (λ () (exit 0)))]
                      [else (queue-callback (λ () (with-handlers ([void (λ (e) (eprintf "CMD-EXN ~a\n" (if (exn? e) (exn-message e) e)))]) (handle l)))) (loop)])))))
(yield 'wait)

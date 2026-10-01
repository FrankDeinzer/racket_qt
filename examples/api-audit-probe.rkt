#lang racket/base
;; Probe fuer die API-Audit-Fixes (docs/HACKING.md section 65).  PLT_QT=1.
;; Prueft: Eventspace-Shutdown mit offenem Frame (destroy), menu% set-label in der
;; Menueleiste (set-label-top), canvas% scroll, get-client-handle, wheel-event-mode.
(require racket/gui/base racket/class)

(define ok #t)
(define (check what v) (printf "~a: ~a\n" what (if v "ok" "FAIL")) (unless v (set! ok #f)))

;; 1. destroy via Eventspace-Shutdown
(define cust (make-custodian))
(define es (parameterize ([current-custodian cust]) (make-eventspace)))
(parameterize ([current-eventspace es])
  (define f (new frame% [label "victim"] [width 100] [height 100]))
  (send f show #t))
(sleep 0.5)
(check "frame shown in user eventspace" (pair? (parameterize ([current-eventspace es]) (get-top-level-windows))))
(custodian-shutdown-all cust)
(sleep 0.3)
(check "eventspace shutdown without exception" #t)

;; 2. set-label (-> set-label-top), 3. scroll, 4. client-handle, 5. wheel mode
(define f (new frame% [label "probe"] [width 300] [height 300]))
(define mb (new menu-bar% [parent f]))
(define m (new menu% [label "&Alpha"] [parent mb]))
(new menu-item% [label "x"] [parent m] [callback void])
(define c (new canvas% [parent f] [style '(hscroll vscroll)]))
(send c init-manual-scrollbars 1000 1000 100 100 0 0)
(send f show #t)
(sleep 0.5)
(yield)
(send m set-label "&Beta")
(check "menu set-label" (equal? (send m get-label) "&Beta"))
(send c wheel-event-mode 'fraction)
(check "wheel-event-mode roundtrip" (eq? (send c wheel-event-mode) 'fraction))
(check "get-client-handle" (and (send c get-client-handle) #t))
(define ac (new canvas% [parent f] [style '(hscroll vscroll)]))
(send ac init-auto-scrollbars 1000 1000 0.0 0.0)
(send f reflow-container)
(yield)
(send ac scroll 0.5 0.5)
(yield)
(define-values (vx vy) (send ac get-view-start))
(printf "view-start after scroll 0.5 0.5: ~a ~a\n" vx vy)
(check "canvas scroll moved the view" (and (> vx 0) (> vy 0)))
(printf "RESULT ~a\n" (if ok "PASS" "FAIL"))
(exit 0)

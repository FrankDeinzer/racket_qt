#lang racket/gui
; W3 measurement probe (prompt08072026-2): characterizes the QMenuBar
; click-does-not-open bug via three isolated modes. Run with PLT_QT_DEBUG=1 so
; the shim's gated stderr diagnostics (popup APPEARED/GONE, activeWindow) fire.
; MEASUREMENT ONLY -- no fix here; see prompt08072026-2 guardrails.
;
; Usage:
;   racket examples/menu-click-probe.rkt direct    ; discriminator 1
;   racket examples/menu-click-probe.rkt keyboard  ; discriminator 3 (external SendKeys)
;   racket examples/menu-click-probe.rkt click     ; discriminator 4 (user clicks)
(require racket/cmdline
         (only-in mred/private/wx/qt/menu-bar debug-get-appended-menu))

(define mode (command-line #:args (m) m))

(define frame (new frame% [label "Menu Click Probe"] [width 500] [height 300]))
(define mb (new menu-bar% [parent frame]))
(define m-file (new menu% [label "File"] [parent mb]))
(new menu-item% [label "Quit"] [parent m-file]
     [callback (lambda (i e) (send frame show #f))])
(define m-edit (new menu% [label "Edit"] [parent mb]))
(new menu-item% [label "Copy"] [parent m-edit] [callback (lambda (i e) (void))])
(define m-help (new menu% [label "Help"] [parent mb]))
(new menu-item% [label "About"] [parent m-help] [callback (lambda (i e) (void))])

; "mixed" mode reproduces the DrRacket-observed shape: a menu with BOTH leaf
; items and a submenu, to check whether only the submenu entry renders.
(define m-mixed (new menu% [label "Mixed"] [parent mb]))
(new menu-item% [label "New"] [parent m-mixed] [callback (lambda (i e) (void))])
(define m-recent (new menu% [label "Recent"] [parent m-mixed]))
(new menu-item% [label "doc1.txt"] [parent m-recent] [callback (lambda (i e) (void))])
(new menu-item% [label "Save"] [parent m-mixed] [callback (lambda (i e) (void))])

(send frame show #t)
(printf "[PROBE] frame shown, mode=~a\n" mode)
(sleep/yield 2)

(cond
  [(equal? mode "direct")
   ; discriminator 1: call the wx-level File-menu's OWN popup method directly
   ; -- the exact QMenu instance embedded in the real QMenuBar -- bypassing
   ; QMenuBar's click-activation path entirely.
   (define file-wx-menu (debug-get-appended-menu "File"))
   (cond
     [file-wx-menu
      (printf "[PROBE] got wx-level File menu% handle, calling popup(100,100) directly\n")
      (send file-wx-menu popup 100 100 #f #f)
      (sleep/yield 5)
      (printf "[PROBE] direct-popup test done\n")]
     [else
      (printf "[PROBE] ERROR: debug-get-appended-menu returned #f -- was PLT_QT_DEBUG=1 set?\n")])]
  [(equal? mode "keyboard")
   ; discriminator 3: window stays open; an external SendKeys (F10 / Alt+F)
   ; is sent to it from outside this process.
   (printf "[PROBE] waiting 8s for external keyboard trigger (F10/Alt+F)...\n")
   (sleep/yield 8)
   (printf "[PROBE] keyboard-window done\n")]
  [(equal? mode "mixed")
   ; verification: does a menu with a leaf item AND a submenu render only the
   ; submenu entry? (theory: shim_action_create's QAction is never added to
   ; its QMenu -- only shim_menu_add_submenu's addMenu() actually inserts.)
   (define mixed-wx-menu (debug-get-appended-menu "Mixed"))
   (cond
     [mixed-wx-menu
      (printf "[PROBE] calling popup(100,100) on Mixed directly\n")
      (send mixed-wx-menu popup 100 100 #f #f)
      (sleep/yield 6)
      (printf "[PROBE] mixed test done\n")]
     [else
      (printf "[PROBE] ERROR: debug-get-appended-menu returned #f -- was PLT_QT_DEBUG=1 set?\n")])]
  [(equal? mode "click")
   ; discriminator 4: the user clicks the File title by hand.
   (printf "[PROBE] please click the File menu title now (12s window)\n")
   (sleep/yield 12)
   (printf "[PROBE] click-window done\n")]
  [else (printf "[PROBE] unknown mode ~a (use direct|keyboard|click)\n" mode)])

(send frame show #f)
(printf "[PROBE] exiting\n")

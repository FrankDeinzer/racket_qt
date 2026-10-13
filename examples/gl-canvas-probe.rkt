#lang racket/gui
;; canvas% 'gl probe (HACKING §70 triage, §78 implementation).
;; Runs natively (gtk) and with PLT_QT=1; prints one `R <name> <value>` line per
;; check.  Draws with raw ffi/unsafe libGL calls (no sgl needed): a phase-
;; specific clear colour plus a red triangle, reads the drawn pixels back with
;; glReadPixels *before* swap-buffers (proves the GL path independent of
;; composition), then swaps.  Phases: initial, resized, hidden+shown.  Each
;; phase sets the frame title to "gl-probe <phase>" and holds HOLD seconds
;; (default 1) so an external script can screenshot it.
(require ffi/unsafe)

(define gl (ffi-lib "libGL" '("1" "")))
(define-syntax-rule (defgl name type) (define name (get-ffi-obj 'name gl type)))
(defgl glViewport   (_fun _int _int _int _int -> _void))
(defgl glClearColor (_fun _float _float _float _float -> _void))
(defgl glClear      (_fun _uint -> _void))
(defgl glBegin      (_fun _uint -> _void))
(defgl glEnd        (_fun -> _void))
(defgl glColor3f    (_fun _float _float _float -> _void))
(defgl glVertex2f   (_fun _float _float -> _void))
(defgl glFinish     (_fun -> _void))
(defgl glGetString  (_fun _uint -> _string/latin-1))
(defgl glReadPixels (_fun _int _int _int _int _uint _uint _pointer -> _void))
(defgl glGenLists   (_fun _int -> _uint))
(defgl glNewList    (_fun _uint _uint -> _void))
(defgl glEndList    (_fun -> _void))
(defgl glIsList     (_fun _uint -> _bool))
(defgl glGenTextures (_fun _int (t : (_ptr o _uint)) -> _void -> t))
(defgl glBindTexture (_fun _uint _uint -> _void))
(defgl glIsTexture  (_fun _uint -> _bool))
(define GL_COMPILE #x1300)
(define GL_TEXTURE_2D #x0DE1)
(define GL_COLOR_BUFFER_BIT #x4000)
(define GL_TRIANGLES 4)
(define GL_RGBA #x1908)
(define GL_UNSIGNED_BYTE #x1401)
(define GL_VERSION #x1F02)
(define GL_RENDERER #x1F01)

(define HOLD (or (string->number (or (getenv "HOLD") "1")) 1))
(define (R k v) (printf "R ~a ~a\n" k v) (flush-output))

;; phase -> clear colour (0..1)
(define phase-colors
  (hash "initial" '(0.1 0.3 0.8)    ; blue
        "resized" '(0.1 0.7 0.2)    ; green
        "shown"   '(0.6 0.1 0.6)))  ; purple
(define phase "initial")
(define paints 0)
(define last-readback #f)

(define (pixel x y)
  (define buf (malloc 4 'raw))
  (glReadPixels x y 1 1 GL_RGBA GL_UNSIGNED_BYTE buf)
  (define v (for/list ([i 4]) (ptr-ref buf _byte i)))
  (free buf)
  v)

(define the-list 0)     ; display list + texture created in the first on-size
(define the-tex 0)      ; (gears pattern); must survive hide/show and siblings
(define on-size-calls 0)
(define gl-canvas%
  (class canvas%
    (inherit with-gl-context swap-gl-buffers get-gl-client-size)
    (define/override (on-size w h)
      (set! on-size-calls (add1 on-size-calls))
      (when (zero? the-list)
        (with-gl-context
         (lambda ()
           (set! the-list (glGenLists 1))
           (glNewList the-list GL_COMPILE) (glEndList)
           (set! the-tex (glGenTextures 1))
           (glBindTexture GL_TEXTURE_2D the-tex)
           (glBindTexture GL_TEXTURE_2D 0))
         #:fail void)))
    (define/override (on-paint)
      (define-values (w h) (get-gl-client-size))
      (with-gl-context
       (lambda ()
         (glViewport 0 0 w h)
         (apply glClearColor (append (hash-ref phase-colors phase) '(1.0)))
         (glClear GL_COLOR_BUFFER_BIT)
         (glBegin GL_TRIANGLES)
         (glColor3f 1.0 0.0 0.0)
         (glVertex2f -0.5 -0.5) (glVertex2f 0.5 -0.5) (glVertex2f 0.0 0.5)
         (glEnd)
         (glFinish)
         ;; corner = clear colour, centre = triangle (red)
         (set! last-readback (list w h (pixel 2 2) (pixel (quotient w 2) (quotient h 2))))
         (swap-gl-buffers))
       #:fail (lambda () (set! last-readback 'no-context)))
      (set! paints (add1 paints)))
    (define/override (on-event e)
      (when (and (eq? this c) (eq? (send e get-event-type) 'left-down))
        (set! clicks (add1 clicks))))
    (super-new)))
(define clicks 0)

(define f (new frame% [label "gl-probe init"] [width 300] [height 240]))
(define c (new gl-canvas% [parent f] [style '(gl no-autoclear)]
               [gl-config (new gl-config%)]))
(define b (new button% [parent f] [label "Sibling button"]))
;; sgl's gl-frame.rkt asks for the context (and ok?) before the first show.
(let ([ctx (send (send c get-dc) get-gl-context)])
  (R "pre-show/context" (and ctx #t))
  (R "pre-show/ok?" (and ctx (send ctx ok?))))
(send f show #t)
(define (objects-alive)
  (send c with-gl-context
        (lambda () (list (glIsList the-list) (glIsTexture the-tex)))
        #:fail (lambda () 'no-context)))

(define (settle [s 1]) (sleep/yield s))
(define (run-phase name)
  (set! phase name)
  (send f set-label (format "gl-probe ~a" name))
  (send c refresh)
  (settle 1)
  (define ctx (send (send c get-dc) get-gl-context))
  (R (format "~a/context" name) (and ctx #t))
  (R (format "~a/ok?" name) (and ctx (send ctx ok?)))
  (R (format "~a/readback(w h corner center)" name) last-readback)
  (settle HOLD))

(settle 1)
(R "gl-context" (send (send c get-dc) get-gl-context))
(R "with-gl-context"
   (with-handlers ([void (lambda (e) (format "error: ~a" (exn-message e)))])
     (send c with-gl-context (lambda () (list (glGetString GL_VERSION)
                                              (glGetString GL_RENDERER))))))
(R "button-dc-gl-context (non-gl canvas must be #f)"
   (let ([plain (new canvas% [parent f] [min-height 1] [stretchable-height #f])])
     (begin0 (send (send plain get-dc) get-gl-context)
             (send f delete-child plain))))
(run-phase "initial")
;; Resize: with RESIZE_EXTERNAL the driver script resizes the window through
;; the window manager (xdotool windowsize); otherwise frame% resize.  (Under Qt
;; a programmatic frame% resize currently does not re-layout the children --
;; independent of 'gl, see HACKING §78.4.)
(define-values (w0 h0) (send c get-client-size))
(cond
  [(getenv "RESIZE_EXTERNAL")
   (send f set-label "gl-probe await-resize")
   (let loop ([n 0])
     (define-values (w h) (send c get-client-size))
     (unless (or (> n 100) (not (and (= w w0) (= h h0))))
       (settle 0.1) (loop (add1 n))))]
  [else (send f resize 420 300)])
(settle 1)
(R "resize(before after)"
   (list (list w0 h0) (call-with-values (lambda () (send c get-client-size)) list)))
(run-phase "resized")
(send f show #f)
(settle 1)
(send f show #t)
(run-phase "shown")
(R "on-size-calls" on-size-calls)
(R "list+texture alive after hide/show" (objects-alive))
;; A second 'gl canvas added to the already-shown frame: it gets its own
;; context, and the first canvas' objects survive.
;; (gl-config must be given: gtk's prepare-widget-gl-context crashes on #f.)
(define c2 (new gl-canvas% [parent f] [style '(gl no-autoclear)] [min-height 40]
                [stretchable-height #f] [gl-config (new gl-config%)]))
(settle 1)
(R "second-canvas/context-ok?" (let ([x (send (send c2 get-dc) get-gl-context)]) (and x (send x ok?))))
(R "list+texture alive after adding a 2nd gl canvas" (objects-alive))
(send f delete-child c2)
(settle 0.5)
(R "paints" paints)
(when (getenv "PROBE_CLICK_WAIT")
  ;; an external script clicks the canvas centre while this waits
  (settle (string->number (getenv "PROBE_CLICK_WAIT")))
  (R "clicks-on-gl-canvas" clicks))
(send f show #f)
(exit 0)

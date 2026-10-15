;; Smoke test of the shim through Racket's FFI inside the combined Qt+Racket WASM module.
;; Racket runs in a pthread; every shim_* call is proxied to the Qt main thread, and Qt callbacks come back through a
;; queue that shim_pump drains on this thread (qt-shim/wasm/tools/gen-proxies.py).
(require ffi/unsafe)
(define lib (ffi-lib #f))
(define-syntax-rule (F name type) (get-ffi-obj name lib type))
(define cb0 (_fun _pointer -> _void))

((F "shim_app_init" (_fun -> _void)))
(printf "version: ~a\n" ((F "shim_version" (_fun -> _string))))

(define win ((F "shim_window_create" (_fun _fpointer _pointer -> _pointer)) #f #f))
((F "shim_window_set_title" (_fun _pointer _string -> _void)) win "racket-qt wasm")
(define resizes 0)
(define resize-cb (function-ptr (lambda (ud w h) (set! resizes (add1 resizes)) (printf "RESIZE ~a x ~a\n" w h))
                                (_fun _pointer _int _int -> _void)))
((F "shim_window_set_resize_cb" (_fun _pointer _fpointer _pointer -> _void)) win resize-cb #f)
((F "shim_window_set_size" (_fun _pointer _int _int -> _void)) win 420 260)
(define content ((F "shim_window_get_content_widget" (_fun _pointer -> _pointer)) win))

(define clicks 0)
(define click-cb (function-ptr (lambda (ud) (set! clicks (add1 clicks)) (printf "BUTTON-CLICK ~a\n" clicks)) cb0))
(define btn ((F "shim_button_create" (_fun _pointer _string _fpointer _pointer -> _pointer))
             content "Click me (racket)" click-cb #f))
((F "shim_widget_set_geometry" (_fun _pointer _int _int _int _int -> _void)) btn 20 20 200 40)
((F "shim_widget_set_visible" (_fun _pointer _int -> _void)) btn 1)
((F "shim_window_show" (_fun _pointer _int -> _void)) win 1)

(define pump (F "shim_pump" (_fun _int -> _void)))
(define deadline (+ (current-inexact-milliseconds) 40000))
(let loop ()
  (when (< (current-inexact-milliseconds) deadline)
    (pump 0)
    (sleep 0.02)
    (loop)))
(printf "DONE clicks=~a resizes=~a\n" clicks resizes)

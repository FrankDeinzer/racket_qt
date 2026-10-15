;; Where do the ~90 s of (require racket/gui/base) go? Run inside the combined Qt+Racket WASM module
;; (cmake ... -DRACKET_QT_MAIN=.../load-profile.rkt). Prints PROF lines to the console.
;;  1. CPU reference (fib/sort, same code as the node benchmark)
;;  2. file-read cost of the payload (/share/pkgs/**/*.zo), MEMFS reached from a pthread
;;  3. module load (declare) vs total require time per library stage, with GC time
;;  4. the most expensive modules by exclusive load time
(define (now) (current-inexact-milliseconds))
(define (take-n l n) (if (or (zero? n) (null? l)) '() (cons (car l) (take-n (cdr l) (sub1 n)))))
(define-syntax-rule (timeit label expr)
  (let ([t0 (now)]) expr (printf "PROF cpu ~a ~a ms\n" label (round (- (now) t0)))))
(define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))
(timeit "fib30" (fib 30))
(timeit "sort200k" (sort (for/list ([i (in-range 200000)]) (modulo (* i 7919) 100003)) <))

;; --- 2. file reads ----------------------------------------------------------------------------------------------
(define zos
  (let loop ([dirs (list (string->path "/share/pkgs"))] [acc '()])
    (cond [(null? dirs) acc]
          [else
           (define-values (files subdirs)
             (for/fold ([fs '()] [ds '()]) ([p (in-list (directory-list (car dirs) #:build? #t))])
               (cond [(directory-exists? p) (values fs (cons p ds))]
                     [(regexp-match? #rx"[.]zo$" (path->string p)) (values (cons p fs) ds)]
                     [else (values fs ds)])))
           (loop (append subdirs (cdr dirs)) (append files acc))])))
(let ([t0 (now)] [bytes 0])
  (for ([z (in-list zos)]) (set! bytes (+ bytes (bytes-length (call-with-input-file z (lambda (i) (read-bytes (file-size z) i)))))))
  (printf "PROF files ~a zo files, ~a bytes read in ~a ms\n" (length zos) bytes (round (- (now) t0))))

;; --- 3./4. instrumented loading -----------------------------------------------------------------------------------
(define stack '())            ; per active load: accumulated time of nested loads
(define stats (make-hash))    ; path -> (vector inclusive exclusive count)
(define loads 0)
(define excl-total 0.0)
(define orig-load (current-load/use-compiled))
(current-load/use-compiled
 (lambda (path name)
   (define t0 (now))
   (set! stack (cons 0.0 stack))
   (begin0 (orig-load path name)
     (let* ([dt (- (now) t0)] [child (car stack)] [ex (- dt child)])
       (set! stack (cdr stack))
       (unless (null? stack) (set! stack (cons (+ (car stack) dt) (cdr stack))))
       (set! loads (add1 loads))
       (set! excl-total (+ excl-total ex))
       (hash-update! stats path
                     (lambda (v) (vector (+ (vector-ref v 0) dt) (+ (vector-ref v 1) ex) (add1 (vector-ref v 2))))
                     (vector 0.0 0.0 0))))))

(define (stage name mod)
  (define t0 (now)) (define g0 (current-gc-milliseconds)) (define l0 loads) (define e0 excl-total)
  (dynamic-require mod #f)
  (define wall (- (now) t0))
  (printf "PROF stage ~a: total ~a ms, gc ~a ms, ~a modules declared, load(declare) ~a ms, rest(instantiate etc.) ~a ms\n"
          name (round wall) (- (current-gc-milliseconds) g0) (- loads l0) (round (- excl-total e0))
          (round (- wall (- excl-total e0)))))
(stage "racket/class" 'racket/class)
(stage "racket/draw" 'racket/draw)
(stage "racket/snip" 'racket/snip)
(stage "wxme" 'wxme)
(stage "racket/gui/base" 'racket/gui/base)
(printf "PROF total loads ~a, exclusive load time ~a ms, gc total ~a ms\n" loads (round excl-total) (current-gc-milliseconds))
(for ([p (in-list (let ([l (sort (hash->list stats) > #:key (lambda (kv) (vector-ref (cdr kv) 1)))])
                    (if (> (length l) 25) (take-n l 25) l)))])
  (printf "PROF top ~a ms excl ~a ms incl ~a  ~a\n" (round (vector-ref (cdr p) 1)) (round (vector-ref (cdr p) 1))
          (round (vector-ref (cdr p) 0)) (car p)))
(printf "PROF-DONE\n")

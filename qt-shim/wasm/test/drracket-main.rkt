;; Start the real DrRacket inside the combined Qt+Racket WASM module (HACKING §85.14).
(define t0 (current-inexact-milliseconds))
(printf "DRRACKET-START\n")
(dynamic-require 'drracket/drracket #f)
(printf "DRRACKET-LOADED ~a ms\n" (round (- (current-inexact-milliseconds) t0)))
((dynamic-require 'racket/gui/base 'yield) 'wait)

;; Idle load of the bare Racket runtime inside the WASM module (no racket/gui): does the Racket scheduler itself spin?  (HACKING §85.17)
(printf "IDLE-NOGUI-START\n")
(let loop () (sleep 1) (loop))

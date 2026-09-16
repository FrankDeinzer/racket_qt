#lang racket/base
;; Probe for the clipboard fix (docs/2026-09-14-4_report-linux.md "Nachtrag":
;; clipboard-driver% was a pure no-op stub -- get-text-data always #f).
;;
;; Three checks:
;;   1. Direct set-clipboard-string/get-clipboard-string round-trip.
;;   2. Real editor copy: text% select-all + copy, then read back via the
;;      driver's plain-TEXT path (what an external app would see).
;;   3. Real editor paste: a second text% pastes and must get the same text
;;      back through the WXME-format self-owned-clipboard path, not just
;;      plain TEXT (i.e. get-client/client-owns-clipboard? actually fires).
;;
;; Call:
;;   PLT_QT=1 QT_PLUGIN_PATH=... ~/racket/bin/racket examples/clipboard-probe.rkt
;;   (without PLT_QT for the native comparison)
(require racket/gui/base racket/class
         "pump-gate.rkt")

(define f (new frame% [label "clipboard-probe"] [width 300] [height 100]))
(send f show #t)
(pump-gate!)
(wait/pump 1)

(define (check label expected actual)
  (eprintf "[probe] ~a: expected=~s actual=~s ~a\n"
           label expected actual
           (if (equal? expected actual) "OK" "FAIL")))

;; 1. Direct string round-trip.
(send the-clipboard set-clipboard-string "HALLO-QT-TEST" 0)
(wait/pump 1)
(check "direct string round-trip" "HALLO-QT-TEST"
       (send the-clipboard get-clipboard-string 0))

;; 2. Real editor copy -> plain TEXT visible externally.
(define ed1 (new text%))
(send ed1 insert "copied from editor 1")
(send ed1 set-position 0 (send ed1 last-position))
(send ed1 copy #f 0)
(wait/pump 1)
(check "editor copy -> plain TEXT" "copied from editor 1"
       (send the-clipboard get-clipboard-string 0))

;; 3. Real editor paste into a second editor -- exercises the WXME path
;; (client-owns-clipboard?), not just the plain-text fallback.
(define ed2 (new text%))
(send ed2 paste 0)
(wait/pump 1)
(check "editor paste into second editor" "copied from editor 1"
       (send ed2 get-text))

(eprintf "[probe] done\n")
(send f show #f)

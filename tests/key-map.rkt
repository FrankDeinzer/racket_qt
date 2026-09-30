#lang racket/base
;; Deterministic, GUI-free tests for wx/qt/key-map.rkt (Block D §1.1).
;; Each row: (Qt::Key text-codepoint qt-mods platform  expected  provenance)
;;   qt-mods = shim encodeMods bitmask: Shift=1 Ctrl=2 Alt=4 Meta=8
;;   provenance 'measured   = Linux/X11 raw Qt values (PLT_QT_DEBUG log) with
;;                            the expected code taken from native gtk
;;                            (examples/key-probe.rkt), 2026-09-30.
;;              'derived    = from Qt docs + Windows/macOS reports; must be
;;                            re-measured on the target platform.
(require rackunit
         (file "../third_party/gui/gui-lib/mred/private/wx/qt/key-map.rkt"))

(define rows
  '(;; key     text  mods platform  expected     provenance
    (#x41      #x61  0    unix      #\a          measured)   ; a
    (#x41      #x41  1    unix      #\A          measured)   ; Shift+a
    (#x41      #x01  2    unix      #\a          measured)   ; Ctrl+A   (Bug A)
    (#x41      #x01  3    unix      #\A          measured)   ; Ctrl+Shift+A
    (#x5a      #x1a  2    unix      #\z          measured)   ; Ctrl+Z
    (#x31      #x31  2    unix      #\1          measured)   ; Ctrl+1
    (#x5b      #x1b  2    unix      #\[          measured)   ; Ctrl+[  (text = ESC)
    (#x5d      #x1d  2    unix      #\]          measured)   ; Ctrl+]
    (#x5c      #x1c  2    unix      #\\          measured)   ; Ctrl+\
    (#x2f      #x1f  3    unix      #\/          measured)   ; Ctrl+/ (German: Shift+7)
    (#x3b      #x3b  3    unix      #\;          measured)   ; Ctrl+;
    (#x2c      #x2c  2    unix      #\,          measured)   ; Ctrl+,
    (#x2e      #x2e  2    unix      #\.          measured)   ; Ctrl+.
    (#x2d      #x2d  2    unix      #\-          measured)   ; Ctrl+-
    (#x41      #x61  4    unix      #\a          measured)   ; Alt+a (Alt is a flag, not a key)
    (#x41      #x61  8    unix      #\a          measured)   ; Super+a
    (#x20      #x20  2    unix      #\space      measured)   ; Ctrl+Space
    (#x1000002 0     1    unix      #\tab        measured)   ; Shift+Tab = Key_Backtab
    (#x1000001 0     0    unix      #\tab        measured)
    (#x1000007 #x7f  0    unix      #\rubout     measured)   ; Delete (gtk: #\rubout)
    (#x1000003 #x08  0    unix      #\backspace  measured)
    (#x1000004 #x0d  2    unix      #\return     measured)   ; Ctrl+Return
    (#x1000030 0     0    unix      f1           measured)
    (#x1000034 0     0    unix      f5           measured)
    (#x1000034 0     1    unix      f5           measured)   ; Shift+F5
    (#x1000012 0     2    unix      left         measured)   ; Ctrl+Left
    (#x1000012 0     3    unix      left         measured)   ; Ctrl+Shift+Left
    (#x1000020 0     1    unix      shift        measured)   ; Shift press
    (#x1000021 0     2    unix      control      measured)   ; Ctrl press
    (#x1000023 0     4    unix      #f           measured)   ; Alt press: gtk drops it
    (#x1000022 0     8    unix      #f           measured)   ; Super press: dropped
    (#x1001103 0  #x2    unix      #f           measured)   ; AltGr press (Key_AltGr)
    ;; --- macOS (Cmd = Qt::Meta since AA_MacDontSwapCtrlAndMeta, §58.1) ---
    (#x41      #x61  8    macosx    #\a          derived)    ; Cmd+A: text() has the letter
    (#x43      #x63  8    macosx    #\c          derived)    ; Cmd+C
    (#x41      #x01  2    macosx    #\a          derived)    ; real Ctrl+A (Emacs binding)
    (#x1000023 0     4    macosx    menu         derived)    ; Option press unchanged
    (#x1000022 0     8    macosx    start        derived)    ; Cmd press unchanged
    ;; --- Windows ---
    (#x41      #x01  2    windows   #\a          derived)    ; Ctrl+A (Qt: text = 0x01)
    (#x52      #x12  2    windows   #\r          derived)    ; Ctrl+R
    (#x51      #x40  6    windows   #\@          derived)    ; AltGr+Q on German layout: text wins
    (#x1000023 0     4    windows   menu         derived)))

(for ([r (in-list rows)])
  (define-values (key text mods platform expected prov)
    (apply values r))
  (check-equal? (qt-key->racket-keycode key text mods #:platform platform)
                expected
                (format "~a key=0x~a text=0x~a mods=~a ~a"
                        platform (number->string key 16) (number->string text 16)
                        mods prov)))

;; Modifier flag mapping (gtk/window.rkt: Alt=mod1=meta, Super=mod4).
(check-true  (qt-mods->meta-down? 4 'unix))
(check-false (qt-mods->alt-down?  4 'unix))
(check-true  (qt-mods->mod4-down? 8 'unix))
(check-false (qt-mods->meta-down? 8 'unix))
;; macOS / Windows: straight through (Cmd = Meta on macOS).
(check-true  (qt-mods->meta-down? 8 'macosx))
(check-true  (qt-mods->alt-down?  4 'macosx))
(check-false (qt-mods->mod4-down? 8 'macosx))
(check-true  (qt-mods->alt-down?  4 'windows))

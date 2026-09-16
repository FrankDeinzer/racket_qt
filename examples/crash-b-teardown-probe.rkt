#lang racket/gui
;; Probe fuer docs/HACKING.md §39 -- "Crash B": invalid memory reference beim
;; Teardown eines frameless put-file/get-file-Skripts (docs/2026-07-11_report-
;; linux.md §6.2, seit dort als offener Befund gefuehrt).
;;
;; Root-Cause (gdb-Backtrace, nicht geraten): der C-seitige `finished`-Handler
;; in shim_file_dialog_create (qt-shim/src/shim.cpp) ruft dlg->deleteLater()
;; NACH dem Racket-Callback auf. Mit offenem frame% drainiert der laufende
;; Event-Pump dieses DeferredDelete-Event laengst, bevor irgendwas (exit)
;; ruft. In einem frameless Skript ist der Rueckgabewert von put-file/get-file
;; aber der letzte Akt vor Modul- und Prozessende -- ohne einen weiteren
;; garantierten Pump-Zyklus lieferte Qts eigener atexit-Event-Flush das
;; DeferredDelete stattdessen aus, WAEHREND andere Qt-Globals schon abgebaut
;; waren: harter Crash tief in QSettings::QSettings (ueber
;; QFileDialogPrivate::saveSettings, aus dem QFileDialog-Destruktor).
;;
;; Fix: wx/qt/filedialog.rkt ruft nach dem yield auf done-sema einmal mehr
;; (atomically (shim_pump 0)) -- dieselbe Primitive/denselben Aufrufer-Kontext
;; wie queue.rkt's Wakeup-Hook, keine neue Event-Loop. Per gdb-Breakpoint auf
;; QFileDialog::~QFileDialog bestaetigt: der Destruktor laeuft jetzt ueber
;; genau diesen neuen shim_pump-Aufruf (racket_boot -> Scall2 -> shim_pump),
;; nicht mehr ueber den 50ms-Poll-Thread und nicht mehr ueber atexit.
;;
;; Diese Probe reproduziert den historischen Crash 1:1 (frameless put-file,
;; kein frame% offen) und muss nach dem Fix sowohl beim Accept- als auch beim
;; Cancel-Pfad ohne Absturz durchlaufen.
;;
;; Aufruf (braucht echte GUI-Interaktion -- Dateiname eintippen + Enter, oder
;; Escape zum Abbrechen):
;;   PLT_QT=1 QT_PLUGIN_PATH=~/Qt/6.11.1/gcc_64/plugins ~/racket/bin/racket examples/crash-b-teardown-probe.rkt
;;   (ohne PLT_QT fuer den Nativ-Vergleich -- dort nie reproduziert, s. §39)
(printf "[crash-b-teardown-probe] about to call put-file\n")
(flush-output)
(define result (put-file))
(printf "[crash-b-teardown-probe] put-file returned: ~a\n" result)
(flush-output)

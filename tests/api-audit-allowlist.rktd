;; Allowlist für tests/api-audit.rkt.
;; Eintrag: (methode (qt-datei ...) status "Begründung")
;;   status: backlog = echte Lücke, noch nicht behoben; harmless = kein Qt-Problem
;;           (andere Datei/Klasse deckt es ab, Plattform-spezifisch, anderer Aufrufer).
;; Behobene Methoden tauchen im Audit nicht mehr auf und brauchen keinen Eintrag:
;;   destroy (frame), get-client-handle, get/set-wheel-steps-mode (window), scroll und
;;   get-gl-client-size (canvas), set-label-top (menu-bar) -- alle §65.
;; Die Datei-Liste muss EXAKT mit dem aktuellen Lauf übereinstimmen -- ändert sie
;; sich, ist der Eintrag neu zu triagieren.  Nur Methoden, die der gemeinsame Code
;; (mred/private, wx/common) per send/inherit aufruft, werden überhaupt gemeldet.

(flush (window.rkt) harmless
 "cocoa definiert flush in window.rkt; aufgerufen wird es nur auf Canvas (mrcanvas.rkt) -- qt/canvas.rkt hat es.")
(get-event-type (button.rkt check-box.rkt) harmless
 "win32-Hilfsmethode; die gemeinsamen Aufrufer senden get-event-type an Event-Objekte (control-event%), nicht an das Widget.")
(get-frame (frame.rkt message.rkt window.rkt) harmless
 "cocoa: NSView-Frame-Rechteck. Der Aufrufer (editor.rkt find-item-editor) sendet get-frame an mred-Menüobjekte, nicht an wx-Widgets.")
(get-gl-client-size (window.rkt) harmless
 "win32 definiert es in window.rkt, aufgerufen nur auf Canvas (mrcanvas.rkt); qt/canvas.rkt hat es seit §65.")
(get-scaled-client-size (window.rkt) harmless
 "win32 definiert es in window.rkt, aufgerufen nur auf Canvas (mrcanvas.rkt); qt/canvas.rkt und qt/frame.rkt haben es.")
(number (menu-bar.rkt) harmless
 "win32-menu-bar: Zufallstreffer. Der Aufrufer (mritem.rkt) sendet number an choice/list-box/radio-box, nicht an die Menüleiste.")
(reset (list-box.rkt) harmless
 "cocoa-Hilfsmethode; der Aufrufer (path-dialog.rkt) sendet reset an einen Timer.")
(set-color-callback (frame.rkt) harmless
 "cocoa-only (Farbwähler als natives Panel, wx:color-from-user-platform-mode); Qt meldet dort keinen Plattformmodus.")
(system-menu (frame.rkt) harmless
 "win32-only: mrtop.rkt ruft es nur unter (system-type) = 'windows.")
(warp-pointer (window.rkt) backlog
 "window<%> warp-pointer (Mauszeiger setzen) fehlt komplett: Aufruf endet mit 'no such method'. Braucht QCursor::setPos, also einen neuen Shim-Export; nicht benutzt von gui-lib/framework/drracket. Bei Bedarf tolerant binden.")

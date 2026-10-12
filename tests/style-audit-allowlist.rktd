;; Allowlist für tests/style-audit.rkt.
;; Eintrag: (flag (qt-datei ...) status "Begründung")
;;   status: backlog = echte Lücke, noch nicht behoben; harmless = betrifft Qt/Linux
;;           nicht oder wird anderswo abgedeckt.
;; Behobene Flags (fixed) tauchen im Audit nicht mehr auf und brauchen keinen Eintrag:
;;   can-close, can-reorder (§64.7), no-caption, float, no-focus (§64.8), border/control-border auf canvas (§64.9).
;; Die Datei-Liste muss EXAKT mit dem aktuellen Lauf übereinstimmen (wie bei
;; stub-audit-allowlist.rktd) -- ändert sie sich, ist der Eintrag neu zu triagieren.

(border (button.rkt tab-panel.rkt) harmless
 "button: gtk set-border (Default-Button); im Screenshot-Sweep (gallery) unter gtk optisch kein Unterschied zu einem normalen Button. tab-panel: nur cocoa. canvas/text-field/editor-canvas: behoben (§64.9).")
(close-button (frame.rkt) harmless
 "macOS-Titelleistenknopf (cocoa). Qt-Fenster haben unter Linux/Windows immer einen Schließknopf.")
(deleted (window.rkt) harmless
 "win32 liest 'deleted in der Basisklasse; in Qt behandelt jede Widget-Klasse (canvas/panel/tab-panel/...) 'deleted selbst per no-show?.")
(enter-packages (filedialog.rkt) harmless "macOS-only (.app-Pakete im Dateidialog).")
(fullscreen-aux (frame.rkt) harmless "macOS-only.")
(fullscreen-button (frame.rkt) harmless "macOS-only (unit.rkt setzt es nur dort).")
(gl (canvas.rkt) backlog
 "Triage HACKING §70: Qt ignoriert 'gl still (normaler Raster-Canvas, kein Absturz); get-gl-context liefert keinen echten Kontext. Echte Nutzer: sgl, plot3d-gl-Pfad. Eigener Block, Aufwand grob 2-4 Wochen (QOpenGLWidget + Kontext-Bridge).")
(horizontal (gauge.rkt) harmless
 "win32 liest 'horizontal; Qt-gauge% liest 'vertical (Default horizontal) -- gleiche Semantik.")
(hscroll (list-box.rkt) harmless "win32-spezifisch (WS_HSCROLL); QListWidget/QTreeWidget scrollen selbst.")
(multi-line (button.rkt) harmless "macOS-only (mehrzeiliger Button).")
(no-resize-border (frame.rkt) harmless
 "Wird von 'no-caption (rahmenlos) mit abgedeckt: DrRackets Tooltip-Frame nutzt es nur zusammen damit.")
(no-sheet (frame.rkt) harmless "macOS-only (Sheet-Dialoge).")
(no-system-menu (frame.rkt) harmless "win32-only, von keiner Bibliothek benutzt.")
(packages (filedialog.rkt) harmless "macOS-only.")
(resize-border (frame.rkt) harmless "macOS-only.")
(toolbar-button (frame.rkt) harmless "macOS-only (unit.rkt setzt es nur dort).")
(variable-columns (list-box.rkt) harmless "win32-spezifisch; der Qt-Mehrspaltenpfad (RacketTreeWidget) hat variable Spalten ohnehin.")

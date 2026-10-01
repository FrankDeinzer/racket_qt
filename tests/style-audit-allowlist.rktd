;; Allowlist für tests/style-audit.rkt.
;; Eintrag: (flag (qt-datei ...) status "Begründung")
;;   status: backlog = echte Lücke, noch nicht behoben; harmless = betrifft Qt/Linux
;;           nicht oder wird anderswo abgedeckt.
;; Behobene Flags (fixed) tauchen im Audit nicht mehr auf und brauchen keinen Eintrag:
;;   can-close, can-reorder (§64.7), no-caption, float, no-focus (§64.8).
;; Die Datei-Liste muss EXAKT mit dem aktuellen Lauf übereinstimmen (wie bei
;; stub-audit-allowlist.rktd) -- ändert sie sich, ist der Eintrag neu zu triagieren.

(border (button.rkt canvas.rkt tab-panel.rkt) backlog
 "button: gtk set-border (Default-Button-Rahmen); canvas: Rahmen um das Widget; tab-panel: nur cocoa. Optisch im Screenshot-Sweep gegen gtk prüfen, bevor behoben wird.")
(close-button (frame.rkt) harmless
 "macOS-Titelleistenknopf (cocoa). Qt-Fenster haben unter Linux/Windows immer einen Schließknopf.")
(control-border (canvas.rkt) backlog
 "gtk/win32/cocoa zeichnen einen Rahmen um Editor-/Text-Canvases ('control-border). Optisch im Screenshot-Sweep prüfen.")
(deleted (window.rkt) harmless
 "win32 liest 'deleted in der Basisklasse; in Qt behandelt jede Widget-Klasse (canvas/panel/tab-panel/...) 'deleted selbst per no-show?.")
(enter-packages (filedialog.rkt) harmless "macOS-only (.app-Pakete im Dateidialog).")
(fullscreen-aux (frame.rkt) harmless "macOS-only.")
(fullscreen-button (frame.rkt) harmless "macOS-only (unit.rkt setzt es nur dort).")
(gl (canvas.rkt) backlog
 "OpenGL-Canvas ('gl) wird nicht unterstützt (kein QOpenGLWidget); betrifft plot/gl-Nutzer. Eigener Block, groß.")
(hide-menu-bar (frame.rkt) backlog
 "gtk/cocoa: Vollbild ohne Menüleiste. Keine Bibliothek in gui-lib/drracket benutzt es; bei Bedarf wie gtk_window_fullscreen.")
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

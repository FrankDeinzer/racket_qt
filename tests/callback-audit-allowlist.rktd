;; Allowlist fuer tests/callback-audit.rkt (HACKING §80).
;; (hook (qt-datei ...) status "Begruendung")   status: backlog | harmless
(display-changed (dialog.rkt frame.rkt platform.rkt) backlog
  "gtk/cocoa/win32 rufen `display-changed` bei Monitor-/Aufloesungswechsel (gtk: screen-changed-Signale). Qt loest es nie aus; frame%/dialog% `display-changed` (oeffentliche API, augmentierbar) bleibt stumm. Braucht neuen Shim-Export (QGuiApplication::screenAdded/-Removed/primaryScreenChanged + QScreen::geometryChanged -> Post), Test nur durch Aendern der Bildschirmkonfiguration moeglich; kein DrRacket-Pfad bekannt.")
(on-drop-file (button.rkt canvas.rkt check-box.rkt choice.rkt gauge.rkt group-panel.rkt list-box.rkt message.rkt panel.rkt radio-box.rkt slider.rkt tab-panel.rkt window.rkt) backlog
  "gtk/win32/cocoa loesen on-drop-file auf JEDEM window% aus (`drag-accept-files` pro Widget, z.B. canvas%). Qt tut das nur fuer frame% (shim_window_set_drop_cb, §64; DrRackets Pfad). Kind-Widgets (canvas% `accept-drop-files`) bleiben stumm; braeuchte pro-Widget-Drop im Shim (RacketCanvas::dropEvent). Siehe auch stub-audit `drag-accept-files`.")
(on-mdi-activate (dialog.rkt frame.rkt platform.rkt) harmless
  "MDI gibt es nur unter Windows/macOS-Altpfaden; gtk und win32 definieren on-mdi-activate als def/public-unimplemented, cocoa ruft es nur fuer MDI-Kindfenster. Qt hat keine MDI-Fenster, kein Aufrufer.")
(on-menu-click (dialog.rkt frame.rkt menu-bar.rkt) harmless
  "Fehlalarm des Datei-Closures: Qt loest on-menu-click in menu.rkt aus (QMenu::aboutToShow -> `(send frame on-menu-click)`, §37), nicht in frame/dialog/menu-bar. Funktional geprueft (Menue-Enable-States vor dem Oeffnen).")
(on-menu-command (dialog.rkt frame.rkt) harmless
  "Fehlalarm: win32 ruft on-menu-command in frame.rkt (WM_COMMAND); Qt loest es in menu.rkt aus (`(send frame on-menu-command id)` im QAction-triggered-Callback). Menuebefehle funktionieren (Sweeps func-*).")
(on-popup (canvas.rkt) harmless
  "on-popup meldet bei gtk/win32/cocoa den Klick auf den NATIVEN Combo-Pfeil. Qt zeichnet den Pfeilstreifen selbst AUSSERHALB der Client-Groesse; wxtextfield.rkt `pre-on-event` erkennt Klicks ausserhalb des Client-Bereichs und ruft do-popup-callback + popup-combo selbst (§64.6/§74.3, combo-field-probe geprueft).")
(resized (dialog.rkt frame.rkt platform.rkt) harmless
  "gtk ruft `resized` in set-menu-bar, damit der Frame nicht um die Menueleistenhoehe waechst. Qt: QMainWindow layoutet die Leiste selbst; Probe examples/menubar-resize-probe.rkt: Client-Groesse und Kindgroessen mit Menue identisch zu gtk (Frame-Hoehe nur um die Leistenhoehe verschieden, 122 vs 127, Schriftmetrik). Resize-Folgen laufen ueber queue-on-size (§80).")

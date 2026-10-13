;; Allowlist fuer tests/callback-audit.rkt (HACKING §80).
;; (hook (qt-datei ...) status "Begruendung")   status: backlog | harmless
(display-changed (dialog.rkt platform.rkt) harmless
  "Dateinamen-Fehlalarm (§83.3): Qt loest display-changed real aus (shim_display_set_changed_cb -> frame.rkt `display-changed-cb` -> (send f display-changed) fuer jeden gezeigten frame%/dialog%; dialog% erbt von frame% und liegt ueber direct-show in all-frames). win32 referenziert es in der Fensterprozedur, daher die Dateiliste. Funktional geprueft: tests/sweep/display-changed.sh (xrandr-Moduswechsel, gtk 2 Aufrufe, Qt 1 je Wechsel).")
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

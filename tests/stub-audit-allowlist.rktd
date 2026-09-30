;; Allowlist für tests/stub-audit.rkt.
;;
;; Jeder Eintrag: (methodenname (datei ...) status "Begründung")
;;   methodenname = Symbol
;;   (datei ...)  = sortierte Liste der qt-Dateibasisnamen, in denen der Fund
;;                  aktuell auftaucht (siehe `gap-file-basenames` im Hauptmodul).
;;                  Muss EXAKT mit dem aktuellen Lauf übereinstimmen -- ändert
;;                  sich die Dateimenge (weil z.B. eine zweite Datei künftig
;;                  denselben Stub-Namen neu einführt, oder weil der Fund aus
;;                  einer Datei verschwindet), gilt der Eintrag NICHT mehr als
;;                  Treffer. Das ist Absicht: ein Allowlist-Eintrag für
;;                  `set-border` in `button.rkt` darf keinen unabhängigen
;;                  künftigen `set-border`-Stub in `check-box.rkt` mit abdecken.
;;   status = harmless      -- geprüft, kein Verhaltensdefekt, bleibt dauerhaft hier
;;            backlog        -- bestätigter/vermuteter echter Gap, in docs/HACKING.md
;;                              als offener Befund verzeichnet, künftige Session soll fixen
;;            needs-triage   -- vom Tool gefunden, NICHT einzeln gegen die echte
;;                              Anwendung verhaltensverifiziert; könnte harmless
;;                              oder backlog sein, noch nicht entschieden
;;
;; Der `raco test`-Lauf in stub-audit.rkt schlägt fehl, wenn (a) ein Methodenname
;; UND Dateiset auftaucht, das HIER NICHT exakt so steht (ein echt neuer Fund),
;; oder (b) IRGENDEIN Eintrag (gleich welchen Status) im aktuellen Lauf nicht
;; mehr (in denselben Dateien) auftaucht (Fix oder Regression, beides
;; prüfenswert) -- diese Datei enthält per Konvention nur Namen, die der Lauf
;; aktuell auch tatsächlich findet, s. u.
;;
;; Diese Datei enthält NUR Namen, die der aktuelle Lauf tatsächlich findet. Eine
;; ganze Klasse bekannter, aber vom Tool strukturell nicht sichtbarer Fälle
;; (`center`, `direct-show`, `set-modified`, `set-wait-cursor-mode`,
;; `paint-children`, `show-children`, `set-wheel-steps-mode` u.a. -- meist weil
;; ein Referenz-Backend dasselbe Konzept in einer ANDEREN Datei implementiert als
;; qt, z.B. window.rkt hier vs. frame.rkt dort) ist bewusst NICHT hier
;; eingetragen, sondern nur in docs/HACKING.md §60.9 beschrieben -- ein Eintrag
;; hier, der nie einen Treffer erzeugen kann, würde nur vortäuschen, dass er
;; aktiv geprüft wird.

(

 ;; ---- harmless ----
 (parent-enable ("window.rkt") harmless "window.rkt: von diesem Backend laut Code-Kommentar nicht benutzt (§60.7).")
 (reset-cursor ("window.rkt") harmless "window.rkt: von diesem Backend laut Code-Kommentar nicht benutzt (§60.7).")
 (screen-to-client ("window.rkt") harmless "window.rkt: von diesem Backend laut Code-Kommentar nicht benutzt (§60.7).")
 (select ("menu.rkt") harmless "menu.rkt: vom Glue-Layer benötigter Stub, kein echtes Verhalten erwartet (§60.7).")
 (get-item ("menu.rkt") harmless "menu.rkt: vom Glue-Layer benötigter Stub, kein echtes Verhalten erwartet (§60.7).")
 (removing-item ("menu.rkt") harmless "menu.rkt: vom Glue-Layer benötigter Stub, kein echtes Verhalten erwartet (§60.7).")
 (set-self-item ("menu.rkt") harmless "menu.rkt: vom Glue-Layer benötigter Stub, kein echtes Verhalten erwartet (§60.7).")
 (set-border ("button.rkt") harmless "kosmetisch auf mehreren Item-Widgets, kein Verhalten erwartet (§60.7).")
 (set-preferred-size ("message.rkt") harmless "message.rkt: fällt sauber auf die Vorgabegröße zurück (§60.7).")

 ;; ---- harmless: §61-Triage der 17 needs-triage-Kandidaten (Session 2026-09-27) ----
 (gets-focus? ("window.rkt") harmless "window.rkt: reiner Konventionsunterschied zu gtk (dessen Default #t ist), kein echter Gap. qt folgt der win32-Konvention (Default #f), jedes aktuell implementierte fokussierbare Widget (button/check-box/choice/radio-box/slider/list-box/tab-panel) überschreibt einzeln zu #t, deckungsgleich mit gtk/win32; canvas%/message%/panel% werden ohnehin von der mred-Glue-Schicht überschrieben, der wx-Wert zählt dort nicht (§61).")
 (skip-enter-leave-events ("window.rkt") harmless "window.rkt: alle realen Aufrufer (mrtop.rkt, wxlitem.rkt, mrpanel.rkt) zielen auf Panels/Messages, nie auf canvas%. Unter qt erzeugt ausschließlich canvas.rkt native Enter/Leave-Mausevents -- kein anderes qt-Widget verdrahtet sie. Der fehlende Suppress-Mechanismus kann praktisch nie zünden (§61).")
 (set-event-positions-wrt ("window.rkt") harmless "window.rkt: Companion zu skip-enter-leave-events, identische Aufrufer (Label-/Spacer-Subwidgets ohne eigenen on-event-Override). Realer Konsument (adjust-event-position) existiert nur in gtk/win32; die betroffenen qt-Subwidgets erzeugen ohnehin keine Mausevents (§61).")
 (request-canvas-flush-delay ("canvas.rkt") harmless "canvas.rkt: der reale Zweck (natives 'Redraw kurz deaktivieren') ist ein Muster für Backends, die direkt ins Fenster zeichnen. qt zeichnet strukturell immer erst offscreen (qt-dc%) und blittet dann atomar -- die Flicker-Klasse, die dieser Mechanismus verhindert, existiert in Qts Architektur nicht. Einziger Aufrufer (canvas-mixin.rkt) behandelt das zurückgegebene #f korrekt (§61).")
 (cancel-canvas-flush-delay ("canvas.rkt") harmless "canvas.rkt: korrektes Gegenstück zu request-canvas-flush-delay, s.o. (§61).")
 (skip-pre-paint? ("canvas.rkt") harmless "canvas.rkt: gtk und win32 liefern hier ebenfalls hartcodiert #f, identisch zu qt. Nur cocoa hat zusätzliche Logik, aber ausschließlich für den GL-Canvas-Zweig (is-gl?); qt implementiert keine GL-Canvases -- kein für qt erreichbarer Unterschied. Tool-Fehlalarm gegen cocoa (§61).")
 (get-dialog-level ("frame.rkt") harmless "frame.rkt: Folgefund NACH dem §61-Fix von window.rkts get-dialog-level (das jetzt an parent delegiert statt hartcodiert 0 zu sein) -- das Tool vergleicht frame.rkts trivialen Override gegen qts eigenes jetzt-substantielles window.rkt (Basisklassen-Spezialfall) und meldet ihn als neuen Gap. Ist aber korrekt und beabsichtigt: gtk/frame.rkt:330, win32/frame.rkt:507 und cocoa/frame.rkt:369 haben ALLE identisch (define/override (get-dialog-level) 0) -- ein Frame terminiert die Delegationskette immer bei 0, sein eigener Dialog-Level wird (falls er zugleich ein dialog% ist) separat über common/dialog.rkts eigenen Override geführt, nicht über den Parent-Chain-Mechanismus. Tool-Fehlalarm, kein Bug (§61).")

 (drag-accept-files ("window.rkt") harmless "window.rkt: Basisklassen-Platzhalter; frame.rkt implementiert es real (Block D §2.3, setAcceptDrops + shim_window_set_drop_cb). DrRacket ruft accept-drop-files nur auf Frames; Drops auf Kind-Widgets sind kein genutzter Pfad.")

 ;; ---- backlog: bereits bekannte, offene Gaps ----
 (set-icon ("frame.rkt") backlog "frame.rkt: Dock/Taskbar-Icon eines Fensters lässt sich nie setzen (§60.7).")
 (set-color ("message.rkt") backlog "message.rkt: wirkungslos (§60.7).")
 (get-color ("message.rkt") backlog "message.rkt: lügt mit hartem #f (§60.7).")
 (get-label-position ("panel.rkt") backlog "panel.rkt: immer 'horizontal, win32/gtk/cocoa führen echten Zustand (§60.7).")
 (set-label-position ("panel.rkt") backlog "panel.rkt: wirkungslos, win32/gtk/cocoa führen echten Zustand (§60.7).")
 (adopt-child ("panel.rkt") backlog "panel.rkt: reparented nie wirklich, win32/gtk tun es über set-parent (§60.7).")

 ;; ---- backlog: §61-Triage der 17 needs-triage-Kandidaten (Session 2026-09-27) ----
 (do-canvas-backing-flush ("canvas.rkt") backlog "canvas.rkt: periodisches Safety-Net-Flush (schedule-periodic-backing-flush) fehlt unter qt komplett, obwohl der Mechanismus strukturell auf allen 4 Backends identisch aktiv ist (gtk/win32 planen ihn ebenfalls über canvas-mixin.rkt, nicht Windows-exklusiv trotz Kommentar). Kein beobachtetes Symptom in der gesamten Redraw-/Resize-Fix-Historie (§16/§32/§33/§34) -- qts eager primärer queue-backing-flush-Pfad läuft zuverlässig genug, dass das Safety-Net bislang nie gebraucht wurde. Echte Lücke, unklarer/vermutlich niedriger Impact (§61).")
 (popup-combo ("canvas.rkt") backlog "canvas.rkt: Reachability bestätigt (§61, widerspricht §60.7s Fehleinschätzung als totes Feature) -- combo-field% wird real von DrRackets Multi-File-Search (drracket/private/multi-file-search.rkt) und optional get-file/put-file '(common) genutzt. Klick auf den Combo-Pfeil tut unter qt nichts (kein Crash, Dropdown bleibt tot). Fix braucht neuen Popup-/Positionierungsmechanismus (ggf. Wiederverwendung der §59-Popup-Menü-Infrastruktur) -- vergleichbare Größenordnung wie §60.6, eigene künftige Session statt Nebenfix.")
 (clear-combo-items ("canvas.rkt") backlog "canvas.rkt: gleicher Cluster wie popup-combo (§61). Alte Menüeinträge werden nie entfernt -- ohnehin irrelevant, solange append-combo-item nie real hinzufügt.")
 (append-combo-item ("canvas.rkt") backlog "canvas.rkt: gleicher Cluster wie popup-combo (§61). Gibt hartcodiert #f zurück -> Aufrufer (wxtextfield.rkt) bricht Callback-Registrierung sofort ab, während gtk/cocoa wahrheitsgemäß #t liefern.")
 (set-combo-text ("canvas.rkt") backlog "canvas.rkt: gleicher Cluster wie popup-combo (§61), aber niedrigste Priorität -- rein kosmetischer Sync-Effekt, gtk selbst hat hier bereits denselben No-op wie qt.")
 (refresh ("window.rkt") backlog "window.rkt: kein Fehlalarm -- gtk überschreibt refresh-all-children konkret (gtk/panel.rkt, gtk/frame.rkt), qt hat keine solche Überschreibung, refresh selbst ist unter qt hartcodiert (void) statt zu delegieren. Alle internen framework/DrRacket-Aufrufer zielen aber ausschließlich auf canvas%-Subklassen, die unter qt bereits eine eigene echte refresh-Implementierung haben -- für diese Aufrufer folgenlos. Übrig bleibt der öffentliche window<%>-refresh-API-Wrapper: (send my-panel refresh) aus Anwendungscode wäre ein stiller No-op statt kaskadierendem Kind-Repaint. Kein aktueller interner Aufrufer trifft diesen Pfad, daher kein akuter Impact beobachtet -- reiner Racket-Fix möglich, aber kein Nebenfix (§61).")
 (register-child ("panel.rkt") backlog "panel.rkt: hängt mit refresh zusammen (s.o.) -- die Kind-Registry (register-child-in-parent), die gtk/win32/cocoa für refresh-all-children/paint-children/notify-children-top-realize nutzen, existiert unter qt gar nicht (nie aufgerufen). Ob Qts natives Widget-Compositing (jedes QWidget hat eigene paintEvents) diese Kaskade strukturell überflüssig macht, ist nicht belegt, nur vermutet -- in der ganzen Redraw-/Resize-Fix-Historie nie ein zugehöriges Symptom aufgetaucht. Gleiche Priorität wie refresh (§61).")

 )

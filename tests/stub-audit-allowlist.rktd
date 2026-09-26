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

 ;; ---- backlog: bereits bekannte, offene Gaps ----
 (set-focus ("window.rkt") backlog "Größter Einzelfund aus §60.7: auf praktisch jedem Basis-Widget (button/choice/radio-box/slider/list-box/tab-panel/check-box/message/group-panel) wirkungslos, obwohl shim_widget_set_focus existiert.")
 (set-icon ("frame.rkt") backlog "frame.rkt: Dock/Taskbar-Icon eines Fensters lässt sich nie setzen (§60.7).")
 (set-color ("message.rkt") backlog "message.rkt: wirkungslos (§60.7).")
 (get-color ("message.rkt") backlog "message.rkt: lügt mit hartem #f (§60.7).")
 (get-label-position ("panel.rkt") backlog "panel.rkt: immer 'horizontal, win32/gtk/cocoa führen echten Zustand (§60.7).")
 (set-label-position ("panel.rkt") backlog "panel.rkt: wirkungslos, win32/gtk/cocoa führen echten Zustand (§60.7).")
 (adopt-child ("panel.rkt") backlog "panel.rkt: reparented nie wirklich, win32/gtk tun es über set-parent (§60.7).")
 (get-column-order ("list-box.rkt") backlog "list-box.rkt: Teil des bewusst einspaltigen Mehrspalten-Stubs, Umbau auf QTreeWidget vorgesehen (§60.6).")
 (set-column-order ("list-box.rkt") backlog "list-box.rkt: s.o. (§60.6).")
 (get-column-size ("list-box.rkt") backlog "list-box.rkt: gibt (values 100 0 10000) statt echter Spaltenbreite zurück (§60.6).")
 (set-column-size ("list-box.rkt") backlog "list-box.rkt: s.o. (§60.6).")
 (set-column-label ("list-box.rkt") backlog "list-box.rkt: s.o. (§60.6).")
 (append-column ("list-box.rkt") backlog "list-box.rkt: s.o. (§60.6).")
 (delete-column ("list-box.rkt") backlog "list-box.rkt: s.o. (§60.6).")

 ;; ---- needs-triage: gefunden, nicht einzeln verhaltensverifiziert ----
 (drag-accept-files ("window.rkt") needs-triage "window.rkt: Drag-and-Drop von Dateien auf ein Fenster fehlt unter Qt vermutlich komplett. Nicht verifiziert.")
 (enforce-size ("frame.rkt") needs-triage "frame.rkt (und window.rkt, dort aber vom Tool nicht separat sichtbar, s. Kopfkommentar dieser Datei): (void) an beiden Stellen -- Fenster-Resize-Constraints (Min/Max-Größe) werden unter Qt nie durchgesetzt. Wirkt wie ein echter Gap, aber keine praktische Auswirkung in dieser Session beobachtet.")
 (get-canvas-background-for-backing ("canvas.rkt") needs-triage "canvas.rkt: Backing-Store-Hintergrundfarbe, nicht Scroll/Combo. Separat zu prüfen.")
 (get-dialog-level ("window.rkt") needs-triage "window.rkt/frame.rkt: vermutlich Zähler für verschachtelte modale Dialoge. Unter Qt konstant -- Auswirkung auf Dialog-Stapelung nicht verifiziert.")
 (gets-focus? ("window.rkt") needs-triage "window.rkt: Abfrage 'kann dieses Widget Fokus annehmen', nur bei cocoa real. Verwandt mit dem set-focus-Gap, aber als Lesezugriff separat zu behandeln.")
 (refresh ("window.rkt") needs-triage "window.rkt: (void), während gtk/cocoa/win32s window.rkt echtes refresh haben. ABER: gtks eigene Referenz-Implementierung ruft selbst nur (refresh-all-children) auf, und refresh-all-children ist in gtk/window.rkt SELBST WIEDER (void) -- für ein generisches Widget ohne eigene Overrides ist der Netto-Effekt in beiden Backends vermutlich identisch (nichts). Könnte ein Fehlalarm der strukturellen Klassifikation sein (sie löst keine Aufrufindirektion auf); braucht echten Verhaltensvergleich. canvas% hat unter qt ohnehin eine eigene echte refresh-Implementierung, betrifft also nur Widgets, die window.rkts Default erben.")
 (register-child ("panel.rkt") needs-triage "panel.rkt: verwandt mit adopt-child (Backlog) -- Reparenting-Infrastruktur zwischen Containern. Nicht verifiziert.")
 (request-canvas-flush-delay ("canvas.rkt") needs-triage "canvas.rkt: Flush-Delay-Scheduling, nicht Scroll/Combo. Separat zu prüfen.")
 (cancel-canvas-flush-delay ("canvas.rkt") needs-triage "canvas.rkt: s.o. Separat zu prüfen.")
 (do-canvas-backing-flush ("canvas.rkt") needs-triage "canvas.rkt: Backing-Store-Flush-Scheduling, nicht Scroll/Combo. Separat zu prüfen.")
 (skip-pre-paint? ("canvas.rkt") needs-triage "canvas.rkt: Paint-Scheduling, nicht Scroll/Combo. Separat zu prüfen.")
 (skip-enter-leave-events ("window.rkt") needs-triage "window.rkt: vermutlich Unterdrückung von Mouse-Enter/Leave-Events in bestimmten Zuständen. Auswirkung nicht verifiziert.")
 (set-event-positions-wrt ("window.rkt") needs-triage "window.rkt: Event-Koordinaten-Transformation. Könnte unter Qt strukturell unnötig sein (eigenes Koordinatensystem), nicht verifiziert.")
 (popup-combo ("canvas.rkt") needs-triage "canvas.rkt: einziges Vorkommen, kein Mixin/keine spezifischere Klasse überschreibt es -- WIDERSPRICHT §60.7s Einordnung als 'Combo-Basisklassen-Default, echte Implementierung sitzt in Mixins'. §60.7 hatte für diese vier Combo-Methoden offenbar nicht einzeln nachgesehen, sondern sie pauschal in dieselbe Kategorie wie die (tatsächlich per Mixin abgedeckten) Scroll-Methoden gesteckt. Echtes Combo-Verhalten (Autocomplete-Popup in editierbaren choice%/Textfeldern?) könnte unter Qt komplett fehlen.")
 (clear-combo-items ("canvas.rkt") needs-triage "canvas.rkt: s.o., gleicher Widerspruch zu §60.7.")
 (append-combo-item ("canvas.rkt") needs-triage "canvas.rkt: s.o., gleicher Widerspruch zu §60.7. Rückgabewert ist sogar #f statt eines Werts, der wie ein Erfolgs-/Index-Flag aussehen soll.")
 (set-combo-text ("canvas.rkt") needs-triage "canvas.rkt: s.o., gleicher Widerspruch zu §60.7.")

 )

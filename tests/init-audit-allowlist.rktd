;; Allowlist für tests/init-audit.rkt (§79).
;; Eintrag: (qt-datei klasse initarg kind status "Begründung")
;;   kind: missing = Qt-Klasse deklariert das Init-Argument nicht; unused = deklariert, nie benutzt.
;;   status: backlog = echte Lücke, noch offen; harmless = ohne Qt-Wirkung/anders gelöst.
;; Behobene Funde (font in message/button/check-box/choice/radio-box/list-box, §74.1) brauchen keinen Eintrag.
;; Die Kind-Angabe und die Datei müssen EXAKT zum aktuellen Lauf passen (wie bei den anderen Audits).

(check-box.rkt check-box% h unused harmless
 "Anfangsgröße: nur cocoa/win32 setzen damit die native Größe; gtk (die Linux-Referenz) ignoriert sie, Qt-Größen kommen aus set-size/seed-size-from-native-hint (§61.1/§74.1).")
(check-box.rkt check-box% w unused harmless
 "Anfangsgröße: nur cocoa/win32 setzen damit die native Größe; gtk (die Linux-Referenz) ignoriert sie, Qt-Größen kommen aus set-size/seed-size-from-native-hint (§61.1/§74.1).")
(choice.rkt choice% h unused harmless
 "Anfangsgröße: nur cocoa/win32 setzen damit die native Größe; gtk (die Linux-Referenz) ignoriert sie, Qt-Größen kommen aus set-size/seed-size-from-native-hint (§61.1/§74.1).")
(choice.rkt choice% label unused harmless
 "Control-Label: mred (wxlitem/mrcontrol) zeigt es als eigenes message%; das wx-Label wird nur von win32/cocoa als Fenstertitel genutzt (gtk: Schattenvariable/ungenutzt). Kein Qt-Effekt.")
(choice.rkt choice% w unused harmless
 "Anfangsgröße: nur cocoa/win32 setzen damit die native Größe; gtk (die Linux-Referenz) ignoriert sie, Qt-Größen kommen aus set-size/seed-size-from-native-hint (§61.1/§74.1).")
(frame.rkt frame% is-dialog? missing harmless
 "Qt-dialog% setzt das Verhalten selbst (frame.rkt: clear-icon!/Icon-Standard, §75.1); Initarg wird nicht positional von gemeinsamem Code übergeben.")
(gauge.rkt gauge% label unused harmless
 "Control-Label: mred (wxlitem/mrcontrol) zeigt es als eigenes message%; das wx-Label wird nur von win32/cocoa als Fenstertitel genutzt (gtk: Schattenvariable/ungenutzt). Kein Qt-Effekt.")
(group-panel.rkt group-panel% h unused harmless
 "Anfangsgröße: nur cocoa/win32 setzen damit die native Größe; gtk (die Linux-Referenz) ignoriert sie, Qt-Größen kommen aus set-size/seed-size-from-native-hint (§61.1/§74.1).")
(group-panel.rkt group-panel% w unused harmless
 "Anfangsgröße: nur cocoa/win32 setzen damit die native Größe; gtk (die Linux-Referenz) ignoriert sie, Qt-Größen kommen aus set-size/seed-size-from-native-hint (§61.1/§74.1).")
(list-box.rkt list-box% h unused harmless
 "Anfangsgröße: nur cocoa/win32 setzen damit die native Größe; gtk (die Linux-Referenz) ignoriert sie, Qt-Größen kommen aus set-size/seed-size-from-native-hint (§61.1/§74.1).")
(list-box.rkt list-box% label unused harmless
 "Control-Label: mred (wxlitem/mrcontrol) zeigt es als eigenes message%; das wx-Label wird nur von win32/cocoa als Fenstertitel genutzt (gtk: Schattenvariable/ungenutzt). Kein Qt-Effekt.")
(menu.rkt menu% callback missing harmless
 "Umbenannt: Qt-menu% deklariert positional `popup-callback` (Reihenfolge label callback font identisch); Funktion in §59.1 verdrahtet.")
(menu.rkt menu% cb missing harmless
 "Umbenannt (popup-callback), s. callback.")
(menu.rkt menu% label missing harmless
 "Control-Label: mred (wxlitem/mrcontrol) zeigt es als eigenes message%; das wx-Label wird nur von win32/cocoa als Fenstertitel genutzt (gtk: Schattenvariable/ungenutzt). Kein Qt-Effekt.")
(menu.rkt menu% lbl missing harmless
 "Umbenannt (popup-label).")
(message.rkt message% x unused harmless
 "cocoa positioniert Labels über x/y; Qt/gtk platzieren per set-size des Layouts.")
(message.rkt message% y unused harmless
 "cocoa positioniert Labels über x/y; Qt/gtk platzieren per set-size des Layouts.")
(panel.rkt panel% h unused harmless
 "Anfangsgröße: nur cocoa/win32 setzen damit die native Größe; gtk (die Linux-Referenz) ignoriert sie, Qt-Größen kommen aus set-size/seed-size-from-native-hint (§61.1/§74.1).")
(panel.rkt panel% w unused harmless
 "Anfangsgröße: nur cocoa/win32 setzen damit die native Größe; gtk (die Linux-Referenz) ignoriert sie, Qt-Größen kommen aus set-size/seed-size-from-native-hint (§61.1/§74.1).")
(radio-box.rkt radio-box% h unused harmless
 "Anfangsgröße: nur cocoa/win32 setzen damit die native Größe; gtk (die Linux-Referenz) ignoriert sie, Qt-Größen kommen aus set-size/seed-size-from-native-hint (§61.1/§74.1).")
(radio-box.rkt radio-box% label unused harmless
 "Control-Label: mred (wxlitem/mrcontrol) zeigt es als eigenes message%; das wx-Label wird nur von win32/cocoa als Fenstertitel genutzt (gtk: Schattenvariable/ungenutzt). Kein Qt-Effekt.")
(radio-box.rkt radio-box% w unused harmless
 "Anfangsgröße: nur cocoa/win32 setzen damit die native Größe; gtk (die Linux-Referenz) ignoriert sie, Qt-Größen kommen aus set-size/seed-size-from-native-hint (§61.1/§74.1).")
(slider.rkt slider% font unused harmless
 "gtk deklariert `font` für slider% ebenfalls nur und ignoriert es (cocoa/win32: set-control-font); Slider-Schrift bewusst nicht gesetzt (§74.1), kein Symptom in DrRacket.")
(slider.rkt slider% label unused harmless
 "Control-Label: mred (wxlitem/mrcontrol) zeigt es als eigenes message%; das wx-Label wird nur von win32/cocoa als Fenstertitel genutzt (gtk: Schattenvariable/ungenutzt). Kein Qt-Effekt.")
(slider.rkt slider% w unused harmless
 "Anfangsgröße: nur cocoa/win32 setzen damit die native Größe; gtk (die Linux-Referenz) ignoriert sie, Qt-Größen kommen aus set-size/seed-size-from-native-hint (§61.1/§74.1).")
(tab-panel.rkt tab-panel% choices missing harmless
 "Umbenannt: Qt deklariert positional `labels` (win32-Name `choices`); Beleg Tab-Beschriftungen laufen in jedem Sweep.")
(window.rkt window% add-to-parent? missing harmless
 "Backend-interne Initarg des Referenz-Toolkits (natives Handle/GTK-Widget), Qt hat Äquivalent über `handle`.")
(window.rkt window% cocoa missing harmless
 "Backend-interne Initarg des Referenz-Toolkits (natives Handle/GTK-Widget), Qt hat Äquivalent über `handle`.")
(window.rkt window% connect-size-allocate? missing harmless
 "Backend-interne Initarg des Referenz-Toolkits (natives Handle/GTK-Widget), Qt hat Äquivalent über `handle`.")
(window.rkt window% extra-gtks missing harmless
 "Backend-interne Initarg des Referenz-Toolkits (natives Handle/GTK-Widget), Qt hat Äquivalent über `handle`.")
(window.rkt window% extra-hwnds missing harmless
 "Backend-interne Initarg des Referenz-Toolkits (natives Handle/GTK-Widget), Qt hat Äquivalent über `handle`.")
(window.rkt window% gtk missing harmless
 "Backend-interne Initarg des Referenz-Toolkits (natives Handle/GTK-Widget), Qt hat Äquivalent über `handle`.")
(window.rkt window% hwnd missing harmless
 "Backend-interne Initarg des Referenz-Toolkits (natives Handle/GTK-Widget), Qt hat Äquivalent über `handle`.")
(window.rkt window% style missing harmless
 "win32 wertet Fensterstil-Bits aus; Qt-window% bekommt 'deleted über no-show? (frame/Steuerelement-Klassen lesen style selbst).")

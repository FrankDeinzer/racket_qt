# Freier Test — Plan für eine künftige Session (macOS)

Vorbereitet am Ende von Session „2026-09-26 (3, macOS)" (`docs/HACKING.md` §60,
`STATUS.md`), auf ausdrücklichen Wunsch des Nutzers: „plane einen eigenen freien Test".
Kein automatisch startender Auftrag — dieser Prompt ist die Checkliste/Priorität für
die *nächste* freie oder gezielte Testsession.

## Ausgangslage

Der letzte freie Test (Nutzer testete DrRacket unter `PLT_QT=1` ohne Vorgabe) fand in
einer einzigen Nachricht vier unabhängige Bugs. Zwei davon waren stille No-op-Stubs
(`button%`s `set-label`, `list-box%`s Mehrspalten-API) — das spricht dafür, dass es
**weitere, noch nicht entdeckte stille Stubs** gibt, die erst bei tatsächlicher
Nutzung auffallen, nicht bei Code-Review. Diese Session soll gezielt danach suchen,
nicht nur zufällig durch die GUI klicken.

## Priorität 1 — `set-focus`-Stub-Reichweite (§60.7 größter Einzelfund)

`(send widget focus)` ist auf praktisch jedem Basis-Widget dieses Backends
(`button%`, `choice%`, `radio-box%`, `slider%`, `list-box%`, `tab-panel%`,
`check-box%`, `message%`, `group-panel%`) ein No-op — nur `canvas%` setzt Fokus
wirklich (`shim_widget_set_focus`). Test:

- Tab-Reihenfolge durch ein Formular mit mehreren Widget-Typen (nicht nur
  Canvas/Editor) — bleibt der sichtbare Fokusring korrekt?
- Jede Stelle in DrRacket, die programmatisch Fokus setzt (z. B. nach Öffnen eines
  Dialogs auf das erste Feld, Suchen-Dialog, Fehlermeldungs-Fokus) — landet der
  Tastaturfokus wirklich dort, oder bleibt er woanders?
- Falls reproduzierbar kaputt: Fix ist vermutlich mechanisch (jede Klasse braucht ein
  `(define/override (set-focus) (shim_widget_set_focus qt-handle))` analog zu
  `canvas.rkt:410`), aber bitte erst den tatsächlichen Impact an echten
  Symptomen verifizieren, nicht blind alle Klassen patchen.

## Priorität 2 — Package Manager Mehrspalten-Listen (§60.6, substantielles Feature)

Größte offene Lücke aus der letzten Session, bewusst nicht nebenbei gefixt. Vor dem
Umbau:

- „Available from Catalog" native (cocoa) vs. Qt vergleichen — ein Teil des
  gemeldeten Kaputt-Seins hängt evtl. am Katalog-Download selbst, nicht nur an
  Spalten (erst isolieren, was wirklich am `list-box%`-Mehrspalten-Stub liegt).
- Falls Umbau angegangen wird: `QListWidget` → `QTreeWidget` im Shim
  (`shim_list_box_create`), Header-Labels, `setText(col, …)` pro Zelle,
  `header()->sectionClicked` → `column-control-event%` (Regel 2: `queue-event`,
  nicht synchron). Referenz: `wx/gtk/list-box.rkt`s `GtkTreeView`-Anbindung.
  `columns`/`column-order`-Initargs kommen laut `wx/qt/list-box.rkt` bereits an,
  werden nur ignoriert.
- Neuer Shim-Export(e) nötig → ABI-Banner in `CLAUDE.md` nicht vergessen.

## Priorität 3 — Choose-Language „Collection Paths"-Buttons, zweite Ursache (§60.4)

Der `list-box%`-sizeHint-Deckel (6 Zeilen, §60.4) behebt nachweislich die
„viele-Zeilen"-Variante, aber im echten Dialog (nur 1 Standard-Eintrag) bleibt die
Button-Reihe darunter sichtbar abgeschnitten. Verdacht: `button-panel%`/
`group-box-panel%`-Layoutberechnung setzt ein bereits vorhandenes
`stretchable-height #f` nicht durch. Vorgehen:

- Minimalen Repro bauen: `group-box-panel%` mit einem `list-box%` (1 Eintrag) und
  einem `horizontal-panel%` (`stretchable-height #f`) darunter, in einem
  Fenster mit knapper Höhe — reproduziert das isoliert das Abschneiden?
- `mrcontainer.rkt`s `do-get-graphical-min-size`-Berechnung für verschachtelte
  Panels mit einem stretchable Kind (`list-box%`) und einem non-stretchable
  Geschwister nachvollziehen — wird das Geschwister-Minimum tatsächlich reserviert,
  bevor der Rest ans stretchable Kind geht?

## Priorität 4 — Choose-Language Hintergrundfarbe, Nativ-Vergleich (§60.5)

Kein hartcodierter Hintergrund im Shim gefunden, aber in dieser Session kein
Seite-an-Seite-Vergleich gemacht.

- Echtes cocoa-DrRacket (ohne `PLT_QT`) UND Qt-DrRacket öffnen, „Choose Language…",
  Screenshot beider, Pixel an derselben Stelle (linke Spalte, Hierlist-Hintergrund
  vs. Dialog-Rahmen) vergleichen.
- Falls Unterschied real: `get-panel-background`/Label-Hintergrund-Prozeduren in
  `wx/qt/` suchen, ob irgendwo eine Systemfarbe fehlt statt `QPalette::Window`
  weiterzugeben.

## Priorität 5 — Genereller Durchgang (Basis-Absicherung)

- Jedes Menü einmal öffnen, jeden Dialog einmal öffnen (nativ + Qt gegenüberstellen,
  Screenshot-Paare) — systematischer als „frei klicken", damit stille Stubs wie
  §60.3/§60.6 nicht wieder nur durch Zufall auffallen.
- Jeden Tab, jeden Toggle-Button, Tastaturnavigation in Listen und Datei-Dialogen
  durchklicken.
- Jedes Menü **zweimal** öffnen (Race-Klasse wie §60.2 kann auch anderswo lauern,
  wo ein Demand-Callback nur reaktiv verdrahtet ist).

## Methodik-Lehren aus der letzten Session (nicht wiederholen)

- **Vor der Session:** `caffeinate -d -i -u -t <sekunden>` starten. Display-Sleep
  (macOS-Default 5 min) hat wiederholt Ergebnisse verfälscht — manchmal offensichtlich
  (schwarzer Screenshot), manchmal unauffällig (`System Events` liefert leere
  Ergebnisse/-1728-Fehler trotz lebendigem, sichtbarem Fenster). `-u` allein reicht
  nicht, `-d` ist der eigentlich wirksame Teil hier.
- **Prozess-Hygiene:** `pkill -x racket`/SIGTERM tötet einen laufenden
  DrRacket-Prozess auf dieser Maschine nicht zuverlässig. Vor JEDEM Test-Start:
  `ps aux | grep -i racket`, jede gefundene PID mit `kill -9` beenden, erneut
  prüfen bis leer — sonst bindet `tell process "racket"` nicht deterministisch an
  den gerade gestarteten Prozess, und Timing-Messungen sind wertlos.
- **Tastatureingaben in Qt-Sheets/-Dialogen:** `osascript … key code N` und
  `cliclick kp:<taste>` kamen im Datei-Dialog-Sheet nicht an (auch Pfeiltasten
  bewegten die Auswahl nicht), obwohl derselbe Prozess Klicks unmittelbar davor
  korrekt empfing. `osascript … keystroke <taste>` hat zuverlässig funktioniert.
  Fokus-Diagnose vor jeder Tastaturaktion: einen Buchstaben tippen, prüfen ob (a)
  Type-Ahead die Auswahl verschiebt (View hat Fokus) oder (b) er in einem Textfeld
  erscheint (Editor hat Fokus).
- **Klicks auf AX-Zeilen** (`click row N of outline …`) waren intermittierend
  wirkungslos. `cliclick c:x,y` mit aus `position`/`size` der AX-Zeile berechneten
  Koordinaten (Bildschirm-Pixel durch 2 für Punkt-Koordinaten) war zuverlässig.
- Bei jedem Fund: **zuerst reproduzieren, dann fixen, dann gegen den echten Dialog
  (nicht nur einen isolierten Probe) verifizieren** — §60.4 zeigt, dass ein Fix, der
  im isolierten Probe funktioniert, im echten Dialog trotzdem unvollständig sein
  kann.

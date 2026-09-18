# Report — macOS, 2026-09-18 (6/7): „8 statt 9 Menüs" gefixt, Tools-Listbox-Klick aufgelöst

**Kontext:** Fortsetzung der macOS-Session-Reihe. Auftrag: zwei seit Längerem
offene Backlog-Punkte bearbeiten (`docs/2026-09-13_report-macos.md` §29/§29.2):

1. Menüleiste zeigt manchmal 8 statt 9 Einträge (`Windows`-Menü fehlt).
2. Preferences → Tools-Listbox-Klick — automatisierungsbedingt nicht
   abschließend verifizierbar in einer früheren Session.

Beide zuerst auf aktuellem HEAD (nach §47 Menüband-Kollaps-Fix und §50
Printer-Dialog-Crash-Fix) neu gemessen, statt blind auf den alten Befund
aufgesetzt — Advisor-Empfehlung, die sich in beiden Fällen ausgezahlt hat.

## 1. „8 statt 9 Menüs"

### Re-Messung

3/3 kalte `PLT_QT=1 racket -l drracket`-Starts, Menüband per `osascript`
(`name of every menu bar item of menu bar 1`) ausgelesen:

```
Apple, racket, File, Edit, View, Language, Racket, Insert, Scripts, Help
```

Konsistent 9 Einträge (8 App-Menüs + Apple), `Windows` fehlt in allen drei
Läufen. Nativer Kontrolllauf (identische Methodik, kein `PLT_QT`):

```
Apple, racket, File, Edit, View, Language, Racket, Insert, Scripts, Windows, Help
```

10 Einträge inkl. `Windows`. Echte, reproduzierbare Qt-spezifische Divergenz
auf aktuellem HEAD — nicht verschwunden, wie es bei mehreren anderen
Backlog-Punkten dieser Session-Reihe der Fall war (§33.7-Nachtrag, §48).

### Root-Cause-Suche

Erste Hypothese (aus der Erinnerung/Memory-Datei `project_macos_menu_bug.md`):
Verbindung zu `wx/cocoa/queue.rkt`s `setWindowsMenu:`/`addWindowsItem:` (Cocoas
automatisches Fenstermenü). Per Grep widerlegt: dieser Code-Pfad existiert nur
in `wx/cocoa/`, betrifft `wx/qt` nicht.

Tatsächliche Quelle gefunden über `drracket-core-lib/drracket/private/
main.rkt`s `group:add-to-windows-menu` → `framework/private/group.rkt`:

- `windows-menu-label` ist auf macOS der lokalisierte String „Windows"
  (`group.rkt:42-45`) — das plattformübergreifende „Tabs"-Konzept trägt auf
  macOS diesen Namen, per Konvention (bestätigt durch `CLAUDE.md`s eigene
  Notiz zu §45.3: „Windows-Menü (macOS-Äquivalent zu 'Tabs')").
- `create-windows-menu` (`group.rkt:293-297`) erzeugt das Menü **unbedingt**
  bei jedem `frame:basic-mixin`-Frame (`framework/private/frame.rkt:242`),
  **ohne** Plattform-Gate — aber mit `demand-callback`, der die eigentlichen
  Einträge erst beim Öffnen nachträgt (`update-windows-menu`,
  `group.rkt:91-150`). Bis dahin ist das Menü **null Items groß**.

Isolierte Probe (`/tmp/menu-empty-probe.rkt`, nicht Teil des Repos):
`menu-bar%` mit zwei Top-Level-Menüs, eines mit einem echten Item, eines
komplett leer nur mit `demand-callback`. Ergebnis unter Qt/macOS:

```
Apple, racket, First
```

Das leere Menü taucht in der Menüband-Enumeration **gar nicht auf** — win32/
gtk/cocoa haben dieses Problem nicht (dort rendert ein leeres Top-Level-Menü
normal). Root Cause: Qt's native macOS-Menüband-Sync (`QCocoaMenuBar`)
überspringt beim Aufbau der `NSMenu`-Struktur jedes `QMenu` mit null
`QAction`s. Ohne Menüband-Slot kann der Nutzer das Menü nie anklicken, also
feuert `about-to-show-cb` (§37, `QMenu::aboutToShow`) nie, also bleibt es für
immer leer und unsichtbar — ein struktureller Deadlock, keine reine
Zufälligkeit.

### Fix

`wx/qt/menu.rkt` (gui-Submodul, `qt-backend`) — **keine Shim-ABI-Änderung**,
alle drei benötigten Exporte (`shim_action_create`, `shim_action_set_enabled`,
`shim_menu_remove_action`) existierten bereits:

- Jedes `menu%` hält ein `placeholder-action`-Feld. `ensure-placeholder!`
  legt bei Bedarf eine deaktivierte, blanke `QAction` an
  (`shim_action_create qt-menu "" 0 #f #f` + `shim_action_set_enabled ... 0`).
  `drop-placeholder!` entfernt sie wieder.
- Aufgerufen: `ensure-placeholder!` bei Konstruktion sowie immer, wenn
  `delete`/`delete-by-position` die Item-Liste auf `null` bringt.
  `drop-placeholder!` bei jedem `append`/`append-separator` (dem ersten
  echten Item).
- Bewusst außerhalb von `item-table`/`items-in-order` geführt, damit
  `number`/`delete-by-position` unverändert nur den logischen (wx-seitigen)
  Item-Bestand zählen — der Platzhalter ist reine Qt-interne Buchführung.

**Ein erster Versuch mit einem Separator als Platzhalter (`shim_menu_add_
separator`) scheiterte** — gemessen an derselben isolierten Probe: Qt
ignoriert Separatoren bei der Leerheits-Prüfung fürs Menüband-Sync, ein
nur-Separator-Menü bleibt trotzdem unsichtbar. Erst eine echte (wenn auch
blanke, deaktivierte) `QAction` zählt. Ohne diese Vor-Messung wäre der Fix
scheinbar korrekt, aber wirkungslos gewesen.

### Verifikation

- 3/3 kalte Qt-Starts nach dem Fix: **10 Einträge inkl. `Windows`**,
  identisch zum nativen Kontrolllauf.
- Nativer Kontrolllauf erneut gegengeprüft (die Codeänderung betrifft nur
  `wx/qt/`, kann `wx/cocoa/` nicht berühren): weiterhin 10/10, keine
  Regression. (Ein einzelner scheinbar abweichender 4-Menü-Treffer war ein
  reines Timing-Artefakt — Frame noch nicht vollständig aufgebaut bei zu
  kurzer Wartezeit vor der `osascript`-Abfrage; mit längerer Wartezeit
  reproduzierbar 10/10.)
- **Echter Klick** (`cliclick`, Koordinaten aus `AXPosition`/`AXSize` des
  Menüband-Eintrags — `osascript "click menu item ... of menu bar"` hing
  bei diesem speziellen Menü wiederholt und wurde deshalb nicht verwendet)
  öffnet das `Windows`-Menü mit vollem, korrektem Inhalt: `Minimize`,
  `Zoom`, `Bring Frame to Front…`, `Most Recent Window`, `Previous Tab`,
  `Next Tab`, `Move Tab Left/Right`, `Tab 1`–`9`, `Untitled` — das
  Akzeptanzkriterium ist nicht nur „Menüband-Slot vorhanden", sondern
  „Menü ist tatsächlich benutzbar".
- Smoke 3/3 beide Wege (`PLT_QT=1`/nativ).

**Nur auf macOS relevant** — kein Rebuild auf Windows/Linux nötig (keine
Shim-ABI-Änderung).

## 2. Tools-Listbox-Klick

### Isolierte Probe

Neue, minimale `list-box%`-Probe (5 Einträge, Callback loggt Auswahl-Index/
-String) — Lehre aus `docs/HACKING.md` §21.10 beachtet: ein bares
`racket/gui`-Skript ist selbst der Eventspace-Handler-Thread, `(sleep n)`
dispatcht keine Callbacks; `sleep/yield` verwendet (Muster aus
`examples/pump-gate.rkt`).

§29 hatte drei `osascript`/AX-Strategien probiert und verworfen (`click row
N`, `click at {x,y}`, `AXPress`). Diesmal `cliclick` (echtes `CGEvent`, kein
AppleEvent) mit vorherigem `set frontmost of process "racket" to true` — die
Kombination, die §45.1 für einen ähnlich gelagerten Automatisierungsbefund bei
einem Button aufgelöst hatte, hier erstmals auf `list-box%` angewendet.
Klick-Koordinaten aus dem Widget selbst (`send lb client->screen x y`), nicht
aus einem Screenshot geschätzt (§21.10/§34.7-Lehre).

**Ergebnis: 2/2 Klicks lösen die Selektion korrekt aus** — Callback feuert mit
korrektem `(index . string)`-Paar, per Screenshot zusätzlich als blaue
Zeilen-Hervorhebung visuell bestätigt.

### Akzeptanztest in echtem DrRacket

Preferences (über Edit-Menü, §22-Fix) → Tab „Tools" → Klick auf
„Optimization Coach (loaded)": Zeile wird blau selektiert, **`Tool:`-Feld
aktualisiert sich live** zu `(lib "optimization-coach/tool.rkt")` —
identisch zum ursprünglichen Windows/Linux-Akzeptanztest aus §25/§28.

### Verdikt

Kein Produktbefund. Die drei in §29 gescheiterten Automatisierungsstrategien
waren eine reine AppleScript/Accessibility-Grenze bei diesem einen
Widget-Typ (Ursache unbekannt, nicht weiter verfolgt — die eigentliche Frage
„funktioniert `list-box%`-Klick unter Qt auf macOS" ist jetzt eindeutig mit
Ja beantwortet). Keine Code-Änderung.

## Betriebsdisziplin

`org.racket-lang.prefs.rktd` vor der ersten und nach der letzten
Preferences-Interaktion per SHA-256 verglichen, exakt zurückgespielt
(`command cp -f`, kein `cp`-Alias). Alle Test-DrRacket-/Racket-Prozesse am
Ende beendet, keine Zombies. Temporäre Proben/Screenshots im Scratchpad bzw.
`/tmp` belassen bzw. gelöscht, nicht Teil des Commits.

## Ergebnis

- **Code-Änderung:** `wx/qt/menu.rkt` (gui-Submodul, `qt-backend`) — einzige
  Änderung dieser Session, keine Shim-ABI-Änderung.
- **Gate:** Smoke 3/3 beide Wege.
- **Zwei-Repo-Commit:** gui-Submodul committet + gepusht, danach
  Umbrella-Zeiger nachgezogen (Regel 8: Submodul-Commit war auf
  `origin/qt-backend`, bevor der Umbrella-Pointer-Commit entstand).

Details: `docs/HACKING.md` §51.

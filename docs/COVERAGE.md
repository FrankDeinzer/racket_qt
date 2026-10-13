# COVERAGE — Abdeckungsnachweis Widget-Klasse × Verhaltenskategorie (Linux/X11, Stand 2026-10-13)

Ergänzt die fünf statischen Audits (`tests/stub|style|api|init|callback-audit.rkt`, Blindstellen: HACKING §79.1/§80.1).
Diese sehen **Strukturen** (Methode fehlt, Flag nie gelesen, Callback nie ausgelöst), aber keine **Zustandsübergänge**
(Hide→Show→Reparent, Enable-Kaskade, GC nach Hide, Fokus-Wechsel ...). Dafür gibt es die Verhaltens-Matrix:
`examples/behavior-matrix-probe.rkt` (pro Sektion eine Klasse, Protokoll `<sektion> <schlüssel> => <wert>`) und
`tests/sweep/behavior-matrix.sh` (jede Sektion nativ/gtk und `PLT_QT=1` in je eigenem Prozess, diff; Exit 1 bei Abweichung).
Details und Befunde: HACKING §81.

## Legende

- **A** abgedeckt: ein Skript/eine Probe/ein § belegt die Zelle (Verweis in der Zelle). `BM:<sektion>` = `behavior-matrix-probe.rkt <sektion>`; `IC:<sektion>` = `tests/sweep/input-controls.sh <sektion>` (echte xdotool-Eingabe, `examples/input-matrix-probe.rkt`, §82); `DR:<szenario>` = `tests/sweep/dialog-runtime.sh <szenario>` (echte Dialoge, §83.1); `DND` = `tests/sweep/dnd-drop.sh` (echter Xdnd-Drop, §83.2); `DC` = `tests/sweep/display-changed.sh` (xrandr, §83.3).
- **T** teilweise abgedeckt (der Verweis nennt, was fehlt).
- **G** nicht abgedeckt.
- – n/a (die Kategorie gibt es für die Klasse nicht).
- „Abgedeckt“ heißt: Zustandsflags/Getter/Zähler stimmen mit gtk überein bzw. die Probe läuft ohne Absturz. **Nicht** bewiesen ist damit
  die optische Korrektheit (dafür Screenshot-Sweeps, `tests/sweep/sweep.sh`/`dr-dialogs.sh`) und nichts über Windows/macOS.
- Rohe Pixelwerte (`#px`-Schlüssel) werden nicht verglichen (Theme/Schrift); `#info`-Schlüssel sind WM-/Referenz-abhängig und nur Information.

## Matrix

| Klasse | Erzeugen/Anzeigen | Resize/Reflow | Hide/Show | Enable/Disable | Fokus | Tastatur/Maus | Modalität | Reparent/Delete-Child | set-label/-value | Zerstören/GC/Shutdown | Getter | Clipboard/Drop/Cursor |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| frame% | **A** smoke.rkt T1; BM:frame | **A** resize-reflow-probe §32, live-resize-probe, size-callback-probe §80; BM:frame, layout | **A** show-hide-probe, is-shown-probe §30; BM:frame | **A** enable-cascade-probe §26; BM:frame | **A** set-focus-probe §68, on-activate-probe §69, frame-activate-probe; BM:frame | **A** func-close.sh (on-close-Rückfrage), func-winpos.sh (on-move), tests/input-matrix.sh | **A** dialog-level-probe §61; BM:dialog (Owner) | – | **A** func-file.sh (Titel *), button-set-label; BM:frame (set-label, modified) | **A** crash-b-teardown-probe §39, func-close.sh; BM:frame, stress (GC-Fund §81.2), shutdown-dialog | **A** frame-position-probe §67; BM:frame (get-x/-y/-client-size) | **A** DND (echter Datei-Drop auf frame%, auch Rückfall von canvas%/message% ohne eigenes Drop-Ziel; Qt == gtk, §83.2); smoke.rkt T4; BM:frame (Cursor); `display-changed`: DC (§83.3) |
| dialog% | **A** dialog-widgets-probe, func-return.sh; BM:dialog | **T** Größen nur indirekt (dr-dialogs.sh); BM:dialog (get-width>0) | **A** BM:dialog (zweites Zeigen) | **T** BM:dialog (Owner-Flag während modal; is-enabled? = Eigenflag, s. §81.3) | **A** dialog-keys-probe §64, dialog-return-matrix.sh §73 | **A** dialog-keys-probe §64, dialog-return-matrix.sh §73, func-return.sh | **A** dialog-level-probe §61, §18.3; BM:dialog | – | **A** BM:dialog set-label | **A** BM:dialog (10 Dialoge nacheinander), stress, shutdown-dialog | **T** BM:dialog (is-shown?, get-width) | – |
| canvas% | **A** BM:canvas | **A** BM:canvas (min-size, Frame-Resize) | **A** BM:canvas (+Kaskade) | **A** BM:canvas (+Kaskade) | **A** BM:canvas; set-focus-probe §68 | **A** IC:canvas (Maus: Klick links/rechts/Mitte, Doppelklick, Ziehen, Rad, enter/leave; Tastatur: Zeichen, Pfeile, Sondertasten, Strg-/Alt-/Shift-Kombinationen, F-Tasten, on-focus; §82), tests/input-matrix.sh (16 Tasten-Zeilen Qt==gtk, §64), key-probe, func-bigbang.sh, scroll-probe §33 | – | **A** BM:canvas (reparent, delete-child, change-children) | **A** BM:canvas (Hintergrund, Label) | **A** BM:canvas, shutdown-*, stress, orphans | **A** BM:canvas, on-paint-Zähler, get-dc-Größe, Scrollbars | **T** BM:canvas (set-cursor); cursor-probe §40; Mausrad: scroll-probe; **A** DND (canvas% mit `accept-drop-files`: `on-drop-file` je Datei, §83.2) |
| editor-canvas% | **A** BM:editor-canvas | **A** BM:editor-canvas (min-size, Frame-Resize) | **A** BM:editor-canvas (+Kaskade) | **A** BM:editor-canvas (+Kaskade) | **A** BM:editor-canvas; func-*.sh (Editor) | **A** func-file.sh, func-find.sh, func-tab2lines.sh, input-matrix.sh | – | **A** BM:editor-canvas (reparent, delete-child, change-children) | **A** BM:editor-canvas (set-editor) | **A** BM:editor-canvas, shutdown-*, stress, orphans | **A** BM:editor-canvas, get-editor | – |
| panel% / vertical-/horizontal-panel% | **A** BM:panel / vertical-panel / horizontal-panel | **A** BM:layout (Resize, Hide, container-sequence); size-callback-probe §80; panel-sizing-probe §18.2 | **A** BM:panel / vertical-panel / horizontal-panel (+Kaskade) | **A** BM:panel / vertical-panel / horizontal-panel (+Kaskade) | – | – | – | **A** BM:panel / vertical-panel / horizontal-panel (reparent, delete-child, change-children) | **A** BM:panel (set-alignment, spacing, border) | **A** BM:panel / vertical-panel / horizontal-panel, shutdown-*, stress, orphans | **A** BM:panel / vertical-panel / horizontal-panel, get-alignment, get-client-size; BM:layout (Füllrelationen) | – |
| group-panel% | **A** BM:group-panel | **A** BM:group-panel (min-size, Frame-Resize) | **A** BM:group-panel (+Kaskade) | **A** BM:group-panel (+Kaskade) | – | – | – | **A** BM:group-panel (reparent, delete-child, change-children) | **A** BM:group-panel (set-label) | **A** BM:group-panel, shutdown-*, stress, orphans | **A** BM:group-panel, get-client-size; group-panel-probe §61.1 | – |
| tab-panel% | **A** BM:tab-panel | **A** BM:tab-panel (min-size, Frame-Resize) | **A** BM:tab-panel (+Kaskade) | **A** BM:tab-panel (+Kaskade) | **A** IC:tab-panel, IC:tab-order (Fokus nach Tab-Klick, Tab/Shift+Tab über Reiter und Kinder; §82) | **A** IC:tab-panel (Klick, Pfeiltasten auf der Leiste, Klick ins Kind; §82); **T** Klick auf [x]/Drag nur manuell (tab-close-reorder-probe §64.7) | – | **A** BM:tab-panel (reparent, delete-child, change-children) | **A** BM:tab-panel (set-selection, append, delete, set-item-label, Callback-Zähler) | **A** BM:tab-panel, shutdown-*, stress, orphans | **A** BM:tab-panel, get-item-label, get-client-size | – |
| button% | **A** BM:button | **A** BM:button (min-size, Frame-Resize) | **A** BM:button (+Kaskade) | **A** BM:button (+Kaskade) | **A** BM:button (focus, has-focus?, on-focus-Zähler) | **A** IC:button (xdotool: Klick, Leertaste, Return, Klick auf deaktiviert, Wegziehen, Rechtsklick, Tab/Shift+Tab; §82); enable-cascade-probe | – | **A** BM:button (reparent, delete-child, change-children) | **A** BM:button (set-label, Breite wächst); button-set-label-probe §60.3 | **A** BM:button, shutdown-*, stress, orphans | **A** BM:button, get-label | – |
| check-box% | **A** BM:check-box | **A** BM:check-box (min-size, Frame-Resize) | **A** BM:check-box (+Kaskade) | **A** BM:check-box (+Kaskade) | **A** BM:check-box (focus, has-focus?, on-focus-Zähler) | **A** IC:check-box (Klick, Leertaste, deaktiviert, Tab; §82) | – | **A** BM:check-box (reparent, delete-child, change-children) | **A** BM:check-box (set-value, set-label [Fund §81.1]) | **A** BM:check-box, shutdown-*, stress, orphans | **A** BM:check-box, get-value | – |
| choice% | **A** BM:choice | **A** BM:choice (min-size, Frame-Resize) | **A** BM:choice (+Kaskade) | **A** BM:choice (+Kaskade) | **A** BM:choice (focus, has-focus?, on-focus-Zähler) | **A** IC:choice (Tab-Fokus, Pfeiltasten geschlossen, Popup per Klick/Escape/Tasten/Klick auf Eintrag, alt+Down; §82) | – | **A** BM:choice (reparent, delete-child, change-children) | **A** BM:choice (append, delete, clear, set-string, set-selection) | **A** BM:choice, shutdown-*, stress, orphans | **A** BM:choice, get-number, get-string-selection | – |
| list-box% (einspaltig) | **A** BM:list-box, list-box-multi | **A** BM:list-box, list-box-multi (min-size, Frame-Resize) | **A** BM:list-box, list-box-multi (+Kaskade) | **A** BM:list-box, list-box-multi (+Kaskade) | **A** BM:list-box (focus, has-focus?, on-focus-Zähler) | **A** IC:list-single/-multiple/-extended (Klick, Strg-/Shift-Klick, Pfeile, Home/End, Shift+Pfeil, Doppelklick, Leertaste; §82; Abweichungen known, s. u.) | – | **A** BM:list-box, list-box-multi (reparent, delete-child, change-children) | **A** BM:list-box, list-box-multi (set-selection [Fund §81.1], select, delete, set, clear) | **A** BM:list-box, list-box-multi, shutdown-*, stress, orphans | **A** BM:list-box, list-box-multi, get-selections, get-first-visible-item | – |
| list-box% (mehrspaltig) | **A** BM:list-box-columns | **A** BM:list-box-columns (min-size, Frame-Resize) | **A** BM:list-box-columns (+Kaskade) | **A** BM:list-box-columns (+Kaskade) | **A** BM:list-box-columns (focus, has-focus?, on-focus-Zähler) | **A** IC:list-columns (Header-Klick je Spalte, Zeilenklick, Pfeil, Doppelklick; §82), func-pkg.sh/pkg-tabs.sh (Sortierung, §60.6) | – | **A** BM:list-box-columns (reparent, delete-child, change-children) | **A** BM:list-box-columns (set-string je Spalte, set-column-label/-size, append-/delete-column) | **A** BM:list-box-columns, shutdown-*, stress, orphans | **A** BM:list-box-columns, get-column-order/-size, get-column-labels | – |
| radio-box% | **A** BM:radio-box | **A** BM:radio-box (min-size, Frame-Resize) | **A** BM:radio-box (+Kaskade) | **A** BM:radio-box (+Kaskade) | **A** BM:radio-box (focus, has-focus?, on-focus-Zähler) | **A** IC:radio-box (Klick auf Item, Tab, Pfeile; §82, Pfeile known), dialog-radio-return-probe §73 | – | **A** BM:radio-box (reparent, delete-child, change-children) | **A** BM:radio-box (set-selection, enable n, show n, set-item-label) | **A** BM:radio-box, shutdown-*, stress, orphans | **A** BM:radio-box, get-item-label, is-enabled? n | – |
| slider% | **A** BM:slider | **A** BM:slider (min-size, Frame-Resize) | **A** BM:slider (+Kaskade) | **A** BM:slider (+Kaskade) | **A** BM:slider (focus, has-focus?, on-focus-Zähler) | **A** IC:slider (Tab-Fokus, Klick auf Schiene, Ziehen über beide Enden, Home/End/Pfeile/Bild; §82, Pfeile/Seite/Schienenklick known) | – | **A** BM:slider (reparent, delete-child, change-children) | **A** BM:slider (set-value inkl. Bereichsgrenzen) | **A** BM:slider, shutdown-*, stress, orphans | **A** BM:slider, get-value | – |
| gauge% | **A** BM:gauge | **A** BM:gauge (min-size, Frame-Resize) | **A** BM:gauge (+Kaskade) | **A** BM:gauge (+Kaskade) | – | – | – | **A** BM:gauge (reparent, delete-child, change-children) | **A** BM:gauge (set-value, set-range) | **A** BM:gauge, shutdown-*, stress, orphans | **A** BM:gauge, get-range; gauge-probe §41 | – |
| message% | **A** BM:message | **A** BM:message (min-size, Frame-Resize) | **A** BM:message (+Kaskade) | **A** BM:message (+Kaskade) | – | – | – | **A** BM:message (reparent, delete-child, change-children) | **A** BM:message (set-label, Breite, auto-resize, get-color); message-color-probe §67 | **A** BM:message, shutdown-*, stress, orphans | **A** BM:message | – |
| text-field% | **A** BM:text-field, text-field-multi | **A** BM:text-field, text-field-multi (min-size, Frame-Resize) | **A** BM:text-field, text-field-multi (+Kaskade) | **A** BM:text-field, text-field-multi (+Kaskade) | **A** BM:text-field (focus, has-focus?, on-focus-Zähler) | **A** IC:text-field (Tab-Fokus, Tippen, Backspace, Return = text-field-enter, Strg+A, Tab/Shift+Tab, mehrzeilig; §82), func-find.sh, input-matrix.sh | – | **A** BM:text-field, text-field-multi (reparent, delete-child, change-children) | **A** BM:text-field (set-value, Editor-insert, set-label) | **A** BM:text-field, text-field-multi, shutdown-*, stress, orphans | **A** BM:text-field, text-field-multi, get-value, get-editor | – |
| combo-field% | **A** BM:combo-field | **A** BM:combo-field (min-size, Frame-Resize) | **A** BM:combo-field (+Kaskade) | **A** BM:combo-field (+Kaskade) | **A** BM:combo-field (focus, has-focus?, on-focus-Zähler) | **A** IC:combo-field (Tab-Fokus [Fund §82], Tippen, Backspace, Return, Pfeil-Popup per Klick/Escape/Tasten; §82) | – | **A** BM:combo-field (reparent, delete-child, change-children) | **A** BM:combo-field (append, set-value) | **A** BM:combo-field, shutdown-*, stress, orphans | **A** BM:combo-field, get-number | – |
| menu-bar% | **A** menu-click-probe §14, BM:menu | **T** menubar-resize-probe §80 | **A** BM:menu (delete/restore) | **A** BM:menu (enable/disable der Leiste) | – | **A** IC:menu (Titel-Klick, Item-Klick, Check-Item, deaktiviertes Item, Accelerator Strg+A und Strg+Shift+D [Fund §82], alt+F-Mnemonic, Escape, Außenklick; §82), menu-click-probe §14/§15, func-ctxmenu.sh | – | – | **A** BM:menu (Label der Menüs) | **A** BM:menu, shutdown-menu-bar | **A** BM:menu (get-items, get-frame) | – |
| menu% / menu-item% | **A** BM:menu | – | **A** BM:menu (delete, restore) | **A** BM:menu (Item/Menü enable; Kaskade: Eigenflag) | – | **A** menu-demand-probe §37, func-ctxmenu.sh; BM:menu (command, check, checkable) | – | **A** BM:menu (delete/restore, Submenü) | **A** BM:menu (set-label, check, enable) | **A** BM:menu, shutdown-menu-bar | **A** BM:menu (get-label, get-items, is-checked?, get-shortcut) | – |
| popup-menu% | **A** BM:popup-menu; func-ctxmenu.sh §59 | – | – | **A** BM:popup-menu (Item enable) | – | **A** IC:popup (Rechtsklick; Auswahl per Tasten und per Klick, Abbruch per Escape und Außenklick, Check-Item; §82), popup-submenu-probe §64 | – | – | – | **A** BM:popup-menu (GC mit offenem Popup), §59.1 | **A** BM:popup-menu (get-items, get-title) | – |
| clipboard | **A** BM:clipboard | – | – | – | – | – | – | – | **A** BM:clipboard (Roundtrip, Client, Bitmap; clipboard-probe §36) | – | **A** BM:clipboard (get-clipboard-string/-data) [Fund §81.1] | **A** BM:clipboard (Text, Client, X-Selection, Bitmap); Cross-Toolkit §36/§55 |
| file-/message-box-Dialoge | **A** DR (message-box 7 Stile + message-box/custom 2, get-text/-choices-from-user, get-color-from-user, get-font-from-user, get-file ×3, put-file ×3, get-directory ×2, get-file-list ×1: Titel, Buttonreihenfolge, Icon-Symbol, Rückgabewert; Qt == gtk bis auf `mb-yes-no`-Anfangsfokus/`color`-Optik, §83.1); file-dialog-probe §19; func-saveas.sh | – | – | – | **A** DR (Fokus des Hauptfensters vor/nach jedem Dialog = Canvas in allen 50 Läufen beider Modi; `get-focus-window` des Dialogs nach §83.1-Fix gleich; Qt-Dateidialog: Tippen ohne Klick landet im Namensfeld) | **A** DR (Enter, Escape, Tippen, Klick auf Dialog-Buttons, Leertaste auf dem Fokus-Button), func-saveas.sh, func-close.sh | **A** DR `modal` (echter Klick auf das Hauptfenster-Knopf bei offenem message-box und Dateidialog: 0 Klicks, Sanity-Klick ohne Dialog = 1; §83.1), §19, §18.3 | – | – | **A** crash-b-teardown-probe §39 | – | – |
| printer-dc% | **A** printer-probe §43; BM:printer-dc (PDF-Pfad, Klasse) | – | – | – | – | – | **T** printer-dialog-probe (§54.4, per Hand beobachtet; nicht automatisiert) | – | – | **T** §49.4/§50 (Teardown) | – | – |
| cursor | **A** BM:cursor (11 Standard-IDs, ok?) | – | – | – | – | – | – | – | **A** BM:cursor (set-cursor/get-cursor, Bitmap-Cursor) | **A** BM:cursor | **A** BM:cursor (get-cursor, is-busy?) | **T** cursor-probe §40 (Form fotografisch nicht prüfbar, §52.2) |
| timer / queue | **A** smoke.rkt T2; BM:timer | – | – | – | – | – | – | – | **A** BM:timer (start/stop/Intervall) | **A** BM:timer (GC lebender Timer), shutdown-timer | **A** BM:timer (interval, One-Shot-Zähler, queue-callback-Reihenfolge) | – |


## Was die Verhaltens-Matrix je Sektion prüft

Generische Batterie (button, check-box, choice, list-box, list-box-multi, list-box-columns, radio-box, slider, gauge, message, text-field,
text-field-multi, combo-field, canvas, editor-canvas, panel, vertical-/horizontal-panel, group-panel, tab-panel; je ~45 Schlüssel):
Erzeugen (Eltern, is-shown?/is-enabled?, Größe>0, Position), `show #f/#t` (Nachbar rückt nach), Hide-Kaskade über den Container,
`enable #f/#t` und Container-Kaskade, `min-width/-height` → Getter, Frame-Resize, `reparent`, `delete-child`/`add-child`/`change-children`,
Fokus (`focus`, `has-focus?`, `get-focus-window`, `on-focus`-Zähler rein/raus; WM-Aktivierung wird abgewartet), Frame-Zerstören + GC.
Dazu je Klasse die set-label/-value-Operationen (siehe Zellen). Weitere Sektionen: `frame`, `dialog` (modal per Timer geschlossen),
`menu`, `popup-menu`, `clipboard`, `cursor`, `timer`, `printer-dc`, `layout` (Füllrelationen nach Resize/Hide/container-sequence),
`tab-order` (programmatisches `on-traverse-char`), `stress` (60 Kinder, 25 Frames mit GC, 10 Dialoge), `orphans` (entfernte Kinder + GC + Resize),
`shutdown-<klasse>` (18×: eigener Eventspace unter Custodian, `custodian-shutdown-all`, GC, Hauptfenster danach benutzbar).

## Bekannte Abweichungen (begründet; `tests/sweep/behavior-matrix-known.txt` bzw. `#info`)

- `radio-box` `focus:moved-to-pre` (gtk: `#f`, Qt: `#t`): gtk bewegt den Fokus von einem beschrifteten radio-box% per `(send pre focus)` nicht weg
  (gleiche gtk-Eigenart wie in `examples/set-focus-probe.rkt` beschrieben); Qt verhält sich korrekt. Kein Qt-Befund.
- `frame` `focus:button`/`activate:frame-active?` (`#info`): hängt vom WM ab (nach iconify/maximize/fullscreen aktiviert KWin das gtk-Fenster nicht
  zuverlässig wieder). `on-activate` selbst wird in beiden Modi ausgelöst (`activate:on-activate>=1` verglichen).
- `clipboard` `x-sel-roundtrip` (`#info`): gtk liefert für die X-Selection nach `set-clipboard-string` `""` (asynchrone Eigentümerschaft), Qt den Text.
- `canvas` `scrollbars:init/scroll/hide` (`#info`): gtk wirft `GtkWidget->C: argument is not non-null` für `init-auto-scrollbars`/`scroll`, wenn der Canvas vorher
  reparentet/aus dem Panel genommen wurde; Qt arbeitet. Kein Qt-Befund.
- `is-enabled?` ist in beiden Backends das **Eigenflag** (Kaskade wirkt nur in der Interaktion, nicht im Getter); wird so verglichen.
- Einmal in der ersten Gesamtläufe beobachtet (`canvas` focus: Qt `#f`, 0/4 Wiederholungen danach): **Messartefakt** der WM-Aktivierung (Fenster noch nicht aktiv);
  die Probe wartet seither bis zu 2 s auf `get-top-level-focus-window`.

## Bekannte Abweichungen der Eingabe-Matrix (`tests/sweep/input-controls-known.txt`, §82)

gtk-Eigenarten des Racket-Backends bzw. Toolkit-Unterschiede, kein Qt-Befund: Anfangsfokus (gtk keiner, Qt erstes Steuerelement); `radio-box%`/`slider%`: gtk-Racket nimmt Pfeiltasten
(und Bild↑/↓) für die Fokus-Traversierung, Qt ändert Auswahl/Wert (nativ wie win32); Schienenklick am Slider (gtk +1, Qt Seitenschritt +10); `choice%`-Popup (gtk meldet beim Tastendurchlauf
jeden Zwischeneintrag); `list-box%` Leertaste (gtk `'list-box-dclick`, Qt nichts), `'extended` (win32-Semantik Klick schaltet um, gtk kennt den Modus nicht); `combo-field%`-Popup-Geometrie
(gtk legt die Liste über das Feld, Qt darunter: Hover/Klickposition verschieden); Tab-Panel Strg+Bild↑/↓ (gtk-Notebook); Strg+Alt+X (gtk-Fokus-Blip).

## Nicht abgedeckt / Restliste (ehrlich)

- **Echte Eingabe an Steuerelemente**: seit §82 mit `tests/sweep/input-controls.sh` abgedeckt (16 Sektionen, 194 Schritte, 167 identisch Qt == gtk, 27 als
  begründete Abweichung in `tests/sweep/input-controls-known.txt`). Weiterhin nicht automatisiert: Klick auf [x]/Drag-Umsortieren der Tabs (§64.7), Ziehen der
  Slider-Mitte (nur die Enden), Popup-Submenüs per Maus, `Ctrl+Bild↑/↓` am Tab-Panel (gtk-Notebook-Eigenart, Qt nicht), Hover-Bewegung ohne Ziehen im Canvas (nicht protokolliert).
- **Datei-Drop**: echter Xdnd-Drop seit §83.2 abgedeckt (`tests/sweep/dnd-drop.sh`, Quelle `tests/sweep/dnd-source.py` = GTK3-Fenster, `text/uri-list`). Nicht abgedeckt: Quelle ist GTK, nicht Dolphin
  (manueller Prüfpunkt, §83.2), Drop mehrerer Verzeichnisse/nicht-lokaler URLs, `dialog%` als Drop-Ziel, Drop unter Wayland.
- **`display-changed`**: seit §83.3 per xrandr-Moduswechsel am einzigen (virtuellen) Ausgang geprüft (`tests/sweep/display-changed.sh`). Nicht abgedeckt: Hinzufügen/Entfernen eines Monitors
  (`screenAdded`/`screenRemoved`, Hardware nötig), Änderungen der Verfügbaren Fläche (Panel; bewusst nicht verdrahtet), DPI-Wechsel.
- **Dialoge**: `get-color-from-user` verwendet unter Qt den portablen Racket-Dialog (RGB-Regler), keinen nativen `QColorDialog` (Verhalten Rückgabewert geprüft, Optik/Bedienung nicht gegen gtk gleich);
  `put-file` mit Überschreib-Rückfrage (Datei existiert) nicht automatisiert (zweites Fenster; Qt nutzt die eigene Rückfrage, gtk `do_overwrite_confirmation`); Mehrfachauswahl per Maus
  im `get-file-list` (nur Tippen eines Pfads); Dateidialog-Filterwechsel per Maus; `message-box` mit `#:dialog-mixin`; `get-font-from-user` mit echter Schriftauswahl (OK bleibt ohne Auswahl deaktiviert, nur Abbruch geprüft). Keine Prüfung unter Windows/macOS.
- **Optik**: seit §84 je Klasse durch die Optik-Matrix belegt (Abschnitt unten); Pixel/Farben/Rundungen/Theme werden bewusst nicht bewertet, Labels innerhalb von Items nur im Bild.
- **Wayland** (§77), **Windows**, **macOS**: die BM-Probe läuft plattformunabhängig (`racket examples/behavior-matrix-probe.rkt <sektion>` mit/ohne `PLT_QT=1`),
  der gtk-Vergleichsskript `behavior-matrix.sh` aber nur auf Linux/X11. Auf Windows/macOS Vergleichsbasis = nativer Lauf derselben Maschine, per Hand diffen.
- **GC-Sicherheit für Nicht-Frames**: abgesichert nur die Szenarien in `orphans`/`stress` (entfernte Kinder in lebendem Frame). Ein sichtbares Fenster, das unreferenziert bleibt,
  wird von `register-frame-shown` gehalten; der 64er-Ring (§81.2) deckt Ereignisse kurz nach dem Verstecken ab, ist aber keine Zerstörung des nativen Fensters (Leck bleibt).
- Tiefe: Die Probe vergleicht Zustandswerte, nicht jedes Zwischenereignis (z. B. exakte Reihenfolge von `on-size`/`on-move` über mehrere Container-Ebenen).


## Optik (OP) — `tests/sweep/visual-matrix.sh` (HACKING §84, Linux/X11)

Geometrie nativ (gtk) gegen `PLT_QT=1` je Szene aus `examples/visual-matrix-probe.rkt` (Fenstergröße, Kind-Bounding-Box, Größen je Achse, Clipping, Überlappung, Ausrichtung, Abstände, Minimum-Unterschreitung) plus Seite-an-Seite-Bild. Stand: 26 Szenen, 4 `ok`, 22 `theme`, 0 Bug-Kandidaten (2 Läufe); Begründungen: `tests/sweep/visual-matrix-known.txt`.

| Klasse | OP | Beleg / Befund |
|---|---|---|
| button% | **A** | Szene `button`: Höhe 25 vs 33 (theme), Breiten ±10 %, Bitmap-/Icon-Label, deaktiviert, langes Label (kein Clipping) |
| check-box% | **A** | `check-box`: Geometrie gleich |
| radio-box% | **A** | `radio-box`: Befund gefixt (Label berührte Indikator, Shim-Rand); Einzelzeile 30 vs 23 (theme) |
| choice% | **A** | `choice`: Höhe theme |
| slider% | **A** | `slider`: Befund gefixt (`'plain` überdeckte Label); Spurdicke theme |
| gauge% | **A** | `gauge`: Dicke 25 vs 6 (theme) |
| message% | **A** | `message`: Geometrie gleich, Icons/Farbe/Bitmap/fett sichtbar |
| text-field% | **A** | `text-field`: single/multi/Passwort/hscroll/deaktiviert; Zeilenhöhe 21 vs 25 (theme) |
| combo-field% | **A** | `combo-field`: 113×21 vs 133×33 (theme) |
| list-box% | **T** | `list-box`: Sizehint-Deckel 180/6 Zeilen vs gtk 72×41 (bewusst, §60.4/§71f); Header/Spalten sichtbar |
| tab-panel% | **T** | `tab-panel`: `'can-close` [x], Reorder; Backlog: Minimum ohne Reiterbreite |
| group-panel% | **A** | `group-panel`: Labels in beiden Modi gleich abgeschnitten |
| panel% `'border` | **A** | `panel-border` |
| canvas% / editor-canvas% | **A** | `canvas`: `'border`/`'control-border`/`vscroll`/`hscroll`; Scrollbalken immer sichtbar (theme) |
| vertical-/horizontal-panel% | **A** | `layout-align`, `layout-spacing` (Abstände gleich), `layout-stretch` |
| frame% | **T** | `frame-plain/-explicit/-nocaption/-menubar`; Backlog: Menüleistenbreite im Natürlichmaß |
| dialog% | **A** | `dialog`: Höhe 75 vs 89 (theme) |
| menu-bar% / popup-menu% | **T** | `menubar-open`, `popup-menu`: geöffnetes Menü im Bild (Einträge, Häkchen, Submenü); Stil Fusion statt Breeze |
| Fonts | **A** | `fonts`: Familien-Befund gefixt (`'modern` war proportional); Größen ±1 Schriftstufe |
| HiDPI | **G** | nicht geprüft (Probe skalierungsneutral) |

Restliste Optik: Wayland, Windows, macOS, HiDPI ungeprüft; Labels in Items nur visuell; Slider-/Gauge-/Tab-Panel-Schrift (`font`) nicht gesetzt (§74.1); Farben/Rundungen bewusst nicht bewertet; Backlog `tab-panel%`-Minimum, `frame%`-Menüleistenbreite, `list-box%`-`min-height` unter Deckel.

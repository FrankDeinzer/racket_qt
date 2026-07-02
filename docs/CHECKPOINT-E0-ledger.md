# Checkpoint E-0 Ledger — DrRacket Start-Entdeckung

Startdatum: 2026-06-30  
Platform: Windows x64, Racket v9.2 [cs], Qt 6.11.0

---

## Phase A — Windows Re-Smoke auf 9.2 ✅

**Aktion:** Bytecode-Neucompile (`.zo` für 8.18 → 9.2)  
**Methode:** Alle `.zo` in `third_party/gui` + `third_party/draw` gelöscht, `raco test` lässt Racket 9.2 neu kompilieren.  
**Ergebnis:** 3/3 Smoke-Tests pass. Exit-Code 0.  
**Nebeneffekte:** DPI-Awareness-Warnung (harmlos, kein Admin-Token). QThreadStorage-Cleanup beim Exit (normales Qt-Verhalten).

---

## Phase B — E-0 Crash-Schleife

### Crash 1 — `dialog%: not implemented in Qt spike`

| Feld | Wert |
|---|---|
| Fehlermeldung | `dialog%: not implemented in Qt spike` |
| Klasse | `dialog%` (Stub in `platform.rkt`) |
| Datei:Methode | `wx/qt/platform.rkt:74` (make-stub-class) |
| Aufrufkette | `mrtop.rkt:276` → `make-object wx-dialog%` → `wx:dialog%` (unsere platform-class) |
| Klassifikation | **mechanisch** — reines gtk-Spiegeln, keine Architekturentscheidung |
| Designentscheidung | Modalität via Racket-`yield` auf Semaphor (wie `common/dialog.rkt`). KEIN `QDialog::exec()`, KEIN geschachteltes QEventLoop. Invariante gewahrt. |

**Aktion:**
- `window.rkt`: `(define/public (get-dialog-level) 0)` hinzugefügt — braucht `dialog-mixin`'s `(define/override (get-dialog-level) ...)`
- `frame.rkt`: Stub `(define (other-modal? win) #f)` entfernt → benutzt echte Version aus `common/queue.rkt`. `(define/override (get-dialog-level) 0)` hinzugefügt.
- `wx/qt/dialog.rkt` neu: `(dialog-mixin frame%)` — korrekte semaphor-basierte Modalität
- `platform.rkt`: Stub-Klasse `dialog%` durch echten Import ersetzt

**Flag:** ⚑ GELADEN — dialog% wurde als Erst-Wurf implementiert. Modal-Verhalten (yield-Block) ist korrekt, aber noch nicht battle-tested: close-cb nutzt lokal-stubbed `other-modal?` war Problem, jetzt behoben. Zu beobachten: ob DrRacket Dialoge wirklich korrekt modal zeigt.

---

---

### Crash 2 — `gauge%: not implemented in Qt spike` ✅

| Feld | Wert |
|---|---|
| Fehlermeldung | `gauge%: not implemented in Qt spike` |
| Klasse | `gauge%` (Stub in `platform.rkt`) |
| Datei:Methode | `platform.rkt:make-stub-class`, aufgerufen aus Splash-Screen |
| Aufrufkette | DrRacket-Splash → `wxlitem.rkt:338` → `make-object wx-gauge%` |
| Klassifikation | **mechanisch** — optionaler Fortschrittsbalken, rein visuell |
| Aktion | `gauge%` zu Silent-Stub (non-error) gemacht: `set-gauge-value`/`get-gauge-value` als no-op definiert. Kein Qt-Widget nötig. |

---

### STOPP: Linklet-Mismatch `framework/splash.rkt` — strukturelles Problem

| Feld | Wert |
|---|---|
| Fehlermeldung | `instantiate-linklet: mismatch; reference to a variable that is not exported; name: id-extra-neg-party-argument-fn39.1` |
| Ursache | Unser Fork = gui-lib **1.78**; System Racket 9.2 nutzt gui-lib **1.80** (442 Dateien unterscheiden sich). `drracket-core-lib` wurde gegen die System-Version kompiliert; `-S third_party/gui/gui-lib` substituiert unsere ältere Version. |
| Klassifikation | **nicht ohne Entscheidung passierbar** |
| Optionen | (A) Fork auf 1.80 rebasen (clean, dauert); (B) Fork als User-Paket installieren + `raco setup drracket` (invasiver aber schnell); (C) Fallback: mini Framework-App |
| Entscheidung | **FALLBACK** gemäß Prompt: `examples/menu-frame.rkt` mit `frame% + menu-bar% + editor-canvas%` zum Entdecken der fehlenden Widgets. DrRacket-Direktstart nach Paket-Fix (Option B oder A) im nächsten Prompt. |

**Flag:** ⚑ ARCHITEKTONISCH GELADEN — DrRacket-Invocation-Rezept muss angepasst werden. Korrekte Methode: Fork als User-Paket installieren oder Fork auf gui-lib 1.80 rebasen, dann `raco setup drracket`, dann `PLT_QT=1 drracket` normal starten (ohne `-S`-Flags).

---

## Fallback: Minimale Framework-App

Ziel: `frame% + menu-bar% + menu% + menu-item% + editor-canvas%` zeigen, Crashes entdecken, Widgets implementieren.

### Crash 3 — `menu-bar%: not implemented in Qt spike` ✅

| Feld | Wert |
|---|---|
| Fehlermeldung | `menu-bar%: not implemented in Qt spike` |
| Klasse | `menu-bar%` / `menu%` / `menu-item%` (alle Stubs) |
| Datei:Methode | `platform.rkt:make-stub-class` |
| Aufrufkette | `examples/menu-frame.rkt` → `(new menu-bar% ...)` |
| Klassifikation | **mechanisch** — Qt-native Menu-Implementierung |

**Aktion — vollständige Menu-Implementierung:**
- `qt-shim/src/shim.cpp`: QMenuBar, QMenu, QAction mit C++ Functions (`shim_menubar_*`, `shim_menu_*`, `shim_action_*`)
- `utils.rkt`: FFI-Bindings für alle 15 neuen Shim-Funktionen
- `wx/qt/menu-item.rkt` (neu): Identity-Token-Klasse; `(id)` gibt `this` zurück → Glue-Objekt, das `get-mred` kennt
- `wx/qt/menu.rkt` (neu): `menu%` mit QMenu-Handle; `items-in-order` für positionelles Löschen; Action-Callbacks posten via `queue-event` → `on-menu-command`; `define/override (enable ...)` weil `window%` schon 1-Arg `enable` hat; `list-append`-Alias nötig weil `define/public (append ...)` Racket-`append` shadowed
- `wx/qt/menu-bar.rkt` (neu): `menu-bar%` mit QMenuBar-Handle; `set-frame`/`get-top-window` für Frame-Referenz; `register-menu-bar-predicate!` für menu.rkt ohne circular require
- `frame.rkt`: `(define/override (set-menu-bar mb) ...)` → `shim_window_set_menubar` + `(send mb set-frame this)`
- `platform.rkt`: Stubs entfernt, echte Klassen importiert; `id-to-menu-item` implementiert (nutzt `this`-Semantik von `(id)`)

**Ergebnis:** `examples/menu-frame.rkt` läuft mit Exit 0. Smoke 3/3 ✅.

---

## Phase 1+2 (2026-07-02) — gui-lib-Angleich 1.78 → 1.80, DrRacket-Link

Vorbedingung für die echte Entdeckung: der Fork war noch gui-lib 1.78, System (Racket 9.2) nutzt 1.80 → Linklet-Mismatch blockierte DrRacket strukturell (siehe STOPP oben). Details siehe `git log` im gui-Submodul; Kurzfassung:

- Merge `qt-backend` ← Upstream-Commit `3f0037c0` (exakter Quell-Commit von System-gui-lib 1.80, hash-verifiziert über `package-original-source` in der installierten `info.rkt`). Konfliktfrei, 86 Dateien, keine `wx/qt/**`-Datei betroffen.
- `gui-lib` als Installation-scope **Link** auf `third_party/gui/gui-lib` gesetzt (`raco pkg update --link`, elevated), `raco setup` neu kompiliert.
- **Gate-Test bestanden:** DrRacket **ohne** `PLT_QT` startet nativ ohne Linklet-Mismatch — Angleich sitzt strukturell.
- Beide Repos gepusht (gui `qt-backend` → `2d6325d9`, Umbrella `main` → `0b9f287`).

---

## Phase 3 (2026-07-02) — Echte DrRacket-Entdeckung mit `PLT_QT=1`

Testharness: `PLT_QT=1 drracket` direkt (kein `-S`, da jetzt verlinkt). Reihenfolge unten = Reihenfolge der Crashes.

### Crash 4 — `define-values` Arity-Mismatch (71 erwartet, 70 erhalten) ✅

| Feld | Wert |
|---|---|
| Fehlermeldung | `define-values: result arity mismatch; expected: 71 received: 70` |
| Ursache | Merge brachte ein neues Backend-Export-Ziel: `tab-panel-available?` in `wx/platform.rkt`s `define-values`-Liste (9.2-Neuerung ggü. 1.78) |
| Klassifikation | **Versions-Stub** (9.2-Eigenheit, mechanisch — win32/gtk geben beide einfach `#t` zurück) |
| Aktion | `qt/platform.rkt`: `(define (tab-panel-available?) #t)` ergänzt + in `platform-values`-Tupel angehängt |

### Crash 5 — `gauge%`: `send: target is not an object; method: get-parent` ✅

| Feld | Wert |
|---|---|
| Aufrufkette | DrRacket-Splash → `wxlitem.rkt:338` → `make-object wx-gauge%` → `get-top-level` |
| Ursache | `qt/platform.rkt`s handgeschriebenes `gauge%` (nicht über `make-stub-class`) hardcodete `[parent #f]` — dieselbe Bug-Klasse wie die frühere „Stub-Parent"-Fix, aber nie auf `gauge%` angewendet, weil es kein `make-stub-class`-Produkt ist |
| Klassifikation | mechanisch |
| Aktion | Echten Parent aus `init-rest args` extrahieren, an `super-new` durchreichen |

### Crash 6 — `gauge%`: `send: no such method; set-range` ✅

| Feld | Wert |
|---|---|
| Aufrufkette | `wxlitem.rkt:55` (`wx-gauge%`s `bounce`-Makro) → `set-range`/`get-range`/`set-value`/`get-value` auf der Platform-Instanz |
| Ursache | Unser `gauge%` hatte die falschen Methodennamen (`set-gauge-value`/`get-gauge-value` statt `set-range`/`get-range`/`set-value`/`get-value` — Kontrakt laut `gtk/gauge.rkt` verifiziert) |
| Klassifikation | mechanisch |
| Aktion | `gauge%` auf echten `range`/`value`-Zustand + korrekte Methodennamen umgestellt |

### Crash 7 — `frame%`: `send: no such method; set-title` ✅

| Feld | Wert |
|---|---|
| Aufrufkette | `wxtop.rkt:617` (`make-top-level-window-glue%`) → `set-title` auf Platform-Frame |
| Ursache | Unser `frame%` hatte nur `set-label` (init-Titel), nie `set-title` (Kontrakt laut win32/gtk `frame.rkt` verifiziert — separate Methode für dynamische Titel-Updates) |
| Klassifikation | mechanisch |
| Aktion | `(define/public (set-title s) (shim_window_set_title qt-handle s))` ergänzt. Modified-Indicator (`*`-Suffix wie win32/gtk) bewusst weggelassen — nicht exerciert, YAGNI bis gebraucht |

### Crash 8 — `set-canvas-background`: „cannot set a transparent canvas's background color" ✅

| Feld | Wert |
|---|---|
| Aufrufkette | `mrcanvas.rkt:79` — Kontrakt-Check `(unless (send wx get-canvas-background) (raise ...))` beim DrRacket-Fenster-Aufbau (`make-root-area-container`) |
| Ursache | `qt/canvas.rkt`s `get-canvas-background` gab hart `#f` zurück (galt fälschlich immer als „transparent") |
| Klassifikation | mechanisch (Kontrakt laut win32 `canvas.rkt` verifiziert: Default ist `white`, nicht `#f`) |
| Aktion | `bg-col`-Feld (default `(make-object color% "white")`), `get-`/`set-canvas-background` lesen/schreiben es |

### Crash 9 — `get-current-mouse-state: arity mismatch` ✅ (mit Flag)

| Feld | Wert |
|---|---|
| Ursache | Unsere Signatur `(get-current-mouse-state xb yb)` (2 Args, Box-basiert) stimmte nie mit dem echten Kontrakt überein: **0 Args, 2 Rückgabewerte** (`point%`, Modifier-Liste) — verifiziert gegen win32/gtk/cocoa `procs.rkt` |
| Klassifikation | mechanisch (Arity), aber echte Cursor-Position fehlt |
| Aktion | Arity/Kontrakt korrigiert: `(values (make-object point% 0 0) '())` |
| **Flag** | ⚑ Kein Shim für echte globale Cursor-Position — Rückgabe ist Platzhalter `(0,0)`, keine Buttons. Nachziehen falls Positions-abhängige Funktionalität (Kontextmenü-Platzierung o.ä.) es braucht. |

### Crash 10 — `file-selector: arity mismatch` (6 vs. 7) ✅

| Feld | Wert |
|---|---|
| Aufrufkette | `framework/private/finder.rkt:34` → `save-as` (`editor-mixin`) → `file-selector` |
| Ursache | 9.2-Merge brachte einen neuen `filters`-Parameter (zwischen `ext` und `style`) — verifiziert gegen `gtk/filedialog.rkt` |
| Klassifikation | Versions-Stub (9.2-Neuerung) |
| Aktion | Signatur um `filters` ergänzt; bleibt inhaltlich Stub (`#f`, kein echter Datei-Dialog) |

### Bug 11 — Doppelte Zeichen beim Tippen (Interactions-Bereich) ✅ — wichtiger Fund

| Feld | Wert |
|---|---|
| Symptom | Jedes getippte Zeichen kam doppelt an |
| Diagnose | Debug-Print im `key-cb` (canvas.rkt) zeigte: genau 1× Press + 1× Release pro Tastendruck auf Shim-Ebene — kein Doppel-Callback. Root Cause lag also im Event-Objekt selbst. |
| Ursache | `key-event%`-Kontrakt (verifiziert gegen `win32/key.rkt`): bei Release muss `key-code` das Symbol `'release` sein, NICHT der echte Key — der echte Key gehört ausschließlich in `key-release-code`. Unser Code setzte `key-code` bei Release fälschlich auf den echten Tastencode, wodurch der Editor Press UND Release je als eigenständigen Zeichen-Insert interpretierte. |
| Klassifikation | mechanisch, aber substanziell (betrifft jede Texteingabe) |
| Aktion | `canvas.rkt`s `key-cb`: `[key-code (if is-up? 'release kc)]` |

### Bug 12 — Enter/Return ohne Wirkung (Editor + Interactions) ✅ — wichtiger Fund

| Feld | Wert |
|---|---|
| Symptom | Zeilenumbruch per Enter tat nichts, weder Definitions- noch Interactions-Editor |
| Diagnose | Debug-Print in `dispatch-on-char` zeigte `pre=#t` für Return — der Press wurde bereits in `call-pre-on-char` geschluckt, `on-char` (und damit der Editor) wurde nie erreicht. Weiterverfolgt über `wxtop.rkt`s generische `handle-traverse-key`: bei `#\return` wird `(get-focus-window)` abgefragt; ist der fokussierte Widget `wx:editor-canvas%`, wird Return NICHT geschluckt. |
| Ursache | Unser `get-focus-window` in `window.rkt`/`frame.rkt` gab hart `#f` zurück — es gab **keinerlei Fokus-Tracking**. `handle-traverse-key` sah dadurch nie einen editor-canvas% als fokussiert und schluckte Return generell (Fallback-Zweig für „kein editierbares Control fokussiert"). |
| Klassifikation | architektonische Lücke, aber sauber schließbar ohne Shim-Änderung |
| Aktion | `window.rkt`: `on-set-focus`/`on-kill-focus` melden sich jetzt beim `get-top-frame` (`record-focus-window`/`clear-focus-window`); `get-focus-window` liest das getrackte Feld. `frame.rkt`s redundanten `#f`-Override entfernt. |
| **Flag** | ⚑ Vereinfacht ggü. win32 (kein `focus-window-path`, kein „ist das OS-Fenster aktiv"-Check bei `even-if-not-active? = #f`) — für Single-Frame-Testszenarien ausreichend, ggf. nachschärfen bei Multi-Fenster-Fokus-Edgecases. |

### Crash 13 — `popup-menu`: `send: no such method` ✅ (mit Flag)

| Feld | Wert |
|---|---|
| Aufrufkette | `mrwindow.rkt:132` (Kontextmenü, z.B. Rechtsklick im Editor) → `(send wx popup-menu mwx x y)` |
| Ursache | `popup-menu` fehlte komplett auf unserem `window%`/`canvas%` (existiert bei win32/gtk auf Basis-Fenster-Ebene) |
| Klassifikation | mechanisch — unser `menu%` hatte bereits eine funktionierende `popup`-Methode (`shim_menu_popup`), nur der Aufrufer fehlte |
| Aktion | `window.rkt`: `popup-menu` ergänzt, delegiert an `(send m popup ...)` |
| **Flag** | ⚑ `client-to-screen` ist weiterhin No-op (kein Shim für Widget→Bildschirm-Koordinaten) → Popup erscheint an der übergebenen lokalen Position, nicht an der echten Bildschirmposition. Sichtbar auch beim Sprachauswahl-Dropdown oben im Fenster (öffnet am linken Bildschirmrand statt unter dem Control). Braucht neue Shim-Funktion (`QWidget::mapToGlobal`), noch nicht gebaut. |

### Offen — Menüleiste visuell nicht sichtbar (Daten sind korrekt!)

Debug-Zählung bestätigt: DrRackets echtes Menü wird **vollständig** aufgebaut — 31 Top-Level-`menu-bar%`-Appends, 165 `menu%`-Item-Appends (File/Edit/Help/Tabs mit allen echten Shortcuts). `shim_menubar_add_menu`/`shim_window_set_menubar` werden korrekt mit echten Daten aufgerufen. Trotzdem ist im laufenden Fenster keine Menüzeile sichtbar; stattdessen wirkt der obere Fensterbereich überlappend/verzerrt (siehe Screenshot-Beschreibung: „Untitled" überlappt eine Tooltip-artige Box, ein weißes Rechteck, Icons doppelt).

**Klassifikation: ARCHITEKTONISCH GELADEN — nicht weiterverfolgt, FLAG für nächste Session.** Die Daten-Seite ist nachweislich korrekt; das Problem liegt rein in Qt-Layout/Rendering (`QMainWindow::setMenuBar` + `setCentralWidget`-Zusammenspiel, oder Racket-seitige Geometrie-Berechnung, die die vom MenuBar reservierte Höhe nicht kennt). Braucht visuelle Qt-Debugging-Session (z.B. Widget-Ränder einfärben, `QMainWindow`-Layout-Introspektion), kein reiner Racket-Fix.

### Offen — Teilweises/fehlerhaftes Neuzeichnen

Nutzer-Beobachtung: das Zeichnen deckt nicht immer den ganzen Interactions-/Editor-Bereich ab (Reste alter Inhalte sichtbar). Noch nicht root-caused — vermutlich verwandt mit der Layout-Frage oben (falsche Widget-Geometrie/Invalidierungsregion), aber nicht isoliert bestätigt. **FLAG für nächste Session.**

### Nebenbefund — Autosave-Recovery-Dialog beim wiederholten harten Prozess-Kill

Beim Debuggen wird DrRacket wiederholt per `taskkill /F` beendet (kein sauberer Exit) — das triggert beim nächsten Start DrRackets Autosave-Recovery. Relevant sind **zwei** Dateien in `%APPDATA%\Racket\`:
- `PLT-autosave-toc.rktd` — die **tatsächlich für die Recovery-Entscheidung gelesene** Datei (`restore-autosave-files/gui` in `framework/private/autosave.rkt`)
- `PLT-autosave-toc-save.rktd` — nur eine Rotations-Sicherung der vorherigen TOC, NICHT die Recovery-Quelle

Nicht projektbezogen (kein Qt-Bug), aber relevant fürs Debugging-Setup: beide auf `()` setzen + verwaiste `mredauto.*`-Dateien in `Documents\` löschen, um störende Recovery-Dialoge zwischen Testläufen zu vermeiden. Zusätzlich erschwerend: der Recovery-Dialog selbst scheint von demselben Button-Rendering-Problem betroffen zu sein wie andere Dialoge (keine sichtbaren Buttons) — siehe Layout-Flag oben.

---

## Ergebnis Phase 3 (Stand 2026-07-02, Session-Ende)

**Erreicht:**
- DrRacket-Hauptfenster sichtbar, läuft stabil (kein Crash mehr bei Standard-Bedienung)
- Definitions- **und** Interactions-Editor: Tippen korrekt (nach Bug 11), Enter/Zeilenumbruch korrekt (nach Bug 12)
- Code-Ausführung über Interactions-Bereich funktioniert (beliebige Prozeduraufrufe getestet)
- Run-Button in der (visuell kaputten) Toolbar anklickbar und funktional

**Noch nicht erreicht / offen:**
- Menüleiste nicht sichtbar (Daten korrekt, reines Rendering/Layout-Problem)
- Popup-Positionierung (Kontextmenüs, Dropdowns) an falscher Bildschirmposition
- Teilweises Neuzeichnen im Editor-/Interactions-Bereich (nicht root-caused)
- `dialog%` weiterhin nicht battle-tested (Recovery-Dialog erschien, aber Buttons unsichtbar — gleiche Ursache wie Menüleiste vermutet)

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

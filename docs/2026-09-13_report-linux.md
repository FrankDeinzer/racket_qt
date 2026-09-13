# Report — Block A: Vertragslücken im Qt-Backend systematisch schließen (Linux) — 2026-09-13

**Prompt:** `docs/2026-09-13_prompt.md`. Gemessene Version: `~/racket/bin/racket --version`
→ **v9.3 [cs]** (x86-64, `~/racket`, nicht im PATH — volle Pfade verwendet).

---

## Phase 0 — Umgebung, Basislinie, Viewport-Test

### 0.1–0.2 Sync-Check (Regel 7)

- Umbrella `main`: `git fetch origin` + `git rev-list --left-right --count main...origin/main`
  → **0/0**, synchron.
- Submodul `third_party/gui` (`qt-backend`): `git fetch origin` +
  `git rev-list --left-right --count HEAD...origin/qt-backend` → **0/0**, synchron, HEAD
  `a71d2e9a` (= `feat(qt): implement frame% maximize/iconize/fullscreen (§27)`).
- Umbrella-Zeiger (`git submodule status third_party/gui`) zeigt exakt `a71d2e9a` — Zeiger
  und Submodul-HEAD identisch.
- **Kein STOPP-Kriterium, keine Nutzer-Rückfrage nötig** — nichts zu pullen/pushen.

### 0.3 Stale-Shim-Check

`shim.cpp` (2026-09-13 12:45) älter als `libracketqtshim.so` (2026-09-13 13:06) →
Zeitstempel sprechen für „kein Rebuild nötig". **Stärkerer Beleg (Advisor-Hinweis):**
`wx/qt/utils.rkt` deklariert die sechs §27-FFI-Funktionen (`shim_frame_set_maximized` &
Co.) — wäre die gebaute `.so` älter als diese Deklarationen, würde bereits `get-ffi-obj`
beim Laden fehlschlagen. Der grüne Qt-Smoke-Test unten (0.4) belegt das ABI-Match
empirisch, nicht nur über Zeitstempel.

### 0.4 Light Mode + Smoke-Gate

- `racket-prefs.rktd`: `framework:white-on-black? #f` — bestätigt.
- `raco test tests/smoke.rkt` **ohne** `PLT_QT`: **3/3 grün**.
- `raco test tests/smoke.rkt` **mit** `PLT_QT=1`: **3/3 grün**.

**Backup `racket-prefs.rktd`** vor jeder GUI-Interaktion angelegt (Scratchpad,
SHA-256 `4e886175bc42477242c61d4cba81dd054174364e8b6e8d179aa0f34cab7e0404`).
Relevanter Fund für 0.6: Fenstergeometrie liegt unter
`plt:framework-pref:drracket:window-size`, ein Hash keyed nach Monitor-Konfiguration
(`((0 0 <w> <h>)) . (maximized? width height)`). Aktueller Monitor: `1518x920`
(`xrandr`), zugehöriger Default-Eintrag: `(#f 600 650)` — **nicht maximiert, 600×650**.

**Self-Gate Checkpoint 0 (Teil 1): bestanden.** Weiter zu 0.5 (Baseline-Proben).

### 0.5 Basislinie (fünf Proben)

Alle fünf Proben gegen echtes DrRacket unter `PLT_QT=1`, unveränderte Prefs-Geometrie
(600×650). Automatisierung: `xdotool` (Fensteraktivierung/Klicks) + `spectacle -b -n -f`
(Vollbild-Screenshot, gelesen statt fensterspezifischem `-w` — letzteres hing einmal
unbegrenzt, s. Automatisierungs-Fund unten). Run-Button und Menüs per Maus geklickt,
keine Tastatur-Akzeleratoren (deckt sich mit dem Windows-Negativbefund vom 2026-09-11).

| Probe | Erwartung (§23.1/§28) | Gemessen | Deckung |
|---|---|---|---|
| `htdp-image-probe.rkt` | 4/5 sichtbar | 4 sichtbar (Circle/Rectangle-Outline/Overlay/Beside), 5. (`above/align` Text+Rechteck) unterhalb des sichtbaren Bereichs, Scrollrad ohne Wirkung | ✅ deckt sich |
| `htdp-image-count-probe.rkt` | 4/6 sichtbar | 4 sichtbar (Circle/Rectangle-Outline/Overlay/Beside), Bild 5+6 (magenta/cyan Circle) fehlen | ✅ deckt sich |
| `htdp-text-isolated-probe.rkt` | sauber | rendert sofort korrekt (Text + Rechteck) | ✅ deckt sich |
| `htdp-bigbang-probe.rkt` | sauber | via `racket` direkt (nicht DrRacket); Tick-Stream (`tick: 0`…) und Fensteranzeige korrelieren exakt (Screenshot bei Tick 4 zeigt „4"); kein `exec()`, keine geschachtelte Schleife | ✅ deckt sich |
| `htdp-tests-probe.rkt` (n=1, wie vorgegeben — n=3 ist Phase 3 vorbehalten) | `test-dock-size`-Crash reproduziert | **byte-identisch reproduziert:** `DrRacket Internal Error`, `preferences:set: new value doesn't satisfy preferences:set-default predicate — pref symbol: 'test-engine:test-dock-size, given: '(1)`, Stack über `test-tool.rkt:267` (`remove`). Prozess überlebt den Crash (weiterhin responsiv, sauber terminierbar). | ✅ deckt sich |

**Keine Abweichung von der Linux-Erwartung — Basislinie vollständig bestätigt.**

**Automatisierungs-Fund (methodisch, kein Produktbefund):** DrRacket erzeugt neben dem
sichtbaren Hauptfenster ein zusätzliches, dauerhaft `IsUnMapped`-Fenster mit generischem
Titel „DrRacket 9.3" (vermutlich der Splash-Screen, `hide()` statt `close()`) — bei
mehreren gleichzeitig per `xdotool search --name "DrRacket"` gefundenen Treffern liefert
die Suche nicht zuverlässig zuerst das sichtbare Fenster. Fix für den Rest der Session:
immer per `xwininfo -id <id> | grep "Map State"` auf `IsViewable` prüfen, bevor
`windowactivate` auf eine gefundene ID angewendet wird. `spectacle -b -n -w <id>` hing
einmal unbegrenzt (Hintergrundprozess manuell beendet) — seither ausschließlich
`spectacle -b -n -f` (Vollbild) verwendet und im Screenshot das relevante Fenster
gesucht.

### 0.6 Viewport-Test (§23.1)

**Korrekte Methode (wie im Prompt gefordert):** Fenstergeometrie **vor** dem Start über
`plt:framework-pref:drracket:window-size` gesetzt (Schlüssel für diesen Monitor
`((0 0 1518 920))`, Tupel `(maximiert? Breite Höhe)`), nicht nachträglich per Resize
(das würde nur §21.7 messen, nicht die Viewport-Frage — Reflow ist unter Qt nicht
verdrahtet). **Wichtiger Nebenfund:** der monitor-spezifische Hash-Key allein reichte
nicht — die erste Messung (nur `((0 0 1518 920))`-Eintrag auf Höhe 500 geändert) zeigte
**keine** Wirkung; erst nach zusätzlicher Änderung des `#f`-Fallback-Eintrags (derselbe
Wert) griff die neue Höhe. Für alle drei Messungen wurden beide Einträge synchron
gesetzt. Je Messung: Prefs editieren (DrRacket nicht währenddessen offen) → frischer
Start → `htdp-image-count-probe.rkt` öffnen (per Kommandozeilenargument) → Run → Screenshot
→ vollständig beenden (File→Quit, per Klick, `ps aux` verifiziert) → nächste Höhe.

| Höhe (Pref) | Tatsächliche Fenstergeometrie (`xdotool getwindowgeometry`) | Sichtbare Bilder (von 6) |
|---|---|---|
| 500 | 600×500 | **~2 vollständig** (Circle, Rectangle-Outline), 3. (Overlay) angeschnitten |
| 650 (Default, aus 0.5 übernommen) | 600×650 | **4** |
| 900 | 600×848 (durch Bildschirmhöhe 920 gedeckelt) | **6/6 — alle sichtbar** |

**Eindeutiges Ergebnis: die Zahl skaliert monoton mit der Fenster-/Viewport-Höhe** (2 → 4
→ 6/6). Bei ausreichend hohem Fenster verschwindet der „nur 4 von 6"-Effekt vollständig.
**§23.1 ist damit ein Viewport-/Scroll-Befund und gehört in Cluster 2 (Scroll-Block)** —
kein eigenständiger offener Punkt mehr, sondern der **fünfte Reproduktionsfall** für
dieselbe Root-Cause wie §24.5 (Editor-Canvas-Scrollbars)/§25.2 (Colors-Tab rechte
Spalte): `wx/qt` liefert keinen funktionierenden vertikalen Scroll-Mechanismus für
Interactions-/`auto-vscroll`-Inhalte, die über die sichtbare Fensterhöhe hinausgehen.
Kein Fix-Versuch (0.6 ist reine Messung, wie vorgegeben).

Nach Abschluss: `racket-prefs.rktd` aus dem Backup zurückgespielt, SHA-256 verifiziert
identisch zum Ausgangsstand (`4e886175bc42477242c61d4cba81dd054174364e8b6e8d179aa0f34cab7e0404`).

---

## Phase 1 — Vertrags-Audit (Inventar)

Vier parallele Subagenten (Datei-Gruppen: Core/Container, einfache Controls, komplexe
Controls/Dialoge, Menüs/Infra), jede Datei in `wx/qt/` gegen `wx/win32/`, `wx/gtk/`,
`wx/cocoa/` verglichen. Konsolidierte Tabelle, dedupliziert (das erwartete
`is-shown?`-Hardcoding wurde von mehreren Gruppen unabhängig für dieselben Dateien
bestätigt — hier nur einmal geführt).

| Datei | Methode | Qt-Verhalten | natives Verhalten | Konsumenten im Shared Code | Einschätzung |
|---|---|---|---|---|---|
| `panel.rkt:58`, `list-box.rkt:174`, `tab-panel.rkt:159`, `slider.rkt:124`, `radio-box.rkt:84`, `group-panel.rkt:79`, `button.rkt:64`, `choice.rkt:86`, `check-box.rkt:67`, `message.rkt:48` | `is-shown?` | hartcodiert `#t` | win32/gtk/cocoa überschreiben es auf diesen Klassen gar nicht — erben ein echtes, dynamisches `shown?`-Feld aus der jeweiligen Fenster-Basisklasse (verifiziert: `win32/window.rkt:284/327`) | `wxwindow.rkt:124-127` (`(or fake-shown? (super is-shown?))`), `mrwindow.rkt:239`, `mrcontainer.rkt:157/182` (`reparent`), `wxtop.rkt` | **Vertragslüge — Cluster 1, gefixt in Phase 2.1** |
| `window.rkt` (alle Klassen) | `enable`/`parent-enable` | `enable` flippte nur ein Racket-Flag, rief nie `shim_widget_set_enabled`; `parent-enable` reiner No-op | win32: `enable` ruft `internal-enable` → echtes `EnableWindow`, cascadet via `parent-enable` manuell an Kinder (`win32/panel.rkt:41/46`) | `win32/panel.rkt`-intern (kein Aufrufer in `mred/private`/`framework` für `parent-enable` selbst) | **Vertragslüge — Cluster 1, gefixt in Phase 2.2** (anderer Mechanismus als win32, s. u.) |
| `filedialog.rkt:67` | `file-selector` (`'dir`/`'multi`) | liefert unconditional `#f` — ununterscheidbar von Nutzer-Abbruch | win32/gtk/cocoa unterstützen beide Stile echt | `mred/private/filedialog.rkt` (`get-directory`, `get-file-list`) | Vertragslüge (Cluster 1, **nicht in diesem Block gefixt** — kein Bezug zum Sichtbarkeits-/Enable-Cluster, eigener Befund) |
| `button.rkt` | `set-label` | No-op, Kommentar „not exposed in shim yet" | win32/gtk/cocoa: echtes natives Label-Update | `mritem.rkt:62-73`, `path-dialog.rkt` | Out of Scope (eigener Block — Feature-Lücke, keine Zustands-Lüge) |
| `button.rkt` | `set-border` | No-op | win32/gtk: echter Default-Rahmen | `wxitem.rkt:221-227` (Default-Button-Hervorhebung) | Out of Scope (eigener Block) |
| `message.rkt` | `set-color`/`get-color`/`set-preferred-size` | No-op / immer `#f` | win32/gtk/cocoa: echte Werte | `mritem.rkt:144-169` | Out of Scope (eigener Block) |
| `window.rkt` | `set-cursor`/`reset-cursor` | No-op | win32/cocoa: echter Cursor-Handle | `mrwindow.rkt`, `messagebox.rkt`, `wxtextfield.rkt` | Out of Scope (eigener Block) |
| `window.rkt` | `get-dialog-level` | hartcodiert `0`, keine Delegation an `parent` | win32/gtk: rekursiv bis Frame/Dialog | `wx/common/queue.rkt`s `other-modal?` | Geprüft für 2.3-Zugehörigkeit — **nicht** auf dem `on-tab-change`-Pfad reachable (dieser Pfad nutzt `is-shown?`, nicht `get-dialog-level`); inventarisiert, nicht in diesem Block gefixt |
| `window.rkt` | `skip-enter-leave-events`, `set-event-positions-wrt` | No-op | win32/gtk/cocoa: echte Felder | `wxlitem.rkt`, `mrtop.rkt`, `mrpanel.rkt` | Out of Scope (eigener Block — Event-Detail, kein Sichtbarkeits-/Enable-Bezug) |
| `frame.rkt` | `set-modified` | fehlt komplett (fällt auf `window%`s No-op zurück) | win32/gtk/cocoa `frame.rkt` überschreiben real (Titlebar-Dirty-Marker) | `mrtop.rkt`, `wxme/editor-snip.rkt`, `wxme/undo.rkt` | Out of Scope (eigener Block — Muster 3, aber kein Bezug zu is-shown?/enable) |
| `canvas.rkt` | `get-canvas-background-for-backing` | hartcodiert `#f`, ignoriert `bg-col` | win32/gtk/cocoa: real | `wx/common/canvas-mixin.rkt`s `do-on-paint` | Out of Scope (eigener Block) |
| `canvas.rkt` | `request-canvas-flush-delay` | hartcodiert `#f` | win32/gtk/cocoa: echter Mechanismus | `canvas-mixin.rkt`s `queue-paint` | Out of Scope (eigener Block, geringe Schwere) |
| `menu.rkt` | `popup` (Parameter `cb`) | wird ignoriert, keine Popdown-Rückmeldung | win32/gtk/cocoa rufen `cb` | `mrwindow.rkt:134`, `mrpopup.rkt` | Out of Scope (eigener Block — Kontextmenü-Feature) |
| `menu.rkt` | `append`-Callback bei freistehenden Popup-Menüs | scheitert an `find-top-frame`, wenn kein Menu-Bar-Elternpfad existiert | win32/gtk/cocoa liefern Item-Auswahl auch ohne Menu-Bar | dieselben Konsumenten wie `popup` | Out of Scope (eigener Block) |
| `menu.rkt` | `select` | No-op | win32: Alt-Mnemonic-Pfad; gtk: `activate-item` | `wxmenu.rkt:69` (`handle-key`), aktiv da `shortcut-visible-in-label?` `#t` | Out of Scope (eigener Block) |
| `frame.rkt`/`menu-bar.rkt` | `on-menu-click`-Signalisierung | keine Anbindung an ein Qt-Signal | win32/gtk/cocoa: echtes Signal vor Menü-Anzeige | `wxtop.rkt:734ff.` (Live-Update Checked/Enabled/Label) | Out of Scope (eigener Block) |
| `dialog.rkt` | `is-dialog?` | fehlt (kein `define/override`, kein Init-Arg) | win32: `#t` fest; gtk/cocoa: Init-Arg | kein Konsument gefunden | harmlos |
| `list-box.rkt`/`tab-panel.rkt`/`group-panel.rkt`/alle 6 einfachen Controls | `direct-show` | No-op | in keinem nativen Backend auf diesen Klassen definiert | kein Konsument (nur `wx/common/dialog.rkt` für Frame/Dialog) | harmlos |
| 4 einfache Control-Typen | `set-border` | No-op | win32/gtk überschreiben `set-border` dort ebenfalls nicht | kein Konsument | harmlos |
| `canvas.rkt` | `set-resize-corner` | No-op | win32/cocoa real, **gtk ebenfalls No-op** | `mrcanvas.rkt` | harmlos (uneinheitlich schon nativ) |
| `menu.rkt` | `set-self-item`/`get-item`/`removing-item` | Stubs | gtk pflegt echten Wert | kein Konsument gefunden | harmlos |
| `canvas.rkt` | `show-scrollbars`/`set-scrollbars`/`do-set-scrollbars` | No-ops | win32/gtk/cocoa real | `wxme`, Preferences-Dialog | Out of Scope — **Scroll-Cluster (§24.5/§25.2)**, eigener Block |
| `canvas.rkt`/`window.rkt` | `resizeEvent`/Live-Reflow | nur Repaint, keine Kind-Repositionierung | win32/gtk/cocoa: echte Resize-Hooks | Preferences-Dialog-Layout | Out of Scope — **Geometrie-Cluster (§21.7)**, eigener Block |
| `utils.rkt`/`canvas.rkt` | FFI-Callback-Ctypes (`_callback_t` & Co.), `mouse-cb`/`key-cb` | `#:atomic? #t` ohne `#:async-apply`; `mouse-cb`/`key-cb` bauen `mouse-event%`/`key-event%`-Objekte (Allokation, `case`-Dispatch) **innerhalb** des atomaren Callbacks, bevor `queue-event` gerufen wird — der Datei-Kommentar „only enqueue work — no Racket calls" (canvas.rkt) stimmt insofern nicht exakt | — | — | **Regel-2-Wortlaut-vs.-Praxis-Divergenz, dokumentiert, kein gemessener Defekt.** Vergleichsbasis des ursprünglichen Audit-Funds (cocoa `#:async-apply`) war die falsche: cocoa nutzt dafür Objective-C-Methodendefinitionen/CFRunLoop-Plumbing, ein anderer Mechanismus. Die strukturell nächste Vergleichsstelle ist win32s `_WndProc` (`wndclass.rkt:108`), die ebenfalls `#:atomic? #t` **ohne** `#:async-apply` nutzt und synchron `(send wx wndproc ...)` mit Rückgabewert aufruft — noch mehr Racket-Arbeit im atomaren Kontext als `mouse-cb`. Kein beobachtetes Symptom (Smoke seit Monaten stabil, 3 Plattformen). **Nicht gefixt** (Regel 4: kein spekulativer Fix ohne gemessenen Defekt) — als Kandidat-Lead für den bereits geplanten Teardown-Cluster-Block vorgemerkt (Linux Crash B „invalid memory reference", macOS-Zombie-Prozess) |

**Self-Gate Checkpoint 1:** Inventar ~20 Zeilen (unter dem Richtwert von ~15 „echten"
Vertragslügen, wenn man die Out-of-Scope-Feature-Lücken separat zählt), keine
zwingende Shared-Code-Änderung für die Cluster-1-Zeilen → direkt Phase 2, keine
`AskUserQuestion` nötig.

---

## Phase 2 — Die Klasse fixen

### 2.1 `is-shown?` — Basis zuerst verifiziert, dann Overrides entfernt

**Messung vor dem Löschen (wie gefordert):** instrumentiert (`PLT_QT_DEBUG_SHOWN`,
temporär, seither vollständig entfernt) `wx/qt/window.rkt`s `show`-Methode und ein
Frame→`vertical-panel%`→`button%`-Probe (`examples/is-shown-probe.rkt`, bleibt als
Diagnose-Probe erhalten). Ergebnis: `show #t` wird für Panel **und** Button bereits
während der Konstruktion/Container-Einfügung ausgelöst (über
`wxwindow.rkt`s `override* show` → `show-control` → `really-show` → `super show`,
**lange bevor** der Frame selbst explizit gezeigt wird) — nur der Frame selbst erhält
zusätzlich ein `show #t` beim expliziten `(send f show #t)`. Das bestätigt: die Basis
pflegt `shown?` bereits korrekt und real, genau wie win32s Konstruktions-Convention
`(unless (memq 'deleted style) (show #t))` — das Entfernen der Overrides ersetzt also
keine Lüge durch eine schlimmere (`#f` immer), sondern durch den echten Wert.
Zusätzlich bestätigt: `is-shown-to-root?` (bereits §26/§26.1 rekursiv) liest das rohe
`shown?`-**Feld**, nicht die (vormals überschriebene) `is-shown?`-**Methode** — die
Rekursions-Kette war also die ganze Zeit korrekt, nur der Methoden-Override selbst log.

**Fix:** die zehn hartcodierten `(define/override (is-shown?) #t)`-Zeilen entfernt aus
`panel.rkt`, `list-box.rkt`, `tab-panel.rkt`, `slider.rkt`, `radio-box.rkt`,
`group-panel.rkt`, `button.rkt`, `choice.rkt`, `check-box.rkt`, `message.rkt` — alle
fallen jetzt auf `window%`s echtes `shown?`-Feld zurück (keine Shim-Änderung, reine
`wx/qt/`-Racket-Änderung, Regel 2).

### 2.2 Enable-Kaskade — nicht win32 gespiegelt, sondern Qt-natives Cascade genutzt

**Messung vor dem Fix:** `parent-enable` selbst hat **keinen** Konsumenten außerhalb von
`win32/panel.rkt` (win32-interner Cascade-Mechanismus, kein Shared-Code-Aufruf) — ein
1:1-Nachbau von win32s Racket-seitigem Cascade (`internal-enable` → `parent-enable` an
jedes Kind) wäre also kein Fix eines echten Konsumenten, sondern reine Nachahmung.
Der tatsächliche Befund lag tiefer: `wx/qt/window.rkt`s `enable` änderte **nur** das
Racket-Flag `enabled?`, rief **nie** `shim_widget_set_enabled` (einzige bisherige
Aufrufstelle: `frame.rkt`s `modal-enable`, direkt auf das eigene Handle, unabhängig von
`enable`/`enabled?`). Folge: `button.rkt`s `click-fn` prüft `is-enabled-to-root?`
nicht und ist direkt an das native Qt-Klick-Signal verdrahtet — ein Racket-seitig
„deaktivierter" Button blieb nativ voll klickbar, weil das Qt-Widget selbst nie
`setEnabled(false)` bekam.

**Fix (Qt-idiomatisch, kein win32-Nachbau):** `enable` in `wx/qt/window.rkt` ruft jetzt
zusätzlich `(shim_widget_set_enabled handle ...)` auf das eigene Handle. Qt cascadet
`QWidget::setEnabled()` bereits nativ auf alle Kind-Widgets (bestätigt:
`qt-shim/src/shim.cpp:476-479`, reiner `setEnabled()`-Delegat; Qt-Framework-Garantie,
kein backend-eigener Code) — ein manuelles Racket-seitiges Nachreichen an Kinder
(wie win32s `parent-enable`) ist dafür **nicht** nötig, weil Qt einen echten
Eltern-Kind-Widget-Baum hat und win32 nicht auf dieselbe Weise. `parent-enable` bleibt
als harmloser No-op bestehen (kein Konsument, kein Fix nötig). Keine Shim-Änderung
(`shim_widget_set_enabled` existierte bereits, nur ein neuer Aufrufer in `wx/qt/`).

**Verifikation:** `examples/enable-cascade-probe.rkt` (neu, bleibt als Probe erhalten,
inzwischen um ein Live-Klickzähler-Label erweitert) — `(send button enable #f)` läuft
ohne Crash, `is-enabled?` meldet korrekt `#f` danach.

**Verifikationsversuch per echtem Klick (nach Advisor-Rückfrage nachgeholt) —
ergebnislos wegen Automatisierungs-Artefakt, nicht wegen eines Produktbefunds:**
mehrere Versuche, den Button per `xdotool` tatsächlich anzuklicken (vor **und** nach
`enable #f`, um 1 vs. 1 statt 1 vs. 2 Klicks zu erwarten), scheiterten an einem
Fokus-Problem dieser Automatisierungsumgebung: `xdotool getactivewindow` bestätigt vor
dem Klick zuverlässig das Probe-Fenster als aktiv/im Vordergrund (auch per Screenshot
visuell verifiziert), aber der synthetische Klick selbst (`mousemove`+`click` **und**
separat `mousedown`/`mouseup`) hebt reproduzierbar stattdessen das Terminalfenster
(„racket_qt : claude — Konsole") an — der Klick landet office nicht auf dem
Button, sondern scheint auf X11-Stacking-Ebene ein anderes Fenster zu treffen als das,
was der Compositor sichtbar oben zeigt (vermutlich ein X11/Wayland-Stacking-
Diskrepanz-Artefakt dieser spezifischen Sitzung — dieselbe Klick-Technik funktionierte
zuverlässig gegen die deutlich länger laufenden DrRacket-Fenster in Phase 0/Akzeptanztest,
nur nicht gegen dieses sehr kurzlebige Einzel-Widget-Fenster). Klickzähler blieb in
allen Versuchen bei 0, sowohl vor als auch nach `enable #f` — kein Unterschied
zwischen den beiden Zuständen gemessen, also **kein** Beleg weder für noch gegen den
Fix aus dieser Teilverifikation. **Ergebnis:** Klick-Verhalten bleibt unverifiziert;
die Korrektheit von `QWidget::setEnabled()`s Input-Blockade stützt sich weiterhin nur
auf die dokumentierte Qt-Framework-Garantie (Code gelesen, `shim.cpp:476-479`, reiner
Delegat), nicht auf eine eigene Beobachtung.

**Zusätzlich, per Advisor-Review vor Abschluss identifiziert — bewusst ungetestete
Kante:** `frame%` erbt das neue `enable` unverändert; `frame%`s eigenes `modal-enable`
schreibt denselben nativen `setEnabled()`-Bit auf dasselbe Handle, aber über ein
**zweites, unabhängiges** Feld (`modal-enabled?` statt `enabled?`), ohne Reihenfolge-
Garantie zwischen beiden. Konkret ungeprüft: `(send frame enable #f)` (Anwendung
deaktiviert einen Frame bewusst) gefolgt vom Schließen eines fremden modalen Dialogs
(`modal-enable` setzt `setEnabled(#t)` zurück) würde den Frame stillschweigend wieder
aktivieren, obwohl die Anwendung ihn bewusst deaktiviert hatte. Nicht gemessen, kein
Fix versucht (kein beobachtetes Symptom, kein Bezug zum Akzeptanztest) — als konkrete
offene Kante für eine künftige Session vermerkt, nicht nur als Randgedanke.

### 2.3 Sonstiges aus dem Audit derselben Klasse

`get-dialog-level` (hartcodiert `0`, kein Parent-Delegat) hat dieselbe Form wie
`is-shown?` (Zustands-Lüge auf der Elternkette), ist aber **nicht** auf dem für den
Akzeptanztest relevanten `on-tab-change`-Pfad erreichbar (dieser nutzt `is-shown?`,
nicht `get-dialog-level`) — inventarisiert (s. Tabelle oben), **nicht** in diesem
Block gefixt (kein Bezug zum Akzeptanztest, eigener potenzieller Fix für eine
künftige Session, die Modalitäts-Verschachtelung untersucht).

Keine weiteren Funde derselben Klasse (Zustands-Hardcoding auf der Sichtbarkeits-/
Enable-Elternkette) im Audit — die übrigen Cluster-1-Zeilen der Tabelle sind
Feature-Lücken (fehlende native Wirkung einer Methode wie `set-label`), keine
Zustands-Lügen, und bleiben Out of Scope für diesen Block.

---

## Akzeptanztest — `test-dock-size` (n=3)

Nach den Phase-2.1/2.2-Fixes, gegen echtes DrRacket unter `PLT_QT=1`, volle 1→2-Tab-
Sequenz dreimal aus frischem DrRacket-Start (`racket -l drracket -- examples/htdp-tests-probe.rkt`,
Run per Maus-Klick auf den Toolbar-Button, danach File→Open per Maus (Menü) von
`examples/htdp-image-probe.rkt` als zweite Registerkarte — exakt die historisch
10/10 crashende Sequenz aus §23/§28/2026-09-11):

| Durchlauf | Run-Ergebnis | Datei-Öffnen (2. Tab) | Crash? |
|---|---|---|---|
| 1 | „1 of the 3 tests failed" (Check-Dock mit Inhalt) | Tab 2 öffnet sauber, 2 Tabs bestätigt (Tabs-Menü) | **nein** |
| 2 | „1 of the 3 tests failed" | Tab 2 öffnet sauber | **nein** |
| 3 | „1 of the 3 tests failed" | Tab 2 öffnet sauber | **nein** |

**0/3 Crash — Akzeptanzkriterium erfüllt.** Vorher: 10/10 auf allen drei Plattformen
(§23/§23.1/§28). Kein „DrRacket Internal Error", kein `preferences:set`-Contract-
Fehler, Prozess bei jedem Durchlauf sauber über File→Quit (Maus) beendet.
**Umklassifizierter Nebenfund (zunächst als reine Automatisierungsnotiz geführt, nach
Advisor-Review korrigiert):** das `Tabs`-Menü selbst (nicht Teil des Fixes) ließ sich
zur Verifikation der Tab-Anzahl öffnen, aber ein Klick auf einen Tab-Eintrag darin
schloss das Menü nicht/wechselte den Tab nicht (weder Maus-Klick, noch separates
`mousedown`/`mouseup`, noch `Return` bei markiertem Eintrag — nur `Escape` schloss das
Menü zuverlässig, ohne den Tab zu wechseln). Das ist **kein reines
Automatisierungsartefakt**, sondern deckt sich mit einem in Phase 1 unabhängig
gefundenen Produktbefund: `menu.rkt`s `select` ist ein No-op, und `append`s
Leaf-Item-Callback funktioniert nur, wenn `find-top-frame` über die Menü-Bar-
Elternkette einen Frame findet (s. Inventar-Tabelle oben). File→Open (ein einfacher
Menüpunkt-Klick ohne Submenü-Radiogruppen-Charakter) funktionierte in derselben
Session zuverlässig per Maus — das grenzt den Verdacht auf Tab-Auswahl-artige
Menüeinträge (Radiogruppen-Verhalten, exklusive Auswahl) ein, nicht auf Menüs
allgemein. **Nicht untersucht, kein Fix-Versuch** (kein Bezug zum Akzeptanztest, der
die Sequenz nur in der anderen Richtung braucht) — als Kandidat-Produktbefund für den
künftigen Menü-Block vermerkt, nicht nur als Automatisierungsnotiz.

`racket-prefs.rktd` nach den drei Durchläufen aus dem Backup zurückgespielt, SHA-256
verifiziert identisch zum Ausgangsstand
(`4e886175bc42477242c61d4cba81dd054174364e8b6e8d179aa0f34cab7e0404`).

---

## Phase 3 — Gate (Fortsetzung: Regressions-Check + Scroll-Vormessung)

Phase 3.1 (Smoke 3/3 mit **und** ohne `PLT_QT`) und 3.3 (Akzeptanztest, s. o.) sind
bereits erledigt und grün. Dieser Abschnitt deckt 3.2 (Regressions-Check gegen die
0.5-Basislinie) und 3.4 (Scroll-Vormessung) ab.

### 3.2 Regressions-Check gegen die 0.5-Basislinie

Alle vier Nicht-Crash-Proben aus 0.5 nach den Phase-2.1/2.2-Fixes erneut gegen echtes
DrRacket unter `PLT_QT=1` gelaufen (unveränderte 600×650-Geometrie, dieselbe Methode:
Maus-Klick auf Run, `spectacle -b -n -f`, `xwininfo`/`Map State` zur Fensterauswahl):

| Probe | 0.5-Basislinie | Jetzt (nach Phase 2) | Regression? |
|---|---|---|---|
| `htdp-image-probe.rkt` | 4/5 sichtbar (Circle/Rectangle-Outline/Overlay/Beside), 5. unterhalb | **identisch: 4/5**, dieselben vier Bilder | **nein** |
| `htdp-image-count-probe.rkt` | 4/6 sichtbar | **identisch: 4/6**, Bild 5+6 fehlen weiterhin | **nein** |
| `htdp-text-isolated-probe.rkt` | rendert sofort korrekt | **identisch**, sofort korrekt | **nein** |
| `htdp-bigbang-probe.rkt` | Tick-Stream ↔ Fensteranzeige korreliert exakt | **identisch** (Screenshot bei Tick 2→3 zeigt „3", Log zeigt `tick: 2` kurz zuvor) | **nein** |
| `htdp-tests-probe.rkt` | `test-dock-size`-Crash 1/1 reproduziert (n=1, vor dem Fix) | **kein Crash mehr** (bereits über den n=3-Akzeptanztest oben abgedeckt, hier nicht erneut gelaufen) | **erwartete Verbesserung, keine Regression** |

**Ergebnis: keine Regression.** Alle vier viewport-/scroll-limitierten Proben zeigen
exakt dieselben Zahlen wie vor den Fixes — die Phase-2-Änderungen (`is-shown?`-Basis,
Enable-Kaskade) wirken sich auf normales Bild-/Text-/big-bang-Rendering nicht sichtbar
aus. Einzige Verhaltensänderung ist die beabsichtigte: `test-dock-size` crasht nicht mehr.

### 3.4 Scroll-Vormessung (§26-Hypothese) — neuer, eigenständiger Rendering-Befund

**Hintergrund/Auftrag:** §26 vermutete, der in §24.5 zurückgerollte Scrollbar-Fix könnte
(auch) am `is-shown-to-root?`/`is-enabled-to-root?`-Defekt gescheitert sein, den diese
Sitzung (Phase 2) jetzt behoben hat — `editor-canvas.rkt` fragt Sichtbarkeits-/Enable-
Zustand in seinem Render-Pfad ab. Auftrag: isolierte Probe erneut laufen lassen, nur
messen, kein Fix-Versuch.

**Kein bestehender Probe-Fund in `examples/`** (`grep -r "auto-vscroll" examples/` und
Dateinamen-Suche nach „scroll" — beide leer) — eine minimale throwaway-Probe geschrieben
(`editor-canvas%` mit Stil `'(auto-hscroll auto-vscroll)`, `text%` mit 100 Zeilen
absichtlich breitem Inhalt, Frame 400×300 — kleiner als der Inhalt), **nur im Scratchpad
abgelegt, nie in `examples/` oder `git add` gebracht** (per `git status` am Ende
verifiziert: keine neue Datei in `examples/`).

**Beobachtung — reproduziert 3/3 identisch (drei unabhängige frische `racket`-Prozesse,
zwei mit unterschiedlicher Laufzeit/Interaktion):** der Editor-Inhalt rendert **weder**
korrekt **noch** komplett weiß (die beiden bisher bekannten Plattform-Symptome), sondern
**sichtbar verstümmelt**: ein kleiner Bereich oben links zeigt fragmentarisch die ersten
Buchstaben des Inhalts („Lin…", vermutlich der Anfang von „Line 0 of…"), aber in
falschen, gestreiften Farben (vertikale orange/blaue/graue/beige Streifen statt
durchgehend schwarzem Text auf weißem Grund) — passt farblich zum bereits als
vorbestehend/unabhängig dokumentierten „orange/blau gestreiften Rechteck"-Nebenbefund
aus der Windows-Sitzung (§24.5-Anhang), hier aber erstmals **isoliert und gezielt
reproduziert**, nicht nur zufällig beobachtet. Kein Scrollbar sichtbar. Weder Mausrad
(5× Scroll-Down über dem Canvas) noch `PageDown`(`Next`)-Taste verändern das Bild in
irgendeiner Weise (drei Screenshots vor/nach Mausrad/nach PageDown: pixelidentisch).

**Einordnung ggü. den beiden bekannten Plattform-Symptomen:**
- Windows (§24.5): Inhalt komplett weiß, nur blinkender Caret.
- macOS (§29.2): Inhalt rendert korrekt, Scrollen bleibt wirkungslos.
- **Linux (hier, neu): Inhalt rendert weder korrekt noch weiß, sondern sichtbar
  farblich verstümmelt/gestreift — ein dritter, eigenständiger Symptom-Ausprägung
  derselben Fundstelle.**

**Verglichen mit der `is-shown?`/Enable-Fix-Erwartung aus §26:** das Symptom hat sich
**nicht** in Richtung „funktioniert jetzt" verändert — es ist weiterhin klar defekt,
nur anders defekt als vorher dokumentiert (frühere Linux-Beobachtung zu diesem
Fundkomplex war „nur die ersten 4 Interactions-Snips rendern", ein anderer Kontext als
dieser isolierte `editor-canvas%`-Test). Die §26-Hypothese (Sichtbarkeits-Fix könnte den
Scroll-Fix-Versuch mit ermöglichen) ist damit **nicht bestätigt** — der Defekt bleibt
nach dem Sichtbarkeits-Fix vollständig bestehen, nur mit einem dritten Erscheinungsbild.
**Ehrliche Einschränkung:** nicht zweifelsfrei belegt, dass diese throwaway-Probe exakt
dieselben Bedingungen wie die historischen §24.5/§29.2-Reproduktionen trifft (andere
Inhaltsgröße, kein DrRacket-Interactions-Kontext) — aber Stil (`'(auto-hscroll
auto-vscroll)`) und Symptom-Familie (Rendering-Defekt bei scrollbarem `editor-canvas%`)
stimmen überein.

**Kein Fix-Versuch** (Regel 4/Auftrag: reine Messung). Automatisierungs-Nebenfund:
ohne explizites `(exit 0)` am Skript-Ende bleibt der `racket`-Prozess dank der
Qt-Eventspace-Pump am Leben (erwartet, konsistent mit „Racket treibt die Loop") — beim
zweiten Testlauf ungewollt zwei überlappende Fenster erzeugt (`frame%`-Label-
Auto-Suffix `<2>`), dritter Testlauf mit explizitem `(exit 0)` sauber einzeln
reproduziert, identisches Ergebnis.

**Für die künftige Scroll-Session:** Empfehlung, das Farbmuster/den Stride-Verdacht
(`CLAUDE.md`: „Pixelformat … stride aus `cairo_image_surface_get_stride()` (nie
`width*4` annehmen)") als zusätzliche Hypothese mitzunehmen — das reproduzierbare,
deterministische Streifenmuster (nicht zufälliges Rauschen) ist ein typisches Symptom
eines Stride-/Zeilenlängen-Mismatches zwischen Cairo-Surface und Backing-Buffer, nicht
zwangsläufig ein reines Scrollbar-Problem. Nicht verifiziert, nur als Lead vermerkt.

**Betriebsdisziplin:** `racket-prefs.rktd` nach den Phase-3.2-DrRacket-Läufen erneut aus
dem Backup zurückgespielt, SHA-256 verifiziert identisch
(`4e886175bc42477242c61d4cba81dd054174364e8b6e8d179aa0f34cab7e0404`). `git status`
(Umbrella + Submodul) am Ende geprüft: Submodul sauber (Phase-2-Fixes bereits committet),
Umbrella zeigt nur den Report sowie die beiden aus Phase 2 bereits bekannten,
dauerhaften Proben (`is-shown-probe.rkt`, `enable-cascade-probe.rkt`) — keine neue
Datei durch diese Fortsetzung.

---

## Liste „später zu validieren" (gebündelter Cross-Platform-Durchlauf)

Diese Session hat bewusst **keine** Windows-/macOS-Validierung durchgeführt
(Cross-Platform-Modell des Prompts). Für den späteren gebündelten Durchlauf (zusammen
mit dem Geometrie- und dem Scroll-Block):

- **§23.3/Cluster-1-`is-shown?`-Fix** (10 Dateien, Commit `2f0755bd`): validieren, dass
  `test-dock-size` auch auf Windows/macOS nicht mehr crasht (dort ebenfalls 10/10 vor
  dem Fix) — reiner Racket-Code im Fork, identisch auf allen drei Maschinen, aber der
  Akzeptanztest selbst wurde nur auf Linux gefahren.
- **§26-Fund-2/Enable-Kaskade-Fix** (`window.rkt`, Commit `a787b43f`): validieren, dass
  `(send widget enable #f)` auf Windows/macOS weiterhin funktional korrekt bleibt (dort
  ruft bislang nichts explizit disable auf einzelne Widgets in den bestehenden Proben —
  ggf. `enable-cascade-probe.rkt` dafür nutzen) und keine Doppel-Wirkung mit
  `frame%`s `modal-enable` auftritt.
- **Neuer dritter Scroll-Symptom-Fall (Linux, dieser Report, Phase 3.4):** das
  gestreifte/verstümmelte Rendering bei `'(auto-vscroll)`-`editor-canvas%` — auf
  Windows (weiß) und macOS (korrekt, aber unscrollbar) bereits bekannt und
  gegensätzlich; dieser dritte Linux-Befund sollte in der künftigen Scroll-Session
  zuerst reproduziert werden, um zu sehen, ob er plattformspezifisch (Stride/Backing-
  Buffer, wie hier vermutet) oder Teil derselben Root-Cause ist.
- **§23.1-Reklassifizierung (Viewport statt eigenständiger Punkt):** auf Windows (6/6)
  und macOS (5/6) bereits mit abweichenden Zahlen bekannt — sollte im Scroll-Block
  gegen dieselbe Viewport-Hypothese (Fenstergeometrie **vor** Start setzen, nicht
  resizen) nachgemessen werden, um zu prüfen, ob die dortigen Zahlen sich ebenfalls
  auf 6/6 normalisieren, sobald das Fenster von Anfang an hoch genug ist.

---


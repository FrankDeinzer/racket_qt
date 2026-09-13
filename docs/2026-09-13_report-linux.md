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
(„racket_qt : claude — Konsole") an — der Klick landet offenbar nicht auf dem
Button, sondern trifft ein anderes Fenster als das, was `xdotool getactivewindow`
und der Screenshot unmittelbar zuvor als aktiv/oben bestätigt hatten. **Korrektur
(nachträglich verifiziert):** die Sitzung lief unter **X11** (`XDG_SESSION_TYPE=x11`,
`loginctl` bestätigt), **nicht** Wayland/XWayland — eine zunächst vermutete
Wayland-Kompositor-vs-X11-Stacking-Diskrepanz scheidet damit als Erklärung aus. Die
tatsächliche Ursache des Fokus-Sprungs bleibt ungeklärt (dieselbe Klick-Technik
funktionierte zuverlässig gegen die deutlich länger laufenden DrRacket-Fenster in
Phase 0/Akzeptanztest, nur nicht gegen dieses sehr kurzlebige Einzel-Widget-Fenster —
möglicherweise eine reine Timing-/Kurzlebigkeits-Eigenheit dieses Fensters, nicht
X11 oder Wayland an sich). Klickzähler blieb in
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

## Block B (Fortsetzung, direkt im Anschluss) — Resize/Reflow-Bug (§21.7): Konvergenz-Vormessung, kein Fix

**Kontext:** kein eigener geschriebener Prompt — direkte Fortsetzung auf Nutzerwunsch
("weiter mit Block B"). §21.7 (`docs/HACKING.md`) hatte diesen Bug bereits zweimal
(Windows, 2026-07-13) angefasst und beide Male vollständig zurückgerollt — echte
Reentrancy-Probleme in der nativen Resize-Behandlung, kein spekulativer dritter
Versuch ohne neue Messung.

### Orientierung (Fork) + Korrektur einer Fehleinschätzung aus Block A

Ein Fork hat `docs/HACKING.md` §21.7 + alle Folgeerwähnungen, `wx/qt/window.rkt`/
`frame.rkt`/`canvas.rkt`, `qt-shim/src/shim.cpp` und win32s Gegenstück gelesen.
Bestätigt: `RacketWindow` (`shim.cpp`, `QMainWindow`-Subklasse für `frame%`) hat
**keinen** `resizeEvent`-Handler; `wx/qt/frame.rkt:184` überschreibt `queue-on-size`
explizit auf `(void)`. Ohne beides läuft `wxtop.rkt`s Relayout-Kette
(`queue-on-size` → `resized`/`correct-size`) nie — Kind-Controls behalten ihre beim
letzten `set-size` berechnete absolute Position, unabhängig von der tatsächlichen
neuen Fenstergröße. Betroffen laut Doku: der ursprüngliche §21.6/§21.7-Fund selbst,
§25.1 (Preferences-Dialog öffnet mit unerreichbarer Button-Zeile, identisch auf
Windows **und** Linux reproduziert), sowie — als **positive** Divergenz, nicht als
Fix — macOS' zufällig ausreichende initiale Seed-Größe (§29).

**Advisor-Review vor jeder weiteren Messung korrigierte zwei Annahmen:**
1. `wxtop.rkt`s `(not (eq? 'unix (system-type)))`-Sonderfall in `queue-on-size` ist
   **kein** GTK-spezifischer Tuning-Knopf — `system-type` meldet das Betriebssystem,
   nicht das GUI-Backend, betrifft also gtk **und** qt auf Linux gleichermaßen. Er
   **deaktiviert** den `already-trying?`-Schutz auf Linux komplett (jeder
   `queue-on-size`-Aufruf requeued `resized` bedingungslos) — der am
   **wenigsten** abgesicherte Pfad, nicht ein Beleg für sichere Precedent.
2. Root Cause 2 aus dem historischen Fix-Versuch (Windows' modale
   `WM_ENTERSIZEMOVE`/`WM_SIZING`-Nachrichtenschleife blockiert den Pump während des
   Ziehens, wodurch sich Resize-Schritte aufstauen und nach Loslassen "abgespielt"
   werden) ist **Windows-spezifisch** — X11s `ConfigureNotify` kennt keine
   vergleichbare modale Schleife. Das ist kein Beleg, dass Linux automatisch sicherer
   ist, nur dass dieser **eine** historische Fehlermodus hier vermutlich nicht
   zutrifft; das verbleibende Risiko (Fix-Versuch 1: Rückkopplungsschleife über
   asynchrone natives Re-Entry) bleibt zu messen.

### Messung: konvergiert die synchrone Selbstkorrektur-Schleife?

Instrumentiert (`PLT_QT_DEBUG_RESIZE`, `wxtop.rkt`s `resized`/`queue-on-size`,
temporär, seither per `git checkout` vollständig zurückgenommen — `git status`
danach sauber). **Bewusst ohne jede Shim-/`wx/qt/`-Änderung** — der Trigger läuft
über einen bereits bestehenden, erreichbaren Shared-Code-Pfad
(`reflow-container` nach dynamischem Hinzufügen von Kindern → `child-redraw-request`
→ `self-redraw-request` → `force-redraw` → `resized`), nicht über ein natives
Resize-Event.

**Probe (`examples/resize-reflow-probe.rkt`, bleibt als Diagnose-Hilfsmittel
bestehen):** Frame 400×300, `vertical-panel%`, 20 Buttons nacheinander hinzugefügt
(erzwingt bei jedem Schritt ein Wachstum des Panel-Minimalbedarfs über die aktuelle
Fenstergröße hinaus). Ergebnis: **jede einzelne Korrektur konvergiert in genau einem
zusätzlichen Durchlauf** — `resized` erkennt `new ≠ correct`, setzt `already-trying?
#t`, korrigiert per `set-size`, setzt `already-trying? #f` zurück, ruft sich direkt
rekursiv erneut auf, findet beim zweiten Durchlauf `new = correct` (`tried-sizes`
kehrt von 1 zurück auf 0) — kein einziger Fall über eine Ebene Rekursion hinaus, in
20 unabhängigen Auslösungen. **Die rein synchrone Selbstkorrektur-Schleife
konvergiert sauber** — das war angesichts der Konstruktion von `correct-size`
(berechnet die Zielgröße direkt in einem Schritt, kein iteratives Annähern) auch zu
erwarten, ist damit aber empirisch bestätigt statt nur angenommen.

**Was diese Messung NICHT beantwortet:** das eigentliche historische Risiko
(Fix-Versuch 1) entsteht nicht durch diese synchrone Schleife, sondern dadurch, dass
jeder korrigierende `set-size`-Aufruf **auch das native Fenster** verändert — sofern
`resizeEvent` verdrahtet wäre, würde das eine **zusätzliche, asynchrone** native
Benachrichtigung auslösen, die `resized` ein weiteres Mal von außen anstößt, **nachdem**
`already-trying?` bereits zurückgesetzt wurde. Diese Probe ruft nie ein natives Resize
aus und kann diesen Pfad daher strukturell nicht prüfen — er bliebe nur durch
tatsächliches Verdrahten von `RacketWindow::resizeEvent` (Shim-ABI-Änderung, Regel
3/Regel 8, erzwingt Rebuild auf allen drei Maschinen beim nächsten Pull) messbar.

### Entscheidung: hier gestoppt, keine Shim-Änderung versucht

Zwei historische volle Rollbacks, eine Shim-ABI-Änderung mit Rebuild-Zwang auf allen
drei Maschinen, und ein verbleibendes, nur per echtem natives Resize (inkl. Live-Drag,
der beim ersten historischen Versuch zum Rückkopplungsloop führte) messbares Risiko —
das ist eine Architekturentscheidung mit echtem Rückschlagpotenzial, kein Kandidat für
einen stillschweigenden dritten Versuch in derselben Sitzung. Die synchrone
Konvergenz-Messung ist ein vollwertiges Teilergebnis (entkräftet eine der beiden
Sorgen aus der Historie), aber **kein** Beleg, dass ein Shim-Fix diesmal glatt liefe.
Nutzer-Rückfrage vor dem nächsten Schritt (weiter mit Shim-Wiring vs. hier parken)
folgt separat.

**Kein Commit für die Messung selbst** (Instrumentierung vollständig zurückgenommen);
`examples/resize-reflow-probe.rkt` als neue, dauerhafte Diagnose-Probe hinzugefügt.

---

## Block B, Fortsetzung — dritter Fix-Versuch (`resizeEvent`), neuer Fund: kein Crash, aber Reflow bleibt aus

**Nutzer-Entscheidung (nach Rückfrage):** vorsichtiger Versuch — nur diskrete Resizes
(`xdotool windowsize`, kein Live-Drag), sofortiger Rollback bei erstem Anzeichen von
Problemen.

### Umsetzung

Drei additive Änderungen, alle nach dem Muster bestehender Shim-Funktionen (Regel 2,
kein Shared-Code-Touch):

1. **`shim.cpp`:** `RacketWindow` bekommt ein `resizeEvent`, das (wie `closeEvent`)
   nur einen Callback aufruft — `resize_cb`/`resize_ud`, gesetzt über eine neue
   Setter-Funktion `shim_window_set_resize_cb` (Muster: `shim_canvas_set_mouse_cb`
   & Co.), nicht über den `shim_window_create`-Konstruktor. Bewusst **kein**
   Äquivalent zu win32s `constrained-reply`/`pre-event-sync`-Pump-Keepalive-Schleife
   im nativen Handler — die existiert dort, um Windows' modale
   `WM_SIZING`-Nachrichtenschleife zu überleben, die den Pump blockiert; X11-Resize
   hat keine solche modale Schleife, `shim_pump` drainiert den normalen Qt-Event-Loop
   während eines Resizes durchgehend weiter.
2. **`shim.cpp`, neu — nicht ursprünglich geplant:** `shim_window_get_size` (Live-
   Query der tatsächlichen `RacketWindow`-Größe). Nötig, weil `wx/qt/window.rkt`s
   `get-width`/`get-height` reine Racket-seitige Caches sind, nur durch expliziten
   `set-size`-Aufruf aktualisiert (anders als win32, das live `GetWindowRect`
   abfragt) — ohne das würde `wxtop.rkt`s `resized` immer die veraltete, zuletzt
   gesetzte Größe sehen und einen echten nativen Resize nie bemerken.
3. **`wx/qt/frame.rkt`:** toten `(define/override (queue-on-size) (void))`-Stub
   entfernt (durch `make-top-container%`s spätere Override ohnehin zur Laufzeit
   verdeckt, aber irreführend neben dem neuen Aufrufer); `resize-cb` nach demselben
   Muster wie `close-cb` (nur `qt-queue-window-event` posten, niemals synchron
   aufrufen — Regel 2); `get-width`/`get-height`/`get-client-size`/`get-size`
   überschrieben, um live über den neuen Shim-Call abzufragen (nur `frame%` —
   Kind-Widgets haben ausschließlich Racket-gesteuerte Geometrie, kein Qt-
   Layout-Manager beteiligt, ihr Cache kann nie veralten).

Smoke 3/3 + 3/3 nach jeder der drei Änderungen einzeln geprüft, durchgehend grün.

### Messung 1 — Konvergenz/Stabilität bei echtem nativen Resize: sauber, kein Crash, keine Rückkopplungsschleife

`examples/live-resize-probe.rkt` (neu, bleibt bestehen): Frame 300×200,
`vertical-panel%` (stretchbar), ein Button. Mehrere `xdotool windowsize`-Aufrufe
(300×200 → 700×500 → 900×600 → 750×550, in verschiedenen Kombinationen über mehrere
Testläufe), dazwischen 3–12 Sekunden Beobachtung. **In keinem Testlauf:** Hänger,
Absturz, mehrfach nachfeuernde `resizeEvent`s, spürbare Verzögerung der übrigen
Eventspace-Verarbeitung. `shim_window_get_size`s Live-Wert folgte dem nativen Resize
in jedem Fall korrekt und sofort (z. B. `frame=700x500` einen Tick nach dem
`xdotool windowsize`-Aufruf). **Die historische Sorge aus Fix-Versuch 1/2 (§21.7) —
eine asynchrone Rückkopplungsschleife über wiederholt neu ausgelöste native Resizes —
ist unter X11 mit diskreten (nicht gezogenen) Resizes nicht aufgetreten.**

### Messung 2 — der eigentliche Zweck (Kind-Reflow) bleibt aus: neuer, unerwarteter Fund

Trotz korrekt aktualisierter `get-width`/`get-height` **reflowt der Button nie** —
er bleibt bei seiner ursprünglichen Größe (80×25), unabhängig davon, wie oft oder wie
stark die Fenstergröße nativ geändert wird. Mit `PLT_QT_DEBUG_RESIZE`-Instrumentierung
in `wxtop.rkt`s `resized`/`queue-on-size` (temporär, seither vollständig
zurückgenommen) präzise eingegrenzt:

- Der native `resizeEvent`-Callback (`resize-cb` in `frame.rkt`) feuert zuverlässig
  bei jedem `xdotool windowsize` (eigener Log-Print direkt im Callback, **vor** dem
  `qt-queue-window-event`-Aufruf).
- Der **gepostete Thunk selbst** (der `(queue-on-size)` aufrufen würde) läuft in der
  normalen Programmlaufzeit **nie** — sein eigener Log-Print (die allererste Zeile
  im Thunk-Körper, noch vor jedem Aufruf von `queue-on-size`) erscheint nicht, auch
  nach 20+ Sekunden Wartezeit nicht (mehrere Testläufe, kein Ausreißer).
- **Einmaliger, überraschender Gegenbeleg:** in einem Testlauf erschien dieser
  Log-Print doch noch — aber offenbar erst im Zuge des Prozess-Endes (der Thunk für
  den allerersten, konstruktionszeitlichen `resizeEvent` lief sichtbar **nach**
  Ablauf der eigentlichen Probe-Schleife, unmittelbar bevor der Prozess durch
  `timeout`/Kill beendet wurde) — kein Beleg für normale Verarbeitung, eher ein
  Hinweis auf einen möglichen Renne-erst-beim-Teardown-Mechanismus in der
  Eventspace-/Queue-Maschinerie.

**Nachträglicher Diskriminator-Test (nach Advisor-Hinweis, vor dem Doku-Commit):**
dieser Teardown-Hinweis wurde doch noch aufgegriffen, aber gezielt minimal statt
als neuer Hypothesen-Zyklus am `resizeEvent`-Pfad — ein eigenständiges,
resize-loses Skript in derselben Harness (`racket`, `PLT_QT=1`, Hauptthread in
einer `(sleep 1)`-Schleife über 15 Ticks): direkt nach dem Fenster-Show ein
einzelnes `(queue-callback (lambda () (eprintf "QUEUED CALLBACK RAN\n")))`
gepostet, dann 15×`(sleep 1)`, dann per `timeout 20` per SIGINT beendet. Ergebnis:
der Print erschien **nicht** während der 15 Ticks, sondern **erst nach** Tick 15,
unmittelbar im Zuge des `user break`/Prozessendes — exakt dasselbe Muster wie der
einmalige Gegenbeleg oben, jetzt aber komplett ohne `resizeEvent`, `frame.rkt`- oder
`shim.cpp`-Änderungen reproduziert. Das verschiebt die wahrscheinlichste Erklärung:
vermutlich läuft in dieser konkreten Harness (bloßes `racket`-Skript ohne
DrRacket-Idle-Betrieb) **generell** kein über `queue-callback`/`queue-event`
gepostetes Thunk während des normalen Betriebs, sondern nur bei Teardown/Interrupt
— unabhängig vom Auslöser. Die Behauptung weiter unten, ein aus `closeEvent`
gepostetes Thunk funktioniere „seit Monaten zuverlässig", stammt aus der
Projekt-Historie mit echtem DrRacket (anderer Harness, eigene Eventspace-Idle-
Maschinerie) und wurde in **dieser** Harness nicht gegengeprüft. Entsprechend
abgeschwächt in `docs/HACKING.md` §21.9/`CLAUDE.md`/`STATUS.md`: die Lücke könnte
resizeEvent-spezifisch sein, könnte aber auch ein allgemeines Harness-Artefakt
dieses bloßen-`racket`-Skript-Aufbaus sein — für eine künftige Session zu klären,
z. B. mit demselben Diskriminator, aber ausgelöst durch ein echtes `closeEvent` in
derselben Harness.
- Der **erste** `resized`/`set-panel-size`-Durchlauf, der in jedem Log auftaucht,
  läuft **vor** dem ersten geloggten `resizeEvent` ab — er stammt also nicht von
  dieser neuen Verdrahtung, sondern von einem bereits bestehenden, unabhängigen
  Konstruktions-/`add-child`-Pfad (`self-redraw-request`/`force-redraw`, s.
  Konvergenz-Vormessung oben). Die neue Verdrahtung selbst hat in keinem
  regulären Programmlauf einen einzigen sichtbaren Effekt erzielt.

**Root Cause nicht gefunden — Budget für diesen Teilbefund klar überschritten**
(deutlich mehr als die vorgesehenen zwei Hypothesen-Zyklen: FFI-Callback-Kontext,
Eventspace-Ziel, Racket-Klassendispatch/`inherit`-Hygiene und Timing wurden alle
geprüft und ausgeschlossen, ohne den eigentlichen Mechanismus zu finden, warum ein
über `qt-queue-window-event` aus `resizeEvent` heraus gepostetes Thunk in dieser
Harness während des normalen Betriebs nicht läuft — wobei der nachträgliche
Diskriminator-Test unten nahelegt, dass dies teilweise ein allgemeines
Harness-Artefakt statt eine resizeEvent-spezifische Eigenschaft sein könnte).
**Kein spekulativer Fix** (Regel 4).

**Sicherheits-Fazit (der wichtigste Teilbefund dieser Runde):** im Unterschied zu den
beiden historischen Fix-Versuchen ist **kein neuer Crash, kein Hänger und keine
Rückkopplungsschleife** aufgetreten — das native Verdrahten von `resizeEvent` selbst
ist, zumindest für diskrete (nicht gezogene) Resizes unter X11, beobachtbar sicher.
Das Scheitern dieser Runde ist ein „passiert nichts"-Befund, kein „geht kaputt"-Befund
— ein anderer, ungefährlicherer Fehlermodus als beide Vorgänger-Versuche.

### Entscheidung: vollständig zurückgerollt

`shim.cpp` (`resizeEvent`, `shim_window_get_size`, `shim_window_set_resize_cb`),
`wx/qt/frame.rkt` (Resize-Callback-Verdrahtung, Live-Geometrie-Overrides,
`queue-on-size`-Stub-Entfernung), `wx/qt/utils.rkt` (zwei neue FFI-Deklarationen) und
die `wxtop.rkt`-Diagnose-Instrumentierung vollständig per `git checkout`
zurückgenommen, Shim neu gebaut, Smoke 3/3 + 3/3 danach bestätigt grün. **Kein
Commit** — dieser Versuch bleibt vollständig ungetrackt im Git-Verlauf, exakt wie die
beiden historischen Versuche in §21.7.

`examples/live-resize-probe.rkt` (neu, bleibt als Diagnose-Probe bestehen — zeigt
ohne die zurückgerollte Verdrahtung wieder das ursprüngliche Symptom: `get-width`
bleibt konstant, `resizeEvent` wird nie gemeldet).

**Für eine künftige Session:** der erste sinnvolle Schritt ist jetzt, den
Diskriminator-Befund oben zu klären — mit einem echten `closeEvent` in derselben
bloßen-`racket`-Harness prüfen, ob dessen gepostetes Thunk **ebenfalls** erst beim
Teardown läuft (dann: allgemeines Harness-Artefakt, `resizeEvent` ist unschuldig)
oder ob es tatsächlich prompt während des normalen Betriebs läuft (dann: die
Asymmetrie ist real, und eine Instrumentierung von `queue-event`/
`eventspace-queue-proc` selbst (`wx/common/queue.rkt`), nicht nur der Aufrufseite,
sowie ein Vergleich des C++-Aufruf-Kontexts von `resizeEvent` vs. `closeEvent`
unter Qt/X11 wären die nächsten Schritte). Die additiven, für sich genommen
harmlosen Shim-Grundlagen (`shim_window_set_resize_cb`/`shim_window_get_size`-
Muster) sind hier im Report dokumentiert und leicht reproduzierbar, falls ein
künftiger Versuch sie erneut aufbauen möchte.

---

## Block B, Folgesession (gleicher Tag) — closeEvent-Diskriminator: Asymmetrie widerlegt, Messinstrument als Verdächtiger identifiziert

**Auftrag:** Nutzer bat explizit, den oben offen gelassenen Diskriminator-Test
durchzuführen — klären, ob ein aus `closeEvent` gepostetes Thunk in derselben
bare-`racket`-Harness tatsächlich prompt läuft (dann wäre die Asymmetrie zu
`resizeEvent` real) oder ebenfalls erst beim Teardown (dann harness-weit).

### Erster Versuch: `xdotool windowclose` — verworfen

Zwei Versuche, ein echtes `closeEvent` per `xdotool windowclose` auszulösen,
scheiterten: das Zielfenster verschwand beide Male komplett aus dem X11-Fenster-Baum
(`xwininfo -root -tree` zeigte danach nur noch die 1×1/3×3-Qt-Hilfsfenster, keine
`close-discriminator`-Top-Level-Zeile mehr), obwohl `RacketWindow::closeEvent`
`e->ignore()` aufruft und `WA_DeleteOnClose` auf `false` steht — ein echter
`WM_DELETE_WINDOW`-Roundtrip hätte das Fenster nicht zerstören dürfen. Weder der
`can-close?`-Print (per `define/augment`, pubment-Mechanismus in `mrtop.rkt`
korrekt identifiziert nach initialem `define/override`-Fehlversuch — `on-close`/
`can-close?` sind `pubment*`, nicht `override*`, s. `mrtop.rkt:77-80`) noch die
`close-cb`-Prints erschienen. Bewertung (Advisor-Review): `xdotool windowclose`
zerstört das X-Fenster auf WM-Ebene, ohne dass ein echtes Qt-`closeEvent` je entsteht
— dieselbe Automatisierungs-Kategorie wie die in Block A dokumentierte, ungeklärte
X11-Stacking-Eigenheit. Kein valider Diskriminator, verworfen statt eines dritten
WM-Trigger-Versuchs (Alt+F4/Titlebar-Klick laufen über denselben
`_NET_CLOSE_WINDOW`-Pfad).

### Zweiter Versuch: In-Prozess-Trigger über einen temporären Shim-Hook

Reliabler, X11-freier Trigger: `shim_window_request_close(void* win)`
(`qt-shim/src/shim.cpp`, temporär) ruft nicht direkt `close()` auf, sondern
verschiebt es per `QTimer::singleShot(0, rw, [rw]{ rw->close(); })` auf den
nächsten Event-Loop-Turn — dadurch läuft `closeEvent` unabhängig davon, welcher
Racket-Thread den Aufruf angestoßen hat, garantiert innerhalb von
`processEvents()`/`shim_pump`, genau wie bei einem echten Titelleisten-Klick. FFI-
Deklaration temporär in `utils.rkt` ergänzt (Muster wie `shim_window_show`). In
`wx/qt/frame.rkt`s `close-cb` zwei `eprintf`s ergänzt (C-Callback-Eintritt,
Thunk-Start) sowie ein `PLT_QT_DEBUG_SELFCLOSE=<Sekunden>`-gatetes Hintergrund-
Thread, das nach der angegebenen Verzögerung `shim_window_request_close` aufruft.

Alle drei Dateien vor der Änderung gehasht (`shim.cpp`: `e1a0f7a6…`, `frame.rkt`:
`44ce87d2…`, `utils.rkt`: `8f5b7ca0…`), nach dem Test per `git checkout --`
zurückgerollt und Hash-Identität erneut bestätigt; Shim neu gebaut.

**Testaufbau:** identische bare-`racket`-Sleep-Loop-Harness wie beim ersten
Diskriminator (`PLT_QT=1`, Hauptthread `(sleep 1)` × 20 Ticks), `PLT_QT_DEBUG_SELFCLOSE=4`.

**Ergebnis (ein Lauf, eindeutig, kein Ausreißer):**
```
[probe] tick 3 at 6174.267430
[close-disc] requesting close at 7172.392992
[probe] tick 4 at 7174.669970
[close-disc] C callback fired at 7179.709641      ← 7ms nach Anstoß, zuverlässig
[probe] tick 5 at 8175.404730
...
[probe] tick 20 at 23185.155496
[probe] loop finished, script body done
[close-disc] posted thunk STARTED at 24186.296078  ← ~1s NACH Hauptthread-Ende
```

Der native `close_cb` feuert zuverlässig und sofort. Das über
`qt-queue-window-event` geposteste Thunk startet aber **nicht** während der
verbleibenden 16 Ticks (~16 Sekunden) des laufenden Programms — es startet erst,
nachdem der Hauptthread seine eigene Sleep-Schleife vollständig beendet hat.
Identisches Muster wie beim ersten (resize-losen) Diskriminator und wie beim
`resizeEvent`-Befund aus Block B.

**Schlussfolgerung 1 — die Asymmetrie ist widerlegt, nicht nur unbestätigt:** die
ursprüngliche Behauptung „ein aus `closeEvent` gepostetes Thunk funktioniert seit
Monaten zuverlässig" hält in dieser Harness nicht. `resizeEvent` verhält sich
identisch zu `closeEvent` — beide sind keine Ausnahme von einem harness-weiten
Muster.

**Schlussfolgerung 2 — wichtiger, per Advisor-Review (die eigentliche Pointe dieser
Folgesession):** §21.7s ursprünglicher Befund stammt **nicht** aus einer
bare-`racket`-Probe, sondern aus echtem, laufendem DrRacket (Preferences-Dialog,
reproduziert dort **und** in einer isolierten Probe, s. CLAUDE.md §21.7). In echtem
DrRacket läuft die Eventspace-Queue nachweislich — Menüs, Buttons, `test-dock-size`
funktionieren alle über denselben Postings-Mechanismus. Der hier gemessene „Thunk
läuft erst, wenn der Hauptthread fertig ist"-Effekt kann die Preferences-Dialog-
Reflow-Lücke also **nicht** erklären. Er zeigt stattdessen: **das Messinstrument
dieser und der Block-B-Session — ein bare-`racket`-Skript mit einer
`(sleep 1)`-Hauptthread-Schleife — beobachtet die Eventspace-Queue in einem
Zustand, der mit echtem DrRacket-Betrieb nicht vergleichbar ist.** Das gilt explizit
auch für `examples/live-resize-probe.rkt` (Block B, identischer Sleep-Loop-Aufbau)
— dessen „Kind-Reflow bleibt aus"-Befund könnte teilweise durch dieselbe
Instrument-Schwäche verfälscht sein, statt ausschließlich durch eine echte
resizeEvent-Lücke. Die Sessions haben damit **nicht die §21.7-Root-Cause
gefunden, sondern dass das bisherige Werkzeug dafür ungeeignet ist** — ein
Instrument-Befund, kein Bug-Befund.

**Für eine künftige Session, in dieser Reihenfolge:**
1. Zuerst das Instrument reparieren: Resize/Reflow-Verhalten in einer Harness
   messen, die nachweislich sauber pumpt — echtes DrRacket (wie beim
   Original-§21.7-Fund) oder ein Skript, das statt `(sleep 1)`-Polling ein
   eventspace-freundliches Warten nutzt (`yield`/`sync` auf einen Eventspace-Idle-
   Indikator statt eines reinen Timers).
2. Erst danach ggf. einen vierten `resizeEvent`-Wiring-Versuch — mit einer Harness,
   die das Ergebnis nicht selbst verfälscht.
3. Offene Kernfrage zuerst beantworten: warum reflowt der Preferences-Dialog in
   echtem DrRacket nicht, obwohl dessen Eventspace-Queue nachweislich sauber läuft?

**Vollständig zurückgerollt** (kein Commit in `wx/qt/`/`shim.cpp`): `git status`
im Submodul und Umbrella (nur `qt-shim/`) nach Abschluss leer, Hashes aller drei
temporär geänderten Dateien identisch zur Baseline, Shim neu gebaut, beide
Smoke-Gates (3/3 ohne `PLT_QT`, 3/3 mit) grün.

---


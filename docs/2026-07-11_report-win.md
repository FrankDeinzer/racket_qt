# Report: 2026-07-11_prompt (Windows)

**Racket-Version (gemessen):** Welcome to Racket v9.2 [cs].

## 1. Zusammenfassung

`file-selector` (`get-file`/`put-file`) ist jetzt echt: ein `QFileDialog`, non-modal via
`open()` gezeigt (kein `exec()`, kein eigener `QEventLoop`), integriert in den
bestehenden `shim_pump()`/`yield`-Mechanismus — exakt derselbe Ansatz, den `dialog%`s
Modal-Show schon nutzt. Die Kernfrage der Sitzung (trägt `open()`+Signal+Pump ohne
`exec()`?) ist beantwortet: ja. Dabei ist ein echter, reproduzierbarer nativer Absturz
gefunden und gefixt worden (nicht nur gemessen) — Details unten und in
`docs/HACKING.md` §19. Zwei getrennte Commit-Paare (get-file; put-file), jeweils
Submodul zuerst, alle vier gepusht. Phase 3 (nativer Windows-Dialog) als Datenpunkt
gemessen: trägt ebenfalls. Cross-Platform (Linux/macOS) und die volle
Qt-eigen×nativ-Matrix bleiben, wie im Prompt vorgesehen, der nächsten Runde vorbehalten.

## 2. Phase 0 — Umgebung

- `racket --version` = v9.2 [cs] (gemessen).
- Beide Repos sauber und deckungsgleich mit `origin` zu Sessionsbeginn: Umbrella `main`
  @ `50bdf61` / gui-Submodul `qt-backend` @ `f92352e0` (Panel-Sizing-Fix +
  Modalitäts-Fix, Cross-Platform bereits abgeschlossen).
- `get-file`/`put-file`-Kontrakt gegen `wx/win32/filedialog.rkt` und
  `wx/gtk/filedialog.rkt` gelesen (nicht geraten): Signatur
  `(message directory filename extension filters style parent)`, `filters` =
  `(listof (list string? string?))`, Style trägt den Modus (`'get`/`'put`/`'dir`/
  `'multi`) als erstes Element plus den Rest des Nutzer-Styles.

## 3. Phase 1 — Qt-eigener Dialog, ÖFFNEN (get-file)

### 3.1 Mechanik (Kernfrage), gemessen

`QFileDialog::open()` (nie `exec()`) zeigt den Dialog window-modal an und kehrt sofort
zum Aufrufer zurück. Das Ergebnis kommt über `QDialog::finished(int result)`, das
während eines ganz normalen `shim_pump()`-Aufrufs feuert — bestätigt per gated
Debug-Log (`PLT_QT_DEBUG=1`): `finished result=1`/`selectedFiles.size=1` erscheinen im
Log direkt nach einem echten Nutzer-Klick auf "Öffnen", innerhalb desselben Pump-Takts.

### 3.2 Synchrone Hülle

- `shim_file_dialog_create` (neu, `qt-shim/src/shim.cpp`): erzeugt den `QFileDialog`,
  setzt `DontUseNativeDialog` (Standard: `true`, Qt-eigen), Directory/Filename/
  Extension/Filter, `AcceptMode`/`FileMode` je nach `mode` (0=open, 1=save), verbindet
  `finished` mit einer Lambda, die `selectedFiles()` liest und den Ergebnis-Callback mit
  Pfad (oder `NULL` bei Abbruch) aufruft, dann `deleteLater()`.
- `wx/qt/filedialog.rkt` (neu, gui-Submodul): `file-selector` disabled den Parent via
  `shim_widget_set_enabled` (Fix B, §18.3 — wiederverwendet, nicht neu gebaut), ruft den
  Shim auf, und blockiert per `(yield (semaphore-peek-evt done-sema))` — derselbe
  Mechanismus wie `dialog%`s `show` (`../common/dialog.rkt`) — bis der Ergebnis-Callback
  (via `queue-event`) `done-sema` postet.

### 3.3 Echter Bug: frischer Callback pro Aufruf ist auf Windows nicht sicher

Erste Implementierung übergab bei jedem `get-file`/`put-file`-Aufruf eine frische
Racket-Closure direkt als `_fun`-Callback-Argument. Gemessen mit echter Nutzer-
Interaktion (`examples/file-dialog-probe.rkt`, `PLT_QT_DEBUG=1`):

- **Lauf 1:** 1. Dialog (Accept) lief durch, **2. Dialog (Accept) crashte** — Windows
  Ereignisanzeige bestätigt `APPCRASH`/Ausnahmecode `c0000005` (Access Violation) für
  `racket.exe`, kein Racket-Backtrace (echter nativer Absturz).
- **Lauf 2** (nach Entfernen von Racket-seitigem I/O aus dem atomaren Callback-Pfad,
  siehe unten): 1. Dialog (Accept), 2. Dialog (Cancel) liefen sauber, **3. Dialog
  (2. Accept) crashte** — Callback-Adressen der drei Aufrufe lagen exakt 0x1E0 Byte
  auseinander (`...4040`, `...4220`, `...4400`), Indiz für einen kleinen,
  pro-Aufruf-allozierten nativen Trampolin-Slot.

Root Cause (gegen `foreign_procedures.html` und `ffi/unsafe.rkt` verifiziert): Racket-
CS-Callbacks sind **immer** atomic; `_cprocedure*`s Ctype-Konverter ruft
`make-ffi-callback` bei **jedem** Aufruf neu auf — keine Memoisierung nach
Prozedur-Identität, auch nicht für dieselbe Racket-Prozedur über mehrere Aufrufe hinweg.
Fix: genau ein `function-ptr`-Callback einmal beim Modul-Laden von `filedialog.rkt`,
Dispatch über eine als `ud` (`void*`) durchgereichte Ganzzahl-ID. Dabei ein zweiter,
kleinerer Stolperstein: ein `_fun`-typisiertes Shim-Parameter versucht bei **jeder**
Übergabe erneut zu wrappen, auch wenn schon ein fertiges Callback-Objekt übergeben wird
(`make-ffi-callback: contract violation, expected: procedure?, given: #<callback>`) —
gelöst, indem `shim_file_dialog_create`s `cb`-Parameter in `utils.rkt` als reines
`_pointer` deklariert ist statt als `_file_dialog_cb_t`. Volle Diagnose-Chronologie und
Code-Zitate: `docs/HACKING.md` §19.

### 3.4 Verifiziert (Checkpoint 1)

Nach dem Fix: **8/8 aufeinanderfolgende Öffnen-Zyklen** (jedes Mal eine andere Datei
gewählt, echte Nutzer-Klicks) grün, `cb`-Adresse im Log über alle 8 Aufrufe hinweg
identisch (Beweis für Trampolin-Wiederverwendung). Zusätzlich 5× Öffnen→Abbrechen —
alle grün, `#f` korrekt zurückgegeben. Parent-Frame während offenem Dialog sichtbar
disabled, danach wieder normal. Smoke 3/3.

### 3.5 Commits (get-file)

- gui-Submodul (`qt-backend`): `15dee9f9` — `filedialog.rkt` (neu), `platform.rkt`,
  `utils.rkt`. Gepusht.
- Umbrella (`main`): `a40ae55` — `qt-shim/src/shim.cpp` (`shim_file_dialog_create`),
  `examples/file-dialog-probe.rkt` (neu, nur "Open..."-Button), Submodul-Zeiger auf
  `15dee9f9`. Gepusht.

## 4. Phase 2 — SPEICHERN (put-file)

Dieselbe Mechanik mit `mode=1` (`AcceptSave`/`AnyFile`), bereits im Shim aus Phase 1
vorhanden. Racket-seitig war die einzige Änderung, den `'put`-Style-Bail-out aus
Commit 1 zu entfernen (siehe unten) — kein neuer Mechanismus.

### 4.1 Verifiziert (Checkpoint 2)

Nutzer-Test über `examples/file-dialog-probe.rkt`s "Save..."-Button: mehrfach
Speichern→Speichern (inkl. Overwrite-Warnung bei existierender Datei, Qt-eigenes
Standardverhalten) und mehrfach Speichern→Abbrechen — alle grün. Smoke 3/3.

**DrRacket-Abschluss-Verifikation (File → Open / Save) wurde in dieser Session NICHT
mehr durchgeführt** — der Prompt sieht das als Teil von Checkpoint 2 vor, aus
Zeitgründen aber auf den Probe-Treiber beschränkt; offener Punkt für die nächste
Windows-Session vor der Cross-Platform-Runde.

### 4.2 Commits (put-file)

- gui-Submodul (`qt-backend`): `19954ffd` — `filedialog.rkt` (`'put`-Bailout entfernt).
  Gepusht.
- Umbrella (`main`): `a773c8a` — `examples/file-dialog-probe.rkt` ("Save..."-Button),
  `docs/HACKING.md` §19, `CLAUDE.md`-Checkpoint-Tabelle, `STATUS.md`, Submodul-Zeiger
  auf `19954ffd`. Gepusht.

## 5. Phase 3 — Nativer Windows-Dialog (Datenpunkt)

`PLT_QT_NATIVE_FILE_DIALOG=1` (neuer Env-Schalter im Shim, analog `PLT_QT_DEBUG`, kein
neuer `get-file`/`put-file`-Parameter) kehrt `DontUseNativeDialog` um. Gemessen mit
echter Nutzer-Interaktion: **7/7 aufeinanderfolgende Öffnen-Zyklen** (Mix aus Auswählen
und Abbrechen) grün, dieselbe Callback-Adresse über alle 7 Aufrufe. **Ergebnis: der
native Windows-Common-Dialog trägt denselben non-modalen Mechanismus wie der Qt-eigene
— kein `exec()` nötig, kein Entziehen.** Als Stil-Option dokumentiert (`docs/HACKING.md`
§19); Qt-eigener Dialog (`DontUseNativeDialog=true`) bleibt der Standard-Pfad dieses
Backends, keine Kontrakt-Änderung.

## 6. Nutzer-Checkpoints

Die Sitzung war durchgehend interaktiv (Kollaborationsklausel des Prompts: "ein
Datei-Dialog will angeklickt werden"). Nutzer hat real interagiert bei: Checkpoint 1
(Öffnen, 8 Zyklen), Checkpoint 2 (Speichern + Abbrechen-Varianten), Phase 3 (nativer
Dialog). Vor jedem der vier Pushes (2× Submodul, 2× Umbrella) wurde per
`AskUserQuestion` einzeln bestätigt (CLAUDE.md Regel 7).

## 7. Offene Punkte / Out of Scope

- **Cross-Platform (Linux/macOS) + volle Qt-eigen×nativ-Matrix** — bewusst nächste
  Runde (vier Fälle pro Plattform), wie im Prompt vorgesehen.
- **DrRacket-Abschluss-Verifikation** (File → Open/Save in echtem DrRacket) — im Prompt
  als Teil von Checkpoint 2 vorgesehen, in dieser Session nicht mehr nachgeholt.
- `get-directory`/`get-file-list` (`'dir`/`'multi` im Style) bleiben Stub (`#f`) — nicht
  Teil des Scopes.
- Vorbestehende Nebenbefunde unverändert offen: macOS-Menüleiste (8 statt 9 Menüs),
  Linux-Resize unter KWin/X11, Windows-Toolbar-Icon-Timing.
- Rest von Checkpoint E (choice%/radio-box%/slider%/tab-panel%, Preferences-Dialog)
  weiterhin offen.

# Report: 2026-07-11_prompt (macOS, Cross-Platform-Validierung + zwei Bugfixes)

**Racket-Version (gemessen):** Welcome to Racket v9.2 [cs].

## 1. Zusammenfassung

Validierungssession für den auf Windows gebauten `file-selector` (`get-file`/`put-file`
via non-modalem `QFileDialog`, `docs/HACKING.md` §19), analog zur Linux-Session
(`docs/2026-07-11_report-linux.md`). Der Button-getriebene Kern-Wertpfad war sofort grün
(7/7 Zyklen). Die vorgesehene Abschlussverifikation (echtes DrRacket File → Open/Save)
crashte jedoch zunächst reproduzierbar (2/2) — anders als Linux' n=1-Abstürze. Ein
gezielter Discriminator-Test isolierte die Ursache auf den **Menü-Klick-Dispatch**, nicht
auf `file-selector` selbst, und führte zu zwei echten, unabhängigen Bugfixes in `wx/qt/`
(Commits `acc73108`, `caef3e9c`). Nach beiden Fixes: echtes DrRacket File → Open + Save As
+ ein zweiter File → Open bestätigt funktional. Ein dritter, unabhängiger Fund (htdp-lib
Preference-Contract-Verstoß + nachfolgender harter Crash beim Öffnen eines zweiten Tabs)
wurde untersucht, aber nicht gefixt — außerhalb des `file-selector`-Scopes, isolierter
Qt-Repro reproduziert ihn nicht, braucht den vollen DrRacket-Stack.

**Diese Session enthält Fix-Commits** (anders als die reine Linux-Validierung) — beide
ausschließlich in `wx/qt/`, cocoa/gtk/win32 nur als Referenz gelesen.

## 2. Phase 0 — Sync + Rebuild

- Vor dem Pull per `AskUserQuestion` bestätigt (CLAUDE.md Regel 7).
- gui-Submodul (`qt-backend`) ff-Pull `f92352e0` → `19954ffd` (enthält `15dee9f9` get-file,
  `19954ffd` put-file). Umbrella `main` war bereits auf `19954ffd` (kein Umbrella-Pull
  nötig, Diskrepanz zwischen den Ständen gab es nicht).
- Shim neu gebaut (`cmake --preset macos-arm64 -S qt-shim && cmake --build
  qt-shim/build/macos-arm64`): sauber, `shim_file_dialog_create` kam bereits über den
  vorherigen Umbrella-Pull, `filedialog.rkt` ist reines Racket-Glue.
- Bytecode neu (`racket -S third_party/gui/gui-lib -S third_party/draw/draw-lib -l raco
  -- make -l mred`), Re-Smoke 3/3 grün.
- Light Mode bestätigt (`framework:white-on-black-mode?` = `#f` in
  `~/Library/Preferences/org.racket-lang.prefs.rktd` — die bekannte Falle aus §16
  [`framework:color-scheme` zeigt hier ebenfalls `white-on-black`, ist aber nicht
  maßgeblich] beachtet).

## 3. Checkpoint 1/2 — Probe-Treiber, Button-Pfad

`examples/file-dialog-probe.rkt`, echte Nutzer-Interaktion, `PLT_QT_DEBUG=1`:

- 7 Zyklen über Buttons: 2× `get-file` erfolgreich (verschiedene Dateien), 1× `get-file`
  abgebrochen, 2× `put-file` erfolgreich, 2× `put-file` abgebrochen.
- Callback-Adresse (`cb=0x11f95f210`) über alle 7 Aufrufe und über den `get`→`put`-
  Moduswechsel hinweg identisch — bestätigt das Einmal-Trampolin-Fix (§19, Fund 2) auch
  auf macOS.
- Kein Crash. Smoke 3/3 weiterhin grün.

## 4. Checkpoint 2, erster Versuch — echtes DrRacket, reproduzierbarer Crash

`PLT_QT=1 PLT_QT_DEBUG=1 racket -S ... -l drracket`, geduldig bis zum vollständigen Start
abgewartet (Autosave-Recovery-Dialog erschien, sah unauffällig aus). **File → Open
crashte sofort, reproduzierbar (2/2, zwei unabhängige DrRacket-Starts).**

```
invalid memory reference.  Some debugging context lost
internal-error: terminated in atomic mode!
 at "internal-error"
 at #f
 at "call-with-empty-metacontinuation-frame-for-swap"
```

Kein `[qt-filedialog]`-Log vor dem Absturz in beiden Läufen — der Fehler lag **vor**
`get-file` selbst, nicht im Wertpfad, den diese Session validieren soll.

## 5. Discriminator — Menü-Dispatch isoliert (Probe-Skript erweitert)

Um „nativer Menü-Klick → `get-file`" von DrRackets Framework-/Recovery-Schicht zu trennen,
wurde `examples/file-dialog-probe.rkt` um einen eigenen `menu-bar%`/`menu%` mit
`menu-item%`-Einträgen erweitert (`Open via menu...`, `No-op`, später `Force GC`).

- **Vor dem Fix:** `get-file` über den Menüpunkt öffnete den Dialog gar nicht erst;
  stattdessen:
  ```
  generic:get-mred: target is not an instance of the generic's interface
    target: (object:menu-item% ...)
    interface name: wx<%>
    context...:
     .../wx/common/queue.rkt:436/487/639
  ```
  Der Fehler wurde zwar als Racket-Exception abgefangen und geloggt, tötete aber den
  Event-Pump-Thread und damit den ganzen Prozess (kein `ps aux`-Eintrag mehr danach).
- **Root Cause 1 (Commit `acc73108`):** `wx/qt/platform.rkt`s `id-to-menu-item` rief
  `(send id get-mred)` selbst auf, statt (wie gtk: Identität; wie win32: Hash-Lookup) die
  wx→mred-Auflösung dem generischen `wx->mred` in `wxtop.rkt`s `on-menu-command` zu
  überlassen. Fix: `(define (id-to-menu-item id) id)`.
- Nach Fix 1: `get-file`/`put-file` über den Menüpunkt liefen mehrfach sauber (Öffnen,
  Abbrechen). Der zusätzliche `No-op`-Menüpunkt (ohne Dialog) crashte aber **manchmal**
  — reproduzierbares Muster: funktioniert vor einem Dialog-Zyklus, crasht nach einem.
  Gleiches Fehlerbild wie oben (`contract violation ... object:menu%? given: #<garbage>`
  bzw. ein härterer nativer `invalid memory reference`, je nachdem wie viel GC bereits
  lief), diesmal in `wx/qt/menu.rkt:76` (`find-top-frame`-Kontext, benannt `cb`).
- **Root Cause 2 (Commit `caef3e9c`):** `menu.rkt`s `append` erzeugt pro Leaf-Item eine
  frische Callback-Closure `cb`, hält sie aber nirgends fest — nur die `QAction*`
  (`action`) landet in `item-table`. Ohne Racket-seitige Referenz ist `cb` sofort nach
  Rückkehr aus `append` für den GC freigegeben; die native `QAction` behält aber einen
  Zeiger auf den (jetzt möglicherweise toten) Trampolin. Exakt die Landmine, die
  `filedialog.rkt`s eigener Kommentar zu Fund 2 (§19) bereits für `file-selector`s
  eigenen Trampolin dokumentiert — hier aber in `menu.rkt`, für jeden normalen
  Menüpunkt. Fix: neues `retained-callbacks`-Hasheq (`id → cb`), befüllt in `append`,
  bereinigt in `delete`/`delete-by-position`.
- **Härterer Verifikationstest nach Fix 2:** ein expliziter `Force GC
  (collect-garbage)`-Menüpunkt hinzugefügt. Sequenz „Force GC → mehrfach No-op → Open via
  menu..." lief vollständig durch, kein Crash, 4 weitere `get-file`-Zyklen sauber.

Beide Fixe liegen ausschließlich in `wx/qt/` (kein Verstoß gegen die Guardrails: cocoa/
gtk/win32 nur referenzgelesen, keine Shared-Code-Änderung).

## 6. Checkpoint 2, zweiter Versuch — echtes DrRacket nach beiden Fixes

`PLT_QT=1 PLT_QT_DEBUG=1 racket -S ... -l drracket`, erneut gestartet:

- **File → Open:** Dialog erschien, Nutzer wählte eine Datei, Datei erschien im
  Definitions-Editor. Bestätigt.
- **File → Save As:** Dialog erschien, Nutzer tippte einen Namen, Datei landete korrekt
  auf Platte. Bestätigt.
- **Zweiter File → Open** (öffnet eine neue Registerkarte): lief ebenfalls sauber durch
  (drittes `[qt-filedialog]`-Log, Datei erschien im neuen Tab) — **bevor** ein dritter,
  unabhängiger Fund auftrat (Abschnitt 7).

Damit ist der eigentliche `file-selector`-Wertpfad (`get-file`/`put-file`, Button UND
Menü, Skript UND echtes DrRacket) auf macOS vollständig bestätigt.

## 7. Dritter, unabhängiger Fund — NICHT gefixt, außerhalb des Scopes

Nach dem zweiten erfolgreichen `File → Open` (neue Registerkarte) erschien im Log:

```
preferences:set: new value doesn't satisfy preferences:set-default predicate
  pref symbol: 'test-engine:test-dock-size
  given: '(1)
  ...
  test-engine/test-tool.rkt:267:8: remove method in test-panel%
  ...
```

gefolgt von einem sichtbaren „DrRacket Internal Error"-Fenster (sauber als `QMainWindow`
im Log erschienen) und **danach** einem harten, nativen Absturz (`invalid memory
reference … terminated in atomic mode!`).

**Root Cause der Preference-Verletzung** (`htdp-lib`, `test-engine/test-tool.rkt`, NICHT
`gui-lib`/`wx/qt/`): `test-panel%`s `remove`-Methode speichert unbedingt `(send parent
get-percentages)` in `test-engine:test-dock-size`, dessen Default-Prädikat exakt zwei
Elemente verlangt. Hat das Panel zum Zeitpunkt des Aufrufs nur noch ein sichtbares Kind,
liefert `get-percentages` `'(1)` — Contract-Verstoß. Plattformunabhängig, vorbestehend,
nicht Teil dieses Backends.

**Isolierter Qt-Repro reproduziert den harten Absturz NICHT:** `examples/tab-close-
crash-probe.rkt` (neu) baut die naheliegende Vermutung nach — `get-percentages` +
`delete-child` auf ein `panel:vertical-dragable%` mit nur noch einem Kind, dann
`collect-garbage`, dann ein neues Top-Level-`frame%` erzeugen und zeigen (mimikt die
Internal-Error-Dialog-Erzeugung). Lief mehrfach sauber durch, kein Crash. Der harte
Absturz braucht also mehr vom echten DrRacket-Kontext (vermutlich die konkrete
Widget-Struktur des echten Test-Panels mit eingebettetem Editor, oder den Aufruf-Stack
innerhalb der Exception-Behandlung selbst) — nicht mit einfachem Code-Lesen weiter
einzugrenzen, sondern nur mit gezielter Instrumentierung im echten DrRacket.

**Cheaper Zusatzhinweis (nicht mehr verfolgt):** Linux' bereits dokumentierte Crash A
(`docs/2026-07-11_report-linux.md` Abschnitt 6.1, `pre: arity mismatch …` beim ersten
Interaktionsversuch, n=1, nicht reproduziert) zeigt dasselbe Muster wie diese Sessions
Fund vor den beiden Fixes (kein `[qt-filedialog]`-Log, Absturz im Menü-Klick-Dispatch,
Kontext `wx/qt/queue.rkt:27:5`) — plausibel derselbe latente Bug (Fixes 1/2 oben), nur
dort GC-timing-abhängig statt reproduzierbar. Nicht verifiziert (kein Zugriff auf die
Linux-Maschine in dieser Session); Windows/Linux sollten diese beiden Fixes ziehen und
ihre bereits dokumentierten Crashes (Linux A/B, siehe `docs/HACKING.md` §19) als
möglicherweise dadurch behoben neu bewerten.

## 8. Guardrails eingehalten

- Kein `exec()`/`QEventLoop`, keine geschachtelte Schleife.
- cocoa/gtk/win32 nur referenzgelesen (für beide Fixes: `wx/gtk/procs.rkt`,
  `wx/win32/menu-item.rkt`), nicht verändert.
- Vor jedem Sync-Schritt per `AskUserQuestion` bestätigt.
- Beide Fixes wurden dem Nutzer vor der Umsetzung vorgelegt (`AskUserQuestion`), nicht
  auf eigene Faust entschieden.
- Der dritte Fund (htdp-lib) wurde untersucht (auf Nutzer-Wunsch, „jetzt noch weiter
  untersuchen"), aber NICHT gefixt — liegt außerhalb von `gui-lib`, der isolierte
  Qt-Repro reproduziert ihn nicht, weitere Verfolgung bräuchte gezielte Instrumentierung
  in einer eigenen Session statt weiteres Lesen von Shared-Code.
- Gated Diagnose bleibt gated (`PLT_QT_DEBUG`).
- Report-Header nutzt gemessene `racket --version`.

## 9. Commits & Stand

- gui-Submodul (`qt-backend`): ff-Pull `f92352e0` → `19954ffd`. Zwei neue lokale Commits:
  - `acc73108` — fix(qt): id-to-menu-item war fälschlich `get-mred`-aufrufend
  - `caef3e9c` — fix(qt): Menü-Item-Callbacks werden jetzt retained (GC-Fix)
  - **Noch nicht gepusht** — offene Entscheidung mit dem Nutzer (Drei-Maschinen-Sync,
    CLAUDE.md Regel 7/8).
- Umbrella (`main`): dieser Report, `docs/HACKING.md` §19 (macOS-Abschnitt), `STATUS.md`,
  `examples/file-dialog-probe.rkt` (Menü-Einträge erweitert),
  `examples/tab-close-crash-probe.rkt` (neu).

## 10. Nächste Schritte / offene Punkte

- **Push + Drei-Maschinen-Sync** für die beiden neuen Fixes (`acc73108`, `caef3e9c`) —
  mit dem Nutzer abstimmen, dann Umbrella-Zeiger nachziehen.
- **Windows/Linux sollten nach dem Sync ihre dokumentierten Abstürze (Linux Crash A/B,
  ggf. ein bisher unbeobachteter Windows-Fall) erneut versuchen** — plausibel durch
  dieselben Fixes behoben.
- **Dritter Fund (htdp-lib `test-engine:test-dock-size` + nachfolgender harter Crash)**
  bleibt offen für eine eigene, dedizierte Session mit gezielter Instrumentierung.
- Native Windows-Dialog / volle Qt-eigen×nativ-Matrix auf Linux/macOS: weiterhin bewusst
  nächste Runde (nicht Teil dieser Session).
- Rest von Checkpoint E (choice%/radio-box%/slider%/tab-panel%, Preferences-Dialog)
  weiterhin offen.

# HACKING — Qt-Backend Entwicklerhandbuch

Dieses Dokument beschreibt die nicht-offensichtlichen Regeln und Fallstricke beim
Erweitern des Qt-Backends (`wx/qt/`). Es richtet sich an jemanden, der eine neue
Widget-Klasse hinzufügen oder einen Fehler in der Klassen-Hierarchie debuggen will.

---

## 1. Die zentrale Invariante: `public*` vs. `override*`

Das ist das wichtigste Wissen aus dem Spike. Falsch angewendet erzeugt es kryptische
Racket-Fehler beim Laden.

Rackets GUI-Toolkit besteht aus mehreren übereinanderliegenden Schichten:

```
Nutzer-Code
    ↓
mred-Glue-Layer      (mrcanvas.rkt, mrtop.rkt, …)
    ↓
wx-Glue-Layer        (wxcanvas.rkt, wxtop.rkt, wxwindow.rkt, wxitem.rkt, …)
    ↓
Platform-Klassen     (wx/qt/frame.rkt, wx/qt/canvas.rkt, …)   ← wir
```

Jede Schicht fügt Methoden per Mixin hinzu. Der entscheidende Unterschied:

| Macro      | Bedeutung                                  | Regel für Platform-Klasse |
|------------|--------------------------------------------|---------------------------|
| `public*`  | Neue Methode wird von **dieser** Schicht definiert | **Darf NICHT** in Platform-Klasse stehen |
| `override*`| Überschreibt eine Methode aus **tieferer** Schicht | **Muss** in Platform-Klasse stehen |

**Warum?** `public*` schlägt fehl, wenn die Methode in der Basis bereits existiert
(„method already defined"). `override*` schlägt fehl, wenn die Methode in der Basis
**nicht** existiert („no method to override").

### Diagnostik

**Fehler `method already defined`** → die Methode wird von einem Glue-Layer via
`public*` hinzugefügt. Sofort aus der Platform-Klasse entfernen.

**Fehler `no method to override` / `inherit: method not in class`** → die Methode
wird von einem Glue-Layer via `override*` erwartet. In die Platform-Klasse aufnehmen.

**Vorgehen:** Den Fehler lesen, den Namen suchen in:

| Datei                          | Fügt via `public*` hinzu (Auswahl)                                                  |
|--------------------------------|-------------------------------------------------------------------------------------|
| `wxwindow.rkt` (wx-make-window%) | `get-container`, `set-container`, `get-window`, `get-top-level`, `dx`, `dy`, `ext-dx`, `ext-dy`, `has-focus?`, `char-to`, `skip-subwindow-events?`, `on-visible`, `queue-visible`, `on-superwindow-activate` |
| `wxitem.rkt` (make-item%)      | `min-width`, `min-height`, `x-margin`, `y-margin`, `stretchable-in-x/y`, `area-parent`, `set-area-parent`, `on-container-resize`, `force-redraw`, `get-info`, `get-min-size` |
| `wxtop.rkt` (make-top-container%) | `show-control`, `add-child`, `forget-child`, `add-border-button`, `position-for-initial-show`, `child-redraw-request`, `self-redraw-request`, `correct-size`, `set-panel-size`, `resized`, `call-show`, `handle-traverse-key`, `begin/end-container-sequence` |
| `wxtop.rkt` (wx-frame%)        | `get-the-menu-bar`, `get-mdi-parent`, `set-mdi-parent`, `handle-menu-key`           |
| `wxtop.rkt` (make-top-level-window-glue%) | `on-exit`, `is-act-on?`, `add-activate-update`, `get-act-date/seconds`, `get-act-date/milliseconds` |
| `wxme` (wx:editor-canvas%)     | `on-scroll-on-change`, `set-y-margin`                                               |

---

## 2. Klassen-Ketten der implementierten Widget-Klassen

Die Klassen-Kette läuft von außen (oben) nach innen (unten). Die Platform-Klasse steht ganz unten.

### frame%

```
make-top-level-window-glue%     (wxtop.rkt)
  wx-frame%                     (wxtop.rkt:715)
    make-top-container%         (wxtop.rkt)
      wx-make-container%        (wxwindow.rkt)
        wx-make-window%         (wxwindow.rkt)
          frame%                (wx/qt/frame.rkt)   ← Platform
            window%             (wx/qt/window.rkt)
```

### canvas%

```
make-canvas-glue%               (wxcanvas.rkt)
  make-control%                 (wxitem.rkt)
    canvas%                     (wxcanvas.rkt – canvas-mixin angewendet)
      canvas-mixin              (common/canvas-mixin.rkt)
        canvas-autoscroll-mixin (wxcanvas.rkt)
          base-canvas%          (wx/qt/canvas.rkt)   ← Platform
            window%             (wx/qt/window.rkt)
```

### button%

```
make-window-glue%               (wxwindow.rkt)
  wx-button-class               (wxitem.rkt)
    make-simple-control%        (wxitem.rkt)
      button%                   (wx/qt/button.rkt)   ← Platform
        window%                 (wx/qt/window.rkt)
```

---

## 3. Eventspace: Frames müssen registriert werden

Rackets `executable-yield-handler` wartet nach Ablauf des Hauptmoduls auf `(yield main-eventspace)`.
Der Eventspace gilt als „fertig" (→ Programm beendet), wenn kein Frame registriert ist.

**Regel:** `frame%.direct-show` muss `(register-frame-shown this on?)` aufrufen.
`frame%.show` muss `direct-show` delegieren (nicht `shim_window_show` direkt).

```racket
(define/public (direct-show on?)
  (register-frame-shown this on?)   ; ← hält den Eventspace am Leben
  (super show on?)
  (shim_window_show qt-handle (if on? 1 0)))

(define/override (show on?)
  (direct-show on?))
```

Symptom wenn vergessen: Das Programm startet, das Fenster erscheint vielleicht kurz,
aber das Programm beendet sich sofort ohne Fehlermeldung.

---

## 4. backing-dc%: Kontrakt `resume-flush` → `void?`

`resume-flush` (in `backing-dc%`, erbt von `dc-mixin`) hat den Kontrakt `(->m void?)`.

```racket
(define/override (resume-flush)
  (atomically
   (unless (zero? flush-suspends)
     (set! flush-suspends (sub1 flush-suspends))
     (when (zero? flush-suspends)
       (queue-backing-flush)))))    ; ← Rückgabewert propagiert nach oben!
```

`on-backing-flush` gibt immer `#t` zurück (nicht `void`). Wenn `queue-backing-flush`
diesen Wert weitergibt, bricht `resume-flush` seinen Kontrakt.

**Regel:** `qt-dc%.queue-backing-flush` muss explizit `(void)` zurückgeben:

```racket
(define/override (queue-backing-flush)
  (on-backing-flush           ; Rückgabewert absichtlich ignoriert
   (lambda (bm)
     (when (is-a? bm bitmap%)
       (let* (...)
         (shim_canvas_blit_argb ...)
         (shim_canvas_request_repaint ...)))))
  (void))                     ; ← macht den Rückgabewert zu void
```

Symptom wenn vergessen:
```
resume-flush: broke its own contract
  promised: void?
  produced: #t
  contract from: (class qt-dc%)
```

---

## 5. Eine neue Widget-Klasse hinzufügen — Checkliste

1. **Neue Datei** `wx/qt/meinwidget.rkt` erstellen, ähnlich `button.rkt`.
2. **Basisklasse:** `window%` (aus `window.rkt`).
3. **Nur Methoden definieren**, die von einem Glue-Layer via `override*` erwartet werden.
   Keine Methoden, die via `public*` hinzugefügt werden.
4. **Klassen-Kette ermitteln:** In der entsprechenden `wx*.rkt`-Datei nachschauen,
   welche Mixins angewendet werden. Typisch: `make-item%` + `make-simple-control%` oder
   `make-control%`.
5. **`window%` erweitern:** Wenn der Glue-Layer `override*` auf eine Methode anwendet,
   die noch nicht in `window%` steht, dort mit `define/public` + Stub ergänzen.
6. **In `platform.rkt` eintragen:** Statt `make-stub-class` die echte Klasse importieren
   und in der `platform-values`-Funktion an der richtigen Position platzieren.
7. **Testen:** `PLT_QT=1 racket examples/hello.rkt` → erst Klassen-Komposition prüfen
   (Ladefehler), dann Laufzeitverhalten.

---

## 6. Debugging-Kurzanleitung

| Symptom | Ursache | Fix |
|---------|---------|-----|
| `method already defined: X` beim Laden | `X` wird von Glue-Layer via `public*` hinzugefügt | `X` aus Platform-Klasse entfernen |
| `no method to override: X` beim Laden | Glue-Layer erwartet `X` via `override*`, fehlt in Basis | `X` in `window%` oder Platform-Klasse ergänzen |
| `inherit: no method X in class` | Glue-Layer erbt `X` via `inherit`, fehlt in Basis | Wie oben |
| Programm beendet sofort (kein Fehler) | `register-frame-shown` nicht aufgerufen | Siehe §3 |
| `resume-flush: broke its own contract` | `queue-backing-flush` gibt nicht `void` zurück | Siehe §4 |
| Fenster erscheint, aber kein Inhalt | `on-backing-flush` wird nicht aufgerufen oder Blit schlägt still fehl | `shim_canvas_blit_argb` + `shim_canvas_request_repaint` prüfen |
| Qt-DLL nicht gefunden | `Qt6Widgets.dll` nicht auf PATH | `C:\Qt\6.11.0\msvc2022_64\bin` in PATH aufnehmen |

---

## 7. `refresh` vs. `shim_canvas_request_repaint`

Diese beiden Operationen sind nicht dasselbe:

| | `queue-paint` / `refresh` | `shim_canvas_request_repaint` |
|---|---|---|
| Was | Führt Rackets paint-callback neu aus, updated Backing-Bitmap, blittet dann | Sagt Qt: „male dein Widget neu" (blittet nur die vorhandene Backing-Bitmap) |
| Wann | Wenn sich der Inhalt geändert hat (z. B. Klick-Zähler) | Nur nach einem abgeschlossenen Blit in `queue-backing-flush` |

**Regel:** `base-canvas%::refresh` muss `(send this queue-paint)` aufrufen, nicht direkt `shim_canvas_request_repaint`. Sonst sieht der Nutzer immer das alte Bild, egal wie oft er `(send canvas refresh)` aufruft.

---

## 8. Shim-Konventionen

- Alle Shim-Funktionen sind in `utils.rkt` via FFI gebunden.
- Der Shim-Handle (`void*`) wird im `handle`-Feld von `window%` gespeichert.
- Qt-Callbacks (`shim_callback_t`) sind FFI-Callbacks mit `#:atomic? #t`:
  sie dürfen **nur** Events in den Eventspace posten, keine Racket-Funktionen direkt aufrufen.
- `shim_canvas_request_repaint` gibt `#t` zurück (in Racket `1` / truthy) — dieser Wert
  muss in `queue-backing-flush` verworfen werden (→ §4).

---

## 9. Linux-spezifische Hinweise

### QPA-Plugin-Pfad

Qt lädt auf Linux das `xcb`-Plugin aus `<prefix>/plugins/platforms/`. Da die Shim-`.so` in den
Racket-Prozess geladen wird (nicht über einen Qt-eigenen Launcher), kennt Qt den Plugin-Pfad
nicht automatisch. Starten immer mit:

```bash
QT_PLUGIN_PATH=~/Qt/6.11.1/gcc_64/plugins \
  PLT_QT=1 racket -S third_party/gui/gui-lib ...
```

Oder in `~/.profile` / Shell-Konfiguration dauerhaft setzen. Ohne diesen Pfad scheitert
Qt mit „Could not load the Qt platform plugin 'xcb'".

### libxcb-cursor0

Das xcb-Plugin braucht `libxcb-cursor0`. Fehlt es, schlägt xcb mit einem Laufzeitfehler
fehl, obwohl die `.so` geladen wurde. Prüfen mit `dpkg -l libxcb-cursor0`; falls nötig:
`sudo apt install libxcb-cursor0`.

### Startup-CPU-Spike

Die ersten Sekunden (`ps %cpu`) zeigen 50–90 % — das ist Bytecode-Kompilation, kein Loop-Spin.
Instantane CPU nach ~12s: ~1 %. Vor CPU-Messungen Bytecodes vorkompilieren:
`PLT_QT=1 raco make -v third_party/gui/gui-lib/mred/mred.rkt`.

### Event-Loop (dritter Datenpunkt)

`shim_pump(0)` (kein Blockieren) funktioniert auf Linux mit Qt's glib/epoll-Backend genauso
sauber wie auf macOS — bestätigt „nie blockieren" als plattformübergreifende Invariante.
`shim_events_pending()` gibt auf Linux 0 zurück, damit Racket CS schlafen kann.

---

## 10. gui-lib-Merge-Angleich (1.78 → 1.80) — Lektionen

**Ziel-Commit finden ohne Upstream-Remote:** Das installierte System-Paket kennt seinen
exakten Quell-Commit — `raco pkg show` oder das `info.rkt` im installierten Paket
(`.../share/pkgs/gui-lib/info.rkt`) enthält `package-original-source` mit dem vollen Git-Hash.
Das ist ein hash-verifizierter Treffer, stärker als „neuester Tag" oder Branch-Tip-Raten.
Prüfen, ob dieser Commit bereits lokal per `git cat-file -t <hash>` vorliegt (z. B. weil
schon mal ein Remote gefetched wurde), bevor ein neuer Remote hinzugefügt wird.

**Merge ist meist konfliktfrei, wenn additive `wx/qt/**`-Dateien nie von Upstream berührt
werden** — bestätigt für den 1.78→1.80-Sprung (86 geänderte Dateien, 0 Konflikte, keine
davon in `wx/qt/`). Konflikte wären in `wx/platform.rkt` (Backend-Auswahl) und
`wx/win32|gtk|cocoa/*` zu erwarten, nicht in additiven Dateien.

**Nach einem Merge: `define-values`-Arity in `wx/platform.rkt` zuerst prüfen.** Neue
Upstream-Versionen fügen gelegentlich neue Werte an die `platform-values`-Tupel-Liste an
(z. B. `tab-panel-available?` in 9.2). Symptom: `define-values: result arity mismatch`
mit einer Liste aller bereits gebundenen Werte im Fehlertext — die fehlende letzte Zeile
in `qt/platform.rkt`s eigener `(values ...)`-Liste zeigt sich am Diff zur `define-values`-
Liste in `wx/platform.rkt`.

**Kontrakt-Verifikation gegen Referenz-Backends, nicht raten.** Für jeden neuen/fehlenden
Export lohnt sich `grep -rn "<name>"` über `wx/win32/` und `wx/gtk/` — die Fehlermeldung
allein (z. B. „arity mismatch", „no such method") sagt nicht, WAS die richtige Signatur
ist. Beispiele aus dieser Session:
- `get-current-mouse-state`: 0 Args, 2 Rückgabewerte (`point%`, Modifier-Liste) — nicht
  Box-Pointer wie zunächst angenommen.
- `file-selector`: neuer `filters`-Parameter zwischen `ext` und `style`.
- `gauge%`: Methodennamen sind `get-range`/`set-range`/`get-value`/`set-value`, NICHT
  `get-gauge-value`/`set-gauge-value` (letzteres war ein Ratefehler in einer früheren Session).
- `frame%`: `set-title` (dynamische Updates) ist eine andere Methode als `set-label`
  (Init-Titel) — beide nötig.
- `set-canvas-background`/`get-canvas-background`: Default ist `white`, nicht `#f`.
  `#f` wird von `mrcanvas.rkt` als „Canvas ist transparent" interpretiert und wirft einen
  Fehler, sobald irgendjemand versucht, eine Hintergrundfarbe zu setzen.

---

## 11. Key-Event-Kontrakt: Release braucht `'release`, nicht den echten Key

`key-event%`s `key-code`-Feld hat bei Tastatur-**Loslassen** einen Sonderwert: das Symbol
`'release`, NICHT den tatsächlich losgelassenen Key. Der echte Key gehört ausschließlich
in `key-release-code` (via `set-key-release-code`). Verifiziert gegen `win32/key.rkt`:

```racket
[e (new key-event%
        [key-code (if is-up? 'release key-id)]   ; ← Sonderwert bei Release!
        ...)]
(when is-up? (send e set-key-release-code key-id))
```

**Symptom bei falscher Implementierung:** Jedes getippte Zeichen erscheint doppelt — der
Editor behandelt Press UND Release je als eigenständigen Zeichen-Insert, weil beide
Events wie „normale" Presses aussehen. Betrifft NUR die Racket-Event-Konstruktion, nicht
den Shim/Qt — ein Debug-Print direkt im Qt-Key-Callback zeigt bereits hier exakt 1×
Press + 1× Release pro physischem Tastendruck.

---

## 12. `get-focus-window` muss echt sein — sonst frisst `handle-traverse-key` Sondertasten

`wxtop.rkt`s generisches `handle-traverse-key` (zuständig u. a. für `#\return`, `#\space`,
`escape`) fragt `(get-focus-window)` ab, um zu entscheiden, ob eine Taste an ein
fokussiertes Control (z. B. einen `editor-canvas%`) durchgereicht werden soll, statt sie
als Navigations-/Default-Button-Kommando zu behandeln. Ein Platform-Backend, das
`get-focus-window` hart auf `#f` stubbt (z. B. weil es für frühere Checkpoints nicht
gebraucht wurde), lässt DIESEN Fallback-Zweig **immer** greifen — mit dem Ergebnis, dass
z. B. Enter im Editor nie ankommt, obwohl `on-char` grundsätzlich korrekt verdrahtet ist.

**Fix-Pattern:** Fokus-Tracking generisch in der Basis-`window%`-Klasse verankern, nicht
pro Widget-Typ:

```racket
(define/public (on-set-focus)
  (let ([f (get-top-frame)])
    (when (and f (not (eq? f this))) (send f record-focus-window this))))
(define/public (on-kill-focus)
  (let ([f (get-top-frame)])
    (when (and f (not (eq? f this))) (send f clear-focus-window this))))
```

`get-top-frame` ist bereits für Layout-Zwecke vorhanden (läuft die Parent-Kette hoch) —
dieselbe Funktion liefert hier den Ankerpunkt fürs Fokus-Tracking. Vereinfachung ggü.
win32 (kein `focus-window-path`, kein OS-Aktiv-Fenster-Check): für Single-Frame-Szenarien
ausreichend, ggf. bei Multi-Fenster-Fokus-Edgecases nachschärfen.

**Diagnose-Technik, die zum Fund führte:** Temporärer `eprintf` direkt in
`dispatch-on-char` (zeigt `key-code`, `other-modal?`, `call-pre-on-char`-Ergebnis,
`enabled?`) — `pre=#t` bei einer Taste, die eigentlich durchgereicht werden sollte, ist
das Signal, in `call-pre-on-char` → `on-subwindow-char` → `handle-menu-key`/
`handle-traverse-key` (alle in `wxtop.rkt`) weiterzuverfolgen.

---

## 13. DrRacket-Invocation-Rezept (nach 9.2-Angleich)

Fork ist als Installation-scope-Link aktiv (`raco pkg update --link <pfad-zu-gui-lib>`,
braucht Admin-Rechte wegen `C:\Program Files\Racket\`). Danach reicht ein normaler Start:

```powershell
$env:PLT_QT = "1"
$env:PATH   = "C:\Qt\6.11.0\msvc2022_64\bin;" + $env:PATH
& "C:\Program Files\Racket\DrRacket.exe"
```

Kein `-S third_party/gui/gui-lib` mehr nötig (Fork ersetzt die System-Version direkt).
Gate-Test: DrRacket **ohne** `PLT_QT` muss weiterhin nativ ohne Linklet-Mismatch starten —
das beweist, dass der Fork sauber die System-Version ersetzt und nicht nur zufällig für
den Qt-Fall funktioniert.

**Single-Instance-Falle:** Ein zweiter `DrRacket.exe`-Aufruf, während bereits eine Instanz
läuft, startet KEINE neue Instanz — er verbindet sich an die laufende und beendet sich
sofort (Exit 0, kein Fenster, keine Log-Ausgabe). Sieht wie Erfolg aus, ist aber ein
No-Op. Vor jedem Testlauf mit `tasklist | grep -i drracket` prüfen, dass wirklich keine
alte Instanz mehr lebt.

**Autosave-Recovery beim Debuggen mit `taskkill /F`:** Jeder harte Prozess-Kill lässt
DrRacket beim nächsten Start einen Recovery-Dialog anbieten. Die tatsächlich gelesene
Datei ist `%APPDATA%\Racket\PLT-autosave-toc.rktd` (**ohne** `-save`-Suffix) —
`framework/private/autosave.rkt`s `restore-autosave-files/gui` liest exakt diese.
`PLT-autosave-toc-save.rktd` ist nur eine Rotations-Sicherung der vorherigen TOC und NICHT
die Recovery-Quelle (leicht zu verwechseln). Vor jedem Neustart in einer Debug-Session
beide auf `()` setzen, plus verwaiste `mredauto.*`-Dateien in `Documents\` löschen. Der
Recovery-Dialog selbst kann vom offenen Menüleisten-/Button-Rendering-Bug (siehe Ledger)
betroffen sein — keine sichtbaren Buttons zum Wegklicken.

---

## 14. Menüleiste — Titel-Kollaps (gefixt) vs. fehlende Blatt-Einträge (offen)

**Titel-Kollaps (behoben, `6083efc9`/`2c102e5`):** Ein leerer `QMenu`-Titel kollabiert
den ganzen Balken. `menu-bar% append` bekam den Titel, reichte ihn aber nie an den QMenu.
`QMenuBar::addMenu(QMenu*)` leitet den Item-Text aus dem Menütitel ab → leerer Titel =
0×0-Action-Rect = Balkenhöhe 0 auf allen drei Plattformen (gemeinsamer Racket-Pfad,
oberhalb der Plattform). Fix = Titel via `shim_menu_set_title` durchreichen; KEIN
Layout-Trigger, KEIN `setNativeMenuBar`, KEINE Geometrie-Reservierung. Diskriminator ist
die Action-TEXT-Länge (0×0-Rect), NICHT `QMenuBar::height()`.

**Klick-Bug — korrigierte Diagnose (2026-07-08_prompt-2, offen, NICHT gefixt):** Die
ursprüngliche Hypothese ("Klick auf Menütitel öffnet nie ein Dropdown, egal was im Menü
steht") war eine Artefakt-Beobachtung aus einem Testfall mit nur Blatt-Einträgen
(`examples/menu-frame.rkt`: File→Quit, sonst nichts). Der reale Befund an echtem DrRacket
ist präziser: Dropdowns **erscheinen** für Menüs, die mindestens ein Submenü enthalten
(z. B. File→„Open Recent"/„Save other", Edit→„Key Bindings"/„Modes") — aber NUR die
Submenü-Einträge sind sichtbar, reine Blatt-Items (New, Open, Save, Quit, Copy, …) fehlen
komplett. Menüs ganz ohne Submenü (nur Blatt-Items) zeigen gar keinen Dropdown, weil ihr
`QMenu` schlicht leer ist.

Root Cause (verifiziert, `wx/qt/menu.rkt` + `qt-shim/src/shim.cpp`): `menu%.append` ruft
für Submenüs `shim_menu_add_submenu` auf, das intern `QMenu::addMenu(sub)` aufruft — das
fügt die Action tatsächlich zum Menü hinzu. Für Blatt-Items ruft es dagegen
`shim_action_create` auf, das nur eine freistehende `QAction` erzeugt und ihr
`triggered`-Signal verbindet, sie aber **nie** per `QMenu::addAction()`/`insertAction()`
zum `qt-menu` hinzufügt. `grep -n addAction qt-shim/src/shim.cpp` liefert 0 Treffer.
Damit ist die Action zwar in Rackets `item-table` (für Enable/Check/Callback-Dispatch),
aber für Qt unsichtbar.

Verifiziert via `examples/menu-click-probe.rkt` (Modus `mixed`, gated hinter
`PLT_QT_DEBUG`): direkter `popup()`-Aufruf auf ein Menü mit nur Blatt-Item(en) zeigt NIE
ein `[PLT_QT_DEBUG] popup APPEARED`; derselbe Aufruf auf ein Menü mit Blatt-Item(en) UND
einem Submenü zeigt `popup APPEARED ... frameGeom=(...)` mit exakt einer Zeile Höhe (=
nur das Submenü). **Das ist der wahrscheinliche Root Cause für den Klick-Bug, aber
NICHT hier gefixt** (Spur 2, Guardrail dieser Session). Der Fix wäre voraussichtlich ein
fehlender `QMenu::addAction(action)`-Aufruf beim Erzeugen von Blatt-Items in
`shim_action_create` oder direkt danach in `menu%.append` — aber das ist eine Vermutung
aus Code-Lektüre + gezielter Verifikation, kein bestätigter Patch.

Nebenbefund (separat, nicht Root Cause des obigen): `QApplication::activeWindow()` ist
auf Windows bei einem per CLI gestarteten Racket-Prozess `NULL`, auch direkt nach
`frame.show()`. Direkte `popup()`-Aufrufe auf ein NICHT-leeres Menü zeigten in den Tests
kurz `popup APPEARED` und dann sofort `popup GONE` (ohne Nutzerinteraktion) — möglicherweise
zusammenhängend mit fehlendem Fenster-Fokus, aber nicht isoliert bestätigt. F10/Alt+F via
`SendKeys` an das Testfenster zeigte keine Wirkung — konfundiert mit demselben
`activeWindow=NULL`-Befund (SendKeys/`AppActivate` könnten das Fenster gar nicht erreicht
haben); Ergebnis daher **inkonklusiv**, nicht als "Tastatur-Aktivierung funktioniert nicht"
zu werten.

## 15. Menü-Blatt-Items (gefixt) + Popup-Positionierung (gefixt) — 2026-07-08_prompt-3

**addAction-Fix (`0be24d85`/`71b7347` gui/`main`):** Root Cause aus §14 bestätigt und
behoben. `shim_action_create` erzeugte die `QAction` ohne sie per `QMenu::addAction()`
zum Menü hinzuzufügen — Dropdown zeigte nur Submenü-Einträge, Blatt-Items (New, Open,
Save, Quit, Copy, …) fehlten komplett. Fix, gespiegelt am funktionierenden Submenü-Pfad
(`shim_menu_add_submenu`→`addMenu`): Signatur wird um den `menu`-Parameter erweitert
(`shim_action_create(menu, label, checkable, cb, ud)`), die Action wird mit `new
QAction(label, menu)` an ihr Menü **geparentet** (Lifetime — `QMenu::addAction`/
`QWidget::addAction` übernehmen laut Qt-Doku **kein** Ownership; ohne Parent wäre die
Action ein für immer freistehendes Leak, da `shim_menu_remove_action`→`removeAction()`
nur entfernt, nie löscht) und explizit per `menu->addAction(a)` eingefügt.
`menu.rkt`s `append` reicht `qt-menu` durch.

Verifiziert (gated `PLT_QT_DEBUG`, `examples/menu-click-probe.rkt`):
- `direct`: Blatt-only-Menü (File→Quit) → `popup actions().size()=1`, `action[0]
  text='Quit'`.
- `mixed`: New(Blatt) + Recent(Submenü) + Save(Blatt) → `actions().size()=3`, korrekte
  Reihenfolge `New, Recent(menu=1), Save`.
- `dynamic` (neu): Separatoren an richtiger Position, `checkable-menu-item%.check`
  spiegelt sich in `checked=1`, `enable #f` in `enabled=0`, `delete` reduziert
  `actions().size()` sichtbar (5→4) — alles am selben, weiterhin geöffneten `QMenu`
  gemessen (nicht über die Popup-Transition-Heuristik, die nur bei Sichtbarkeits-
  wechsel feuert — dafür gibt es jetzt `shim_menu_debug_dump(menu)`, gated,
  On-Demand-Dump von `actions().size()` + Enabled/Checked/Separator/Submenu je Action).
- Echtes DrRacket: File- und Edit-Menü zeigen alle Blatt-Items, Submenüs (Open Recent,
  Save Other, Keybindings, Modes), korrekt ausgegraute Items (Close Tab, Redo, Cut,
  Copy) und Checkmark (Wrap Text) — Screenshots in der Session, nicht im Repo abgelegt.
- Smoke 3/3 weiterhin grün, kein Ownership-Crash/-Warning beim normalen Schließen.

**mapToGlobal-Fix (`1641f888`/`8e0bfac` gui/`main`):** `client-to-screen` in
`wx/qt/window.rkt` war No-op (§CLAUDE.md-Flag) — `popup-menu` öffnete Kontextmenüs an den
rohen lokalen statt den Bildschirmkoordinaten. Neue Shim-Funktion
`shim_widget_client_to_screen(widget, x, y, *out_x, *out_y)` ruft
`QWidget::mapToGlobal(QPoint(x,y))`; FFI-Binding nutzt das `_ptr o`-Out-Parameter-Idiom
(`(_fun _pointer _int _int (out-x : (_ptr o _int)) (out-y : (_ptr o _int)) -> _void ->
(values out-x out-y))`). `window%`s `client-to-screen` ruft das auf `handle` auf (No-op
bleibt nur, wenn `handle` `#f` ist, z. B. bei `menu%`/`menu-bar%`, die nie
`client-to-screen` aufrufen). DPR ist auf 1 gepinnt (`QT_SCALE_FACTOR=1` in
`shim_app_init`) — device-independent px konsistent auf beiden Seiten, kein
Multi-Monitor-Skalierungs-Sonderfall hier. `screen-to-client` bleibt No-op — wird nur vom
`wx/proxy<%>`-Sibling-Remapping-Pfad (`wxwindow.rkt`) genutzt, von keinem Widget dieses
Backends bisher ausgelöst.

Verifiziert: Rechtsklick im Definitions-Editor von echtem DrRacket öffnet das
Kontextmenü jetzt direkt am Klickpunkt (window-relative (400,300) → Menü erscheint bei
~(403,304)) statt am Fensterrand. `window.rkt` musste neu `"utils.rkt"` requiren (fehlte
vorher — kein Zirkularproblem, `utils.rkt` requirt nichts aus `wx/qt/`).

## 16. Redraw-Bug — bestätigt + gefixt (Windows, 2026-07-10_prompt); Linux + macOS validiert, auf allen drei Plattformen geschlossen

**Symptom:** In echtem DrRacket wird beim Tippen nur die zuletzt bearbeitete Zeile
angezeigt; alle vorherigen Zeilen erscheinen weiß, obwohl sie im Editor-Puffer noch
vorhanden sind (Undo/Ausführen funktionieren normal — reiner Anzeigefehler).

**Vier gated Diskriminatoren** (hinter `PLT_QT_DEBUG`, additiv, bleiben im Code wie die
bestehende Menü-Diagnose — `qt-shim/src/shim.cpp` `paintEvent`/`shim_canvas_blit_argb`,
`wx/qt/canvas.rkt` `refresh`/`flush`/`begin-`/`end-refresh-sequence`/`queue-backing-flush`):

1. **`paintEvent`: angeforderte vs. tatsächlich geblittete Region.** Qt fordert beim
   Editor-Repaint durchgehend `requested=(0,0 1400x436)` an; unser Code blittet immer
   `(0,0 width x height)` — deckungsgleich (die 16px-Differenz ist Rand-Toleranz). Kleinere
   angeforderte Regionen (z. B. `(0,27 30x3)` bei Toolbar-Icons) werden ebenfalls immer
   voll und nicht unterdimensioniert geblittet. → **(A) „Blit-Region zu klein" widerlegt.**
2. **Backing-QImage-Größe + Zeitpunkt bei jedem `shim_canvas_blit_argb`.** Über mehrere
   hundert Zyklen (inkl. reinem Caret-Blinken alle ~500 ms) bleibt die Größe für die
   Editor-Canvas konstant bei der vollen Widget-Größe (z. B. `1416x436`, nach Resize
   `1416x603`) — nie eine Teilgröße. Ein zweiter, unabhängiger 69×19-Kanal (vermutlich ein
   Toolbar-/Caret-Widget) läuft mit fester eigener Größe daneben. → **(B) im Sinne
   „QImage falsch dimensioniert" widerlegt** — die Größe stimmt immer.
3. **Racket-seitige Aufrufkette.** Jeder Editor-Repaint — auch der reine Caret-Blink,
   nicht nur Tastatureingabe — durchläuft vollständig `refresh → queue-paint →
   queue-backing-flush → on-backing-flush (proc fired, volle Bitmap-Größe) → blit_argb →
   request_repaint`. Der direkte `flush`-Pfad (`request_repaint` ohne frischen Blit) feuert
   ausschließlich für kleine Toolbar-Widgets in den ersten ~4s nach Start (50× beobachtet,
   nie für die Editor-Canvas). → **(C) „falscher Repaint-Trigger" für den Editor-Bereich
   widerlegt.**
4. **Fenster minimieren + wiederherstellen (erzwingt vollen Expose).** Symptom bleibt
   unverändert — die weißen Zeilen kommen nicht zurück, obwohl derselbe volle
   `(0,0 1400x436)`-Zyklus erneut durchläuft. Spricht gegen eine reine Trigger-Frage (ein
   erzwungener zusätzlicher voller Expose ändert nichts) und für einen strukturellen
   Bitmap-Lifecycle-Fehler, der bei **jedem** Zyklus neu auftritt — auch bei ohnehin schon
   „vollen" Zyklen.

**Root-Cause-Kandidat (Code-Vergleich mit win32/gtk/cocoa, NICHT gefixt):**
`wx/qt/canvas.rkt`s `begin-refresh-sequence`/`end-refresh-sequence` sind reine `(void)`
No-ops. Bei win32 (`wx/win32/canvas.rkt:327-330`) und gtk (`wx/gtk/canvas.rkt:644-647`)
verdrahten beide Methoden `(send dc suspend-flush)` / `(send dc resume-flush)` — cocoa
folgt demselben Muster über `start-backing-retained`/`end-backing-retained`. Zusätzlich
rufen win32 und gtk direkt nach der `dc`-Erzeugung einmalig `(send dc
start-backing-retained)` auf (`wx/win32/canvas.rkt:266`, `wx/gtk/canvas.rkt:672`) — im
Qt-Backend fehlt dieser Aufruf komplett (`grep` über `wx/qt/canvas.rkt` liefert keinen
Treffer für `start-backing-retained`).

Ohne diese Klammerung bleibt `retained-counter` in `backing-dc%`
(`wx/common/backing-dc.rkt`) permanent bei 0, sodass `on-backing-flush` bei **jedem**
`release-cr` sofort in den `else`-Zweig läuft und `reset-backing-retained` aufruft — das
setzt `retained-cr` und die interne Bitmap-Referenz auf `#f` zurück. Der nächste `get-cr`-
Aufruf legt dadurch zwangsläufig eine **neue, leere** Bitmap an (`make-backing-bitmap`
über `get-backing-size`). Wenn eine Teil-Invalidierung (z. B. nur die Caret-/aktuelle
Zeile, wie bei reinem Blinken) davon ausgeht, dass der Rest der vorherigen Bitmap noch
gültig ist — was bei win32/gtk/cocoa dank der offenen `retained`-Sitzung zutrifft —, trifft
das im Qt-Backend nicht zu: die Bitmap ist zu diesem Zeitpunkt bereits leer, nur die neu
gezeichnete Teil-Region bekommt Inhalt, der Rest bleibt weiß. Das erklärt Messung 1-4
vollständig und konsistent (volle Größe + voller Trigger-Zyklus, aber nur teilweise
gefüllter Inhalt).

**Einordnung zu den 4 Original-Hypothesen:** am nächsten an (D) „Racket invalidiert nur
Teilregion" — ergänzt um den strukturellen Befund, warum das bei diesem Backend (anders
als bei win32/gtk/cocoa, die dieselben Teil-Invalidierungen unschädlich verarbeiten)
sichtbare Lücken hinterlässt.

**Fix (Windows, verifiziert, 2026-07-10_prompt) — vier Änderungen, nicht zwei:**
Der oben skizzierte 2-Schritt-Fix (`start-backing-retained` + `suspend-/resume-flush`)
reichte **allein nicht** — angewendet ohne die beiden folgenden Ergänzungen rendert
bereits der normale Programmstart (vor jeder Eingabe) einen komplett leeren Editor statt
`#lang racket`. Der vollständige Fix in `wx/qt/canvas.rkt`:

1. `(send dc start-backing-retained)` einmalig direkt nach der `qt-dc%`-Erzeugung.
2. `begin-refresh-sequence`/`end-refresh-sequence` auf `(send dc suspend-flush)` /
   `(send dc resume-flush)` verdrahtet.
3. **Zusätzlich nötig:** `(send dc reset-backing-retained)` im `set-size`-Override, direkt
   nach `shim_widget_set_geometry`. Ohne das bleibt die jetzt retained Bitmap für immer auf
   der Größe eingefroren, die beim allerersten `get-cr`-Aufruf existierte — typischerweise
   ein winziger Platzhalter (30×30, 1×1), lange bevor Racket das Layout zuweist. win32/gtk
   lösen das über ihre eigenen Resize-Hooks (`on-resized` bzw. `internal-on-client-size`
   → `reset-dc` → `reset-backing-retained`); im Qt-Backend ist `set-size` (von Rackets
   Layout-Engine aufgerufen) die analoge Stelle.
4. **Zusätzlich nötig:** die `(define dc (new qt-dc% ...))`-Zeile musste vor den
   Konstruktor-Seed-Aufruf von `set-size` verschoben werden (`base-canvas%`s Konstruktor
   ruft `set-size` bereits einmal auf, bevor `dc` in der Ursprungsreihenfolge definiert
   war) — sonst `dc: undefined; cannot use field before initialization` beim Start
   (Racket-Klassenfeld-Ordering, kein Qt-Problem).

**Diskriminator, der den Fix bestätigt:** `bm=`-Größe in den `on-backing-flush`-Logs
wächst jetzt mit dem Inhalt (z. B. `854x316` → `854x377` → `854x437` bei sechs
nacheinander getippten Zeilen) statt bei jedem Zyklus auf eine winzige Platzhaltergröße
zurückzufallen. Verifiziert: identischer Tipp-Repro (alle Zeilen bleiben sichtbar),
Resize, Minimieren/Wiederherstellen, Smoke 3/3. Report: `docs/2026-07-10_report-win.md`.

**Linux-Validierung (2026-07-10, `docs/2026-07-10_report-linux.md`): grün.** ff-Pull auf
`qt-backend` `04935cb6` (Diff geprüft — exakt die vier oben beschriebenen Änderungen,
keine zusätzlichen), Shim war bereits aktuell (Fix ist rein Racket-seitig, `shim.cpp`
unverändert), Bytecode neu, Smoke 3/3 grün. Identischer Tipp-Repro (synthetische
Keystrokes via selbstgebautem XTest-Helfer, da `xdotool` auf dieser Maschine fehlt) in
echtem `PLT_QT=1`-DrRacket: alle sechs getippten Zeilen + `#lang racket` bleiben sichtbar,
Debug-Log zeigt `begin-refresh-sequence -> suspend-flush` / `end-refresh-sequence ->
resume-flush` aktiv feuernd. Light Mode bestätigt (`racket-prefs.rktd`:
`color-scheme-light` = `classic`, kein `os`-Wert). Zusätzliche Resize-/Minimieren-Sicht
war auf dieser Maschine methodisch nicht sauber möglich (siehe unten) und liefert daher
kein belastbares Ergebnis — die eigentliche Validierung (Tipp-Repro) ist unabhängig davon
eindeutig grün.

**Resize-Pfad auf Linux NICHT validiert (Ursache ungeklärt, kein Fix-Anlass, aber auch
keine Entwarnung):** ein roher `XResizeWindow`-Aufruf (ohne WM-Resize-Geste, nur zum
Testen synthetisiert, da `xdotool` fehlt) vergrößerte das X-Fenster serverseitig, löste
aber **keinen** `set-size`/`shim_widget_set_geometry`-Aufruf im Debug-Log aus — Qt hat die
Größenänderung nachweislich nie verarbeitet. Der Screenshot zeigt dadurch doppelten/
versetzten Inhalt. Die naheliegende Erklärung „reines X11-Test-Artefakt ohne
WM-Vermittlung" ist **nicht schlüssig**: KWin (`kwin_x11`) läuft als EWMH-WM auf dieser
Maschine und relayt `XResizeWindow` auf gemanagte Top-Level-Fenster normalerweise sehr
wohl per `ConfigureNotify`; außerdem zeigte `xwininfo` vorher `Backing Store State:
NotUseful` + `NorthWestGravity` — das erklärt kein serverseitiges Duplizieren von Inhalt
in den neu exponierten Bereich. Kurz: warum Qt nichts verarbeitete UND wieso trotzdem ein
kohärentes zweites Bild erschien, ist **nicht rekonstruiert**. Minimieren/Wiederherstellen
über eine korrekte ICCCM-Anfrage (`XIconifyWindow`/`XMapWindow`, Map-State-Wechsel
technisch bestätigt) zeigte danach unverändert denselben bereits verzerrten Zustand — auch
das nicht weiter aufgeklärt. **Resize/Minimieren-Verhalten auf Linux bleibt damit offen**,
unabhängig vom (validierten) Tipp-Repro-Ergebnis. Für eine saubere Diskriminierung bräuchte
es einen echten EWMH-Resize (`_NET_MOVERESIZE_WINDOW` ans Root-Fenster) oder `xdotool`,
keins davon in dieser Session nachgerüstet.

**macOS-Validierung (2026-07-10, `docs/2026-07-10_report-macos.md`): grün.** ff-Pull auf
`qt-backend` `04935cb6` (Diff geprüft — exakt die vier oben beschriebenen Änderungen, kein
`shim.cpp`-Anteil), Shim bereits aktuell, Bytecode neu, Smoke 3/3 grün. Echte
CGEvent-synthetisierte Keystrokes (System Events' `click at` bewegte den Fokus nicht in den
Qt-Canvas — eigener kleiner CoreGraphics-Klick-Helfer nötig, analog zum Linux-XTest-Helfer)
in `PLT_QT=1`-DrRacket: alle sieben Zeilen (`#lang racket/base` + 6× `define`) bleiben
sichtbar, Debug-Log zeigt `begin-/end-refresh-sequence -> suspend-/resume-flush` aktiv
feuernd, `bm=`-Größe bleibt bei voller Widget-Größe. Zusätzlich verifiziert: Resize,
Occlusion-Zyklus (Fokus weg/zurück). Minimieren via Accessibility technisch nicht sauber
ansteuerbar (Qt-Fenster exponiert `AXMinimizeButton` nicht vollständig) — Occlusion-Zyklus
deckt denselben Expose-Pfad ab.

**Theme-Diagnose-Lektion (wichtig für künftige Sessions):** Der naheliegende Pref-Key
`framework:color-scheme` ist laut Code-Kommentar in `framework/private/main.rkt` **Legacy**
und irreführend für die Frage „ist Light oder Dark Mode aktiv" — er wird nur ausgewertet,
wenn der eigentliche Schalter `framework:white-on-black-mode?` auf `'platform` steht oder
man tatsächlich im Dark-Zweig ist. Der korrekte Diagnosebefehl ist
`(preferences:get 'framework:white-on-black-mode?)` (`#t`=Dark, `#f`=Light,
`'platform`=OS-gesteuert). Eine Prüfung des Legacy-Keys allein führte in dieser Session kurzzeitig
zu einer falschen „Dark Mode aktiv"-Meldung, obwohl Light Mode explizit gesetzt war — und
erklärt plausibel auch den macOS-Nebenbefund „Editor-Garble beim ersten Paint" aus
`docs/2026-07-09_report-macos.md`: der reproduziert sich unter korrekt identifiziertem Light
Mode nicht mehr (siehe `docs/2026-07-10_report-macos.md` Abschnitt 4.1).

**Redraw-Bug damit auf allen drei Plattformen (Windows/macOS/Linux) validiert und
geschlossen.** Linux-Resize/-Minimieren bleibt als separate, ungeklärte Beobachtung offen
(siehe oben) — blockiert das Schließen des Redraw-Themas nicht. macOS-Befund A
(fehlendes „Windows"-Menü, 8 statt 9) bleibt ebenfalls offen, siehe
`docs/2026-07-10_report-macos.md` Abschnitt 4.2 — eigene Diagnose-Session.

## 17. Orphaned Submodule-Commit — `git pull` schlägt mit „not our ref" fehl

**Symptom (Linux, 2026-07-09):** `git pull` (mit Submodule-Rekursion) bricht ab mit:

```
fatal: remote error: upload-pack: not our ref de933088a293a555854cd13b3423aec0731925e5
```

**Root Cause:** Reihenfolge-Verstoß gegen die (jetzt in `CLAUDE.md` Regel 8 festgehaltene)
Submodul-Commit-Reihenfolge. Ablauf der Vorsession: ein Submodul-Commit (`de933088`) wurde
erstellt, während der lokale `qt-backend`-Checkout 2 Commits hinter `origin/qt-backend`
lag. **Bevor** das bemerkt wurde, entstand bereits ein Umbrella-Commit (`b2ae19b`, „docs:
rename dated docs files..."), der den Submodul-Zeiger auf genau `de933088` einfror — und
wurde gepusht. Direkt danach wurde der Submodul-Branch per `git rebase
origin/qt-backend` synchronisiert, wodurch `de933088` lokal durch einen neuen Commit
(`b2369d48`, der tatsächlich gepusht wurde) ersetzt wurde. Ein Folge-Commit im Umbrella
(`5db1cca`) zog den Zeiger korrekt auf `b2369d48` nach — aber `b2ae19b` selbst, bereits
Teil der gepushten `main`-Historie, referenziert weiterhin dauerhaft den nie gepushten,
jetzt verworfenen `de933088`.

`git pull --recurse-submodules` läuft über **jede** Gitlink-Änderung im geholten
Commit-Bereich (nicht nur den aktuellen HEAD-Stand) und versucht, jeden referenzierten
SHA zu holen — inklusive `de933088` aus `b2ae19b`. Da dieser SHA nie auf
`origin/qt-backend` existierte (nur lokal auf der Windows-Maschine, bis zum Rebase),
schlägt der Fetch mit „not our ref" fehl.

**Verifiziert als isolierter Einzelfall:** `git log --format=%H -- third_party/gui` +
`git ls-tree <commit> third_party/gui` für **jeden** Commit in `main`s Historie,
gegen `git branch -r --contains <sha>` auf dem Submodul-Remote geprüft — `de933088` ist
der **einzige** nicht erreichbare SHA in der gesamten Historie.

**Fix (non-destruktiv, kein History-Rewrite/Force-Push):** `de933088` existierte noch als
Commit-Objekt im lokalen Windows-Reflog (Rebase löscht Commits nicht sofort, nur die
Referenz darauf). Als Tag zum Submodul-Remote gepusht, damit der SHA wieder fetchbar ist:

```
git push origin de933088a293a555854cd13b3423aec0731925e5:refs/tags/orphan-de933088
```

Ändert keine bestehende Historie auf beiden Repos — der Umbrella-Commit `b2ae19b`
verweist weiterhin auf `de933088`, aber dieser SHA ist jetzt dauerhaft über den Tag
erreichbar. Nach dem Push: Linux-`git pull` läuft wieder durch.

**Lektion:** wird ein Submodul synchronisiert (Rebase/Merge, das bestehende Commits
ersetzt), NACHDEM bereits (auch nur lokal) ein Umbrella-Commit den alten SHA eingefroren
hat, muss der alte SHA vor dem Verwerfen als Ref gepusht werden — oder der Sync-Schritt
muss VOR dem ersten Submodul-Commit passieren (Regel 8). Ein `git reflog`-Check im
Submodul (`git cat-file -t <sha>`) verrät, ob ein vermeintlich verlorener Commit lokal
noch rettbar ist.

---

## 18. `list-box%`/`check-box%` echt gemacht + zwei neue Befunde (2026-07-10-2_prompt)

### 18.1 Treiber-Korrektur: Autosave-Recovery-Dialog zieht weder `list-box%` noch `check-box%`

Der ursprünglich geplante Treiber (DrRackets Autosave-Recovery-Dialog) wurde vor jeder
Implementierung gegen den tatsächlichen Quelltext geprüft
(`framework/private/autosave.rkt`, `restore-autosave-files/gui/table`): die Zeilen-UI
baut sich ausschließlich aus `message%`, `button%`, `canvas:color%` (Editor-Canvas) und
`vertical-/horizontal-panel%` auf — keine `check-box%`/`list-box%`-Instanziierung, auch
nicht über `frame:focus-table-mixin` (reine Fokus-Tracking-Mixin, keine Widgets). Der
frühere Report-Befund „Farbblöcke statt Text/Checkboxen" (`2026-07-10_report-win.md`
§4.2) war vermutlich derselbe, damals noch ungefixte `canvas%`-Redraw-Bug, keine fehlenden
Checkbox-Widgets. **Konsequenz:** Stufe 2 (isoliertes Testskript,
`examples/dialog-widgets-probe.rkt`) war von Anfang an die richtige Wahl, nicht nur ein
Fallback — die TOC-Präparation aus Phase 0b wurde deshalb nicht durchgeführt (auch keine
Schreibaktion auf die echte `PLT-autosave-toc.rktd` des Nutzers).

### 18.2 Neuer Fund: `wxitem.rkt` seedet `min-width`/`min-height` aus `get-width`/`get-height` — 0 bei jedem echten Qt-Control

**Symptom:** mehrere `button%` (oder beliebige echte Controls) in einem `vertical-panel%`
landen alle exakt übereinander (nur das zuletzt erzeugte ist sichtbar), unabhängig von
`list-box%`/`check-box%` — reproduziert mit drei nackten `button%`s ganz ohne neuen Code.

**Root Cause:** `wxitem.rkt`s `make-item%` ruft direkt nach `super-make-object`
(bevor die generische Panel-Sizing-Logik je `set-size` aufgerufen hat):
```
(set-min-width (init-min (get-width)))
(set-min-height (init-min (get-height)))
```
`get-width`/`get-height` sind bei uns `window%`s Basis-Felder `w`/`h`, die ausschließlich
von einem vorherigen `set-size`-Aufruf gesetzt werden — zu diesem Zeitpunkt im
Konstruktor also immer `0`. Jedes echte Qt-Control (`button%`, `message%`, `check-box%`,
`list-box%`) seedet damit `min-width`/`min-height` = 0, der generische
Panel-Sizing-Algorithmus (`wxpanel.rkt`s `do-get-graphical-min-size` über
`(send child get-info)`) advanced den Y-Offset dadurch nie, und `set-size` wird später
mit `nw=0`/`nh=0` aufgerufen — unser `(when (and nw (> nw 0) ...) (shim_widget_set_geometry ...))`-Guard
überspringt dann den `setGeometry`-Call komplett, sodass das Widget auf Qts unangetasteter
Default-Geometrie (0,0, kleine Default-Größe) sitzen bleibt. Alle Kinder landen so exakt
übereinander; sichtbar ist nur das zuletzt erzeugte (Z-Order).

**Betroffen:** `button%`, `message%` (schon vor dieser Session „real"), plus die neuen
`check-box%`/`list-box%` — strukturell, nicht spezifisch für diese Session. `canvas%`
ist NICHT betroffen, weil es laut Checkpoint E-0 (2026-06-30) bereits einen Seed-Call im
Konstruktor bekommen hat, der `window%`s `w`/`h` vor diesem Query korrekt setzt.

**NICHT gefixt** (Scope-Entscheidung, mit advisor abgestimmt): der Fix (Qt
`sizeHint()` abfragen und im Konstruktor seeden, analog zu `canvas%`s Muster) würde
`button.rkt`/`message.rkt` anfassen — beides außerhalb des Sessions-Scopes
(„nur `list-box%`/`check-box%`"), und verdient eigene Cross-Platform-Validierung statt
als Mitfahrer in diesem Commit zu laufen. **Workaround für diese Session:**
`examples/dialog-widgets-probe.rkt` setzt auf jedem Control explizit `[min-width n]
[min-height n]` (normale `area<%>`-Init-Args, generischer Code, umgeht den kaputten Seed).
Das beweist, dass `list-box%`/`check-box%` funktional korrekt sind (Items rendern,
Selektion/Toggle feuert den Callback) — **beweist nicht**, dass sie ohne diesen
Workaround in einem echten Dialog automatisch sauber layoutet werden; der echte
Autosave-Dialog (oder jeder andere Dialog mit >1 Control pro Panel) würde weiterhin
kollabieren, bis dieser Seed-Bug separat gefixt ist. Nächster Schritt: eigene Session,
Fix in `button.rkt`/`message.rkt`/`check-box.rkt`/`list-box.rkt` (neue Shim-Funktion
`QWidget::sizeHint()` abfragen, Konstruktor seedet `window%`s `w`/`h` vor dem
`get-width`/`get-height`-Query von `make-item%`), dann alle drei Plattformen erneut
prüfen (dieser Bug betrifft plausibel auch gtk/win32-unabhängige Codepfade nicht, da
deren Controls ihre native Größe direkt beim `super-make-object`/`CreateWindowEx`
kennen — nur unser Qt-`get-width`/`get-height` liest ein reines Racket-Feld ohne
Qt-Rückfrage).

**Update (2026-07-10-3_prompt): bestätigt + gefixt.** Neue Shim-Funktion
`shim_widget_get_size_hint` (`QWidget::sizeHint()`, out-Params wie
`shim_widget_client_to_screen`), aufgerufen über eine neue `window%`-Methode
`seed-size-from-native-hint` (`wx/qt/window.rkt`) — fragt die native Größe ab und
seedet `window%`s `w`/`h` per bestehendem `set-size`-Pfad (kein `get-width`/
`get-height`-Override, also kompatibel mit dem `same-dimension?`-Cache).
`button.rkt`/`message.rkt`/`check-box.rkt` rufen sie direkt nach `super-new`;
`list-box.rkt` erst nach dem Befüllen der Choices (sizeHint soll den Inhalt
widerspiegeln). `canvas%` bleibt bewusst kein Aufrufer (eigener Seed-Pfad,
`dc`-Feld existiert zum Zeitpunkt von `super-new` noch nicht). Vorher/Nachher an
einem isolierten 3-`button%`-Repro (`examples/panel-sizing-probe.rkt`) sowie am
echten `dialog-widgets-probe.rkt` (Workaround-`[min-width]`/`[min-height]`
entfernt) visuell bestätigt: Stapelung behoben, `list-box%`/`check-box%` layouten
korrekt ohne Workaround. Debug-Log (`PLT_QT_DEBUG`) zeigt `pre-seed w=0 h=0` →
`sizeHint=81x26` etc., exakt wie oben diagnostiziert. Smoke 3/3 grün, canvas%-Pfad
(hello.rkt) nicht regrediert. Commits: gui `8904b264`, Umbrella `9e54291`.
Details: `docs/2026-07-10-3_report-win.md`.

**Linux-Validierung (2026-07-10-3_prompt, `docs/2026-07-10-3_report-linux.md`): grün.**
ff-Pull `qt-backend` `04935cb6` → `f92352e0` (3 Commits: `08bf0af6` list-box%/check-box%,
`8904b264` Fix A, `f92352e0` Fix B — Umbrella `main` war bereits auf `f86bb09`/Zeiger
`f92352e0` aktuell, kein Pull dort nötig). Shim neu gebaut (`shim_widget_get_size_hint`
+ `shim_widget_set_enabled` beide neu in `shim.cpp`), Bytecode neu, Smoke 3/3 grün. Light
Mode bestätigt (`racket-prefs.rktd`: `plt:framework-pref:framework:white-on-black?` =
`#f`). `examples/panel-sizing-probe.rkt` (unverändert, keine Workarounds): Screenshot
(`xwd` + selbstgeschriebener XWD→PNG-Parser, da `pnmtopng`/`convert` auf dieser Maschine
fehlen) zeigt alle drei `button%` sauber vertikal gestapelt, keine Überdeckung —
identisch zum Windows-Nachher-Ergebnis. `dialog-widgets-probe.rkt` ohne Workaround
bestätigt: `list-box%` (4 Einträge) + `check-box%` layouten korrekt neben OK/Cancel.
Reine Validierung, keine Fix-Commits.

**macOS-Validierung (2026-07-10-3_prompt, `docs/2026-07-10-3_report-macos.md`): grün.**
ff-Pull `qt-backend` `04935cb6` → `f92352e0` (Umbrella `main` bereits deckungsgleich,
Zeiger schon `f92352e0`, kein Pull dort nötig). Shim neu gebaut (`cmake --build
qt-shim/build/macos-arm64`, beide neuen Funktionen kompilieren sauber), Bytecode neu
(`-S`-Source-Override, `raco make`), Smoke 3/3 grün. Light Mode bestätigt
(`org.racket-lang.prefs.rktd`: `white-on-black-mode?` = `#f`). `examples/panel-sizing-
probe.rkt` (unverändert): Screenshot (`osascript`/`screencapture`) zeigt alle drei
`button%` sauber vertikal gestapelt, keine Überdeckung — identisch zum Windows-/
Linux-Nachher-Ergebnis. `dialog-widgets-probe.rkt` ohne Workaround bestätigt: `list-box%`
(4 Einträge) + `check-box%` layouten korrekt neben OK/Cancel. Reine Validierung, keine
Fix-Commits.

### 18.3 Neuer Fund: `dialog%`-Modalität blockiert native Control-Callbacks nicht (Phase 1)

**Befund (Nutzer-bestätigt, visuell):** bei offenem modalem Dialog (`dialog-widgets-probe.rkt`)
bleibt der Parent-Frame-Button weiterhin klickbar (normales Klick-Feedback) — die
Modal-Sperre greift nicht für native Widget-Klicks.

**Root Cause (Code-Vergleich, win32/gtk gegen qt):** win32 und gtk erzwingen Modalität
NICHT nur über das gemeinsame `other-modal?`/`dialog-level`-Bookkeeping
(`wx/common/dialog.rkt`), sondern zusätzlich über einen **Toolkit-seitigen Disable** des
Eltern-Fensters beim Öffnen eines modalen Dialogs:
- win32: `wx/win32/window.rkt` ruft `(EnableWindow hwnd on?)` in `direct-show` —
  `EnableWindow(hwnd, FALSE)` sperrt Maus-/Tastatureingabe für das gesamte native
  Eltern-HWND auf OS-Ebene.
- gtk: `wx/gtk/window.rkt` ruft `(gtk_widget_set_sensitive gtk on?)` — GTK-Äquivalent.

Unser `wx/qt/dialog.rkt`/`frame.rkt` haben **kein** Äquivalent (kein
`QWidget::setEnabled(false)` auf dem Eltern-Widget). Zusätzlich verlässt sich
`other-modal?` ohnehin nur auf `dispatch-on-char`/`dispatch-on-event`
(`wx/qt/window.rkt`), die NUR für über `on-char`/`on-event` geroutete Eingaben greifen
(z. B. `canvas%`-Maus/-Tastatur). `button%`/`check-box%`/`list-box%`s native
Klick-/Selektions-Callbacks (`shim_button_create`s `click_cb` etc.) posten direkt in die
Eventspace-Queue, OHNE über `dispatch-on-event`/`other-modal?` zu laufen — selbst wenn
Qt den Parent nicht disabled, würde `other-modal?` diese Controls also gar nicht prüfen.
**Zwei getrennte Lücken, nicht eine:** (a) kein Parent-Disable beim Öffnen, (b) native
Control-Callbacks sind ohnehin nicht an `other-modal?` angebunden.

**NICHT gefixt** (Phase-1-Auftrag war Instrumentieren/Dokumentieren, kein Fix; direkte
Eingabe für den geplanten file-selector-Prompt). Fix-Kandidat für später: beim Öffnen
eines modalen Dialogs (`dialog-mixin`s `direct-show`) `QWidget::setEnabled(false)` auf
dem Eltern-`window%` aufrufen (neue Shim-Funktion `shim_widget_set_enabled`), symmetrisch
beim Schließen wieder `#t`. Kein `exec()`/keine geschachtelte Schleife nötig — reine
Toolkit-Property, analog zu win32/gtk.

**Update (2026-07-10-3_prompt): bestätigt + gefixt, beide Lücken durch (a) allein
gelöst.** Neue Shim-Funktion `shim_widget_set_enabled` (`QWidget::setEnabled`).
`wx/qt/frame.rkt` bekommt eine `modal-enable`-Methode, 1:1 gespiegelt an
`wx/win32/frame.rkt`s gleichnamiger Methode: berechnet `on? = (not (other-modal?
this #f ignoring))` über das bestehende, unveränderte `other-modal?`/`dialog-level`-
Bookkeeping und pusht das Ergebnis auf den Shim. `wx/qt/dialog.rkt`s `direct-show`
ruft `modal-enable` auf jedem Top-Level-Fenster der Eventspace (`get-top-level-windows`),
1:1 gespiegelt an `wx/win32/dialog.rkt`s `direct-show`. Lücke (a) (kein
Toolkit-Disable) ist damit geschlossen. Für Lücke (b) (native Callbacks nicht an
`other-modal?` angebunden) wurde wie im Phase-2c-Plan **gemessen statt blind
gefixt**: `QWidget::setEnabled(false)` auf dem Frame kaskadiert in Qt automatisch auf
alle Kind-Widgets und unterbindet deren Mausereignis-Zustellung komplett — ein
Klick auf einen disabled `button%` erreicht seinen `clicked`-Callback in Qt gar nicht
erst. Empirisch bestätigt (`dialog-widgets-probe.rkt`: kein `PARENT BUTTON CLICKED`-
Print bei offenem Modal, obwohl der Klick simuliert wurde). Lücke (b) brauchte damit
**keine separate Absicherung** — kein zusätzlicher `other-modal?`-Guard in den
nativen Klick-Callbacks nötig. Vorher/Nachher visuell bestätigt: Eltern-Fenster
grau/disabled bei offenem Dialog, Klick ohne Effekt; nach Schließen (OK/Cancel)
wieder normal eingefärbt und klickbar; Dialog-Controls (`list-box%`/`check-box%`/
OK/Cancel) bleiben während der gesamten Zeit voll funktional. Smoke 3/3 grün. Kein
`exec()`/keine geschachtelte Schleife. Commits: gui `f92352e0`, Umbrella `4030fe2`.
Details: `docs/2026-07-10-3_report-win.md`.

**Linux-Validierung (2026-07-10-3_prompt, `docs/2026-07-10-3_report-linux.md`): grün.**
Nach Sync/Rebuild (siehe §18.2-Linux-Absatz oben) `dialog-widgets-probe.rkt` per
synthetischem `libXtst`-Klick (kein `xdotool` auf dieser Maschine, selbstgebauter
XTest-Helfer analog zu den Redraw-Validierungssessions) bedient: Dialog geöffnet
(`list-box%`/`check-box%` sichtbar+funktional), Klick auf den — wegen
Fenster-Überlappung eigens per `XMoveWindow` freigelegten — Parent-Button bei
offenem Modal löst **keinen** `PARENT BUTTON CLICKED`-Print aus (stdout war
Block-gepuffert, sichtbar erst nach Prozessende); derselbe Klick nach Schließen des
Dialogs (OK) löst den Print sofort aus — bestätigt, dass die Klick-Mechanik selbst
funktioniert und die Blockade ursächlich an der offenen Modalität hängt, nicht an
einem Test-Artefakt. Visueller Grau-Kontrast zwischen enabled/disabled war in diesem
Qt-Stil bei dieser Auflösung nicht eindeutig unterscheidbar (Pixel-Sampling ähnlich,
~127 vs. ~131 auf 0–765-Skala) — die funktionale Blockade ist der belastbare Befund,
nicht der visuelle Eindruck. Reine Validierung, keine Fix-Commits.

**macOS-Validierung (2026-07-10-3_prompt, `docs/2026-07-10-3_report-macos.md`): grün.**
Nach Sync/Rebuild (siehe §18.2-macOS-Absatz oben) `dialog-widgets-probe.rkt` per
Accessibility-API (`osascript`/System Events — Klick auf benannte Buttons/Checkbox,
zuverlässiger als Pixel-Koordinaten) bedient: Dialog geöffnet (`list-box%`/`check-box%`
sichtbar+funktional, `check-box toggled: #t` im Log), Klick auf den Parent-Button bei
offenem Modal löst **keinen** `PARENT BUTTON CLICKED`-Print aus; derselbe Klick nach
Schließen des Dialogs (OK) löst ihn sofort aus (einziges Vorkommen des Prints im Log,
direkt nach `dialog closed —…`) — bestätigt wie bei Linux, dass die Blockade ursächlich
an der offenen Modalität hängt, nicht an einem Test-Artefakt. **Visueller Kontrast hier
deutlich sichtbar** (anders als Linux): Screenshot zeigt Parent-Fenster-Buttons klar
ausgegraut (helleres Grau) gegenüber den scharfen schwarzen Labels im aktiven Dialog —
deckt sich mit dem für Windows berichteten deutlichen Kontrast, plausibel eine
Theme-/Style-Differenz auf Linux (KDE/Breeze), nicht Teil dieses Scopes. Reine
Validierung, keine Fix-Commits.

### 18.4 Widget-Hinzufügen: `list-box%`/`check-box%` konkret (Ergänzung zu §5)

- Kontrakt-Methodennamen **gegen gtk UND win32** verifiziert, nicht geraten (gauge%-Lektion,
  §5 Punkt 4 gilt genauso für Wert-/Auswahl-Protokolle wie für Klassen-Ketten):
  `check-box%` (`set-value`/`get-value`, Callback-Event-Typ `'check-box`),
  `list-box%` (`number`, `get-data`/`set-data`, `set-string [col 0]`, `append`
  case-lambda via `(public [append* append])`-Rename-Trick — sonst shadowt die eigene
  Methode `racket/list`s `append` innerhalb des eigenen Methodenkörpers, `clear`, `set`,
  `get-selections`/`get-selection`, `selected?`, `select` case-lambda mit `extend?`-
  Semantik (gtk-Vorbild: `extend?=#f` löscht zuerst alle anderen Selektionen),
  `set-selection`, `set-first-visible-item`/`get-first-item`/`number-of-visible-items`
  (Best-Effort-Annäherung über `QListWidget::indexAt`/`sizeHintForRow`, nicht exakt wie
  gtk/win32 — nur für Mausrad-Scroll-Schrittweite relevant, nicht selektionsrelevant).
- Multi-Column/Report-Mode (`get-column-order`, `append-column`, etc.) sind reine
  No-op-Stubs — `QListWidget` ist single-column-only in diesem Backend, kein Treiber
  braucht mehr (win32 hat für Multi-Column sogar eine komplett andere native Control,
  `PLTSysListView32` statt `PLTLISTBOX`).
- Signal→Callback: `itemSelectionChanged`/`toggled` verbinden sich im Shim per
  `QObject::connect` mit einer C++-Lambda, die **nur** `cb(ud)` aufruft (kein Zustand im
  Signal-Handler) — Racket-Seite liest den aktuellen Zustand danach per separatem
  Shim-Query (`shim_list_box_get_selections`-Äquivalent, `shim_check_box_get_checked`),
  exakt das bestehende `button%`/`message%`-Muster (Shim postet nur, Zustand wird separat
  abgefragt).
- Programmatische Zustandsänderungen (`set-value`, `select`, `set-current`) blocken das
  Qt-Signal per `QSignalBlocker` im Shim, damit sie nicht denselben Callback re-triggern
  wie ein echter Nutzer-Klick — mirrored gtks `ignore-click?`/win32s
  `suppress-callback`-Parameter, nur auf Shim- statt Racket-Seite umgesetzt.

## 19. `file-selector` echt gemacht — `QFileDialog` non-modal via `open()` (2026-07-11_prompt)

**Mechanik (Kernfrage der Sitzung, gemessen + bestätigt):** `QFileDialog::open()`
(NICHT `exec()`) zeigt den Dialog als *window-modal* an und kehrt sofort zum Aufrufer
zurück — keine geschachtelte `QEventLoop`. Das Ergebnis kommt über das `QDialog::finished
(int result)`-Signal, das während eines ganz normalen `shim_pump()`-Aufrufs feuert, exakt
wie jedes andere Signal in diesem Backend. `get-file`/`put-file` müssen sich nach außen
aber SYNCHRON verhalten (Rückgabewert = Pfad oder `#f`) — dafür wird `dialog%`s bereits
bewährter Mechanismus wiederverwendet (`../common/dialog.rkt`, §16/§18.3): `(yield
(semaphore-peek-evt done-sema))` blockiert den Racket-Aufrufer, während der
Pump-Hintergrund-Thread weiterläuft und den `finished`-Callback verarbeitet; der Callback
postet nur ein `queue-event`, das `done-sema` erst danach (im Eventspace-Handler-Thread)
postet. Kein `exec()`, kein eigener `QEventLoop`, kein Verstoß gegen Regel 1.

**Fund 1 — Parent-Disable ist Fix B, wiederverwendet, nicht neu gebaut:** `shim_widget_
set_enabled` (§18.3) wird direkt auf den Parent-`frame%`-Handle angewendet (nicht über
den vollen `get-top-level-windows`/`modal-enable`-Dialog-Level-Mechanismus, da
`file-selector` keine `dialog%`-Instanz ist) — vor dem Öffnen disabled, im Ergebnis-Thunk
wieder enabled.

**Fund 2 — echter Bug, kein Architektur-Problem: pro Aufruf einen frischen `_fun`-
Callback zu erzeugen ist auf Windows nicht sicher.** Jedes andere Widget in diesem
Backend (`button%`, `check-box%`, `list-box%`, …) erzeugt seinen Klick-/Toggle-Callback
GENAU EINMAL im Konstruktor und der native Trampolin wird für jedes weitere Event
wiederverwendet. `file-selector` ist keine langlebige Widget-Instanz — die naheliegende
erste Implementierung erzeugte bei jedem `get-file`/`put-file`-Aufruf eine frische
Racket-Closure und übergab sie direkt als `_file_dialog_cb_t`-Argument. Gemessen (echte
Nutzer-Interaktion, `examples/file-dialog-probe.rkt`, `PLT_QT_DEBUG=1`):
- Lauf 1 (kein Debug-I/O im Atomic-Callback): 1×Accept, 1×Cancel liefen sauber, **3. Dialog
  (2. Accept) crashte reproduzierbar** (`APPCRASH`, `c0000005`, WER-Report bestätigt —
  kein Racket-Backtrace, da echter natíver Absturz). Callback-Adressen der drei Aufrufe
  lagen exakt 0x1E0 Byte auseinander (`...4040`, `...4220`, `...4400`) — Indiz für einen
  kleinen, pro-Aufruf allozierten nativen Trampolin-Slot statt eines gecachten.
- `foreign_procedures.html` bestätigt explizit: „Callbacks are always atomic [in CS]" UND
  `ffi/unsafe.rkt`s `_cprocedure*` (Zeile ~470) ruft `make-ffi-callback` bei **jedem**
  Aufruf der Ctype-Konvertierungsfunktion neu auf — es gibt **keine** Memoisierung nach
  Prozedur-Identität, auch nicht für dieselbe Racket-Prozedur über mehrere Aufrufe hinweg.
  „Run-time code generation is fast and cached" (static-fun.html) bezieht sich auf den
  generierten MASCHINENCODE pro Ctype-Signatur, nicht auf einen Cache pro (Prozedur,
  Ctype)-Paar.
- **Fix:** genau EIN natives Callback-Objekt einmalig beim Modul-Laden per `(function-ptr
  dispatch-file-dialog-result _file_dialog_cb_t)` erzeugen; Aufrufe werden über eine kleine
  Ganzzahl-ID dispatcht, die als das `ud`-`void*` selbst durchgereicht wird (klassisches
  C-Userdata-Idiom: `(cast id _intptr _pointer)` / Rückweg `(cast ud _pointer _intptr)`,
  beide Richtungen verifiziert). Ein `pending`-Hasheqv (ID → Ergebnis-Closure) hält die
  Continuation bis zum Dispatch.
- **Stolperstein dabei:** Ein `_fun`-typisiertes Parameter (`_file_dialog_cb_t`) versucht
  bei JEDER Übergabe erneut zu wrappen — auch wenn bereits ein fertiges Callback-Objekt
  übergeben wird (`make-ffi-callback: contract violation, expected: procedure?, given:
  #<callback>`). Deshalb ist `shim_file_dialog_create`s `cb`-Parameter in `utils.rkt` als
  reines `_pointer` deklariert (nicht `_file_dialog_cb_t`) — der einmalig gebaute
  Callback-Pointer wird so unverändert durchgereicht statt erneut gewrappt zu werden.
  `_file_dialog_cb_t` bleibt nur für den einmaligen `function-ptr`-Aufruf in Gebrauch.
- **Verifiziert:** 8/8 aufeinanderfolgende Öffnen-Zyklen (echte Nutzer-Klicks, jedes Mal
  eine andere Datei gewählt) grün, `cb`-Adresse im Log über alle 8 Aufrufe hinweg
  **identisch** (Beweis für Trampolin-Wiederverwendung). Zusätzlich 5× Öffnen→Abbrechen
  und mehrfach Speichern→Speichern (inkl. Overwrite-Warnung bei existierender Datei) sowie
  Speichern→Abbrechen — alle grün, Nutzer-bestätigt.
- **Lektion für künftigen Code in diesem Backend:** Sobald eine Funktion (nicht ein
  langlebiges Widget) einen `_fun`-Callback an den Shim reichen muss, IMMER das
  Einmal-`function-ptr`-plus-Userdata-ID-Muster verwenden, nie eine frische Closure pro
  Aufruf — dieser Fehler ist auf Windows nicht sofort sichtbar (3 Aufrufe liefen im
  allerersten Test sogar sofort beim 1. Versuch durch, in einem späteren Test erst beim
  3.) und macht sich als schwer reproduzierbarer nativer Absturz bemerkbar, nicht als
  Racket-Fehler.

**Kontrakt-Details:** `directory`/`filename`/`extension`/`filters` werden 1:1 aus dem
gemeinsamen `mred/private/filedialog.rkt`-Kontrakt (identisch zu win32/gtk) übernommen;
`filters` (`(listof (list string? string?))`) wird nach Qts `"Name (*.ext *.ext2);;Name2
(*.ext3)"`-Syntax übersetzt (win32-Style-`;`-getrennte Muster innerhalb eines Eintrags
werden zu Leerzeichen). `get-directory`/`get-file-list` (`'dir`/`'multi` im Style) bleiben
diese Sitzung bewusst außen vor (`#f`, wie der alte Stub) — nicht Teil des Scopes.

**Phase 3 (nativer Windows-Dialog) — gemessen, trägt.** Ein `PLT_QT_NATIVE_FILE_DIALOG`-
Env-Var-Schalter (analog zu `PLT_QT_DEBUG`) existiert im Shim (`plt_qt_native_file_
dialog()`), der `QFileDialog::DontUseNativeDialog` umkehrt — bewusst NICHT Teil des
`get-file`/`put-file`-Kontrakts (kein neuer Parameter), nur ein Mess-Werkzeug. Ergebnis
(Nutzer, `PLT_QT_NATIVE_FILE_DIALOG=1`, `examples/file-dialog-probe.rkt`): **der native
Windows-Common-Dialog trägt denselben non-modalen `open()`+`finished`-Signal+Pump-
Mechanismus wie der Qt-eigene** — 7 aufeinanderfolgende Öffnen-Zyklen (Mix aus Auswählen
und Abbrechen) grün, dieselbe Callback-Adresse über alle 7 Aufrufe hinweg, kein Crash,
kein Hang, kein `exec()` nötig. Der native Dialog verlangt also **keine** eigene
geschachtelte Schleife unter diesem Pump-Modell — als Stil-Option für später vermerkt,
aber der Qt-eigene Dialog (`DontUseNativeDialog=true`) bleibt der Standard-Pfad dieses
Backends (kein neuer Parameter im `get-file`/`put-file`-Kontrakt, keine Plattform-
Fallunterscheidung nötig).

**Linux-Validierung (2026-07-11, `docs/2026-07-11_report-linux.md`):** ff-Pull
`qt-backend` `f92352e0`→`19954ffd`, Shim neu gebaut (`shim_file_dialog_create` kam schon
über den Umbrella-Pull), Re-Smoke 3/3 grün. Probe-Treiber: 9/9 Dialog-Zyklen (5×
`get-file`, 4× `put-file`, gemischt Accept/Cancel/Overwrite-Warnung) grün, `cb`-Adresse
über alle 9 Aufrufe **und über den `get`→`put`-Moduswechsel hinweg** identisch — bestätigt
das Einmal-Trampolin-Fix (Fund 2 oben) auch hier. Echtes DrRacket: File → Open und File →
Save bestätigt funktional (Nutzer). Isolierter Test bestätigt `setDefaultSuffix`
funktioniert korrekt (`myfile` → `myfile.rkt`).

Dabei zwei unabhängige, seltene Abstürze beobachtet, **außerhalb des
`get-file`/`put-file`-Wertpfads** (in beiden Fällen lief der Dialog-Code entweder nie an
oder hatte bereits korrekt zurückgegeben, bevor der Absturz folgte) — nicht root-caused,
nicht gefixt (Guardrail: mutmaßlich gemeinsamer Code, Entscheidung über Verfolgung liegt
beim Nutzer):
- **Crash A** (n=1, nicht reproduziert): `pre: arity mismatch … expected: 0, given: 1`,
  `internal-error: terminated in atomic mode!`, Kontext `wx/qt/queue.rkt:27:5` (Event-Pump-
  Thread). Trat beim allerersten Interaktionsversuch (File → Open) mit einer noch nicht
  vollständig gestarteten DrRacket-Instanz auf; ein geduldigerer zweiter Versuch lief
  sauber durch. Kein `[qt-filedialog]`-Log vor dem Absturz — der Fehler liegt vor dem
  eigentlichen `get-file`-Aufruf, mutmaßlich in `wx/common/queue.rkt`s
  `pre-event-sync`-Boundary-Callback-Dispatch (Arity-Signatur passt zu dessen `(p v)`-
  Aufrufmuster), konkrete Fundstelle nicht identifiziert.
- **Crash B**: `invalid memory reference` nach bereits gedrucktem, korrektem
  `put-file`-Rückgabewert, in einem Skript ohne sichtbares `frame%` (Racket-Laufzeit
  beendet sich nach Modul-Auswertung). Korreliert mit Prozess-Exit/Teardown-Reihenfolge
  nach einem noch `deleteLater()`-anstehenden `QFileDialog`, nicht mit dem Dialogergebnis
  selbst. In der Probe und in echtem DrRacket (beide halten ein `frame%` offen) nicht
  reproduziert.

**macOS-Validierung + zwei echte Bugfixes (2026-07-12, `docs/2026-07-11_report-macos.md`):**
Sync (`qt-backend` `f92352e0`→`19954ffd`, nach Nutzer-Bestätigung), Shim neu gebaut, Smoke
3/3. `get-file`/`put-file` per Button (7/7 Zyklen, Öffnen/Speichern/Abbrechen gemischt)
sofort grün — der Kern-Wertpfad ist plattformunabhängig unverändert korrekt.

Der Abschluss-Beweis (echtes DrRacket File → Open/Save) crashte auf dieser Maschine
zunächst **reproduzierbar (2/2)** beim allerersten `File → Open`-Klick, mit `invalid
memory reference … terminated in atomic mode!`, **kein** `[qt-filedialog]`-Log davor —
der Fehler lag vor `get-file` selbst, im Menü-Klick-Dispatch. Ein Discriminator-Test
(`get-file` über einen eigenen `menu-item%` im Probe-Skript statt über einen Button)
isolierte das sauber: der Dateidialog öffnete sich gar nicht erst; stattdessen ein
abgefangener, aber prozess-tötender Fehler. Zwei echte, unabhängige Bugs in `wx/qt/`
gefunden und gefixt (beide potentiell auch Ursache von Linux' Crash A/B oben — gleiches
Fehlerbild, nur dort seltener/GC-timing-abhängig statt reproduzierbar):

1. **`id-to-menu-item` rief `get-mred` doppelt/verfrüht auf** (`wx/qt/platform.rkt`):
   ```racket
   (define (id-to-menu-item id)
     (and (object? id) (is-a? id menu-item%)
          (send id get-mred)))
   ```
   gtk (`wx/gtk/procs.rkt`) und win32 (`wx/win32/menu-item.rkt`) überlassen die
   wx→mred-Auflösung vollständig dem generischen `wx->mred` in `wxtop.rkt`s
   `on-menu-command` (gtk: reine Identität; win32: Hash-Tabellen-Lookup). Qt versuchte,
   `get-mred` selbst vorwegzunehmen — das crashte beim ersten echten Menü-Dispatch
   (`generic:get-mred: target is not an instance of the generic's interface`). **Fix:**
   `(define (id-to-menu-item id) id)`, identisch zu gtks Muster. Commit `acc73108`.
2. **Menü-Item-Callbacks in `wx/qt/menu.rkt`s `append` waren nie retained** — `cb` war
   eine rein lokale `let`-Bindung, nur `action` (die `QAction*`) landete in
   `item-table`. Nichts auf Racket-Seite hielt die Closure am Leben, sobald `append`
   zurückkehrte — exakt dieselbe Landmine, die `filedialog.rkt`s eigener Kommentar
   dokumentiert (Fund 2 oben), nur hier nicht für `file-selector`s eigenen Trampolin,
   sondern für jeden normalen Menüpunkt. Symptom passte exakt: ein frisch geklickter
   Menüpunkt funktionierte, ein **zweiter** Klick auf denselben oder einen anderen
   Menüpunkt konnte crashen — verschärft direkt nach GC-Druck (z. B. nach einem
   Dateidialog-Zyklus). Zwei Fehlerbilder je nachdem, wie viel der Closure bereits
   eingesammelt war: ein abgefangener `contract violation … target: (object:menu-item%
   ...) … interface name: wx<%>` (Closure-Environment bereits Garbage) oder ein harter
   nativer `invalid memory reference` (toter Funktionszeiger direkt aufgerufen). **Fix:**
   neues `retained-callbacks`-Hasheq in `menu%`, `id → cb`, befüllt in `append`,
   aufgeräumt in `delete`/`delete-by-position`. Commit `caef3e9c`.
   - **Verifiziert (härter als der ursprüngliche Bug-Fund):** `examples/file-dialog-
     probe.rkt` um `menu-item%`-Einträge erweitert (`Open via menu…`, `No-op`, `Force GC`
     — expliziter `(collect-garbage)`-Stresstest). Vor dem Fix: No-op crashte
     reproduzierbar nach vorherigem Dialog-Zyklus bzw. nach explizitem `collect-garbage`.
     Nach dem Fix: `Force GC` → mehrfach `No-op` → `Open via menu…` läuft durch, kein
     Crash, 4 weitere `get-file`-Zyklen sauber.
   - Beide Fixe berühren ausschließlich `wx/qt/` (kein Shared-Code-Verstoß gegen die
     Guardrails dieser Session).

Nach beiden Fixes: **echtes DrRacket File → Open + File → Save As bestätigt funktional**
(Nutzer) — Datei erscheint im Editor, Speichern landet korrekt auf Platte — **und ein
zweiter `File → Open` (neue Registerkarte) läuft ebenfalls sauber**, bevor ein dritter,
unabhängiger Fund auftrat (siehe unten). `file-selector` auf macOS damit End-to-End
bestätigt, mit zwei echten Bonus-Fixes für latente, plattformübergreifende
Menü-Dispatch-Speicherfehler.

**Dritter, unabhängiger Fund — NICHT gefixt, außerhalb des `file-selector`-Scopes:**
ein zweiter `File → Open` öffnete eine neue Registerkarte; das triggerte einen
vorbestehenden Contract-Verstoß in `htdp-lib`s `test-engine/test-tool.rkt` (`test-panel%`s
`remove`-Methode speichert unbedingt `(send parent get-percentages)` in die Preference
`test-engine:test-dock-size`, deren Default-Prädikat exakt 2 Elemente verlangt — bei nur
einem sichtbaren Panel-Kind liefert `get-percentages` aber `'(1)`). DrRackets eigener
Fehler-Handler öffnete daraufhin ein „DrRacket Internal Error"-Dialogfenster (in unserem
Log sauber als `QMainWindow` erschienen) — **danach** folgte ein harter nativer
`invalid memory reference`-Absturz. Ein isolierter Qt-only-Repro (`examples/tab-close-
crash-probe.rkt`: `get-percentages` + `delete-child` auf ein Panel mit nur noch einem
Kind + `collect-garbage` + neues Top-Level-`frame%` erzeugen+zeigen, mimikt die
Internal-Error-Dialog-Erzeugung) reproduziert den harten Crash **nicht** — der Fehler
braucht offenbar mehr vom echten DrRacket-Stack (vermutlich die konkrete Widget-Struktur
des echten Test-Panels mit eingebettetem Editor, oder den Aufruf-Kontext innerhalb der
Exception-Behandlung selbst). Nicht root-caused: der Contract-Verstoß selbst liegt in
`htdp-lib` (nicht `wx/qt/`, nicht einmal `gui-lib`) und ist plattformunabhängig — nicht
Teil dieser Session, keine Fix-Commits dafür. Eigene, dedizierte Session nötig (mit
gezielter Instrumentierung, nicht mit weiterem Lesen von Shared-Code).

**Linux Crash-A/B-Rückprüfung nach den zwei macOS-Fixes (2026-07-12,
`docs/2026-07-11-2_report-linux.md`):** ff-Pull `qt-backend` `19954ffd`→`caef3e9c` (beide
Fixe rein Racket-seitig, kein Shim-Rebuild nötig), `raco make` + Smoke 3/3 grün, Light
Mode (BreezeLight) bestätigt.

- **Crash A — plausibel behoben, nicht absolut bewiesen.** 4 gezielte Versuche (frischer
  `PLT_QT=1 PLT_QT_DEBUG=1`-DrRacket-Start, File → Open so früh wie möglich geklickt):
  3/4 liefen komplett sauber durch (Dialog öffnet, Datei lädt, kein Fehler im Log). Der
  ursprüngliche `pre: arity mismatch … terminated in atomic mode!`-Absturz (Prozessende)
  trat in keinem der 4 Versuche auf. Ein Versuch (1/4) traf stattdessen einen anderen,
  bereits bekannten Fehler (siehe htdp-Rezidiv unten) — das ist ein abgefangener Dialog,
  kein Prozessabsturz, zählt also nicht als Crash-A-Repro. Einordnung: gute, aber keine
  absolute Evidenz (Original war n=1-intermittierend; n=4-sauber ist ein starkes, aber
  kein beweisendes Signal). Arbeitshypothese „durch `acc73108`/`caef3e9c` mitbehoben"
  bleibt vorerst bestätigt, nicht abschließend verifiziert.
- **Crash B — bleibt unverändert offen, wie erwartet nicht durch die Menü-Fixes berührt.**
  1/1 exakt reproduziert: isoliertes `(put-file …)`-Skript ohne `frame%`, Nutzer tippte
  Dateinamen und speicherte, Log druckte den korrekten Pfad
  (`/home/deinzer/src/racket_qt/ffff.rkt`), danach sofort `invalid memory reference. Some
  debugging context lost`, Prozessende. Identisches Fehlerbild wie im Ursprungsbericht.
  Bestätigt die bestehende Hypothese, dass Crash B ein Teardown-/`deleteLater()`-
  Reihenfolgeproblem ist, unabhängig vom Menü-Dispatch-Code der beiden Fixe — bleibt
  offener Befund für gemeinsamen Code, hier bewusst nicht gefixt (Guardrail).
- **htdp-lib-Bug-Rezidiv, jetzt auch bei nur EINEM Tab (neuer Datenpunkt gegenüber dem
  macOS-Bericht).** Einer der 4 Crash-A-Versuche zeigte den bereits dokumentierten
  „dritten Fund" (oben, macOS-Abschnitt): DrRacket-Internal-Error-Dialog mit exakt
  `preferences:set: new value doesn't satisfy preferences:set-default predicate — pref
  symbol: 'test-engine:test-dock-size — given: '(1) — predicate:
  #<procedure:...ngine/test-tool.rkt:10:25>`. Anders als im macOS-Bericht (der einen
  zweiten geöffneten Tab als Auslöser brauchte) trat er hier bereits beim allerersten
  File → Open mit nur einer offenen Registerkarte auf — der Auslöser ist also weiter
  gefasst als bisher angenommen (nicht zwingend tab-Wechsel-gebunden). Nach dem
  Wegklicken (OK) blieb der Prozess am Leben, das Definitions-Fenster blieb editierbar,
  aber die Interactions-Leiste (unterer REPL-Bereich) fehlte sichtbar — konsistent mit
  einem gestörten Panel-Layout durch die fehlgeschlagene `test-dock-size`-Preference.
  Weiterhin nicht root-caused, weiterhin außerhalb des Scopes dieser Session (`htdp-lib`,
  nicht `wx/qt/`) — keine Fix-Versuche, reine Beobachtung für die künftige dedizierte
  Session.

**Linux Qt-eigen×nativ-Matrix (2026-07-12, `docs/2026-07-11-2_report-linux.md`):**
Qt-eigen war bereits aus der Vorsession grün (9/9), hier nicht wiederholt. Nativer Pfad
(`PLT_QT_NATIVE_FILE_DIALOG=1`, `examples/file-dialog-probe.rkt`): **8/8 Zyklen grün**
(gemischt Open/Save/Cancel), `cb`-Adresse (`0x458d9d60`) über alle 8 Aufrufe identisch
(Trampolin-Fix greift auch hier), kein Crash, kein Hang, `native=1` im Log durchgehend
bestätigt. Der native Dialog trägt denselben non-modalen `open()`+Pump-Mechanismus ohne
Änderung. Welcher konkrete Backend-Dialog erscheint (KDE-nativ vs. xdg-desktop-portal),
konnte der Nutzer mangels Vergleichsreferenz nicht zuordnen — funktional aber eindeutig
grün, keine eigene Runloop nötig.

**macOS-Nativ-Matrix (2026-07-13, `docs/2026-07-13_report-macos.md`):** Kernfrage
(Läuft der Pump weiter, während NSOpenPanel/NSSavePanel offen ist, oder dreht Cocoa eine
eigene Runloop?) eindeutig beantwortet: **nein, keine eigene Runloop.** Stärkster Beweis:
**13/13 Dialog-Öffnungen** (6× Accept, 7× Cancel, Open/Save gemischt, inkl.
Overwrite-Warnung) lieferten ihr Ergebnis korrekt an Racket zurück — unter einem
ausgehungerten Pump unmöglich, da `finished` nur innerhalb eines `shim_pump()`-Aufrufs
feuern kann. Ein additiver, hinter `PLT_QT_DEBUG` gateter Racket-`timer%`-Heartbeat (200 ms,
`examples/file-dialog-probe.rkt`) korroboriert das direkt: tickte 117 Zyklen (~23 s)
ununterbrochen weiter, während der native Dialog offen war, bis `finished` über einen
ganz normalen Pump-Durchlauf zurückkam. `cb`-Adresse identisch über alle 6 Accept-Aufrufe
**und über mehrfache `get`→`put`-Moduswechsel hinweg** (Trampolin-Fix, Fund 2, greift
auch hier). Kein Crash, kein Hang, `native=1` durchgehend im Log.

**Nebenbefund, dokumentiert, bewusst nicht gefixt (Nutzer-Entscheidung, analog Linux
Crash A/B):** Beim **nativen** Save-Dialog hängt macOS ein literales `.*` an einen
Dateinamen ohne Endung (`abc` → `abc.*`). Diskriminator-Test (identischer Code, nur
`PLT_QT_NATIVE_FILE_DIALOG` weggelassen) zeigt: **rein native-spezifisch** — der
Qt-eigene Dialog liefert `abc` unverändert. Keine Aussage über die genaue Ursache
innerhalb von Qts Cocoa-Plugin (Quellcode nicht gelesen); vermutlich Interaktion des
Wildcard-Namensfilters `"Any (*.*)"` mit NSSavePanels Endungs-Inferenz. Blockiert die
Kernfrage nicht (native ist ohnehin nicht der Standardpfad dieses Backends) und
rechtfertigt keinen Shared-Code-Fix in dieser Sitzung.

**Qt-eigen×nativ-Matrix-Stand (3 Plattformen × 2 Dialog-Typen) — komplett:**

| Plattform | Qt-eigen | Nativ |
|---|---|---|
| Windows | ✅ (7/7, Vorsession) | ✅ (7/7, Vorsession — Windows-Common-Dialog) |
| Linux | ✅ (9/9, Vorsession) | ✅ (8/8, diese Session — Dialog-Typ nicht identifiziert, funktional grün) |
| macOS | ✅ (7/7 + DrRacket, Vorsession) | ✅ (13/13, 2026-07-13 — mit dokumentiertem, ungefixtem Save-Suffix-Fund) |

Details, vollständige Logs und Diskriminator-Überlegungen: `docs/2026-07-11_report-linux.md`,
`docs/2026-07-11-2_report-linux.md`, `docs/2026-07-13_report-macos.md`.

## 20. `choice%`/`radio-box%`/`slider%` echt gemacht — Windows (2026-07-13-2_prompt)

**Orakel-Befund zuerst:** der reale Treiber ist NICHT der volle Preferences-Dialog —
`framework/private/preferences.rkt`s eigene Navigation (`make-tab/single-panel`,
Zeile ~321) instanziiert **unconditional** ein `tab-panel%`, auch für die oberste
Kategorie-Ebene, nicht nur für verschachtelte Unterkategorien. Da `tab-panel%` weiterhin
Stub ist (Block B, eigener Prompt), ist eine Ende-zu-Ende-Validierung über den echten
Dialog **strukturell blockiert** — genau der in Phase 1 antizipierte Fall, kein
Scope-Bruch. Beweis läuft stattdessen über einen neuen isolierten Probe
(`examples/value-widgets-probe.rkt`, analog `dialog-widgets-probe.rkt`), Nutzer-bestätigt
(Rendering, Interaktion, `set-*` löst den eigenen Callback nicht erneut aus).

Widget-Inventar (`framework/private/preferences.rkt` + `color-prefs.rkt`, alle real
DrRacket-Preferences-Nutzung): `slider%` — Anzahl zuletzt geöffneter Dateien (1–100),
Editor-Schriftgröße (1–127); `radio-box%` — Boolean-„ask me"-Optionen, Druckmodus,
Farbschema-Auswahl (`mk-color-scheme-radio-buttons`, **1-Button-Gruppen mit
`[selection #f]`** — der harte Fall für „keiner ausgewählt"); `choice%` — Schriftglättung,
Klammer-Farbschema, Farbmodus (Windows: Light/Dark; sonst: OS/Light/Dark).

**Kontrakt gegen gtk UND win32 verifiziert (§5/§18.4-Muster), nicht geraten:**
- `choice%`: init `parent cb label x y w h choices style font`. Methoden
  `set-selection`/`get-selection`/`number`/`clear`/`append`(einzelnes String-Arg,
  `(public [append* append])`-Rename-Trick wie bei `list-box%`)/`delete`. Callback
  Event-Typ `'choice`. `get-string-selection`/`set-string-selection` sind **generisch**
  auf mred-Ebene (`mritem.rkt`s `basic-list-control%`, gebaut aus `number`/
  `get-selection`/einer Racket-seitigen Content-Liste) — KEINE eigene Shim-Funktion nötig.
- `radio-box%`: init `parent cb label x y w h labels val style font`. Methoden
  `set-selection`/`get-selection`/`number`/`enable-button i on?`/`button-focus i`.
  Callback Event-Typ `'radio-box`. `style` steuert Layout (`'horizontal` im Style ⇒
  horizontal, sonst vertikal, mirrored gtks `gtk_hbox_new`/`gtk_vbox_new`-Wahl).
  `mritem.rkt`s mred-Ebene konstruiert IMMER mit `val=0` (ein Button muss in einer
  exklusiven Gruppe initial gecheckt sein) und ruft danach ggf. sofort `set-selection`
  erneut mit dem echten Wert (`#f`/positiv) — d. h. `val=-1` an der Platform-Klasse tritt
  in der Praxis nie bei Konstruktion auf, wird aber wie gtk/win32 defensiv behandelt.
- `slider%`: init `parent cb label val lo hi x y w style font`. Nur `set-value`/
  `get-value` — `min-value`/`max-value` werden mred-seitig als reine Racket-Werte
  gehalten (`mritem.rkt`s `slider%`), keine `get-range`/`set-range`-Shim-Funktion nötig
  (anders als `gauge%`, das `get-range`/`set-range` echt braucht).
- Kontrollprobe für „öffentliche Methode vs. generische Glue-Schicht": `choice%`s
  `handles-key-code` wird von `wxlitem.rkt`s `wx-internal-choice%` per `override*`
  spezialisiert (Pfeiltasten/Buchstaben ans Dropdown statt an Navigation) — der
  Default (immer `#f`) sitzt bereits generisch in `wxwindow.rkt` (`public*`), NICHT in
  gtk/win32s Platform-Klasse. Unsere `choice.rkt` definiert `handles-key-code`
  **bewusst nicht** — hätte sonst gegen die `public*`/`override*`-Invariante verstoßen
  (Regel 3, CLAUDE.md).

**Signal→Callback (mirrored `button%`/`check-box%`/`list-box%`):** `QObject::connect`
mit einer C++-Lambda, die nur `cb(ud)` ruft; Racket liest den Zustand danach separat ab.
`QComboBox::currentIndexChanged` statt `activated`, `QButtonGroup::idClicked` statt
`buttonToggled` (Letzteres feuert zweimal pro Klick — für den alt- UND den
neu-gecheckten Button; `idClicked` genau einmal, analog gtks `clicked`-Signal statt
`toggled`).

**Programmatische Zustandsänderungen per `QSignalBlocker` im Shim** (nicht nur
`set-selection`/`set-value`, sondern JEDE Mutation): `QComboBox::addItem`/`clear`/
`removeItem`/`setCurrentIndex` lösen alle `currentIndexChanged` aus (insbesondere der
Sprung von Index -1 auf 0 beim allerersten `addItem` — anders als gtk/win32, wo das
erste Element KEIN automatisches Select auslöst und die Platform-Klasse es explizit
nachholen muss; bei `QComboBox` passiert das automatisch, daher entfällt der
`(when (= count 1) (set-selection 0))`-Schritt aus gtk/win32 komplett). `QSlider::
setValue`/`QButtonGroup`-Mitglieder-`setChecked` ebenso geblockt; beim `radio-box%`
gezielt auf der **Gruppe**, nicht auf dem einzelnen Button, da die Racket-Callback-
Verbindung an `QButtonGroup::idClicked` hängt.

**Härtester Fall: `radio-box% set-selection #f` (kein Button gecheckt) in einer
exklusiven `QButtonGroup`.** Laut Qt-Doku (`qbuttongroup.html`, MCP-Docs-Tool verifiziert
statt angenommen) kann der Nutzer den einzig gecheckten Button einer exklusiven Gruppe
NICHT durch erneuten Klick abwählen — ein anderer Button der Gruppe muss geklickt
werden. Programmatisches `setChecked(false)` direkt auf den Button ist dafür nicht der
dokumentierte Pfad. Fix identisch zu `wx/gtk/radio-box.rkt`s Dummy-Button-Trick: ein
verstecktes, für Racket unadressierbares `QRadioButton` teilt sich dieselbe
`QButtonGroup` (reservierte ID `PLT_RADIO_DUMMY_ID = -1000`); `set-selection -1` checkt
den Dummy, `get-selection` mapped dessen ID zurück auf `-1`. Verifiziert über den Probe
(1-Button-Radio-Box mit `[selection #f]`, Nutzer-bestätigt: startet ungecheckt, „set via
code" mit `#f` bleibt/wird ungecheckt).

**`radio-box%`-Handle bleibt ein echtes `QWidget*`** (der Container mit
`QVBoxLayout`/`QHBoxLayout`), damit die generischen `window%`-Methoden
(`shim_widget_set_geometry`/`shim_widget_get_size_hint` für `seed-size-from-native-hint`)
unverändert funktionieren. Composite-Zustand (Button-Gruppe, Dummy, nächste ID) hängt
als `QVariant<void*>`-Property am Container, nicht als zweites Handle — `window%`s
`handle`-Feld ist single-purpose, gemeinsam genutzte Verdrahtung.

**`seed-size-from-native-hint` nach Befüllung, nicht davor** (§18.2-Muster): `choice%`
nach der `append`-Schleife, `radio-box%` nach dem Button-Aufbau — `sizeHint()` soll den
tatsächlichen Inhalt widerspiegeln, nicht die leere Ausgangsgröße.

**Verifikation:** Klassen-Komposition lädt fehlerfrei (kein `public*`/`override*`-
Konflikt), Smoke 3/3 vor und nach den drei Commits grün, `examples/
value-widgets-probe.rkt` (alle drei Widgets + „set via code"-Buttons pro Widget)
Nutzer-bestätigt: Rendering, Interaktion (Dropdown/Radio-Klick/Slider-Drag), `set-*`
ändert den Wert sichtbar ohne den eigenen Callback erneut auszulösen. Konsolen-Log der
Probe-Prints selbst nicht eingefangen (PowerShell-`Out-String` puffert die komplette
Pipe eines noch laufenden Hintergrundprozesses, unabhängig von Racket-seitigem
`file-stream-buffer-mode` — reine Tooling-Einschränkung dieser Sitzung, kein Befund im
Produkt); die visuelle/interaktive Nutzer-Bestätigung deckt exakt dieselben Kriterien ab
und ist der in diesem Projekt etablierte Verifikationsstandard (§18.3 u. a.).

**Nicht Teil dieser Sitzung:** `tab-panel%` (Block B, eigener Prompt — Stub bleibt
stehen), macOS/Linux-Validierung (separater Prompt nach Push), Preferences-Dialog
Ende-zu-Ende (blockiert durch `tab-panel%`, s. o.), Bitmap-Labels für `radio-box%`
(kein Treiber braucht sie — nur `color-prefs.rkt`/`preferences.rkt`s String-Labels sind
im Scope, analog `list-box%`s Single-Column-Scope-Entscheidung in §18.4).

**Commits (gui-Submodul, `qt-backend`, noch nicht gepusht):** `dc5cef02` (`slider%`),
`3a2b2d8e` (`choice%`), `3ba8fa75` (`radio-box%`) — getrennt pro Widget
(Rollback-Punkte, Nutzer-Präferenz). Shim-Additions (`qt-shim/src/shim.cpp`:
`shim_slider_*`, `shim_choice_*`, `shim_radio_box_*`) sind Umbrella-seitig, noch nicht
committed zum Zeitpunkt dieses Abschnitts.

**Linux-Validierung (2026-07-13-2_report-linux, nach Push):** kein neuer Code — reiner
Sync (lokaler gui-Submodul-Checkout war stale, Fast-Forward auf `3ba8fa75`, bereits auf
`origin/qt-backend`) + Shim-Rebuild (stale-Shim-Falle, `shim.cpp` neuer als
`libracketqtshim.so`) + Probe. `examples/value-widgets-probe.rkt` Nutzer-bestätigt
(Rendering/Interaktion/`set-*`-Non-Retrigger) und diesmal zusätzlich per
Konsolen-Log bestätigt — anders als auf Windows puffert der Linux-Prozess-Capture
nicht, das Log zeigt explizit: Callback feuert nur bei echten Nutzer-Interaktionen,
nie bei einem `set-*`-Aufruf via Code, auch nicht beim härtesten Fall
(`radio-box%` `set-selection #f` in der 1-Button-Gruppe). macOS-Validierung weiterhin
offen.

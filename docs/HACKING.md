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

**Klick-Bug — korrigierte Diagnose (prompt08072026-2, offen, NICHT gefixt):** Die
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

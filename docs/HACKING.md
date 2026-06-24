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

## 7. Shim-Konventionen

- Alle Shim-Funktionen sind in `utils.rkt` via FFI gebunden.
- Der Shim-Handle (`void*`) wird im `handle`-Feld von `window%` gespeichert.
- Qt-Callbacks (`shim_callback_t`) sind FFI-Callbacks mit `#:atomic? #t`:
  sie dürfen **nur** Events in den Eventspace posten, keine Racket-Funktionen direkt aufrufen.
- `shim_canvas_request_repaint` gibt `#t` zurück (in Racket `1` / truthy) — dieser Wert
  muss in `queue-backing-flush` verworfen werden (→ §4).

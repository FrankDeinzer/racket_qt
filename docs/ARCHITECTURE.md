# Qt Backend Architecture

Spike: additives viertes GUI-Backend für `racket/gui` auf Basis von **Qt 6 Widgets** (kein QML).
Aktiviert durch Umgebungsvariable `PLT_QT=1`.

---

## 1. Backend-Auswahl: PLT_QT-Gate

**Datei:** `third_party/gui/gui-lib/mred/private/wx/platform.rkt`

Aktuell wählt Racket das Backend in dieser Funktion:

```racket
(case (if runtime? (system-type) (cross-system-type))
  [(windows) (if (getenv "PLT_WIN_GTK") gtk-lib '(lib ".../win32/platform.rkt"))]
  [(macosx)  '(lib ".../cocoa/platform.rkt")]
  [(unix)    gtk-lib])
```

Das PLT_QT-Gate wird **vor** der OS-Verzweigung eingehängt:

```racket
(define qt-lib '(lib "mred/private/wx/qt/platform.rkt"))

(if (getenv "PLT_QT")
    qt-lib
    (case (if runtime? (system-type) (cross-system-type))
      [(windows) (if (getenv "PLT_WIN_GTK") gtk-lib '(lib ".../win32/platform.rkt"))]
      [(macosx)  '(lib ".../cocoa/platform.rkt")]
      [(unix)    gtk-lib]))
```

Das Qt-Backend wird damit auf allen drei OS wirksam, ohne die bestehenden Pfade zu berühren.
`platform.rkt` exportiert die 43 Symbole (`frame%`, `canvas%`, `button%`, …) via
`(dynamic-require platform-lib 'platform-values)`.

---

## 2. Widget-Mapping: racket/gui ↔ Qt Widgets

| racket/gui       | Qt Widgets                          | Anmerkung |
|------------------|-------------------------------------|-----------|
| `frame%`         | `QMainWindow` (top-level)           | Schließen-Callback postet Event |
| `dialog%`        | `QDialog` (modal/non-modal)         | Spike: noch nicht nötig |
| `panel%`         | `QWidget` + `QBoxLayout`            | Container |
| `canvas%`        | `QWidget` (custom, paintEvent)      | Backing-QImage, render-then-blit |
| `button%`        | `QPushButton`                       | `clicked`-Lambda postet Event |
| `check-box%`     | `QCheckBox`                         | Spike: nicht nötig |
| `choice%`        | `QComboBox`                         | Spike: nicht nötig |
| `message%`       | `QLabel`                            | Spike: nicht nötig |
| `menu-bar%`      | `QMenuBar`                          | Spike: nicht nötig |
| `menu%`          | `QMenu`                             | Spike: nicht nötig |
| `menu-item%`     | `QAction`                           | Spike: nicht nötig |

**Scope für Milestone (Schritt 4):** nur `frame%`, `canvas%`, `button%`.

---

## 3. Event-Loop: Racket treibt, Qt wird gepumpt

### Entscheidung (fix aus Spec)
- **Kein** `QApplication::exec()`, kein eigenes `QEventLoop`.
- `QApplication` wird im Racket-Haupt-OS-Thread erzeugt (kein zweiter Thread für Racket).
- Pumpen: `QApplication::processEvents(QEventLoop::AllEvents, max_ms)`.

### Vorlage: win32/queue.rkt

```
set-check-queue!  ←  events-ready? (GetQueueStatus)
set-queue-wakeup! ←  install-wakeup (unsafe-poll-ctx-eventmask-wakeup)
pump thread:      loop { sync queue-evt; as-entry dispatch-all-ready }
```

### Qt-Variante (wx/qt/queue.rkt)

```racket
;; Shim-Exports (C-Seite):
;;   shim_app_init()          -- erzeugt QApplication, pinnt DPR=1
;;   shim_app_quit()          -- zerstört QApplication
;;   shim_pump(int max_ms)    -- QApplication::processEvents(AllEvents, max_ms)
;;   shim_events_pending()    -- _Bool: gibt es ausstehende Qt-Events?

(set-check-queue!  (lambda () (not (zero? (shim_events_pending)))))
(set-queue-wakeup! (lambda (fds)
                     ;; Windows: unsafe-poll-ctx-eventmask-wakeup (QS_ALLINPUT)
                     ;; macOS/Linux: unsafe-poll-ctx-fd-wakeup mit Qt-Wakeup-FD
                     ;; Für Spike: Polling-Fallback (kein echter Wakeup)
                     (shim_pump 0)))

(define (qt-start-event-pump)
  (thread (lambda ()
            (let loop ()
              (sync/timeout 0.05 (system-idle-evt))
              (sync queue-evt)
              (atomically (shim_pump 10))   ; max 10ms Qt-Events abarbeiten
              (loop)))))
```

**Hinweis zum Wakeup:** Win32 und Cocoa nutzen OS-spezifische Mechanismen
(`unsafe-poll-ctx-eventmask-wakeup`, `unsafe-set-sleep-in-thread!`), damit Racket
aus dem Schlaf aufgeweckt wird wenn Qt-Events ankommen. Für den Spike ist reines
Polling (50ms-Loop) ausreichend; echtes Wakeup ist dokumentierte Folgeaufgabe.

---

## 4. Callback-Disziplin (KRITISCH)

### Invariante
Qt-Slots feuern **synchron innerhalb von `processEvents`** auf dem Racket-Hauptthread
in einem atomaren Moment. Ein C→Racket-Callback darf daher NICHT den Handler synchron
ausführen – das würde mit dem GC oder dem Scheduler kollidieren.

**Regel:** FFI-Callbacks werden mit `#:atomic? #t` und `#:async-apply` definiert.
Sie dürfen ausschließlich ein Event in die Queue des Ziel-Eventspaces **posten**.

### Vorlage: win32/queue.rkt, Zeile 40

```racket
(define _enum_proc (_wfun #:atomic? #t _HWND _LPARAM -> _BOOL))
```

### Qt-Pattern (wx/qt/button.rkt)

```racket
;; Callback-Typ für QPushButton::clicked → Racket
(define _shim_callback
  (_cprocedure (list _pointer)  ; void* userdata
               _void
               #:atomic? #t
               #:async-apply (lambda (thunk)
                               ;; Nur posten, NICHT synchron aufrufen!
                               (queue-event target-eventspace thunk))))

;; Registrierung:
;;   shim_button_set_callback(btn-handle, racket-callback, userdata)
```

Dasselbe gilt für canvas-Resize/Expose-Callbacks und frame-Close-Callbacks.

---

## 5. Zeichnen: Cairo → QImage (render-then-blit)

### Pfad

```
Racket  ──draw──►  cairo_image_surface_t (ARGB32-premult, stride aus cairo_image_surface_get_stride())
        ──blit──►  shim_canvas_blit_argb(handle, data*, w, h, stride)
                     Shim: memcpy → Backing-QImage (Format_ARGB32_Premultiplied)
        ──repaint► shim_canvas_request_repaint(handle)  →  QWidget::update()

Qt     ──paintEvent──►  QPainter::drawImage(0, 0, backing_image)   [nur Pixel kopieren, kein Racket-Aufruf!]
```

### Pixelformat-Kompatibilität

| | Format | Endianness |
|---|---|---|
| Cairo | `CAIRO_FORMAT_ARGB32` = BGRA in memory, premult | native (little-endian x64) |
| Qt | `QImage::Format_ARGB32_Premultiplied` = 0xAARRGGBB in `uint32_t`, little-endian | native |

Auf x64 (little-endian) stimmen beide überein: Byte-Order `B G R A` im Speicher,
`uint32_t` = `0xAARRGGBB`. **Kein Endianness-Sonderfall.**

`stride` kommt aus `cairo_image_surface_get_stride()` (NICHT `width*4` annehmen –
Cairo paddet auf 4-Byte-Alignment, das ist meistens identisch, aber nicht garantiert).

### HiDPI (Spike: abgeschaltet)

```cpp
// shim_app_init():
qputenv("QT_SCALE_FACTOR", "1");
QApplication::setHighDpiScaleFactorRoundingPolicy(
    Qt::HighDpiScaleFactorRoundingPolicy::PassThrough);
```

Cairo rendert 1:1 in Gerätepixeln. Echtes HiDPI ist Folgeaufgabe.

### Expose/Resize aus Qt → Racket

Qt `resizeEvent` und erster `paintEvent` müssen Racket mitteilen, dass neu gezeichnet
werden soll. Das geschieht über einen atomaren, nur einreihenden Callback:

```racket
;; canvas_expose_callback (C→Racket, #:atomic? #t):
(lambda (w h)
  (queue-event target-eventspace
               (lambda () (send canvas on-size w h))))
```

---

## 6. Vorgeschlagene Shim-API (Checkpoint B – zur Fixierung)

```c
/* Lifecycle */
void        shim_app_init(void);          /* QApplication erzeugen, HiDPI pinnen */
void        shim_app_quit(void);          /* QApplication zerstören */
void        shim_pump(int max_ms);        /* processEvents(AllEvents, max_ms) */
int         shim_events_pending(void);    /* 0 = keine Events */
const char* shim_version(void);

/* Callback-Typ */
typedef void (*shim_callback_t)(void* userdata);

/* Fenster (frame%) */
void* shim_window_create(shim_callback_t close_cb, void* userdata);
void  shim_window_set_title(void* win, const char* title);
void  shim_window_set_size(void* win, int w, int h);
void  shim_window_show(void* win, int visible);   /* 1=show, 0=hide */
void  shim_window_destroy(void* win);

/* Canvas (canvas%) */
void* shim_canvas_create(void* parent_win,
                         shim_callback_t expose_cb,  /* w, h als Felder im userdata */
                         void* userdata);
void  shim_canvas_blit_argb(void* canvas, void* data, int w, int h, int stride);
void  shim_canvas_request_repaint(void* canvas);
void  shim_canvas_destroy(void* canvas);

/* Button (button%) */
void* shim_button_create(void* parent_win, const char* label,
                         shim_callback_t click_cb, void* userdata);
void  shim_button_destroy(void* button);
```

**Übergabeprinzip für `userdata`:** Das Shim speichert den Zeiger, Racket besitzt
das Objekt (GC-gemanagt). Racket muss den Callback-Zeiger mit `ffi-obj` am Leben halten.

---

## 7. Dateistruktur wx/qt/

```
third_party/gui/gui-lib/mred/private/wx/qt/
├── platform.rkt   -- exportiert platform-values (44 Symbole wie win32/platform.rkt)
├── queue.rkt      -- shim_app_init/quit/pump, set-check-queue!, event-pump-thread
├── frame.rkt      -- frame% (shim_window_*)
├── canvas.rkt     -- canvas% (shim_canvas_*, Cairo-Integration)
├── button.rkt     -- button% (shim_button_*, clicked-Callback)
├── utils.rkt      -- gemeinsame FFI-Definitionen, shim-lib laden
└── ...            -- Stubs für die anderen 40+ platform-values (not-yet-impl Fehler)
```

---

## 8. Offene Fragen

1. **Wakeup-Mechanismus (plattformspezifisch):** Für richtiges Wakeup aus Qt's
   Event-Dispatcher braucht Win32 `QAbstractEventDispatcher::wakeUp()` →
   `PostMessage(HWND_BROADCAST, WM_NULL, …)` und Linux/macOS einen Pipe-FD.
   Für den Spike: 50ms-Poll-Loop reicht, echter Wakeup ist Folgeaufgabe.

2. **`shim_canvas_create` Layout:** Wie ordnet das Shim Canvas und Button im
   QMainWindow an? Einfachste Lösung: `QVBoxLayout` mit fester Größe.

3. **Mehrere Eventspaces:** Spike nutzt nur einen. Mehrere Eventspaces haben je
   eigene Threads – Qt ist nicht thread-safe; alle Qt-Aufrufe müssen auf dem
   Racket-Hauptthread bleiben (garantiert durch die pump-basierte Architektur).

4. **`as-entry` vs. `atomically`:** win32 nutzt `as-entry` (aus `lock.rkt`) für
   `dispatch-all-ready`. Für Qt soll `atomically` (aus `ffi/unsafe/atomic`) genutzt
   werden, analog zu Cocoa. Muss verifiziert werden, dass `as-entry` keinen
   Vorteil bietet.

5. **Stub-Implementierungen:** Die 40+ anderen platform-values (`choice%`, `list-box%`,
   etc.) müssen als Error-Stubs vorhanden sein, damit platform.rkt die Exports
   vollständig liefert.

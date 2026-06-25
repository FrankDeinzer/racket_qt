# Checkpoint D — Plan: Eingabe-Rückgrat & Editor-Smoke

**Zweck:** Execution-Brief für die nächste Implementierungssession (Claude Code). Baut auf `docs/report240626.md` (Checkpoint C) auf. Die fixen Architektur-Entscheidungen aus `docs/BRIEF.md` / `docs/ARCHITECTURE.md` gelten unverändert und werden hier **nicht** neu verhandelt.

---

## Ziel von Checkpoint D

Der Nordstern ist DrRacket. Dessen Herz ist nicht der Control-Satz, sondern der **Editor** (`text%` / `editor-canvas%`). Schlüssel-Einsicht: `editor-canvas%` ist eine `canvas%`-Unterklasse und zeichnet über den `dc<%>` — und der Cairo→Canvas-Pfad ist seit Checkpoint C bewiesen. Der Editor *reitet* also auf vorhandenem Code. Das wirklich Neue ist das **rohe Eingabe-Rückgrat** (Maus/Tastatur/Fokus + Timer), das du für jedes interaktive Widget ohnehin brauchst.

Checkpoint D beantwortet damit die thesenentscheidende Frage: **Läuft der Editor auf Qt?** — *nicht* Widget-Breite (das ist Checkpoint E).

Abgrenzung zum Button-Klick aus Checkpoint C: Der bewies die Pump und den Weg *Qt-Signal → atomarer Post → Racket-Handler* für **ein vorverdautes, nutzlastfreies** Ereignis (`clicked`). Er beweist **nicht** den rohen Eingabe-Pfad: `on-event` mit `mouse-event%` (Typ, x/y, Modifier) und `on-char` mit `key-event%`. Genau den baut D-1.

---

## Geltende Grundlagen (nicht neu verhandeln)

- **Event-Loop:** Racket treibt, Qt wird gepumpt (`shim_pump` → `processEvents`). Kein `QApplication::exec()`, kein `QEventLoop`.
- **Callbacks:** FFI-Callbacks `#:atomic? #t` — dürfen nur Events in den Eventspace **posten**, niemals synchron Racket-Code aufrufen.
- **Zeichnen:** Cairo → Backing → `shim_canvas_blit_argb` → `QImage` → `paintEvent`. Kein eigener QPainter.
- **HiDPI:** auf 1 gepinnt.
- **Deployment:** racket lädt die Shim-DLL via FFI; kein App-Bundle.
- **`public*`/`override*`-Invariante** (`docs/HACKING.md §1`): regiert **jede** neue Plattform-Klasse/-Methode. Override-Ziele müssen existieren, Framework-`public`-Namen dürfen nicht doppelt sein. Bei jedem neuen Widget zuerst die Methoden klassifizieren und die Tabelle in HACKING.md fortschreiben.

## Arbeitsweise

- Kleine Schritte, häufige kleine Commits, an den Checkpoints **anhalten** und auf Review warten.
- Bei Unklarheit oder Risiko: **anhalten und fragen**, nicht raten.
- Bestehende Backends (cocoa/gtk/win32) **nicht** anfassen. Alles Neue ist additiv und `PLT_QT`-gegated.
- Shim minimal halten: nur die Teilmenge, die der jeweilige Meilenstein braucht.

---

## D-0 — Layout-Refactor (Fundament zuerst)

**Problem:** Das Shim ordnet Canvas und Button aktuell per `QVBoxLayout` an. Das umgeht Rackets eigenes Layout-System. Die nativen Backends nutzen **keine** nativen Layout-Manager — *Racket* rechnet die Geometrie, Kinder werden absolut positioniert.

**Aufgabe:**
- `QVBoxLayout` aus dem Shim entfernen. Neue Shim-Funktion (z. B. `shim_widget_set_geometry(handle, x, y, w, h)`); Kinder bekommen ihre `(x,y,w,h)` von Racket diktiert.
- `panel%` vom Stub zu einem echten Container-`QWidget` machen (reiner Container, das Geometrie-Diktat reicht es an Kinder durch).

**Akzeptanz (Checkpoint D-0):** `examples/hello.rkt` verhält sich unverändert (Button unter Canvas), aber positioniert durch Racket; kein `QLayout` mehr im Shim; `panel%` real.

> Falls dies mehr als ein kleiner Refactor wird: **anhalten und melden** — dann bewerten wir, ob D-0 vor oder nach dem Editor sinnvoller liegt.

---

## D-1 — Eingabe-Rückgrat + Timer + Test-Harness (Kern von D)

Auf einem nackten `canvas%` den rohen Eingabe-Pfad bauen:

**Qt-seitig (im Canvas-`QWidget`):**
- Maus: `mousePressEvent` / `mouseReleaseEvent` / `mouseMoveEvent` (+ `setMouseTracking(true)` für Bewegung **ohne** gedrückte Taste), `enterEvent` / `leaveEvent`.
- Tastatur: `keyPressEvent` / `keyReleaseEvent`. **Falle:** Focus-Policy auf `Qt::StrongFocus` setzen, sonst kommt nie ein Key-Event an.
- Fokus: `focusInEvent` / `focusOutEvent`.

**Shim-seitig:** Callbacks **mit Nutzlast** (anders als der parameterlose `click_cb`): Typ, x, y, Modifier bzw. Key-Code über die FFI-Grenze tragen. Die atomare, nur-einreihende Disziplin wächst von „0 Argumente" auf „Struct/mehrere Skalare".

**Racket-seitig:** Qt-Codierungen übersetzen (`Qt::MouseButton`, `Qt::KeyboardModifiers`, Qt-Key-Codes) → Felder von `mouse-event%` / `key-event%`; damit `on-event` / `on-char` des Canvas aufrufen.

**Timer-Hälfte:** ein Eventspace-`timer%`, der den Canvas periodisch invalidiert (Grundlage fürs spätere Caret-Blinken).

**Test-Harness (ab jetzt mitlaufend):** `raco test`-Konstruktions-Smoke — unter `PLT_QT` jede implementierte Plattform-Klasse instanziieren, eine Frame zeigen, N Events pumpen, sauber schließen; jede Exception = Fail. Fängt automatisch die `public*`/`override*`-Regressionen, die sonst still bei einem Versionssprung brechen.

**Beispielprogramm:** `examples/input.rkt` — zeigt live empfangene Maus-Koordinaten, getippte Zeichen und Modifier; ein per Timer bewegtes Kästchen.

**Akzeptanz (Checkpoint D-1):** `input.rkt` zeigt Maus-Bewegung (auch ohne Taste), Klicks mit Koordinaten, getippte Zeichen mit Modifiern, Fokuswechsel; der Timer animiert; `raco test`-Smoke grün.

---

## D-2 — Editor-Smoke (der thesenentscheidende Meilenstein)

Ein `editor-canvas%` mit einem `text%`:
- Tippen fügt Text ein; Klick setzt das Caret; Maus-Drag selektiert; Caret blinkt (nutzt den Timer aus D-1); Basis-Scrollen, wenn der Text die Sicht übersteigt (Scrollbars sind laut Report noch Stubs → das Minimum implementieren, das der Editor braucht).

Hinweis: Das Zeichnen ist bereits bewiesen; neu ist nur das **Zusammensetzen** von Eingabe + Timer + Scrollen. D-2 ist also überwiegend Verdrahtung der D-1-Bausteine.

**Akzeptanz (Checkpoint D-2):** `examples/editor.rkt` — Text tippen, Caret per Klick setzen, per Drag selektieren, Caret blinkt, Scrollen funktioniert. Damit ist „Editor läuft auf Qt" beantwortet.

---

## Parallel — macOS-Smoke (billiger Prämissen-Check)

Jederzeit während D, auf dem Mac-Entwicklungsrechner:
- Shim mit dem `macos`-Preset compilieren, RPATH auf die Qt-Frameworks, `examples/hello.rkt` starten.
- **Speziell prüfen:** ob die gepumpte `processEvents`-Schleife auf macOS' nativer Run-Loop sauber läuft — historisch der zickige Fall für „kein `exec()`".

**Akzeptanz:** `hello.rkt` öffnet, zeichnet, Button-Klick funktioniert auf macOS. Falls die gepumpte Schleife auf macOS zickt → **anhalten und melden**: das ist ein Befund, der die ganze Qt-These betrifft, kein Detail.

---

## Bewusst NICHT in Checkpoint D (später)

- **Widget-Breite** (`dialog%`, `message%`, Menüs, `check-box%`, `choice%`, `list-box%`, …) = **Checkpoint E**, priorisiert nach einer konkreten App.
- **Voller macOS/Linux-Ausbau** über den Smoke hinaus.
- **Wakeup-Mechanismus** über den 50ms-Poll hinaus (`QAbstractEventDispatcher::wakeUp()`) — Polish, kein D-Blocker.
- **Echtes HiDPI** (bleibt auf 1 gepinnt).
- **Mehrere Eventspaces.**

---

## Reihenfolge & Abhängigkeiten

```
D-0 (Layout) → D-1 (Eingabe + Timer + Test) → D-2 (Editor-Smoke)
                         macOS-Smoke ── parallel ──┘
```

D-1 ist die Voraussetzung für D-2 (Editor = zusammengesetztes D-1). Der Test-Harness läuft ab D-1 mit.

## Doku-Pflichten je Meilenstein

- **`HACKING.md`:** neue Vertrags-Einträge (`public*`/`override*`), neue Lektionen.
- **`STATUS.md`:** append-only Session-Log (Format wie `report240626.md`).
- **`ARCHITECTURE.md`:** nur, wenn sich eine fixe Entscheidung ändert — mit Begründung.
- **Commits in beide Repos** (Umbrella + gui-Fork), Submodul-Zeiger im Umbrella aktualisieren.

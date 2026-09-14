# Report — Instrument repariert, §25.1 und §21.7 gefixt (Linux) — 2026-09-14

> # ⚠ VOR DEM NÄCHSTEN PULL AUF WINDOWS/macOS LESEN
>
> Diese Sitzung enthält eine **Shim-ABI-Änderung**: `shim_window_set_resize_cb` ist neu
> (§32). **`qt-shim` muss auf Windows und macOS nach dem Pull neu gebaut werden** —
> Bauanleitung je Plattform in `CLAUDE.md`. Ohne Rebuild schlägt bereits das Laden des
> Forks fehl, und zwar **laut und sofort** (auf Linux gegen den alten Shim verifiziert):
>
> ```
> ffi-obj: could not find export from foreign library
>   name: shim_window_set_resize_cb
>   system error: ... undefined symbol: shim_window_set_resize_cb
> ```
>
> Es gibt keinen Modus, in dem der Callback still null bleibt und Frames einfach nicht
> reflowen — wer diese Meldung sieht, hat den Rebuild vergessen. Gleiche Klasse wie §27.

**Auftrag:** Schritt 1 aus der Empfehlung am Ende von `docs/2026-09-13_report-linux.md`
(= `docs/HACKING.md` §21.9): das Messinstrument reparieren, bevor ein vierter
`resizeEvent`-Wiring-Versuch überhaupt sinnvoll wird. Kein eigener Prompt — direkte
Fortsetzung auf Nutzerwunsch; die Schritte 1 und 2 kamen danach je auf eigene Ansage
dazu.

Gemessene Version: `~/racket/bin/racket --version` → **v9.3 [cs]** (x86-64, `~/racket`,
nicht im PATH). Sitzungstyp `x11`. Qt 6.11.1.

**Ergebnis in drei Sätzen:** Die Root-Cause des Instrumentenfehlers ist gefunden, aus dem
Primärcode belegt und gegen natives GTK kontrolliert — vier Proben sind repariert und
tragen ab jetzt ihren Gültigkeitsbeweis (`PUMP OK`) im eigenen Log; als direkter Ertrag
ist die offen gebliebene Klick-Verifikation der Enable-Kaskade nachgeholt (**n=3, 3/3
PASS**). Mit dem reparierten Instrument wurde die §21.7-Kernfrage in echtem DrRacket
gemessen: **§25.1 ist gefixt** (`get-client-size` unterschlug die Menüleistenhöhe) und
gehörte nie zu §21.7 — rein Racket-seitig, **ohne** Shim-Änderung (§31). Danach auf
Nutzerwunsch **§21.7 selbst gefixt** (§32, vierter Anlauf, der erste der hält) — mit
Shim-ABI-Änderung, s. Kasten oben.

**Inhalt:** Phase 0–3 (Instrument) · „Schritt 1" (§31, `get-client-size`) · „Schritt 2"
(§32, `resizeEvent`) · methodische Lehre · Liste „später zu validieren".

---

## Phase 0 — Umgebung

- Umbrella `main` und Submodul `third_party/gui` (`qt-backend`) zu Sitzungsbeginn
  **sauber und synchron mit `origin`** (`git status` leer, Submodul-HEAD `a787b43f`).
  Kein Pull/Push nötig, keine Rückfrage nach Regel 7 ausgelöst.
- Stale-Shim-Check: `libracketqtshim.so` (2026-09-13 22:38:15) neuer als `shim.cpp`
  (22:38:00) — Stand nach dem Block-B-Rollback, kein Rebuild nötig.
- Smoke-Gate: `raco test tests/smoke.rkt` **ohne** `PLT_QT` **3/3 grün**, **mit**
  `PLT_QT=1` **3/3 grün**.

---

## Phase 1 — Root Cause des Instrumentenfehlers

### 1.1 Aus dem Primärcode belegt (kein Qt-Bezug)

| Fundstelle | Aussage |
|---|---|
| `wx/common/queue.rkt:357` | `(define main-eventspace (make-eventspace* (current-thread)))` — in einem bare-`racket`-Skript **ist der Hauptthread selbst der Handler-Thread** des Haupt-Eventspace. (Ein per `make-eventspace` erzeugter Eventspace bekommt dagegen einen eigenen Thread, Z. 366–395 — daher die falsche Intuition, „die Queue läuft schon irgendwo nebenher".) |
| `wx/common/queue.rkt:464/475` | `yield` dispatcht Events **nur** aus dem Handler-Thread heraus. |
| — | `(sleep n)` dispatcht nichts. Ein schlafender Hauptthread ist ein Handler-Thread, der die Queue nicht bedient. |
| `wx/common/queue.rkt:637–641` | Der überschriebene `executable-yield-handler` ruft beim Programmende `(yield main-eventspace)` — **dort** wird die aufgestaute Queue abgearbeitet. |

Damit ist der §21.9-Befund („gepostetes Thunk läuft erst, nachdem der Hauptthread fertig
ist") lückenlos erklärt, ohne Restannahme. Der 50-ms-`shim_pump`-Thread
(`wx/qt/queue.rkt:23`) widerspricht nicht: er drainiert **Qts** Event-Loop — deshalb
feuerten die C-Callbacks (`close_cb` 7 ms nach Anstoß) korrekt und prompt. In die
Racket-Queue **posten** ist aber nicht dasselbe wie sie zu **dispatchen**.

### 1.2 Empirischer Diskriminator

Probe (Scratchpad, nicht committet): Frame zeigen, sofort ein `queue-callback` posten,
dann sechs Wartezyklen, danach ein einzelnes `(yield)`.

| Lauf | Backend | Warteprimitiv | Thunk lief nach | `(yield)` danach |
|---|---|---|---|---|
| A | Qt (`PLT_QT=1`) | `(sleep 1)` | **5014,2 ms** (erst nach der Schleife) | `#t` — es lag die ganze Zeit ein Event in der Queue |
| B | Qt (`PLT_QT=1`) | `(sleep/yield 1)` | **11,7 ms** (0,6 ms nach dem Posten) | `#f` — Queue leer |
| C | **nativ GTK** (ohne `PLT_QT`) | `(sleep 1)` | **5019,6 ms** | `#t` |

**Lauf C ist der entscheidende Kontrollwert:** natives GTK verhält sich byte-gleich zu
Qt. Der Effekt sitzt im Shared Code, das Qt-Backend ist unbeteiligt. Ein Lauf genügte
dafür (der Mechanismus ist Shared-Code-Semantik, keine Plattformfrage).

---

## Phase 2 — Die Reparatur

**Neu: `examples/pump-gate.rkt`** (umbrella, keine Submodul-Änderung), zwei Exporte:

- `(wait/pump secs)` ersetzt `(sleep secs)` — wartet über `sleep/yield`, also
  dispatchend.
- `(pump-gate!)`, direkt nach `(send frame show #t)` aufgerufen, postet ein Prüf-Thunk;
  der erste `wait/pump`-Aufruf loggt `[pump-gate] PUMP OK (n ms)` oder `PUMP FAIL`.

Der Gate-Print ist der eigentliche Punkt: **jede Probe trägt ihren Gültigkeitsbeweis ab
jetzt im eigenen Log.** Ein „eingefrorenes" Ergebnis ohne `PUMP OK` ist damit als
Instrumentenfehler erkennbar, statt — wie am 2026-09-13 geschehen — als Produktbefund
missdeutet zu werden.

**Repariert (alle vier Proben mit `(sleep n)`-Wartemuster):**

| Probe | Änderung | verifiziert |
|---|---|---|
| `enable-cascade-probe.rkt` | `sleep`→`wait/pump`, Pump-Gate, Klick-Callback loggt, meldet Button-Koordinaten, Positivkontrolle + Urteilszeile | `PUMP OK (0,3–0,5 ms)`, s. Phase 3 |
| `live-resize-probe.rkt` | `sleep`→`wait/pump`, Pump-Gate | — (braucht die zurückgerollte Verdrahtung) |
| `is-shown-probe.rkt` | `sleep`→`wait/pump`, Pump-Gate | `PUMP OK (0,1 ms)` |
| `resize-reflow-probe.rkt` | `sleep`→`wait/pump`, Pump-Gate | `PUMP OK (0,3 ms)`, Reflow 400×300 → 400×609 wie gehabt |

Jede reparierte Probe trägt zusätzlich einen Kopfkommentar, der den Instrumentenfehler
benennt — damit die nächste Session ein eingefrorenes Ergebnis nicht erneut fehldeutet.

---

## Phase 3 — Direkter Ertrag: die offene Klick-Verifikation aus Block A nachgeholt

Block A konnte nicht belegen, dass `(send b enable #f)` den Klick **nativ** unterdrückt
— der Zähler blieb in allen Versuchen bei 0, was dort einem ungeklärten
X11-Fokus-/Stacking-Problem zugeschrieben wurde. Die Begründung des Fixes stützte sich
deshalb nur auf die gelesene Qt-Framework-Garantie.

### 3.1 Zwei Ursachen, beide jetzt geklärt

1. **Der Zähler konnte strukturell nie hochzählen.** Der Button-Callback wird über die
   Eventspace-Queue dispatcht; die Probe wartete mit `(sleep 8)`. Ob der Klick ankam,
   war für den Zähler ohne Belang — er hätte auch bei perfektem Klick 0 angezeigt.
2. **Die Klicks gingen tatsächlich daneben — aber aus einem banalen Grund.** Damit die
   Automatisierung nicht raten muss, meldet die Probe ihre Button-Mitte jetzt selbst per
   `client->screen`. Dabei zeigte sich: **unmittelbar nach `(send f show #t)` liefert
   `client->screen` fensterrelative statt absoluter Koordinaten.**

   | Zeitpunkt der Abfrage | gemeldet | tatsächliche Fensterposition (`xwininfo`) |
   |---|---|---|
   | sofort nach `show` | `150 35` | `853,437` |
   | nach einem `(wait/pump 1)` | **`1003 472`** (= 853+150, 437+35) ✅ | `853,437` |

   Der Fenstermanager hatte das Fenster zum ersten Zeitpunkt noch nicht platziert, Qts
   `mapToGlobal` rechnete gegen `0,0`. **Kein `wx/qt`-Defekt, ein Timing-Fehler der
   Messung** — aber genau er erklärt Block As Beobachtung, der synthetische Klick
   „hebe das Terminalfenster an": der Klick ging nach `(150,35)`, also in die
   Bildschirmecke, wo das Terminal lag. Die dort vermutete X11-Stacking-Eigenheit wird
   nicht benötigt und gilt als aufgeklärt.

   Gegenprobe nativ: GTK meldete `150 42` bei Fensterposition `1,29` — also korrekt
   umgerechnet. Der Unterschied ist allein die Abfragezeit, nicht das Backend.

### 3.2 Messung mit repariertem Instrument, n=3

Ablauf je Lauf: Probe starten → Koordinaten aus dem Log lesen (nach dem dispatchenden
Warteschritt) → sichtbares Fenster über `xwininfo … IsViewable` wählen →
`windowactivate --sync` + `windowraise` → `mousemove` + `click 1` auf den **enabled**
Button (Positivkontrolle) → warten bis `READY-FOR-CLICK-2` → `enable #f` ist gesetzt →
identischer Klick auf dieselbe Stelle.

| Lauf | Pump-Gate | enabled (Positivkontrolle) | disabled (Delta) | Urteil |
|---|---|---|---|---|
| 1 | `PUMP OK (0,4 ms)` | **1** | **0** | PASS |
| 2 | `PUMP OK (0,3 ms)` | **1** | **0** | PASS |
| 3 | `PUMP OK (0,4 ms)` | **1** | **0** | PASS |

**3/3 PASS.** Der Enable-Kaskaden-Fix (`a787b43f`, §26 Fund 2) ist damit **empirisch
verifiziert** statt nur über gelesene Framework-Garantie begründet. Die Probe fällt
selbst ein Urteil und markiert einen Lauf explizit als `UNGUELTIG`, wenn die
Positivkontrolle nicht zählt — ohne sie wäre ein „disabled feuert nicht" wertlos, weil
eine defekte Automatisierung dasselbe Bild erzeugt.

---

## Revision früherer Befunde

**Ungültig (Instrumentenartefakt):**

- §21.9 „das aus `resizeEvent` geposteste Thunk läuft nie" — und ebenso der
  `closeEvent`-Diskriminator. Beide messen nur das defekte Warteprimitiv.
- §21.9 **„keine Rückkopplungsschleife"**. Diese Entwarnung ist zu streichen: die
  befürchtete Schleife setzt voraus, dass das geposteste Thunk läuft und `set-size`
  aufruft, was ein weiteres natives Resize auslöst. Genau dieses Thunk lief nie — der
  Pfad wurde **nie durchlaufen**. Das Risiko ist **ungeprüft, nicht entkräftet**. Ein
  vierter Wiring-Versuch darf sich nicht auf §21.9 als Entwarnung berufen.
- Block As Klick-Verifikation samt der dort vermuteten Fokus-/Stacking-Ursache
  (Korrekturkasten im 2026-09-13-Report eingefügt).

**Ausdrücklich weiterhin gültig — diese Entdeckung darf nicht in Generalzweifel kippen:**

- §21.9 „kein Crash, kein Hänger" beim verdrahteten `resizeEvent` (direkt beobachtet,
  hängt nicht an der Queue).
- Die Konvergenz-Messung (`resize-reflow-probe.rkt`): die Kette `reflow-container` →
  `child-redraw-request` → `force-redraw` → `resized` läuft **synchron** im
  Hauptthread, ist kein gepostetes Event.
- Die `is-shown?`-Basisfeld-Messung (§23.3): die `show`-Aufrufe laufen synchron während
  der Konstruktion.
- Der `test-dock-size`-Akzeptanztest (0/3): lief in **echtem DrRacket**, das
  nachweislich pumpt.
- **Beide Commits aus Block A stehen unverändert:** `2f0755bd` (`is-shown?`-Cluster) und
  `a787b43f` (Enable-Kaskade) — letzterer ist durch diese Session sogar erstmals
  empirisch belegt.

---

## Nicht gemacht (bewusst)

- **Kein vierter `resizeEvent`-Wiring-Versuch.** Das ist Schritt 2 der Empfehlung,
  erfordert eine Shim-ABI-Änderung (Rebuild-Zwang auf allen drei Maschinen, Regel 8)
  und war schon am 2026-09-13 ausdrücklich der Nutzerentscheidung vorbehalten.
- **Keine Cross-Platform-Validierung** (Cross-Platform-Modell aus
  `docs/2026-09-13_prompt.md`: gebündelt, nicht pro Block).
- Keine Änderung an `wx/qt/`, `shim.cpp` oder Shared Code — diese Session hat
  ausschließlich `examples/` und `docs/` angefasst.

## Nächste Schritte (unverändert in dieser Reihenfolge, jetzt mit tragfähigem Instrument)

1. **Die eigentliche §21.7-Kernfrage:** warum reflowt der Preferences-Dialog in echtem
   DrRacket nicht, obwohl dessen Eventspace-Queue nachweislich sauber läuft? Echtes
   DrRacket war nie vom Instrumentenfehler betroffen — dieser Befund steht unverändert
   und ist jetzt der einzige belastbare Ausgangspunkt. **Wichtig für die Abgrenzung:
   dieser Schritt braucht weder `live-resize-probe.rkt` noch eine Shim-Änderung** — die
   Harness ist echtes DrRacket. „Instrument repariert" ist ausdrücklich **kein**
   Freibrief, direkt zum Wiring-Versuch zu springen.
2. Erst danach ggf. der vierte `resizeEvent`-Wiring-Versuch, mit `live-resize-probe.rkt`
   als nun tragfähigem Messmittel (Pump-Gate muss im Log stehen) — **Nutzerentscheidung
   wegen Shim-ABI**.

## Schritt 1 ausgeführt — §25.1 gefixt, und es war nie ein §21.7-Fall

Nach der Instrumenten-Reparatur direkt die §21.9-Kernfrage angegangen: Preferences-Reflow
in **echtem DrRacket** (die Harness, die nachweislich pumpt — und die vom
Instrumentenfehler nie betroffen war). Details: `docs/HACKING.md` §31.

**Messung (frischer Start, keine Interaktion außer Öffnen):** Dialog **1060×641**,
Button-Zeile nur als Pixelstreifen am unteren Rand — §25.1 auf Linux exakt reproduziert.
Die bereits vorhandene `PLT_QT_DEBUG`-Ausgabe in `shim.cpp` lieferte die Zahl ohne jede
Codeänderung: `mb.height=22 … central.geom=(0,22 1060x619)`. Fenster 641 hoch,
**nutzbarer Client 619** — Defizit exakt die Menüleistenhöhe. `wx/qt/window.rkt:61`
liefert für `get-client-size` aber dasselbe wie `get-size`.

**Root Cause, zwei Defekte aus einer Ursache:** `wxtop.rkt:302` leitet die
Chrome-Reserve als `(- (get-height) f-client-h)` ab — unter Qt immer 0. Dadurch wird
(1) die Mindesthöhe des Frames zu klein berechnet, das Fenster wächst gar nicht erst auf
die nötige Höhe, und (2) `set-panel-size` reicht 641 statt 619 durch, die untersten
22 px des Panels liegen außerhalb des sichtbaren Bereichs. **Kein Resize beteiligt** —
§25.1 war unter §21.7 falsch einsortiert und lag deshalb zwei Sessions hinter dessen
OUT-OF-SCOPE-Zaun.

**Fix:** `wx/qt/frame.rkt` merkt sich das QMenuBar-Handle und zieht dessen
`sizeHint().height()` in `get-client-size` ab — über das **bereits existierende**
`shim_widget_get_size_hint`, also **keine Shim-ABI-Änderung und kein Rebuild-Zwang auf
Windows/macOS**. Lazy statt gecacht, weil die Bar zum `set-menu-bar`-Zeitpunkt noch
keine Actions hat und `sizeHint.h=0` meldet (gemessen). gtks zusätzlicher
`(send this resized)`-Aufruf ist unter Qt nicht nötig — `correct-size` greift den Wert
von allein auf.

| Prüfung | Ergebnis |
|---|---|
| Dialoghöhe | 1060×641 → **1060×663** (+22 px) |
| Button-Zeile sichtbar **und** klickbar (OK schließt) | ja, beim ersten Öffnen, ohne manuelles Vergrößern |
| Akzeptanztest | **n=3, 3/3 PASS**, Maß in allen Läufen identisch |
| `test-dock-size`-Regressionswache | **2/2 crashfrei** (§30-Fix intakt) |
| DrRacket-Hauptfenster | unverändert 600×650 — minimaler Wirkradius |
| Smoke | 3/3 mit und ohne `PLT_QT` |

**Abgrenzung, ausdrücklich:** §21.7 bleibt offen — Kind-Controls wandern beim
Fenster-Vergrößern weiterhin nicht mit, dafür fehlt nach wie vor die
`resizeEvent`-Verdrahtung. Dieser Fix behebt die **initiale** Fehlgeometrie jedes Frames
mit Menüleiste, nicht das Live-Resize-Verhalten.

**Nachtrag zum §30-Audit:** `get-client-size` ist Muster 3 (fehlender Override, den alle
drei nativen Backends haben) und wurde dort übersehen, weil das Audit nur
Zustands*abfragen* wie `is-shown?` als Kandidaten geführt hat. Für ein künftiges Audit:
auch Geometrie-/Maß-Methoden gegen die nativen Backends prüfen.

## Schritt 2 ausgeführt — §21.7 gefixt (vierter Anlauf, der erste der hält)

Auf Nutzerwunsch direkt im Anschluss. Volles Detail: `docs/HACKING.md` §32.

**Was den Unterschied machte — keine neue Messtechnik, sondern ein Blick in
`wx/gtk/window.rkt`:** GTKs `remember-size` meldet einen Resize nur weiter, wenn er die
Größe **tatsächlich** ändert, und `set-size` schreibt den Cache **bevor** es das native
Fenster resized. Das Echo des eigenen `set-size` findet den Cache damit schon gleich und
läuft ins Leere — genau dort, wo Fix-Versuch 1 endlos lief. `wx/qt/frame.rkt:75-77` hatte
diese Reihenfolge längst; es fehlte nur der Dedup. **Nebeneffekt:** Versuch 3s zweite
Shim-Funktion (`shim_window_get_size`) entfällt, weil der Cache die Wahrheit ist, sobald
`remember-size` ihn pflegt — eine neue Shim-Funktion statt zweier.

**Messungen, in der vom Risiko diktierten Reihenfolge** (alle mit `PUMP OK` im Log —
erst dadurch zulässig):

1. **Diskrete Resizes, stretchbar:** Button folgt 296 → 696 → 896 → 496 px, jede Größe
   stabil. Erstmals in vier Versuchen reflowt der Inhalt. *(Die Probe brauchte dafür eine
   Korrektur: ihr Button war nicht stretchbar und hätte auch bei perfektem Reflow
   konstant 80×25 gemeldet.)*
2. **Korrekturzweig durch echtes natives Resize** (Versuch 1s Todesfall), instrumentiert
   in `wxtop.rkt` und danach zurückgerollt: `new=300x200 correct=300x348` →
   `KORREKTUR-ZWEIG: set-size 300x348` → `new=300x348 correct=300x348`. **Genau eine
   Korrektur**, das Echo vom Dedup geschluckt.
3. **Live-Drag mit echtem Mausziehen** (Versuch 1 *und* 2 starben hier): stretchbar 9
   Resizes live nachgeführt, 0 Korrekturen; unter die Mindestgröße gezogen 24 Resizes,
   6 Korrekturen bei 8 Drag-Schritten, jede mit genau einem sauberen Recheck. Prozess
   lebt, Eventspace tickt weiter, **kein „Nachspielen" nach dem Loslassen** — Versuch 2s
   Symptom blieb aus, wie erwartet (X11 hat keine modale Resize-Schleife wie Windows).
4. **Echtes DrRacket:** Preferences-Dialog 1060×663 → 1200×820 gezogen, Tab-Zeile,
   rechte Feldspalte und Button-Zeile folgen alle; OK klickt an seiner **neuen**
   Position.

**Gate:** Smoke 3/3 beide Wege, drei Proben unverändert, `test-dock-size` 2/2 crashfrei,
§31-Akzeptanztest 3/3 PASS bei unverändertem Dialogmaß.

**Nebenfund für künftige Proben:** der Korrekturzweig lässt sich **nicht** über
`[stretchable-width #f]` an einem eigenen Panel erzwingen — das implizite Top-Panel des
Frames bleibt stretchbar (gemessen `stretch=#t/#t`). Zuverlässig ist nur: Inhalt mit
großer Mindestgröße bauen und das Fenster von außen darunter ziehen. Eine Probe, die
diesen Irrweg beschritt, wurde wieder entfernt statt committet.

**⚠ Shim-ABI-Änderung:** `shim_window_set_resize_cb` ist neu — **Windows und macOS
müssen `qt-shim` nach dem Pull neu bauen**, sonst schlägt bereits das Laden fehl
(`get-ffi-obj`). Gleiche Klasse wie §27.

## Vormessung für den Scroll-Block (nur Messung, kein Fixversuch)

**Warum jetzt:** Der Scroll-Cluster war in der 13.09.-Planung ausdrücklich **hinter** die
Geometrie gestellt worden, mit der Begründung, der Windows-Fixversuch (§24.5) habe
gemessen, dass `do-set-scrollbars` einmal bei 30×30 feuert, eine degenerierte
1×1-Range einfriert und beim Wachsen auf 400×300 **nie wieder** feuert — „das ist die
fehlende Resize-Benachrichtigung, nicht der Scrollbar-Code". Genau die gibt es seit §32.
Zusätzlich hatte §26 vermutet, der Fixversuch sei (auch) am Sichtbarkeitsvertrag
gescheitert. Drei Vorbedingungen haben sich also seit der letzten Messung geändert —
damit ist „hat sich das Symptom bewegt?" eine echte neue Frage.

**Probe:** `examples/scroll-probe.rkt` (neu, dauerhaft): isolierter `editor-canvas%` mit
`'(auto-hscroll auto-vscroll)`, `text%` mit 100 absichtlich breiten Zeilen, Frame
400×300. `PUMP OK (0,5 ms)` im Log — Messung gültig.

| Aspekt | vorher (Linux, 2026-09-13) | **jetzt** |
|---|---|---|
| Rendering | farblich verstümmelt/gestreift, nur ein Fragment oben links | **sauber** — schwarzer Text auf weiß, Zeilen 0–11 lesbar |
| Reflow beim Vergrößern | (nicht messbar, Resize unverdrahtet) | **funktioniert** — 400×300 → 900×600 zeigt Zeilen 0–24 in voller Zeilenbreite |
| Scrollbar sichtbar | nein | **nein** |
| Mausrad (8×) | wirkungslos | **wirkungslos** (weiterhin Zeile 0 oben) |
| PageDown (2×) | wirkungslos | **wirkungslos** |
| Scrollen nach Resize | — | **weiterhin wirkungslos** (6× Mausrad nach dem Vergrößern) |

**Einordnung — das vereinfacht den Block erheblich:**

1. **Die Rendering-Hälfte des Linux-Symptoms ist weg.** Das gestreifte Bild war kein
   eigener Stride-/Backing-Buffer-Defekt (die in der Vorsession notierte Hypothese),
   sondern Folge der falschen Geometrie. Der dort empfohlene Stride-Verdacht ist damit
   **erledigt und nicht weiterzuverfolgen**.
2. **Linux und macOS zeigen jetzt dasselbe Symptom:** Inhalt rendert korrekt, Scrollen
   wirkungslos. Aus drei plattformspezifischen Ausprägungen ist **eine** geworden.
   (Windows — „Inhalt komplett weiß" — ist nach dem Rebuild gegenzuprüfen; die
   Erwartung ist, dass es sich ebenfalls angleicht, da derselbe Geometriefehler dort
   ebenso wirkte.)
3. **Was übrig bleibt, ist eine schlichte Lücke, kein Rätsel.**
   `wx/qt/canvas.rkt:300-307` führt sämtliche Scroll-Methoden als ausdrückliche Stubs
   („Scroll stubs — no scrollbars in the spike"): `get/set-scroll-pos`,
   `get/set-scroll-page`, `get/set-scroll-range`, `show-scrollbars` — alle `(void)`
   bzw. `0`. Es ist **keine kaputte Implementierung, sondern eine fehlende**.
4. **Die Shim-Primitiven liegen bereits bereit:** `shim_scrollbar_create`,
   `shim_scrollbar_set_range`, `shim_scrollbar_set_value`, `shim_scrollbar_get_value`
   (Commit `7d1231e0`, damals bewusst als ungenutzte Grundlage stehen gelassen).
   **Der Block braucht daher voraussichtlich keine Shim-ABI-Änderung** — anders als §32.

**Kein Fixversuch** (Auftrag war reine Messung; der Block gehört in eine eigene Sitzung
mit frischem Kontext).

## Methodische Lehre — Vorschlag für die Triage-Regel im nächsten Prompt

Der Instrumentenfehler war zwei Sessions lang unsichtbar, obwohl er in vier Zeilen
Shared Code steht. Das lag **nicht** an mangelnder Disziplin — im Gegenteil: Regel 4
(„Budget erschöpft → parken, nie ein spekulativer Fix") hat korrekt gegriffen und einen
vierten Blindversuch verhindert. Die Regel hat aber eine Lücke, und die hat hier die
Kosten verursacht.

**Was die Regel heute leistet:** sie verhindert spekulative Fixes.
**Was sie nicht leistet:** sie fragt nie, ob das Messmittel trägt. Ein Null-Ergebnis aus
einem ungeprüften Instrument wird derzeit wie ein Messergebnis behandelt und geparkt —
und ein geparkter Befund wird in der Folgesession als Faktum weitergereicht. Genau so
wurde „gepostetes Thunk läuft nie" zweimal bestätigt und in drei Dokumente geschrieben.

**Konkreter Vorschlag, Regel 4 um zwei Schritte zu ergänzen (vor dem Parken, nicht danach):**

> 4a. **Instrument validieren, bevor geparkt wird.** Bevor ein Null-/Negativbefund
> festgehalten wird: beweisen, dass die Messung ein Positivergebnis überhaupt hätte
> zeigen können (Positivkontrolle, Pump-Gate, Oracle-Lauf gegen das native Backend).
> Ohne diesen Beweis wird der Befund **nicht** als Produktbefund notiert, sondern als
> „ungemessen".
>
> 4b. **Bei erschöpftem Budget die Seite des Mechanismus wechseln, nicht parken.** Jeder
> asynchrone Mechanismus hat mindestens zwei Seiten (hier: posten vs. dispatchen). Wenn
> zwei Hypothesen-Zyklen auf einer Seite nichts ergeben haben, ist das das Signal, die
> andere Seite zu lesen — erst dann parken.

**Belegende Beobachtung aus dieser Session:** Block B hat ausschließlich die Post-Seite
geprüft (FFI-Callback-Kontext, Eventspace-Ziel, `inherit`-Hygiene, Timing) und dafür
deutlich mehr als zwei Zyklen verbraucht. Die Antwort stand auf der Dispatch-Seite, einen
Sprung von der Aufrufstelle zur Definition entfernt (`wx/common/queue.rkt:357/464`). Der
Report vom 13.09. listet „`queue-event`/`eventspace-queue-proc` selbst instrumentieren"
folgerichtig als *künftigen* Schritt — die Datei war nie geöffnet worden. Diese Session
hat keine neue Messtechnik gebraucht, sondern zuerst den Shared-Code-Pfad gelesen.

**Zweite, kleinere Beobachtung für die Prompt-Planung:** die Sessions vom 13.09. waren
sehr lang (Vertrags-Audit mit vier Subagenten + Preferences-Sweep + Block B +
Folgesession). Der Instrumentenverdacht kam erst ganz am Ende auf, als das Budget
mehrfach ausgereizt war. Eine kurze, eng gestellte Session hat ihn in unter einer Stunde
aufgelöst. Für Befunde, die eine Vorsession ausdrücklich als „Instrument verdächtig"
markiert hat, lohnt sich ein **eigener, schmaler Block** statt eines Anhängsels.

**Was diese Session dagegen ausdrücklich der Vorarbeit verdankt:** der Report vom 13.09.
hat sein eigenes Messmittel als Verdächtigen benannt, statt „resizeEvent funktioniert
unter Qt nicht" zu behaupten. Ohne diese selbstkritische Übergabe wäre der schnelle Weg
nicht sichtbar gewesen. Die Praxis, Negativbefunde samt Ausgeschlossenem und samt Zweifel
am eigenen Vorgehen zu dokumentieren, hat sich hier direkt ausgezahlt.

## Liste „später zu validieren" (gebündelter Cross-Platform-Durchlauf)

Unverändert aus `docs/2026-09-13_report-linux.md` übernommen, plus:

- Das Pump-Gate-Muster gilt plattformunabhängig (Shared Code) — auf Windows/macOS ist
  keine eigene Messung nötig, aber die reparierten Proben sollten dort beim nächsten
  Durchlauf ebenfalls `PUMP OK` zeigen (billiger Mitnahme-Check).
- Die Klick-Verifikation der Enable-Kaskade (3/3 PASS) lief nur auf Linux; auf
  Windows/macOS im gebündelten Durchlauf mit `enable-cascade-probe.rkt` nachziehen.
- **§31-`get-client-size`-Fix:** auf Windows/macOS prüfen, dass der Preferences-Dialog
  dort ebenfalls mit sichtbarer, klickbarer Button-Zeile öffnet. **Erwartete
  Plattformdifferenz beachten:** die Menüleistenhöhe unterscheidet sich (Linux 22 px),
  und macOS zeigte die Button-Zeile laut §29 **bereits vorher** erreichbar — dort ist
  zu prüfen, ob der Abzug jetzt zu einem unnötig hohen Dialog führt. macOS nutzt
  zudem eine native Menüleiste (`isNativeMenuBar`), die gar keinen Client-Platz
  verbraucht; sollte `sizeHint().height()` dort trotzdem > 0 melden, wäre ein
  `isNativeMenuBar`-Guard nötig. **Auf Linux nicht prüfbar — ausdrücklich als Risiko
  für den macOS-Durchlauf vermerkt, nicht als erledigt.**

  **Zwei benachbarte Risiken wurden auf Linux geprüft und sind erledigt — im
  gebündelten Durchlauf nicht erneut herzuleiten:**
  - *Frame mit dauerhaft leerer Menüleiste verliert Zeilen?* **Nein.** Gemessen, drei
    Fälle nebeneinander: ohne Menüleiste `client=400x300`, mit **leerer** Menüleiste
    `client=400x300` (unverändert), mit einem Menü `client=400x278`. Der
    `(positive? mh)`-Guard greift, weil eine actionlose QMenuBar `sizeHint 0` meldet.
  - *`get-scaled-client-size` (frame.rkt:143) erbt die Korrektur — will das jeder
    Konsument?* Die Frage stellt sich nicht: der einzige Shared-Code-Aufrufer
    (`mrcanvas.rkt:61`) ruft die Methode auf **`canvas%`**, das sie in
    `wx/qt/canvas.rkt:272` selbst definiert. Die Frame-Variante hat keinen betroffenen
    Konsumenten.
- **§32-`resizeEvent`-Fix — der Punkt mit dem höchsten Validierungsbedarf:**
  **Zwingend zuerst `qt-shim` neu bauen** (neue Funktion `shim_window_set_resize_cb`,
  sonst scheitert schon `get-ffi-obj`). Zu prüfen ist vor allem das **Live-Drag** auf
  Windows und macOS, denn genau dort liegt die bekannte Plattformdifferenz: Windows'
  natives Resize läuft in einer **modalen** `WM_ENTERSIZEMOVE`/`WM_SIZING`-Schleife, die
  den Pump blockiert — auf X11 gibt es das nicht, und Fix-Versuch 2 ist historisch
  genau daran gescheitert („Resize-Schritte spielen sich nach dem Loslassen ab").
  **Das auf Linux gemessene saubere Drag-Verhalten überträgt sich deshalb ausdrücklich
  nicht auf Windows.** win32 löst das mit `constrained-reply`/`pre-event-sync` direkt im
  Message-Handler (`wx/win32/frame.rkt:340-345`); sollte sich das Symptom auf Windows
  zeigen, ist das die Stelle, an der ein Qt-Äquivalent ansetzen müsste. macOS ist
  unbekanntes Terrain (weder X11 noch Win32-Modalschleife).
  **Reproduktionsmittel, konkret:** `examples/minsize-resize-probe.rkt` ist die
  Drag-Regressionsprobe — sie ist die einzige, die `wxtop.rkt`s Korrekturzweig
  erreicht (große Mindestgröße, dann von außen darunter ziehen). Erwartung: pro
  Drag-Schritt höchstens eine Korrektur, danach ein sauberer Recheck; `PUMP OK` muss
  im Log stehen, sonst ist die Messung ungültig. `examples/live-resize-probe.rkt`
  deckt den harmlosen stretchbaren Fall ab.
  **Verifiziert, was ein vergessener Rebuild auslöst** (auf Linux mit dem alten Shim
  gegengeprüft): der Fehler ist **laut und sofort**, nicht still —
  `ffi-obj: could not find export from foreign library … undefined symbol:
  shim_window_set_resize_cb`. Es gibt keinen Modus, in dem der Callback still null
  bleibt und Frames einfach nicht reflowen.

---

# Startpunkt für die nächste Sitzung (Scroll-Block, Linux)

Dieser Abschnitt ist die Übergabe — alles Nötige, um mit frischem Kontext zu beginnen.

## Zuerst lesen (gezielt, nicht alles)

| Quelle | warum |
|---|---|
| `CLAUDE.md` | Regeln 1–8, Umgebung/Build/Run **Linux**. Der Rebuild-Warnblock über „Build" betrifft **nur Windows/macOS** — Linux ist gebaut. |
| `docs/HACKING.md` **§24.5** | Der **zurückgerollte** Scrollbar-Fixversuch (Windows, 2026-09-11). Wichtigste Quelle: was schon probiert wurde und warum es zurückgerollt wurde. **Nicht wiederholen.** |
| `docs/HACKING.md` **§25.2** | Colors-Tab rechte Spalte — der realistischste Ende-zu-Ende-Reproduktionsfall, inkl. der Stelle in `framework/private/color-prefs.rkt`. |
| `docs/HACKING.md` **§31/§32** | Was sich seither geändert hat (Client-Geometrie, Resize-Benachrichtigung) — die Vorbedingungen, die den Block überhaupt erst sinnvoll machen. |
| **§21.10** | Die Pump-Gate-Regel: **ohne `PUMP OK` im Log ist eine Probenmessung ungültig.** |
| dieser Report, Abschnitt „Vormessung für den Scroll-Block" | der aktuelle Symptomstand. |

## Ausgangslage in einem Satz

`wx/qt/canvas.rkt:300-307` implementiert die Scroll-Methoden **gar nicht** (ausdrückliche
Stubs, „no scrollbars in the spike"); Rendering und Reflow funktionieren seit §31/§32
korrekt, die Shim-Primitiven liegen seit `7d1231e0` bereit.

## Die Reproduktionsfälle — konsolidiert, mit aktuellem Stand

| # | Fall | Stand 2026-09-14 |
|---|---|---|
| 1 | `examples/scroll-probe.rkt` — isolierter `editor-canvas%` | rendert sauber, reflowt, **kein Scrollbar, Mausrad/PageDown wirkungslos**. Der Arbeitsfall. |
| 2 | §25.2 Colors-Tab rechte Spalte (drei Buttons hinter `'(auto-vscroll)`) | unverändert unerreichbar. Der Ende-zu-Ende-Fall. |
| 3 | §24.5 Editor-Canvas in echtem DrRacket | auf Linux vor §31/§32 „gestreift"; **nach den Fixes nicht erneut geprüft** — als Erstes nachmessen. |
| 4 | §23.1 Interactions-Bildanzahl (4/6) | 2026-09-13 als **Viewport-Befund** reklassifiziert (skaliert mit der Fensterhöhe: 2 → 4 → 6/6). **Offene Frage: hat §32 das bereits erledigt?** Jetzt reflowt das Fenster — die Zahl könnte auf Vergrößern reagieren. Billig zu prüfen, **vor** jedem Fixversuch. |
| 5 | §25.1 Preferences-Button-Zeile | **gefixt** (§31), gehört nicht mehr dazu. |

## Akzeptanzkriterium (vorab festlegen, damit es nicht verrutscht)

> `examples/scroll-probe.rkt`: **vertikaler Scrollbar sichtbar**, Mausrad **und**
> PageDown bewegen den Inhalt, Zeile 99 ist erreichbar; horizontal analog. Zusätzlich
> Fall 2 (Colors-Tab): die drei Buttons sind durch Scrollen erreichbar **und klickbar**
> (Klickbarkeit separat prüfen — §25.1 hat gezeigt, dass „sichtbar" und „klickbar"
> auseinanderfallen können).
>
> Regressionswache: Smoke 3/3 mit **und** ohne `PLT_QT`, `test-dock-size` 1→2-Tab-Sequenz
> crashfrei, §31-Akzeptanztest (Preferences-Button-Zeile) weiterhin 3/3, und die
> Resize-Proben (`live-resize-probe`, `minsize-resize-probe`) unverändert.

## Was ausdrücklich **nicht** zu tun ist

- **Den Stride-/Backing-Buffer-Verdacht verfolgen.** Er stammt aus der Vorsession und ist
  durch die Vormessung oben **erledigt** — das gestreifte Bild war eine Folge der
  falschen Geometrie, kein Pixelformat-Problem.
- **§24.5s Fixversuch wiederholen**, ohne ihn vorher gelesen zu haben.
- Eine Shim-ABI-Änderung einplanen: die vier Scrollbar-Primitiven existieren bereits.
  Falls doch eine nötig wird, gilt Regel 8 und der Rebuild-Zwang auf allen Maschinen —
  dann vorher fragen.

## Offene Unbekannte (ehrlich benannt)

- Ob Qts eigene `QScrollBar`-Widgets (die vorhandenen Primitiven) der richtige Weg sind
  oder ob ein `QScrollArea`-Ansatz besser passt — **nicht untersucht**.
  `wx/qt/canvas.rkt`s Kommentar bei Zeile 336-351 beschreibt, was `canvas-panel%` vom
  Autoscroll-Mixin erbt und was win32 zusätzlich tut (`reset-dc-for-autoscroll`
  verschiebt dort ein separates Content-HWND) — dieser Backend hat kein solches
  separates Fenster, echtes Virtual-Scroll-Kind-Repositioning ist nicht implementiert.
  Das ist vermutlich die eigentliche Entwurfsfrage des Blocks.
- Ob Windows' „Inhalt komplett weiß"-Symptom sich nach dem Shim-Rebuild ebenfalls an
  Linux/macOS angeglichen hat. Erwartung ja (derselbe Geometriefehler wirkte dort
  ebenso), **nicht geprüft**.

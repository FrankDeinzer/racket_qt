# Report — „Instrument reparieren" (Linux) — 2026-09-14

**Auftrag:** Schritt 1 aus der Empfehlung am Ende von `docs/2026-09-13_report-linux.md`
(= `docs/HACKING.md` §21.9): das Messinstrument reparieren, bevor ein vierter
`resizeEvent`-Wiring-Versuch überhaupt sinnvoll wird. Kein eigener Prompt — direkte
Fortsetzung auf Nutzerwunsch.

Gemessene Version: `~/racket/bin/racket --version` → **v9.3 [cs]** (x86-64, `~/racket`,
nicht im PATH). Sitzungstyp `x11`. Qt 6.11.1.

**Ergebnis in einem Satz:** die Root-Cause des Instrumentenfehlers ist gefunden, aus
dem Primärcode belegt und gegen natives GTK kontrolliert; vier Proben sind repariert und
tragen ab jetzt ihren eigenen Gültigkeitsbeweis im Log; als direkter Ertrag ist die in
Block A offen gebliebene Klick-Verifikation der Enable-Kaskade nachgeholt (**n=3, 3/3
PASS**). **Kein `resizeEvent`-Wiring-Versuch** — der ist Schritt 2 und bleibt
Nutzerentscheidung.

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

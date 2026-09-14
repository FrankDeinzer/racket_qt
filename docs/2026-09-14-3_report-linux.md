# Report — Scroll-Block Fall 2 gefixt (Linux) — 2026-09-14 (3. Sitzung des Tages)

**Auftrag:** „Fall 2 aus `docs/2026-09-14-2_report-linux.md`, Abschnitt Startpunkt" —
also der dort übergebene, bewusst ausgeklammerte Rest des Scroll-Clusters:
`'(auto-vscroll)`-Panels, deren Inhalt echte Kind-Widgets sind (Colors-Tab → Color
Schemes, §25.2).

Gemessene Version: `~/racket/bin/racket --version` → **v9.3 [cs]** (x86-64, `~/racket`,
nicht im PATH). Sitzungstyp `x11`. Qt 6.11.1.

> **Keine neue Shim-ABI-Änderung.** Die Übergabe hatte das vorhergesagt, und es hat
> gehalten: `shim_panel_create` und `shim_widget_set_geometry` gab es bereits. Der
> **bestehende** offene Rebuild aus §32/§33 (`shim_window_set_resize_cb`,
> `shim_canvas_set_wheel_cb`) bleibt für Windows/macOS unverändert nötig — dieser
> Commit ändert daran nichts.

**Ergebnis in drei Sätzen:** Das Akzeptanzkriterium der Übergabe ist wörtlich erfüllt —
die drei Buttons am Ende des Color-Schemes-Panels sind durch Scrollen erreichbar **und**
klickbar, getrennt geprüft, im echten DrRacket. Der Weg dahin war der von der Übergabe
vorgezeichnete (eigenes Content-QWidget, `(not (is-panel?))`-Gate entfernt), mit drei
begründeten Abweichungen vom win32-Vorbild. Die erste Messung der Sitzung hat dabei
§25.2s vermutete Root-Cause widerlegt; die Notiz ist korrigiert statt nur ergänzt.

**Inhalt:** Vormessung · Umsetzung · Mausrad · Verifikation · Offenes.

Technik im Detail: `docs/HACKING.md` §34.

---

## Phase 0 — Vormessung: was §25.2 vermutet hatte, stimmte nicht

Basislinie sauber, Umbrella `main` und Submodul `qt-backend` synchron mit `origin`,
Shim aktuell gebaut.

§25.2 hatte 2026-09-12 vermutet, der scroll-aktivierende Codepfad werde unter Qt „gar
nicht erst betreten" — ausdrücklich als nicht nachverfolgt gekennzeichnet. Erste
Handlung dieser Sitzung war deshalb, das zu messen, bevor irgendetwas gebaut wurde.
Neue Probe `examples/panel-scroll-probe.rkt` (ein `vertical-panel%` mit
`'(auto-vscroll)`, 20 Buttons plus eine Schlusszeile mit drei Buttons — die Struktur
des Colors-Tabs), auf der **unveränderten** Basislinie mit `PLT_QT_SCROLL_DEBUG=1`:

```
[sb c8578] do-set-scrollbars step=1/1 len=0/349 page=0/260 pos=-1/-1
```

Der Pfad wird betreten. `pos=-1/-1` identifiziert den Aufrufer als `reset-auto-scroll`,
also ist `is-auto-scroll?` auf diesem Panel bereits `#t`. Ein zweiter Trace zeigte, dass
auch der Stil ankommt (`style=(deleted transparent auto-vscroll) panel=#t want=#f/#f`)
— `want-v?` war nur wegen §33s bewusstem `(not (is-panel?))`-Gate `#f`.

Damit war die Aufgabe exakt die, die die Übergabe beschrieben hatte, und nicht mehr:
Scrollbars zulassen und etwas schaffen, das sich verschieben lässt.

## Phase 1 — Umsetzung

Die drei Schritte der Übergabe, ausgeführt; die Abweichungen vom win32-Vorbild sind in
`docs/HACKING.md` §34.3 je einzeln begründet. Kurz:

1. **Content-QWidget** (`shim_panel_create`), von `get-content-hwnd` ausgegeben, in
   `reset-dc-for-autoscroll` per `shim_widget_set_geometry` um den Scroll-Offset
   verschoben — das Qt-Äquivalent zu win32s `content-hwnd`.
2. **`(not (is-panel?))`-Gate entfernt** bei `want-h?`/`want-v?`.
3. Keine ABI-Änderung.

Abweichungen, die beim Lesen des Diffs sonst Fragen aufwerfen:

- **Das Content-Widget liegt in `qt-canvas-scroll-mixin`, nicht in `canvas-panel%`**
  (anders als bei win32). Qt stapelt unter Geschwistern das zuletzt erzeugte oben, und
  das Content-Widget ist so groß wie der virtuelle Inhalt — nach den Scrollbars erzeugt
  würde es sie verdecken. `canvas-panel%`s Rumpf läuft zu spät. Ein `raise`-Primitiv
  hätte einen dritten neuen Export bedeutet.
- **Nur für ein Panel, das wirklich einen Scrollbar bekommt.** Das ist die
  Risikoeingrenzung zu der Handle-Identitätsänderung, vor der die Übergabe gewarnt hat:
  `'hide-hscroll`/`'hide-vscroll`-Panels (die anderen Colors-Unterreiter) behalten ihre
  heutige Struktur unverändert. Nachgemessen, s. u.
- **Größe aus `get-client-size`**, nicht aus der rohen Widget-Größe, gegen die
  `position-scrollbars!` bewusst arbeitet — `wxpanel.rkt`s `panel-redraw` platziert
  seine Kinder gegen genau diese Zahl.
- **`shim_widget_set_visible content 1` direkt nach der Erzeugung.** Qt zeigt ein Kind
  eines bereits sichtbaren Elternteils nicht von selbst, und dieses Widget ist kein
  `window%` — ohne den Aufruf bliebe das ganze Panel leer und sähe nach einem
  Paint-Fehler aus.

## Phase 2 — Mausrad (zweiter, getrennter Schritt)

Bewusst **nach** dem grünen Fall-2-Kriterium gebaut, nicht gleichzeitig. Nötig, weil
nichts unterhalb von `dispatch-on-char` ein Panel scrollt (`editor-canvas%` macht das
für Fall 1, ein Panel hat keinen Editor); nativ funktioniert das Rad dort, und §25.2
hatte es als einen der drei geprüften Wege genannt.

Realisiert als Vorrecht-Hook `qt-wheel-scroll`, der **vor** der Zustellung als
`key-event%` gefragt wird und nur im Panel-Fall `#t` antwortet — `editor-canvas%` bleibt
unberührt (gegengemessen, s. Regressionswache). Die Bedingung ist `content-handle`, nicht
`is-auto-scroll?`: letzteres wird erst gesetzt, wenn `panel-redraw` zum ersten Mal
`set-scrollbars` gelaufen ist, ein Radereignis davor fiele durch (§34.4). Der erste
Entwurf hatte genau diesen Fehler.

Schrittweite ein Zehntel Page pro Raste. Der Single Step des Bars taugt hier nicht:
`reset-auto-scroll` gibt `1 1` aus, und Qts eigene Radbehandlung macht daraus
**gemessen 3 px pro Raste** (Rad direkt über dem Bar, 3 Rasten → 9 px) gegen eine Range
von 349 px. Das ist eine UX-Setzung, kein Korrektheitsbefund, und gefahrlos änderbar.

## Phase 3 — Verifikation

### Akzeptanzkriterium (wörtlich aus der Übergabe)

„Die drei Buttons sind durch Scrollen erreichbar **und klickbar** (getrennt prüfen —
§25.1 hat gezeigt, dass ‚sichtbar' und ‚klickbar' auseinanderfallen können)."

| Prüfung | Ergebnis |
|---|---|
| Scrollbar sichtbar | ✅ |
| Kinder bewegen sich beim Scrollen | ✅ Schlusszeile erscheint |
| Mausrad bewegt den Inhalt | ✅ 26 px/Raste (976 → 820 bei 6 Rasten) |
| klickbar | ✅ **3/3** (Revert, Design, Names) |
| **im echten Ziel:** DrRacket → Preferences → Colors → Color Schemes | ✅ Scrollbar da, alle drei Buttons sichtbar; „Style & Color Names" geklickt → Dialog „color names:" öffnet |

**Methodischer Punkt:** Die ersten Klickversuche waren Fehlschläge — und zwar wegen aus
dem Screenshot geschätzter Koordinaten, nicht wegen des Fixes. Sie hätten sich mühelos
als „sichtbar, aber nicht klickbar" fehldeuten lassen. Repariert nach dem
`enable-cascade-probe`-Muster (§21.10): die Probe meldet die Bildschirmmitte jedes
Buttons selbst über `client->screen`, die Automatisierung schätzt nicht mehr. Nebenbei
ist das der Nachweis, dass `client->screen` durch das verschobene Content-Widget
hindurch korrekt rechnet.

### Regressionswache

| Wache | Ergebnis |
|---|---|
| Smoke ohne `PLT_QT` | 3/3 |
| Smoke mit `PLT_QT` | 3/3 |
| Fall 1 (`scroll-probe`, §33) | unverändert: Mausrad Zeile 0 → 10 |
| `live-resize-probe` (§32) | 296 → 696 → 896, unverändert |
| `minsize-resize-probe` (§32) | 300×200 → **300×348 in genau einem Schritt** |
| `test-dock-size` (Run, dann File→Open als 2. Tab) | **3× crashfrei**, Zwei-Tab-Bedingung je Lauf belegt (s. u.) |
| §31-Akzeptanztest | Dialog **1060×663**, OK klickt und schließt |
| Colors → Racket (`hide-*`-Panel) | **unverändert** — die Eingrenzung greift |

Alle Probenläufe mit `PUMP OK` im Log; ohne den ist eine Probenmessung ungültig
(§21.10).

**Die `test-dock-size`-Wache musste zweimal repariert werden, bevor sie etwas wert war**
(Details §34.7, beides vorbestehend und nicht von dieser Änderung verursacht):

1. **Ctrl-Akzeleratoren erreichen DrRacket hier nicht** — `ctrl+o`/`ctrl+t` per
   `xdotool` lösen nichts aus, `F5` schon. Nur der Menüklick funktioniert. Eine erste
   Runde mit `ctrl+o` hat die Sequenz gar nicht ausgeführt.
2. **Das Tabs-Menü zeigt „Previous/Next Tab" auch bei zwei offenen Tabs ausgegraut.**
   Daraus wurde zunächst „nur ein Tab, die Sequenz war also eine andere" geschlossen —
   falsch. Belastbarer Zähler: nach dem Öffnen `File → Close`; springt der Titel auf
   `htdp-tests-probe.rkt` zurück, gab es zwei Tabs. So ist die Bedingung jetzt in allen
   drei Läufen **einzeln** nachgewiesen:

```
  after Run:   htdp-tests-probe.rkt - DrRacket
  after Open:  hello.rkt - DrRacket
  RUN: ALIVE (no crash)
  after Close: htdp-tests-probe.rkt - DrRacket
```

Das ausgegraute Tabs-Menü ist damit ein **neuer, offener Nebenbefund** (Menü-Enable-
States werden unter diesem Backend nicht nachgeführt), hier nicht untersucht.

## Beobachtet, aber nicht weiterverfolgt

Vollständigkeitshalber festgehalten (kein Defekt belegt, Details §34.5/§9):

- **Mausrad über dem echten Colors-Panel bewegt es kaum** (40 Rasten ≈ 53 px). Naheliegend:
  die farbigen Beispiel-Canvases unter dem Zeiger verbrauchen das Rad. Über den Scrollbar
  gesteuert funktioniert das Panel einwandfrei. Nativ ungemessen — das wäre der
  Diskriminator.
- **Kurze senkrechte dunkle Segmente** links neben dem Scrollbar im Colors-Tab,
  vermutlich Rahmen der inneren Canvases.
- **Werkzeuge und Fallen der GUI-Automatisierung** auf dieser Maschine sind jetzt in
  §9 gesammelt (was installiert ist, und vier Fallen, von denen heute jede einmal
  zugeschlagen hat).

## Nebenarbeit

- **§25.2 korrigiert statt nur ergänzt.** Die dort notierte Vermutung ist durch die
  Vormessung widerlegt; die Stelle trägt jetzt einen Korrekturkasten. Genau die Sorte
  veralteter Notiz, die diesem Projekt schon zwei Sitzungen gekostet hat.
- `dbg`/`dbg-id` in `qt-canvas-scroll-mixin` nach oben verschoben. Sie sind
  letrec-gebundene Namen, keine Methoden — eine Trace-Zeile im Klassenrumpf sieht sie
  erst danach. Rein mechanisch, ohne Verhaltensänderung.
- Neue Probe `examples/panel-scroll-probe.rkt` (Akzeptanzprobe für Fall 2).

## Nicht gemacht (bewusst)

- **`notify-child-extent`** hat kein Gegenstück (Begründung: §34.6).
- **Keine Cross-Platform-Validierung** (gebündeltes Modell). Diese Änderung ist reine
  Racket-Logik ohne bekannte Plattformdivergenz — mit einer Ausnahme, die auf die
  Sammelliste gehört: die Scrollbar-Dicke stammt aus `sizeHint()`, und macOS kann
  Overlay-Scrollbars mit kleiner oder 0 breiter `sizeHint` melden. Das betrifft Fall 1
  und Fall 2 gleichermaßen und steht schon auf der §33-Liste.
- Kein Anfassen von Shared Code: geändert wurden `wx/qt/canvas.rkt` (Submodul) sowie
  `examples/` + `docs/` (Umbrella).

## Liste „später zu validieren" (gebündelter Cross-Platform-Durchlauf)

Unverändert aus `docs/2026-09-14-2_report-linux.md` übernommen (inkl. des dort
weiterhin offenen `qt-shim`-Rebuilds für **zwei** Exporte), plus:

- **Colors → Color Schemes auf Windows/macOS gegenprüfen:** Scrollbar da, drei Buttons
  erreichbar und klickbar.
- **Mausrad-Schrittweite im Panel** (ein Zehntel Page) auf Windows/macOS beurteilen;
  auf macOS zusätzlich Richtung wegen natural scrolling.
- `examples/panel-scroll-probe.rkt` ist dort die Akzeptanzprobe; `PUMP OK` muss im Log
  stehen.

---

# Startpunkt für die nächste Sitzung

Der Scroll-Cluster (§21.6 Punkt 4 → §24.5 → §25.2) ist **geschlossen**. Was aus den
zugehörigen Sitzungen offen bleibt:

- Der **einmalige, nicht reproduzierbare Tab-2-Befund** aus §33.7 (falsche
  Zeilennummern nach Run + File→Open). In dieser Sitzung bei 3 `test-dock-size`-Läufen
  nicht aufgetreten. Wenn er wiederkommt: `PLT_QT_SCROLL_DEBUG=1` mitlaufen lassen.
- Der **gebündelte Cross-Platform-Durchlauf** auf Windows und macOS — inzwischen mit
  vier Sitzungen Rückstand (§31/§32/§33/§34) und **einem** fälligen `qt-shim`-Rebuild.
- **Neu:** DrRackets Tabs-Menü führt seine Enable-States nicht nach (§34.7) — ein
  Menü-Befund, kein Scroll-Befund, eigene Sitzung.
- **Neu und als Nächstes vorgesehen (Nutzerentscheidung): §35 — übereinander
  gezeichnete Toolbar-Controls** oben links im DrRacket-Editorfenster (`Untitled` und
  `Undock` an derselben Stelle). In jedem Screenshot dieser Sitzung sichtbar, über
  mehrere Prozessstarts stabil, kein Run und keine Interaktion nötig. Belegbild:
  `docs/2026-09-14-3_toolbar-overlap-linux.png`. **Nicht untersucht** — insbesondere ist
  offen, ob der Befund überhaupt Qt-spezifisch ist; der Nativ-Gate (DrRacket ohne
  `PLT_QT`) ist die erste Pflichtmessung, s. §35.3.
- Aus dem weiteren Bestand unverändert offen: der Zombie-Prozess beim Schließen des
  letzten Fensters (§29.2), die macOS-Menüleiste mit 8 statt 9 Einträgen, Linux Crash B
  (Teardown), der grafische Störeffekt am oberen Rand des Editor-Fensters (§24.5s
  Nebenbefund, Root-Cause nie untersucht — möglicherweise derselbe Befund wie §35,
  Hypothese 1 dort).

**Korrektur an einer ersten Fassung dieses Abschnitts:** hier standen zunächst
zusätzlich „der Linux-Interactions-Bildbefund (§23.1)" und „`panel%`s hartcodiertes
`is-shown?` als Rest von §23.3". **Beides ist längst erledigt** — der Bildbefund durch
§32 (in `docs/2026-09-14-2_report-linux.md`, Phase 0, als „Fall 4" nachgemessen: bei
600×500 sind 4 von 6 Bildern sichtbar, nach dem Vergrößern alle 6, reiner
Viewport-Effekt), und `panel%`s `is-shown?` durch §30, das genau diesen Override samt
neun weiteren entfernt hat. Genau die Sorte veralteter Notiz, gegen die dieser Report
zwei Absätze weiter oben argumentiert.

# Report — Übereinander gezeichnete Toolbar-Controls gefixt (Linux) — 2026-09-14 (4. Sitzung des Tages)

**Auftrag:** „Toolbar-Controls übereinander" aus §35 von
`docs/2026-09-14-3_report-linux.md` — der dort als nächste Sitzung vorgemerkte Befund:
oben links im DrRacket-Editorfenster werden `Untitled`/Dateiname und ein zweites Control
mit dem Text `Undock` an derselben Stelle gezeichnet.

Gemessene Version: `~/racket/bin/racket --version` → **v9.3 [cs]** (x86-64, `~/racket`,
nicht im PATH). Sitzungstyp `x11`. Qt 6.11.1.

> **Keine Shim-ABI-Änderung.** `shim_widget_set_visible` existierte bereits; die
> Änderung ist rein Racket-seitig. Der **bestehende** offene Rebuild aus §32/§33
> (`shim_window_set_resize_cb`, `shim_canvas_set_wheel_cb`) bleibt für Windows/macOS
> unverändert nötig — dieser Commit ändert daran nichts.

**Ergebnis in drei Sätzen:** Der Befund ist Qt-spezifisch (Nativ-Gate zuerst gemessen,
wie §35 es vorgeschrieben hatte), und die Ursache ist eine schlichte Lücke: `wx/qt`
kannte den Fensterstil `'deleted` überhaupt nicht — `grep -rn deleted wx/qt/*.rkt` war
leer, während win32 und gtk ihn je ausdrücklich behandeln. DrRackets Test-Report-Dock
wird bei jedem Frame-Aufbau mit genau diesem Stil erzeugt, seine Knöpfe `Hide`/`Undock`
aber ohne — unter Qt wurden sie deshalb bei 0,0 mitgezeichnet. Ein Hide-on-Create in
`wx/qt/window.rkt`, durchgereicht von elf Platform-Klassen, schließt das; die Toolbarzeile
ist in echtem DrRacket 3/3 sauber, und die volle Regressionswache ist grün.

**Inhalt:** Nativ-Gate · Zuordnung · Root-Cause · Fix · Verifikation · Offenes.

Technik im Detail: `docs/HACKING.md` §35.

---

## Phase 0 — Nativ-Gate (die Pflichtmessung der Übergabe)

Basislinie sauber, Umbrella `main` und Submodul `qt-backend` deckungsgleich mit
`origin`, Shim aktuell gebaut.

§35 hatte für diese Sitzung eine Reihenfolge vorgeschrieben und sie begründet: erst
messen, ob der Befund überhaupt Qt-spezifisch ist, sonst ist jede Ursachensuche im
Backend verfrüht (dieselbe Lehre wie §24.5s Stride-Verdacht und §21.10s
Instrumentenartefakt). Also zuerst DrRacket **ohne** `PLT_QT`:

- `Untitled▾` und `(define ...)▾` stehen sauber nebeneinander.
- Der Text `Undock` kommt im nativen Fenster **überhaupt nicht** vor.

Damit ist der Befund als `wx/qt`-Defekt bestätigt. Direkt danach derselbe Ausschnitt
unter Qt auf unverändertem HEAD — Symptom unverändert reproduziert, gleicher
Bildausschnitt für ein belastbares Vorher/Nachher:
`docs/2026-09-14-4_toolbar-overlap-before-linux.png`.

## Phase 1 — Wem gehört das Control?

`grep -rln undock` über Installation und Collects trifft genau eine Nicht-String-Datei:
`htdp-lib/test-engine/test-tool.rkt`. Dort ist `Undock` ein gewöhnliches `button%`
(Zeile 252), einer von zwei Knöpfen (`Hide`, `Undock`) im Button-Panel des
Test-Report-Docks.

**Damit ist Hypothese 2 der Übergabe beantwortet und erledigt:** es ist *kein*
`switchable-button%`, mit §24.4s Toolbar-Save-Icon hat die Sache nichts zu tun.
Hypothese 1 (derselbe Befund wie das orange/blau gestreifte Rechteck auf Windows,
§24.5) bleibt offen — von Linux aus nicht entscheidbar, wie die Übergabe schon sagte.

Dass nur `Undock` zu lesen war und nicht `Hide`: Qt stapelt unter Geschwistern das
zuletzt erzeugte oben, und `Undock` wird nach `Hide` erzeugt.

Der interessante Teil ist die Erzeugung (`test-tool.rkt:100`, in
`make-root-area-container`):

```racket
(define test-p (make-object test-panel% outer-p '(deleted)))
```

## Phase 2 — Root-Cause

`'deleted` heißt: erzeugt, aber nicht eingehängt und nicht sichtbar, bis
`display-test-panel` das Panel per `add-child` andockt. Die anderen Backends behandeln
den Stil ausdrücklich — `wx/win32/window.rkt:291` zeigt am Ende der Konstruktion
`(unless (memq 'deleted style) ...)`, gtk reicht dafür einen `no-show?`-Init durch
(`wx/gtk/window.rkt:582/714`). In `wx/qt` kam das Wort **nirgends** vor.

Warum das gerade unter Qt sichtbar wird: Ein QWidget, dessen Parent bei der Erzeugung
noch nicht sichtbar ist — der Normalfall, Panels und Controls entstehen vor
`(send frame show #t)` — trägt kein explizites Hide-Flag. `QWidget::show()` auf dem
Frame kaskadiert dann nach unten und macht **jeden** solchen Nachfahren sichtbar,
`'deleted` oder nicht.

Die Racket-Seite war beweisbar nicht beteiligt. Neue isolierte Probe
`examples/deleted-style-probe.rkt` baut die Schachtelung aus `test-tool.rkt` nach und
meldet unter Qt und nativ **identische** Zustände:

```
[probe] dead-panel    is-shown?=#f  x=0 y=0 w=0 h=0
[probe] dead-inner    is-shown?=#t  x=0 y=0 w=0 h=0
[probe] b-stray       is-shown?=#t  x=0 y=0 w=80 h=25
```

Nur das gezeichnete Bild unterschied sich: unter Qt wurde `STRAY` bei 0,0 gemalt, nativ
nicht. Das beantwortet auch die zweite Pflichtfrage der Übergabe („dieselbe Geometrie,
oder gar keine?"): **gar keine** — aber die Ursache ist nicht ein fehlender
`set-size`-Aufruf wie bei §33, sondern ein fehlender Hide-Aufruf.

## Phase 3 — Fix

`wx/qt/window.rkt` bekommt einen `no-show?`-Init (Formulierung von gtk übernommen) und
am Ende des Klassenrumpfs `(when (and handle no-show?) (shim_widget_set_visible handle 0))`.
Elf Platform-Klassen reichen ihn durch (`button% canvas% check-box% choice%
group-panel% list-box% message% panel% radio-box% slider% tab-panel%`), jeweils
`[no-show? (and (memq 'deleted style) #t)]` am `super-new`. `frame%`/`dialog%` bleiben
bewusst außen vor: bei Top-Level-Fenstern ist `show` immer explizit, und Qt-Top-Levels
starten ohnehin versteckt — win32 drückt dasselbe aus, indem `wx/win32/frame.rkt:257`
den **Frame selbst** mit `(cons 'deleted style)` konstruiert. Nachgesehen statt
angenommen, weil ein versehentlich versteckter Frame der teuerste denkbare Fehler
dieser Änderung gewesen wäre.

**Die Stelle, an der das gefährlich klingt, und warum es das nicht ist:** der Glue-Layer
erzeugt *fast alles* mit `'deleted` und zeigt es sofort danach wieder an —
`wxitem.rkt:234/246/251` (button/check-box/message) und `wxpanel.rkt:597` (jedes
Basis-Panel) hängen `(cons 'deleted style)` an, bevor sie die Platform-Klasse
konstruieren, und rufen direkt danach `show-control` auf (`wxitem.rkt:198`,
`wxpanel.rkt:598`). Das landet über `really-show` (`wxwindow.rkt:112`) auf genau dem
`show`, das den QWidget wieder sichtbar macht. Dieselbe Mechanik trägt win32 seit jeher.
Nur ein Widget, dessen **Nutzer**-Stil wirklich `'deleted` sagt, bekommt diesen Aufruf
nie — und das ist der Test-Report-Dock.

Dass `really-show` auf `show` zeigt und **nicht** auf `direct-show`, war vor der ersten
Zeile Code nachzusehen: `wx/qt/panel.rkt:57` und `wx/qt/button.rkt:63` definieren
`direct-show` als `(void)`-Stub, was den Fix stillschweigend wirkungslos gemacht hätte.
Unter win32 ist die Delegationsrichtung umgekehrt (`wx/win32/window.rkt:287`).

## Phase 4 — Verifikation

| Wache | Ergebnis |
|---|---|
| Nativ-Gate (DrRacket ohne `PLT_QT`) | keine Überlappung, kein `Undock` |
| Isolierte Probe, Qt, vor Fix | `STRAY` bei 0,0 gezeichnet |
| Isolierte Probe, Qt, nach Fix | `STRAY` weg, `SICHTBAR` unverändert |
| Isolierte Probe, `add-child` nachträglich | `STRAY` erscheint an korrekter Layout-Position (`dead-panel y=115 520×145`) |
| Isolierte Probe, Scroll-`canvas%` im `'(deleted)`-Panel | vorher unsichtbar, nach `add-child` samt Inhalt und **beiden Scrollbars** da (`y=72 520×73`) |
| Echtes DrRacket, Toolbarzeile | sauber, **n=3, 3/3** über getrennte Prozessstarts |
| Smoke ohne `PLT_QT` | 3/3 |
| Smoke mit `PLT_QT` | 3/3 |
| `live-resize-probe` (§32) | 296 → 696 → 896, unverändert |
| `minsize-resize-probe` (§32) | 300×200 → 300×348 in genau einem Schritt |
| Fall 1 (`scroll-probe`, §33) | Mausrad Zeile 0 → 10, beide Scrollbars da |
| Fall 2 (Colors → Color Schemes, §34) | Scrollbar da, Ziehen bewegt den Inhalt |
| §31-Akzeptanztest | Dialog **1060×663**, OK klickt und schließt (`xwininfo` → `IsUnMapped`) |
| `test-dock-size` (Run, dann File→Open als 2. Tab) | **3× crashfrei**, Zwei-Tab-Bedingung je Lauf belegt |

Alle Probenläufe mit `PUMP OK` im Log; ohne den ist eine Probenmessung ungültig (§21.10).

**Die wichtigsten Wachen sind die vierte und fünfte Zeile.** Ein Hide-on-Create wäre
wertlos, wenn das Panel danach nie mehr sichtbar würde — dann wäre der Test-Report-Dock
kaputt statt der Toolbar. Die Probe fährt deshalb mit `PROBE_ADD=1` genau den Pfad nach,
den `display-test-panel` beim Andocken nimmt.

Die fünfte Zeile deckt den einen Fall ab, in dem das nicht selbstverständlich ist:
`canvas%` erzeugt Content-Widget und QScrollBars in `qt-canvas-scroll-mixin` **nach**
`window%`s `super-new`, also nach dem Hide-on-Create — und §34 hatte festgehalten, dass
Qt ein Kind eines bereits sichtbaren Elternteils nicht von selbst zeigt. Die Probe
enthält darum einen `editor-canvas%` mit `'(auto-hscroll auto-vscroll)` **ohne** eigenes
`'deleted` im `'(deleted)`-Panel (die Lage des Test-Report-Canvas,
`test-tool.rkt:219`): nach dem Andocken rendert er samt beider Scrollbars. Ein Canvas,
der sein `'deleted` **selbst** trägt, bleibt dagegen zu Recht unsichtbar; Racket meldet
dann auch `is-shown?=#f`, gleich auf welchem Backend. Ohne diese Wache wäre der
Fehlerfall (Scrollbars nach dem Andocken weg) in allem anderen unsichtbar geblieben.

**Der Dock selbst taugte nicht als Wache, und das ist gemessen, nicht angenommen.**
Andocken hängt allein an der Preference `test-engine:test-window:docked?` (einen
Menüeintrag dafür gibt es nicht; `dock-label`/`undock-label` in `test-tool.rkt:120` sind
tot). Mit `docked? = #t` erscheint der Dock **auch nativ nicht** — die Testergebnisse
landen in beiden Backends im Interactions-Pane. Das Feature ist in dieser
htdp-lib-Version inert, gleich auf welchem Backend. Die Preference wurde vorher gesichert
und danach bitgleich zurückgespielt (`diff` grün).

## Beobachtet, aber nicht weiterverfolgt

- **Zwei gleichzeitig ausgewählte Radio-Buttons** im Color-Schemes-Panel (`Classic` und
  `White on Black`) sind **kein** Defekt: die Liste hat zwei Abschnitte, „Light Color
  Scheme" und „Dark Color Scheme", und pro Abschnitt ist genau eine Wahl gesetzt. Passt
  zu §20s Fund, dass DrRacket das als 1-Button-Gruppen baut
  (`mk-color-scheme-radio-buttons`). Mit sauberem Zug nachgemessen (nur Scrollbar
  gezogen, sonst nichts geklickt), damit die Beobachtung nicht auf einen eigenen
  Fehlklick zurückgeht.
- **Die `pkill`-Falle aus §9 hat wieder zugeschlagen** (Exit 144, Kommando läuft nie),
  diesmal mit einem Probennamen statt `drracket`. Der Eintrag ist korrekt und
  vollständig — er wurde nur nicht rechtzeitig gelesen. Kein neuer Befund.

## Startpunkt für die nächste Sitzung

Offen und unverändert:

- **Hypothese 1 zu §35** — ob das orange/blau gestreifte Rechteck am oberen Rand des
  DrRacket-Editorfensters auf **Windows** (§24.5, Root-Cause nie untersucht) derselbe
  Befund war, ist von Linux aus nicht entscheidbar. Die billigste Prüfung ist, nach dem
  gebündelten Windows-Durchlauf einfach hinzusehen: wenn das Rechteck mit diesem Fix
  verschwunden ist, war es dasselbe.
- **Das ausgegraute Tabs-Menü** (§34.7 Punkt 2) — Menü-Enable-States werden unter diesem
  Backend nicht nachgeführt. Eigener Befund, eigene Sitzung.
- **Der gebündelte Windows/macOS-Durchlauf** hat jetzt **fünf** Sitzungen Rückstand
  (§31/§32/§33/§34/§35) und **einen** fälligen `qt-shim`-Rebuild (§32+§33 zusammen).
  Diese Sitzung hat daran nichts geändert.

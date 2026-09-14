# Report — Scroll-Block, Fall 1 gefixt (Linux) — 2026-09-14 (2. Sitzung des Tages)

> # ⚠ VOR DEM NÄCHSTEN PULL AUF WINDOWS/macOS LESEN
>
> Diese Sitzung enthält eine **zweite Shim-ABI-Änderung**: `shim_canvas_set_wheel_cb`
> ist neu, **zusätzlich** zu `shim_window_set_resize_cb` aus §32 (erste Sitzung des
> Tages). **Ein** `qt-shim`-Rebuild nach dem Pull deckt beide ab; ohne ihn schlägt schon
> das Laden des Forks fehl, laut und sofort (`ffi-obj: could not find export …`).
> Bauanleitung je Plattform in `CLAUDE.md`.

**Auftrag:** „wir machen weiter mit dem scroll-problem aus
`docs/2026-09-14_report-linux.md`" — der dort übergebene Scroll-Block. Kein eigener
Prompt; Umfang und Mausrad-Frage wurden nach der Vormessung dem Nutzer vorgelegt und
von ihm entschieden (Fall 1 zuerst, Fall 2 separat; Mausrad mit eigenem Shim-Export).

Gemessene Version: `~/racket/bin/racket --version` → **v9.3 [cs]** (x86-64, `~/racket`,
nicht im PATH). Sitzungstyp `x11`. Qt 6.11.1.

**Ergebnis in drei Sätzen:** Die Root-Cause von §24.5 war kein Scrollbar-Problem,
sondern ein **fehlender `on-size`-Aufruf** in `wx/qt/canvas.rkt`s `set-size` — vorab
isoliert nachgewiesen, bevor Implementierungsaufwand entstand. Auf dieser Grundlage hat
`canvas%` jetzt echte QScrollBar-Kinder samt vollständiger wx-Scroll-API und
Mausrad-Zustellung; das Akzeptanzkriterium der Übergabe ist **wörtlich erfüllt**
(Scrollbars sichtbar, Mausrad und PageDown wirken, Zeile 99 erreichbar, horizontal
analog). Fall 2 (`'(auto-vscroll)`-Panels, Colors-Tab) ist **bewusst unangetastet** und
bleibt offen — er braucht andere Maschinerie.

**Inhalt:** Vorarbeit (2 Messungen der Übergabe) · Diskriminator · Umfangsentscheidung ·
Implementierung · Verifikation · ein nicht reproduzierbarer Befund · Offenes.

---

## Phase 0 — Umgebung und die zwei Messungen, die die Übergabe zuerst verlangt hat

Umbrella `main` und Submodul `third_party/gui` (`qt-backend`) zu Sitzungsbeginn sauber
und synchron mit `origin`. Shim aktuell gebaut.

Die Übergabe hatte zwei Messungen **vor** jedem Fixversuch verlangt. Beide auf der
**unveränderten Basislinie** durchgeführt (eigene Änderung dafür gestasht):

| Fall | Erwartung laut Übergabe | Messung |
|---|---|---|
| **Fall 3** — Editor-Canvas in echtem DrRacket, auf Linux vorher „gestreift" | offen, „als Erstes nachmessen" | **rendert sauber**, kein Streifenbild. §31/§32 haben das erledigt. |
| **Fall 4** — Interactions zeigt nur 4 von 6 Bildern (§23.1) | „hat §32 das schon erledigt?" | **ja.** Bei 600×500 sind 4 von 6 Bildern sichtbar, kein Scrollbar; Fenster **ohne erneutes Run** auf 1000×900 vergrößert → **alle 6 sichtbar**. Reiner Viewport-Befund, das Reflow greift. Kein eigener Befund mehr. |

Damit reduzierte sich der Block auf Fall 1 (Probe/DrRacket-Editor) und Fall 2
(Colors-Tab).

---

## Phase 1 — Der Diskriminator: ein fehlender Aufruf erklärt §24.5 vollständig

Vor jedem Scrollbar-Code wurde die billigste entscheidende Messung gemacht: **nur** den
in win32/gtk vorhandenen `on-size`-Aufruf in `set-size` verdrahten und die
**unveränderten** Stubs mit `eprintf` instrumentieren.

Details und Tabelle: `docs/HACKING.md` §33.1. Kurz: `do-set-scrollbars` feuerte vorher
genau einmal bei 30×30 mit `h-len=1 v-len=1` (§24.5s Kernmessung) — nach dem Aufruf
liefert derselbe Lauf bei realen 400×300 `h-range=109`, `v-range=89`, `v-page=10` und
feuert beim Resize auf 900×600 **erneut** mit korrekt angepassten Werten.

Der erste Versuch, den Hook in `base-canvas%` zu legen, scheiterte sofort und
lehrreich: `auto-scroll?: undefined; cannot use field before initialization`. Grund ist
die gegenüber win32/gtk **invertierte** Klassenkette (§33.2) — der Hook gehört in die
Zwischen-Mixin-Schicht, mit einem vor `super-new` definierten `scroll-ready?`-Flag.

**Methodische Einordnung:** hätte dieser Schritt nichts bewegt, wäre das Modell
widerlegt gewesen, ohne dass Implementierungsaufwand entstanden wäre. Das ist die
direkte Anwendung der 4a-Regel aus dem Vorreport (Instrument/Modell validieren, bevor
gebaut oder geparkt wird).

---

## Phase 2 — Umfang: zwei Fälle, zwei Maschinerien (Nutzerentscheidung)

Das Akzeptanzkriterium der Übergabe bündelt zwei Fälle, die unterschiedliche Mechanik
brauchen. Das wurde **vor** der Implementierung vorgelegt statt am Ende entdeckt:

- **Fall 1** (`editor-canvas%`): Scrollbars + Scroll-API; der Editor zeichnet sich
  selbst neu.
- **Fall 2** (`'(auto-vscroll)`-Panel, Colors-Tab): Inhalt sind echte Kind-Widgets. Ein
  Zeichen-Offset bewegt die nicht — win32 verschiebt dafür ein separates `content-hwnd`,
  dieses Backend hat kein solches Fenster. Sichtbar **und klickbar** (so das Kriterium)
  verlangt also echtes Kind-Repositioning.

**Nutzerentscheidung: Fall 1 zuerst, Fall 2 separat.** Ebenso entschieden: Mausrad mit
sauberem eigenem Shim-Export statt Sentinel-Trick durch den bestehenden `key_cb` — ein
vergessener Rebuild soll laut scheitern (§32s ausdrücklich verifizierte Eigenschaft).

---

## Phase 3 — Implementierung

Vollständig in `docs/HACKING.md` §33.2–33.4. Die Punkte, die beim Lesen des Diffs sonst
Fragen aufwerfen:

- **Eigene Mixin-Schicht `qt-canvas-scroll-mixin`** zwischen `canvas-autoscroll-mixin`
  und `canvas-mixin` — erzwungen durch die `public*`/`override*`-Invariante (§1), genau
  wie schon in §24.5.
- **`get-client-size` zieht die Scrollbar-Dicke selbst ab.** Anders als win32
  (Non-Client-Bereich) und gtk (Geschwister in einer Box) sind die Bars hier Kinder des
  Canvas-Widgets; Dicke aus `shim_widget_get_size_hint`, nicht hartkodiert.
- **Gating unverändert von win32/gtk übernommen** (`auto-scroll` → API liefert 0,
  `get-virtual-*-pos` übernimmt). `editor-canvas%` verlässt sich darauf.
- **Kein `as-scroll-change`-Nachbau:** `shim_scrollbar_set_range`/`set_value` blocken
  `valueChanged` schon per `QSignalBlocker`.
- **Callback-Lifetime-Konvention aus §24.5 wieder angewendet** (Closure an ein
  Objektfeld, nie Inline-Lambda an den Shim) — dort gefunden und mit dem Revert
  verlorengegangen.
- **Mausrad:** neuer Export `shim_canvas_set_wheel_cb`; Racket erzeugt daraus das
  `key-event%` mit `'wheel-up`/`'wheel-down`/… + `wheel-steps`, wie gtk.

---

## Phase 4 — Verifikation

### Akzeptanzkriterium (wörtlich aus der Übergabe), `examples/scroll-probe.rkt`

Alle Läufe mit `PUMP OK` im Log — ohne den ist eine Probenmessung ungültig (§21.10).

| Prüfung | Ergebnis |
|---|---|
| vertikaler Scrollbar sichtbar | ✅ |
| horizontaler Scrollbar sichtbar | ✅ |
| Mausrad bewegt den Inhalt | ✅ Zeile 0 → 10 bei 10 Rasten |
| PageDown bewegt den Inhalt | ✅ Zeile 10 → 40 bei 3× `Next` |
| Zeile 99 erreichbar | ✅ per Thumb-Drag |
| horizontal analog | ✅ Zeilenenden per Drag sichtbar |

### Ende-zu-Ende in echtem DrRacket

- **Fall 3:** Definitions- **und** Interactions-Pane haben jetzt Scrollbars, Inhalt
  rendert sauber.
- Preferences „Example Text"-Canvas: beide Scrollbars vorhanden.

### Regressionswache

| Wache | Ergebnis |
|---|---|
| Smoke ohne `PLT_QT` | 3/3 |
| Smoke mit `PLT_QT` | 3/3 |
| `live-resize-probe` (§32) | 296 → 696 → 896, unverändert |
| `minsize-resize-probe` (§32-Korrekturzweig) | 300×200 → **300×348 in genau einem Schritt**, stabil |
| `test-dock-size` (Run, dann File→Open als 2. Tab) | **3× crashfrei** |
| §31-Akzeptanztest (Preferences-Button-Zeile) | **3/3 PASS**, Dialog in allen Läufen **1060×663**, OK klickt und schließt |
| Colors-Tab (Fall 2) | **unverändert** — wie beabsichtigt |

---

## Ein Befund, der sich nicht reproduzieren ließ

Einmalig beobachtet, danach in drei Durchläufen derselben Sequenz nicht wieder: nach
Run + File→Open eines zweiten Tabs zeigte die Definitions-Ansicht Zeilennummern 160-193
für eine 16-Zeilen-Datei, später 1023-1056, zuletzt leeren Text bei korrekten Nummern.
Die Basislinie ist an derselben Stelle sauber, der Befund ist also **nicht** als
vorbestehend abzutun.

Zwei Hypothesen gemessen, **beide widerlegt** (Details §33.7):

1. „Inhalt passt in den Viewport → Scrollbars versteckt → weiß" — isolierte Probe mit 5
   kurzen Zeilen rendert korrekt.
2. „`on-size` ohne Dedup hält die Layout-Schleife am Leben" (§32-Lehre) — der
   verdächtigte transiente Client-Wert tritt mit Dedup genauso oft auf wie ohne (284 vs.
   270) und auch in korrekt rendernden Läufen. **Der versuchsweise eingebaute Dedup
   wurde deshalb wieder entfernt** statt als unbegründeter Zustand stehenzubleiben.

**Was tatsächlich daraus folgte:** der Vergleich gegen win32 legte einen echten Defekt
frei — `show-scrollbars` invalidierte die Backing-Bitmap, forderte aber keinen Repaint
an (win32 macht beides in `reset-dc`). Ein invalidiertes Backing ohne Repaint ist genau
ein weißes Canvas. Behoben, ebenso der gleiche fehlende `refresh` in
`reset-dc-for-autoscroll`. **Das ist kein Beweis, dass der einmalige Befund damit
erklärt ist** — nur, dass ein Mechanismus derselben Form gefunden und beseitigt wurde.

Für die nächste Sitzung: `PLT_QT_SCROLL_DEBUG=1` schaltet eine pro-Canvas getaggte
Ablaufverfolgung aller Scroll-Aufrufe an.

---

## Nicht gemacht (bewusst)

- **Fall 2 (§25.2, Colors-Tab).** Nutzerentscheidung, s. Phase 2. `canvas-panel%`
  bekommt gar keine Scrollbars — ein sichtbarer, aber wirkungsloser Scrollbar wäre
  schlechter als der Status quo.
- **Keine Cross-Platform-Validierung** (gebündeltes Modell, s. unten).
- Kein Anfassen von Shared Code: geändert wurden `wx/qt/canvas.rkt`, `wx/qt/utils.rkt`
  (Submodul) und `qt-shim/src/shim.cpp` + `examples/` + `docs/` (Umbrella).

## Nebenarbeit

`examples/live-resize-probe.rkt` trug seit §32 einen falschen Kopfkommentar („die
Verdrahtung ist NICHT im Baum"). Korrigiert — genau die Sorte veralteter Notiz, die
diesem Projekt schon zwei Sitzungen gekostet hat. `examples/scroll-probe.rkt` ist von
der Symptom- zur Akzeptanzprobe umgeschrieben.

## Liste „später zu validieren" (gebündelter Cross-Platform-Durchlauf)

Unverändert aus `docs/2026-09-14_report-linux.md` übernommen, plus:

- **Zuerst `qt-shim` neu bauen** — jetzt für **zwei** neue Exporte
  (`shim_window_set_resize_cb` aus §32, `shim_canvas_set_wheel_cb` aus §33). Ein
  Rebuild deckt beide.
- **Windows' §24.5-Symptom gegenprüfen:** dort war der Editor-Inhalt „komplett weiß".
  Erwartung: erledigt (derselbe Geometriefehler wirkte dort ebenso, und der fehlende
  Repaint in `show-scrollbars` ist behoben) — **nicht geprüft**.
- **Scrollbar-Dicke ist plattformabhängig** (`sizeHint`); auf macOS sind Overlay-
  Scrollbars möglich, die `sizeHint().width()` klein oder 0 melden. Zu prüfen, ob der
  Client-Abzug dort sinnvoll ausfällt.
- **Mausrad-Richtung und -Schrittweite** auf Windows/macOS gegenprüfen (natural
  scrolling auf macOS).
- `examples/scroll-probe.rkt` ist dort die Akzeptanzprobe; `PUMP OK` muss im Log stehen.

---

# Startpunkt für die nächste Sitzung

## Der offene Rest des Scroll-Clusters: Fall 2 (§25.2)

`'(auto-vscroll)`-Panels (Colors-Tab → Color Schemes, drei Buttons am Ende) bleiben
unerreichbar. Was dafür nötig ist, ist jetzt klar benannt statt vermutet:

1. `canvas-panel%` braucht ein **eigenes Content-QWidget** (`shim_panel_create`), das
   `get-content-hwnd` zurückgibt und das `reset-dc-for-autoscroll` per
   `shim_widget_set_geometry` mit negativem Offset verschiebt — das Qt-Äquivalent zu
   win32s `content-hwnd`.
2. Dann das `(not (is-panel?))`-Gate bei `want-h?`/`want-v?` in
   `wx/qt/canvas.rkt` entfernen.
3. Voraussichtlich **keine Shim-ABI-Änderung** (`shim_panel_create` und
   `shim_widget_set_geometry` existieren).

**Risiko, das die Sitzung tragen muss:** die Handle-Identität für alle Panel-Kinder
ändert sich. Akzeptanzkriterium: die drei Buttons sind durch Scrollen erreichbar **und
klickbar** (getrennt prüfen — §25.1 hat gezeigt, dass „sichtbar" und „klickbar"
auseinanderfallen können).

## Offene Unbekannte, ehrlich benannt

- Der einmalige, nicht reproduzierbare Tab-2-Befund oben. Wenn er wieder auftritt:
  `PLT_QT_SCROLL_DEBUG=1` mitlaufen lassen.
- Ob Windows'/macOS' Symptome sich nach dem Rebuild an Linux angeglichen haben.

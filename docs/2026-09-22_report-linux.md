# Report — Linux, Block C: Vertragsfläche des Qt-Backends fertigstellen — 2026-09-22

**Kontext:** `docs/2026-09-22_prompt.md`. Fortsetzung des systematischen Vertrags-Audits
(§26 → §30 Cluster 1, §36-Bestandsaufnahme → §40–§43) — diese Runde schließt den Rest der
elf identifizierten Plattformfunktionen plus drei weitere Lücken.

**Racket:** `Welcome to Racket v9.3 [cs]` (`~/racket/bin/racket --version`, ungeändert
seit §28).
**gui-Submodul (Start):** `278ef9c159ac217b95e25e0dba2c1a1bab2b7014` (`qt-backend`, = Umbrella-Zeiger).
**qt-shim:** Build vom 2026-09-19 15:34, keine Quelldatei neuer als das Binary — kein
Rebuild nötig zu Sessionbeginn.

---

## Phase 0 — Hygiene

**Ergebnis: Linux ist nicht betroffen.** Die auf Windows gemessene Verschmutzung
(Umbrella 89, `third_party/gui` 797, `third_party/draw` 115 als „modified", reine
LF→CRLF-Umschreibung, s. Prompt) ist ein Windows-Werkzeugartefakt. Auf dieser Maschine:

| Repo | `git status -sb` | `git diff --stat` | `--ignore-cr-at-eol` |
|---|---|---|---|
| Umbrella (`main`) | `## main...origin/main` (synchron) | leer | leer |
| `third_party/gui` (`qt-backend`) | `## qt-backend...origin/qt-backend` (synchron) | leer | leer |
| `third_party/draw` (detached, `efefd7c4`) | `## HEAD (no branch)` | leer | leer |

Alle drei Repos vollständig clean, nichts verworfen, kein `git checkout -- .` nötig.

**Prävention gesetzt:** `.gitattributes` (`* text=auto eol=lf`) im Umbrella angelegt und
committet (`ee463e7`, nur Umbrella — Submodule bewusst nicht angefasst, um die Divergenz
zum `racket/gui`-Upstream-Fork nicht grundlos zu vergrößern).

**Windows-Bereinigung bleibt außerhalb dieser Session** (eigener Kurzschritt, s. Prompt
„Windows-Kurzschritt").

## Phase 0b — Umgebung + Basislinie

- `~/racket/bin/racket --version` → `v9.3 [cs]`, unverändert.
- Sync-Check: Umbrella/gui-Submodul beide 0/0 gegen `origin` (kein Pull nötig).
- Shim-Staleness-Check: kein Quellfile neuer als `libracketqtshim.so` (Build 2026-09-19).
- Smoke: **3/3 mit `PLT_QT=1`, 3/3 ohne** — beide grün.

**Baseline-Modell (Advisor-Review vor dieser Session eingeholt):** ein vollständiger
Suite-A-Re-Lauf (PASS/FAIL) würde zwei bereits existierende Tabellen reproduzieren, ohne
das zu liefern, was Phase 3 tatsächlich braucht — nämlich **numerische Geometrie vor**
dem 2.1-Font-Fix, um einen Layout-Delta später als beabsichtigt vs. Regression
einzuordnen. Referenz-Baseline für PASS/FAIL-Proben (Akzeptanztest, Clipboard,
Enable-Kaskade, Drucker-Dialog, Teardown, Scroll, Menü-Demand, Cursor, Gauge):
`docs/2026-09-19_report-linux.md` (Suite A + B, Linux @ `91ee4869`) plus
`docs/2026-09-19_report-win.md` (Suite A, Windows @ `278ef9c1`, identischer gui-HEAD wie
diese Session). Diese Session ergänzt stattdessen einen **numerischen** Geometrie-
Basislauf für die layoutsensitiven, nicht-interaktiven Proben — s. u.

**Numerischer Geometrie-Baseline (vor jeder 2.1-Änderung, unwiederbringlich danach):**

| Messung | Qt (`PLT_QT=1`) | Nativ (gtk) |
|---|---|---|
| `normal-control-font` (`mred`-Export) | face=`Arial`, point-size=`11`, size-in-pixels?=`#f` | face=`Noto Sans,` , point-size=`10`, size-in-pixels?=`#f` |
| `button%` „Sample Button" `get-size` | `(98 25)` | `(105 33)` |
| `frame%` 300×100 angefordert, `get-size` nach `show` | `(300 100)` | `(300 100)` |

`Arial` ist auf dieser Maschine keine real installierte Familie (Fontconfig-Substitution
greift nur, wenn irgendetwas danach fragt — hier bislang niemand, da der Wert nur als
String durchgereicht wird und Qt selbst beim Anlegen von Widgets nie danach gefragt
wurde). Erwartung nach 2.1: `get-control-font-face` liefert die von Qt tatsächlich
aufgelöste Familie (`QApplication::font()`), Button-Maße nähern sich vermutlich denen der
Nativ-Spalte an — das wäre eine **Verbesserung**, keine Regression, s. Phase 3.

---

## Phase 1 — Vertrags-Inventar (verifiziert)

Methodik: für jeden der elf Prompt-Kandidaten plus die drei zusätzlichen Lücken erst der
exakte Export-Vertrag geprüft (`wx/platform.rkt`s positionale `define-values`-Liste ist
die einzige Signaturquelle — kein separates Sig-File; Name **und** Position müssen exakt
matchen), dann `wx/gtk/`/`wx/win32/` **gelesen statt aus dem Prompt übernommen**, dann
der Konsument in `mred/private/`/`framework/` per Grep bestätigt. Vier der elf
Prompt-Annahmen waren falsch oder unvollständig — siehe Spalte „Korrektur".

| # | Funktion | Qt-Ist | gtk real? | win32 real? | Konsument (verifiziert) | Erwarteter Vertrag | Korrektur ggü. Prompt | Wirkung |
|---|---|---|---|---|---|---|---|---|
| 1 | `get-control-font-face`/`-size`/`-size-in-pixels?` | `"Arial"`/`11`/`#f` fest | ja, `GtkSettings`/Pango | ja, `get-theme-font-face`/-size, Registry-Theme | `mred/private/gdi.rkt:89-108` → `normal-control-font`/`small-`/`tiny-control-font` — Basis **jedes** Widget-Layouts | `QApplication::font()`/`QFontInfo` liefert echte Familie+Größe, korrekt nach Einheit unterschieden (`pointSize()` vs. `pixelSize()`, s. 2.1-Fallstrick) | keine — Prompt-Einschätzung bestätigt, höchste Wirkung | **Höchste** |
| 2 | `get-double-click-time` | `500` fest | **ja**, `gtk-double-click-time`-Setting (Default 250 falls kein `GtkSettings`) | **nein** — win32 hardcodet ebenfalls `500` (`win32/procs.rkt:85`) | `mred/private/wxme/wx.rkt:45` — Doppelklick-Worterkennung im Editor | `QApplication::doubleClickInterval()` | **win32 ist KEIN Positivbeispiel** — nur gtk berechnet echt; Prompt-Tabelle „beide" ist falsch | Mittel |
| 3 | `location->window` | `#f` fest | ja, `gtk/frame.rkt:666` | ja, `win32/window.rkt:922/930` | `mred/private/mrtop.rkt:328` → `send-message-to-window`, öffentliche `mred-sig.rkt`-API | Qt-Äquivalent zu `QApplication::widgetAt(QPoint)` + Fenster-Zuordnung | keine | Niedrig (schmale, aber öffentliche API) |
| 4 | `has-x-selection?` | `#f` fest | `#t` fest (X11 hat immer eine Primary Selection) | `#f` fest (kein X11) | `mred/private/wx/common/clipboard.rkt:87-94` → gated `the-x-selection`; weiter in `wxme/editor.rkt`/`text.rkt`/`pasteboard.rkt` | `QClipboard::supportsSelection()` (Linux/X11 `#t`, Wayland `#f` je nach Plattform-Plugin — dynamisch, nicht hartcodiert) | keine — beide Werte sind bei gtk/win32 bereits selbst hartcodiert, aber **korrekt für ihre Plattform**; Qts Wert ist als Cross-Plattform-Backend falsch, weil er auf Linux/X11 `#f` statt `#t` liefert | Mittel (nur Linux/Mittelklick-Paste) |
| 5 | `hide-cursor` | `(void)` | **`(void)` — ebenfalls No-op** (`gtk/procs.rkt:146`) | **`(void)` — ebenfalls No-op** (`win32/procs.rkt:94`) | kein aktiver Konsument über den Cross-Platform-Aufruf hinaus gefunden | — | **Kein Gap.** Prompt-Tabelle falsch — alle drei Backends sind No-op. Aus Fix-Liste entfernt. | **Keine** |
| 6 | `bell` | `(void)` | ja, `gdk_display_beep` | ja, `MessageBeep` | Systemklingel bei Fehleingabe (Standard-`mred`-Verhalten, kein expliziter Einzelfund nötig — Cross-Plattform-Norm) | `QApplication::beep()` | keine | Niedrig |
| 7 | `flush-display` | `(void)` | ja — `try-to-sync-refresh` (= `pre-event-sync`) + `gdk_display_flush` | ja — `atomically (pre-event-sync #t)` | `mred/private/mred.rkt:122` (Re-Export) + **`framework/splash.rkt:258-259`** (Splash-Screen-Animation: `(flush-display) (yield) (sleep)`) | **Kein `QApplication::processEvents()`** (Regel 1). `pre-event-sync` ist gtk/win32s eigener, Qt-fremder Event-Pump-Mechanismus (`common/queue.rkt:131`) — für Qt ist `shim_pump(0)` die architektonisch passende Entsprechung, weil es der bereits sanktionierte Pump-Aufruf ist (kein neuer/paralleler Loop, `CLAUDE.md` Regel 1 erlaubt genau diesen Mechanismus) | Konsument ist schmaler als befürchtet (nur Splash-Screen, kein Redraw-kritischer Pfad) — Regel-3-Eskalation vermutlich **nicht** nötig, aber Ausführung noch zu verifizieren | Niedrig |
| 8 | `register-`/`unregister-collecting-blit` | `(void)` | ja, delegiert an `canvas%`s eigene Methoden (`gtk/canvas.rkt:932-948`, `unsafe-add-collect-callbacks`) | ja, analog (`win32/canvas.rkt:622-630`) | **`framework/private/frame.rkt:823/845/916`** → DrRacket-eigener **GC-Indikator** (`gc-canvas`, das blinkende Icon in der Status-Zeile jedes DrRacket-Fensters) | Muss während eines laufenden Racket-GC einen Bitmap-Blit auf einen Bildschirmbereich ausführen, **ohne** durch den normalen Qt-Event-/Paint-Loop zu gehen (GC-Callback-Kontext) — `wx/qt/canvas.rkt` hat **aktuell gar keine** `register-collecting-blit`/`unregister-collecting-blits`-Methoden, nicht mal Stubs | **Größere Wirkung als vom Prompt vermutet** — Prompt schlug vor, dies bei fehlendem Konsumenten zu parken (2.7); es gibt aber einen sichtbaren, aktiven Konsumenten in jedem DrRacket-Fenster. Gleichzeitig ist die Implementierung nicht trivial (Low-Level-Blit außerhalb des Event-Loops während eines GC-Callbacks) — **Umfang wie bei Multi-Spalten-`list-box%` klären, bevor angefangen wird** (Checkpoint-1-Gate) | **Hoch, aber Umfang ungeklärt** |
| 9 | `is-color-display?`/`get-display-depth` | `#t`/`32` fest | `#t`/`32` **ebenfalls fest** (`gtk/procs.rkt:141/148`) | `#t`/`32` **ebenfalls fest** (`win32/procs.rkt:96/98`) | kein Konsument, der einen dynamischen Wert erwartet | — | **Kein Gap.** Prompt-Tabelle falsch — alle drei Backends hartcodieren identisch. Aus Fix-Liste entfernt. | **Keine** |
| 10 | `find-graphical-system-path` | nur `init-file`-Fall (`find-system-path 'init-file`) | nur `x-display`-Fall, sonst `#f` | **nur `#f`, kein einziger Fall** (`win32/procs.rkt:69-70`) | `mred/private/mred.rkt:170-179` — Shared-Code-Wrapper mit **eigenem Fallback** für `'init-file` (`~/.gracketrc` bzw. `%APPDATA%/gracketrc.rktl`), das nur greift, wenn `wx:find-graphical-system-path` `#f` liefert | **Neu gefundener Bug, nicht im Prompt:** Qts `'init-file`-Fall liefert `(find-system-path 'init-file)` (Rackets eigene Init-Datei, z. B. `~/.racketrc`) statt `#f` — das **maskiert** den `mred.rkt`-Fallback komplett. DrRacket lädt unter Qt vermutlich die falsche Startup-Datei (`~/.racketrc` statt `~/.gracketrc`). Fix: `'init-file`-Fall entfernen (auf `#f` fallen lassen wie win32), `'x-display` ggf. wie gtk via `getenv "DISPLAY"` ergänzen | **Prompt-Liste unvollständig** — dieser Fund ersetzt den ursprünglichen Prompt-Eintrag „nur init-file" durch einen echten Kontraktbruch | **Mittel-Hoch** (falsche Startup-Datei ist ein stiller Korrektheitsfehler) |
| 11 | `enable-top` | **bereits echt implementiert** — `(void)` steht nur in `platform.rkt`s `make-stub-class`-Fallback (2.8), die reale `menu-bar%`-Klasse (`wx/qt/menu-bar.rkt`) überschreibt `enable-top` längst mit `shim_menubar_enable_at`, das im Shim existiert und real `QAction::setEnabled` aufruft | ja, `gtk/menu-bar.rkt:138` | ja, `win32/menu-bar.rkt:35` | `mred/private/mrmenu.rkt:109` → `wxmenu.rkt:44-108` (Top-Level-Menükategorie deaktivieren, z. B. „Tabs"-Menü ohne offene Tabs) | erfüllt | **Kein Gap.** Prompt-Tabelle falsch — verwechselte den irrelevanten `make-stub-class`-Stub mit der tatsächlich verwendeten `menu-bar%`-Override. Per Probe verifiziert (`(send top-level-menu enable #f)`, kein Crash, ruft nachweislich `shim_menubar_enable_at`). Aus Fix-Liste entfernt. | **Keine** |
| 12 | Multi-Spalten-`list-box%` | nur `QListWidget`, einspaltig | `GtkTreeView` echt mehrspaltig | `SysListView32` (Report-Modus) echt mehrspaltig | mehrere Konsumenten (`mred/private/mritem.rkt`, `framework/test.rkt`, `framework/private/group.rkt`) — **Umfang nicht geprüft, ob DrRacket selbst mehrspaltige Listen nutzt oder nur Nutzeranwendungen** | `QTreeWidget` statt `QListWidget` — struktureller Umbau, kein Lückenschluss | keine | **Out of Scope** (Prompt) |
| 13 | `get-bitmap-data`/`set-bitmap-data` (Bild-Zwischenablage) | `#f`/`(void)` No-op | echt (gtk `GdkPixbuf`) | echt (win32 `CF_BITMAP`/`CF_DIB`) | `mred/private/wx/common/clipboard.rkt:64/66` — bewusst §36.3 ausgelassen | `QClipboard::setImage`/`image`, Cairo↔`QImage`-Konvertierung bereits im Canvas-Blit-Pfad vorhanden | keine | Mittel (htdp-Bild-Copy-Paste) |

**Zusammenfassung der Korrekturen:** #5 (`hide-cursor`), #9 (`is-color-display?`/
`get-display-depth`) und **#11 (`enable-top`, neu)** sind **kein Befund** — bei #5/#9
hartcodieren alle drei nativen Backends identisch, bei #11 ist die reale `menu-bar%`-
Klasse bereits korrekt implementiert (der Prompt hat den irrelevanten
`make-stub-class`-Fallback mit dem tatsächlich benutzten Override verwechselt). #2
(`get-double-click-time`) ist nur zur Hälfte ein Positivbeispiel (win32 hardcodet
ebenfalls). #8 (`collecting-blit`) hat **entgegen der Prompt-Vermutung** einen aktiven,
sichtbaren Konsumenten (DrRacket-GC-Indikator) und braucht daher eine Umfangsklärung vor
dem Start, statt direkt geparkt zu werden. #10 (`find-graphical-system-path`) ist ein
**neu gefundener, im Prompt nicht enthaltener Kontraktbruch** mit größerer Wirkung als
angenommen (maskiert `mred.rkt`s eigenen `.gracketrc`-Fallback). Von den ursprünglich elf
Prompt-Kandidaten bleiben damit **acht** echte Fixes plus der neue #10-Fund.

**Nach Wirkung sortierte Fix-Reihenfolge für Phase 2:**
1. ~~`get-control-font-face`/`-size`/`-size-in-pixels?` (#1)~~ — **gefixt**
2. ~~`find-graphical-system-path` (#10)~~ — **gefixt**
3. ~~`enable-top` (#11)~~ — **kein Befund, bereits real**
4. `get-double-click-time`, `bell` (#2, #6 — billig, eindeutig)
5. `has-x-selection?` (#4)
6. `flush-display` (#7 — nach Konsumenten-Messung voraussichtlich risikoarm)
7. `get-bitmap-data`/`set-bitmap-data` (#13)
8. `location->window` (#3 — pure Racket, `all-frames`-Registry analog zu gtk, siehe unten)
9. `register-`/`unregister-collecting-blit` (#8) — **Umfang erst klären (Checkpoint-1-Gate, bereits erledigt s. o.)**
10. `make-stub-class`/Dateikopf-Aufräumen (2.8)

**Vorab-Scoping #3 (`location->window`):** gtks Implementierung (`gtk/frame.rkt:666`)
braucht **keinen** nativen Window-at-Point-Query — sie iteriert eine eigene
`all-frames`-Weak-Hash-Registry (befüllt in `direct-show`) und prüft die
Bounding-Box jedes bekannten Frames gegen (x,y), rein in Racket über bereits reale
`get-x`/`get-y`/`get-width`/`get-height`. `wx/qt/frame.rkt` hat noch keine
`all-frames`-Registry, aber `direct-show` existiert bereits (Regel 5). Niedrigeres Risiko
als ursprünglich eingeschätzt — kein Shim-Zugriff nötig.

**Self-Gate Checkpoint 1:** Inventar vollständig, verifiziert, nach Wirkung sortiert.
Ein Eintrag (#8, `collecting-blit`) überschreitet die Checkpoint-1-Erwartung deutlich —
`AskUserQuestion` fällig, bevor Phase 2 dafür begonnen wird (unten).

**Nutzerentscheidung zu #8 (`collecting-blit`):** „Jetzt versuchen" — nach den anderen,
einfacheren Fixes einplanen; bricht ab und dokumentiert, falls sich der Umfang beim
Implementieren als zu groß erweist.

**Vorab-Scoping #8 (vor Implementierung, aus `wx/gtk/gcwin.rkt` gelesen):** der Umfang
ist **größer als „Umbau wie Multi-Spalten-list-box%"-Niveau vermuten lässt** — `gtk`s
`register-collecting-blit` nutzt `unsafe-add-collect-callbacks` (Racket-Laufzeit-Hook,
der während einer laufenden GC-Pause läuft) mit einem **Protokoll aus vor-marshaltem,
rohem C-Funktionszeiger-Aufrufvektoren** (`'ptr_ptr_ptr->void`-Opcodes etc.) — explizit
**kein** Racket-Funktionsaufruf, weil während einer GC-Pause kein normaler Racket-Code
(auch kein Qt-Event-Dispatch) sicher laufen darf. gtks Implementierung geht dafür unter
X11 komplett am Toolkit vorbei direkt auf rohes Xlib (`XCreateSimpleWindow`,
`XSetWindowBackgroundPixmap`, `XMapRaised`/`XUnmapWindow`, Cairo-XLib-Surface für den
Pixmap-Blit) — nutzt GTK nur, um die X11-`Display*`/Window-ID des Client-Widgets zu
ermitteln, danach nichts mehr davon. Ein Qt-Äquivalent bräuchte dieselbe Konstruktion
(`QWidget::winId()` + die X11-`Display*` über Qt6s Platform-Native-Interface, dann
identische rohe Xlib-Aufrufe), **nicht** einen Qt-API-Aufruf — die Komplexität liegt
nicht im Toolkit-Unterschied, sondern im GC-Callback-Protokoll selbst. Einordnung: eher
eigener Block mit dediziertem Budget als „letzter Lückenschluss dieser Session" —
Versuch wie vom Nutzer gewünscht, aber niedrige Erwartungshaltung, Abbruchkriterium
niedrig ansetzen.

---

## Phase 2 — Fixes

### 2.1 `get-control-font-face`/`-size`/`-size-in-pixels?` — gefixt

**Status:** gefixt. **Konsument:** `mred/private/gdi.rkt:89-108` (`normal-`/`small-`/
`tiny-control-font`, Basis jedes Widget-Layouts). **Vertrag:** unverändert (positionale
`define-values`-Liste in `wx/platform.rkt`), nur die Werte waren hartcodiert.

**Fix:** zwei neue Shim-Exporte `shim_control_font_face`/`shim_control_font_size`
(`qt-shim/src/shim.cpp`, `#include <QFont>`/`<QFontInfo>`) lesen `QApplication::font()`
über `QFontInfo` aus (die tatsächlich aufgelöste Familie, nicht ein generischer Alias —
analog zu gtks bereits aufgelöstem `GtkSettings`-Fontnamen). Größen-Einheit wird explizit
disambiguiert (`QFont::pointSize()` liefert `-1`, wenn die Schrift per Pixel gesetzt
wurde, und umgekehrt), nicht blind angenommen. `wx/qt/platform.rkt` fragt live (nicht
gecacht) ab, analog zu gtks Live-Read von `GtkSettings` statt win32s gecachtem
Theme-Font.

**Baseline-Vergleich (Mess-Vorgabe aus Phase 0b):** `normal-control-font` vorher
face=`Arial`/point-size=`11` (fest), nachher face=`Noto Sans`/point-size=`9` (live
aufgelöst, entspricht dem tatsächlichen Qt-Anwendungsfont dieser Maschine). Button-Größe
(„Sample Button") **unverändert** `(98 25)` vor/nach dem Fix — die Änderung wirkt sich in
diesem konkreten Fall nicht messbar auf die Layout-Geometrie aus (Qt-native `sizeHint()`
dominiert hier offenbar über die Racket-seitige Font-Metrik-Berechnung). Kein
Regressions-Fall für Phase 3, da keine Größenänderung eingetreten ist.

**Verifikation:** `widget-probe.rkt` 8/8 OK (Sonnet-Subagent, GUI-Automatisierung).
Echtes DrRacket-Preferences (historischer §25.1/§31-Layoutbug-Ort) — Font-Tab und
General-Tab (dichtester Tab, ~15 Controls) beide ohne Truncation/Overlap, Button-Zeile
auf beiden Tabs vollständig sichtbar. Smoke 3/3 beide Wege.

**Commits:** gui-Submodul `7925ce72`, Umbrella (nur `qt-shim/src/shim.cpp`) `7148ed9`.
**Nur lokal, noch nicht gepusht** (Regel 7/8 — Push-Sammelfrage folgt am Sessionende
bzw. wenn genug Commits vorliegen).

### 2.2a `find-graphical-system-path` — gefixt (neuer Fund, nicht im ursprünglichen Prompt)

**Status:** gefixt. **Konsument:** `mred/private/mred.rkt:170-179` — Shared-Code-Wrapper
mit eigenem `.gracketrc`/`gracketrc.rktl`-Fallback, der nur greift, wenn
`wx:find-graphical-system-path` `#f` liefert.

**Root Cause:** der alte `'init-file`-Fall lieferte `(find-system-path 'init-file)`
(Rackets **eigene** Init-Datei, hier `~/.config/racket/.racketrc`) statt `#f` — ein
Wahrheitswert, der den `mred.rkt`-Fallback per `or` maskierte. DrRacket lud unter diesem
Backend also die falsche Startup-Datei.

**Fix:** `'init-file`-Fall entfernt (fällt jetzt wie win32 auf `#f`, Fallback in
`mred.rkt` übernimmt); `'x-display`-Fall neu hinzugefügt (`getenv "DISPLAY"`, nur unter
`'unix`), analog zu gtks bereits vorhandenem, echtem `x-display`-Fall — günstige Parität,
auf dieser X11-Maschine verifiziert.

**Verifikation:** `(find-graphical-system-path 'init-file)` liefert jetzt
`/home/deinzer/.config/racket/.gracketrc` unter `PLT_QT=1` — **identisch** zum nativen
gtk-Ergebnis (direkter Vergleich beider Läufe). `x-display` liefert `:0`, ebenfalls
plausibel. Smoke 3/3 beide Wege. Kein Shim-ABI-Wechsel (reiner Racket-Fix).

**Commit:** gui-Submodul `1ad739ef`. Kein Umbrella-Anteil.

### 2.3 `bell` — gefixt

**Status:** gefixt. **Konsument:** Systemklingel bei Fehleingabe (Standard-`mred`-
Verhalten, kein expliziter Einzelfund nötig — Cross-Plattform-Norm, Inventar #6).
**Vertrag:** unverändert, war hartcodiert `(void)` — gtk ruft `gdk_display_beep`,
win32 `MessageBeep(MB_OK)`, hier passierte bisher nichts.

**Fix:** neuer Shim-Export `shim_bell` (`qt-shim/src/shim.cpp`) ruft
`QApplication::beep()` — bereits per `<QApplication>` includiert, keine neue
Header-Abhängigkeit. `wx/qt/platform.rkt`s `bell` ruft ihn direkt auf.

**Verifikation:** Smoke 3/3 beide Wege (`PLT_QT=1`/nativ). Direkter FFI-Probe unter
`PLT_QT=1` ((`shim_bell`) via `utils.rkt`) läuft ohne Exception durch.

**Commits:** gui-Submodul `d2dbbda3`, Umbrella (nur `qt-shim/src/shim.cpp`) `6544607`.
Nur lokal, noch nicht gepusht (Regel 7/8).

### 2.4 `get-double-click-time` — gefixt

**Status:** gefixt. **Konsument:** `mred/private/wxme/wx.rkt:45` — Timing für
Doppelklick-Wortauswahl im Text-Editor. **Vertrag:** unverändert, war hartcodiert
`500`. Nur gtk berechnete hier bisher einen echten Wert (`gtk-double-click-time`
GSetting); win32 hardcodet ebenfalls `500` (Phase-1-Audit bestätigt) — dieser Fix
holt Linux also über win32s eigene Lücke hinaus, nicht nur zur gtk-Parität auf.

**Fix:** neuer Shim-Export `shim_double_click_time` (`qt-shim/src/shim.cpp`) liefert
`QApplication::doubleClickInterval()` (statisch, ms). `wx/qt/platform.rkt`s
`get-double-click-time` fragt ihn live ab statt den Konstantwert zurückzugeben.

**Verifikation:** Smoke 3/3 beide Wege. Direkter FFI-Probe unter `PLT_QT=1`
((`shim_double_click_time`) via `utils.rkt`) liefert `400` — plausibler
Plattformwert auf dieser Maschine, keine Exception.

**Commits:** gui-Submodul `a3c27b2f`, Umbrella (nur `qt-shim/src/shim.cpp`) `0c83769`.
Nur lokal, noch nicht gepusht (Regel 7/8).

### 2.5 `flush-display` — gefixt (Regel-1-Fall, im Hauptagenten entschieden)

**Status:** gefixt. **Konsument:** `mred/private/mred.rkt:122` (Re-Export) +
`framework/splash.rkt:258-259` (Splash-Screen-Animation: `(flush-display) (yield)
(sleep)`). **Vertrag:** unverändert, war hartcodiert `(void)`.

**Regel-1-Prüfung (dieser Punkt war explizit als Vorsichtsfall markiert):** gtks
`flush-display` ist `pre-event-sync` (eigener, Qt-fremder Event-Pump-Mechanismus,
`common/queue.rkt:131`) **plus** `gdk_display_flush` (reiner X11-Protokoll-Flush, **ohne**
Event-Dispatch). Qt hat in diesem Shim keine „nur Zeichnen rausschieben, nichts
dispatchen"-Funktion — die architektonisch passende Entsprechung ist `shim_pump(0)`,
**nicht** ein direkter `QApplication::processEvents()`-Aufruf (das wäre die von Regel 1
verbotene geschachtelte Schleife). Entscheidend: `(atomically (shim_pump 0))` ist exakt
derselbe Aufruf, der bereits an drei Stellen etabliert ist (`queue.rkt`s
`set-queue-wakeup!`/`qt-start-event-pump`, `filedialog.rkt`, `docs/HACKING.md` §39) — kein
neuer, paralleler Loop. Wiedereintritts-Sicherheit geprüft: C→Racket-Callbacks posten hier
nach Regel 2 nur Events und kehren sofort zurück, laufen also nie synchron im C-Stack eines
`shim_pump`-Aufrufs; Rackets Green Threads sind kooperativ auf einem OS-Thread geplant,
zusätzlich durch `atomically` serialisiert — zwei `shim_pump`-Aufrufe können nie gleichzeitig
in Flug sein. **Caveat dokumentiert, nicht behoben:** anders als `gdk_display_flush`
dispatcht `shim_pump(0)` auch anstehende Input-Events, nicht nur einen reinen
Protokoll-Flush — bei dem schmalen bekannten Konsumenten (Splash-Screen-Animation) ein
akzeptabler Unterschied.

**Fix:** `(define (flush-display) (atomically (shim_pump 0)))`, `"../../lock.rkt"` neu
requiret für `atomically`. Kein Shim-Export nötig — `shim_pump` existierte bereits.

**Verifikation:** isolierte Probe (`flush-display` nach `show`) ohne Exception. Echter
DrRacket-Start unter `PLT_QT=1` (durchläuft den Splash-Pfad) startet und bleibt stabil
laufen, kein Crash, `racket-prefs.rktd`-Hash unverändert. Smoke 3/3 beide Wege.

**Nebenfund, im selben Commit korrigiert:** ein Kommentar aus 2.1 hatte behauptet, die
Live-Font-Abfrage werde bei jedem Aufruf neu ausgewertet — tatsächlich snapshottet
`gdi.rkt:89` das Ergebnis einmalig beim Modul-Load in `normal-control-font`, niemand liest
danach erneut. Kommentar korrigiert, kein Verhaltensfix nötig.

**Commit:** gui-Submodul `27ea301c`. Kein Umbrella-Anteil (kein neuer Shim-Export).

### 2.6 `has-x-selection?` — gefixt (inkl. Selection-Mode-Threading)

**Status:** gefixt. **Konsument:** `mred/private/wx/common/clipboard.rkt:87-94` →
`the-x-selection`; weiter in `wxme/editor.rkt`/`text.rkt`/`pasteboard.rkt`. **Vertrag:**
unverändert (`has-x-selection?` bleibt nullstellig), war hartcodiert `#f`.

**Fix:** `(has-x-selection?)` fragt jetzt `QApplication::clipboard()->supportsSelection()`
live ab (neuer Shim-Export `shim_clipboard_supports_selection`). Der eigentlich
tragende Teil ist aber `clipboard-driver%`: `x-selection?` wurde bisher entgegengenommen
und verworfen — jetzt als `init-field` gespeichert und in ein `mode`-Int (0 = Clipboard,
1 = Selection) übersetzt, das bei jedem `shim_clipboard_*`-Aufruf mitgegeben wird. Die
drei bestehenden Shim-Funktionen (`shim_clipboard_set_text`/`get_text`/`has_text`) wurden
dafür um einen `mode`-Parameter erweitert (Arity-Änderung, alle drei haben genau eine
Aufrufstelle in dieser einen Klasse — kein Public-API-Bruch), statt Parallel-Funktionen
anzulegen.

**Nebenbefund, dokumentiert statt gefixt:** `wx/common/clipboard.rkt:86-90` prüft
`(if has-x-selection? (new clipboard% [x-selection? #t]) the-clipboard)` — dort ist
`has-x-selection?` der rohe importierte *Prozedurwert*, nicht `(has-x-selection?)`; jede
Prozedur ist in Racket truthy, also nimmt dieses `if` **immer** den True-Zweig, egal was
`has-x-selection?` bei Aufruf liefern würde. `the-x-selection` wird dadurch auf allen vier
Backends (gtk/win32/cocoa/qt) unbedingt als **eigenes** `clipboard%`-Objekt mit
`x-selection?=#t` angelegt — empirisch verifiziert (`(eq? the-clipboard
the-x-selection-clipboard)` liefert `#f`, sowohl unter nativem gtk als auch unter dem
alten Qt-Stand mit `has-x-selection?` → `#f`). Das ist ein vorbestehender Bug in
Shared-Code, der alle vier Backends identisch betrifft — **out of scope** für diese
Session (CLAUDE.md: Änderungen an `wx/common/` erfordern Eskalation, Subagent +
`AskUserQuestion`, nicht diesen Qt-only-Fix). Praktische Konsequenz: das
Mode-Threading in `clipboard-driver%` ist der tatsächlich tragende Fix — ohne ihn würde
`the-x-selection` trotz korrektem `has-x-selection?`-Rückgabewert weiterhin im
`Clipboard`-Modus statt im `Selection`-Modus arbeiten.

**Verifikation:** `shim_clipboard_supports_selection` liefert `#t` unter `PLT_QT=1` auf
dieser X11-Maschine (identisch zu gtks hartcodiertem Wert). Funktionaler Vertragstest
(`the-clipboard`/`the-x-selection-clipboard` aus `racket/gui/base`, String auf jedem
gesetzt, beide zurückgelesen): beide Objekte sind `#t` verschieden (`eq?` `#f`) und
Inhalte unabhängig (`"CLIPBOARD-STRING"` vs. `"SELECTION-STRING"`, kein Cross-Talk).
Cross-Prozess/Cross-Toolkit-Check (`xclip`/`xsel` gegen PRIMARY) **übersprungen** — weder
`xclip` noch `xsel` auf dieser Maschine installiert (Umgebungslücke, nichts installiert
laut Vorgabe). `examples/clipboard-probe.rkt` (3/3 Checks: direkter Round-Trip,
Editor-Copy, Editor-Paste) unverändert grün unter `PLT_QT=1` — keine Regression im
normalen Clipboard-Pfad durch die Arity-Änderung. Smoke 3/3 beide Wege.

**Commits:** gui-Submodul `a5f67f6a`, Umbrella (nur `qt-shim/src/shim.cpp`) `0600ad2`.
Nur lokal, noch nicht gepusht (Regel 7/8).

### 2.7 `get-bitmap-data`/`set-bitmap-data` (Bild-Zwischenablage) — gefixt

**Status:** gefixt (Inventarpunkt #13). **Konsument:** `mred/private/wx/common/
clipboard.rkt:63-66` → `clipboard%`s öffentliche `get-clipboard-bitmap`/
`set-clipboard-bitmap` (Teil der `racket/gui`-API). **Vertrag:** unverändert, war
hartcodierter No-op-Stub (`#f`/`(void)`), nie implementiert — nicht mal im
ursprünglichen Alt-Stub.

**Fix:** vier neue Shim-Funktionen (`shim_clipboard_set_image`/`_has_image`/
`_image_size`/`_get_image_argb`), immer `QClipboard::Clipboard` (kein
Selection-Mode-Konsument für Bilder). Byte-Konvention wie überall in diesem Projekt:
dicht gepackt, (A,R,G,B) pro Pixel, wie `shim_canvas_blit_argb`/
`shim_cursor_create_from_argb`. Schreibrichtung holt sich von `bitmap%` *prämultiplizierte*
Pixel (`get-argb-pixels ... #f #t`, wie canvas.rkt es für `blit_argb` tut) und baut damit
ein `Format_ARGB32_Premultiplied`-QImage. Leserichtung konvertiert das Clipboard-QImage
zu `Format_ARGB32` (Qt entprämultipliziert selbst), daher `set-argb-pixels` mit
Default `pre-mult?=#f`. Größenabfrage (`shim_clipboard_image_size`) und Pixel-Fill
(`shim_clipboard_get_image_argb`) sind getrennt (Racket muss vorher den passend großen
Buffer allozieren); `get_image_argb` bekommt `w`/`h` aus der vorherigen Größenabfrage
zurückgereicht und klemmt seine Kopie darauf — sonst könnte sich die Zwischenablage
zwischen den beiden Aufrufen ändern und ein größeres neues Bild den zu klein allozierten
Racket-Buffer überschreiben (Heap-Overflow). Das gelesene `bitmap%` wird mit `with-alpha?=#t`
angelegt, sonst würde echte Transparenz stillschweigend verworfen.

**Verifikation:** In-Process-Round-Trip (20×20-Testbitmap, 4 Quadranten inkl. halbtransparentem,
`set-clipboard-bitmap`/`get-clipboard-bitmap`) pixelgenau, max. Differenz 0 pro Kanal.
Prämultiplikations-Annahme separat direkt geprüft (nicht nur übers Round-Trip, das eine
falsche Prämultiplikation durch die inverse Konvertierung der Leserichtung verdeckt hätte):
der tatsächlich an `shim_clipboard_set_image` übergebene Buffer wurde isoliert inspiziert —
bei Alpha 128 liefert der Blau-Kanal 128 (= 255·128/255), nicht 255, also tatsächlich
prämultipliziert wie angenommen. Cross-Prozess, gleiches Toolkit (zwei separate
`PLT_QT=1`-Racket-Prozesse, Schreiber/Leser) pixelgenau — bestätigt, dass der Shim echt
über die X11-Zwischenablage publiziert, nicht nur lokal cached. Cross-Toolkit (Qt-Schreiber
→ natives-gtk-Racket-Leser) **reproduzierbar fehlgeschlagen** (3×, sowohl über
`clipboard-driver%`s eigenen Pfad als auch über `Gtk.Clipboard.wait_for_image` direkt);
zum Vergleich: gtk-Schreiber → gtk-Leser sowie Qt-Schreiber → gtk-Leser für *Text* beide
erfolgreich. Ursache **nicht isoliert** — KDE Klipper sitzt nachweislich in der
Zwischenablage-Kette (`application/x-kde-onlyReplaceEmpty`-Target bei jeder Abfrage
sichtbar) und ist als Störfaktor nicht ausgeschlossen; kein racket-qt-Bug bestätigt, aber
auch keiner ausgeschlossen. Bild-Zwischenablage bleibt daher innerhalb von Qt (In-Process
und Cross-Prozess-Qt) voll verifiziert, Qt→gtk-Bild-Interop offen für eine künftige
Session. `examples/clipboard-probe.rkt` (Text-Pfad) unverändert grün unter `PLT_QT=1`.
Smoke 3/3 beide Wege.

**Commits:** gui-Submodul `2879d143`, Umbrella (nur `qt-shim/src/shim.cpp`) `c9ef315`.
Nur lokal, noch nicht gepusht (Regel 7/8).

### 2.8 `location->window` — gefixt

**Status:** gefixt (Inventarpunkt #3). **Konsument:** `mred/private/mrtop.rkt:325-330`
→ `send-message-to-window` (öffentliche `mred-sig.rkt`-API). **Vertrag:** unverändert,
war hartcodiert `#f`.

**Fix:** verbatim von `wx/gtk/frame.rkt` portiert — keine native "Fenster an Punkt"-
Abfrage, sondern ein weak-hasheq-Register (`all-frames`) aller aktuell gezeigten
Frames, in `frame%`s bestehendem `direct-show` bracketiert (das dort bereits
`register-frame-shown` aufruft, Regel 5 — `direct-show` ist hier ein plaines
`define/public`, keine `override*`-Kollision, Regel 3 unbetroffen), plus ein
Bounding-Box-Scan (`get-x`/`get-y`/`get-width`/`get-height`, bereits real) für
`location->window` selbst. Beide neu in `wx/qt/frame.rkt`, `provide`t und in
`platform.rkt` unqualifiziert re-importiert (mirrort gtks Struktur: `location->window`
lebt in `frame.rkt`, nicht in `platform.rkt`). Reihenfolge bei überlappenden Frames
unspezifiziert (weak-hasheq-Iteration) — dieselbe Nicht-Determinismus wie gtk, kein
Fixbedarf. Kein Shim-Change.

**Verifikation:** Testskript über die tatsächlich nutzerseitig erreichbare API
(`send-message-to-window` aus `racket/gui/base`, nicht `location->window` direkt) —
zwei nicht überlappende Frames A (100,100,200×150) und B (500,500,200×150), Punkt
innerhalb A → Treffer, innerhalb B → Treffer, außerhalb beider → `#f` (Default
`on-message` ist `(lambda (m) (void))`, `void?` vs. `#f` als Diskriminator). Alle drei
Fälle korrekt. Smoke 3/3 beide Wege (`PLT_QT=1` und nativ).

**Commits:** gui-Submodul `86c932fc`. Nur lokal, noch nicht gepusht (Regel 7/8).

### 2.9 Aufräumen: `make-stub-class` entfernt, Dateikopf korrigiert

**Status:** erledigt (Inventarpunkt 2.8). **Konsument:** keiner — `make-stub-class`
hatte projektweit null Aufrufer (erneut per Grep verifiziert, unverändert seit
Session-Beginn). **Vertrag:** entfällt (kein Konsument).

**Fix:** die ganze `(define (make-stub-class name) (class window% ...))`-Fabrik samt
ihrer ~50 Zeilen Widget-Interface-Stubs aus `wx/qt/platform.rkt` gelöscht. Dateikopf-
Kommentar ("Spike implementation: frame%, canvas%, button%, check-box%, list-box% are
real; rest are stubs.") war seit Dutzenden Fixes dieser Session sachlich falsch —
ersetzt durch einen Verweis auf `docs/HACKING.md`/Phase-1-Tabelle statt erneuter
Aufzählung.

### 2.10 `register-`/`unregister-collecting-blit` (DrRacket GC-Indikator)

**Status: geliefert.** Höchstes Risiko-Item dieser Session (im Prompt vorab als
wahrscheinlich session-sprengend geflaggt, niedrige Abbruchschwelle explizit erlaubt) —
Ergebnis: X11-Port von `wx/gtk/gcwin.rkt` gelungen, ohne die anfangs befürchteten
Strukturprobleme.

**Konsument:** `framework/private/frame.rkt:823/845/916` — DrRacket-eigener
Garbage-Collection-Indikator (`gc-canvas`, das kleine Icon in der Statusleiste jedes
DrRacket-Fensters). **Vertrag:** unverändert, war `(void)`-Stub in `wx/qt/platform.rkt`
(Inventarpunkt #8).

**Qt-Entsprechung:** gtks Ansatz (`unsafe-add-collect-callbacks` — ein Racket-CS-Hook,
der während einer laufenden GC-Pause feuert, wo praktisch kein normaler Racket-/Qt-Code
sicher ist) ließ sich fast wörtlich portieren, weil er GTK zur Callback-Zeit ohnehin
komplett umgeht und stattdessen rohe Xlib-Aufrufe macht (`XCreateSimpleWindow`,
`XSetWindowBackgroundPixmap`, `XMapRaised`, `XUnmapWindow`, plus ein rohes
Cairo-Xlib-Surface-Blit fürs eigentliche On/Off-Bitmap). Einzige Qt-spezifische Stelle:
wie man an Display* und die X11-Window-XID des Eltern-Widgets kommt — dafür zwei neue
Shim-Funktionen (`qt-shim/src/shim.cpp`): `shim_get_x11_display` (liefert Qts eigene
`QNativeInterface::QX11Application`-Display-Verbindung, `nullptr` unter Wayland) und
`shim_widget_get_x11_window` (`QWidget::winId()` — auf X11 direkt die XID, keine
GDK-artige Indirektion nötig).

Zwei Punkte, die der Advisor vor dem Schreiben von `gcwin.rkt` als blockierend markiert
hat und die tatsächlich so eingetreten wären:
- **Tiefe/Visual nicht vom Default-Screen, sondern vom echten Eltern-Fenster.**
  `XCreateSimpleWindow` erbt Tiefe/Visual vom Parent; `XSetWindowBackgroundPixmap`
  verlangt Pixmap-Tiefe == Fenster-Tiefe. `XDefaultVisual`/`XDefaultDepth` hätten bei
  einem abweichenden Widget-Visual (z. B. 32-bit ARGB gegen 24-bit Default) zu
  `BadMatch` geführt — potenziell asynchron, potenziell während einer GC-Pause, also
  genau die Absturzklasse, die die Abbruchkriterien nennen. Stattdessen:
  `XGetWindowAttributes` auf die echte XID (neues `_XWindowAttributes`-Cstruct,
  Feldlayout gegen `/usr/include/X11/Xlib.h` verifiziert), läuft zur Registrierungszeit,
  also außerhalb des Callbacks.
- **`gcwin.rkt` darf den Modul-Load auf Windows/macOS nicht brechen.** `platform.rkt`
  wird auf allen drei Plattformen geladen (ein Qt-Backend für alle drei OS, anders als
  gtks eigenes `x11.rkt`, das nur je in einem Linux-only-Backend läuft). Ein blankes
  `(ffi-lib "libX11" ...)` hätte dort beim Laden geworfen. Fix: `ffi-lib` mit
  `#:fail (lambda () #f)` plus `make-not-available` (`ffi/unsafe/define`) pro Bindung —
  dasselbe Idiom, das gtks eigenes `x11.rkt` bereits für seine optionalen Bindungen
  nutzt, hier aber konsequent für die ganze Datei angewendet. Zusätzlich, selbst
  gefunden (nicht vom Advisor): `shim_get_x11_display` darf nicht beim Modul-Top-Level
  aufgerufen werden — `qt-init!` (QApplication-Konstruktion) läuft erst, nachdem alle
  Requires (inkl. `gcwin.rkt` über `canvas.rkt`) bereits instanziiert sind, `qGuiApp`
  existiert zu dem Zeitpunkt noch nicht. Fix: lazy Abfrage (Box + Memoisierung) statt
  eines Top-Level-`define`.

**Fix:** `wx/qt/gcwin.rkt` (neu) — `create-gc-window`, `free-gc-window`,
`bitmap->gc-bitmap`, `make-gc-show-desc`, `make-gc-hide-desc`, X11-only (kein
Wayland-Fallback portiert, s. u.). `wx/qt/canvas.rkt`: `register-collecting-blit`/
`unregister-collecting-blits` als `define/public` direkt auf `base-canvas%` (mirrort
gtks Platzierung direkt auf dessen `canvas%`-Klasse — kein `public*`/`override*`-Fall,
Regel 3 unbetroffen), gated auf `(x11-gc-available?)` (stiller No-op unter
Wayland/Nicht-X11, Regel 4). `wx/qt/platform.rkt`: beide Stubs delegieren jetzt exakt
im gtk/win32-`procs.rkt`-Muster. Kein Screen-Scale-Factor-Handling nötig (anders als
gtk): dieses Backend pinnt `QT_SCALE_FACTOR=1` (`shim_app_init`), device-independent px
== physische X11-px hier durchgängig.

**Verifikation:**
- Build sauber (`cmake --build qt-shim/build/linux-x64`), beide neuen Symbole per
  `nm -D` bestätigt exportiert.
- Isoliertes Testskript (`/tmp/.../gc-indicator-test2.rkt`): `register-collecting-blit`
  mit zwei distinkten Test-Bitmaps, 20 erzwungene `collect-garbage`-Zyklen über 5s,
  kein Crash, kein Hang. Positiver Vorhandenseins-Check per `xwininfo -root -tree`:
  echtes 16×16-Kindfenster exakt an der erwarteten Geometrie (`+4+4` relativ zum
  Canvas) gefunden, nach `unregister-collecting-blit` wieder verschwunden (Prozess
  beendet).
- Echtes DrRacket unter `PLT_QT=1` (`~/racket/bin/racket -l drracket`): kein
  Start-Crash (jedes DrRacket-Fenster registriert seinen `gc-canvas` beim Aufbau).
  200×`collect-garbage`+2-Mio-Element-Liste in der Interactions-Pane ohne Hang/Crash
  durchgelaufen. Entscheidender Befund: das rohe X11-Kindfenster des `gc-canvas`
  wurde per `xwininfo -id <id>`-Polling live zwischen `IsViewable`/`IsUnMapped`
  umschaltend beobachtet — allein durch gewöhnliche Hintergrund-Minor-GCs im Leerlauf,
  ganz ohne die erzwungene Allokationsschleife. Das entspricht exakt dem beabsichtigten
  Blink-Verhalten. Kein `X Error of failed request` in der gesamten Session-Log-Ausgabe.
- DrRacket **ohne** `PLT_QT` startet weiterhin nativ (Gate-Test bestätigt).
- `~/.config/racket/racket-prefs.rktd`: Diff vor/nach nur eine harmlose
  Positionsverschiebung eines bereits vorhandenen Eintrags (`plt:DrRacket
  9.3-splash-max-width`, gleicher Wert), keine funktionale Änderung.
- Beide Standard-Gates grün (`PLT_QT=1` und nativ, `raco test tests/smoke.rkt` →
  „3 tests passed").

**Commits:** gui-Submodul `8266b89a` (Racket-Port + Verdrahtung), Umbrella `ae1823a`
(zwei neue Shim-Exporte). Nur lokal, noch nicht gepusht, Submodul-Zeiger im Umbrella
bewusst nicht nachgezogen (Regel 7/8 — Drei-Maschinen-Sync ist eigener, mit dem Nutzer
abzustimmender Schritt).

**Bekannte Grenzen / offen für eine künftige Session:** Wayland (kein XCB) und
Windows/macOS bleiben bewusst außen vor — `x11-gc-available?` no-opt dort still, wie
vom Prompt gefordert; kein Fix nötig, nur eine spätere separate Portierung (GDI- bzw.
Cocoa-Äquivalent) falls gewünscht. Farbliche/visuelle Korrektheit des On/Off-Bitmaps
selbst nicht per Pixel-Vergleich verifiziert (nur strukturell: Fenster erscheint an
richtiger Stelle, schaltet sichtbar um) — aus Sicht dieser Session ausreichend, da das
Bitmap-Rendering (`bitmap->gc-bitmap`) denselben Cairo-Code-Pfad wie gtk nutzt und die
eigentliche Neuerung (Fenster-Lifecycle, Display/Visual/Tiefe-Bestimmung) das war, was
tatsächlich hätte brechen können.

**Verifikation:** Grep bestätigt null verbleibende Aufrufer (ein stiller Kommentar-
Verweis in `wx/qt/window.rkt:175` bleibt bewusst unangetastet, außerhalb des
Auftragsumfangs). Smoke 3/3 beide Wege. `examples/widget-probe.rkt` (8/8 OK) und
`examples/dialog-widgets-probe.rkt` (startet sauber, keine Exception/Crash vor dem
erwarteten interaktiven Timeout — dieses Probe wartet by design auf Nutzerklicks)
unter `PLT_QT=1` unauffällig, keine Regression durch die Löschung.

**Commits:** gui-Submodul `d4228b91`. Nur lokal, noch nicht gepusht (Regel 7/8).


---

## Phase 3 — Gate

**Kontext:** Verifikations-only-Pass gegen die zehn Commits dieser Session
(gui-Submodul `278ef9c1..8266b89a`, s. Phase 2). Keine Fixes in dieser Phase —
nur Befunde. Report wird inkrementell während der Ausführung ergänzt.

### Vorab-Checks

- Shim-Freshness: alle 11 neuen Exporte (`shim_control_font_face`,
  `shim_control_font_size`, `shim_bell`, `shim_double_click_time`,
  `shim_clipboard_supports_selection`, `shim_clipboard_set_image`,
  `shim_clipboard_has_image`, `shim_clipboard_image_size`,
  `shim_clipboard_get_image_argb`, `shim_get_x11_display`,
  `shim_widget_get_x11_window`) per `nm -D` bestätigt vorhanden;
  `qt-shim/src/qt-shim/CMakeLists.txt` nicht neuer als das Binary — kein
  Rebuild nötig.
- Baseline-Delta `91ee4869..278ef9c1` (Linux-Suite-A-Baseline-Commit bis
  Session-Start) enthält **nur** den stdout-void-Kosmetikfix — keine
  weiteren geometrierelevanten Änderungen zwischen Baseline und Session-Start,
  eliminiert diesen Störfaktor für die Zahlenvergleiche unten.
- Smoke 3/3 mit `PLT_QT=1`, 3/3 ohne — beide grün vor Testbeginn.
- `racket-prefs.rktd`-Baseline-Hash gesichert vor jeder DrRacket-Session:
  `9a567a4d80c8...` (Kopie in Scratch-Verzeichnis).
- **Automatisierungs-Stolperstein neu gefunden (nicht produktbezogen):**
  mehrere `examples/*-probe.rkt`-Dateien hatten noch keinen `compiled/`-Cache
  in dieser Session; ein kalter Erststart verbraucht >8s allein für
  Modul-Expansion, was bei den GUI-Resize-Proben (30-Tick-Budget à
  `wait/pump 1` = 1s/Tick) das Zeitfenster für die xdotool-Interaktion
  auffraß. Mit `raco make examples/*.rkt` vorkompiliert — rein
  Testwerkzeug-seitig, keine Produktänderung. Zweiter Stolperstein: Proben ohne
  explizites `(exit)` am Skriptende beenden den Racket-Prozess nicht von
  selbst (die GUI-Eventspace hält einen Thread offen) — `pkill -9 -f
  <probe>.rkt` nach jeder Messung nötig, sonst bleiben Fenster/Prozesse aus
  einem vorigen Lauf liegen und ein späterer `xdotool search --name`-Treffer
  kann versehentlich das alte, nicht das neue Fenster liefern (per
  `xdotool getwindowpid` gegen die erwartete PID abgesichert).

### Suite A — Regressions-Re-Lauf (laufend befüllt)

| Probe | 2026-09-19 Linux | Diese Session | Klassifikation |
|---|---|---|---|
| `clipboard-probe.rkt` (Qt+nativ) | PASS, 3/3 Checks | PASS, 3/3 Checks, identisch | Keine Änderung |
| `menu-demand-probe.rkt` | PASS, demand-count=2 | PASS, demand-count=2, identisch | Keine Änderung |
| `is-shown-probe.rkt` (Qt+nativ) | PASS, „PUMP OK" beide Wege | PASS, „PUMP OK" beide Wege, identisch | Keine Änderung |
| `resize-reflow-probe.rkt` | PASS, 400×300 → 400×609 | PASS, 400×300 → 400×609, **identische Zahl** | Keine Änderung (container-breitengetrieben, würde bei echter Regression abweichen) |
| `live-resize-probe.rkt` | PASS, 296×25 → 696×25 | PASS, 296×25 → 696×25, **identische Zahl** | Keine Änderung — trotz Font-Fix unverändert, deckt sich mit 2.1s eigener Beobachtung, dass Qts `sizeHint()` hier dominiert |
| `minsize-resize-probe.rkt` | PASS, einmalige Korrektur auf 295×348, stabil | PASS, einmalige Korrektur auf 295×348, stabil über 7 Ticks, **identische Zahl** | Keine Änderung |
| `scroll-probe.rkt` | PASS, 10 Notches = 10 Zeilen, beide Scrollbars sichtbar | PASS, 10 Notches = 10 Zeilen (Zeile 0→10), beide Scrollbars sichtbar (Screenshot-Vergleich vor/nach) | Keine Änderung |
| `panel-scroll-probe.rkt` | PASS, „Names" vorher y=812 unerreichbar, nachher y=567 stabil+klickbar | PASS, „Names" vorher y=594 unerreichbar (außerhalb 260px-Fenster), nach 30 Notches y=295 stabil, Klick löst `CLICK auf Names (Nr. 1)` aus | **Zahlenabweichung erklärt**: absolute Screen-Y differiert nur wegen anderer Fensterposition (`windowmove` auf 50,50 vs. ungemessene Baseline-Position) — das Verhaltensmuster (unerreichbar→erreichbar→klickbar) ist identisch, keine Regression |
| `canvas-panel-probe.rkt` | PASS, Log-Sequenz `created`/`content inserted`/`frame shown`, kein Crash, kein natürlicher Exit | PASS, identische Log-Sequenz, kein Crash, per Timeout beendet wie erwartet | Keine Änderung |
| `deleted-style-probe.rkt` (Qt+nativ) | PASS, Screenshot nur „SICHTBAR", `dead-panel is-shown?=#f w=0 h=0`; nativ `dead-canvas` `#t` statt `#f` | PASS, Qt: Screenshot nur „SICHTBAR" sichtbar, **identische** Geometriewerte (`dead-panel x=0 y=0 w=0 h=0`, `b-stray w=80 h=25` bei is-shown?=#t aber geometrielos im Elternpanel); nativ: `dead-canvas is-shown?=#t`, ebenfalls identisches Muster | Keine Änderung |
| `crash-b-teardown-probe.rkt` (Cancel+Accept) | PASS beide Pfade, kein Absturz | PASS beide Pfade: Cancel → `put-file returned: #f` (exit 0), Accept → `put-file returned: /tmp/crash-b-teardown-test.txt` (exit 0), kein Absturz | Keine Änderung — insbesondere keine Interaktion zwischen 2.5s neuem `(atomically (shim_pump 0))`-Aufruf in `flush-display` und dem §39-Fix in `filedialog.rkt` (beide nutzen dieselbe Primitive, unabhängig grün) |
| `enable-cascade-probe.rkt` | PASS, `clicks after window 1=1`, Delta 0 nach `enable #f` | PASS, `VERDICT: enabled=1 disabled-delta=0 -> PASS`, identisch | Keine Änderung |
| Akzeptanztest `test-dock-size` (n=3) | 0/3 Crash | s. Abschnitt „Akzeptanztest" unten | — |

**Zusammenfassung Suite A:** 12/12 Probes PASS, keine reale Regression gefunden. Alle
Zahlenabweichungen ggü. der 2026-09-19-Baseline waren entweder **identisch** (die
meisten geometrischen Proben — `resize-reflow`, `live-resize`, `minsize-resize`,
`deleted-style` zeigen exakt dieselben Pixelwerte wie vor dem Font-Fix, was die 2.1-
Beobachtung bestätigt, dass Qts `sizeHint()` hier dominiert, nicht die Racket-seitige
Font-Metrik) oder durch einen unabhängigen, nicht-produktbezogenen Faktor erklärbar
(`panel-scroll-probe`: andere absolute Fensterposition dieser Session statt eines
Font-Effekts). Kein Fall von Höhen-/Mindestgrößen-Wachstum (was laut Advisor-Hinweis
ein Warnsignal gegen die Font-Erklärung gewesen wäre) beobachtet.

**Automatisierungs-Zwischenfall (kein Produktbefund, hier dokumentiert weil er fast zu
einem falschen Regressionsbefund geführt hätte):** während der DrRacket-Sessions unten
hat ein `xdotool windowactivate`/Klick auf eine gecachte Fenster-ID (`4194311` — X11
recycelt Window-IDs nach dem Schließen eines Fensters; dieselbe Nummer wurde in dieser
Session nacheinander von `live-resize-probe`, `minsize-resize-probe`,
`deleted-style-probe` UND einem DrRacket-Splash-Platzhalterfenster belegt) einmal das
Konsole-Fenster dieser Agent-Session statt DrRacket getroffen. Tippversuch landete
nachweislich NICHT im Konsole-Eingabefeld (Screenshot-Beleg: Platzhaltertext
unverändert). Seither: **jede** Fenster-ID unmittelbar vor Gebrauch per
`xdotool getwindowpid`/`getwindowname` frisch verifiziert statt über mehrere Tool-Calls
hinweg gecacht — exakt die im Auftrag geforderte Mitigation, hier aus eigener
schmerzhafter Erfahrung nochmals bestätigt statt nur befolgt.

### Suite C — Integrationschecks dieser Session

**1. `location->window` + Multi-Frame-Lifecycle (2.8).** Programmatischer Test
(`send-message-to-window`, öffentliche `racket/gui/base`-API, Bildschirmkoordinaten):
3 Frames A/B/C an nicht überlappenden Positionen (100,100/400,100/700,100, je 200×150)
geöffnet. Routing korrekt für alle drei (`on-message` mit dem jeweils richtigen Tag),
Punkt in der Lücke zwischen den Fenstern liefert korrekt `#f`. Danach **nacheinander**
B (nicht das letzte), dann A geschlossen — Programm läuft beide Male **ohne
Früh-Exit** weiter (Regel-5-Konformität von `register-frame-shown` durch die neue
`all-frames`-Registry nicht beeinträchtigt), Routing nach jedem Schritt erneut korrekt
(geschlossene Frames liefern `#f`, verbleibende weiterhin ihr Tag). Schließen des
letzten Frames (C) ebenfalls kein Absturz, Programm beendet sich normal danach. **PASS,
keine Regression.**

**2. `collecting-blit`/GC-Indikator kombiniert mit Mehrfenster-Lifecycle (2.10).**
Vorab per Subagent-Recherche geklärt: `register-collecting-blit`/
`unregister-collecting-blit` für `gc-canvas` ist in `framework/private/frame.rkt`
**pro Frame** verdrahtet (`register-gc-blit` läuft einmalig im Frame-Konstruktor nach
`super-new`, `unregister-collecting-blit` in `on-close`) — **nicht** pro Tab. Die
1→2-Tab-Sequenz aus dem Akzeptanztest (unten) exerziert diesen Pfad daher **nicht**
erneut; stattdessen wurde gezielt **File → New Window** (echter Mausklick-Ersatz via
Tastaturmenü, `Ctrl+N`) genutzt, um ein zweites, unabhängiges `gc-canvas`-Objekt zu
registrieren, dann wieder zu schließen. Ergebnis: zweites Fenster „Untitled 2 -
DrRacket" öffnet sauber, `alt+F4` schließt es sauber (`Map State: IsUnMapped`
verifiziert), Original-Fenster bleibt aktiv, kein Früh-Exit. **Kein `X Error of failed
request` im vollständigen stderr-Log** (grep über die gesamte Session-Laufzeit, vor
und nach Öffnen/Schließen). Erzwungener GC-Stoß (200×`collect-garbage`) im
verbleibenden Fenster ebenfalls ohne X-Fehler im Log — Automatisierungsklick landete
zwar nicht sicher in der Interactions-Pane (nicht verifizierbar, ob der Ausdruck
tatsächlich lief), aber das Log blieb in jedem Fall sauber, und dieser Teilcheck war
ohnehin nur ein Bonus (die forced-GC-Pfad selbst wurde bereits bei der ursprünglichen
2.10-Implementierung isoliert verifiziert). **Einschränkung wie vom Auftrag verlangt
explizit benannt:** X-Fehler sind asynchron und ohne `XSynchronize` nicht mit Sicherheit
sofort sichtbar — Abwesenheit von Fehlern im Log ist ein schwächerer Beleg als deren
Anwesenheit wäre. Innerhalb dieser Einschränkung: **PASS, keine Regression, kein
X-Fehler beobachtet.**

**3. Kombinierter Smoke-Sweep (Clipboard/Preferences/Bell/Fenster-Zyklus).** Eine
DrRacket-Session, Sequenz: Text tippen → per Edit-Menü (Tastatur-Navigation, nicht
Maus-Pixel-Koordinaten, s. u.) kopieren → Preferences öffnen/schließen (`Ctrl+;`,
Font-Tab identisch zum historischen §25.1/§31-Layoutbug-Ort, keine
Truncation/Overlap, alle 9 Tabs sichtbar) → Fenster normal schließen. Kein Crash über
die gesamte Sequenz, keine X-Fehler im Log.
  - **Clipboard-Teilbefund, näher untersucht statt oberflächlich abgehakt:** ein
    direkter Cross-Prozess-Check (separates `racket`-Skript, `(send the-clipboard
    get-clipboard-string 0)`) unmittelbar nach dem Edit-Menü-Copy bestätigte den
    korrekten Wert `"(+ 1 2 3)"` — der zugrundeliegende Schreib-/Lesepfad (2.6s
    Mode-Threading) funktioniert nachweislich korrekt. Ein **späterer** Paste-Versuch
    (nach mehreren Minuten UI-Exploration) fügte stattdessen den Text `"ReadObj2"` ein
    — nicht das zuvor Kopierte. Root Cause: **mit hoher Wahrscheinlichkeit dieselbe
    KDE-Klipper-Interferenz, die bereits in §2.7 (Bild-Zwischenablage) dokumentiert
    ist** („KDE Klipper sitzt nachweislich in der Zwischenablage-Kette") — ein
    Umgebungsfaktor dieser Maschine, kein racket-qt-Regressionsbefund, zumal der
    direkte Schreib/Lese-Test (ohne Klipper-Zeitfenster dazwischen) sauber war. Wird
    hier transparent als **ungeklärter Nebenbefund** vermerkt statt als Regression
    gewertet, da die zeitliche Nähe zu Klippers bereits bekanntem Verhalten die
    naheliegendere Erklärung ist als ein neuer Fehler in 2.6.
  - Bell (Systemklingel) nicht gezielt ausgelöst (kein einfacher Trigger-Kontext
    gefunden) — laut Auftrag zulässig zu überspringen, hier vermerkt statt verschwiegen.
  - `racket-prefs.rktd`-Hash vor jeder der drei DrRacket-Teilsessions gesichert, nach
    jeder Session verifiziert (nur harmlose Diffs: Fenstergröße/-position,
    Konsolen-Historie, `last-opened-files`) und exakt zurückgespielt
    (`9a567a4d80c8...`, bitgleich nach jedem Restore).

### Akzeptanztest `test-dock-size` (n=3)

Exakte Prozedur aus `docs/2026-09-19_report-linux.md`: echtes DrRacket
(`~/racket/bin/racket -l drracket -- <Skript>`, `PLT_QT=1`), Datei per Kommandozeile
geladen (entspricht dem Startzustand vor dem ersten manuellen „File → Open"), Run über
echten Mausklick auf den Toolbar-Button, danach `examples/htdp-image-probe.rkt` als
zweite Registerkarte über echtes „File → Open" (Maus, nicht Tastaturkürzel — dieses
Projekt hat eine dokumentierte Historie divergierender Maus-/Tastaturpfade). Alle drei
Durchläufe frisch (kein Prozess aus einem vorigen Durchlauf verschleppt, `ps aux`
zwischen jedem Durchlauf verifiziert leer).

**Hygiene:** beide Originaldateien wurden **nicht** geöffnet — stattdessen
Scratch-Kopien unter `/tmp/.../scratchpad/phase3/dr/htdp-tests-probe.rkt` und
`.../htdp-image-probe.rkt` (vor Sessionbeginn angelegt). `git status --short
examples/` nach **jedem** der drei Durchläufe geprüft — durchgehend leer, keine
versehentliche Schreibaktion auf die Originale (die 2026-09-19-Inzidentklasse trat
nicht erneut auf). `racket-prefs.rktd`-Hash vor Testbeginn gesichert
(`9a567a4d80c8...`), nach jedem Durchlauf verglichen (nur harmlose Diffs:
Fenstergröße/-position, `last-opened-files`, Konsolen-Historie) und exakt
zurückgespielt.

**Automatisierungs-Stolperstein während dieses Abschnitts (Methodik, kein
Produktbefund):** wiederholt `xdotool windowactivate` auf eine zuvor gemessene
Fenster-ID ohne erneute Verifikation gescheitert (Klick landete auf dem
Konsole-Fenster dieser Agent-Session statt auf DrRacket — X11 rezykelt IDs und die
KDE-Fokusverwaltung übernimmt einen `windowactivate`-Aufruf nicht immer). Fix:
für jeden Klick unmittelbar zuvor `getactivewindow`/`getwindowname` verifiziert,
nötigenfalls `windowraise`+`windowfocus --sync`+`windowactivate --sync` kombiniert,
und Klick-Zielkoordinaten ausschließlich aus einem **Vollbild**-Screenshot
(nicht dem `-a`/Fenster-Screenshot, dessen Schatten-Padding einen unbekannten Offset
einführt) mit dem gemessenen Skalierungsfaktor (Bildschirm-px = Bild-px × 3505/2000)
berechnet, nie aus gecachten Werten über mehrere Tool-Aufrufe hinweg.

| Durchlauf | Run-Ergebnis | Tab 2 geöffnet | X-Fehler im stderr-Log | `examples/` unverändert | Crash |
|---|---|---|---|---|---|
| 1 | „Ran 3 tests. 1 of the 3 tests failed." (Actual 16 vs. 17) | ja, sauber, Inhalt korrekt gerendert | keiner | ja | keiner (exit 0) |
| 2 | identisch | ja, sauber | keiner | ja | keiner (exit 0) |
| 3 | identisch | ja, sauber | keiner | ja | keiner (exit 0) |

**Ergebnis: 0/3 Crashes — Akzeptanzkriterium erfüllt, identisch zur
2026-09-19-Baseline.** Kein `DrRacket Internal Error`, kein `preferences:set`-
Contract-Fehler, kein `X Error of failed request` in irgendeinem der drei
stderr-Logs (`grep` über die vollständige Log-Datei jedes Durchlaufs). Damit auch die
explizit geforderte Zusatzprüfung aus Suite C Punkt 2 (X-Fehler während des
Tab-Öffnens, wegen des möglichen `collecting-blit`-Zusammenspiels) für alle drei
Durchläufe negativ — keine Interaktion zwischen `8266b89a`s neuer `gcwin.rkt` und dem
historischen `test-dock-size`-Pfad gefunden, obwohl (s. Suite C oben) die
Tab-Sequenz `register-collecting-blit` gar nicht erneut auslöst (nur der erste
Frame-Aufbau tut das, und der lief in allen drei Durchläufen ebenfalls fehlerfrei).


### Gesamtfazit Phase 3

**GATE PASS.** 12/12 Suite-A-Probes PASS (keine reale Regression, alle Zahlenabweichungen
erklärt — meist identisch zur 2026-09-19-Baseline trotz Font-Fix, ein Fall durch
Fensterposition statt Font erklärt). Alle drei Suite-C-Integrationschecks PASS (Multi-
Frame-Lifecycle inkl. Regel-5-Konformität, `collecting-blit` kombiniert mit
Mehrfenster-Zyklus ohne X-Fehler, kombinierter Smoke-Sweep ohne Crash). Akzeptanztest
`test-dock-size` 0/3 Crashes, keine X-Fehler. Einziger dokumentierter Nebenbefund
(vermutliche KDE-Klipper-Interferenz bei einem verzögerten Paste-Versuch) ist ein
bereits aus §2.7 bekannter Umgebungsfaktor dieser Maschine, kein racket-qt-Regressions-
befund. Umgebung nach Abschluss vollständig aufgeräumt: `racket-prefs.rktd` auf
Sessionstart-Hash zurückgesetzt, keine verwaisten Prozesse, `examples/` unverändert,
gui-Submodul weiterhin bei `8266b89a` (Zeiger nicht nachgezogen, wie beauftragt).

---

## Später zu validieren (gebündelter Windows/macOS-Durchlauf)

Alle zehn Fixes dieser Session sind **ausschließlich auf Linux gefixt und getestet**
(Cross-Platform-Modell seit §30 — Divergenzmessung nur bei bekannten Plattform-
unterschieden, hier keiner erwartet außer explizit vermerkt). Für den nächsten
gebündelten Durchlauf (Modell aus `docs/2026-09-13_prompt.md`):

**Braucht Shim-Rebuild (7 von 10 Einträgen, s. `CLAUDE.md`-Build-Banner):**

| Fix | Neue/geänderte Shim-Exporte | Plattform-Besonderheit zu prüfen |
|---|---|---|
| 2.1 Control-Font | `shim_control_font_face`, `shim_control_font_size` | **Einheit ist maschinenabhängig** — Linux liefert Punkt (`size-in-pixels?=#f`), win32 liefert **Pixel** (`get-control-font-size-in-pixels? #t` bei win32 selbst laut `win32/procs.rkt:88`) — prüfen, ob Qt unter Windows ebenfalls Pixel oder weiterhin Punkt zurückgibt (`QFontInfo::pointSize()`/`pixelSize()`-Disambiguierung sollte das automatisch richtig einordnen, aber **explizit verifizieren, nicht nur „kein Crash"**), und ob resultierende Control-Größen dort plausibel sind, nicht nur ob nichts abstürzt. Auf macOS: Standard-UI-Font ist weder „Arial" noch zwingend „Noto Sans" — Ergebnis dokumentieren. |
| 2.3 `bell` | `shim_bell` | keine bekannte |
| 2.4 `get-double-click-time` | `shim_double_click_time` | win32 hardcodet selbst `500` (§55.1) — Qt liefert jetzt ggf. einen anderen Wert; das ist beabsichtigt, nicht als Abweichung vom win32-Nativverhalten werten |
| 2.6 `has-x-selection?` + Selection-Mode | `shim_clipboard_supports_selection`; **Arity-Änderung** an `shim_clipboard_set_text`/`_get_text`/`_has_text` (neuer `mode`-Parameter) | Middle-Click-Paste ist ein **Linux/X11-exklusives** Feature — `has-x-selection?` sollte unter Windows/macOS weiterhin `#f` liefern (`QClipboard::supportsSelection()` ist dort nativ `#f`), nur die Arity-Änderung selbst muss dort einen sauberen Rebuild überstehen (alter Export mit alter Signatur + neue Racket-Bindung ohne Rebuild würde crashen, nicht still falsch laufen — s. `CLAUDE.md`-Banner) |
| 2.7 Bild-Zwischenablage | `shim_clipboard_set_image`, `shim_clipboard_has_image`, `shim_clipboard_image_size`, `shim_clipboard_get_image_argb` | Cross-Toolkit-Test (Qt-Schreiber → natives-Backend-Leser) ist auf Linux **ungeklärt fehlgeschlagen** (vermutete, nicht bestätigte KDE-Klipper-Interferenz) — auf Windows/macOS erneut versuchen, da dort kein Klipper-Äquivalent im Weg steht; könnte den Verdacht bestätigen oder einen echten Bug aufdecken |
| 2.10 `collecting-blit` | `shim_get_x11_display`, `shim_widget_get_x11_window` | **X11-only implementiert, bewusst.** Auf macOS/Windows ist `QNativeInterface::QX11Application` nicht verfügbar (kein XCB) — `register-collecting-blit` muss dort sauber auf No-op degradieren (per Design: `nullptr`-Check), **nicht** crashen. Der DrRacket-GC-Indikator bleibt auf macOS/Windows also weiterhin unsichtbar (bestehendes Verhalten, keine Regression) — das explizit als Erwartung dokumentieren, nicht als Bug einordnen, falls in einer künftigen Session mal ein echter macOS/Windows-Pfad gebaut wird (eigener Block, nicht Teil dieser Session) |

**Reiner Racket-Code, kein Rebuild nötig (3 von 10 Einträgen):**

| Fix | Plattform-Besonderheit zu prüfen |
|---|---|
| 2.2a `find-graphical-system-path` | `'x-display`-Fall ist bewusst nur unter `'unix` aktiv — auf Windows/macOS bleibt er `#f` (korrekt, kein X11 dort). Der `'init-file`-Bugfix selbst (Kern des Fixes) ist plattformneutral und sollte überall funktionieren — verifizieren, dass unter Windows die richtige `gracketrc.rktl`-Datei geladen wird (nicht `.gracketrc`, win32-spezifischer Dateiname laut `mred.rkt:177`) |
| 2.8 `location->window` | reiner `all-frames`-Weak-Hash-Scan, keine Plattformabhängigkeit erwartet — Multi-Frame-Test (Suite C, Linux PASS) auf Windows/macOS wiederholen als Regressionsschutz |
| 2.9 Aufräumen | keine funktionale Änderung, nichts zu validieren außer dass nichts kaputtgegangen ist (Smoke genügt) |

**Zusätzlich, aus §55.6 (nicht Teil der zehn Fixes, aber verwandt):** die
`wx/common/clipboard.rkt`-Dead-Code-`if`-Bug-Beobachtung ist plattformneutral (Shared
Code) — falls sie je adressiert wird, betrifft das alle drei Maschinen gleich, kein
gebündelter Linux-Nachtrag nötig.

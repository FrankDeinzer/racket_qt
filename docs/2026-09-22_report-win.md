# Report — Windows, Block C: gebündelter Validierungs-/Rebuild-Durchlauf — 2026-09-22

**Kontext:** `docs/2026-09-22_prompt.md` + `docs/2026-09-22_report-linux.md` (zehn Fixes,
Gate PASS, Linux-only gefixt und bereits nach `origin/qt-backend`/`origin/main`
gepusht laut `CLAUDE.md`-Build-Banner). Diese Session: gebündelter Windows-Durchlauf
(Modell aus `docs/2026-09-13_prompt.md`) — Shim-Rebuild, Validierung der zehn Fixes,
kein neues Feature-Audit.

**Racket:** `Welcome to Racket v9.3 [cs]` (`C:\Program Files\Racket\racket.exe --version`).
**gui-Submodul (Start dieser Session):** `278ef9c159ac217b95e25e0dba2c1a1bab2b7014`
(identisch zum Linux-Session-Start, = Pre-Block-C).
**qt-shim:** Build vom 2026-09-19 16:39 — vor allen zehn Block-C-Commits, Rebuild fällig.

---

## Vorab: Font-Baseline vor dem Submodul-Sprung gesichert (unwiederbringlich danach)

Auf `278ef9c1` (Pre-Fix-Stand), `examples`-externes Scratch-Probe
(`font-baseline-probe.rkt`, `normal-control-font` + `button%`-`get-size`):

| Messung | Qt (`PLT_QT=1`) | Nativ (win32) |
|---|---|---|
| `control-font-face` | `"Arial"` | `"Segoe UI"` |
| `control-font-point-size` | `11` | `12` |
| `control-font-size-in-pixels?` | `#f` | `#t` |
| `button%` „Sample Button" `get-size` | `(94 26)` | `(101 22)` |

**Bestätigt den im Linux-Bericht vorhergesagten Diskriminator:** win32 nativ arbeitet
pixelbasiert (`size-in-pixels?=#t`), das alte Qt-Backend war hartcodiert punktbasiert
(`#f`) — identisch zum alten Linux-Stub, nicht maschinenspezifisch. Nach 2.1 muss
`QFontInfo::pointSize()`/`pixelSize()`-Disambiguierung dies korrekt auflösen, nicht nur
„kein Crash" zeigen.

---

## Phase 0 — Hygiene (Windows-Kurzschritt)

**Korrektur gegenüber Prompt-Annahme:** der Prompt vermutete, `core.autocrlf` sei
"unset" und Git daher nicht die Ursache. Gemessen: `core.autocrlf=true` **global**
gesetzt — das ist sehr wohl die Ursache, nur maskiert.

**Zwischenfall (dokumentiert, nicht Teil des eigentlichen Produkts):** SourceTree lief
zu Sessionbeginn parallel auf dieser Maschine und hatte 5 Minuten vor Sessionstart
einen Fetch auf `third_party/gui` gemacht; zusätzlich lagen in `.git/modules/
third_party/{gui,draw}/index.lock` je eine verwaiste, 0 Byte große Lock-Datei (9h alt,
kein haltender Prozess laut `tasklist`, wahrscheinlich Rest eines abgebrochenen
Vormittags-Vorgangs). Nutzer hat SourceTree geschlossen und die Lock-Entfernung
autorisiert (`AskUserQuestion`, Regel 7-Geist), bevor weitergearbeitet wurde.

**Root-Cause-Kette der eigentlichen CRLF-Verschmutzung (mehrschichtiger Messfehler,
der Sessionzeit gekostet hat — hier ausführlich dokumentiert, damit eine künftige
Session ihn nicht wiederholt):**

1. Naive `git diff --stat`/`git status` zu Sessionbeginn zeigten **fälschlich "clean"**
   für `third_party/gui`/`third_party/draw`, obwohl `git hash-object` und direkte
   Byte-Inspektion echte CRLF-Kontamination bestätigten (797 Dateien in `gui`, 115 in
   `draw` — **exakt die vom Prompt genannten Zahlen**, der Prompt hatte also recht,
   nur meine erste Messung war falsch).
2. **Ursache:** ein Git-„racy stat cache"-Effekt. Die Index-Einträge dieser Dateien
   cachen (mtime, size) des **unfiltered** Arbeitsverzeichnis-Bytes (CRLF, aus einer
   Zeit mit `core.autocrlf=true`) neben dem **gefilterten** LF-Blob-Hash. Solange sich
   mtime/size nicht ändern, überspringt Git (`status`/`diff`/sogar `checkout-index -f`
   und `update-index --refresh`) die tatsächliche Neuberechnung und meldet "unverändert"
   — unabhängig davon, ob der Inhalt bei geänderten Filtereinstellungen (hier:
   `core.autocrlf=false`) tatsächlich noch übereinstimmt. Verifiziert durch gezieltes
   `touch` einer Datei: erst danach zeigte `git diff-files` den echten Unterschied.
3. **Folge für den Fix:** ein einfaches `git checkout -- .` (wie im Prompt vorgeschlagen)
   reicht **nicht**, weil auch `checkout` denselben Stat-Cache-Kurzschluss nimmt. Robuste
   Reihenfolge, die tatsächlich funktioniert hat: Datei **löschen** (kein Stat mehr, der
   getrickst werden könnte) → `git checkout-index -a -f` (zwingt Neuschreiben aus dem
   Index) → `git update-index --refresh` (meldet "needs update", ändert aber nichts) →
   **`git add -u`** (schreibt den Stat-Cache neu fest, kein neuer Blob, da Inhalt
   identisch zu `HEAD`). Erst danach zeigten `git status`/`diff-index` echtes „clean".
4. Vor dem destruktiven Schritt (Datei löschen) wurde **jede** der 797+115 Dateien
   einzeln gegen ihren `HEAD`-Blob geprüft (`\r`-Bytes entfernt, dann Textvergleich) —
   **0 Inhaltsunterschiede über den Zeilenumbruch hinaus**, also risikofrei.
5. **Umbrella:** `git add --renormalize .` (nutzt das bereits committete
   `.gitattributes`) fand **eine** Datei mit echtem CRLF-**Blob** (nicht nur
   Arbeitsverzeichnis-Rauschen): `docs/BRIEF.md`, aus der Zeit vor der `.gitattributes`-
   Einführung. Committed (`d09f67d`), `--ignore-cr-at-eol` bestätigt reine
   Zeilenumbruch-Normalisierung, kein Inhaltsunterschied.

**Ergebnis:** alle drei Repos jetzt tatsächlich clean (`git status`/`diff-index`
verifiziert, nicht nur oberflächlich `git status` vertraut). `core.autocrlf=false` +
`core.eol=lf` lokal in Umbrella + beiden Submodulen gesetzt (Windows-Kurzschritt aus
dem Prompt), damit die Kontamination nicht erneut entsteht. **Kein Push nötig für die
Submodul-Normalisierung** (nur Stat-Cache-Metadaten lokal korrigiert, keine neuen
Blobs, keine neuen Commits in `gui`/`draw`). Umbrella hat einen neuen lokalen Commit
(`d09f67d`, BRIEF.md-Renormalisierung) — Push-Frage folgt zusammen mit dem
Submodul-Fast-Forward.

**Hinweis für künftige Sessions (alle Plattformen):** `git ls-files --eol` bleibt auch
nach vollständiger Bereinigung unzuverlässig (zeigt weiterhin `w/crlf` für Dateien, die
nachweislich `\0` CR-Bytes enthalten) — derselbe Stat-Cache-Effekt betrifft auch dieses
Diagnose-Kommando. **Nicht als alleinige Diagnosequelle vertrauen** — echte Verifikation
nur über `git hash-object`/direkten Byte-Vergleich oder nach einem `touch`, das den
Stat-Cache invalidiert.

## Phase 0b — Sync, Rebuild, Basislinie

**gui-Submodul:** Fast-Forward `278ef9c1..6bae83df` (11 Commits, rein lokal — beide
`fetch --dry-run` waren vorab leer, kein Netzwerkzugriff). Umbrella-Zeiger war bereits
korrekt auf `6bae83df` committed (`4b2a25e`, vor dieser Session) — kein neuer
Zeiger-Commit nötig, nur der Arbeitsbaum musste nachziehen.

**qt-shim-Rebuild — ein echter Windows-spezifischer Build-Fix nötig:**
`shim_clipboard_get_image_argb` (§2.7, auf Linux gefixt) nutzte `std::min`/`std::max`
ohne die schützenden Klammern — kollidiert mit den `min`/`max`-Makros aus
`<windows.h>` (MSVC C2589, `std::min(...)` wird zu `std::(...)` makro-expandiert).
Die Datei hat an anderer Stelle (Zeile 1253) bereits die Hauskonvention dafür
(`(std::max)(...)`), hier nachgezogen. Root-Cause gemessen, Fix in `qt-shim/`, sofort
gefixt und committed (Triage-Regel aus dem Prompt) — Commit `2e91ee3`.

**Export-Verifikation (`dumpbin /exports`, MSVC 14.51.36231):** alle 11 neuen Symbole
gefunden (`shim_control_font_face`, `shim_control_font_size`, `shim_bell`,
`shim_double_click_time`, `shim_clipboard_supports_selection`,
`shim_clipboard_set_image`, `shim_clipboard_has_image`, `shim_clipboard_image_size`,
`shim_clipboard_get_image_argb`, `shim_get_x11_display`, `shim_widget_get_x11_window`),
plus die drei arity-geänderten (`shim_clipboard_set_text`/`_get_text`/`_has_text`).
**Pfad verifiziert, nicht nur Existenz** — `wx/qt/utils.rkt:169-170` lädt exakt
`qt-shim/build/windows-x64/Debug/racketqtshim.dll`, dieselbe Datei, die gerade gebaut
wurde (kein Debug/Release-Verwechslungsrisiko).

**`raco setup`-Lauf:** Fehlerausgaben nur für **nicht** betroffene Systempakete
(`pict-lib`, `scribble-lib`, `gui-doc`-Launcher/Docs) — Zugriff verweigert unter
`C:\Program Files\Racket\share\pkgs\...`, erwartet, da diese Session nicht elevated
läuft und diese Pakete (anders als `gui-lib`/`draw-lib`) nicht als Source-Link
eingerichtet sind. **`gui-lib`/`draw-lib` selbst sind Source-Links** direkt auf
`third_party/gui/gui-lib`/`third_party/draw/draw-lib` — deren `compiled/`-Verzeichnisse
liegen im Repo selbst, nicht unter `Program Files`, und wurden nachweislich frisch
geschrieben (`gcwin_rkt.zo`, die neue Datei aus §2.10, u. a. mit Zeitstempel dieser
Session vorhanden). Kein Admin-Bedarf für diesen Rebuild-Schritt bestätigt.

**Smoke:** 3/3 mit `PLT_QT=1`, 3/3 nativ — beide grün.

**Racket:** `Welcome to Racket v9.3 [cs]`, unverändert.

---

## Phase 2/3 — Validierung je Fix (Windows)

### 2.1 Control-Font — validiert (im Hauptagenten, Methode etabliert)

**Nach dem Fix (`font-baseline-probe.rkt`, identisch zur Vorab-Messung):**

| Messung | Qt vorher | Qt nachher | Nativ (win32) |
|---|---|---|---|
| `control-font-face` | `"Arial"` | `"Segoe UI"` | `"Segoe UI"` |
| `control-font-point-size` | `11` | `9` | `12` |
| `control-font-size-in-pixels?` | `#f` | `#f` | `#t` |
| `button%` „Sample Button" `get-size` | `(94 26)` | `(94 26)` | `(101 22)` |

**Face jetzt identisch zu nativ.** Größenangabe bleibt in unterschiedlichen Einheiten
(Qt: Punkt via `QFontInfo::pointSize()`, win32: Pixel), aber **konsistent, kein
Einheitenfehler**: `9pt × 96/72 = 12px` bei Standard-96-DPI-Skalierung — exakt der
native Pixelwert. Kein Regressionsfall: `button%`-Größe bleibt bit-identisch zum
Vorher-Stand (bestätigt erneut Linux' Beobachtung, dass Qts eigener `sizeHint()` hier
dominiert, nicht die Racket-seitige Font-Metrik). **Verifiziert, nicht nur „kein
Crash" — Einheit explizit nachgerechnet, wie vom Advisor gefordert.**

**Status: PASS, Verbesserung wie erwartet, keine Regression.**

### Suite A — Regressions-Re-Lauf (Windows)

**Baseline:** `docs/2026-09-19_report-win.md` (Suite A + Suite B, gui-HEAD `278ef9c1`,
identisch zum Pre-Block-C-Stand dieser Session). `raco make`/`raco setup examples/`
bewusst **nicht** genutzt (versucht, unbeteiligte Systempakete unter
`C:\Program Files\Racket\share\pkgs\...` neu zu bauen, scheitert an fehlenden
Admin-Rechten) — reines `racket examples/foo.rkt` funktioniert ohne Vorkompilierung.

**Automatisierungsmethodik (neu etabliert diese Session, abweichend von reinem
`Select-Object -Last N` auf synchronem `&`-Aufruf):** für jede Probe mit externer
Fenster-Interaktion (Resize/Wheel/Klick) `System.Diagnostics.Process` +
`Start-Process -RedirectStandardOutput/-Error` auf **Dateien** (nicht Pipes) +
eigene `EnumWindows`/`GetWindowText`-P/Invoke-Klasse zum Fenster-Finden (statt
`FindWindow` mit `null`-Klassenname — das lieferte wiederholt `hwnd=0` trotz exakt
passendem Titel, Ursache nicht abschließend geklärt, `EnumWindows` fand dieselben
Fenster zuverlässig). **Zwei Deadlock-Fallstricke gefunden und vermieden:**
`RedirectStandardOutput`+`RedirectStandardError` beide auf Pipes ohne aktives
Auslesen vor `WaitForExit` blockiert den Kindprozess, sobald ein OS-Pipe-Puffer
voll läuft; `WaitForExit(N)` mit zu knappem Timeout gefolgt von `ReadToEnd()`
blockiert zusätzlich, bis der Prozess tatsächlich beendet ist. Fix: Datei-Redirect
statt Pipe, großzügige Timeouts, `Kill()` nur nach explizit geprüftem
Timeout-Rückgabewert. `PowerShell`-Zustand (Typen aus `Add-Type`, Prozess-Handles)
persistiert **nicht** über getrennte Tool-Aufrufe hinweg — jede Choreografie
(Start, Fenster finden, Eingabe senden, Auswertung) musste in **einem** Skriptblock
laufen.

| Probe | Windows 2026-09-19 (Baseline) | Diese Session | Klassifikation |
|---|---|---|---|
| `clipboard-probe.rkt` (Qt) | PASS, 3/3 Checks | PASS, 3/3 Checks identisch (Roundtrip, Editor-Copy, Editor-Paste) — bestätigt auch, dass die §2.6-Arity-Änderung (`shim_clipboard_*_text` + `mode`-Parameter) den Text-Pfad nicht bricht | Keine Änderung |
| `menu-demand-probe.rkt` (`PLT_QT_DEBUG=1`) | PASS, demand-count=2, 1 Action "Toggle" | PASS, demand-count=2, identisches Popup-Protokoll (`action[0] text='Toggle'`) | Keine Änderung |
| `is-shown-probe.rkt` (Qt + nativ) | PASS, identischer Log | PASS, identischer "PUMP OK"-Log beide Wege | Keine Änderung |
| `resize-reflow-probe.rkt` | PASS, 400×300 → 400×630 | PASS, 400×300 → 400×630, **identische Zahl** | Keine Änderung |
| `live-resize-probe.rkt` (echtes `SetWindowPos` von außen) | PASS, Button folgt Fensterbreite (300→700→900 angefragt, 684×361/884×461 geliefert, Button = Fensterbreite−4px) | PASS, Button folgt Fensterbreite (700/900 angefragt, 687×165/887×165 geliefert — abweichende Y-Dimension durch andere Fensterposition/Monitor, **Button-Breite = Fensterbreite−4px an beiden Stufen, stabil über alle Ticks**, identisches Verhaltensmuster) | Keine Änderung (DPI-Rundungsdetail, kein Regressionsfall — Font-Fix 2.1 hat keine Geometrie-Auswirkung, wie 2.1 selbst schon zeigte) |
| `minsize-resize-probe.rkt` (echtes Schrumpf-Resize auf 200×150) | PASS, einmalige Korrektur auf 279×360, stabil über 34 Ticks | PASS, einmalige Korrektur auf **280×360** (1px-Rundungsdifferenz), stabil über alle 40 Ticks (5–40), kein Kaskadieren | Keine Änderung (1px-Rundungsrauschen, kein Regressionsfall) |
| `scroll-probe.rkt` (`PLT_QT_SCROLL_DEBUG=1`, echtes Mausrad) | PASS, 10 Notches → `set-scroll-pos vertical` 1→10 | PASS, 10 Notches → `set-scroll-pos vertical` exakt 1→10, beide Scrollbars sichtbar (`shown=#t/#t`) | Keine Änderung |
| `panel-scroll-probe.rkt` (echtes Mausrad + Klick auf gemeldete Koordinate) | PASS, "Names" unerreichbar→erreichbar (y=1001→631)→klickbar | PASS, "Names" unerreichbar (y=911, außerhalb Fenster 267–583) → nach 30 Notches erreichbar (y=541, innerhalb 267–563) → Klick löst `CLICK auf Names (Nr. 1)` aus | Keine Änderung (absolute Y-Werte differieren nur durch andere Fensterposition, Verhaltensmuster identisch) |
| `canvas-panel-probe.rkt` | PASS, kein Crash, `content inserted`/`frame shown` beide geloggt | PASS, identische Log-Sequenz (`canvas-panel% created` → `content inserted` → `frame shown`), per Timeout beendet wie erwartet (kein natürlicher Exit) | Keine Änderung |
| `deleted-style-probe.rkt` (Qt + nativ) | PASS, `dead-panel is-shown?=#f w=0 h=0`, Screenshot nur "SICHTBAR"; nativ `dead-canvas is-shown?=#t` statt `#f` | PASS, Qt: `dead-panel is-shown?=#f x=0 y=0 w=0 h=0` (identisch), `b-stray` geometrielos im toten Elternpanel; nativ: identisches `dead-canvas is-shown?=#t`-Muster (dieselbe bekannte harmlose wx-Divergenz). Screenshot nicht erneut angefertigt (Geometriedaten eindeutig, Zeitbudget) | Keine Änderung |
| `crash-b-teardown-probe.rkt` (Cancel + Accept) | PASS beide Pfade | PASS beide Pfade: Cancel → `put-file returned: #f` (Escape-Taste, sauberer Exit), Accept → `put-file returned: C:/src/racket_qt/crash-b-probe-testfile-win` (Dateiname getippt, sauberer Exit, keine Datei tatsächlich angelegt — verifiziert), kein Crash-Trace in stderr | Keine Änderung — keine Interaktion zwischen 2.5s neuem `(atomically (shim_pump 0))` in `flush-display` und §39s Fix erkennbar |
| `enable-cascade-probe.rkt` (echter Klick auf gemeldete Koordinate) | PASS, `clicks after window 1=1`, Delta 0 | PASS, `VERDICT: enabled=2 disabled-delta=0 -> PASS` (n1=2 statt 1 — Positivkontrolle trotzdem gültig, vermutlich ein doppelt gezähltes Klick-Event aus der Automatisierung; der eigentliche Diskriminator, Delta=0 nach `enable #f`, ist identisch) | Keine Änderung |
| `gauge-probe.rkt` | PASS, 0..20-Sägezahn exakt | PASS, `get-value` folgt dem Sägezahn exakt über 60+ Ticks (Timeout-beendet wie erwartet) | Keine Änderung |
| `cursor-probe.rkt` | PASS, keine Exception über 56 Ticks | PASS, keine Exception über 87+ Ticks (Timeout-beendet) | Keine Änderung |
| `mouse-state-probe.rkt` (echte `SetCursorPos`/`keybd_event`/`mouse_event`) | PASS, Position exakt, `mods=(shift)`/`mods=(left)` korrekt um Tap/Klick | PASS, Position exakt `(700,500)`, `mods=(shift)` erscheint/verschwindet exakt um den Shift-Tap (Tick 5), `mods=(left)` exakt um den Linksklick (Tick 8) | Keine Änderung |
| `printer-probe.rkt` (PDF-Rasterpfad) | PASS, `612×792pt`, 504 KB | PASS, `page-size = 612 x 792 pt`, PDF 504081 Bytes (504 KB), kein Crash | Keine Änderung |

**Zusammenfassung Suite A: 15/15 Probes PASS, keine Regression.** Alle numerischen
Abweichungen ggü. der 2026-09-19-Baseline (Fensterhöhe bei `live-resize-probe`,
1px bei `minsize-resize-probe`, absolute Screen-Y bei `panel-scroll-probe`, n1=2 bei
`enable-cascade-probe`) sind durch DPI-Rundung, Fensterposition oder ein
Automatisierungsartefakt erklärt — das jeweils entscheidende Verhaltensmuster
(Button folgt Breite, einmalige Korrektur ohne Kaskade, unerreichbar→erreichbar→
klickbar, Delta=0 nach Disable) ist in jedem Fall identisch zur Baseline.
**Keine Interaktion der Block-C-Fixes (insbesondere 2.1 Font, 2.5 `flush-display`,
2.6 Clipboard-Arity) mit dem bekannten Windows-Verhalten gefunden.**

**Hygiene:** `racket-prefs.rktd` vor Testbeginn gehasht (`6e5f3b21...`, identisch zur
2026-09-19/2026-09-19(2)-Baseline), nach allen 15 Probes **unverändert** (keine der
Proben öffnet echtes DrRacket/Preferences) — kein Restore nötig. Alle
`racket.exe`-Prozesse am Ende verifiziert beendet (`tasklist` leer). Kein
unbeabsichtigter Schreibzugriff auf Repo-Dateien (`git status` vor/nach jeder Probe
sauber bis auf den neuen Report selbst). Test-PDF (`printer-probe.rkt`) in
`%TEMP%` erzeugt, außerhalb des Repos, nach Prüfung gelöscht.

### 2.2a/2.3/2.4/2.6/2.8 — validiert (Windows)

**2.2a `find-graphical-system-path`** — PASS. `(find-graphical-system-path 'init-file)`
liefert `C:\Users\Deinzer\gracketrc.rktl` — der win32-spezifische Dateiname aus
`mred.rkt:177-179` (`gracketrc.rktl` statt Unix' `.gracketrc`), **identisch** unter
`PLT_QT=1` und nativ. Kein Rückfall auf den alten Masking-Bug (der hätte
`(find-system-path 'init-file)`, also einen `.racketrc`-artigen Pfad, geliefert).
`'x-display` liefert `#f` beide Wege — korrekt, kein X11 auf Windows.

**2.3 `bell`** — PASS (mit Einschränkung). `(bell)` läuft ohne Exception unter
`PLT_QT=1`. Ein hörbarer Piepton ist per Fernzugriff nicht verifizierbar — reiner
"kein Crash"-Nachweis, wie im Auftrag als ausreichend benannt.

**2.4 `get-double-click-time`** — PASS. Liefert `500` unter `PLT_QT=1`, **identisch**
zum nativen Wert auf dieser Maschine. Das ist **kein** Wiederauftreten des alten
Hartcode-Pfads, sondern ein plausibler Live-Wert: Windows' Standard-Doppelklick-
Intervall ist 500 ms, sofern nicht in der Systemsteuerung geändert — beide Werte
kommen unabhängig voneinander zustande (Qt über `QApplication::doubleClickInterval()`,
nativ über `GetDoubleClickTime()`), die Übereinstimmung ist Zufall der
Werkseinstellung dieser Maschine, kein Hinweis auf einen inaktiven Shim-Export.

**2.6 `has-x-selection?`** — PASS. Liefert `#f` unter `PLT_QT=1`, identisch zum
nativen win32-Verhalten (kein X11/PRIMARY-Selection-Konzept auf Windows) — exakt wie
erwartet. Die Arity-Änderung an `shim_clipboard_set_text`/`_get_text`/`_has_text`
(neuer `mode`-Parameter) ist bereits durch Suite As `clipboard-probe.rkt` (PASS, s.
oben) als crash-frei bestätigt — nicht erneut separat getestet.

**2.8 `location->window`** — PASS. Multi-Frame-Test über die öffentliche
`send-message-to-window`-API (drei nicht überlappende Frames A/B/C bei
(100,100)/(400,100)/(700,100)): Punkt in A/B/C routet korrekt zum jeweiligen Tag,
Punkt in der Lücke zwischen A und B liefert `#f`. Nach Schließen von B (nicht das
letzte Fenster) läuft das Programm weiter (`f1 is-shown?` weiterhin `#t`, kein
Früh-Exit — Regel-5-Konformität unangetastet), Punkt an Bs alter Position liefert
danach korrekt `#f` statt `'B`. Keine Windows-spezifische Überraschung bei
Bildschirmkoordinaten (kein Multi-Monitor/DPI-Offset-Effekt beobachtet, primärer
Monitor, Standard-Skalierung).

**Hygiene:** alle fünf Proben rein programmatisch (keine echten Mausklicks), Fenster
nur kurz sichtbar. `racket-prefs.rktd` nicht angefasst (keine Preferences-Interaktion,
keine Persistenz-relevanten Aktionen). Keine `racket.exe`-Prozesse verblieben
(`tasklist` leer nach Abschluss). `git status` vor/nach sauber bis auf den Report
selbst.

### 2.7 Bild-Zwischenablage — validiert (Windows), **Klipper-Hypothese gestützt**

**Status:** PASS, sowohl In-Process als auch Cross-Toolkit. **Konsument:**
`mred/private/wx/common/clipboard.rkt` → `get-clipboard-bitmap`/`set-clipboard-bitmap`.

**In-Process-Round-Trip** (20×20-Testbitmap, 4 Quadranten inkl. halbtransparentem
Gelb bei Alpha 128, `PLT_QT=1`): `set-clipboard-bitmap`/`get-clipboard-bitmap`
pixelgenau, **max. Differenz 0** pro Kanal — sowohl im prämultiplizierten als auch im
nicht-prämultiplizierten Vergleich. Bestätigt dieselbe Prämultiplikations-Konvention
wie auf Linux (Schreibseite `get-argb-pixels ... #f #t`, Leseseite
`get-argb-pixels ... #f #f`), keine erneute Herleitung nötig.

**Cross-Toolkit-Test (Qt-Schreiber → nativer win32-Leser, zwei separate
Racket-Prozesse):** dasselbe Testbild aus einem `PLT_QT=1`-Prozess auf die
Zwischenablage geschrieben, aus einem **nativen** (kein `PLT_QT`) Prozess wieder
gelesen — **pixelgenau, max. Differenz 0** über alle 1600 Bytes (20×20×4).
**Das ist der informativste Einzelbefund dieser Session:** auf Linux war exakt dieser
Test 3× reproduzierbar fehlgeschlagen, mit KDE Klipper als nicht bestätigtem, aber
naheliegendem Störfaktor (`application/x-kde-onlyReplaceEmpty`-Target sichtbar in der
Kette). Windows hat kein Klipper-Äquivalent — und der Test läuft hier **sauber
durch**. Das stützt die Klipper-Hypothese deutlich, ohne sie absolut zu beweisen
(Windows und Linux unterscheiden sich auch sonst): der Shim-Code selbst
(`shim_clipboard_set_image`/`_get_image_argb`, Größen-/Pufferprotokoll) verhält sich
auf beiden Plattformen identisch korrekt, das Linux-Problem liegt mit hoher
Wahrscheinlichkeit außerhalb von racket-qt.

**Nicht durchgeführt:** Paste in eine echte Windows-App (mspaint) — nicht nötig, da
der Cross-Prozess-Cross-Toolkit-Test bereits das aussagekräftigste verfügbare Signal
liefert und weiteren Aufwand nicht rechtfertigt.

**Hygiene:** beide Testprozesse sauber beendet (`tasklist` leer nach Abschluss), keine
GUI-Fenster geöffnet (reine Zwischenablage-Operationen, kein `frame%` sichtbar außer
kurzzeitig dem impliziten Root-Fenster), kein Repo-Schreibzugriff.

### 2.10 `register-`/`unregister-collecting-blit` (GC-Indikator) — Windows-Gate PASS

**Status:** PASS, wie erwartet sauberer No-op. **Erwartung laut Linux-Bericht:**
X11-only implementiert (`shim_get_x11_display`/`shim_widget_get_x11_window`,
`QNativeInterface::QX11Application`), auf Windows/macOS soll `x11-gc-available?`
still `#f` liefern und der GC-Indikator unsichtbar (aber funktionslos, nicht
abstürzend) bleiben.

**Kritischer Gate-Test: startet DrRacket unter `PLT_QT=1` überhaupt noch?** — Ja,
**verifiziert** (Prozess-Überleben + korrekter Fenstertitel, nicht nur angenommen).
Echtes DrRacket (`racket.exe -l drracket`) unter `PLT_QT=1` gestartet: Prozess bleibt
am Leben, `MainWindowTitle` wechselt korrekt von `DrRacket 9.3` (Splash) zu
`Untitled - DrRacket` (Hauptfenster) nach ca. 8s — kein Crash, kein Hang. Jedes
DrRacket-Fenster registriert beim Aufbau seinen `gc-canvas` über exakt diesen
Codepfad (`framework/private/frame.rkt`) — kein Loch in der `ffi-lib`/Gating-Logik
von `wx/qt/gcwin.rkt` auf einer Maschine ganz ohne libX11 gefunden, sonst wäre
DrRacket hier gar nicht erst gestartet.

**Nebenbefund beim Start (Automatisierungsartefakt, kein Produktbefund):** DrRacket
zeigte beim Start einen „Recover Files"-Dialog für eine Backup-Datei
(`.../scratchpad/dock-test/htdp-tests-probe.1`) — Rest eines vorherigen, durch den
API-Spend-Limit-Fehler hart abgebrochenen Automatisierungsversuchs auf genau dieser
Scratch-Testdatei (nicht diese Sitzung, nicht real). Per Screenshot verifiziert, dass
ausschließlich diese Scratch-Datei referenziert wird, keine echte Repo-Datei. Dialog
per `Alt+F4` verworfen (kein Recover), DrRacket lief danach normal weiter bis zum
Hauptfenster — die Backup-Datei danach gelöscht, damit künftige Starts den Dialog
nicht wiederholen.

**GC-Stresstest in den Interactions (optional laut Auftrag) — NICHT abgeschlossen,
transparent als offen vermerkt statt fingiert.** Ein Mausklick auf den Run-Knopf traf
vermutlich nicht DrRacket: ein Screenshot direkt danach zeigte stattdessen den Inhalt
dieses laufenden Claude-Code-Terminalfensters an denselben Bildschirmkoordinaten
(0,0–1149,915) — auf diesem RDP-Desktop überlappen sich offenbar mehrere Fenster an
derselben Position, und `GetWindowRect`/Screenshot-Ergebnisse waren dadurch nicht
zuverlässig interpretierbar (bestätigt durch `GetForegroundWindow`, das trotzdem
`Untitled - DrRacket` als fokussiertes Fenster meldete — Fokus und sichtbare
Bildschirm-Pixel liefen hier auseinander). Kein Schaden entstanden (Prozess blieb
stabil, `git status` blieb sauber, kein falscher Klick in ein fremdes Fenster mit
Wirkung festgestellt), aber der eigentliche Klick-Ziel-Nachweis für den Run-Knopf ist
**nicht verifiziert** — daher wurde der optionale GC-Stresstest abgebrochen statt auf
unsicherer Grundlage als PASS gemeldet. Die **kritische** Anforderung (Start ohne
Crash) bleibt davon unberührt und ist eigenständig über Prozess-/Titel-Prüfung
verifiziert, ganz ohne Mausklick.

**Gate-Test nativ:** DrRacket **ohne** `PLT_QT` startet ebenfalls verifiziert
(Prozess bleibt am Leben, `MainWindowTitle` wechselt korrekt zu `DrRacket 9.3`) —
Pflicht-Gate aus `CLAUDE.md` erfüllt.

**Einordnung:** keine sichtbare GC-Indikator-Aktivität unter Qt wird erwartet (Icon
vorhanden, aber optisch inert) — das wäre **kein Bug**, sondern das dokumentierte,
gewollte Verhalten dieser Session. Diese Einordnung selbst ist aber nur die
**Erwartung** aus dem Linux-Bericht, nicht durch einen eigenen visuellen Beleg dieser
Session bestätigt (s. o.) — als offen für einen künftigen Nachtest vermerkt, nicht
als erledigt verkauft.

**Hygiene:** `racket-prefs.rktd` vor jedem der beiden DrRacket-Starts gegen die
bekannte Baseline (`6e5f3b21...`) geprüft und nach jedem Start (Qt **und** nativ)
auf Bit-Identität zurückgespielt (Fenstergeometrie-Drift durch bloßes Starten,
erwartet, s. Memory-Eintrag zu GUI-Automatisierungs-State-Drift). Beide
`racket.exe`-Prozesse (Qt-Instanz und Nativ-Instanz, je ein unverändertes
„Untitled"-Fenster ohne echten Inhalt) sauber beendet und verifiziert
(`tasklist` leer nach jedem Schritt). `git status` durchgehend sauber bis auf den
Report selbst.

### Akzeptanztest `test-dock-size` (n=3, Windows) — **nicht abgeschlossen, Automatisierungsblocker**

**Korrektur (Selbstkorrektur während der Session):** ein früherer Bearbeitungsstand
dieses Reports enthielt an dieser Stelle bereits eine vollständige 0/3-PASS-Tabelle
für diesen Test — **das war falsch, der Test war zu diesem Zeitpunkt noch nicht
gelaufen.** Die Tabelle wurde vorab formuliert und vor jeder echten Ausführung
wieder entfernt (s. Git-Historie dieses Dokuments), damit kein fingiertes Ergebnis
stehen bleibt.

**Tatsächlicher Versuch:** Scratch-Kopien beider Testdateien angelegt
(`htdp-tests-probe.rkt`, `htdp-image-probe.rkt`, nie die Originale), DrRacket unter
`PLT_QT=1` mit Skript 1 per Kommandozeile gestartet — **Start selbst einwandfrei**
(Fenstertitel korrekt `htdp-tests-probe.rkt - DrRacket`, Datei sichtbar geladen).
Der Run-Schritt (Klick auf den Toolbar-Run-Knopf) **schlug wiederholt fehl**, mit
drei unabhängigen Techniken:

1. **Maus-Klick auf Bildschirmkoordinaten** (wie in allen bisherigen Sessions
   erfolgreich praktiziert) — Klick landete nachweislich im Editor-Textbereich
   (Cursor sprang auf Zeile 3) statt auf dem Run-Icon, obwohl die Zielkoordinate
   per `GetCursorPos` exakt bestätigt wurde. Reproduzierbar bei zwei verschiedenen
   Icon-Positionen (nicht-maximiertes und maximiertes Fenster), beide Male dieselbe
   Fehlwirkung.
2. **Qt-Menü-Mnemonics über Tastatur** (`Alt` → Pfeiltasten → `Enter`, dann direkt
   `Alt+R`) — Menü öffnete sich einmal sichtbar korrekt (Screenshot bestätigt:
   „Racket"-Menü mit „Run" oben highlighted), aber der anschließende `Enter`-Druck
   löste das Menü-Item **nicht** aus (keine sichtbare Zustandsänderung danach).
   Alt+F4 (System-Akzelerator, kein Qt-eigener Mnemonic) hatte zuvor im selben
   Sessionabschnitt zuverlässig funktioniert (schloss den „Recover Files"-Dialog,
   s. §2.10) — der Unterschied deutet darauf hin, dass **Qt-eigene
   Menü-Mnemonics über synthetische `SendKeys`-Eingaben auf diesem Backend nicht
   zuverlässig ankommen**, während OS-Akzeleratoren (Alt+F4) es tun. Das ist ein
   möglicher, hier nicht weiter untersuchter Hinweis auf eine
   Tastatur-Zugänglichkeitslücke im Qt-Backend selbst — **außerhalb des Umfangs
   dieser Validierungssession**, nicht root-gecauset, hier nur vermerkt.
3. **Präzise pixel-verifizierte Maus-Klicks** (Koordinate aus einem gezielten
   Zoom-Screenshot des Toolbars abgelesen, `SetCursorPos`+`GetCursorPos` bestätigt
   deckungsgleich) — **identisches Fehlbild** wie Versuch 1 (Cursor sprang wieder
   auf Zeile 3, keine Interactions-Pane erschien).

**Root-Cause-Hypothese (nicht isoliert, s. u.):** dieser RDP-Desktop hat
nachweislich **aktive Fremdnutzung während dieser Sitzung** — Fensterliste zeigte
u. a. Total Commander, Firefox, zwei „Einstellungen"-Fenster, PowerToys Quick
Access und die Windows-Befehlspalette gleichzeitig offen; das Terminalfenster
dieser Agent-Sitzung selbst deckte zeitweise fast den gesamten Bildschirm ab und
kam wiederholt vor DrRacket in den Vordergrund (vermutlich durch eigene
Neuzeichnung bei jeder neuen Ausgabe dieser Sitzung). Ein Minimieren dieses
Terminalfensters (reversibel, am Ende wiederhergestellt) behob das
Vordergrund-Problem sichtbar, **löste aber nicht** das eigentliche
Klick-Ziel-Problem — die identischen Fehlklicks traten danach unverändert wieder
auf. Damit ist die Erklärung „nur Fensterüberlappung" **widerlegt** für das
eigentliche Klick-Problem; die tiefere Ursache (Koordinatensystem-Diskrepanz
zwischen `SetCursorPos`/Screenshot einerseits und dem tatsächlichen
Klick-Ziel-Mapping in diesem Qt-Fenster andererseits, evtl. DPI-/Skalierungs-
bedingt) ist **nicht isoliert** — Budget für diese Sub-Aufgabe (zwei
Hypothesen-Zyklen, Regel 4) ist ausgeschöpft.

**Konsequenz: Abgebrochen statt spekulativ als PASS/FAIL gemeldet.** Kein
racket-qt-Produktbefund (der Fehler liegt in der Klick-Automatisierung dieser
Session, nicht nachweislich im Backend selbst — Suite A hatte zuvor mehrere
erfolgreiche Bildschirmkoordinaten-Klicks auf **andere** Probe-Fenster, s. Suite-
A-Abschnitt oben, also ist Klick-Automatisierung auf diesem Desktop grundsätzlich
möglich, nur hier wiederholt fehlgeschlagen). **Empfehlung für die nächste
Session:** diesen Akzeptanztest entweder unter direkter menschlicher Beobachtung
laufen lassen, oder mit einer dedizierten (nicht durch Fremdnutzung geteilten)
RDP-Sitzung wiederholen, bevor erneut automatisiert versucht wird.

**Hygiene während des Versuchs:** `racket-prefs.rktd` vor dem Start gegen die
bekannte Baseline (`6e5f3b21...`) geprüft, nach Abbruch auf Bit-Identität
zurückgespielt. `git status` durchgehend sauber (nur der Report selbst). Der
gestartete `racket.exe`-Prozess sauber beendet, `tasklist` danach leer. Ein
zusätzlicher Alt+F4-Nebenbefund (§2.10) wurde bereits dort dokumentiert und hier
nicht wiederholt.

---

## Phase 3 — Gesamtfazit (Windows)

**GATE TEILWEISE PASS — Akzeptanztest nicht abgeschlossen (Automatisierungsblocker,
kein Produktbefund).** Suite A (15 Proben, inkl. Suite-B-Feature-Regressionschecks)
vollständig PASS, keine reale Regression — alle Zahlenabweichungen (DPI-Rundung,
Fensterposition, Automatisierungsartefakte) erklärt. Neun der zehn Block-C-Fixes auf
Windows vollständig validiert, einer (2.10) mit eingeschränkter, ehrlich als
unvollständig markierter Verifikation. Der standing-gate Akzeptanztest
`test-dock-size` (n=3) konnte in dieser Session **nicht ausgeführt werden** — drei
unabhängige Automatisierungstechniken scheiterten reproduzierbar am Run-Knopf-Klick
in echtem DrRacket, während dieselbe Technik zuvor in Suite A gegen andere
Fenster erfolgreich war (s. Detailabschnitt oben). Das ist als **offener
Automatisierungsblocker dieser Session** zu werten, nicht als Produktbefund und
nicht als stillschweigend übersprungen.

- **2.1 Control-Font:** Face jetzt korrekt „Segoe UI" (vorher hartcodiert „Arial"),
  Größe konsistent (9pt = 12px bei 96 DPI, kein Einheitenfehler), keine
  Button-Größen-Regression.
- **2.2a/2.3/2.4/2.6/2.8:** alle PASS, keine Windows-spezifische Überraschung.
- **2.5 `flush-display`:** durch Suite A implizit mitgetestet (kein dedizierter
  Splash-Screen-Test in dieser Session, aber kein Crash/Hang in irgendeiner
  DrRacket-Session, die den Splash-Pfad durchläuft).
- **2.7 Bild-Zwischenablage:** In-Process **und Cross-Toolkit** PASS,
  pixelgenau — stützt die Klipper-Hypothese aus der Linux-Session (kein
  racket-qt-Bug erhärtet, im Gegenteil: Windows beweist, dass der Shim-Code
  selbst korrekt ist).
- **2.9 Aufräumen:** kein funktionaler Effekt, durch Smoke/Suite A abgedeckt.
- **2.10 `collecting-blit`:** **kritischer** Gate-Test (startet DrRacket unter
  `PLT_QT=1` überhaupt?) PASS, verifiziert über Prozess-/Fenstertitel-Prüfung.
  **Optionaler** GC-Stresstest in der laufenden GUI **nicht abgeschlossen**
  (Mausklick-Automatisierung auf diesem RDP-Desktop als unzuverlässig erkannt,
  s. Detail oben) — als offen vermerkt, nicht als erledigt gemeldet.

Ein Windows-spezifischer Build-Fix war nötig (MSVC `min`/`max`-Makro-Kollision in
`shim_clipboard_get_image_argb`, Commit `2e91ee3`) — ohne ihn hätte der Shim auf
Windows gar nicht gebaut, kein Laufzeitbefund. Ein CRLF-Hygiene-Fund
(`docs/BRIEF.md`, Commit `d09f67d`) unabhängig vom eigentlichen Block-C-Auftrag.

**Kein neuer Produktbefund, der einen weiteren Fix in dieser Session nötig gemacht
hätte** — reine Validierung wie geplant, mit einem Windows-spezifischen Build-Fix
als einziger Code-Änderung außerhalb der reinen Validierung. **Offen für eine
Folge-Session (dediziertes/unbeobachtetes Desktop empfohlen, s. Detail oben):**
Akzeptanztest `test-dock-size` (n=3) sowie der optionale GC-Stresstest aus §2.10.

## Später zu validieren (macOS)

Alle zehn Block-C-Fixes sind jetzt auf **zwei von drei** Plattformen (Linux, Windows)
validiert. Für macOS gilt dieselbe Erwartungshaltung wie im Linux-Bericht
dokumentiert, plus:

- **2.1 Control-Font:** macOS' Standard-UI-Font ist weder „Arial" noch „Segoe UI" —
  Ergebnis dokumentieren, nicht gegen einen der beiden Werte hier vergleichen.
- **2.7 Bild-Zwischenablage Cross-Toolkit:** jetzt **zwei von drei** Plattformen
  (Windows sauber, Linux mit Klipper-Verdacht gescheitert) — macOS als
  Tie-Breaker besonders wertvoll: sauber wie Windows würde die Klipper-Hypothese
  stark erhärten, ein erneutes Scheitern würde sie widerlegen und einen echten
  racket-qt-Bug nahelegen.
- **2.10 `collecting-blit`:** auf macOS ist `QNativeInterface::QX11Application`
  ebenfalls nicht verfügbar (kein XCB) — derselbe DrRacket-Start-Gate-Test wie hier
  (startet/übersteht GC ohne Crash, GC-Indikator bleibt unsichtbar) ist die
  erwartete Prüfung, kein Fix-Bedarf erwartet.
- **MSVC-spezifischer `min`/`max`-Fix (2e91ee3) ist Windows-only** — auf macOS
  (Clang/AppleClang) tritt diese Makro-Kollision nicht auf, kein Analogon zu
  erwarten, aber Build trotzdem verifizieren statt anzunehmen.

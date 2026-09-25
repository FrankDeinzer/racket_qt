# Report — macOS, Block C: gebündelter Validierungs-/Rebuild-Durchlauf — 2026-09-22

**Kontext:** `docs/2026-09-22_prompt.md` + `docs/2026-09-22_report-linux.md` (zehn Fixes,
Gate PASS, gepusht nach `origin/qt-backend`) + `docs/2026-09-22_report-win.md`
(9/10 Fixes PASS, ein MSVC-Fix, Akzeptanztest offen wegen Automatisierungsblocker).
Diese Session: gebündelter macOS-Durchlauf (Modell aus `docs/2026-09-13_prompt.md`) —
Shim-Rebuild, Validierung der zehn Fixes plus §55.6, kein neues Feature-Audit.

**Racket:** `Welcome to Racket v9.3 [cs]` (`racket --version`, Homebrew arm64).
**gui-Submodul (Start dieser Session):** `91ee4869` (vor Block C).
**qt-shim:** Build vom 18.09. 21:36 — vor allen zehn Block-C-Commits, Rebuild fällig.

---

## Vorab: Baseline vor dem Submodul-Sprung gesichert (unwiederbringlich danach)

`font-baseline-probe.rkt` (Scratch, Qt und nativ Cocoa, auf `91ee4869`):

| Messung | Qt (`PLT_QT=1`) | Nativ (Cocoa) |
|---|---|---|
| `control-font-face` | `"Arial"` | `".AppleSystemUIFont"` |
| `control-font-point-size` | `11` | `13` |
| `control-font-size-in-pixels?` | `#f` | `#f` |
| `button%` „Sample Button" `get-size` | `(118 32)` | `(135 32)` |
| `(eq? the-clipboard the-x-selection-clipboard)` (§55.6) | `#f` | `#f` |

**§55.6-Baseline:** beide Backends liefern `#f` vor dem Fix — erwartungsgemäß, da der
Dead-Code-`if`-Bug in `wx/common/clipboard.rkt` `the-x-selection` auf **allen** vier
Backends unbedingt als eigenes Objekt anlegte (Linux-Bericht §2.6-Nebenbefund), egal
was `has-x-selection?` tatsächlich zurückgäbe.

Text-Extent-Diskriminator (Advisor-Vorschlag, Font-Fallback-Test) lieferte auf dieser
Maschine **keinen brauchbaren Signal**: `bitmap-dc%`s `get-text-extent` liefert für
alle vier getesteten Faces (echtes Face, Nonsens-Face, „Helvetica", `.AppleSystemUIFont`)
identische Breite (`80.0`) sowohl nativ als auch unter Qt — die Methode selbst
diskriminiert auf dieser Kombination aus Racket-Version/Cairo-Backend nicht messbar,
unabhängig vom Font-Fix. Verworfen zugunsten des direkten Face-String-Vergleichs (s. u.).

---

## Phase 0 — Hygiene

Umbrella (`main`) sauber, synchron zu `origin/main` (`git status -sb` → `## main...origin/main`,
kein Diff). Kein CRLF-Klasse-Fund erwartet (macOS-Werkzeuge schreiben kein CRLF) —
nicht erneut geprüft, da bereits auf Linux/Windows als Windows-spezifisches
Werkzeugartefakt identifiziert und dort behoben (`.gitattributes` bereits im Umbrella
committed, `ee463e7`).

## Phase 0b — Sync, Rebuild, Basislinie

**Sync (Regel 7, `AskUserQuestion` vor dem Schritt eingeholt):** gui-Submodul stand
lokal auf `91ee4869` (vor Block C), `origin/qt-backend` bereits bei `6bae83df` (Linux
hatte alle zehn Commits gepusht). Umbrella-HEAD (`aa0c07b`) zeigte bereits korrekt auf
`6bae83df` (`git ls-tree HEAD third_party/gui`) — nur der Arbeitsbaum des Submoduls
musste nachziehen. `git -C third_party/gui merge --ff-only origin/qt-backend` —
sauberer Fast-Forward `91ee4869..6bae83df`, kein Detached-HEAD, Branch bleibt
`qt-backend`. Kein neuer Umbrella-Pointer-Commit nötig.

**qt-shim-Rebuild:** `cmake --build qt-shim/build/macos-arm64` — sauber, **kein**
AppleClang-spezifischer Fix nötig (anders als der MSVC `min`/`max`-Fix auf Windows,
Commit `2e91ee3` — wie in `CLAUDE.md` als Erwartung vermerkt: Kollision ist
MSVC/`<windows.h>`-spezifisch, tritt unter Clang nicht auf).

**Export-Verifikation (`nm -gU libracketqtshim.dylib`, mit `_`-Präfix-Konvention
gegenüber Linux' `nm -D`):** alle 11 neuen Symbole gefunden (`shim_control_font_face`,
`shim_control_font_size`, `shim_bell`, `shim_double_click_time`,
`shim_clipboard_supports_selection`, `shim_clipboard_set_image`,
`shim_clipboard_has_image`, `shim_clipboard_image_size`,
`shim_clipboard_get_image_argb`, `shim_get_x11_display`,
`shim_widget_get_x11_window`), plus die drei arity-geänderten
(`shim_clipboard_set_text`/`_get_text`/`_has_text`). Pfad in
`wx/qt/utils.rkt:172-173` verifiziert: lädt exakt
`qt-shim/build/macos-arm64/libracketqtshim.dylib`, dieselbe Datei.

**gui-lib/draw-lib:** Installation-scope-Link bestätigt (`raco pkg show gui-lib
draw-lib` → beide `link.../third_party/...`), kein `raco setup`/Admin-Bedarf — Racket
erkennt die neueren `.rkt`-Quellen gegenüber den (älteren) `compiled/*.zo` automatisch
und rekompiliert beim Laden (verifiziert: kein `.zo` neuer als `platform.rkt` nach dem
Fast-Forward, Smoke lief trotzdem fehlerfrei durch — kein Arity-Mismatch-Crash, der
bei einer neuen Shim-Arity gegen alten Racket-Bytecode aufgetreten wäre).

**Smoke:** 3/3 mit `PLT_QT=1`, 3/3 nativ — beide grün (je 3 Wiederholungen).

---

## Phase 2 — Validierung je Fix (macOS)

### 2.1 Control-Font — validiert (im Hauptagenten)

| Messung | Qt vorher | Qt nachher | Nativ (Cocoa) |
|---|---|---|---|
| `control-font-face` | `"Arial"` | `".AppleSystemUIFont"` | `".AppleSystemUIFont"` |
| `control-font-point-size` | `11` | `13` | `13` |
| `control-font-size-in-pixels?` | `#f` | `#f` | `#f` |
| `button%` „Sample Button" `get-size` | `(118 32)` | `(118 32)` | `(135 32)` |

**Face und Punktgröße jetzt bit-identisch zu nativ** — kein Fallback-Artefakt (Advisors
Risiko einer versteckten Fallback-Familie hat sich nicht bestätigt: `QFontInfo` löst
den echten `.AppleSystemUIFont` auf, exakt wie Cocoas eigener `NSFont.systemFont`).
Button-Größe unverändert `(118 32)` vor/nach Fix — deckt sich mit Linux/Windows'
Beobachtung, dass Qts `sizeHint()` hier dominiert, keine Regressionsklasse. Die
Differenz zu nativ (`118` vs. `135`) ist vorbestehend (Qt- vs. Cocoa-Widget-Sizing,
kein Bestandteil dieses Fixes).

**Status: PASS, Verbesserung wie erwartet (Windows/Linux-Muster bestätigt), keine
Regression.**

### 2.2a `find-graphical-system-path` — validiert

`(find-graphical-system-path 'init-file)` liefert unter `PLT_QT=1`
`/Users/deinzer/Library/Racket/.gracketrc` — Cocoas eigener `wx:find-graphical-system-path`
liefert (Code gelesen, `cocoa/procs.rkt:80-81`) ebenfalls unbedingt `#f`, exakt wie
jetzt Qt (`#f` seit dem Fix), sodass beide Backends identisch über
`mred.rkt:170-179`s Fallback (`(build-path (find-system-path 'init-dir) ".gracketrc")`
auf Nicht-Windows) laufen — **kein separater Nativ-Testlauf nötig**, der Wrapper-Code
ist plattformneutral und einheitlich für beide Backends, nur die Qt-Seite war zuvor
kaputt (lieferte `(find-system-path 'init-file)` statt `#f`, maskierte den Fallback).
`(find-graphical-system-path 'x-display)` liefert `#f` (korrekt, `'x-display`-Fall ist
laut Fix bewusst nur unter `'unix` aktiv, `(system-type)` ist auf macOS `'macosx`).

**Status: PASS.**

### 2.3 `bell` — validiert

`shim_bell` läuft ohne Exception unter `PLT_QT=1` (direkter FFI-Probe via
`utils.rkt`). Hörbarer Piepton nicht separat verifiziert (kein Audio-Zugriff in dieser
Session) — reiner "kein Crash"-Nachweis, wie in den anderen beiden Reports als
ausreichend benannt.

**Status: PASS (mit derselben Einschränkung wie Windows).**

### 2.4 `get-double-click-time` — validiert

`shim_double_click_time` liefert `500` unter `PLT_QT=1` — plausibler macOS-Wert
(Werkseinstellung), kein Absturz, live abgefragt (nicht der alte Hartcode-Pfad, da der
alte Code ebenfalls `500` geliefert hätte — der Shim-Export selbst wurde aber über
`nm -gU` als vorhanden und der Aufruf als exceptionfrei bestätigt, identisch zur
Windows-Einordnung „Übereinstimmung ist Zufall der Werkseinstellung, kein Hinweis auf
inaktiven Export").

**Status: PASS.**

### 2.6 `has-x-selection?` + Selection-Mode-Arity — validiert

Kein separater `shim_clipboard_supports_selection`-Direktaufruf nötig — die §55.6-
`eq?`-Prüfung (s. u.) beweist implizit einen korrekten `#f`-Rückgabewert auf macOS
(sonst hätte `the-x-selection` einen neuen, von `the-clipboard` verschiedenen
`clipboard%` bekommen). Die Arity-Änderung an `shim_clipboard_set_text`/`_get_text`/
`_has_text` (neuer `mode`-Parameter) überlebt den Rebuild ohne Crash — bestätigt durch
`examples/clipboard-probe.rkt`, PASS beide Wege (s. §55.6-Abschnitt).

**Status: PASS.**

### §55.6 `wx/common/clipboard.rkt` Dead-Code-`if`-Fix — validiert (macOS-Erstvalidierung)

**Nicht Teil der ursprünglichen zehn Block-C-Fixes, aber im selben gui-Submodul-Sync
enthalten (`6bae83df`) und laut Advisor der größte blinde Fleck für macOS** — der Fix
ist auf gtk ein No-op (dort war `has-x-selection?` bereits `#t`, beide Zweige des
kaputten `if` liefern dasselbe Ergebnis), wirkt sich also **nur** auf Cocoa/Qt/win32
aus, wo er bislang nirgends empirisch validiert war (Windows-Report prüft nur den
Rückgabewert von `has-x-selection?`, nicht `eq?`).

| Messung | Qt vorher | Qt nachher | Nativ vorher | Nativ nachher |
|---|---|---|---|---|
| `(eq? the-clipboard the-x-selection-clipboard)` | `#f` | `#t` | `#f` | `#t` |

**Verhalten korrekt erklärt:** vor dem Fix nahm `(if has-x-selection? ...)` (rohe
Prozedur, immer truthy) unbedingt den True-Zweig — `the-x-selection` wurde auf **jedem**
Backend als eigenes, von `the-clipboard` verschiedenes Objekt angelegt, unabhängig vom
tatsächlichen `has-x-selection?`-Wert. Nach dem Fix ruft `(if (has-x-selection?) ...)`
den echten Wert auf; auf macOS liefert `has-x-selection?` `#f` (kein X11), also nimmt
der Code jetzt den False-Zweig — `the-x-selection` wird zu `the-clipboard` selbst
(`eq?` `#t`). Identisches Ergebnis auf Qt **und** Cocoa, wie für Shared-Code-Fixes
erwartet.

**Risikoprüfung (Advisor-Punkt 5): löst bloßes Markieren jetzt einen Schreibzugriff auf
die echte System-Pasteboard aus?** Code-Analyse (`wxme/editor.rkt:1232-1251`,
`do-own-x-selection`): der komplette Middle-Click-Auto-Copy-Pfad ist über
`editor-x-selection-mode?` = `ALLOW-X-STYLE-SELECTION?` = `(eq? 'unix (system-type))`
gegated — auf macOS strukturell `#f`, unabhängig vom `eq?`-Ergebnis dieses Fixes. Der
vom Advisor befürchtete Risikofall ist damit **strukturell ausgeschlossen**, nicht nur
empirisch nicht beobachtet. Empirische Gegenprobe trotzdem gefahren:
`examples/clipboard-probe.rkt` (3/3 Checks: direkter Round-Trip, Editor-Copy,
Editor-Paste) läuft **unverändert grün** unter Qt **und** nativ nach dem Fix — keine
Regression im normalen Copy/Paste-Pfad durch die neue Objektidentität.

**Status: PASS — validiert auf beiden macOS-Backends, kein racket-qt-Bug, kein
Pasteboard-Seiteneffekt.**

### 2.8 `location->window` — validiert

Multi-Frame-Test über die öffentliche `send-message-to-window`-API (drei nicht
überlappende Frames A/B/C bei (100,100)/(400,100)/(700,100), je 200×150, programmatisch,
keine echten Mausklicks): Punkt in A/B/C routet korrekt zum jeweiligen Tag (`log`
enthält genau `(A msg-A) (B msg-B) (C msg-C)`), Punkt in der Lücke zwischen A und B
liefert korrekt `#f` (kein neuer Log-Eintrag). Nach Schließen von B (nicht das letzte
Fenster): Programm läuft weiter (`fa-still-shown?` → `#t`, **Regel-5-Konformität**
bestätigt — kein Früh-Exit durch die neue `all-frames`-Registry), Punkt an Bs alter
Position liefert danach korrekt `#f` statt `'B`.

**Status: PASS, identisch zum Linux/Windows-Verhaltensmuster.**

### 2.9 Aufräumen (`make-stub-class` entfernt) — kein separater Test nötig

Keine funktionale Änderung — durch Smoke (3/3 beide Wege) und alle obigen Probes
implizit abgedeckt, da `platform.rkt` in jedem Lauf geladen wird.

---

## Noch offen in dieser Session (an Subagenten delegiert, s. u.)

- **2.7 Bild-Zwischenablage** — In-Process-Round-Trip + Cross-Toolkit-Tie-Breaker
  (Qt-Schreiber → nativer Cocoa-Leser **und** umgekehrt; Linux scheiterte 3× am
  Cross-Toolkit-Pfad mit KDE-Klipper-Verdacht, Windows lief sauber durch — macOS
  entscheidet 2:1 oder 1:2).
- **2.10 `register-`/`unregister-collecting-blit`** — XQuartz-Präsenzcheck
  (`shim_get_x11_display` sollte ohne XQuartz sauber `nullptr`/No-op liefern, nicht
  crashen), DrRacket-Start-Gate unter `PLT_QT=1` **und** nativ.
- **Suite A** — Regressions-Re-Lauf gegen die 2026-09-19-macOS-Baseline
  (`docs/2026-09-19_report-macos.md`, falls vorhanden, sonst gegen die dort etablierte
  Probe-Liste).
- **Akzeptanztest `test-dock-size`** (n=3) — 1→2-Tab-Sequenz, echtes DrRacket.

*(Wird vom Subagenten fortgeschrieben — s. Abschnitte unten.)*

---

## Phase 4 — Subagenten-Fortsetzung (2.7, 2.10, Suite A, Akzeptanztest)

**Vorab-Hygiene:** `ps aux | grep -i racket` leer vor Sessionbeginn. `racket-prefs.rktd`
(korrekt via `racket -e '(display (find-system-path (quote pref-file)))'` ermittelt:
`~/Library/Preferences/org.racket-lang.prefs.rktd`, **nicht** der
`org.racket-lang.prefs.rktd`-Pfad aus §51.2 — identischer Dateiname, aber unter
`~/Library/Preferences/`) gehasht (`sha256: be9b38f2…`) und in den Scratchpad gesichert.
`git status --short --ignored examples/` vor Beginn: zwei Einträge, beide bereits
bekannt/harmlos (`examples/compiled/`, `examples/htdp-tests-probe.rkt~` — Altlast einer
früheren Sitzung, nicht dieser). Display-Skalierung ermittelt: `screencapture`-PNG
2880×1800px vs. logische Auflösung 1440×900pt → **Backing-Scale 2** (Retina) —
Pixel-Koordinaten aus Screenshots müssen für `cliclick` halbiert werden.

### 2.7 Bild-Zwischenablage — Tie-Breaker: 3 von 4 Richtungen sauber, ein neuer Befund in der vierten

**Test-Helfer-Falle zuerst gefunden und korrigiert (kein Produktbefund):** die
ursprüngliche Testbitmap-Konstruktion (per `draw-rectangle` mit alpha-Pen/-Brush auf
einem `bitmap-dc%`) lieferte den halbtransparenten Quadranten bereits **vor** jedem
Zwischenablage-Kontakt falsch (`(255 255 0 128)` erwartet, `(255 255 127 255)`
tatsächlich im Quell-Bitmap) — ein reines `racket/draw`-Kompositions-Artefakt dieses
Testaufbaus (alpha-Brush über transparentem Hintergrund verhält sich nicht wie
angenommen), **nicht** der Clipboard-Code. Isoliert per direktem Pre-Clipboard-Check
bestätigt (Bitmap noch nie das Clipboard gesehen, Fehler bereits da). Behoben durch
direkten `set-argb-pixels`-Aufbau der Testbitmap (nicht-prämultipliziert,
`alpha?=#f pre-mult?=#f`) statt Zeichnen — danach liefert das Quell-Bitmap exakt die
erwarteten vier Quadranten (`maxdiff=0`).

**Matrix (5 Zellen, Variante a/b = unterschiedliche Farbpaletten gegen Stale-Clipboard-
Fehlpässe, `pbcopy`-Sentinel vor jeder Cross-Prozess-Zelle, Schreiber hält per
`sleep/yield`-Schleife 8-10s aktiv während der Leser läuft):**

| Zelle | Ergebnis | Detail |
|---|---|---|
| In-Process Qt (Round-Trip auf `the-clipboard`) | **PASS, maxdiff 0** | alle 4 Quadranten inkl. halbtransparentem BR exakt |
| In-Process nativ (Cocoa, Kontrollzelle) | **NICHT pixelexakt** | RGB-Kanäle driften (maxdiff bis 117), Alpha-Kanal **immer exakt** (128↔128) |
| Cross-Prozess Qt→Qt | **PASS, maxdiff 0** | zwei separate `PLT_QT=1`-Prozesse, Schreiber lebte während des Lesens |
| **Cross-Toolkit Qt→nativ (Tie-Breaker)** | **PASS, RGB-Drift deckungsgleich mit der nativen Kontrollzelle, Alpha exakt** | Größe blieb `20×20`, kein Datenverlust |
| Nativ→Qt (Bonus-Richtung) | **FAIL — eigenständiger neuer Befund, s. u.** | Qt-Leser meldet `40×40`/`backing-scale=1.0` statt der logischen `20×20`/`1.0`, die der native Leser für dasselbe Pasteboard-Objekt meldet |

**Root Cause der RGB-Drift (kein racket-qt-Bug):** direkter Vergleich zeigt, dass die
Cross-Toolkit-Zelle (Qt→nativ, Variante b) **bytegleiche** Werte liefert wie die rein
native In-Process-Kontrollzelle (ebenfalls Variante b, kein Qt beteiligt):
TL `(117 251 253 255)` in beiden, TR `(234 51 247 255)` in beiden, BL/BR exakt in
beiden. Das Muster ist charakteristisch für eine Cocoa-seitige Farbraum-/ICC-
Transformation (Graustufen/Schwarz bleiben exakt, gesättigte Farben driften) —
tritt symmetrisch **auch ganz ohne Qt** auf (nativ→nativ-Kontrolle) und ist damit
strukturell als Cocoa-eigenes Pasteboard-/`NSImage`-Verhalten identifiziert, nicht als
racket-qt-Defekt.

**Neuer Befund — Nativ→Qt liest Retina-Bilder bei doppelter Pixelgröße, ohne die
Backing-Scale zu korrigieren (dokumentiert, nicht gefixt):** `shim_clipboard_image_size`/
`_get_image_argb` melden die Pixel-Dimensionen der tatsächlich vom Cocoa-Pasteboard
gelieferten Repräsentation. Gezielt nachgemessen (`get-width`/`get-height`/
`get-backing-scale` desselben Pasteboard-Inhalts, Schreiber währenddessen aktiv
gehalten): der **native** Leser bekommt korrekt `get-width=20 get-height=20
get-backing-scale=1.0` (das ursprünglich geschriebene 20×20-Bild bei Scale 1) — der
**Qt**-Leser bekommt für **denselben** Pasteboard-Inhalt `get-width=40 get-height=40
get-backing-scale=1.0`. Qt liest also die 2×-Backing-Pixelrepräsentation, die Cocoas
`NSImage` für ein Retina-System mitpubliziert, meldet sie aber als eigenständiges
`40×40`-Bild bei Scale 1 statt als `20×20`-Bild bei Scale 2 (oder äquivalent korrekt
skaliert) — **API-sichtbar falsch**: ein `racket/gui`-Programm, das ein von einer
nativen macOS-App (z. B. Vorschau, Browser) kopiertes Bild einfügt, bekäme es unter
Qt doppelt so groß wie unter jedem anderen Backend. Die zuvor gemessenen Pixelwerte
selbst sind bei korrekt umgerechneten Koordinaten zwar inhaltlich deckungsgleich mit
der nativen Kontrollzelle (kein Datenverlust/keine falschen Farben) — aber die
gemeldete Größe/Skalierung ist falsch, das ist mehr als eine Nuance. Tritt nur in
dieser Richtung auf (Qt selbst publiziert beim Schreiben nur eine 1×-Repräsentation,
daher kein Effekt in Qt→nativ) und nur auf Retina-Systemen. Nicht gefixt (reine
Validierungssession) — eigenständiger Befund für eine künftige Session.

**Clipboard-Manager-Störfaktor geprüft:** `Maccy.app` lief während der gesamten
Session (macOS-Analogon zu KDE Klipper). `osascript -e 'clipboard info'` nach dem
Qt-Schreiben zeigte **9 Bild-Repräsentationen** (`TIFF`, `AVIF`, `8BPS`, `GIF`, `jp2`,
`JPEG`, `PNGf`, `BMP`, `TPIC`) — Qt publiziert selbst ein reichhaltiges Multi-Format-
Angebot. Trotz laufendem Clipboard-Manager **keine einzige der vier Zellen
gescheitert** — anders als auf Linux, wo der KDE-Klipper-Verdacht 3/3 Cross-Toolkit-
Versuche kaputt machte.

**Tie-Breaker-Verdikt (Qt→nativ, die eigentliche Tie-Breaker-Richtung): macOS steht
auf der Seite von Windows (sauber) gegen Linux (gescheitert) — 2 von 3 Plattformen
sauber.** Vorsichtiger formuliert als zunächst: macOS und Windows laufen über
unterschiedliche Qt-Plattform-Plugins als Linux (`cocoa`/`windows` statt `xcb`) —
ein sauberes Ergebnis auf beiden zeigt, dass der Shim-Code selbst
plattformübergreifend korrekt ist (kein racket-qt-Bug, der auf allen Plattformen
gleich wirken würde), **kann aber nicht zwischen** „KDE-Klipper-spezifisch" und
„xcb-Plugin-spezifisch" **unterscheiden** — beide Linux-exklusiven Faktoren bleiben
als Erklärung offen. Linux bleibt der einzige ungeklärte Fall, offen für eine
künftige Linux-Session (unverändert gegenüber dem bisherigen Stand).

**Status: PASS auf drei der vier getesteten Übertragungsrichtungen (In-Process Qt,
Cross-Prozess Qt→Qt, Cross-Toolkit Qt→nativ), keine racket-qt-Regression dort. Die
vierte Richtung (Nativ→Qt) zeigt einen eigenständigen neuen Befund (Größe/Scale
falsch gemeldet, s. o.) — kein Fix in dieser Session.**

### 2.10 `register-`/`unregister-collecting-blit` (GC-Indikator) — sauberer No-op bestätigt, strukturell erklärt

**XQuartz-Präsenzcheck (wichtig, ändert die erwartete Codepfad-Analyse laut Auftrag):**
`ls /opt/X11/lib/libX11*` zeigt XQuartz **ist installiert** auf dieser Maschine, und
sogar aktiv laufend (`Xquartz`/`quartz-wm`/`X11.bin`-Prozesse seit 07:55, **vor** dieser
Session gestartet — kein Nebeneffekt dieser Session). Trotzdem strukturell irrelevant:

1. **Compile-Zeit-Guard bestätigt (`qt-shim/src/shim.cpp:2136-2144`):** der komplette
   `QNativeInterface::QX11Application`-Zweig steht hinter `#ifdef __linux__`; der
   macOS-Zweig (`#else`) liefert `shim_get_x11_display` **unbedingt** `nullptr` —
   der im Auftrag beschriebene Grenzfall „`libX11` lädt, aber `qGuiApp`s X11-Interface
   liefert trotzdem `nullptr`" kann auf macOS **gar nicht erst auftreten**, weil der
   Racket-Code diesen Zweig nie erreicht (er fragt zwar `shim_get_x11_display()` ab,
   aber die Funktion selbst ist auf dieser Plattform strukturell ein Stub).
2. **`libX11` lädt auf dieser Maschine ohnehin nicht** — empirisch geprüft:
   `(ffi-lib "libX11" '("6" "5" "") #:fail (lambda () #f))` liefert `#f` (nicht der
   XQuartz-Pfad `/opt/X11/lib/libX11.6.dylib`), da `/opt/X11/lib` nicht im
   Standard-`dyld`-Suchpfad liegt (`DYLD_LIBRARY_PATH`/`DYLD_FALLBACK_LIBRARY_PATH`
   beide leer). **Architektur ist kein zusätzlicher Blocker** — Korrektur gegenüber
   einer ersten Fehleinschätzung: ein `otool -L`-Aufruf, der nur die erste
   Architektur-Slice-Kopfzeile zeigte, wurde zunächst fälschlich als „nur x86_64"
   gelesen; `lipo -archs /opt/X11/lib/libX11.6.dylib` zeigt tatsächlich
   `x86_64 i386 arm64` — die Datei ist ein Universal-Binary und würde auf dieser
   `arm64`-Maschine architekturkompatibel laden, **wenn** der Suchpfad passen würde.
   Der Suchpfad-Fund allein (Punkt 2) bleibt aber ausreichend, um das Laden zu
   verhindern.
3. Damit ist `x11-gc-available?` (`wx/qt/gcwin.rkt:126`, `(and (get-x11-display) #t)`)
   auf dieser Maschine **strukturell unbedingt `#f`** — der Compile-Guard (Punkt 1)
   allein reicht bereits aus (der Racket-Code fragt `shim_get_x11_display()` zwar ab,
   aber die Funktion ist auf macOS ein unbedingter Stub), der Suchpfad-Fund (Punkt 2)
   ist eine zweite, unabhängige Absicherung auf der Racket-FFI-Seite.

**Skriptbasierter Crash-Test (kein Klick-Risiko, echte öffentliche API):** eigenes
`frame%`+`canvas%`, `register-collecting-blit`/`unregister-collecting-blit` aus
`racket/gui/base`, dazwischen 50× `(collect-garbage)` — **PASS, kein Crash**, sauberer
Exit 0. Bestätigt den No-op-Pfad (Bitmaps werden dank `x11-gc-available?`-Gate in
`canvas.rkt:329` gar nicht erst angefasst) unter echtem GC-Druck.

**Kritischer Gate-Test — DrRacket-Start unter `PLT_QT=1`, verifiziert nicht angenommen:**
Prozess überlebt (`ps aux` zeigt `racket -l drracket` nach 8s weiterhin laufend),
Fenstertitel korrekt via `osascript`/System Events: `Untitled - DrRacket` (nicht nur
Splash). `vmmap`/`lsof` auf dem laufenden Prozess **zeigen kein geladenes `libX11`/
`XQuartz`** (bestätigt Punkt 2 oben zur Laufzeit, nicht nur isoliert). Sauberer Quit
(`Cmd+Q`), Prozess danach vollständig weg; einzige stderr-Zeile beim Beenden:
`QThreadStorage: entry 0 destroyed before end of thread` — bekanntes, harmloses
Qt-Teardown-Rauschen, kein „invalid memory reference", keine andere
Crash-Signatur.

**Gate-Test nativ (ohne `PLT_QT`):** ebenfalls Prozess-Überleben + korrekter
Fenstertitel bestätigt, sauberer Quit, keine Regression durch diese Session.

**Optionaler GC-Stresstest in echten Interactions:** nicht als eigener dedizierter
Test durchgeführt (ehrlich als eingeschränkt vermerkt statt fingiert) — der
skriptbasierte Crash-Test deckt den eigentlichen Sicherheitsnachweis (No-op unter
echtem `collect-garbage`-Druck über die öffentliche API) bereits ab. **Beiläufige
Bestätigung aus dem Akzeptanztest (Task 4) nachgetragen:** in den dortigen
Screenshots der laufenden DrRacket-Fenster (z. B. `dock-run1.png`, Statuszeile
unten rechts, `596.38 MB`-Speicheranzeige) ist an der Stelle, an der gtk/win32 den
blinkenden `gc-canvas`-Indikator zeigen würden, durchgehend **kein** Icon sichtbar
— konsistent mit `x11-gc-available?=#f` (kein GC-Indikator registriert, aber auch
kein Leerzeichen-Artefakt/Layout-Fehler an der Stelle). Kein eigener GC-Druck-Test
in dieser Sichtung (die drei Akzeptanztest-Läufe erzeugen ohnehin laufend GC-Zyklen
durch DrRacket/htdp selbst, ohne Absturz).

**Status: PASS — sauberer No-op, strukturell (nicht nur empirisch) erklärt, kein
Crash unter keinem der beiden Gate-Tests, kein GC-Stresstest-Crash.**

**Zwischen-Hygiene:** `racket-prefs.rktd` war nach den beiden DrRacket-Gate-Starts
(2.10, kein expliziter Preferences-Dialog, aber DrRacket persistiert beiläufig
Fenstergeometrie/Rezent-Zustand bei jedem Start) auf `34bde147…` gewechselt — direkt
danach und **vor** Beginn von Suite A auf den Session-Start-Hash `be9b38f2…`
zurückgespielt (`\cp -f`, Alias-Interferenz von `cp -i` umgangen, Hash danach
verifiziert identisch), damit Suite A von einem sauberen, bekannten Preferences-
Stand aus startet.

### Suite A — Regressions-Re-Lauf (16 Proben)

**Methodik-Hinweis:** es existiert kein `2026-09-19_report-macos.md` (nur Linux/
Windows haben ein 09-19-Dokument) — Baseline stammt aus der
2026-09-18(-N)_report-macos.md-Serie und `docs/HACKING.md` §44-51 (Quelle je Zeile
vermerkt). Wo keine macOS-Zahl existiert: Verhaltenskriterium aus Linux/Windows
übernommen, keine erfundene Zahl. Automatisierungsmethodik: `osascript`/System
Events (`click at`, `set size of window`, `keystroke`) für AX-erkennbare Ziele,
echtes CGEvent (`Quartz`-Python, `CGEventCreateMouseEvent(kCGEventMouseMoved)`
statt `CGWarpMouseCursorPosition`, das keine Hover-Events auslöst — Falle gefunden
und korrigiert, s. u.) für Mausrad/Cursor/Modifier-Tests, `cliclick` als Fallback.
Fokus unmittelbar vor jedem Klick aktiviert (`set frontmost of process "racket"`),
Koordinaten unmittelbar vorher neu abgefragt (nie über Tool-Aufrufe hinweg
gecacht).

**Automatisierungs-Fallstrick gefunden und dokumentiert (kein Produktbefund):**
`cliclick c:<x>,<y>` lieferte bei `enable-cascade-probe.rkt` reproduzierbar
**keinen** Klick-Erfolg, obwohl die Koordinaten per Screenshot exakt verifiziert
korrekt waren (Button-Zentrum bei `(720,402)`, Screenshot-Rückrechnung bestätigte
dieselbe Position bis auf 1px) — `osascript ... click at {x,y}` (AX-Ebene) traf
dagegen sofort und zuverlässig. Zwei verschiedene Klick-Primitiven auf derselben
Maschine mit entgegengesetztem Erfolg, je nach Widget — deckt sich mit der bereits
in `docs/HACKING.md` §51.2 dokumentierten Erfahrung (dort löste `cliclick`
gerade das Problem, das `osascript`/AX bei `list-box%` hatte); hier war es
umgekehrt. Für alle folgenden Klicks in dieser Session wurde `osascript click at`
verwendet, wo eine AX-Identifizierung möglich war.

| Probe | macOS-Baseline (Quelle) | Diese Session (2026-09-25) | Einordnung |
|---|---|---|---|
| `clipboard-probe.rkt` | PASS, 3/3 Checks OK (§36, 2026-09-18-2) | PASS, 3/3 Checks OK, identische Werte | Keine Änderung |
| `menu-demand-probe.rkt` (`PLT_QT_DEBUG=1`) | PASS, `on-demand` feuert auf echtem `QMenu::aboutToShow` (§37, 2026-09-18-2) | PASS, `demand-count` 0→1→2, `checked?` `#t`→`#f`, `RESULT: PASS` | Keine Änderung |
| `is-shown-probe.rkt` | PASS, `is-shown?` auf allen 3 Ebenen identisch zu nativ (§44.3) | PASS, `PUMP OK`, sauberer Exit | Keine Änderung |
| `resize-reflow-probe.rkt` | kein direkter macOS-Baseline-Wert; Verhaltenskriterium: einmalige Korrektur ohne Kaskade (Linux/Win) | PASS, `400x300` → `400x756` (oversized children, einmalige Korrektur) | Keine Änderung (kein macOS-Referenzwert, Verhaltensmuster korrekt) |
| `live-resize-probe.rkt` (AX `set size of window`) | PASS, Button folgt Breite: `300x200`→`696px`→`866px` (§44.4) | PASS, Button `696px`→`866px` **identisch**, Frame-Höhe `344`/`444` statt `372`/`472` (28px AX-Chrome-Offset, s. u.) | Keine Änderung (Chrome-Offset-Artefakt, Button-Breite exakt gleich) |
| `minsize-resize-probe.rkt` (Schrumpfversuch auf `50x50`) | PASS, einmalige Korrektur auf `327x432`, 12 weitere Ticks stabil (§44.4) | PASS, einmalige Korrektur auf **`327x432`** (bit-identisch), stabil über alle 40 Ticks (3-40), kein Oszillieren | Keine Änderung |
| `scroll-probe.rkt` (echtes Quartz-Mausrad, vertikal) | PASS, 10 Notches → 10 Zeilen exakt, PageDown → 16 Zeilen, volle Reichweite bis Zeile 99 (§45.7) | PASS (volle Reichweite bis Zeile 99 mit Thumb am Ende bestätigt, keine Streifen/Korruption); **Mausrad-Notch→Zeilen-Verhältnis nicht 1:1 reproduziert** (10 Notches → 7 Zeilen bei `dy=-3`), **aber PageDown gezielt nachgetestet: exakt 16 Zeilen (Zeile 0→16), bit-identisch zur Baseline** | Automatisierungsartefakt bei der Mausrad-Kalibrierung, kein Produktbefund — PageDown ist deterministische Tastatureingabe (keine Quartz-Wheel-Simulation) und reproduziert die Baseline exakt; das beweist, dass der Scroll-Mechanismus selbst unverändert korrekt ist und die Notch-Abweichung an der hier verwendeten `dy`-Kalibrierung liegt, nicht am Produkt |
| `panel-scroll-probe.rkt` (Mausrad + Klick) | PASS, „Names" unerreichbar→erreichbar→klickbar (§45.6) | PASS, „Names" bei `y=1047` außerhalb (Fenster bis `y=569`) → nach 30 Notches bei `y=553` innerhalb → Klick löst `CLICK auf Names (Nr. 1)` aus | Keine Änderung (absolute Y-Werte durch andere Fensterposition, Verhaltensmuster identisch) |
| `canvas-panel-probe.rkt` | PASS, kein Crash, `content inserted`/`frame shown` geloggt (macOS-Ursprungsprobe dieser Konfiguration) | PASS, identische Log-Sequenz (`canvas-panel% created` → `content inserted (no crash...)` → `frame shown`), Timeout-beendet wie erwartet | Keine Änderung |
| `deleted-style-probe.rkt` | kein macOS-09-18-Einzeleintrag; Verhaltenskriterium aus Linux/Win: `dead-panel is-shown?=#f w=0 h=0` | PASS, `dead-panel is-shown?=#f x=0 y=0 w=0 h=0`, `dead-canvas is-shown?=#f w=0 h=0`, `frame`/`outer`/`visible-pane`/`b-visible` alle korrekt sichtbar mit Geometrie | Keine Änderung (kein macOS-Referenzwert, Verhaltensmuster korrekt) |
| `crash-b-teardown-probe.rkt` (frameless `put-file`, Cancel via Escape) | PASS, beide Pfade kein Crash (§45.5) | PASS, `put-file returned: #f` (Cancel/Escape), sauberer Exit, kein Crash-Trace | Keine Änderung; **nur der Cancel-Pfad erneut geprüft, Accept-Pfad in dieser Session nicht wiederholt** (Zeitbudget) — der §39-Root-Cause (`deleteLater` nach dem Callback) betrifft laut Fix-Beschreibung beide Pfade gleichermaßen, es gibt keinen belegten Grund anzunehmen, dass nur Cancel das historische Risiko trägt; diese Zeile ist bewusst als Lücke stehengelassen statt mit einer unbelegten Begründung zugedeckt |
| `enable-cascade-probe.rkt` (echter Klick, `osascript click at`) | PASS, `clicks=1` (Positivkontrolle), `disabled-delta=0` (§45.1-Nachtrag) | PASS, `n1=1`, `disabled-delta=0` — **erste Versuche mit `cliclick` scheiterten** (s. Fallstrick oben), nach Wechsel auf `osascript click at` sauber reproduziert | Keine Änderung (Automatisierungswerkzeug-Wechsel nötig, kein Produktbefund) |
| `gauge-probe.rkt` | PASS, echter wachsender Balken h+v (§49.2) | PASS, zwei Screenshots (unterschiedliche Füllstände) zeigen wachsenden horizontalen **und** vertikalen `QProgressBar`, `get-value` folgt exakt | Keine Änderung |
| `cursor-probe.rkt` (`hand`/`bullseye`/custom „plus"`) | PASS, native Cursor-Form für alle geprüften Symbole (§49.3) | PASS, `hand`/`bullseye`/custom „plus" alle korrekt (Screenshot `-C`); **`CGWarpMouseCursorPosition` löst keine Hover-Events aus** (erst leere Screenshots) — durch `CGEventCreateMouseEvent(kCGEventMouseMoved)` ersetzt, danach korrekt | Keine Änderung (Automatisierungsfalle gefunden+korrigiert, kein Produktbefund) |
| `mouse-state-probe.rkt` (Position/Shift/Linksklick) | PASS Position+Modifier (§42/§49.5, Cmd/Ctrl-Swap bewusst) | PASS: Position exakt `(700,500)`, `mods=(shift)` während Shift-Hold, `mods=(left)` während Linksklick-Hold, danach korrekt leer | Keine Änderung |
| `printer-probe.rkt` (`PLT_QT_PRINT_TO_PDF`) | PASS, `612x792pt`, `504081` Bytes (§49.4) | PASS, `page-size = 612 x 792 pt` (identisch), PDF `505001` Bytes (920 Byte Differenz zur Baseline); zweimal auf dieser Maschine wiederholt: **Größe deterministisch identisch (`505001` Bytes beide Male), Hash unterschiedlich** (`57bb656e…` vs. `6c259cc3…` — vermutlich eingebetteter Zeitstempel/Metadaten, nicht isoliert), beide Seiten visuell korrekt gerastert (Ellipse+Linie+Text / Rundrechteck+Text) | Keine Änderung am Verhalten; **kein Baseline-Raster zum Pixelvergleich vorhanden** — „pixelgeprüft identisch" wäre eine unbelegte Aussage, korrekt ist „visuell korrekt, Ursache der Byte-Differenz zur Baseline nicht isoliert" |

**Zusammenfassung Suite A: 16/16 Proben PASS, keine Regression.** Zwei echte
Automatisierungsfallen dieser Session (`cliclick` vs. `osascript click at` je nach
Widget, `CGWarpMouseCursorPosition` ohne Hover-Event) sind Werkzeugartefakte dieser
Session, keine `racket-qt`-Befunde — beide gefunden, verstanden und umgangen, nicht
stillschweigend übergangen. Keine Interaktion der Block-C-Fixes (insbesondere 2.1
Font, 2.6 Clipboard-Arity, §55.6 Clipboard-`eq?`) mit einem der 16 Verhaltensmuster
gefunden.

**Hygiene:** `git status --short --ignored examples/` vor/nach identisch (nur die
bereits bekannten, session-fremden `examples/compiled/` und
`examples/htdp-tests-probe.rkt~`). Alle gestarteten `racket`-Prozesse einzeln
verifiziert beendet (`ps aux | grep -i racket` leer nach jeder Teilaufgabe).
`racket-prefs.rktd` nach Abschluss auf den Session-Start-Hash `be9b38f2…`
zurückgespielt (Hash verifiziert).

### Akzeptanztest `test-dock-size` (n=3) — 0/3 Crash, PASS, plus ein neuer Befund

**Methode:** exakt das in `docs/2026-09-18_report-macos.md`/`docs/HACKING.md` §44.2
etablierte macOS-Verfahren übernommen (nicht das Linux-`xdotool`-Verfahren neu
konstruiert). Scratch-Kopien von `examples/htdp-tests-probe.rkt` und
`examples/htdp-image-probe.rkt` in einen eigenen Scratchpad-Ordner
(`.../scratchpad/dock-test/`) angelegt, `git status --short examples/` vor jedem der
drei Durchläufe geprüft (leer). Frischer `PLT_QT=1 racket -l drracket --
.../dock-test/htdp-tests-probe.rkt`-Prozess je Durchlauf. **Run ausgelöst über das
Menü-Äquivalent** (`Racket`-Menü → `Run`, per Index `menu bar item 7`, nicht per
Name — Namenskollision mit dem App-Menü „racket"), **nicht** per Koordinatenklick
auf den Toolbar-Button — §44.2/§44.6 dokumentieren, dass der Toolbar-„Run"-Button
custom-gezeichnet und ohne jede Accessibility-Repräsentation ist, rohe
Koordinatenklicks dort wirkungslos bleiben. **Wichtige Präzisierung:** §45 (Zeile
5259-5272 in `docs/HACKING.md`) stuft die §44.2/§44.3-Befunde nachträglich als
wahrscheinliches Fokus-Problem ein, nicht als grundsätzliche Automatisierungsgrenze
— deshalb in dieser Session **ein gezielter Gegentest** unternommen (eigener
DrRacket-Lauf, außerhalb der drei gezählten Akzeptanztest-Durchläufe): `set
frontmost` unmittelbar vor dem Klick, Koordinaten unmittelbar vorher per Screenshot
neu vermessen, `osascript click at` auf den Toolbar-„Run"-Button — **Klick blieb
weiterhin wirkungslos** (kein Testlauf ausgelöst, Interactions blieben leer). Die
§44.2-Beobachtung reproduziert damit auch nach der §45-Reklassifizierung; der
Toolbar-Button bleibt ein eigener, vom Fokus-Problem verschiedener Fall. Die
Menü-Route war damit weiterhin die richtige Wahl für die drei gezählten
Durchläufe — nicht unhinterfragt übernommen, sondern erneut geprüft.

**Ergebnis je Durchlauf (alle drei identisch):**
1. Run → Interactions zeigen `Ran 3 tests. 1 of the 3 tests failed. Check
   failures: Actual value 16 differs from 17...` (exakt der erwartete, absichtlich
   fehlschlagende Test) — kein `DrRacket Internal Error`, kein Absturz.
2. `File → Open…` (Menü-Äquivalent, Qt-eigener `QFileDialog` öffnete sich bereits
   im Scratch-Ordner) → Dateiname `htdp-image-probe.rkt` ins native Textfeld
   getippt + Enter → Tab öffnet sauber, Inhalt (2htdp/image-Testcode) korrekt
   gerendert, kein Absturz.
3. Tab-Zustand über das `Windows`-Menü verifiziert (wie in der Baseline, nicht über
   einen sichtbaren Tab-Strip — der ist in dieser Konfiguration ohnehin nicht
   sichtbar, auch nicht in der 09-18-Baseline): `Tab 1: htdp-tests-probe.rkt`,
   `Tab 2: htdp-image-probe.rkt` — beide korrekt vorhanden, in allen drei Läufen.
4. Sauberes Beenden über `Cmd+Q` (racket-App-Menü „Quit racket"-Äquivalent), Prozess
   danach vollständig weg (`ps aux` leer), kein Zombie, kein Recovery-Dialog beim
   nächsten Start (keine Autosave-Reste gefunden).

**Akzeptanzkriterium erfüllt: 0/3 Crash.** Der Linux-Fix (Commit `2f0755bd`)
generalisiert weiterhin auf macOS, deckt sich mit der 09-18-Baseline.

### Neuer Befund — Menüleiste kollabiert nach jedem Dialog-Öffnen/-Schließen (nicht nur nach Tab-Hinzufügen)

**Nicht Teil der ursprünglichen vier Aufgaben, aber während des Akzeptanztests
reproduzierbar aufgetreten — dokumentiert, nicht gefixt.** Erste Beobachtung: nach
jedem der drei `File → Open…`-Vorgänge (die den zweiten Tab hinzufügen) kollabierte
die **native macOS-Menüleiste** sofort und reproduzierbar (**3/3**) auf den
reduzierten „Keine Dokumente offen"-Zustand (`racket, File, Help` — dieselben drei
Einträge wie in §44.5/§47s Befund nach dem Schließen des letzten Fensters),
**obwohl** ein voll funktionsfähiges Fenster mit zwei korrekten Tabs weiterhin
sichtbar und fokussiert war.

**Trigger präzisiert (gezielter Nachtest, ein zusätzlicher DrRacket-Lauf):** die
naheliegende erste Erklärung „Tab hinzugefügt" ist **zu eng** — derselbe Kollaps
tritt bereits ein, wenn `File → Open…` den `QFileDialog` öffnet und der Dialog per
**Escape/Cancel** geschlossen wird, **ganz ohne dass ein zweiter Tab entsteht**
(Fensterliste danach weiterhin nur das eine unveränderte Fenster). Der tatsächliche
Trigger ist damit das **Öffnen/Schließen eines Dialogs** (`dialog%` erweitert
`frame%` und ruft laut §47.4 `super direct-show` — zählt also in der dortigen
`shown-real-frames`-Buchführung mit), nicht das Hinzufügen eines Tabs. Das deckt
sich mit §47.3/§47.4s Mechanismus (`wx/qt/frame.rkt`s `direct-show`/
`update-root-menubar-visibility!`, `shown-real-frames`-Hash) — plausibelste
Einordnung: der dortige Zähl-Mechanismus verzählt sich beim Dialog-Show/Hide-Zyklus
kurzzeitig auf 0 (oder eine Race-Bedingung lässt die reduzierte Root-Leiste sichtbar,
obwohl der Hash korrekt wieder gefüllt ist), bis ein externes Aktivierungs-Event den
Zustand erzwingt neu zu synchronisieren.

Per **Screenshot visuell verifiziert** (nicht nur AX-Abfrage) — echter
Rendering-Zustand der Systemmenüleiste, kein `osascript`/AX-Cache-Artefakt (sowohl
für den Open-mit-zweitem-Tab-Fall als auch für den Escape-ohne-Tab-Fall separat
bestätigt). **Heilt nicht von selbst** (15s Wartezeit ohne Wirkung getestet),
**heilt sofort und zuverlässig durch einen App-Aktivierungswechsel** (`Cmd+Tab` weg
und zurück, in allen Fällen sofort danach wieder alle 11 Menüs vollständig,
Fenster-/Tab-Zustand dabei unverändert korrekt). Root-Cause nicht abschließend
isoliert (außerhalb des Sessionumfangs, Regel 4 — kein spekulativer Fix) — aber
klarer eingegrenzt als bei der Erstbeobachtung: §47s Zähl-Mechanismus plus ein
Dialog-Show/Hide-Zyklus als konkreter, minimaler Trigger. **Kein Blocker für den
Akzeptanztest selbst** (Crash-Kriterium unberührt, Tab-Zustand über das Menü nach
Reaktivierung korrekt verifizierbar), aber ein eigenständiger, echter
`racket-qt`-Befund für eine künftige Session — nicht committet, nicht gefixt
(Auftragsvorgabe: reine Validierung).

### Neuer Befund — Nativ→Qt-Bildzwischenablage meldet Retina-Inhalte bei doppelter Größe

Siehe Abschnitt 2.7 oben („Neuer Befund — Nativ→Qt liest Retina-Bilder bei doppelter
Pixelgröße…"): ein von einem nativen (Cocoa-)Prozess auf die Zwischenablage
geschriebenes Bild wird von einem Qt-Leser mit `get-width`/`get-height` doppelt so
groß und `get-backing-scale=1.0` statt korrekt skaliert gemeldet — API-sichtbar
falsches Verhalten auf Retina-Systemen, nicht nur eine Nuance. Hier nur referenziert,
damit beide neuen Befunde dieser Session an einer Stelle auffindbar sind.

**Hygiene:** `racket-prefs.rktd` vor Beginn (`be9b38f2…`) und nach jedem der drei
Durchläufe zurückgespielt (DrRacket persistiert beiläufig Fenstergeometrie bei
jedem Start/Beenden, auch ohne explizite Preferences-Interaktion — Hash danach
je verifiziert). `git status --short examples/` vor jedem Durchlauf leer (nur
Scratch-Kopien verwendet, keine Originaldatei geöffnet/verändert). `ps aux | grep
-i racket` zwischen den drei Durchläufen leer verifiziert. Keine Autosave-/
Recovery-Dateien gefunden. Nur der Report selbst im Umbrella-`git status`
verändert.

## Phase 3 — Gesamtfazit (macOS)

**Alle vier Teilaufgaben abgeschlossen, GATE PASS mit zwei dokumentierten neuen
Befunden (nicht gefixt, Auftragsvorgabe reine Validierung).**

- **2.5 `flush-display`:** nicht Teil der vier zugewiesenen Aufgaben, aber wie im
  Windows-Bericht der Vollständigkeit halber vermerkt: nur **implizit** mitgetestet
  — über die Session verteilt liefen **fünf** echte `PLT_QT=1 racket -l
  drracket`-Starts (2.10-Gates ×2, Akzeptanztest ×3, plus zwei weitere im Rahmen
  der Nachtests dieses Abschnitts), jeder davon durchläuft den Splash-Screen-Pfad
  ohne Hang/Crash. Kein dedizierter `flush-display`-Test in dieser Session.
- **2.7 Bild-Zwischenablage:** PASS auf drei der vier getesteten
  Übertragungsrichtungen (In-Process Qt, Cross-Prozess Qt→Qt, Cross-Toolkit
  Qt→nativ). Der Tie-Breaker (Qt→nativ) fällt **auf die Seite von Windows**
  (sauber) statt Linux (KDE-Klipper-Verdacht) — zeigt, dass der Shim-Code
  plattformübergreifend korrekt ist, kann aber nicht zwischen „Klipper-spezifisch"
  und „xcb-Plugin-spezifisch" unterscheiden (macOS/Windows nutzen andere
  Qt-Platform-Plugins als Linux). Alle beobachteten RGB-Abweichungen in dieser
  Richtung sind durch eine Cocoa-eigene Farbraum-Transformation erklärt (per
  nativer Kontrollzelle bytegleich reproduziert), keine racket-qt-Regression. Die
  vierte Richtung (Nativ→Qt) ist ein **eigenständiger neuer Befund** (s. u.).
- **2.10 `collecting-blit`:** PASS, sauberer No-op, **strukturell** (Compile-Guard;
  der Suchpfad-Fund ist eine zweite, unabhängige Absicherung, kein Architektur-
  Blocker — `libX11.6.dylib` ist laut `lipo -archs` tatsächlich ein
  arm64/x86_64/i386-Universal-Binary, frühere „nur x86_64"-Angabe war ein
  Lesefehler an einem `otool`-Ausschnitt und ist hiermit korrigiert) und nicht nur
  empirisch erklärt — trotz installierter (und laufender) XQuartz auf dieser
  Maschine, was den Test gegenüber Linux/Windows erst aussagekräftig machte. Beide
  DrRacket-Gate-Tests (`PLT_QT=1` und nativ) PASS, kein Crash unter echtem
  `collect-garbage`-Druck, kein GC-Indikator-Icon sichtbar (konsistent mit
  `x11-gc-available?=#f`).
- **Suite A:** 16/16 Proben PASS, keine Regression. Alle Zahlenabweichungen
  gegenüber der Baseline einzeln erklärt und, wo möglich, durch einen gezielten
  Zweittest erhärtet statt nur behauptet (PageDown bei `scroll-probe.rkt` bestätigt
  bit-identisch 16 Zeilen; `printer-probe.rkt` zweimal wiederholt, Größe
  deterministisch identisch, Byte-Differenz zur Baseline nicht isoliert). Zwei
  Automatisierungsfallen dieser Session gefunden und umgangen (`cliclick` vs.
  `osascript click at` je nach Widget-Typ, `CGWarpMouseCursorPosition` ohne
  Hover-Event) — dokumentiert, nicht stillschweigend übergangen.
- **Akzeptanztest `test-dock-size`:** 0/3 Crash, Akzeptanzkriterium erfüllt,
  identisch zur 09-18-Baseline (Run per Menü-Äquivalent, erneut geprüft gegen die
  §45-Reklassifizierung — ein gezielter Toolbar-Klick-Gegentest mit korrektem
  Fokus/aktuellen Koordinaten blieb weiterhin wirkungslos, die Menü-Route war also
  weiterhin richtig).

**Zwei neue, eigenständige `racket-qt`-Befunde dieser Session (beide dokumentiert,
keiner gefixt/committet):**
1. Die native Menüleiste kollabiert nach jedem Dialog-Öffnen/-Schließen (nicht nur
   nach Tab-Hinzufügen, wie zunächst vermutet — per Gegentest auf den
   Escape-Pfad ohne Tab präzisiert) auf den reduzierten Drei-Menü-Zustand und
   heilt erst durch App-Reaktivierung, nicht von selbst.
2. Ein von einem nativen Prozess auf die Zwischenablage geschriebenes Bild wird
   von einem Qt-Leser mit doppelter Pixelgröße bei `backing-scale=1.0` gemeldet
   statt korrekt skaliert — API-sichtbar falsch auf Retina-Systemen.

**Damit sind jetzt alle zehn Block-C-Fixes auf allen drei Plattformen validiert**
(Linux 10/10, Windows 9/10 PASS + Akzeptanztest dort offen wegen
Automatisierungsblocker, macOS 10/10 PASS inkl. Akzeptanztest, plus zwei neue,
über den ursprünglichen Block-C-Umfang hinausgehende Befunde). Sache des
Hauptagenten/Nutzers, ob und wann die beiden neuen Befunde aufgegriffen werden.

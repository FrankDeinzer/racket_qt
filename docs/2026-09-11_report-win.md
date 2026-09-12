# Report — Racket-9.3-Migration + Stabilisierungsrunde (Windows) — 2026-09-11

**Prompt:** `docs/2026-09-11_prompt.md`. Gemessene Version: **`racket --version` → v9.3 [cs]**
(via `C:\Program Files\Racket\racket.exe`, s. Fund unten zu PATH).

---

## Phase 0 — Racket-9.3-Migration + Basislinie

### 0.1 Version
`v9.3 [cs]` bestätigt — aber **nicht** über bloßes `racket --version` (PATH-Fund, s. u.),
sondern über den vollen Pfad `C:\Program Files\Racket\racket.exe`.

### 0.2 Sync-Check
- Umbrella `main`: 1 Commit **ahead** of `origin/main` (lokal, ungepusht — der
  `2026-09-11_prompt.md`-Commit). Kein Rückstand, keine Divergenz.
- Submodul `third_party/gui` (`qt-backend`): exakt auf `origin/qt-backend`
  (`54f2f702`), kein Rückstand.
→ Kein STOPP-Kriterium (0.2) erfüllt.

### 0.3 Link-Status (neue 9.3-Installation)
`raco pkg show -l`: `gui-lib`/`draw-lib` **nicht verlinkt** (Teil der 217
auto-installierten Pakete der Installation). Erwartung bestätigt.

### 0.4 Versions-Kompatibilität (Risikopunkt)
- Installierte `gui-lib` (Racket 9.3): **1.80**, Quelle
  `git://github.com/racket/gui/?path=gui-lib#6f0213fa0535d87dd4e35f56c8266d948c8c089e`.
- Installierte `draw-lib` (Racket 9.3): **1.24**.
- Fork (`third_party/gui/gui-lib/info.rkt` / `third_party/draw/draw-lib/info.rkt`):
  **1.80** / **1.24** — identisch zur System-Version.
- Vollständiger Sweep über alle 217 installierten Pakete (`grep -ho '"gui-lib"
  #:version "[^"]*"' */info.rkt`, analog `draw-lib`): höchste geforderte
  `gui-lib`-Version **1.80**, höchste geforderte `draw-lib`-Version **1.23**. Beide vom
  Fork erfüllt (1.80 ≥ 1.80, 1.24 ≥ 1.23).
- **Ergebnis: kein Versionsangleich nötig.** Anders als beim 1.78→1.80-Angleich
  (`docs/2026-07-02_report.md`) ist der Fork bereits auf dem exakten von 9.3
  benötigten Stand. 0.4-Gate: **grün**, weiter zu 0.5/0.6.
- **Bekannter, bewusst nicht verfolgter Punkt:** Versionsgleichheit (1.80/1.24) beweist
  keine Commit-Gleichheit — der Fork wurde nicht gegen `6f0213fa0535` diff-verifiziert.
  Out of scope dieser Session (kein Hinweis auf ein Problem).

### Fund — PATH
`racket` ist **weder im Machine- noch im User-PATH** persistiert (leerer Treffer in
`[Environment]::GetEnvironmentVariable("Path", ...)`). Betrifft alle drei Umgebungen
(Bash, PowerShell) — kein Shell-Artefakt. Alle weiteren Befehle dieser Session nutzen
den vollen Pfad `C:\Program Files\Racket\...`. **CLAUDE.md-Run-Rezepte für Windows
setzen bislang bloßes `racket ...` voraus** — das ist im Moment nicht lauffähig ohne
PATH-Fix oder volle Pfadangabe; wird am Session-Ende in `CLAUDE.md` vermerkt.

### Fund — kein 9.2-Fallback mehr vorhanden
`C:\Program Files\Racket` existiert nur **einmal**, Zeitstempel heutig — die 9.2-
Installation wurde beim 9.3-Update **in-place ersetzt**, nicht parallel installiert.
`AppData\Roaming\Racket\` enthält zwar noch `9.2`-Verzeichnisse (User-Scope-Reste,
u. a. `PLT-autosave-toc.rktd`, keine `pkgs.rktd` darunter — 9.2 nutzte auf dieser
Maschine ebenfalls Installation-Scope für den Link, kein User-Scope-Paket), aber
**keine eigene 9.2-Programminstallation mehr**. Der einzige Rollback-Weg ist damit das
Dateisystem-Backup aus 0.5 (installierte `gui-lib`/`draw-lib`-Verzeichnisse +
`share/pkgs/pkgs.rktd`), **kein** Umschalten auf eine parallele alte Installation.
→ Nutzer gefragt (Regel 7 + 0.5), s. u.

### Elevation
Aktuelle Shell läuft **nicht** erhöht (`IsAdmin: False`). `raco pkg update --link`
gegen `C:\Program Files\Racket\share\pkgs\` braucht Admin-Rechte (Präzedenzfall
`docs/2026-07-02_report.md` §4.1–4.3) → Nutzer-Einbindung nötig vor 0.6.

---

### 0.5 Backup
Angelegt unter `C:\Users\Deinzer\racket-link-backup-2026-09-11\` (`gui-lib/`,
`draw-lib/`, `pkgs.rktd`, 1513 Dateien). Nutzer bestätigte (Regel 7 + 0.5):
Backup-only-Rollback ist ausreichend, kein Versuch, die alte 9.2-Installation
wiederherzustellen.

### 0.6 Linken
Nutzer führte elevated aus:
```
& "C:\Program Files\Racket\raco.exe" pkg update --link "C:\src\racket_qt\third_party\gui\gui-lib" "C:\src\racket_qt\third_party\draw\draw-lib"
```
Lief ohne Fehler durch (volle `raco setup`-Neukompilierung). `raco pkg show -l`
danach bestätigt: `gui-lib`/`draw-lib` beide `(link "C:\src\racket_qt\third_party\...")`.

### 0.7 Gate-Test nativ (bestanden)
- `raco test tests/smoke.rkt` **ohne** `PLT_QT`: **3/3 grün**.
- DrRacket **ohne** `PLT_QT`: startet sauber, Prozess responsiv, Fenstertitel
  „Untitled - DrRacket" — kein Linklet-/Versions-Mismatch. Sauber beendet.

### 0.8 Stale-Shim-Check
`shim.cpp` (2026-07-14 18:36) älter als die gebaute `racketqtshim.dll`
(2026-09-10 14:45) → **kein Rebuild nötig**.

### 0.9 Light Mode
`racket-prefs.rktd`: `(plt:framework-pref:framework:white-on-black? #f)` — bestätigt.

### 0.10 Regressions-Basislinie (Racket 9.3, `PLT_QT=1`)
- `raco test tests/smoke.rkt`: **3/3 grün** (einmalige, bereits dort dokumentierte
  Nebenausgabe `qt.qpa.window: SetProcessDpiAwarenessContext() failed: Zugriff
  verweigert` — vorbestehend seit `docs/2026-06-30_report.md`, **keine 9.3-Regression**).
- **Automatisierungs-Methode dieser Session:** PowerShell + .NET
  (`System.Windows.Forms`/`System.Drawing` für Screenshots, `SetForegroundWindow`/
  `GetForegroundWindow` zur Fokus-Verifikation vor jeder Eingabe, Maus-Koordinaten
  für Menü-/Button-Klicks). **Wichtiger Negativbefund:** Tastatur-Akzeleratoren
  (`SendKeys` für `Ctrl+R`, `Ctrl+O`) werden vom Qt-Backend **nicht** zuverlässig
  entgegengenommen, obwohl sie laut UI-Automation-Baum korrekt als Menü-Shortcut
  hinterlegt sind (`Run␉Ctrl+R`, `Open…␉Ctrl+O`) — Maus-Klicks auf Toolbar-Button/
  Menüpunkt funktionieren zuverlässig. **Nicht weiter verfolgt** (kein Fix-Versuch,
  reine Methodik-Notiz für künftige Automatisierung); möglicher Zusammenhang mit
  historischen Key-Handling-Eigenheiten dieses Backends (`docs/2026-07-02_report.md`),
  aber nicht verifiziert. RDP-Session war während der gesamten Messung aktiv/verbunden
  (`query session` geprüft), Screenshots dadurch zuverlässig (kein Schwarzbild-Risiko).
  Automatisierungshygiene beachtet: `git status` nach jeder DrRacket-Sitzung geprüft,
  keine Quelldatei verändert (nur `docs/2026-09-11_report-win.md` neu, Submodul sauber).
- **Facette 1a — `htdp-image-probe.rkt`:** 5/5 Bilder korrekt (Kreis, Rechteck-
  Outline, overlay, beside, text+rectangle). **Baseline bestätigt, keine Abweichung.**
- **Facette 1b — `htdp-image-count-probe.rkt`:** 6/6 Bilder korrekt — Windows zeigt
  (wie erwartet) **nicht** den Linux-spezifischen „nur 4 von 6"-Defekt (§23.1).
  **Baseline bestätigt.**
- **Facette 1c — `htdp-text-isolated-probe.rkt`:** rendert sofort korrekt.
  **Baseline bestätigt.**
- **Facette 2 — `htdp-bigbang-probe.rkt`:** via `racket` direkt (nicht DrRacket,
  Kosten-/Automatisierungsersparnis) unter `PLT_QT=1` mit sichtbarer Konsole
  gestartet. Tick-Stream (`tick: 0` … `tick: 35`) und World-Fenster-Anzeige (`36`)
  korrelieren exakt. Kein `exec()`, keine geschachtelte Schleife — Kern-Wette
  bestätigt. **Baseline bestätigt**, `on-key`-Test bewusst ausgelassen (bringt für
  die Baseline nichts, nur Automatisierungsrisiko, s. §23-Nebenartefakt der
  2026-07-14-Session).
- **Facette 3 — `htdp-tests-probe.rkt`:** 1→2-Tab-Sequenz (Run mit fehlschlagendem
  `check-expect`, danach File→Open von `htdp-image-probe.rkt` als zweite
  Registerkarte) → **`DrRacket Internal Error`** reproduziert sich byte-identisch
  zum historischen Befund: `preferences:set: new value doesn't satisfy
  preferences:set-default predicate — pref symbol: 'test-engine:test-dock-size,
  given: '(1)`, Stack über `test-panel%::remove` (`test-tool.rkt:267`) ←
  `undock-tests` ← `on-tab-change`. Prozess überlebt den Crash (wie dokumentiert).
  **Baseline bestätigt — dies ist der erwartete, bereits auf allen drei Plattformen
  10/10 reproduzierte Befund, kein neuer Fund.** Datei unverändert (nur geöffnet,
  nicht editiert), Prozess sauber beendet, keine Autosave-Recovery ausgelöst
  (`PLT-autosave-toc.rktd` blieb leer/2 Bytes).

**Ergebnis Phase 0: Basislinie entspricht vollständig der 9.2-Erwartung aus §23 —
keine 9.3-Regression gefunden.**

**Self-Gate Checkpoint 0: bestanden.** 9.3 läuft, Fork verlinkt, Nativ-Gate grün,
Smoke 3/3, Basislinie deckt sich mit 9.2 → weiter zu Phase 1.

---

## Phase 1 — Bekannte flache Befunde

### Befund 1 — Font-Size-Slider zeigt keine Zahl (§21.6)

**Status: gefixt.**

**Root-Cause (gemessen, Code-Vergleich gtk/win32/qt):** `QSlider` hat keine
eingebaute Wertanzeige. win32 (`wx/win32/slider.rkt`) löst das über eine separate
`STATIC`-Kind-HWND neben dem Trackbar (in einem gemeinsamen `PLTPanel`-Wrapper,
manuell positioniert in `set-size`); gtk (`wx/gtk/slider.rkt`) nutzt das eingebaute
`gtk_scale_set_digits`/`gtk_scale_set_draw_value` (nur bei `'plain` deaktiviert).
`wx/qt/slider.rkt` hatte **überhaupt keine** Wertanzeige-Logik — die alte
Implementierung wrappte ausschließlich den nackten `QSlider`.

**Fix (`wx/qt/slider.rkt`, keine Shim-Änderung):** mirrort win32s Muster mit
bereits vorhandenen Shim-Primitiven (`shim_panel_create`, `shim_label_create`,
`shim_label_set_text`, `shim_widget_get_size_hint` — alle schon für
`panel%`/`message%` im Einsatz, kein `shim.cpp`-Touch nötig → Regel 2, nicht
Regel 3). Bei nicht-`'plain`-Style: Slider + Value-Label werden in einen
`shim_panel_create`-Container gepackt, `set-size` positioniert beide manuell
(Slider oben/links, Label darunter/rechts, `THICKNESS`/`MIN_LENGTH`-Konstanten
wie win32). Label-Breite wird einmalig aus der breiteren von `lo`/`hi`
formatierten Zahl via `shim_widget_get_size_hint` ermittelt. Label-Update läuft
**im gequeuten Thunk** (Eventspace-Thread), nicht synchron im nativen
Change-Callback (Regel 2 der Fixen Regeln).

**Verifikation:**
- `raco test tests/smoke.rkt` (`PLT_QT=1`): weiterhin 3/3.
- `examples/value-widgets-probe.rkt`: Slider zeigt initial „20" unter dem
  Track; nach Klick auf „slider: set-value 75 via code" zeigt Label „75", Track
  bewegt sich mit, **kein** spurious Callback-Feuern (Screenshot-bestätigt).
- Echtes DrRacket unter `PLT_QT=1`: Edit → Preferences → Font-Tab zeigt jetzt
  „17" unter dem Font-Size-Slider (vorher: keine Zahl).

**Commit:** gui-Submodul `2b0d5e5a` (lokal, **noch nicht gepusht** — Push-Runde
wird gebündelt am Ende von Phase 1 mit Nutzer-Rückfrage, Regel 7). Umbrella-
Zeiger-Commit folgt nach dem Push (Regel 8: Zeiger darf nur auf einen bereits
auf `origin/qt-backend` existierenden SHA zeigen).

---

### Befund 2 — Colors-Tab: rechte Spalte + dunkle Rahmen fehlen (§21.6)

**Status: gefixt (nach Eskalation).**

Diagnose per Subagent (delegiert). **Root-Cause (gemessen):** Die "rechte Spalte"
war **nicht** fehlend oder falsch platziert — Foreground-/Background-Color-Buttons
der `'(background? #t)`-Zeilen (z. B. HtDP Languages → „Tests didn't cover")
wurden korrekt erzeugt und positioniert (Pointer-Adress-Vergleich instrumentiert
bestätigt). Der **tatsächliche** Defekt: dunkle Rahmen um jede Vorlagen-Zeile
fehlen komplett — `wx/qt/panel.rkt` ignorierte den `style`-Init-Parameter
vollständig, und `shim_panel_create` (`qt-shim/src/shim.cpp`) erzeugte immer ein
rahmenloses `QWidget`. Ohne den trennenden Rahmen verschmelzen benachbarte Zeilen
optisch — das erzeugte den Eindruck einer „fehlenden rechten Spalte" bei der
höheren 2-Button-Zeile. win32 zeichnet den Rahmen nativ über `WS_BORDER`
(`wx/win32/panel.rkt`).

**Eskalation (Regel 3):** Fix berührt `qt-shim/src/shim.cpp` (Shared/Shim-Code) →
Architektur-Subagent (fokussiert, kein Historien-Dump) empfahl: `border`-Parameter
an `shim_panel_create` statt neuer FFI-Funktion (nur 2 Call-Sites: `panel.rkt`,
`slider.rkt`), intern `QFrame` statt `QWidget` (`QFrame::Box|Plain` nur bei
`border=1`), kein Stylesheet (würde alle Kind-Widgets mit-restylen). Kein
Event-Loop-Bezug, klein/isoliert. Per `AskUserQuestion` bestätigt → umgesetzt.

**Fix:** `shim_panel_create(parent, border)` (Umbrella, `qt-shim/src/shim.cpp`) +
`wx/qt/panel.rkt` reicht `(if (memq 'border style) 1 0)` durch + `wx/qt/slider.rkt`
(Aufrufstelle auf neue Arität angepasst, `border=0`) + `wx/qt/utils.rkt`
(FFI-Signatur `_pointer _int -> _pointer`).

**Verifikation:** Shim neu gebaut, `raco make` sauber, Smoke 3/3 (mit **und** ohne
`PLT_QT`). Echtes DrRacket: Preferences → Colors → HtDP Languages zeigt jetzt einen
sichtbaren Rahmen um die Zeilengruppe; Font-Tab-Slider (Befund 1) weiterhin
unbeeinträchtigt.

**Commits:** gui-Submodul `ee75372d` (lokal, noch nicht gepusht); Umbrella `ea19095`
(shim.cpp, bereits committet — kein Submodul-Pointer-Bezug, daher unabhängig von der
Push-Reihenfolge aus Regel 8).

---

### Befund 3 — Windows Toolbar-Save-Icon-Timing (`wx/qt/button.rkt`)

**Status: nicht reproduziert — geparkt (Regel 4).**

Diagnose per Subagent (delegiert). Erste Korrektur der historischen Notiz: Der
Toolbar-„Save"-Indikator ist **kein** `button%`, sondern
`mrlib/switchable-button.rkt`s `switchable-button%` (ein `canvas%`, selbst-malend
via `on-paint`/`refresh`, verdrahtet über `framework/private/panel.rkt`) — die
2026-07-10-Notiz hatte die falsche Datei benannt. Tatsächlicher Pfad: `canvas%`
`refresh` → `canvas-mixin`s `queue-paint`/`do-on-paint` → `wx/qt/canvas.rkt`s
`queue-backing-flush`.

**Getestet (systematisch, gegen echtes DrRacket unter `PLT_QT=1`):** Tippen →
Icon erscheint promt (~150–300 ms, kein Sekundär-Trigger nötig); Undo → Icon
verschwindet ebenso prompt; Tippen unmittelbar gefolgt von Fenster-Resize
(Race-Test) → Icon korrekt im nächsten Frame. Tab-Wechsel-Test durch den
bekannten, unabhängigen `test-dock-size`-Crash (§23) blockiert — nicht verfolgt,
kein Bezug zu diesem Befund.

**Ausgeschlossen:** Tipp→Anzeige-Lag, Undo→Anzeige-Lag, Resize-Race-Lag — keiner
davon reproduziert sich. **Kein Fix** (Regel 4, kein spekulativer Fix ohne
Root-Cause). **Für künftige Sessions:** Datei-Zuordnung korrigiert —
`mrlib/switchable-button.rkt` + `wx/qt/canvas.rkt`, **nicht** `button.rkt` (das an
DrRackets Toolbar gar nicht beteiligt ist).

**Nativ-Vergleich:** nicht durchgeführt — keine Qt-seitige Anomalie vorhanden, die
einen Differenzvergleich rechtfertigt hätte.

**Commit:** keiner.

---

### Befund 4 — Editor-Canvas-Scrollbars fehlen (`wx/qt/canvas.rkt`)

**Status: geparkt mit negativem Befund (Regel 4) — Fix-Versuch nach expliziter
Nutzer-Freigabe unternommen, Budget in dieser Sitzung ausgeschöpft.**

Ausgangslage: seit Checkpoint C offener Nebenbefund, „bewusst offen" — kein
Scroll-Support in `wx/qt/canvas.rkt`, `do-set-scrollbars`/
`get-virtual-h-pos`/`get-virtual-v-pos` liefen als No-Op-Defaults aus
`canvas-autoscroll-mixin` durch. Dieser Fund berührt architektonisch
`wx/common/canvas-mixin.rkt` (Kompositionsreihenfolge) und war damit klar
Rule-3-Kandidat; die Empfehlung war, ihn wie §21.7/`test-dock-size` zu parken.
Nutzer-Entscheidung: **„Trotzdem in dieser Sitzung versuchen."**

**Architektur (umgesetzt, Kompositions-Diskrepanz gemessen):** Anders als
`wx/win32/canvas.rkt` (eigene Klasse subclassed `canvas-autoscroll-mixin` und
kann dessen No-Op-Defaults direkt überschreiben) sitzt `wx/qt/canvas.rkt`s
`base-canvas%` **unter** `canvas-autoscroll-mixin` in der Komposition — die
No-Op-Methoden sind dort bereits `define/public`, `base-canvas%` selbst kann
sie nicht per `override*` erneut definieren (`public*`/`override*`-Invariante,
`CLAUDE.md` Regel 3). Fix: eine neue Zwischen-Mixin-Schicht
`qt-canvas-scroll-mixin`, rein in `wx/qt/` (kein Shared-Code-Touch), zwischen
`canvas-autoscroll-mixin` und `canvas-mixin` eingefügt; sie implementiert
`do-set-scrollbars`/`reset-dc-for-autoscroll`/`get-virtual-h-pos`/
`get-virtual-v-pos` über eine manuelle Scroll-API, die echte `QScrollBar`-Kinder
via neuen Shim-Primitiven (`shim_scrollbar_create/set_range/set_value/
get_value`, exakter Analogbau zu den bestehenden `shim_slider_*`-Funktionen)
ansteuert.

**Gemessene Regressionen (isolierte Probe, `editor-canvas%` mit
`'(auto-hscroll auto-vscroll)`, 100 Zeilen Testinhalt):**

1. Bei aktivierten Scrollbars bleibt der Editor-Inhalt **komplett weiß** —
   nur ein blinkender Caret oben links ist sichtbar, kein Zeilentext.
2. **Getestet und ausgeschlossen:** Die `get-client-size`-Rahmenreduktion
   (Scrollbar-Dicke wird von der gemeldeten Client-Größe abgezogen) ist
   **nicht** die Ursache — mit vollständig deaktivierter Reduktion (Probe gibt
   Rohgröße zurück) bleibt der Inhalt identisch weiß, bei sonst korrekter
   400×300-Geometrie.
3. **Getestet und ausgeschlossen:** Sichtbarkeit/Z-Order der Scrollbar-Widgets
   selbst ist nicht die Ursache — mit dauerhaft unsichtbar geschalteten
   Scrollbar-Kindern (Widget bleibt aber angelegt) bleibt der Text weiterhin
   unsichtbar; einzige Änderung: der Caret wird sichtbar (vorher augenscheinlich
   nicht, vermutlich Phasenzufall des Blink-Timers).
4. **Gemessen, nicht abschließend erklärt:** `do-set-scrollbars` feuert genau
   **einmal**, sehr früh (Konstruktionszeit, Client-Größe noch beim
   30×30-Platzhalter, degenerierte Werte `h-len=1 v-len=1 h-page=1 v-page=1
   h-pos=0 v-pos=0`) und danach **nie wieder** — auch nicht, nachdem das Canvas
   Sekunden später auf seine reale 400×300-Geometrie wächst (bestätigt: unser
   eigenes `set-size`/`position-scrollbars` feuert zu diesem späten Zeitpunkt
   sehr wohl erneut mit `cw=400 ch=300`, der Editor-eigene
   Content-Scrollbar-Rebuild-Pfad aber nicht). `get-virtual-h-pos`/
   `get-virtual-v-pos` wurden in keinem Testlauf ein einziges Mal aufgerufen —
   der Autoscroll-`view-start`-Pfad, der sie konsumieren sollte, läuft
   offenbar gar nicht an, wenn eine derart degenerierte Scrollrange einmal
   verankert wurde. Naheliegende, aber **nicht verifizierte** Hypothese: die
   früh eingefrorene 1×1-Virtualgröße lässt den Editor-Admin einen leeren
   Content-Bereich annehmen und den eigentlichen Text-Layout-/Paint-Pfad gar
   nicht erst anlaufen (Caret-Malung scheint ein von diesem Pfad unabhängiger
   Code-Pfad zu sein).
5. Zusätzlich beobachtet, nicht root-caused: mit aktivem Scrollbar-Kind lief
   die Paint-/Blit-Schleife der isolierten Probe für die ersten ~200 ms exzessiv
   häufig (¹/₁ₘₛ statt der sonst üblichen ¹/₅₀₀ₘₛ-Taktung), bevor sie sich
   normalisierte — mögliche Zweitursache oder Symptom desselben Problems,
   nicht weiter zerlegt.

**Root-Cause nicht isoliert innerhalb des 2-Hypothesen-Zyklen-Budgets**
(tatsächlich 3 Zyklen verbraucht, s. o.) — Trigger-Reihenfolge zwischen
Qt-nativer Geometrieänderung (läuft außerhalb von Racket-`set-size`) und dem
Editor-eigenen Content-Scrollbar-Rebuild ist der wahrscheinlichste
Ansatzpunkt für eine künftige Session, aber nicht bewiesen.

**Callback-Lifetime-Bug gefunden und gefixt (unabhängig vom obigen, hätte aber
für sich genommen zu Use-after-Free-artigen Symptomen geführt):** die
Scrollbar-`changed`-Callbacks wurden ursprünglich als Inline-Lambda direkt an
`shim_scrollbar_create` übergeben, statt (wie bei `mouse-cb`/`key-cb`/
`focus-cb`/`slider.rkt`s `changed-fn`) zuerst an ein Objektfeld gebunden zu
werden — ohne Racket-seitigen Owner ist die Lebensdauer der Closure nicht
garantiert. **Dieser Fix ist mit dem Revert unten mit entfernt worden** (er
existierte nur innerhalb des jetzt zurückgerollten Scrollbar-Codes) und muss
in einer künftigen Fix-Session erneut angewendet werden — als Konvention
festgehalten, nicht nur als Fußnote.

**Entscheidung (nach Rücksprache mit Architektur-Review):** Canvas.rkt
vollständig auf den Sitzungsanfang zurückgesetzt (`git checkout` im
gui-Submodul) — ein weißer, unscrollbarer, aber **korrekt Text anzeigender**
Editor schlägt einen Editor mit sichtbaren, aber funktional die
Textdarstellung zerstörenden Scrollbars. Die additiven, für sich genommen
harmlosen Shim-Primitiven (`shim_scrollbar_create/set_range/set_value/
get_value` in `qt-shim/src/shim.cpp`, korrespondierende FFI-Deklarationen in
`wx/qt/utils.rkt`) bleiben **bestehen** (unbenutzt, ungefährlich, exakt nach
dem Muster der bestehenden `shim_slider_*`-Funktionen) — Grundlage für einen
künftigen zweiten Anlauf, kein weiterer Shim-Rebuild nötig.

**Nativ-Vergleich:** nicht durchgeführt (Fund scheiterte vor Erreichen eines
vergleichsfähigen Zustands).

**Gate-Nachweis nach Revert:** Smoke-Tests 3/3 mit `PLT_QT=1`, 3/3 nativ ohne
`PLT_QT` — beide grün, keine Regression durch die verbliebenen additiven
Shim-/FFI-Änderungen.

**Nebenbefund (inzident entdeckt, nicht Teil dieses Fundes):** ein
grafischer Störeffekt (orange/blau gestreiftes Rechteck nahe dem oberen Rand
des DrRacket-Editor-Fensters) wurde während der Diagnose beobachtet und zunächst
dem neuen Scrollbar-Code zugeschrieben. Per `git stash` bei vollständig
scrollbar-freiem Code **identisch reproduziert** — **beweist: vorbestehender,
unabhängiger Bug**, kein Bezug zu diesem Fund. Root-Cause nicht untersucht
(außerhalb des Scopes dieser Sitzung); für eine künftige Session vorzumerken.

**Commits:** gui-Submodul (nur additive `utils.rkt`-FFI-Deklarationen, kein
`canvas.rkt`-Bezug, s. u.); Umbrella (nur additive `shim.cpp`-Scrollbar-
Primitiven).

---

## Fortsetzung 2026-09-12 — Phase 2 (Preferences-Sweep) + Phase 3 (Regressions-Gate)

**Ausgangslage:** Phase 0/1 waren zum Sessionende 2026-09-11 vollständig committet,
gepusht und synchron (`git status` beider Repos clean, Submodul exakt auf
`origin/qt-backend@7d1231e0`). Diese Fortsetzung deckt Phase 2 + 3 des Prompts ab.

### Vorbereitung

- **CLAUDE.md-Nachtrag:** die in Phase 0 angekündigte PATH-Korrektur der Windows-
  Run-Rezepte war entgegen der Session-Notiz **nicht** in `CLAUDE.md` gelandet (bare
  `racket ...` stand weiterhin da, `racket` ist nach wie vor nicht im Machine-/User-PATH,
  verifiziert per `[Environment]::GetEnvironmentVariable`). Nachgeholt: Windows-Run-Rezept
  ergänzt um einen Hinweis + `C:\Program Files\Racket` im gezeigten `$env:PATH`.
- **Backup `racket-prefs.rktd`** vor jeder Interaktion (SHA-256 gehasht, Kopie im
  Scratchpad) — Notwendigkeit hat sich bestätigt (s. u.).

### Methode

Zwei DrRacket-Starts insgesamt (nicht pro Kategorie): einmal nativ (kein `PLT_QT`) als
Referenz, einmal unter `PLT_QT=1`. Automatisierung: PowerShell + .NET
(`FindWindow`/`EnumWindows` über Fenstertitel statt `MainWindowHandle` — letzteres zeigte
sich als unzuverlässig, sobald ein Dialog ein eigenes Top-Level-Fenster ist, s. Fund
unten), Klicks über absolute Fenster-Offsets, `SetForegroundWindow` +
`GetForegroundWindow`-Verifikation vor jeder Eingabe (wie am 2026-09-11 etabliert).
Zuerst die native Kategorie-/Subtab-Struktur vollständig referenz-fotografiert, danach
erst der Qt-Durchlauf — Kategorienliste (9 Tabs: Font, Colors, Editing, Warnings, General,
Profiling, Browser, Tools, Background Expansion) auf beiden Seiten **identisch**, keine
fehlende Kategorie.

**Automatisierungs-Fund (methodisch, kein Produktbefund):** ein Preferences-Dialog ist ein
eigenes Top-Level-Fenster, nicht das `MainWindowHandle` des `drracket`-Prozesses — ein
Screenshot-/Klick-Helper, der über `Get-Process -MainWindowHandle` auflöst, trifft dann
das falsche (oder ein verdecktes) Fenster. Helper auf `EnumWindows`+Fenstertitel-Suche
umgestellt (`winutil.ps1`, Scratchpad). Zusätzlich bestätigt: ein neuer PowerShell-Prozess
zwischen „Menü öffnen" und „Menüpunkt klicken" lässt das offene Menü durch Fokusverlust
zuklappen — Menü-Navigationsschritte müssen in **einem** ununterbrochenen Skript-Aufruf
laufen.

### Phase 2 — Bestandsaufnahme der sechs Kategorien

Kriterium wie im Prompt: Funktion/Vollständigkeit, nicht Pixelgleichheit.

| Kategorie | Sub-Tabs | Ergebnis |
|---|---|---|
| **Editing** | Indenting, Square Bracket, General Editing, Racket | Vollständig funktional. Alle Listboxen (Begin-/Define-/Lambda-/For-fold-/Letrec-/Local-/Cond-like Keywords) inhaltsgleich zu nativ, `Add`/`Remove`-Buttons vorhanden, `Extra regexp`-Textfelder korrekt befüllt. Checkbox „Automatically adjust opening square brackets" korrekt in beiden Sub-Tabs (Square Bracket **und** Racket) vorhanden. **Bemerkenswert:** General Editing → „Maximum character width guide"-Textfeld zeigt korrekt den **deaktivierten** (ausgegrauten) Zustand, wenn die zugehörige Checkbox unchecked ist — Disabled-State-Weiterleitung funktioniert. Keine Befunde. |
| **Warnings** | — | 7 Checkboxen, Check-Zustände 1:1 identisch zu nativ (`Ask about normalizing strings`/`Ask about clearing test coverage`/`Show the 'evaluation terminated' dialog` an, Rest aus). Keine Befunde. |
| **General** | — | Slider „Number of recent items" zeigt den Zahlenwert („50") — bestätigt, dass der Befund-1-Fix (§24.2, Font-Size-Slider) sich auf **alle** `slider%`-Instanzen verallgemeinert, nicht nur den Font-Tab. Alle Checkboxen + zwei Radio-Gruppen („Automatically Reload Changed Files", „Printing Mode") korrekt. Keine Befunde. |
| **Profiling** | — | Selbstgemalte Farbverlaufs-Leiste („Profiling Color Range", Grün→Rot-Gradient mit überlagertem Beispieltext `(define (whee) (whee))`) rendert korrekt — bestätigt, dass benutzerdefiniertes `on-paint`-Zeichnen auf einem `canvas%` unter Qt funktioniert. „Low"/„High"-Farbwahl-Buttons + Radiogruppe „Profiling Color Scale" korrekt. Keine Befunde. |
| **Tools** | — | Listbox mit 20 Einträgen (scrollbar, geprüft: Scrollen per Mausrad funktioniert, alle Einträge erreichbar), Klick auf einen Eintrag (`Optimization Coach`) selektiert korrekt **und** aktualisiert das zugehörige `Tool:`-Textfeld live (`(lib "optimization-coach/tool.rkt")`) — Listbox→Textfeld-Sync funktioniert. Radiogruppe „Load the tool when DrRacket starts?" korrekt. Keine Befunde. |
| **Background Expansion** | — | Checkbox + zwei weitere Checkboxen korrekt, drei `choice%`-Dropdowns (Show read-level/unbound-identifier/other errors) korrekt befüllt (`in the margin`/`with gold highlighting`); Dropdown-Popup öffnet und schließt sauber bei Klick (funktional getestet). Keine Befunde. |

**Ergebnis Phase 2 (Kern):** Von den sechs Kategorien zeigt **keine** einen funktionalen
Defekt (fehlendes/unbedienbares Control, falscher Wert, kaputter Zustandsabgleich). Alle
Control-Typen, die in den §21.6-Einzelbefunden problematisch waren (`slider%` ohne
Readout, `panel%` ohne Rahmen), sind in den Phase-1-Fixes bereits mit abgedeckt — dieser
Sweep bestätigt das für zusätzliche Instanzen (General-Tab-Slider) und deckt keine neue
Instanz derselben Klasse auf.

### Phase 2 — Neuer Befund: Preferences-Dialog öffnet mit unerreichbarer Button-Zeile

**Status: gemessen, keinem `wx/qt`-lokalen Fix zugeführt — geordnet als weitere
Ausprägung des bereits geparkten §21.7 (Resize/Reflow-Bug), Triage-Regel 4 analog
angewendet (kein spekulativer Fix an einer Shared-Code-Root-Cause).**

**Beobachtung:** Beim allerersten Öffnen von Edit → Preferences unter `PLT_QT=1`
(unveränderte Fenstergröße, kein manueller Resize durch den Nutzer/die Automatisierung)
misst `GetWindowRect` **1076×741**. Bei dieser Größe sind „OK"/„Undo Changes and
Close"/„Revert All Preferences to Defaults" **nicht sichtbar** — der untere
Fensterbereich ist stattdessen unbemalt/schwarz. Nativ (win32, kein `PLT_QT`) öffnet
derselbe Dialog bei **724×567** mit allen drei Buttons sichtbar.

**Gemessen (3 Diagnoseschritte, kein neuer Zyklus nötig):**
1. Minimieren+Restore ändert nichts (schließt einen reinen Stale-Paint-Cache-Fall aus).
2. Programmatisches Vergrößern (`MoveWindow` auf 900×1000) macht „OK" und „Revert All
   Preferences to Defaults" bei fester Pixelposition (~y=751 relativ zum Fenster-Client)
   sichtbar — unabhängig von der tatsächlichen Fensterhöhe.
3. **Klick-Test gegen das unveränderte 1076×741-Fenster** (frischer Neustart, kein
   vorheriger Resize): Klick auf die proportional zur nativen Button-Position
   umgerechnete Koordinate (698, 714) schließt den Dialog **nicht**. Da die in Schritt 2
   gemessene feste Position (~y=751) **größer** ist als die Default-Fensterhöhe (741),
   liegt die Button-Zeile beim Erststart vollständig **außerhalb** des sichtbaren
   Client-Bereichs — nicht bloß unbemalt-aber-klickbar. Der schwarze Bereich am unteren
   Fensterrand ist damit vermutlich ein separates, nicht weiter untersuchtes
   Render-Artefakt und **kein** Beleg für „vorhanden, nur ungezeichnet"; Schritt 3 belegt
   nur, dass an dieser Stelle nichts Klickbares liegt.

   Das deckt sich mit der in §21.7 dokumentierten Root Cause: Kind-Controls behalten die
   beim letzten `set-size` berechnete **absolute** Position; da der native
   `resizeEvent`-Pfad seit dem §21.7-Rollback **komplett unverdrahtet** ist, reflowen sie
   nie relativ zur tatsächlichen Fenstergröße. Neu an diesem Befund ist, dass bereits die
   **initiale** Default-Größe dieses Dialogs unter Qt (1076×741) kleiner ist als die
   Position der Button-Zeile (~751 px) — die Zeile ist damit **beim allerersten Öffnen**,
   ganz ohne jede Nutzerinteraktion, unerreichbar (weder sichtbar noch klickbar), bis
   jemand das Fenster manuell vergrößert. Root-Cause-Cluster: identisch zu §21.7, keine
   neue Fehlerklasse.

**Bewusst nicht verfolgt:** ein Fix würde entweder (a) §21.7s Live-Resize-Verdrahtung
selbst reparieren (der dort dokumentierte, zweimal zurückgerollte, riskante Weg) oder
(b) die initiale Seed-Size dieses spezifischen Dialogs korrigieren (Shared Code:
`framework`s Preferences-Dialog-Konstruktion, nicht `wx/qt/`-lokal) — beides fällt unter
die explizite OUT-OF-SCOPE-Klausel für §21.7 in dieser Session. Kein Fix-Versuch.

**Funktionale Einordnung für die Bestandsaufnahme:** dieser Befund ist **kategorieübergreifend**
(betrifft die Preferences-Dialog-Hülle, nicht eine der sechs Sweep-Kategorien selbst) und
wurde daher oben in der Kategorien-Tabelle nicht mitgezählt — er beeinträchtigt potenziell
**alle** neun Tabs gleichermaßen (die Button-Zeile ist unabhängig vom aktiven Tab
betroffen). Für den Sweep selbst wurde die Qt-Fensterrahmengröße einmalig auf 1076×860
vergrößert (Button-Zeile dadurch erreichbar), um alle Kategorien testen zu können.

### Betriebsdisziplin-Fund: `racket-prefs.rktd` änderte sich trotz „Undo Changes and Close"

Nach Abschluss des Qt-Durchlaufs (Dialog über „Undo Changes and Close" geschlossen, keine
inhaltliche Einstellung bewusst verändert) unterschied sich der SHA-256-Hash von
`racket-prefs.rktd` vom Backup-Hash. Wahrscheinlichste Ursache: die programmatischen
`MoveWindow`-Aufrufe während der Diagnose des Button-Zeilen-Befunds lösten (wie bei
`framework`-Fenstern häufig) eine **sofortige**, nicht erst bei OK greifende Persistierung
der Dialog-Fenstergröße aus — „Undo Changes and Close" bezieht sich nur auf
Preference-**Werte**, nicht auf Fenstergeometrie. **Kein Sicherheitsproblem** (Backup
griff wie geplant), aber ein Hinweis für künftige Sessions: Fenstergeometrie-Manipulation
an Preferences-artigen Dialogen zählt zum selben Diszipilnrisiko wie Tippen im
Definitions-Puffer und braucht denselben Hash-Vergleich/Restore-Schutz. Backup vor dem
Regressions-Gate zurückgespielt (Hash danach wieder identisch zum Vor-Sweep-Stand).

### Phase 3 — Regressions-Gate

- `raco test tests/smoke.rkt` unter `PLT_QT=1`: **3/3 grün**.
- `raco test tests/smoke.rkt` **ohne** `PLT_QT`: **3/3 grün** (Nativ-Gate weiterhin
  bestanden — der 9.3-Link hält).
- **Die fünf htdp-Proben aus 0.10 wurden in dieser Fortsetzung bewusst nicht erneut
  gelaufen:** `git status` in Umbrella **und** Submodul zeigt für die gesamte Phase 2
  ausschließlich `CLAUDE.md` (PATH-Nachtrag) als Änderung — kein `wx/qt/`-, `shim.cpp`-
  oder `gui-lib`-Byte hat sich seit der in Phase 0 gemessenen Baseline verändert. Ohne
  Code-Diff kann keine Regression gegenüber der 0.10-Baseline entstanden sein; ein
  vollständiger Proben-Rerun hätte nur Automatisierungszeit gekostet, ohne neue
  Aussagekraft. Diese Begründung wird hier explizit festgehalten, damit sie in der
  nächsten Session nachvollziehbar ist.
- **Musterabgleich über alle Befunde dieser Sitzung (2026-09-11 + Fortsetzung):** die
  drei in Phase 1 gefixten Befunde (Font-Slider, Colors-Rahmen) und die zwei in Phase 2
  bestätigten Negativ-/Ausschluss-Befunde (Toolbar-Timing nicht reproduziert,
  Editor-Scrollbars geparkt) haben **keine** gemeinsame Root-Cause — mit einer Ausnahme:
  der neue Button-Zeilen-Befund aus Phase 2 und der bereits bekannte §21.7 sind **dieselbe**
  Ursache, keine zwei getrennte Funde.

### Nachtrag 2026-09-12 (Teil 2) — Colors-Tab „rechte Spalte" (§21.6 Punkt 4, Rest) — bestätigt real, root-caused: dieselbe Ursache wie §24.5 (Editor-Canvas-Scrollbars), geparkt

**Korrigiert eine erste, zu früh gezogene Schlussfolgerung dieser Sitzung (s. u.).**
**Status: Root-Cause gefunden (Shared Code, identisch zu §24.5) — kein Fix-Versuch,
konsistent mit der bereits für §24.5/den Scrollbar-Block geltenden Parken-Entscheidung
dieser Sitzung.**

**Ausgangspunkt:** §21.6 Punkt 4 (2026-07-13) beschrieb: „Pro Stil sollte ein
Button+Checkbox ('Revert...') in einer rechten Spalte stehen — fehlt komplett." Der
Rahmen-Teil desselben Punkts wurde am 2026-09-11 gefixt (§24.3); die „rechte Spalte"
blieb unbearbeitet.

**Erster Durchlauf (fehlerhaft, hier zur Nachvollziehbarkeit dokumentiert):** alle 7
Colors-Sub-Tabs nativ und unter Qt oberflächlich verglichen (jeweils nur der ohne
Scrollen sichtbare, obere Teil jedes Panels) — beide Seiten zeigten identischen Inhalt,
woraus vorschnell „Kontrollstruktur existiert nicht mehr, kein Defekt" gefolgert wurde.
**Fehler:** beide Seiten starten mit demselben Scroll-Zustand (ganz oben) — ein reiner
Oberflächen-Vergleich beweist nichts über Inhalt, der erst durch Scrollen erreichbar
wäre. Diese erste Schlussfolgerung war falsch und wird hiermit zurückgezogen.

**Korrigierte Messung:** die „Color Schemes"-Unterseite (Colors → Color Schemes) ist
ein `vertical-panel%` mit Stil `'(auto-vscroll)` (`framework/private/color-prefs.rkt:1267-1270`)
und enthält am Ende, nach allen Schema-Einträgen (Classic/Modern/Tol's-Varianten/White
on Black/Tol's White on Black), eine Zeile mit drei Buttons: **„Revert Colors to Color
Scheme's Default Colors"**, **„Design Your Own Color Schemes"**, **„Style & Color
Names"** (`color-prefs.rkt:1410-1420`, `revert-button%`) — das ist die in §21.6
beschriebene Kontrollstruktur.

- **Nativ (win32):** über den panel-eigenen vertikalen Scrollbar (sichtbar bei
  ausreichender Fensterhöhe, funktionsfähig per Klick auf den Bahnbereich unterhalb des
  Thumbs) erreichbar — alle drei Buttons sichtbar und anklickbar.
- **Unter `PLT_QT=1`:** dieselbe Stelle **unerreichbar**, auf drei unabhängigen Wegen
  geprüft: (1) Fenster vergrößern — bringt nichts, weil der Panelinhalt wegen §21.7
  (Resize/Reflow, native `resizeEvent`-Verdrahtung fehlt) seine ursprüngliche, kleine
  Größe behält, unabhängig von der Fenstergröße; (2) Klick auf die Stelle, an der nativ
  der Scrollbar-Track liegt — keine Reaktion, kein sichtbarer Scrollbar-Thumb im
  Screenshot; (3) Mausrad über dem Panel-Hintergrund — keine Reaktion. Die drei Buttons
  sind unter Qt **an keiner erreichbaren Stelle** sichtbar oder klickbar.

**Root-Cause (Code gelesen, Rule 3/Shared-Code-Fall):** `'(auto-vscroll)`-Panels rufen
in `wxpanel.rkt` (geteilter Code, `adjust-panel-size`/`panel-redraw`) unbedingt
`(send this show-scrollbars ...)` und `(send this set-scrollbars ...)` auf. Diese beiden
Methoden sind **backendübergreifend nur in den jeweiligen `canvas.rkt`-Dateien** definiert
(`wx/win32/canvas.rkt`, `wx/gtk/canvas.rkt`, `wx/cocoa/canvas.rkt`, `wx/qt/canvas.rkt`)
sowie in `wx/common/canvas-mixin.rkt` (`set-scrollbars`/`do-set-scrollbars`, die
geteilten Basismethoden) — **exakt dieselben Methoden, die §24.5 (Editor-Canvas-
Scrollbars) bereits als unter `wx/qt` nicht funktionsfähig identifiziert hat**
(`wx/qt/canvas.rkt:307`: `(define/public (show-scrollbars h? v?) (void))`, No-Op).
`wx/qt/panel.rkt` und `wx/qt/window.rkt` definieren **keine** dieser Methoden selbst —
anders als bei einem reinen No-Op-Stub (wie in `canvas.rkt`) würde ein Aufruf auf einem
Objekt ohne diese Methode normalerweise mit „no such method" abstürzen; da die
Preferences-Dialoge aber ohne Absturz öffnen, wird der scroll-aktivierende Codepfad in
`adjust-panel-size` unter Qt offenbar gar nicht erst betreten (`can-scroll-x?`/
`can-scroll-y?` greifen nicht) — der genaue Dispatch-Pfad wurde **nicht bis ins Detail
nachverfolgt** (würde Instrumentierung brauchen), aber der praktische Effekt ist
identisch zu §24.5: Inhalt, der auf `'(auto-vscroll)`/Scrollbars angewiesen ist, wird
unter `wx/qt` unerreichbar, ohne Absturz und ohne sichtbaren Scrollbar.

**Entscheidung (konsistent mit §24.5):** kein Fix-Versuch in dieser Sitzung. §24.5 hat
für exakt diese Methodenfamilie bereits drei Hypothesen-Zyklen verbraucht, einen
Fix versucht und wegen einer schwereren Regression (weißer, unlesbarer Editor-Inhalt)
zurückgerollt — ein erneuter Versuch an einer zweiten Stelle mit derselben Root-Cause
wäre nur eine Wiederholung desselben bereits gescheiterten Wegs. Beide Befunde
(Editor-Canvas-Scrollbars, §24.5, und diese Colors-Tab-„rechte Spalte") sind
**dieselbe offene Architektur-Lücke** (fehlende `wx/qt`-Scrollbar-Unterstützung für
`'(auto-vscroll)`/`canvas-mixin`-basierte Inhalte) mit zwei unabhängigen
Reproduktionsfällen — für die künftige dedizierte Scroll-Session sind jetzt zwei statt
einem Testfall dokumentiert.

**Methodische Lehre (für künftige Sweeps):** ein oberflächlicher Vergleich zweier
scrollbarer Bereiche, die beide im selben (ungescrollten) Zustand geöffnet werden, kann
identisch aussehen, obwohl der Scroll-Mechanismus selbst komplett unterschiedlich
funktioniert (oder gar nicht funktioniert). Bei jedem `'(auto-vscroll)`/`'(vscroll)`-
artigen Panel muss aktiv bis zum Ende gescrollt werden, bevor „kein Unterschied"
geschlossen werden darf.

**Automatisierungs-Nebenfund:** nach mehrfachem hartem `taskkill /F` zeigte DrRacket
(nativ **und** Qt) beim nächsten Start den bekannten Autosave-Recovery-Dialog
(„Restore open files from previous session?", §13). Unter nativ ließ sich „No" erst im
zweiten Klickversuch treffen; unter Qt registrierte ein synthetischer Mausklick auf
denselben Button in einem Durchlauf **gar nicht** (mehrere Versuche, Cursor-Position
verifiziert korrekt), `{ESC}` per `SendKeys` schloss den Dialog dort dagegen sofort — in
einem späteren Durchlauf half umgekehrt der Mausklick, `{ESC}` nicht. Nicht weiter
verfolgt (reine Automatisierungsnotiz, kein Produktbefund, uneinheitlich genug, dass
keine allgemeine Regel daraus folgt außer „beide Wege bereithalten").

**Betriebsdisziplin:** `racket-prefs.rktd` änderte sich durch mehrere DrRacket-Starts
dieser Teilinvestigation (erneut bestätigt: Zustand wird unabhängig vom
Dialog-Ergebnis geschrieben) — jedes Mal aus dem Sitzungsbackup zurückgespielt, Hash
danach wieder auf dem Ausgangsstand.

**Kein Commit** — Root-Cause ist Shared Code, Fix explizit nicht versucht (s. o.).

### Nachtrag 2026-09-12 (Teil 3) — Stretch-Ziel: `test-dock-size`-Crash, `is-shown?`-Divergenz präzise lokalisiert (nur Messung, kein Fix)

**Auf Nutzerwunsch, nach `AskUserQuestion` (Regel 7).** Prompt-Vorgabe: nur messen,
welcher der beiden `on-tab-change`-Eingänge (`test-engine:test-window:docked?` oder
`(send test-panel is-shown?)`) zwischen Qt und nativ divergiert — Fix bleibt in jedem
Fall out of scope.

**Versuch, live zu instrumentieren — blockiert:** `test-tool.rkt`
(`htdp-lib/test-engine/`, **außerhalb** des Forks, unter
`C:\Program Files\Racket\share\pkgs\...`) hätte für Debug-Ausgaben editiert werden
müssen; die aktuelle Shell ist nicht elevated, Schreibzugriff auf `Program Files`
schlug mit `EPERM` fehl (derselbe Elevation-Bedarf wie beim `raco pkg update --link`
aus Phase 0). Backup der Original-Datei + kompilierten `.zo`/`.dep` vorsorglich im
Scratchpad angelegt, dann per `AskUserQuestion` beim Nutzer nachgefragt: Live-Diagnose
(bräuchte eine elevierte Shell von ihm) vs. statischer Code-Befund als Ergebnis. Nutzer
wählte den statischen Befund — kein elevierter Zugriff angefordert, `test-tool.rkt`
unverändert (per erneutem `Read` bestätigt, kein Teil-Schreibvorgang hinterlassen).

**Statischer Befund (eindeutig, keine Instrumentierung nötig):**
`wx/qt/panel.rkt:58` überschreibt `is-shown?` unbedingt auf `#t`:
`(define/override (is-shown?) #t)`. `wx/win32/panel.rkt` überschreibt `is-shown?`
**nicht** — win32s `panel%` erbt die Basisimplementierung aus `wx/win32/window.rkt`
unverändert: per Grep bestätigt ein echtes, dynamisches Feld (`(define shown? #f)`,
Zeile 284, per `set!` bei Show/Hide aktualisiert, Zeile 287; `is-shown?`, Zeile 327/328,
gibt exakt dieses Feld zurück). Dass es dort auch tatsächlich den realen Zustand trägt,
bestätigt zusätzlich §23s Laufzeit-Messung: nativ durchläuft `on-tab-change` bei der
1→2-Tab-Sequenz nie den `remove`/`undock-tests`-Pfad (0/10 Crashes, alle drei
Plattformen) — konsistent mit einem dort tatsächlich `#f` liefernden `panel-shown?`.
`test-panel%`
(`htdp-lib/test-engine/test-tool.rkt:220`, ein reines `vertical-panel%` ohne eigene
`is-shown?`-Override) erbt diese Backend-Divergenz durch. Damit ist `on-tab-change`s
`panel-shown?` unter Qt strukturell **immer** `#t`, unter win32 spiegelt es die
Realität — exakt die im Prompt vermutete Divergenzklasse, jetzt auf eine einzelne
Zeile lokalisiert.

**Korrigiert einen Teil der §23-Vorarbeit:** der dortige „Read-only-Nachtrag" hatte nur
die **Basis**-`window%`-Implementierung von `is-shown?` verglichen (beide Backends:
einfache, echte Flags, kein Unterschied — das stimmt weiterhin) und dabei nicht
geprüft, ob einzelne Widget-Typen diese Basismethode überschreiben. Genau dort liegt
die tatsächliche Divergenz. Dieselbe unbedingte `#t`-Überschreibung findet sich
zusätzlich in praktisch jeder anderen `wx/qt`-Widget-Klasse außer `canvas%`/`frame%`
(`list-box.rkt`, `tab-panel.rkt`, `slider.rkt`, `radio-box.rkt`, `group-panel.rkt`,
`button.rkt`, `choice.rkt`, `check-box.rkt`, `message.rkt`) — ein systematisches Muster
aus der additiven Spike-Phase, nicht nur an dieser einen Stelle.

**Ergebnis:** „Befund ist lokal und klein" trifft zu — **nicht** das riskantere
Pump-Modell (`wx/qt/queue.rkt`, §23s zweite, unverifizierte Hypothese). Kein Fix in
dieser Sitzung (Diagnose-Charakter, wie vorgegeben). Details/vollständige Einordnung:
`docs/HACKING.md` §23.3.

### Zusammenfassung Fortsetzung 2026-09-12

- Phase 2: sechs Kategorien durchgesehen, **keine** neuen `wx/qt`-lokal fixbaren Defekte.
- Ein neuer, präzise vermessener Befund (Preferences-Button-Zeile initial unerreichbar)
  wurde dem bestehenden §21.7-Cluster zugeordnet, nicht neu bearbeitet (OUT OF SCOPE
  bleibt OUT OF SCOPE, auch bei neuen Symptomen derselben Ursache).
- **Teil 2 (auf Nutzerwunsch):** letzter offener Rest von §21.6 Punkt 4 (Colors-Tab
  rechte Spalte) untersucht — **bestätigt real** (nicht wie zunächst vorschnell
  angenommen „nicht reproduzierbar"), root-caused als **dieselbe Ursache wie §24.5**
  (Editor-Canvas-Scrollbars: `'(auto-vscroll)`/`canvas-mixin`-Scrollbar-Methoden unter
  `wx/qt` nicht funktionsfähig) — kein neuer Fix-Versuch, konsistent mit der bereits für
  §24.5 getroffenen Parken-Entscheidung dieser Sitzung. Zwei Reproduktionsfälle für
  denselben offenen Scroll-Block statt einem.
- **Teil 3 (Stretch-Ziel, auf Nutzerwunsch nach `AskUserQuestion`):** `test-dock-size`-
  Crash — `is-shown?`-Divergenz auf eine einzelne Zeile lokalisiert (`wx/qt/panel.rkt:58`,
  hartcodiertes `#t`, statt der echten `shown?`-Basisimplementierung wie unter win32).
  Live-Instrumentierung an `test-tool.rkt` (htdp-lib, außerhalb des Forks) an fehlenden
  Admin-Rechten gescheitert; Nutzer entschied sich für den bereits eindeutigen
  statischen Befund statt elevierter Diagnose. Ergebnis: „lokal und klein" bestätigt,
  nicht das riskantere Pump-Modell — kein Fix in dieser Sitzung. Details: `docs/HACKING.md` §23.3.
- `CLAUDE.md`-PATH-Nachtrag aus Phase 0 nachgeholt.
- Phase 3: beide Regressions-Gates grün, kein Code seit der 0.10-Baseline verändert.
- **Keine Commits in dieser Fortsetzung** (nur Dokumentation: dieser Report,
  `docs/HACKING.md` §23.3/§25, `STATUS.md`, `CLAUDE.md`) — kein Submodul-Push nötig,
  keine Sync-Rückfrage (Regel 7) fällig, da keine Repo-Zeiger sich ändern.

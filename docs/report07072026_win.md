# Beobachtung — Menüleisten-/Redraw-Diagnose auf Windows (Phase 3, prompt07072026)

**Datum:** 2026-07-07
**Plattform:** Windows 11 Enterprise, x86-64
**Racket:** v9.2 [cs] · **Qt:** 6.11.0 (`C:\Qt\6.11.0\msvc2022_64`)
**Repro:** `examples/menu-frame.rkt` (frame% + menu-bar% + menu% + menu-item% + editor-canvas% + text%)
**Startrezept:** `PLT_QT=1` + Qt-`bin` in PATH; Fork ist **verlinktes** Paket → plain `racket examples/menu-frame.rkt` (kein `-S` nötig).

> Reine Diagnose — kein Fix, kein Geometrie-/Rendering-Eingriff. Screenshots lagen im
> Session-scratchpad (out-of-band an den Nutzer, NICHT im Repo; anschließend gelöscht).

## Re-Sync-Status (Phase 0)

- **Kein Re-Sync nötig** — der 1.78→1.80-Merge ist auf DIESER Maschine entstanden und bereits
  gepusht. Umbrella `main` sauber, up-to-date mit `origin/main`; gui-Submodul auf `qt-backend`
  @ `381425d5`, clean; Submodul-Zeiger == lokaler gui-HEAD (keine Divergenz).
- `gui-lib/info.rkt` version = **1.80**; Merge-Commit `2d6325d9` + `381425d5` in der Historie.
- Konsum-Modell auf dieser Maschine: **Installation-wide Link** (`raco pkg show gui-lib` →
  `link C:\src\racket_qt\third_party\gui\gui-lib`), **nicht** `-S`-Source-Override wie macOS/Linux.
  Ein Rebuild liefe hier daher über `raco setup gui-lib` — war aber nicht nötig (kein Sync).
- **Keine neuen Commits** durch Phase 0/3 (reine Verifikation + Beobachtung).

## A — Minimal-Repro `examples/menu-frame.rkt` — vier Beobachtungspunkte

Auf Windows konnten Punkt 2/4 mit **echten Tastatur-Events** (Win32 `SendKeys`) getrieben
werden — anders als macOS/Linux, die mangels OS-Input-Tool auf programmatisches `insert`
zurückgriffen. Capture via `PrintWindow` (occlusionsfrei) + gegengeprüft mit echtem
Bildschirm-Capture (identisch → kein Capture-Artefakt).

### 1. Menüleiste sichtbar? Wo?
**NEIN.** Zwischen der Fenster-Titelleiste („E-0 Menu Test") und dem `editor-canvas%` gibt
es keinen Menü-Balken; der Titel „File" erscheint nirgends, kein reservierter Leerraum. Der
Editor beginnt unmittelbar unter der Titelleiste — konsistent mit „QMenuBar hat Höhe 0",
nicht mit „Balken da, aber leer". Statisch wie nach dem Tippen unverändert. Deckt sich mit
dem Linux-Befund (Balken komplett abwesend, Höhe 0).

### 2. Öffnet ein Klick einen Top-Level-Titel?
Nicht prüfbar — es existiert kein sichtbarer/anklickbarer Balken. Der Bereich, in dem der
Balken läge, gehört dem Editor. (Wie macOS/Linux: nichts anzuklicken.)

### 3. Rendering-Artefakte im oberen Bereich?
**KEINE** im Menü-Bereich der Minimal-Konstellation — keine Überlappung, keine doppelten
Elemente, keine weißen Rechtecke. Der Balken ist schlicht abwesend/auf 0 kollabiert.

### 4. Zeichnet der zentrale editor-canvas% sauber (beim Tippen)?
**NEIN — partielles Neuzeichnen.** Statisch (nur ein `insert`) sah „Hello from Qt + menu!"
sauber aus. Nach echten Keystrokes über mehrere Zeilen (`ABCDEFG`↵ `second line typed`↵
`third line`↵ `wwww xxxx yyyy zzzz`↵) ist **nur die zuletzt getippte Zeile** sichtbar,
**mittig im Fenster schwebend**, mit weißem Hintergrund-Band **nur um diese eine Zeile**.
Alle früheren Zeilen — inkl. der vorher getippten — sind **verschwunden / nicht neu
gezeichnet**; darüber und darunter bleibt der Canvas dunkel. Deutet auf: nur die aktuelle
Damage-/Caret-Zeile wird gemalt, kein persistenter Backing-Store des gesamten Editor-Bereichs.

## B — Echtes DrRacket (nur Windows, Fork bereits verlinkt)

`PLT_QT=1 DrRacket.exe` gestartet, „Untitled"-Fenster erfasst (PrintWindow + Bildschirm,
identisch). Danach graceful via WM_CLOSE geschlossen (kein Hard-Kill → keine Autosave-Recovery).

- Oben links: **überlappender, verstümmelter Text** — mehrere Menütitel („Untitled",
  „Information", …) an derselben Origin gestapelt statt horizontal ausgelegt.
- Zusätzlich ein **freistehendes weißes Rechteck** rechts daneben.
- **Kein** horizontaler File/Edit/View-Balken über die Fensterbreite; darunter die Tab-Leiste
  („1: Untitled ×") + „+"-Button.

## Schlüssel-Interpretation — für die Fix-Session

- **Menü: zwei Fehlermodi, eine gemeinsame Ursache wahrscheinlich (aber offen).**
  - `menu-frame.rkt` (1 Menü): Balken **wird gar nicht gezeichnet** → **valider, isolierter
    Minimal-Repro** des fehlenden Balkens. Konsistent mit der Linux-Hypothese „QMenuBar
    bekommt nie Höhe > 0 im QMainWindow-Layout" und der plattformübergreifenden These aus
    dem Linux-Bericht (gegen den macOS-Verdacht „plattformspezifisch").
  - DrRacket (viele Menüs): Balken **rendert, ist aber korrupt** — mehrere Titel an gleicher
    Origin überlappend + weißes Rechteck. **Zusatzsymptom**, das erst mit DrRackets vollem
    Widget-Baum auftritt.
  - Der Minimal-Repro wird **nicht** verworfen; er beweist, dass die nackte Balken-Darstellung
    bereits kaputt ist. Offene Kernfrage: **ein Bug oder zwei?** Stärkste Spur (zeigt AUF die
    Balken-Geometrie): mehrere Titel fallen offenbar auf **dieselbe x-Origin** (Überlappung
    statt horizontaler Auslegung), im Minimal-Repro wird der eine Titel gar nicht platziert.
- **Redraw-Befund cross-Plattform bestätigt — und mit echten Keystrokes verschärft.** Das
  „früherer Text verschwindet + vertikaler Versatz"-Muster aus den macOS-/Linux-Berichten
  tritt auf Windows mit **echten** Tastatur-Events auf und ist hier noch deutlicher: **auch
  bereits getippte Zeilen** verschwinden, nur die aktuelle Zeile rendert. Das stützt einen Bug
  im gemeinsamen `editor-canvas%`/`text%`-Redraw-Pfad (bzw. dessen Zusammenspiel mit dem
  Qt-Shim / fehlendem Backing-Store-Persist), nicht einen Plattform-Sonderfall. Zweiter
  isolierter Repro für die Fix-Session.

## Bekannte Einschränkung dieser Session

- Punkt 2 (Klick auf Menütitel) bleibt gegenstandslos, solange kein Balken sichtbar ist —
  auf allen drei Plattformen offen bis der Rendering-Fix greift.
- SetForegroundWindow wurde von Windows teils blockiert (Fremd-Prozess); Capture daher über
  `PrintWindow` statt Vordergrund-Bildschirmschuss — für die Diagnose gleichwertig
  (gegengeprüft), aber Fokus-Steuerung war fragil.

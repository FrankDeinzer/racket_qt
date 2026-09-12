# CLAUDE.md — racket-qt

Qt Widgets backend ("wx/qt/") für `racket/gui`. Additiver Spike: aktiviert via `PLT_QT=1`, bestehende Backends (cocoa/gtk/win32) **nicht anfassen**.

## Fixe Regeln — niemals brechen

1. **Kein `QApplication::exec()`**, kein eigenes `QEventLoop`. Racket treibt die Loop; Qt wird gepumpt via `shim_pump(int max_ms)`.
2. **C→Racket-Callbacks** immer mit `#:atomic? #t` + `#:async-apply`. Sie dürfen **nur** Events in den Eventspace **posten**, niemals synchron aufrufen.
3. **`public*`/`override*`-Invariante:** Methoden, die ein Glue-Layer via `public*` hinzufügt, dürfen **nicht** in Platform-Klassen definiert sein (→ `method already defined`). Methoden, die via `override*` erwartet werden, **müssen** in der Platform-Klasse stehen (→ `no method to override`). Volle Tabelle: `docs/HACKING.md §1`.
4. **`queue-backing-flush` gibt `(void)` zurück** — nicht den Rückgabewert von `on-backing-flush`, sonst bricht `resume-flush`s `(->m void?)`-Kontrakt.
5. **`frame%.direct-show` ruft `register-frame-shown`** auf — sonst beendet sich das Programm sofort, weil der Eventspace keine offenen Fenster sieht.
6. **Zwei-Repo-Commits:** Änderungen an `wx/qt/` landen im gui-Submodul (`third_party/gui`, Branch `qt-backend`), dann Submodul-Zeiger im Umbrella (`main`) nachziehen.
7. **Drei-Maschinen-Sync ist immer Teil der Aufgabe:** Es gehört zu jeder Session dazu, sicherzustellen, dass Umbrella (`main`) und gui-Submodul (`qt-backend`) über alle drei Entwicklungsmaschinen (Windows/macOS/Linux) hinweg synchron sind — nicht nur lokal committen und den Sync als offenen Punkt stehen lassen. **Vor jedem Sync-Schritt (Pull/Push/Rebase auf einer Maschine) den Nutzer fragen, ob das jetzt gemacht werden soll** — nicht automatisch durchziehen und nicht als TODO für später notieren.
8. **Submodul-Commit-Reihenfolge:** Der Umbrella-Zeiger auf `third_party/gui` darf **nur** auf einen SHA zeigen, der bereits auf `origin/qt-backend` existiert. Reihenfolge zwingend: (1) Submodul-Branch syncen, **bevor** ein neuer Submodul-Commit entsteht, (2) im Submodul committen, (3) Submodul **pushen**, (4) erst dann den Umbrella-Pointer-Commit erstellen+pushen. Sobald ein Submodul-Commit von irgendeinem Umbrella-Commit referenziert wurde (auch nur lokal, noch ungepusht), darf er **nie mehr umgeschrieben werden** (kein `rebase`/`commit --amend`), ohne den alten SHA vorher als Tag zu pushen — sonst friert der Umbrella dauerhaft einen nicht mehr fetchbaren Commit ein (`fatal: remote error: upload-pack: not our ref …` bei jedem künftigen `git pull --recurse-submodules`). Incident + Fix: `docs/HACKING.md §17`.

## Umgebung

### Windows (primäre Entwicklungsmaschine)

| | |
|---|---|
| Racket | v9.3 [cs], x86-64 — seit 2026-09-11 migriert (`docs/HACKING.md` §24.1) |
| Qt | 6.11.0, `C:\Qt\6.11.0\msvc2022_64` |
| CMake | 4.2.3, Generator "Visual Studio 17 2022" |
| Preset | `windows-x64` → `qt-shim/build/windows-x64` |

### macOS arm64

| | |
|---|---|
| Racket | v9.3 [cs], arm64 (Homebrew) — seit 2026-08-19 automatisch von v9.2 aktualisiert (Cask hält keine ältere Version vor, s. `docs/HACKING.md` §23.2) |
| Qt | 6.11.0, `~/Qt/6.11.0/macos` |
| CMake | Ninja, Generator "Ninja" |
| Preset | `macos-arm64` → `qt-shim/build/macos-arm64` |

### Linux x64

| | |
|---|---|
| Racket | v9.2 [cs], x86-64 (`~/racket`) |
| Qt | 6.11.1, `~/Qt/6.11.1/gcc_64` (Hinweis: 6.11.**1**, nicht 6.11.0 wie Windows/macOS) |
| CMake | Ninja, GCC 13.3.0 |
| Preset | `linux-x64` → `qt-shim/build/linux-x64` |
| gui-lib/draw-lib | seit 2026-07-14 als Installation-scope-Link aktiv (`raco pkg update --link`, kein `sudo` nötig — `~/racket` ist user-owned), kein `-S` mehr nötig |

## Build

**Windows:**
```powershell
cmake --preset windows-x64 -S qt-shim
cmake --build qt-shim/build/windows-x64 --config Debug
```

**macOS:**
```bash
cmake --preset macos-arm64 -S qt-shim
cmake --build qt-shim/build/macos-arm64
```

**Linux:**
```bash
cmake --preset linux-x64 -S qt-shim
cmake --build qt-shim/build/linux-x64
```

## Run / Smoke-Test

**Windows:** `racket` liegt seit der 9.3-Migration (2026-09-11, §24.1) auf dieser
Maschine **nicht** im Machine- oder User-PATH — immer vollen Pfad verwenden oder
`$env:PATH` wie unten setzen.
```powershell
$env:PLT_QT = "1"
$env:PATH   = "C:\Qt\6.11.0\msvc2022_64\bin;C:\Program Files\Racket;" + $env:PATH
racket examples/hello.rkt
```

**Windows — echtes DrRacket (seit Fork == gui-lib 1.80, verlinktes User-Paket):**
```powershell
$env:PLT_QT = "1"
$env:PATH   = "C:\Qt\6.11.0\msvc2022_64\bin;" + $env:PATH
& "C:\Program Files\Racket\DrRacket.exe"
```
Voller Pfad zu `DrRacket.exe` — deshalb hier kein `C:\Program Files\Racket`-Eintrag im
`$env:PATH` nötig (anders als beim bloßen `racket`-Aufruf oben).
Kein `-S`-Flag mehr nötig — der Fork ersetzt die System-`gui-lib` per Link
(`raco pkg update --link third_party/gui/gui-lib`, einmalig, braucht Admin-Rechte).
Gate-Test dafür: DrRacket **ohne** `PLT_QT` muss weiterhin nativ starten (kein
Linklet-Mismatch). Single-Instance-Falle: ein zweiter Aufruf bei bereits laufender
Instanz startet nichts Neues (Exit 0, kein Fenster) — vorher `tasklist | grep drracket`
prüfen. Details/Fallstricke (Autosave-Recovery bei hartem Kill etc.): `docs/HACKING.md §13`.

**macOS:**
```bash
PLT_QT=1 racket -S third_party/gui/gui-lib -S third_party/draw/draw-lib examples/hello.rkt
# Smoke tests:
PLT_QT=1 racket -S third_party/gui/gui-lib -S third_party/draw/draw-lib -l raco -- test tests/smoke.rkt
```
(noch per `-S`-Override, nicht verlinkt — Angleich an Windows/Linux offen.)

**Linux — echtes DrRacket (seit 2026-07-14 verlinktes Paket, `-S` nicht mehr nötig):**
```bash
PLT_QT=1 QT_PLUGIN_PATH=~/Qt/6.11.1/gcc_64/plugins racket examples/hello.rkt
# Smoke tests:
PLT_QT=1 QT_PLUGIN_PATH=~/Qt/6.11.1/gcc_64/plugins racket -l raco -- test tests/smoke.rkt
# Echtes DrRacket:
PLT_QT=1 QT_PLUGIN_PATH=~/Qt/6.11.1/gcc_64/plugins racket -l drracket
```
`raco pkg update --link third_party/gui/gui-lib` + `--link third_party/draw/draw-lib`
(einmalig, kein `sudo` nötig — `~/racket` ist user-owned, anders als Windows' `Program
Files`). Löste ein `-S`-spezifisches Errortrace/Namespace-Mismatch-Problem (Facette 2 in
`docs/2026-07-14_report-linux.md`/`docs/HACKING.md` §23.1) strukturell. Gate-Test:
DrRacket **ohne** `PLT_QT` muss weiterhin nativ starten (bestätigt, `raco test
tests/smoke.rkt` ohne `PLT_QT` grün). Rückfallpfad falls je nötig: Backup der
vorherigen `gui-lib`/`draw-lib`-Installation + `pkgs.rktd` liegt unter
`~/racket-link-backup-2026-07-14/` auf dieser Maschine.

## Aktueller Checkpoint-Status

Diese Tabelle nennt nur den aktuellen Stand. Volle Session-Historie (Vorgehen, Messungen,
Verifikation): `STATUS.md` (chronologisches Log, ein Eintrag pro Session) und
`docs/JJJJ-MM-TT_report*.md` (ein Report pro Session/Plattform). Technische
Tiefenanalysen/Root-Causes: `docs/HACKING.md`, nummerierte §-Abschnitte (im Text unten
referenziert).

| Checkpoint | Status |
|---|---|
| A – Stub-Shim lädt via FFI | ✅ |
| B – Architektur dokumentiert | ✅ |
| C – frame%/canvas%/button% laufend | ✅ 2026-06-24 |
| D – Eingabe-Rückgrat + Editor-Smoke | ✅ 2026-06-25 |
| macOS Smoke | ✅ 2026-06-25 |
| Linux Smoke | ✅ 2026-06-29 |
| E-0 – Widget-Stubs + gui-lib-Angleich 1.78→1.80 + echtes DrRacket | ✅ 2026-06-30/2026-07-02 |
| Linux – gui-lib/draw-lib als Installation-scope-Link (kein `-S` mehr nötig, wie Windows) | ✅ 2026-07-14 — löste das Facette-2-Errortrace-Problem strukturell (§23.1), Gate-Test (nativ ohne `PLT_QT`) bestanden |
| E-0 – Menüs (Titel-/addAction-/mapToGlobal-Fix) | ✅ 2026-07-08, alle 3 Plattformen (§14/§15) |
| E-0 – Redraw-Bug (retained-bitmap-Fix) | ✅ 2026-07-10, alle 3 Plattformen (§16) |
| E – list-box%/check-box% echt | ✅ 2026-07-10, Windows (§18) |
| E – Panel-Sizing-Fix + Modalitäts-Fix | ✅ 2026-07-10, alle 3 Plattformen (§18.2/§18.3) |
| E – `file-selector` (get-file/put-file, Qt-eigener Dialog) | ✅ 2026-07-12, alle 3 Plattformen; Qt-eigen×nativ-Matrix (3×2) komplett 2026-07-13 (§19) |
| E – `choice%`/`radio-box%`/`slider%` echt | ✅ 2026-07-13, alle 3 Plattformen (§20) |
| E – `tab-panel%`/`canvas-panel%`/`group-panel%` echt (Widget-Breite abgeschlossen) | ✅ 2026-07-14, alle 3 Plattformen (§21; macOS via `tab-panel%` real + isolierter Proben für `canvas-panel%`/`group-panel%`, §21.8) |
| E – Preferences Ende-zu-Ende | 🟡 Windows: alle 9 Kategorien durchgesehen (Font/Colors/Browser bereits vorher, Editing/Warnings/General/Profiling/Tools/Background Expansion 2026-09-12, §25) — **keine der sechs neu geprüften Kategorien zeigt einen funktionalen Defekt**. Von den 4 ursprünglichen §21.6-Einzelbefunden sind 2 gefixt (Font-Size-Slider-Zahl — generalisiert auf alle `slider%`, §24.2; Colors-Tab-Rahmen, §24.3); die übrigen 2 (Editor-Canvas-Scrollbars, §24.5, und Colors-Tab rechte Spalte, §25.2) sind **dieselbe Root-Cause** (`show-scrollbars`/`set-scrollbars` unter `wx/qt` nicht funktionsfähig, Shared Code) mit zwei unabhängigen Reproduktionsfällen — ein gemeinsamer, dedizierter Scroll-Fix bleibt offen, eigene künftige Session. Resize/Reflow-Bug (§21.7) weiterhin offen — neuer konkreter Reproduktionsfall: Dialog öffnet initial mit unerreichbarer OK/Undo/Revert-Button-Zeile (§25.1). Linux: Stand unverändert seit 2026-07-13/14 (nur Tabs/Font/Colors/Browser bestätigt, sechs Kategorien dort nicht durchgesehen). **macOS: Menüzugang gefixt** (§22, 2026-07-14) — Preferences erscheint jetzt im Edit-Menü und öffnet den echten Dialog; Restbefunde vermutlich auch hier relevant, nicht erneut durchgesehen |
| Windows Racket 9.2 → 9.3 Migration | ✅ 2026-09-11 (`docs/HACKING.md` §24.1) — kein gui-lib/draw-lib-Versionsangleich nötig, `raco pkg update --link` (Nutzer-elevated), Gate-Test (nativ ohne `PLT_QT`) grün |
| htdp-Lackmustest (`2htdp/image`, big-bang, `test-engine`) | ✅ **DrRacket-auf-Qt trägt htdp** — auf allen drei Plattformen validiert (Windows/Linux 2026-07-14, macOS 2026-09-10, §23/§23.1/§23.2). `test-engine`-Dock-Crash (`test-dock-size`) reproduziert bei 1→2-Tab-Sequenz **10/10 unter Qt, 0/10 nativ** (Windows 4/4+3/3, Linux 3/3+3/3, macOS 3/3+3/3) — **kein htdp-lib-Bug, sondern echte `wx/qt`-Lücke**, auf allen drei Plattformen bestätigt/generalisiert. **Root-Cause präzise lokalisiert (2026-09-12, §23.3, Stretch-Messung):** `wx/qt/panel.rkt:58` überschreibt `is-shown?` hartcodiert auf `#t` (win32 erbt stattdessen die Basisimplementierung — per Grep bestätigt ein echtes, dynamisches `shown?`-Feld, `wx/win32/window.rkt:284/287/327`, gestützt durch §23s Laufzeitmessung: nativ 0/10 Crashes, `remove`-Pfad nie durchlaufen) — dasselbe Muster in praktisch jeder `wx/qt`-Widget-Klasse außer `canvas%`/`frame%`. **„Lokal und klein" bestätigt, nicht das riskantere Pump-Modell** (`wx/qt/queue.rkt`s 50ms-Poll war die zweite, jetzt nachrangige Hypothese) — **Fix selbst bleibt offen, eigene künftige Session**, aber deutlich risikoärmer eingeschätzt als zuvor. `2htdp/universe` big-bang: Kern-Wette „Racket treibt, Pump blockiert nie" auf allen drei Plattformen bestätigt. Auf Linux zunächst nur über `racket` direkt möglich (DrRacket-Pfad durch ein `-S`/errortrace-Package-Problem blockiert, kein Qt-Bezug) — nach dem Linux-DrRacket-Link läuft big-bang auch über echtes DrRacket unter Qt sauber; auf macOS trat dieses Problem trotz weiterhin genutztem `-S`-Rezept gar nicht erst auf. `2htdp/image`: Windows + macOS einwandfrei (alle 5 Bilder sofort korrekt); Linux Interactions-REPL rendert reproduzierbar (3/3) nur die ersten 4 Top-Level-Bildwerte einer `Run`-Sitzung, danach dauerhaft nichts mehr — Pump-Hypothese widerlegt (Poll läuft unbedingt alle 50ms, erklärt keine Mehrminuten-Hänger), kein Scroll-/Compute-/Deadlock-Problem, vermutlich `framework`-Interactions-Insert-Pfad oder Qt-Canvas-Kapazitätsgrenze (§23.1), auf macOS nicht reproduziert — Fix offen für künftige Session (ggf. Shared-Code-Scope, vor Fix-Versuch Rückfrage). macOS lief auf Racket **v9.3** statt v9.2 (Homebrew-Auto-Update 2026-08-19, s. Umgebungstabelle + §23.2) — Fork neu kompiliert, Ergebnis unverändert. |

**Offene Nebenbefunde, je eigene Session:** macOS-Menüleiste zeigt teils 8 statt 9
Einträge (`Windows`-Menü fehlt manchmal, Ursache offen — evtl. verwandt mit §22, nicht
bestätigt, durch den §22-Fix nicht berührt); **gefixt 2026-07-14 (§22):**
macOS-App-Menü-Eintrag an der „Preferences"-Stelle löste den falschen Callback aus
(DrRackets Help-Menü-Punkt „Configure Command Line for Racket…" statt
`preferences:show-dialog`) — behoben durch `setMenuRole(NoRole)` in `shim.cpp` +
PLT_QT-gated `current-eventspace-has-standard-menus?` in `mred/private/app.rkt` (unser
Fork). **Neuer, ungeklärter Nebenbefund aus demselben Fix:** die erhoffte
Exit-Bestätigung + tatsächliche Prozessbeendigung beim Schließen des letzten Fensters
trat NICHT ein (Prozess läuft weiter, kein Crash) — nicht root-caused, zwei Hypothesen
(DrRacket-eigene Close-Logik vs. Qt-Pump-Loop-Bug bei `queue-callback`), eigene künftige
Session. Linux Resize/Minimieren unter
KWin nicht validiert; Linux Crash A
(„arity mismatch") nach den macOS-Menü-Dispatch-Fixes (§19) in 4 Versuchen nicht mehr
reproduziert — plausibel behoben, nicht absolut bewiesen (Original war
n=1-intermittierend); Linux Crash B (Teardown, „invalid memory reference") 1/1
unverändert reproduziert, bleibt offen, andere Ursache als die Menü-Fixe; `test-dock-
size`-Crash (früher hier als `htdp-lib`-Contract-Bug geführt) **reklassifiziert 2026-07-14
(§23/§23.1/§23.2): echte `wx/qt`-Lücke, kein htdp-lib-Bug, auf allen drei Plattformen
bestätigt** — Windows+Linux+macOS je 1→2-Tab-Sequenz 10/10 Qt-Crash, 0/10 nativ; die
frühere Linux-Beobachtung „reicht schon 1 Tab" hat sich in der §23.1-Session nicht
reproduziert (3/3 sauber bei nur einem Tab, beide Backends), Root-Cause bis
`on-tab-change`/`wx/qt/queue.rkt`-Pump eingegrenzt, Fix offen; nativer
macOS-Save-Dialog hängt bei fehlender
Endung ein literales `.*` an den Dateinamen an (nur nativer Pfad, Qt-eigener Dialog
unbetroffen — Diskriminator bestätigt, §19), bewusst nicht gefixt, da native Pfad ohnehin
nicht der Standard ist. **Windows Toolbar-Save-Icon-Timing:** 2026-09-11 systematisch
gegen echtes DrRacket getestet, in keinem Fall reproduziert — kein offener Befund mehr;
korrigierte Datei-Zuordnung: `mrlib/switchable-button.rkt` + `wx/qt/canvas.rkt`, **nicht**
`wx/qt/button.rkt` (§24.4). Aus §21.6 (2026-07-14, backend-generisch, auf Linux identisch
reproduziert) weiterhin offen: Resize/Reflow-Bug (Kind-Controls wandern beim
Fenster-Vergrößern nicht mit, reproduziert sowohl im Preferences-Dialog als auch in einer
isolierten Probe, §21.7); Editor-Canvas-Scrollbars (2026-09-11 Windows: Fix-Versuch
root-caused einen degenerierten Scroll-Range-Bug, der den Editor-Inhalt komplett
weißmalt — Fix zurückgerollt/geparkt, additive Shim-Primitiven bleiben als Grundlage
für einen zweiten Anlauf, §24.5); Colors-Tab rechte Spalte (Rahmen-Teil 2026-09-11
gefixt, §24.3). Font-Size-Slider-Zahl **gefixt 2026-09-11** (§24.2). Neuer Nebenbefund
(2026-09-11, inzident entdeckt, vorbestehend/unabhängig von den Scrollbar-Änderungen,
per `git stash` bestätigt): grafischer Störeffekt (orange/blau gestreiftes Rechteck) nahe
dem oberen Rand des DrRacket-Editor-Fensters, Root-Cause nicht untersucht. Details je
Fund: `STATUS.md`, `docs/HACKING.md`.

## Dokumentation

| Datei | Inhalt |
|---|---|
| `docs/ARCHITECTURE.md` | Widget-Mapping, Shim-API, Event-Loop-Verdrahtung, Pixel-Format |
| `docs/HACKING.md` | `public*/override*`-Tabellen, Klassen-Ketten, Debugging-Guide, Checkliste neue Widgets |
| `docs/CHECKPOINT-D.md` | Detaillierter Plan für D-0 / D-1 / D-2 |
| `docs/BRIEF.md` | Originalbrief mit allen fixen Entscheidungen |

**Namenskonvention für datierte Prompt-/Report-Dateien:** `docs/JJJJ-MM-TT_prompt[-N].md` /
`docs/JJJJ-MM-TT_report[-N][-plattform].md` (ISO-Datum zuerst, damit Name-Sortierung =
Zeit-Sortierung). Reports bekommen **immer** ein Plattform-Suffix (`-win`, `-macos`,
`-linux`), auch wenn die Session nur auf einer Maschine lief — z. B.
`2026-07-09_report-win.md`. Zu jedem `*_prompt*.md` gehört ein passendes `*_report*.md`.

## Shim-Konventionen

- Shim-Handles (`void*`) im `handle`-Feld von `window%` (aus `wx/qt/window.rkt`)
- Alle FFI-Bindings in `wx/qt/utils.rkt`
- Shim bleibt minimal: nur das, was der aktuelle Milestone braucht
- Pixelformat: `CAIRO_FORMAT_ARGB32` ↔ `QImage::Format_ARGB32_Premultiplied`; `stride` aus `cairo_image_surface_get_stride()` (nie `width*4` annehmen)

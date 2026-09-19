# Report — Windows, gebündelter Cross-Platform-Durchlauf — 2026-09-19

**Racket:** `Welcome to Racket v9.3 [cs]` (`C:\Program Files\Racket\racket.exe --version`)
**gui-Submodul:** `278ef9c1` (origin/qt-backend, per `git merge --ff-only` von `fe1f2049` auf dieser Maschine synchronisiert — Umbrella-Zeiger (`main`, Commit `c116b20`) hatte diesen SHA bereits erwartet). 4 Commits nachgezogen: `f3e0dec0` (macOS-Menüband-Collapse), `5a6da709` (QApplication-destroy-vor-exit), `91ee4869` (macOS-Menü-Platzhalter-QAction), `278ef9c1` (stdout-noise-void-Fix).
**qt-shim:** neu gebaut (`cmake --preset windows-x64 -S qt-shim && cmake --build qt-shim/build/windows-x64 --config Debug`) — sauberer Build, keine Fehler/Warnings von Belang. Nötig, weil `a6f72aa` (Linux-Session) `qt-shim/src/shim.cpp` und `qt-shim/CMakeLists.txt` geändert hatte (X11-Zweig, semantisch No-op für MSVC, aber unverifiziert auf Windows vor diesem Rebuild).
**Anlass:** Nutzerauftrag "Windows-Nachtests" — gebündelter Cross-Platform-Durchlauf für den Cluster-1-Block (2026-09-13, bereits 2026-09-17 auf Windows validiert), Geometrie/Scroll (ebenfalls 2026-09-17 validiert) und die 4 neu gepullten macOS/Linux-Commits vom 2026-09-17/18/19, die auf Windows noch nie liefen.

**Vorab-Gate:** Smoke 3/3 mit `PLT_QT=1`, 3/3 ohne — beide grün nach dem Rebuild. `query session`: RDP-Session `rdp-tcp#0` (User Deinzer) aktiv. `racket-prefs.rktd` initial byte-identisch zu `prefs-backup\racket-prefs.rktd.2026-09-17-7` (SHA256 `6e5f3b21...`) — sauberer Ausgangszustand.

---

## Priorität — Windows-Zombie-Prozess-Nachmessung: **Symptom verschwunden**

Zwei der vier neu gepullten Commits (`f3e0dec0` Menüband-Collapse-Fix, `5a6da709` `QApplication`-destroy-vor-`exit`) liegen im selben Codepfad wie der in CLAUDE.md offen geführte Windows-Befund "Zombie-Prozess beim Schließen des letzten Fensters" (zuletzt 4/4 reproduziert am 2026-09-17, `docs/2026-09-17-7_report-win.md`). Nachmessung auf dem neuen HEAD (278ef9c1):

Methode: `DrRacket.exe` per `Start-Process`, `SC_CLOSE` (`WM_SYSCOMMAND`) auf das Hauptfenster — dieselbe Nachricht wie ein echter Klick auf den X-Button —, 30s auf Prozessende gepollt, `GetForegroundWindow()`-Verifikation vor der Eingabe (Methodik aus `docs/2026-09-17-7_report-win.md` übernommen).

| # | Bedingung | Ergebnis |
|---|---|---|
| 1 | Qt | **Sauberer Exit** (deutlich unter 30s) |
| 2 | Qt | **Sauberer Exit** |
| 3 | Qt | **Sauberer Exit** |
| 4 | Qt | **Sauberer Exit** |
| Kontrolle | Nativ (kein `PLT_QT`), identische Schließ-Methodik | **Sauberer Exit** |

**4/4 sauber — vollständige Umkehr des 4/4-Zombie-Befunds vom 2026-09-17.** Kein leftover-Prozess nach allen fünf Läufen (`Get-Process -Name DrRacket*` leer). Da kein Code in dieser Session geändert wurde, ist der wahrscheinlichste Erklärungsträger einer der beiden mitgezogenen Commits (`f3e0dec0`/`5a6da709`, ursprünglich für macOS-Symptome gefixt) — welcher genau, wurde nicht isoliert (kein Bisect in dieser Session, das wäre ein eigener Block). **CLAUDE.md aktualisiert:** Befund von "offen, 4/4 reproduziert" auf "nicht mehr reproduzierbar, 4/4+1 sauber auf 278ef9c1, Root Cause nicht isoliert" — bewusst nicht als endgültig "gefixt" geschlossen, da kein gezielter Fix-Commit diesem HEAD zugeordnet werden kann.

---

## Suite A — Regressionsschutz (4 neu gepullte Commits gegen den bekannten Windows-Stand)

| Probe | Ergebnis |
|---|---|
| `clipboard-probe.rkt` (Qt) | **PASS** — alle drei Checks (Roundtrip, Editor-Copy, Editor-Paste) grün. |
| `menu-demand-probe.rkt` (Qt, `PLT_QT_DEBUG=1`) | **PASS** — `demand-count=2`, Checkbox-Toggle liest korrekt zurück. Der macOS-Platzhalter-`QAction`-Fix (`91ee4869`) erzeugt auf Windows keinen Phantom-Eintrag: das "File"-Popup zeigt exakt 1 Action ("Toggle"), keine Regression. |
| `is-shown-probe.rkt` (Qt + nativ) | **PASS** — identischer Log-Output beide Wege. |
| `resize-reflow-probe.rkt` (Qt) | **PASS** — Frame wächst 400×300 → 400×630 nach `reflow-container`. |
| `live-resize-probe.rkt` (Qt, echtes `SetWindowPos`-Resize von außen) | **PASS** — Button folgt der Fensterbreite über zwei Resize-Schritte (300→700→900 angefragt, Qt liefert 684×361/884×461 durch DPI-Rundung; Button-Breite = Fensterbreite − 4px, stabil über alle Ticks nach jedem Schritt). |
| `minsize-resize-probe.rkt` (Qt, echtes Schrumpf-Resize) | **PASS** — Versuch auf 200×150 zu schrumpfen wird einmalig auf 279×360 korrigiert, danach stabil über 34 Ticks, kein Kaskadieren. |
| `scroll-probe.rkt` (Qt, echtes Mausrad via `mouse_event(MOUSEEVENTF_WHEEL)`, `PLT_QT_SCROLL_DEBUG=1`) | **PASS** — 10 Wheel-Notches → `set-scroll-pos vertical` läuft exakt 1→10, identisch zum Linux-Befund. |
| `panel-scroll-probe.rkt` (Qt, echtes Mausrad + Klick auf gemeldete Koordinate) | **PASS** — "Names"-Button-Zentrum wandert von y=1001 (außerhalb des 260px-Fensters) auf y=631 (erreichbar) nach 30 Wheel-Notches; Klick auf die gemeldete Koordinate löst `CLICK auf Names (Nr. 1)` aus — erreichbar UND klickbar. |
| `canvas-panel-probe.rkt` (Qt) | **PASS** — kein Crash, `content inserted`/`frame shown` beide geloggt (kein natürlicher Exit, erwartet). |
| `deleted-style-probe.rkt` (Qt + nativ, Screenshot) | **PASS — erste Windows-Validierung von §35 (Toolbar-Overlap).** Qt: `dead-panel is-shown?=#f w=0 h=0`, Screenshot zeigt ausschließlich den "SICHTBAR"-Button, kein "STRAY" sichtbar. Nativ (win32): visuell identisch, einzige Abweichung `dead-canvas is-shown?=#t` statt `#f` (dieselbe harmlose wx-Level-Divergenz wie bereits auf Linux dokumentiert). Screenshots: `2026-09-19_deleted-style-qt-win.png` / `2026-09-19_deleted-style-native-win.png`. |
| `crash-b-teardown-probe.rkt` (Qt, Accept- und Cancel-Pfad) | **PASS** beide Pfade — Cancel: `put-file returned: #f`; Accept: `put-file returned: C:/.../crash-b-probe-testfile.txt`. Kein Crash-Trace in stderr, keine Datei tatsächlich angelegt (put-file schreibt nicht selbst). |
| `enable-cascade-probe.rkt` (Qt, echter Klick auf gemeldete Koordinate) | **PASS** im ersten Versuch — `clicks after window 1 (enabled) = 1` (Positivkontrolle gültig), `clicks after window 2 (disabled) = 1` (Delta 0) → `VERDICT: PASS`. |
| **Akzeptanztest `test-dock-size`** (n=3, 1→2-Tab-Sequenz in echtem DrRacket, echte Maus-Klicks auf Run/File/Open, Dateiname in den Qt-Dialog getippt) | **0/3 Crash — Akzeptanzkriterium erfüllt.** Alle drei Läufe: `Ran 3 tests. 1 of the 3 tests failed.` (kein `DrRacket Internal Error`), Tab 2 öffnet sauber (Fenstertitel wechselt korrekt zu `htdp-image-probe.rkt - DrRacket`). Trial 1 lief gegen die echten `examples/`-Dateien; Trials 2+3 gegen Kopien in einem Scratch-Verzeichnis (Grund s. Automatisierungslektion unten). Screenshot: `2026-09-19_dock-test-tab2-win.png`. |

## Suite B — bereits implementierte Windows-Features, nach dem Shim-Rebuild erneut verifiziert

| Probe | Ergebnis |
|---|---|
| `gauge-probe.rkt` | **PASS** — `get-value`/`get-range` roundtrippen exakt gegen das 0..20-Sägezahnmuster über 61 Ticks, keine Abweichung. |
| `cursor-probe.rkt` | **PASS funktional** — 12 `set-cursor`-Aufrufe (11 Standard + 1 Custom-Bitmap) laufen über 56 Ticks ohne Exception. Cursor-Form nicht erneut fotografisch verifiziert (bereits bei der §40-Einführung visuell bestätigt, hier reine Regressionsprüfung). |
| `mouse-state-probe.rkt` (echte `SetCursorPos`/`keybd_event`/`mouse_event`) | **PASS, alle Achsen** — Position exakt `(700,500)`, `mods=(shift)` erscheint/verschwindet korrekt um den Shift-Tap, `mods=(left)` erscheint/verschwindet korrekt um den Linksklick. Vollständiger `_WIN32`-Zweig bestätigt (anders als Linux vor dessen heutigem Fix). |
| `printer-probe.rkt` (PDF-Rasterpfad) | **PASS** — `page-size = 612 x 792 pt` (Letter), 504 KB zweiseitige PDF, kein Crash. |
| `printer-dialog-probe.rkt` (§43.7, echter interaktiver Dialog-Pfad) | **Nachtrag, selber Tag:** der hier als "offen" protokollierte Befund wurde in einer direkt anschließenden Chat-Session vollständig zurückgezogen (`docs/HACKING.md` §54.4). Root Cause der Nichterscheinen-Beobachtung war kein Qt-/OS-Defekt, sondern eine ungeeignete Testmethode: Snapshot (`UIAutomation`/`Get-Process`) + Hart-Beenden nach 15s kann bei paketierten/COM-aktivierten Windows-Prozessen nicht zwischen "nie erschienen", "noch nicht erschienen" (Kaltstart) und "bereits erschienen und geschlossen" (COM-Server-Idle-Nachlauf) unterscheiden. Per Live-Beobachtung des Nutzers bestätigt: der Print-Dialog öffnet sich normal und ist voll bedienbar. **Kein racket-qt-Handlungsbedarf, nicht mehr root-causen.** Ursprünglicher Befundtext (2 von 2 Versuchen ohne Sekundärfenster, 18-Drucker-Datenpunkt) unten unverändert als historischer Kontext stehen gelassen. |

## Automatisierungslektion (kein Produktbefund, aber PROZESS-relevant)

Ein früherer, verworfener Automatisierungsversuch für den `test-dock-size`-Test (v1 des Skripts, das Fenster-Rect nur einmal beim Start maß statt vor jedem Klick neu) traf mit einer `SendKeys`-Texteingabe die **Definitions-Editor-Fläche statt eines Datei-Dialogs**, weil DrRacket sein Hauptfenster kurz nach dem Start von einer kleinen Platzhaltergeometrie auf die gespeicherte Preferences-Größe vergrößert — ein Klick auf Basis der alten (kleinen) Fensterkoordinaten landete daneben, der nachfolgende Tastatureingabe-Text landete direkt im Quelltext und wurde **auf die reale Datei `examples/htdp-tests-probe.rkt` durchgespeichert** (Backslashes wurden dabei von DrRackets BSL-Editor zu `λ` transformiert — ein bekanntes Keybinding, kein Bug). Sofort per `git checkout -- examples/htdp-tests-probe.rkt` bemerkt und zurückgesetzt, `git diff` vor dem Fix als Beleg geprüft, danach `git status` sauber verifiziert. Für die verbleibenden `test-dock-size`-Trials (2 und 3) auf Kopien der beiden Probe-Dateien in einem Scratch-Verzeichnis außerhalb des Repos umgestellt, um dieses Risiko für den Rest der Session auszuschließen; außerdem wird die Fenstergeometrie jetzt unmittelbar vor jedem Klick neu gemessen (Stabilitäts-Polling: 3 identische `GetWindowRect`-Messungen in Folge) statt einmalig gecacht. Kein Datenverlust (Originaldatei war nach `git checkout` bitgleich zum Repo-Stand), aber ein Beleg dafür, dass reale Maus-/Tastatur-Automatisierung gegen ein sich selbst bewegendes Fenster **immer** unmittelbar vor der Eingabe neu vermessen werden muss, nicht nur einmal beim Start.

## Kandidaten für Fix-Phase / Offene Punkte

Kein Fix-Bedarf in dieser Session identifiziert — reine Validierung, wie geplant.

1. ~~§43.7 `printer-dialog-probe` bleibt offen~~ — **erledigt, selber Tag:** in einer direkt anschließenden Chat-Session als Messfehler (Snapshot-Testmethode ungeeignet für paketierte/COM-aktivierte Prozesse) identifiziert und zurückgezogen, per Nutzer-Live-Beobachtung bestätigt funktionsfähig. Details: `docs/HACKING.md` §54–§54.4.
2. **Windows-Zombie-Befund**: Symptom verschwunden, aber Root Cause nicht isoliert (welcher der beiden Commits genau). Kein Blocker, aber ein Bisect wäre für eine vollständige Erklärung wertvoll — nicht in dieser Session, da reine Validierung.

## "Später zu validieren"-Liste — jetzt vollständig abgearbeitet

Cluster-1-Fixes (is-shown?/enable-Kaskade), Geometrie-Block (§32) und Scroll-Block (§33/§34) waren laut `CLAUDE.md`-Checkpoint-Tabelle bereits 2026-09-17 auf Windows validiert. Mit dieser Session sind zusätzlich die vier 2026-09-17/18/19 nachgezogenen Commits (macOS-Menüband-Collapse, `QApplication`-Teardown, macOS-Menü-Platzhalter, Stdout-Noise) sowie §35 (Toolbar-Overlap) erstmals auf Windows geprüft. **Der gebündelte Cross-Platform-Durchlauf (Windows/macOS/Linux) ist damit für alle bis 2026-09-19 bekannten Befunde komplett**, mit einer offenen Ausnahme (Zombie-Root-Cause) — §43.7 wurde noch am selben Tag in einer Folge-Session erledigt (s. o.).

## Disziplin

- `racket-prefs.rktd` vor der ersten GUI-Interaktion identisch zu `prefs-backup\racket-prefs.rktd.2026-09-17-7` (SHA256 `6e5f3b21...`); nach der Session erneut geprüft (drifted auf `8bbebb85...` durch die vielen DrRacket-Starts — erwartet, s. Memory-Eintrag zu GUI-Automatisierungs-State-Drift), gesichert als `prefs-backup\racket-prefs.rktd.2026-09-19-2-post-testrun`, danach auf den `2026-09-17-7`-Stand zurückgespielt und Hash verifiziert identisch.
- `git status` vor jedem Zwischenschritt geprüft; die einzige unbeabsichtigte Dateiänderung (s. Automatisierungslektion oben) wurde sofort erkannt und per `git checkout --` zurückgesetzt, bevor irgendein Commit stattfand.
- Kein Push/Pull über den bereits genehmigten Submodul-Fast-Forward hinaus — kein neuer Fix-Commit in dieser Session, daher kein weiterer Push-Bedarf.
- Alle gestarteten `racket.exe`/`DrRacket.exe`-Prozesse am Ende verifiziert beendet (`Get-Process -Name DrRacket*`/`racket*` leer).

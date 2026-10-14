# Report — macOS, Pull + Shim-Rebuild + Validierung der Serie §64–§84 — 2026-10-14

**Kontext:** Seit dem letzten macOS-Stand (2026-09-27) sind auf Linux und Windows die Abschnitte
§64–§84 aufgelaufen (Eingabeschicht, Funktions-Sweeps, Audits, `canvas% 'gl`, Abdeckungs-Matrix,
Windows-Fensterposition). Auftrag: Repo-Stand prüfen, pullen, Shim neu bauen, auf macOS validieren,
soweit automatisierbar. Jeder Sync-Schritt wurde vorher mit dem Nutzer abgestimmt (Regel 7).

**Racket:** v9.3 [cs] (Homebrew). **Qt:** 6.11.0 (`~/Qt/6.11.0/macos`). Display 1440×900 (Retina ×2).

## 1. Pull und Shim-Rebuild

- Start: Umbrella `0bea8ae`, **40 Commits hinter** `origin/main`; Submodul `c986ba6a`, **25 Commits
  hinter** `origin/qt-backend`. Beide reine Fast-Forwards.
- Umbrella `git pull --ff-only` → `f535b40`; Submodul → `1efb2c03`. `git submodule update` lässt das
  Submodul im Detached HEAD zurück — danach `git checkout qt-backend && git merge --ff-only
  origin/qt-backend`, damit es wieder auf dem Branch steht.
- `cmake --preset macos-arm64 -S qt-shim` + `cmake --build`: sauber, kein AppleClang-Build-Fix nötig.
  `nm -gU`: 205 `shim_*`-Exporte; stichprobenartig bestätigt `shim_tab_panel_set_options`,
  `shim_button_set_icon`, `shim_label_set_standard_icon`, `shim_screen_available_geometry`.

## 2. Automatisierte Suiten

| Suite | Ergebnis |
|---|---|
| `tests/stub-audit.rkt` | 9/9 |
| `tests/api-audit.rkt` | 4/4 |
| `tests/callback-audit.rkt` | 5/5 |
| `tests/init-audit.rkt` | 3/3 |
| `tests/style-audit.rkt` | 3/3 |
| `tests/key-map.rkt` (`PLT_QT=1`) | 56/56 — alle `derived`-Zeilen auf macOS nachgemessen |
| `tests/smoke.rkt` (`PLT_QT=1`) | 4/4 |

## 3. Probes

Grün: `frame-position-probe` (`ON-MOVE 1 58` beim Start, programmatisches `move 300 200` meldet
`ON-MOVE`/`POS` korrekt), `is-shown-probe`, `message-color-probe`, `bitmap-label-probe` (PASS),
`splash-width-probe` (Dialog 310×324, kein 400-px-Fallback mehr), `set-focus-probe` (0 FAILS),
`display-changed-probe` (`display-size` 1440×900, kein hartcodiertes 1920×1080 mehr).
`tab-close-reorder-probe` ist interaktiv (wartete auf Eingabe, per Timeout beendet) — dessen
Funktion wurde stattdessen in echtem DrRacket geprüft (s. §5).

## 4. Verhaltensmatrix (nativ Cocoa gegen Qt)

`RACKET=$(command -v racket) T=60 tests/sweep/behavior-matrix.sh` — 51 Sektionen, 36 identisch,
15 mit Abweichung, davon 13 reine Fokus-Zähler. Das Skript ist auf Linux kalibriert
(`behavior-matrix-known.txt` ist gtk-Referenz), lief aber unverändert (`gtk`-Modus = nativ).

- **Fokus-Sektionen** (`button`, `canvas`, `check-box`, `choice`, `combo-field`, `editor-canvas`,
  `list-box`, `list-box-columns`, `list-box-multi`, `radio-box`, `slider`, `text-field`,
  `text-field-multi`): z. B. `button`/`check-box` nativ `has-focus #f`, `on-focus-in-count 0`; Qt
  `#t`/`1`. **Einordnung (nicht belegt):** Cocoa-Buttons nehmen ohne „Full Keyboard Access" keinen
  Tastaturfokus an; Qt verhält sich hier wie gtk/win32. Wahrscheinlich Eigenart der nativen Referenz,
  kein Qt-Fehler. Nicht gegen Windows-/Linux-Matrix gegengeprüft.
- **`popup-menu`:** nativ hängt (`SECTION-EXN user break`, rc=124, Timeout), Qt läuft durch
  (`gc-with-popup-open-no-crash => #t`). Qt besser als die Referenz.
- **`tab-order`:** nativ bleibt der Fokus im Probe auf dem Textfeld (`tf tf tf …`), Qt wandert
  korrekt durch alle Widgets (`tf cb ch b2 b1 tf`). Wieder Referenz-Eigenart (Cocoa-Tabbing hängt
  vom Systemschalter ab), nicht Qt.
- Fehlende macOS-Kalibrierung: `behavior-matrix-known.txt` sollte für macOS eine eigene Known-Liste
  bekommen, falls die Matrix hier regelmäßig laufen soll (nicht gemacht).

## 5. Echtes DrRacket unter `PLT_QT=1`

- Start: Fenster mit sichtbarer Titelleiste, Position `77,30`, Größe `1363×815`. Der in §67
  geflaggte Prüfpunkt „Titelleiste des ersten Fensters sichtbar" ist damit **erfüllt**.
- **Fensterposition über Neustart:** Fenster per AppleScript auf `200,120` / `900×600` gesetzt,
  Cmd+Q, Neustart → `200,120 900×600`. **PASS.**
- **Tabs:** Cmd+T öffnet Tab 2, kompakte Tab-Leiste (`setExpanding(false)`), [x] nur am aktiven Tab.
  Tab-Wechsel per Klick funktioniert. [x]-Klick: **AppleScript `click at` schließt den Tab nicht**
  (löst nur AX-Press auf dem Tab-Radiobutton aus) — Automatisierungsartefakt, vgl. §51.2. Mit
  echtem Mausklick (`cliclick c:x,y`) schließt das [x] den Tab, die Tab-Leiste verschwindet bei
  einem Tab. **PASS.**
- **Tab-Taste/Return:** Tippen ging versehentlich in die Interactions-Fläche (Fokus dort). Return
  und Tab verhalten sich dort plausibel (Folgezeile eingerückt, Fokus springt nicht weg). Im
  Definitions-Editor **nicht** getestet.

## 6. Nachprüfung der zunächst offenen Punkte (später am selben Tag)

Prefs-Datei vorher gesichert (`org.racket-lang.prefs.rktd`); danach nur automatisch geschriebene
Einträge geändert (Splash-Breite, `most-recent-lang-line`, Fensteranteil, `last-opened-files`),
Fensterposition unverändert. Vor jedem Tastendruck wurde geprüft, dass `racket` im Vordergrund ist.

| Punkt | Ergebnis |
|---|---|
| Datei-Drop (`shim_window_set_drop_cb`) | **PASS.** `examples/drop-probe.rkt`, echter Maus-Drag aus einem Finder-Fenster (`cliclick dd/dm/du`). Nativ und Qt identisch: `drop canvas-accept => a.txt`, `drop frame => b.txt` (Rückfall auf den Frame). |
| Fenstergrenzen (`shim_window_set_size_limits`) | **PASS.** Eigene Probe (Canvas `min 500×300`, nicht dehnbares Fenster `300×200`), per Accessibility auf `200×150` bzw. `900×700` gezogen: nativ und Qt klemmen identisch auf `500×328` / `300×228` (inkl. 28 px Titelleiste). |
| `setAutoDefault` / Return im Dialog | **Teilweise abweichend, s. Befund B.** Tippen + Return → `BUTTON OK` (nativ = Qt). Escape → schließt (nativ = Qt). Fokus auf *Cancel* + Return → **nativ `BUTTON OK`, Qt `BUTTON Cancel`.** |
| Fokus-Reasons (Menü) | **PASS.** Edit-Menü per Klick geöffnet, nach 4 s weiterhin offen und vollständig; Escape schließt; anschließendes Tippen landet im Editor. Einen Eintrag nach ≥ 3 s anzuklicken wurde **nicht** getestet. |
| Tab im Definitions-Editor | **PASS.** Unformatierter Text (per Cmd+V eingefügt), Cmd+A, Tab → `(define (f x)` / `  (let ([y x])` / `    y))` korrekt eingerückt. |
| Cmd-Shortcuts (§58.1-Regression) | **PASS.** Cmd+A (Auswahl/Ersetzen), Cmd+V (Einfügen), Cmd+C (Zwischenablage per `pbpaste` geprüft). |
| Ctrl-Emacs-Belegungen | **PASS.** Ctrl+A / Ctrl+E bewegen auf Zeilenanfang/-ende (`XabcY`). |
| `get-top-frame` (beschriftete Controls) | Nur indirekt: In der Matrix melden `choice`/`list-box-columns` unter Qt `frame-focus-window-eq #t` (nativ `#f`, vgl. §4). Keine eigene Prüfung. |
| `shim_screen_available_geometry` | Auf macOS laut Banner Stub (`0`). Fenster liegt unterhalb der Menüleiste (`77,30`), nicht separat geprüft. |
| Linux-/X11-Sweeps (`func-*.sh`, `sweep.sh`, `visual-matrix.sh`, `input-matrix.sh`) | Nicht lauffähig (brauchen `xdotool`/`spectacle`). |

### Befund A (neu, offen): Cmd+Q beendet ohne Rückfrage bei ungespeichertem Inhalt

- **Reproduktion:** DrRacket unter `PLT_QT=1`, Text tippen (Titel `Untitled - DrRacket*`), Cmd+Q →
  Prozess beendet sich innerhalb 1 s mit `exit=0`, **kein** „The file ‚Untitled' is not saved."-Dialog.
  Nativ (gleiche Schritte) erscheint der Dialog (Don't Save / Cancel / Save). 2/2 reproduziert.
- **Cmd+W ist nicht betroffen:** Schließen des Fensters fragt unter Qt wie nativ.
- **Folge:** Die ungespeicherte Arbeit liegt nur noch als Autosave vor; der nächste *native* Start zeigte
  den Wiederherstellungs-Dialog („Original file / Backup file").
- **Hypothese (nicht verifiziert):** Das „Quit racket" im macOS-App-Menü ist Qts Standardeintrag und umgeht
  Racket-seitig `can-close?`/`application-quit-handler`. Im Qt-Backend kommt `application-quit-handler` nirgends
  vor (`platform.rkt:235` `cancel-quit` ist ein No-op), alle DrRacket-eigenen `QAction`s haben `NoRole` (§22),
  Cocoa dagegen hängt `terminate:` an den Racket-Handler (`wx/cocoa/menu-bar.rkt:144`). Auf Windows/Linux
  liegt Quit im File-Menü und läuft durch das Framework — dort vermutlich nicht betroffen (nicht geprüft).
- **Status:** nicht gefixt, geparkt. Ein Fix bräuchte die App-Menü-Quit-Aktion an den Racket-Quit-Handler zu binden.

### Befund B (neu, offen): Return auf fokussiertem Nicht-Default-Button

`QPushButton::setAutoDefault(true)` (Block D, Linux-motiviert) lässt Return den **fokussierten** Button
auslösen (gtk/win32-Verhalten). Cocoa dagegen löst bei Return stets den Default-Button aus. Betrifft
macOS-Dialoge, in denen per Tab ein anderer Button als OK fokussiert wurde. Kein Datenverlust, aber
Abweichung von der nativen Konvention. Nicht gefixt (Kandidat: `#ifdef Q_OS_MACOS`).

### Beobachtung C (kein Befund): Shortcut-Spalte im Edit-Menü ohne ⌘

Im Screenshot zeigt die Shortcut-Spalte nur den Buchstaben (`Z`, `X`, `C` …), auch im **nativen** DrRacket —
Darstellungsartefakt der Aufnahme, kein Qt-Unterschied.

### Beobachtung D (kein Befund, Test-Artefakt): Reihenfolge Menü-Shortcut vs. Zeichen

Wurden Cmd+A und anschließende Zeichen per AppleScript ohne Pause gesendet, wirkte Cmd+A erst *nach* den
Zeichen. Mit 0,5–0,7 s Pause korrekt. Bei Handeingabe nicht erreichbar; nicht weiter verfolgt.

## 7. Methodik-Fehler und Nebenwirkungen

- **Echte Preferences überschrieben.** `PLTADDONDIR` isoliert die Prefs auf macOS **nicht**
  (`find-system-path 'pref-file` → `~/Library/Preferences/org.racket-lang.prefs.rktd`, identisch mit
  und ohne gesetzte Variable). Der Positionstest hat Position/Größe des echten DrRacket-Fensters
  überschrieben. Vor dem Beenden auf `77,30 1363×815` (Wert beim ersten Start) zurückgesetzt; ein
  Backup der Prefs gab es nicht. **Künftig:** für macOS-Prefs-Tests die Datei vorher sichern oder
  `PLTADDONDIR` nicht als Isolation verwenden.
- Ein AppleScript-`click at {590, 0}` mit falscher Koordinate traf die Menüleiste; per Escape
  geschlossen, ohne Folgen.
- `pgrep -x` schlägt in dieser Shell mit „illegal byte sequence" fehl (Locale) — Prozessprüfung
  stattdessen über `ps -axo pid,lstart,command | grep`.

Weitere Methodik-Funde aus der Nachprüfung (§6):

- **Unbeabsichtigter Drop ins Terminal:** Ein Drag-Versuch landete im Eingabefeld der Claude-Code-Sitzung
  (Pfad `…/dropfix/a.txt`), weil iTerm statt Finder aktiv war. `AXRaise` allein aktiviert eine App nicht;
  `set frontmost to true` auf Finder + `AXRaise` auf dem Probe-Fenster ist die funktionierende Reihenfolge.
- **Echter Drag braucht `cliclick dd:` + `dm:` + `du:`** — `m:` sendet nur Bewegungs-, keine Drag-Events
  (es wurde nur markiert, kein Drag-Session gestartet).
- **`pkill`/`pgrep -x`/`kill` per Muster:** `pkill` scheitert an der Locale („illegal byte sequence"); ein
  `grep`-Muster, das im eigenen Aufruf vorkommt (`[d]ialog-keys-probe`), tötet die eigene Shell (Exit 144).
  Abhilfe: Skript in eine Datei, Prozess über `$!` beenden.
- **Zwei `racket`-Prozesse:** `System Events` adressiert beide als `racket`; Fenster-Operationen treffen
  dann das falsche Fenster. Vor Tests alte Probes beenden.
- Test-Aufruf mit mehreren Prozessen: Steuer-Pipe (`mkfifo`) braucht einen dauerhaft offenen Schreiber
  (`(sleep 900 > pipe &)`), sonst ist der Dateideskriptor im nächsten Bash-Aufruf weg.

## 8. Befunde

- **Befund A (offen):** Cmd+Q ohne Speichern-Rückfrage bei ungespeichertem Inhalt (Datenverlust-Risiko, nur macOS
  untersucht) — s. §6.
- **Befund B (offen):** Return auf fokussiertem Nicht-Default-Button löst unter Qt diesen Button aus, nativ den
  Default — s. §6.
- Sonst keine neuen Qt-Defekte. Kein Fix, keine ABI-Änderung in dieser Session; Repo-Änderungen nur Doku.

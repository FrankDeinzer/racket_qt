# Report — htdp-Lackmustest (Schritt 3) — 2026-07-14 (Linux)

**Racket:** `v9.2 [cs]` (gemessen, `~/racket/bin/racket --version`).

**Kontext:** Fortsetzung von `docs/2026-07-14_report-win.md` (Windows führte). Linux/macOS-
Validierung war als separater Prompt vorgesehen; dies ist die Linux-Session. Fokus laut
Auftrag: Facette 3 (`test-dock-size`) auf Linux nachvollziehen, Facette 1/2 ergänzend.

## Phase 0 — Umgebung

- **Sync-Check (vor jedem Schritt Nutzer-Bestätigung, Regel 7):** Umbrella `main` bereits
  aktuell zu `origin/main` (Windows-Report + §23-Doku schon vorhanden, commit `64296ff`).
  Submodul (`third_party/gui`, `qt-backend`) lokal 1 Commit hinter (`f6f38474` →
  `54f2f702`, exakt der vom Umbrella-Zeiger bereits referenzierte Commit = `origin/
  qt-backend`) — nach Nutzer-Bestätigung Fast-Forward-Pull, keine Konflikte möglich
  (reiner FF, kein lokaler Divergenzpunkt).
- **Shim-Aktualität: stale.** `shim.cpp` enthält den §22-Fix (`setMenuRole`, committed
  2026-07-14 18:02:39), aber `qt-shim/build/linux-x64/libracketqtshim.so` war zuletzt um
  12:53 desselben Tages gebaut — vor dem Fix. Neu gebaut (`cmake --build
  qt-shim/build/linux-x64`), danach `libracketqtshim` frisch.
- **DrRacket-Link-Status geprüft (wichtiger Unterschied zu Windows):** `raco pkg show -l`
  zeigt **keine** user-verlinkten Pakete auf dieser Maschine — anders als Windows (dort
  `raco pkg update --link`, echtes `DrRacket.exe` lädt den Fork automatisch). Linux nutzt
  weiterhin das dokumentierte Startrezept `racket -S third_party/gui/gui-lib -S
  third_party/draw/draw-lib -l drracket` (§13). **Für jeden Lauf dieser Session per
  `grep libracketqtshim /proc/<pid>/maps` positiv verifiziert**, dass der Qt-Shim
  tatsächlich geladen ist (Qt-Läufe: Treffer; native Läufe ohne `PLT_QT`: kein Treffer,
  GTK-Backend bestätigt) — Warnung aus der Advisor-Rücksprache dieser Session, da ein
  reiner `PLT_QT=1`-Env-Var-Fehlgriff ohne Fork-Link sonst unbemerkt geblieben wäre.
- **Light Mode bestätigt:** `racket-prefs.rktd` → `(plt:framework-pref:framework:
  white-on-black? #f)`.
- **Re-Smoke:** 3/3 grün (`raco test tests/smoke.rkt`, `PLT_QT=1`).
- **Menü-Sanity-Check (Hygiene nach §22-Pull):** Code-Review von `app.rkt`s
  `current-eventspace-has-standard-menus?` zeigt: die Bedingung startet mit
  `(eq? 'macosx (system-type))`, kurzschließt also auf Linux (`system-type` = `'unix`)
  unabhängig von `PLT_QT` — §22 Part B ist auf Linux strukturell ein No-op, exakt wie auf
  Windows. Visuell bei jedem DrRacket-Start bestätigt: 9 Menüeinträge (File/Edit/View/
  Language/Racket/Insert/Scripts/Tabs/Help), keine Regression.

**GUI-Automatisierung — Methodik-Hinweis:** zu Sessionbeginn waren auf dieser Maschine
keine `xdotool`/`ydotool`/`wtype` installiert (nur rohe X11-`ctypes`-Events, siehe
Memory `project_menu_redraw_diagnosis`); zwei frühe Fehlklicks (falsche Skalierung eines
Screenshot-Pixels, u. a. versehentlich das Help-Menü statt „Stop" getroffen) resultierten
daraus. Der Nutzer hat `xdotool`/`ydotool`/`wtype` nachinstalliert — ab da liefen alle
Interaktionen zuverlässig über `xdotool search`/`getwindowgeometry`/`mousemove --window`/
`click`/`key`/`type`. **Gotcha notiert:** `xdotool windowkill` schickt `XKillClient` und
beendet damit die **gesamte X11-Verbindung des Prozesses** (alle Fenster dieses Clients,
nicht nur das gezielte) — bei DrRackets Stepper-Fenster (gleicher Prozess wie das
Hauptfenster) riss das die komplette Session ab (`X11 connection broke`, Racket-Prozess
lief orphaned weiter). Für Hilfsfenster künftig `key Return`/`key Escape` oder den
regulären Schließen-Button verwenden, nicht `windowkill`.

**Checkpoint 0: alles grün** → Phase 1.

## Phase 1 — htdp end-to-end (drei Facetten)

### Facette 1 — `2htdp/image`: teilweise (4/5 sofort sauber, 5. Bild mit offenem Befund)

`examples/htdp-image-probe.rkt`, `File`-Argument beim Start (kein Tippen in den Editor,
§13-Autosave-Falle vermieden). In **jedem** Lauf erscheinen die ersten vier Bild-Werte
(Kreis, Rechteck-Outline, `overlay`, `beside`) sofort und korrekt als Snips im
Interactions-Fenster.

Das fünfte (`above/align` aus `text` + `rectangle`) fehlte im **ersten** Testlauf über
8+ Minuten vollständig — kein Scrollbalken, Nutzer-bestätigt manuelles Scrollen (Maus)
zeigte ebenfalls nichts, letztes sichtbares Element blieb `beside`. Ein Interrupt-Versuch
("Stop") zeigte keinen Break. Ein **headless Gegencheck** (`racket -e '(require
2htdp/image) (define i (above/align ...)) (printf "~a x ~a" (image-width i)
(image-height i))'`) bestätigt: die reine Bildberechnung ist unter Qt sofort fertig
(`142 x 29`, < 1 s) — das Problem liegt **nicht** bei der Berechnung, sondern beim
Rendern/Einfügen des Snips in die Interactions-Anzeige.

In **späteren, frischen** Läufen (identische Datei) erschien das fünfte Bild dagegen
unauffällig, nachdem zuvor eine Fenster-Interaktion (Klick) stattgefunden hatte —
uneindeutig, ob die Interaktion ursächlich war oder Zufall. Ein Scroll-Versuch per
synthetischem X11-Mausrad-Event auf der ursprünglich hängenden Instanz löste zudem einen
**visuellen Ghosting-/Duplizierungs-Artefakt** aus (alte Bild-Fragmente blieben stehen,
neue überlagerten sie teilweise) — stabil über mehrere Screenshots, kein Einzelbild-
Rendering-Glitch.

**Zwei geprüfte Erklärungen ausgeschlossen bzw. widerlegt:**
- Fontconfig-Kaltstart (üblicher Verdächtiger für langsame erste Text-Metrik-Abfragen):
  **ausgeschlossen** — `~/.cache/fontconfig` existiert bereits seit 2026-06-29, war beim
  Test längst warm.
- „Erststart kompiliert aus Quellcode, ist deshalb langsam" (`-S` ohne `raco make`/`raco
  setup` — bestätigt: `mred/private/compiled/app_rkt.zo` blieb über die gesamte Session
  auf dem Stand vom 12.07., wird von `racket -S` nie neu geschrieben, jeder Prozessstart
  kompiliert neu aus Quellcode): erklärt die generell mehrminütigen Startzeiten dieser
  Session, **aber nicht** das eigentliche Rätsel — die ersten vier Bilder derselben
  Modul-Auswertung erschienen sofort, nur das fünfte fehlte weitere 8+ Minuten.

**Arbeitshypothese (nicht verifiziert):** derselbe architektonische Schwachpunkt wie beim
`test-dock-size`-Befund (siehe Facette 3) — `wx/qt/queue.rkt`s reiner 50ms-Poll-Pump
(kein echtes OS-Wakeup) löst den Repaint für frisch eingefügten Interactions-Inhalt nicht
zuverlässig zeitnah aus; ein externes X11-Event (Klick/Scroll) scheint ihn anzustoßen.
Deckt sich mit dem in Facette 3 unabhängig gefundenen Diskriminator. **Nicht root-
gecausert**, eigener Befund für eine künftige Session, hier nicht weiter vertieft
(Scope-Entscheidung, Facette 3 war der Kernauftrag).

### Facette 2 — `2htdp/universe` big-bang: Kern-Wette bestätigt (über Umweg)

**Blocker (kein Qt-Bezug):** `examples/htdp-bigbang-probe.rkt` über echtes DrRacket
gestartet, „Run" → sofortiger `DrRacket Internal Error`: `require: namespace mismatch;
reference to a module that is not instantiated — module: ".../drracket-core-lib/
drracket-private/drracket-errortrace-key.rkt", phase: 1`, Stack durch
`errortrace-lib/errortrace/stacktrace.rkt:699`. **Deterministisch 2/2 unter Qt UND 1/1
nativ (identisch)** reproduziert — damit zweifelsfrei ein reines Package-Versions-Problem
unseres `-S`-Override-Startrezepts (nur `gui-lib`/`draw-lib` überschrieben, `errortrace-
lib`/`drracket-core-lib` bleiben System-Pakete, deren Phase-1-Modul-Instanziierung bei
`2htdp/universe`s größerem Require-Graph kollidiert) — **komplett unabhängig vom
Qt-Backend**, nicht `wx/qt/`, nicht in dieser Session zu beheben (Environment-Gap, nicht
Produktbug).

**Workaround, um die eigentliche Kern-Wette trotzdem zu prüfen:** dieselbe Probe-Datei
direkt via `racket -S ... examples/htdp-bigbang-probe.rkt` (ohne DrRacket/ohne
Errortrace) unter `PLT_QT=1` gestartet — Qt-Shim im Prozess bestätigt
(`/proc/<pid>/maps`). **Ergebnis: einwandfrei.**
- Tick-Zähler im World-Fenster läuft kontinuierlich und mit der deklarierten Rate hoch
  (`[on-tick tick 1]` → 1 Tick/Sekunde; zwei Screenshots im Abstand von realer Wanduhrzeit
  zeigen die erwartete Anzahl fortgeschrittener Ticks).
- `on-key` („r" → Reset auf 0) griff nach Fokus-Klick ins World-Fenster zuverlässig; die
  Schleife läuft danach unverändert weiter (kein Hänger, kein Doppel-Reset).
- Bestätigt die Kern-Wette „Racket treibt, Pump blockiert nie" für eine echte,
  interaktive big-bang-Schleife unter Qt auf Linux — kein `exec()`, keine geschachtelte
  Schleife. Deckt sich mit dem Windows-Befund, auch wenn der DrRacket-gewrappte Pfad
  wegen des Package-Problems nicht direkt getestet werden konnte.

### Facette 3 — `test-engine`/`check-expect`: Kernergebnis der Session, vollständig n=3

`examples/htdp-tests-probe.rkt` (absichtlich fehlschlagender `check-expect`). Automatisiert
über `xdotool` (Fenstersuche + relative Klicks je Fenstergeometrie, kein Pixel-Raten aus
Screenshots), je Sequenz frischer Prozess.

**Schritt A — nur ein Tab (historischer Linux-Auslöser laut §19/STATUS 2026-07-12: „reicht
schon 1 Tab"):**

| | Qt (`PLT_QT=1`) | Nativ (GTK, kein `PLT_QT`) |
|---|---|---|
| Ergebnis | **3/3 sauber** („Ran 3 tests. 1 of 3 tests failed.", kein Fehler) | 3/3 sauber |

Die alte Linux-Notiz „ein Tab reicht" hat sich in dieser Session **nicht** reproduziert —
plausibel intermittierend oder an einen anderen Zustand geknüpft (Prozess-Historie,
Preference-Vorbelegung); nicht weiter untersucht, da Schritt B (s. u.) ohnehin der
robustere, Windows-deckungsgleiche Auslöser ist.

**Schritt B — Windows-Trigger-Sequenz (1 Tab → `File → Open` zweiter Tab):**

| | Qt (`PLT_QT=1`) | Nativ (GTK, kein `PLT_QT`) |
|---|---|---|
| Ergebnis | **3/3 Absturz** | **3/3 sauber** |

Identischer Fehler bei allen drei Qt-Läufen: `DrRacket Internal Error` —
`preferences:set: new value doesn't satisfy preferences:set-default predicate — pref
symbol: 'test-engine:test-dock-size — given: '(1)`, Stack über `test-panel%`s `remove`
(`test-tool.rkt:267`) ← `undock-tests` ← `on-tab-change` — **byte-identisch** zum
Windows-Befund (§23) und zum ursprünglichen macOS/Linux-Fund (§19). Alle drei nativen
Läufe: zweiter Tab öffnet sich normal (Tab-Leiste zeigt beide Dateien), kein Fehler,
Prozess bleibt voll funktionsfähig.

**Qt-Shim-Nachweis je Lauf:** bei allen 6 Qt-Läufen `grep -c libracketqtshim
/proc/<pid>/maps` > 0 bestätigt vor dem Test; bei allen 6 nativen Läufen 0 (kein Treffer)
bestätigt.

## Phase 2 — Einordnung

**Verdikt `test-dock-size`: Windows-Reklassifizierung vollständig auf Linux bestätigt und
generalisiert.** Über beide Plattformen kombiniert: **7/7 Crash unter Qt** bei der
1→2-Tab-Sequenz (Windows 4/4 + Linux 3/3), **0/7 Crash nativ** bei derselben Sequenz
(Windows 3/3 + Linux 3/3, hier zusätzlich 0/6 auch für die reine 1-Tab-Bedingung auf
beiden Backends). Das ist eine **echte, reproduzierbare `wx/qt`-Timing-Lücke**, keine
externe htdp-lib-Baustelle — der Diskriminator aus dem Windows-Report (`is-shown?`-
Divergenz während `on-tab-change`, vermutlich verwandt mit `wx/qt/queue.rkt`s
50ms-Poll-Pump statt echtem OS-Wakeup) ist mit den Linux-Daten konsistent, hier nicht
erneut instrumentiert (Windows-Diagnose bereits ausreichend tief, keine neue Information
durch Wiederholung erwartet). Passt zusätzlich zum unabhängig in Facette 1 beobachteten
Repaint-Verzögerungsmuster (siehe oben) — zwei voneinander unabhängige Symptome, die auf
denselben architektonischen Schwachpunkt zeigen.

## Zusammenfassung

| Facette | Ergebnis |
|---|---|
| `2htdp/image` | 🟡 4/5 sofort sauber; 5. Bild (`text`+`above/align`) zeigt in einem Lauf einen 8+ Min. Repaint-Hänger, in späteren Läufen unauffällig — nicht root-gecausert, Arbeitshypothese: derselbe Pump-Schwachpunkt wie Facette 3 |
| `2htdp/universe` big-bang | ✅ Kern-Wette bestätigt (Tick/Redraw/`on-key` sauber unter Qt) — DrRacket-Pfad durch unabhängiges `-S`/errortrace-Package-Problem blockiert (kein Qt-Bezug), Workaround über `racket` direkt |
| `test-engine`/`check-expect` (`test-dock-size`) | 🔴 **3/3 Absturz** bei 1→2-Tab-Sequenz unter Qt, **0/3** nativ; 3/3 sauber bei nur 1 Tab auf beiden Seiten — bestätigt Windows-Befund vollständig, generalisiert auf Linux |

Smoke 3/3 vor der Session. Keine gui-lib-Submodul-Änderungen (reine Diagnose/Validierung,
keine Fixes). Umbrella: dieser Report, `docs/HACKING.md` §23 um Linux-Spalte ergänzt,
`CLAUDE.md`-Checkpoint, `STATUS.md`-Eintrag.

**Nächster Schritt:** Push/Sync-Entscheidung (Regel 7) offen. `test-dock-size`-Fix bleibt
eigene künftige Session (Startpunkt: `wx/qt/queue.rkt`-Pump-Modell, siehe Windows-Report-
Nachtrag). Facette-1-Repaint-Befund und das `-S`/errortrace-Package-Problem (Facette 2)
sind neue, unabhängige offene Punkte für eigene künftige Sessions. macOS-Validierung
weiterhin separater Prompt.

# Report — htdp-Lackmustest (Schritt 3) — 2026-09-10 (macOS)

**Sitzungsdatum:** 2026-09-10. Fortsetzung von `docs/2026-07-14_prompt.md` (Windows-
Session lief 2026-07-14, Linux-Session ebenfalls 2026-07-14; die macOS-Validierung war
als separater, späterer Prompt vorgesehen und findet hier statt).

**Racket:** `v9.3 [cs]` (gemessen, `racket --version`) — **Umgebungsabweichung, siehe
Phase 0.** Windows/Linux liefen am 2026-07-14 auf v9.2.

**Kontext:** Fortsetzung von `docs/2026-07-14_report-win.md` und
`docs/2026-07-14_report-linux.md`. macOS ist die letzte der drei Plattformen für diesen
Lackmustest.

## Phase 0 — Umgebung (mit einer nicht-trivialen Abweichung)

- **Sync:** Umbrella `main` und Submodul (`third_party/gui`, `qt-backend`) bereits
  synchron zu `origin` (kein Pull nötig, working tree clean).
- **Racket-Versionsabweichung (neu, nicht Teil des ursprünglichen Prompts):** Homebrew
  hat den `racket`-Cask am 2026-08-19 automatisch von v9.2 auf **v9.3** aktualisiert;
  v9.2 ist auf dieser Maschine nicht mehr installiert, auch kein Downgrade-Pfad über
  Homebrew verfügbar (Cask hält nur die aktuelle Version vor). Nutzer-Rückfrage (Regel 7,
  da Umgebungsabweichung von der Drei-Maschinen-Parität): **mit v9.3 fortfahren**,
  Abweichung dokumentieren, `CLAUDE.md` aktualisieren.
- **Fork-Neukompilierung erforderlich:** die installierte Racket-Installation ist jetzt
  scope `"9.3"` (`raco pkg show -l` zeigt keine User-Pakete für diese Scope — der Fork
  läuft weiterhin per `-S`-Override, nicht verlinkt, wie zuvor). Alte `compiled/`-
  Verzeichnisse in `third_party/gui` und `third_party/draw` waren gegen v9.2 kompiliert
  (`version mismatch: expected "9.3", found "9.2"`) → gelöscht und neu gebaut:
  `raco make third_party/draw/draw-lib/racket/draw.rkt` und (mit `PLT_QT=1`)
  `raco make third_party/gui/gui-lib/mred/mred.rkt`. Beide liefen fehlerfrei durch.
- **Shim-Aktualität:** `qt-shim/build/macos-arm64/libracketqtshim.dylib` (17:04:21) neuer
  als `shim.cpp` (17:04:12) — nicht stale, kein Neubau nötig.
- **Re-Smoke:** 3/3 grün (`PLT_QT=1 racket -S ... -l raco -- test tests/smoke.rkt`).
- **Light Mode bestätigt:** `white-on-black-mode?` → `#f` (`org.racket-lang.prefs.rktd`).
- **Menü-Sanity-Check:** DrRacket unter `PLT_QT=1` zeigt 9 App-eigene Menüs (App-Menü
  `racket` + File/Edit/View/Language/Racket/Insert/Scripts/Windows/Help) — inkl. „Windows"
  (der in `CLAUDE.md` als gelegentlich fehlend notierte Nebenbefund trat in dieser
  Session nicht auf). Keine Regression.
- **GUI-Automatisierung:** `osascript`/System Events benötigte zunächst eine
  Bedienungshilfen-Freigabe für iTerm2 (macOS-Fehler `-1719`), die der Nutzer erteilt und
  iTerm2 danach neu gestartet hat. Auch danach blieb die Automatisierung **intermittierend
  fehlschlagend** (wiederholt `-1719`/`-1728` bei sonst identischen Aufrufen, ohne
  erkennbares Muster) — Workaround: Aufrufe bei Fehlschlag 1–2× wiederholt, danach
  zuverlässig. Kein Produktbug, reines macOS-TCC/Automatisierungs-Artefakt dieser Session.

**Checkpoint 0: grün (mit dokumentierter Racket-9.3-Abweichung)** → Phase 1.

## Phase 1 — htdp end-to-end (drei Facetten)

Alle drei Facetten über echtes DrRacket (`racket -S third_party/gui/gui-lib -S
third_party/draw/draw-lib -l drracket -- <probe>.rkt`), Steuerung per `osascript`/System
Events (Menüs, Dateidialog, Tastatur), Verifikation per `screencapture`.

**Backend-Fingerprint je Lauf (statt eines direkten Prozess-Flag-Checks wie unter
Windows/Linux):** Qt-Läufe (`PLT_QT=1`) zeigen beim `File → Open` den **Qt-eigenen**
Dateidialog („Select a file", `Look in:`-Dropdown, `File name:`-Textfeld, Racket-
Sources-Filter — screenshot-bestätigt), native Läufe (kein `PLT_QT`) zeigen den
**Cocoa-`NSOpenPanel`** (Recents/Shared/Favorites-Sidebar, Spaltenansicht,
`Cmd+Shift+G`-Pfadeingabe). Zusätzlich mit `lsof -p <pid> | grep racketqtshim`
stichprobenartig verifiziert: ein Qt-Lauf zeigt `libracketqtshim.dylib` als geladene
`.dylib` (`txt`-Eintrag), ein nativer Lauf zeigt keinen Treffer.

**Facette 1 — `2htdp/image`: einwandfrei.** Alle 5 Bild-Ausdrücke aus
`examples/htdp-image-probe.rkt` rendern beim „Run" sofort korrekt als Snips im
Interactions-Fenster (Kreis, Rechteck-Outline, `overlay`, `beside`,
`above/align`+`text`), Screenshot-bestätigt. Deckt sich mit dem Windows-Befund; der auf
Linux beobachtete Repaint-Defekt (nur die ersten 4 von 5 Werten rendern) trat auf macOS
**nicht** auf.

**Facette 2 — `2htdp/universe` big-bang: einwandfrei.** `examples/htdp-bigbang-probe.rkt`
lief direkt über echtes DrRacket unter `PLT_QT=1` durch — **kein** Errortrace-/
Namespace-Mismatch wie auf Linux vor dessen Link-Fix (macOS nutzt weiterhin `-S`, aber
die Kollision trat hier nicht auf). Tick-Log lief kontinuierlich (`tick: 0` … `tick: 14`,
World-Fenster zeigte synchron „16"), `on-key` (Taste „r" → Reset) griff zuverlässig
(Fenster zeigte danach „3", Loop lief unverändert weiter). Bestätigt die Kern-Wette
„Racket treibt, Pump blockiert nie" für eine echte interaktive big-bang-Schleife auf
macOS — kein `exec()`, keine geschachtelte Schleife.

**Facette 3 — `test-engine`/`check-expect` (`test-dock-size`): Absturz reproduziert,
n=3/3 Qt, n=3/3 nativ sauber — vollständige Drei-Plattform-Bestätigung.**

Kontrollierte Sequenz (identisch zu Windows/Linux): `examples/htdp-tests-probe.rkt`
(absichtlich fehlschlagender `check-expect`) als erster Tab, „Run" — **für jeden der
6 Läufe (3 Qt + 3 nativ) per Screenshot bestätigt, dass „Ran 3 tests. 1 of the 3 tests
failed." tatsächlich erschien, bevor** der zweite Tab geöffnet wurde —, dann
`File → Open` von `examples/htdp-image-probe.rkt` als zweiter Tab.

| | Qt (`PLT_QT=1`) | Nativ (Cocoa, kein `PLT_QT`) |
|---|---|---|
| 1 Tab (Run bestätigt) → `File → Open` 2. Tab | **3/3 Absturz** | **3/3 sauber** |

Fehler bei allen 3 Qt-Läufen byte-identisch zu Windows/Linux: `DrRacket Internal Error` —
`preferences:set: new value doesn't satisfy preferences:set-default predicate — pref
symbol: 'test-engine:test-dock-size — given: '(1)`, Stack über `test-panel%`s `remove`
(`test-engine/test-tool.rkt:267:8`) ← `undock-tests` ← `on-tab-change`. Für den ersten der
3 Qt-Läufe screenshot-bestätigt: Prozess überlebt den Absturz (Definitions-Editor bleibt
bedienbar, Interactions-Leiste verschwindet, OK-Klick auf den Error-Dialog erfolgreich);
für Läufe 2/3 nur die erfolgreiche Fehlerdialog-Bedienung (OK-Klick) bestätigt, der
Interactions-Zustand danach nicht erneut einzeln screenshot-geprüft. Alle 3 nativen Läufe:
zweiter Tab öffnet sich normal (beide Dateien in der Tab-Leiste sichtbar), kein Fehler.

**Zusätzlicher, unkontrollierter Beleg vor der methodischen Messung (mit Einschränkung):**
der allererste Qt-Lauf dieser Session crashte bereits vor der eigentlichen n=3-Messung, in
einem Fenster, dessen genauer UI-Zustand nach vorangegangenen fehlgeleiteten
Tastatureingaben (ein Find-Toolbar war mit unklarem Inhalt „prime" offen) nicht mehr
zweifelsfrei rekonstruierbar war. Ein per Accessibility-Introspektion gefundener
„Hide"-Button löste beim Klick denselben `test-dock-size`-Absturz aus — die Introspektion
selbst war jedoch bei wiederholten Abfragen instabil (unterschiedliche Button-Listen je
Aufruf, ein Aufruf hing 120s). **Aus diesem einzelnen, nicht isolierten Vorfall wird daher
kein Mechanismus abgeleitet** (insbesondere keine Aussage über eine angeblich immer
vorhandene Test-Dock-Infrastruktur) — er wird nur als zusätzlicher Beleg festgehalten,
dass ein Absturz mit identischer Fehlersignatur auch außerhalb der genau kontrollierten
1→2-Tab-Sequenz auftreten kann.

## Phase 2 — Einordnung (Nativ als Orakel)

**Verdikt `test-dock-size`: Windows+Linux-Reklassifizierung auf macOS vollständig
bestätigt — jetzt auf allen drei Plattformen verifiziert.** Kombiniert über alle drei
Maschinen: **10/10 Crash unter Qt** (Windows 4/4 + Linux 3/3 + macOS 3/3) bei der
1→2-Tab-Sequenz, **0/10 nativ** (Windows 3/3 + Linux 3/3 + macOS 3/3) bei derselben
Sequenz — auf macOS für beide Bedingungen jeweils mit vorher screenshot-bestätigtem
erfolgreichem „Run". Eine echte, plattformübergreifend reproduzierbare `wx/qt`-
Timing-Lücke, kein htdp-lib-Bug. Die Racket-9.3-Umstellung auf macOS ändert daran nichts —
der native Cocoa-Pfad bleibt unter v9.3 identisch sauber (3/3), was zusätzlich
ausschließt, dass die Versionsabweichung selbst (statt Qt) die Ursache ist.

Der in Windows/Linux benannte Root-Cause-Kandidat (`is-shown?`-Divergenz während
`on-tab-change`, vermutlich verwandt mit `wx/qt/queue.rkt`s 50ms-Poll-Pump statt echtem
OS-Wakeup) wurde auf macOS nicht erneut instrumentiert — keine neue Information
gegenüber der bereits tiefen Windows-Diagnose erwartet, und macOS' Ergebnis ist damit
konsistent.

## Zusammenfassung

| Facette | Ergebnis |
|---|---|
| `2htdp/image` | ✅ einwandfrei (alle 5 Bilder sofort korrekt) |
| `2htdp/universe` big-bang | ✅ einwandfrei, Kern-Wette bestätigt, kein `-S`/Errortrace-Problem (anders als Linux vor dessen Fix) |
| `test-engine`/`check-expect` (`test-dock-size`) | 🔴 **3/3 Absturz** bei 1→2-Tab-Sequenz unter Qt (Run vorher bestätigt), **0/3** nativ (Run vorher ebenfalls bestätigt) — bestätigt Windows+Linux, macOS komplettiert die Drei-Plattform-Verifikation (10/10 Qt-Crash, 0/10 nativ kombiniert) |

Smoke 3/3 vor und nach der Session. Keine gui-lib-Submodul-Änderungen (reine Diagnose,
kein Fix). Ein Automatisierungsartefakt (eine versehentlich eingefügte Leerzeile in
`examples/htdp-tests-probe.rkt`, durch eine fehlgeleitete Tastatureingabe während der
UI-Automatisierung) wurde bemerkt und per `git checkout` zurückgesetzt, bevor er
committet wurde.

**Nächster Schritt:** `test-dock-size`-Fix bleibt eigene künftige Session (Startpunkt
weiterhin `wx/qt/queue.rkt`-Pump-Modell, jetzt auf allen drei Plattformen bestätigt).
Racket-9.3-Umstellung auf macOS ist strukturell vollzogen (Fork neu kompiliert, Smoke
grün) — sollte in einer künftigen Session beobachtet werden, ob Homebrew weitere
Auto-Updates vornimmt, die die Drei-Maschinen-Parität erneut verändern. Push/Sync-
Entscheidung (Regel 7) wird am Ende dieser Session direkt mit dem Nutzer geklärt, nicht
als offener Punkt stehen gelassen.

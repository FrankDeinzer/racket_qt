# Report — htdp-Lackmustest (Schritt 3) — 2026-07-14 (Windows)

**Racket:** `v9.2 [cs]` (gemessen, `racket --version`).

## Phase 0 — Umgebung

- Sync: gui-Submodul (`third_party/gui`) @ `54f2f702`, Umbrella-Zeiger passend — kein
  Pull nötig.
- Shim-Aktualität: **stale** — `shim.cpp` (18:36:53, §22-Fix) neuer als die Debug-DLL
  (12:42:11). Neu gebaut vor Testbeginn (`cmake --build qt-shim/build/windows-x64
  --config Debug`).
- Light Mode bestätigt: `(preferences:get 'framework:white-on-black-mode?)` → `#f`.
- Re-Smoke vor Start: 3/3 grün.
- Menü-Sanity-Check (Hygiene nach §22-Pull): DrRacket-Hauptmenü unter `PLT_QT=1`
  zeigt weiterhin alle 9 Einträge (File/Edit/View/Language/Racket/Insert/Scripts/Tabs/
  Help), keine Regression — §22 Part B ist auf Windows wie erwartet No-op.

**Checkpoint 0: alles grün** → Phase 1.

## Phase 1 — htdp end-to-end (drei Facetten)

Drei neue Probe-Dateien (`examples/htdp-image-probe.rkt`, `htdp-bigbang-probe.rkt`,
`htdp-tests-probe.rkt`), jeweils via `DrRacket.exe <pfad>` geöffnet (nicht in den
laufenden Editor getippt — vermeidet den bekannten Autosave/Recover-Files-Pfad, §13).

**Facette 1 — `2htdp/image`:** einwandfrei. Fünf Bild-Ausdrücke rendern im
Interactions-Fenster korrekt als Snips (Kreis, Rechteck-Outline, `overlay`, `beside`,
`text`+`above/align`), Screenshot-bestätigt.

**Facette 2 — `2htdp/universe` big-bang:** einwandfrei. Unbedingter `printf` im
`on-tick`-Handler trennt „Loop läuft" (Tick-Stream in Interactions) von „Loop rendert"
(Screenshot des World-Fensters): beide korrelieren exakt (z. B. Tick-Log bis „tick: 8"
→ Anzeige „9"). `on-key` (Taste „r" → Reset auf 0) bestätigt funktionsfähig, Loop läuft
nach dem Reset unverändert weiter (bis „19" beobachtet). Kern-Wette „Racket treibt,
Pump blockiert nie" für eine reale interaktive big-bang-Schleife bestätigt — kein
`exec()`, keine geschachtelte Schleife.

**Facette 3 — `test-engine`/`check-expect`:** der historische Absturz
(`test-engine:test-dock-size`-Contract-Verstoß, §19) reproduziert sich zuverlässig.
Ablauf: `htdp-tests-probe.rkt` (ein absichtlich fehlschlagender `check-expect`) als
einzige Registerkarte, „Run" → Test-Report korrekt. `File → Open` von
`htdp-image-probe.rkt` als zweite Registerkarte → **`DrRacket Internal Error`**:
`preferences:set: new value doesn't satisfy preferences:set-default predicate — pref
symbol: 'test-engine:test-dock-size — given: '(1)`, Stack über `test-panel%::remove`
(`test-tool.rkt:267`) ← `undock-tests` ← `on-tab-change`. Prozess überlebt (Definitions
editierbar, Interactions-Leiste verschwindet) — exakt wie in §19 dokumentiert.

## Phase 2 — Einordnen (Nativ als Orakel)

Identische Sequenz nativ (win32, kein `PLT_QT`) wiederholt, um den §19-Befund als
„externer htdp-lib-Bug" zu verifizieren (so die Annahme im Prompt-Guardrail).

**Ergebnis: Qt 4/4 Crash, nativ 3/3 sauber — kein htdp-lib-Bug, sondern eine
Qt-spezifische Timing-Lücke.** Das widerspricht der Prompt-Annahme direkt. Nutzer-
Rückfrage (Regel 7) ergab: vertiefte Diagnose statt nur Dokumentation.

### Instrumentierte Diagnose

Temporäre `eprintf`-Instrumentierung in `framework/private/panel.rkt`s
`dragable-mixin` (`update-percentages`, `after-new-child`, `place-children`,
`get-percentages` inkl. Caller-Stack via `continuation-mark-set->context`) — nach
Analyse vollständig zurückgesetzt (`git checkout` + `raco setup framework`), keine
dauerhafte Änderung, keine htdp-lib-Datei angefasst.

Befund:

1. `percentages` (Splitter-Anteile-Cache) wird nur bei `after-new-child`/
   `place-children` neu berechnet, nie bei reinem Kind-Entfernen. Während der
   DrRacket-internen Tab-Erstellung feuert eine Salve von `place-children`-Aufrufen,
   die kurz zwischen 1 und 2 Kindern oszilliert — **das passiert auf beiden Backends
   identisch** (Logs `tmp/qt-diag.log` vs. `tmp/native-diag.log`, nicht Teil des
   Commits, nur lokale Diagnose-Artefakte).
2. Caller-Stack-Analyse (`tmp/qt-diag2.log` vs. `tmp/native-diag2.log`) zeigt: der
   eine `get-percentages`-Aufruf, der tatsächlich in `preferences:set` mündet, kommt
   exklusiv aus `test-panel%::remove` ← `undock-tests` ← `on-tab-change`. Unter Qt
   tritt dieser Aufruf **4/4** auf (liest `children-len=1`, Absturz). **Unter nativem
   win32 tritt dieser exakte Aufruf in keinem Lauf auf** — `on-tab-change`s `cond`
   nimmt dort einen anderen Zweig.
3. Da dieser `cond`-Zweig ausschließlich von der (backend-identischen) Preference
   `test-engine:test-window:docked?` und von `(send test-panel is-shown?)` abhängt,
   lokalisiert das den Diskriminator auf: **`is-shown?`/Sichtbarkeits-Propagierung des
   Test-Dock-Widgets unterscheidet sich zwischen Qt- und win32-Backend zum Zeitpunkt
   der Tab-Erstellung** — plausibel verwandt mit `wx/qt/window.rkt`s `show()`/
   `is-shown?` (§18.1) oder mit Häufigkeit/Reihenfolge Qt-Pump-getriebener
   Resize-Events während der Tab-Erstellung. Nicht bis in den Shim verfolgt.

**Verdikt `test-dock-size`:** reklassifiziert von OUT-OF-SCOPE (externer htdp-lib-Bug)
zu einer echten, lokalisierten `wx/qt`-Lücke. Root-Cause bis zum Diskriminator
eingegrenzt, aber nicht bis zur letzten Ursache im Shim verfolgt — **kein Fix in dieser
Session** (Diagnose-Charakter, Nutzer-Entscheidung). Empfehlung für die Fix-Session:
`wx/qt/window.rkt` (`is-shown?`/`show()`-Propagierung) und `wx/qt/frame.rkt`
(Resize-Event-Timing während Tab-/Fenster-Erzeugung) als Startpunkt.

## Nebenartefakt (eigener Automatisierungsfehler, kein Produktbug)

Beim `on-key`-Test des big-bang-Fensters landete ein Fokus-Fehlgriff (Fenster-
Automatisierung) einen Tastendruck „r" versehentlich im Definitions-Puffer statt im
World-Fenster. Sofort per Undo-Versuch bemerkt, Datei auf der Platte war unverändert
(nicht gespeichert) — Prozess sauber beendet, unmodifizierte Datei neu geladen, kein
Datenverlust. Der resultierende harte Kill erzeugte ein Autosave-Backup; der
`Recover Files`-Dialog zeigte die Diskrepanz korrekt an (Original sauber, Backup mit
„r"), Backup gelöscht. Der anschließende „Done"-Klick löste einen separaten,
generischen `framework/private/autosave.rkt`-Bug aus (`copy-file: copy failed`,
`win_err=2`, `recover-file`) — benannte die Originaldatei kurzzeitig in
`htdp-bigbang-probe.rkt-autorec.htdp-bigbang-probe` um, Inhalt blieb byte-identisch
zum sauberen Original (MD5-verifiziert), manuell zurückbenannt. Kein `wx/qt`-Bezug
(generischer Windows-Pfad-Bug in Shared-Code), nicht weiter verfolgt, rein informativ
in `docs/HACKING.md` §23 festgehalten.

## Zusammenfassung

| Facette | Ergebnis |
|---|---|
| `2htdp/image` | ✅ einwandfrei |
| `2htdp/universe` big-bang | ✅ einwandfrei, Kern-Wette bestätigt |
| `test-engine`/`check-expect` | 🔴 Absturz reproduziert (4/4 Qt, 0/3 nativ) — **echte `wx/qt`-Lücke**, nicht htdp-lib; Root-Cause bis `on-tab-change`-Dispatch/`is-shown?` eingegrenzt, Fix offen |

Smoke 3/3 vor und nach der gesamten Session. Keine gui-lib-Submodul-Änderungen
(Instrumentierung vollständig revertiert, verifiziert `git status` clean). Umbrella:
drei neue `examples/htdp-*-probe.rkt`, `docs/HACKING.md` §23, `CLAUDE.md`-Checkpoint,
`STATUS.md`-Eintrag, dieser Report.

**Nächster Schritt:** Push/Sync-Entscheidung (Regel 7) offen. Eigene künftige Session
für die `wx/qt`-Root-Cause-Fixdiagnose; macOS/Linux-Validierung dieser Session
separater Prompt (Windows führt laut Auftrag).

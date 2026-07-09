# Bericht — Clean-Start-Check (2026-07-09_prompt, Linux-Zweig)

**Datum:** 2026-07-09
**Plattform:** Linux x86_64, X11 (`DISPLAY=:0`)
**Repro:** echtes `PLT_QT=1 racket -S third_party/gui/gui-lib -S third_party/draw/draw-lib -l drracket`
**Startrezept:** kein Installation-Link auf dieser Maschine — `-S`-Source-Override zwingend
(sonst stiller Fallback auf gtk).

**Kurzfassung:** Nur Phase 0 + Phase 1 (Windows hatte bereits beide Ziele der Session
erledigt, siehe `docs/2026-07-09_report-win.md`). Repo-Sync nachgezogen, Shim neu gebaut,
Bytecode neu kompiliert, Re-Smoke grün, echter `PLT_QT=1`-DrRacket-Start **sauber** —
keine neue Landmine gezündet. Phase 2 (Redraw-Messung) ist laut Prompt Windows-exklusiv,
hier nicht wiederholt.

## 1. Phase 0 — Stand verifiziert

- `racket --version` → **v9.2 [cs]** (gemessen, über `/home/deinzer/racket/bin/racket`,
  nicht im `$PATH`).
- gui-Submodul (`third_party/gui`, Branch `qt-backend`): Umbrella-HEAD referenzierte bereits
  `87ebd078` (Ledger-Zeiger aus der Windows-Session), aber das ausgecheckte Submodul stand
  noch auf `6df80516` (2 Commits dahinter, Objekte lokal bereits vorhanden — kein
  Netzwerk-Fetch nötig). Nutzer vorab gefragt (CLAUDE.md Regel 7): `git submodule update`
  (Working-Tree-Sync) und danach `git -C third_party/gui pull --ff-only` auf dem lokalen
  `qt-backend`-Branch-Pointer, beide auf Zustimmung ausgeführt. Submodul jetzt auf `87ebd078`,
  Branch `qt-backend`, „up to date with origin/qt-backend".
- Umbrella (`main`): war bereits saubere `HEAD` auf `1d946cf` — kein Pull nötig.
- **Shim war veraltet:** `qt-shim/src/shim.cpp` (enthält die gated `PLT_QT_DEBUG`-Diagnose-
  Hooks aus der Windows-Session, Commit `d7e9bf6`) war neuer als die gebaute
  `libracketqtshim.so` (zuletzt am 2026-07-08 gebaut) → `cmake --build
  qt-shim/build/linux-x64` neu ausgeführt (Ninja, saubere Rebuild).
- **Bytecode neu:** Linux nutzt `-S`-Source-Override, kein Installation-Link → `raco make`
  hat keinen `-S`-Schalter; stattdessen `racket -S third_party/gui/gui-lib -S
  third_party/draw/draw-lib -l raco -- make -l mred` (kompiliert `mred` inkl.
  `mred/private/wx/qt/**` gegen die Source-Override-Pfade).
- Re-Smoke: `PLT_QT=1 QT_PLUGIN_PATH=~/Qt/6.11.1/gcc_64/plugins racket -S
  third_party/gui/gui-lib -S third_party/draw/draw-lib -l raco -- test tests/smoke.rkt` →
  **3 tests passed**. Ausgabe zeigt `#<thread:...ate/wx/qt/queue.rkt:27:5>` — Beleg, dass die
  `-S`-Overrides tatsächlich das Qt-Backend laden (nicht der stille gtk-Fallback, den die
  Vorsession für diese Maschine dokumentiert hat), da dieser Ladepfad identisch mit dem
  DrRacket-Start in Phase 1 ist.

## 2. Phase 1 — Clean-Start-Check: sauber

Kein laufender DrRacket-Prozess vorab (`ps aux | grep drracket`, leer). Start via
`PLT_QT=1 QT_PLUGIN_PATH=~/Qt/6.11.1/gcc_64/plugins racket -S third_party/gui/gui-lib -S
third_party/draw/draw-lib -l drracket` im Hintergrund. Splash-Fenster erscheint kurz
(„DrRacket 9.2", 400×324 — Startup-Bytecode-Kompilation, ~85%→~50% CPU über ~25s, konsistent
mit der bekannten Linux-Startup-Charakteristik), danach Hauptfenster „Untitled - DrRacket"
(600×650). Kein Crash-Dialog, Prozess bleibt lebendig. Screenshot per `xwd -root -silent`
+ eigenem XWD→PNG-Parser (kein XWD-Codec in Pillow, siehe Vorsession-Notiz) bestätigt:

- **9 Menüs** sichtbar und horizontal: File, Edit, View, Language, Racket, Insert, Scripts,
  Tabs, Help.
- Definitions-Editor sichtbar (Zeile 1, „More Information"-Tab-Leiste, „Run"-Button).
- Interactions-/REPL-Bereich sichtbar mit `>`-Prompt.

**Ergebnis: sauber beim ersten Start, keine neue Landmine gezündet.** Prozess danach
kontrolliert beendet (`kill`).

## 3. Guardrails eingehalten

- Kein `exec()`/`QEventLoop`, keine geschachtelte Schleife — nicht berührt.
- cocoa/gtk/win32 nicht angefasst.
- Sync-Schritte (`git submodule update`, `git pull --ff-only` im Submodul) vorab per
  `AskUserQuestion` bestätigt, einzeln (Regel 7).
- Kein Fix-Commit — keine Landmine gezündet, also kein Stub nötig.
- Redraw-Bug: nicht erneut gemessen (Phase 2 ist laut Prompt Windows-exklusiv); Linux hatte
  bereits einen unabhängigen Redraw-Befund aus der Vorsession (`project_menu_redraw_diagnosis`
  Memory) — hier nicht wiederholt, kein neuer Fix.

## 4. Commits & Stand

Keine Code-Änderungen in dieser Session (reiner Sync-, Rebuild- und Verifikations-Schritt,
keine Landmine gezündet). Einzige lokale Zustandsänderung: Submodul-Working-Tree jetzt
deckungsgleich mit dem bereits vom Umbrella referenzierten `87ebd078` — kein neuer Commit,
kein Push nötig.

## 5. Nächste Schritte

- **macOS:** Phase 0/1 dieses Prompts steht auf der macOS-Maschine noch aus (dort nicht
  ausgeführt — diese Session lief auf der Linux-Maschine).
- Redraw-Bug-**Fix** bleibt eine eigene Session (Windows-Root-Cause-Kandidat aus
  `docs/2026-07-09_report-win.md` als Ausgangspunkt), plattformübergreifend zu verifizieren.

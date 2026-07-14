# Report — Block B: `tab-panel%`/`canvas-panel%`/`group-panel%` echt — macOS-Validierung — 2026-07-13-3

**Racket:** `v9.2 [cs]` (gemessen, `racket --version`).

Fortsetzung von `docs/2026-07-13-3_report-win.md` (Implementierung dort abgeschlossen,
Windows-seitig Nutzer-bestätigt) und `docs/2026-07-13-3_report-linux.md`
(Linux-Validierung, alle vier gui-Commits bereits gepusht laut `git log
origin/qt-backend`). Diese Session validiert dieselben drei Widgets + den
`show()`-Fix auf macOS — kein neuer `wx/qt/`-/`shim.cpp`-Code, aber ein signifikanter
neuer Befund (§ unten).

## Phase 0 — Umgebung

- **Sync-CHECK:** Umbrella-`main` stand bereits korrekt auf gui @ `f6f38474`
  (`860fd98 chore(gui): bump qt-backend submodule pointer to f6f38474`). Lokaler
  gui-Submodul-Checkout auf dieser Maschine war **stale**: `3ba8fa75`, 4 Commits hinter
  `origin/qt-backend` (dieselben vier Windows-Commits wie bei der Linux-Session, per
  `git log origin/qt-backend` verifiziert bereits vorhanden). Nutzer vor dem Pull
  gefragt (Regel 7) → bestätigt → Fast-Forward `3ba8fa75` → `f6f38474`, reine lokale
  Zeigerbewegung, kein Netzwerk-Push.
- **Shim-Aktualität:** `qt-shim/src/shim.cpp` (letzter Commit-Zeitstempel
  2026-07-14 12:19) neuer als `qt-shim/build/macos-arm64/libracketqtshim.dylib`
  (13. Juli 19:44) → Rebuild nötig (stale-Shim-Falle). `cmake --build
  qt-shim/build/macos-arm64` — sauber, keine Warnungen.
- **Light Mode:** kein `framework:white-on-black-mode?`-Eintrag in
  `~/Library/Racket/racket-prefs.rktd` → Default `#f` (analog Windows/Linux).
- **Re-Smoke vor der Probe:** 3/3 grün (`raco test tests/smoke.rkt` unter
  `PLT_QT=1`).

**Checkpoint 0:** alles grün, kein STOPP nötig.

## Phase 1/2 — Orakel/Implementierung

Entfällt — bereits auf Windows abgeschlossen (`docs/2026-07-13-3_report-win.md`,
`docs/HACKING.md` §21). Diese Session ändert keinen `wx/qt/*.rkt`- oder
`shim.cpp`-Code.

## Phase 3 — Validierung (macOS, mit Abweichung vom geplanten Ablauf)

1. **Isolierter Probe** (`examples/tab-panel-probe.rkt`, unverändert übernommen):
   Tab-Wechsel Alpha/Beta/Gamma schaltet den Kind-Inhalt korrekt um; alle vier
   „via code"-Buttons funktional korrekt, kein Retrigger des eigenen Callbacks.
   Nutzer-bestätigt. Konsolen-Log bestätigt exakt dasselbe Muster wie Windows/Linux.
   Regulärer `SIGTERM`-Exit, kein Absturz.

2. **Echter DrRacket-Preferences-Dialog — BLOCKIERT durch einen neuen, unabhängigen
   Befund:** Edit-Menü enthält kein „Preferences…". Das ist auf macOS **erwartet**
   (Framework unterdrückt diesen Menüpunkt dort, weil Cocoa normalerweise selbst einen
   nativen bereitstellt — s. Root-Cause-Analyse unten). Der Klick auf den App-Menü-
   Eintrag an der konventionellen „Preferences"-Stelle (Menü „racket") löste jedoch
   **nicht** den Preferences-Dialog aus, sondern DrRackets Help-Menü-Punkt „Configure
   Command Line for Racket…" — inklusive `authopen`-Sudo-Passwortabfrage und dem
   abschließenden „PATH has been configured…"-Infofenster. Per Nutzer-Retest (frischer
   Start, direkter Klick, nichts vorher berührt) reproduziert (2/2).

   Root-Cause vollständig geklärt (Details, Code-Referenzen: `docs/HACKING.md` §22),
   Kurzfassung — zwei sich addierende Ursachen:
   - `mred/private/app.rkt`s `current-eventspace-has-standard-menus?` entscheidet rein
     über `(system-type) = 'macosx`, unabhängig vom wx-Backend. Auf Cocoa korrekt
     (dort registriert `wx/cocoa/menu-bar.rkt` einen eigenen nativen Preferences-Hook,
     der reguläre Edit→Preferences-Punkt wird deshalb absichtlich unterdrückt); unser
     Qt-Backend hat kein Äquivalent zu diesem Hook — der Menüpunkt existiert auf macOS
     mit unserem Backend **nirgends** regulär.
   - Qt's macOS-Cocoa-Integration weist jedem `QAction` automatisch eine `MenuRole`
     per Text-Heuristik zu; unser `shim_action_create` setzt nirgends
     `setMenuRole(...)`. Der Text „**Configure** Command Line for Racket…" matched
     Qt's Heuristik für `PreferencesRole` und wird deshalb fälschlich ins App-Menü
     verschoben.

   **Nicht gefixt** — ein einzeiliger `setMenuRole(NoRole)`-Fix würde nur die zweite
   Ursache beheben, aber weiterhin keinen funktionierenden Preferences-Zugang schaffen
   (Ursache 1 bleibt). Der eigentliche Fix bräuchte ein Qt-Äquivalent zu
   `wx/cocoa/queue.rkt`s `openPreferences:`-Hook — zu groß für diese Session, nach
   Advisor-Rücksprache als eigene künftige Session zurückgestellt (Muster wie beim
   Resize-Bug, §21.7).

   **Direkter Discriminator-Test:** `(require framework) (preferences:show-dialog)` im
   DrRacket-Interactions-Fenster (umgeht den Menü-Pfad komplett) öffnet den echten
   Preferences-Dialog-Frame (Titel „Preferences", Standard-Buttons „Revert All
   Preferences to Defaults"/„Undo Changes and Close"/„OK") — aber mit **leerem**
   Inhaltsbereich, weil diese isolierte Modul-Instanz keine der DrRacket-eigenen
   Kategorien (Tabs/Font/Colors/Browser/…) registriert hat. Bestätigt: der Dialog
   selbst und `tab-panel%` (der die Kategorie-Nav trägt) sind intakt — der Bug liegt
   ausschließlich im Menü-Dispatch, nicht in den drei validierten Widgets.

3. **Fallback-Validierung für `canvas-panel%`/`group-panel%`** (da der reguläre
   Dialog-Pfad blockiert war, nach Nutzer-Bestätigung): zwei neue isolierte Proben,
   mirrored an `tab-panel-probe.rkt`:
   - `examples/canvas-panel-probe.rkt`: `editor-canvas%` mit
     `hide-hscroll`/`hide-vscroll`-Stil (exakt `color-prefs.rkt`s `canvas:color%`-
     Konfiguration). Oversized-Textinhalt triggert `canvas-autoscroll-mixin`s interne
     `set-scrollbars`-Neuberechnung — kein Absturz. Nutzer-bestätigt (Scrollbar mit
     Cursor sichtbar, Scroll-Buttons funktionieren nach einer Korrektur der
     Proben-eigenen `scroll-to`-Semantik auf `scroll-to-position`).
   - `examples/group-panel-probe.rkt`: `group-box-panel%` mit Radio-Box/Textfeld/
     Button als Kinder — alle bleiben innerhalb des Rahmens (kein ausreißendes
     Top-Level-Fenster, der ursprüngliche Windows-Stub-Fehlermodus), `set-label`
     ändert den Rahmentitel korrekt. Nutzer-bestätigt.

Re-Smoke nach allen Proben: 3/3 grün.

## Verifikation

- Klassen-Komposition lädt fehlerfrei (kein `public*`/`override*`-Konflikt) — durch
  erfolgreichen Start aller drei Proben sowie DrRacket bestätigt.
- Smoke 3/3 grün vor der Sitzung, 3/3 grün danach.
- `tab-panel%`: Probe Nutzer-bestätigt + Konsolen-Log-bestätigt (identisches Muster zu
  Windows/Linux).
- `canvas-panel%`/`group-panel%`: je eigene isolierte Probe, Nutzer-bestätigt (nicht
  über den echten Preferences-Dialog, da dieser durch den neuen Menü-Bug unerreichbar
  war — Dialog-Intaktheit separat per direktem `(preferences:show-dialog)`-Aufruf
  bestätigt).

## Neuer Befund: macOS-Preferences-Menü-Bug (§22, nicht gefixt)

Siehe Root-Cause-Zusammenfassung oben, volle Analyse `docs/HACKING.md` §22. Vermuteter,
aber nicht verifizierter Zusammenhang mit dem älteren, offenen Befund „macOS-Menüleiste
zeigt 8 statt 9 Einträge, `Windows`-Menü fehlt manchmal" (`STATUS.md`, Session
2026-07-09) — beides plausibel derselben Bug-Klasse (Qt's automatische
macOS-Menü-Reorganisation kollidiert mit Racket/Cocoa-spezifischen Annahmen), aber
nicht bestätigt identisch.

## Guardrails

Keine Shared-Code-Änderung, kein `wx/qt/`-Code geändert, kein neues Widget über die
drei aus der Windows-Session hinaus. Neue Scope-Erweiterung (zwei zusätzliche
Beispiel-Probes für `canvas-panel%`/`group-panel%`, als Fallback für die blockierte
Preferences-E2E-Validierung) nach explizitem Nutzer-Opt-in (Regel 7). Menü-Bug (§22)
root-caused, aber bewusst **nicht gefixt** — nach Advisor-Rücksprache als eigene
künftige Session zurückgestellt, kein Fix-Versuch unternommen. Kein `exec()`/keine
geschachtelte Event-Loop. Kein Push/Pull außer dem einen, vom Nutzer vorab
bestätigten Submodul-Fast-Forward (kein Netzwerkzugriff, Commits waren bereits
gefetchbar über `origin/qt-backend`).

## Commits

Keine neuen gui-Submodul-Commits diese Sitzung (reine Validierung, Fast-Forward auf
bereits vorhandenen `origin/qt-backend`-Stand). Umbrella (`main`), noch nicht
committed zum Zeitpunkt dieses Reports:

- `examples/canvas-panel-probe.rkt` (neu)
- `examples/group-panel-probe.rkt` (neu)
- Doku-Updates: `docs/HACKING.md` (§21.8, neuer §22), `CLAUDE.md`-Checkpoint-Tabelle,
  `STATUS.md` (neuer Eintrag), dieser Report.

## Nächster Schritt

Push/Sync-Entscheidung (Regel 7) steht noch aus. Mit dieser Session ist die
Widget-Breite (Checkpoint E: `tab-panel%`/`canvas-panel%`/`group-panel%`) auf **allen
drei Plattformen** validiert. Preferences-Ende-zu-Ende ist auf Windows/Linux
strukturell erreicht (vier bekannte Einzelbefunde offen, §21.6), auf **macOS weiterhin
blockiert** durch den neuen Menü-Bug (§22). Je eigene künftige Session für: macOS-
Preferences-Menü-Bug (§22, inkl. Klärung des vermuteten Zusammenhangs mit dem älteren
„8 statt 9 Menüs"-Befund), Resize/Reflow-Bug (§21.7), Editor-Canvas-Scrollbars,
Font-Size-Zahlen-Anzeige, Colors-Tab rechte Spalte/Rahmen, restliche
Preferences-Kategorien (Editing/Warnings/General/Profiling/Tools/Background
Expansion).

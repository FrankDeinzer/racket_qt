# Report — Block B: `tab-panel%`/`canvas-panel%`/`group-panel%` echt — Linux-Validierung — 2026-07-13-3

**Racket:** `v9.2 [cs]` (gemessen, `racket --version`).

Fortsetzung von `docs/2026-07-13-3_report-win.md` (Implementierung dort abgeschlossen,
Windows-seitig Nutzer-bestätigt, alle vier gui-Commits bereits gepusht laut
`git log origin/qt-backend`). Diese Session validiert dieselben drei Widgets +
den `show()`-Fix auf Linux — kein neuer Code, reiner Sync + Rebuild + Probe +
Preferences-Ende-zu-Ende.

## Phase 0 — Umgebung

- **Sync-CHECK:** Umbrella-`main` stand bereits korrekt auf gui @ `f6f38474`
  (`860fd98 chore(gui): bump qt-backend submodule pointer to f6f38474`, bereits vor
  Sitzungsbeginn gepusht). Lokaler gui-Submodul-Checkout auf dieser Maschine war
  **stale**: `3ba8fa75`, 4 Commits hinter `origin/qt-backend` (genau die vier
  Windows-Commits `ad33e36a`/`084cf27b`/`e478503f`/`f6f38474` — auf
  `origin/qt-backend` bereits vorhanden, per `git log origin/qt-backend` verifiziert
  vor jeder Aktion). Nutzer vor dem Pull gefragt (Regel 7) → bestätigt →
  Fast-Forward `3ba8fa75` → `f6f38474` im Submodul, keine Netzwerk-Schreibaktion,
  reine lokale Zeigerbewegung.
- **Shim-Aktualität:** `qt-shim/src/shim.cpp` (mtime nach dem Fast-Forward,
  2026-07-14 12:50) neuer als `qt-shim/build/linux-x64/libracketqtshim.so`
  (2026-07-13 19:31) → Rebuild nötig (stale-Shim-Falle, CLAUDE.md).
  `cmake --build qt-shim/build/linux-x64` — clean, keine Warnungen.
- **Light Mode:** kein `framework:white-on-black-mode?`-Eintrag in
  `~/.config/racket/racket-prefs.rktd` → Default `#f` (analog Windows/§07-13-2-Befund).
- **Re-Smoke vor der Probe:** 3/3 grün (`raco test tests/smoke.rkt` unter
  `PLT_QT=1 QT_PLUGIN_PATH=~/Qt/6.11.1/gcc_64/plugins`).

**Checkpoint 0:** alles grün, kein STOPP nötig.

## Phase 1/2 — Orakel/Implementierung

Entfällt — bereits auf Windows abgeschlossen (`docs/2026-07-13-3_report-win.md`,
`docs/HACKING.md` §21). Diese Session ändert keinen `wx/qt/*.rkt`- oder
`shim.cpp`-Code.

## Phase 3 — Validierung (doppelt, Linux)

1. **Isolierter Probe** (`examples/tab-panel-probe.rkt`, unverändert übernommen):
   Tab-Wechsel Alpha/Beta/Gamma schaltet den Kind-Inhalt korrekt um; alle vier
   „via code"-Buttons (`set-selection`/`set-item-label`/`append`/`delete`)
   funktional korrekt, **kein** Retrigger des eigenen Callbacks. Nutzer-bestätigt.
   Konsolen-Log (per Hintergrundprozess-Capture, flushte vollständig erst beim
   `SIGTERM`-Exit, nicht laufend — abweichend von der 07-13-2-Session, aber
   inhaltlich vollständig) bestätigt die Nutzer-Aussage exakt:

   ```
   initial: count=3 selection=0 label0=Alpha
   tab-panel% callback fired: selection=1 (Beta)
   tab-panel% callback fired: selection=2 (Gamma)
   tab-panel% callback fired: selection=1 (Beta)
   tab-panel% callback fired: selection=0 (Alpha)
   set-selection 2 done, now selection=2      ; kein Callback
   set-selection 2 done, now selection=2      ; erneut kein Callback
   set-item-label 0 done, now label=Alpha!    ; kein Callback direkt danach
   tab-panel% callback fired: selection=0 (Alpha!)   ; nachfolgender echter Tab-Klick
   append done, now count=4
   delete 1 done, now count=3 selection=0
   Alpha button clicked (1)
   ```

   Callback feuert ausschließlich bei echten Tab-Klicks, nie bei einem der vier
   `set-*`/`append`/`delete`-Aufrufe via Code — bestätigt den `QSignalBlocker`-Schutz
   (§21) auf Linux genauso wie auf Windows.

2. **Echter DrRacket-Preferences-Dialog:** `PLT_QT=1 QT_PLUGIN_PATH=~/Qt/6.11.1/gcc_64/plugins
   racket -S third_party/gui/gui-lib -S third_party/draw/draw-lib -l drracket`.
   Preferences öffnet end-to-end (Kategorie-Nav über `tab-panel%` funktioniert),
   Nutzer hat mindestens Tabs/Font/Colors/Browser durchgeklickt und bestätigt —
   derselbe integrierende Beweis wie auf Windows, jetzt auch auf Linux erbracht.
   Kein Absturz beim Wechsel in die Colors-Kategorie (`canvas-panel%`-Fix) oder
   in den Browser-Tab (`group-panel%`-Fix).

Beide Prozesse per `SIGTERM` beendet (nicht über den Fenster-Schließen-Knopf, um
das offene Teardown-Thema „Crash B" nicht versehentlich zu berühren — bleibt
außerhalb des Scopes dieser Sitzung); beide Exits waren reguläre `user break`,
kein Absturz. Re-Smoke danach: 3/3 grün.

## Cross-Check: die vier §21.6-Befunde auf Linux

Nutzer hat gezielt auf die vier aus der Windows-Session bekannten, offenen
Einzelbefunde geachtet — alle vier **identisch reproduzierbar**, keine
plattformspezifische Abweichung:

1. Resize/Reflow-Bug (Kind-Controls wandern beim Fenster-Vergrößern nicht mit).
2. Editor-Canvas-Scrollbars fehlen (Font-Tab).
3. Font-Size-Slider zeigt keine Zahl.
4. Colors-Tab: rechte Spalte (Revert-Button+Checkbox) + dunkle Rahmen fehlen.

Das bestätigt (Nutzer-Beobachtung, nicht instrumentiert): alle vier sind
Backend-generische Befunde, keine Windows-Eigenheit — stützt die bestehende
Root-Cause-Einschätzung aus `docs/HACKING.md` §21.6/§21.7 (Resize-Bug: fehlender
`resizeEvent`-Handler in `RacketWindow`, plattformunabhängig vom Grund her, auch
wenn der Windows-Fix-Versuch an einem Windows-spezifischen modalen
Resize-Drag-Detail scheiterte).

## Verifikation

- Klassen-Komposition lädt fehlerfrei (kein `public*`/`override*`-Konflikt) —
  bereits durch den erfolgreichen Probe- und DrRacket-Start sowie die
  Smoke-Läufe bestätigt.
- Smoke 3/3 grün vor der Probe, 3/3 grün danach.
- Probe Nutzer-bestätigt **und** Konsolen-Log-bestätigt. Preferences-Dialog
  Nutzer-bestätigt (Kategorie-Nav + mind. vier Kategorien durchgeklickt).

## Guardrails

Keine Shared-Code-Änderung. Kein `wx/qt/`-Code geändert. Kein neues Widget über
die drei aus der Windows-Session hinaus. Kein `exec()`/keine geschachtelte
Event-Loop. Kein Push/Pull außer dem einen, vom Nutzer vorab bestätigten
Submodul-Fast-Forward (kein Netzwerkzugriff dabei, Commits waren bereits
gefetchbar über `origin/qt-backend`).

## Commits

Keine neuen Commits diese Sitzung (reine Validierung). Der lokale gui-Submodul-
Checkout wurde per Fast-Forward auf `f6f38474` gebracht (bereits
`origin/qt-backend`, kein neuer Commit). Umbrella-Arbeitsverzeichnis war vor und
nach der Sitzung clean bis auf diesen Report + Doku-Updates (`STATUS.md`,
`docs/HACKING.md` §21-Addendum, `CLAUDE.md`-Checkpoint-Tabelle).

## Nächster Schritt

macOS-Validierung dieser drei Widgets + Preferences-Ende-zu-Ende: weiterhin offen
(separater Prompt). Mit dieser Session ist die Widget-Breite (Checkpoint E) auf
Windows **und** Linux grün; Preferences-Ende-zu-Ende ist auf beiden Plattformen
strukturell erreicht (vier bekannte, nicht-blockierende Einzelbefunde bleiben
offen, s. o.). Je eigene künftige Session für: Resize/Reflow-Bug (braucht ein
Qt-Äquivalent zu win32s synchronem Pump-Trick im `resizeEvent`, s. §21.7),
Editor-Canvas-Scrollbars, Font-Size-Zahlen-Anzeige, Colors-Tab rechte
Spalte/Rahmen, restliche Preferences-Kategorien (Editing/Warnings/General/
Profiling/Tools/Background Expansion).

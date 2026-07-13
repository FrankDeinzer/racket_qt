# Report — Block A: `choice%`/`radio-box%`/`slider%` echt — Linux-Validierung — 2026-07-13-2

**Racket:** `v9.2 [cs]` (gemessen, `racket --version`).

Fortsetzung von `docs/2026-07-13-2_report-win.md` (Implementierung dort abgeschlossen,
Windows-seitig Nutzer-bestätigt). Diese Session validiert dieselben drei Widgets auf
Linux — kein neuer Code, reiner Sync + Rebuild + Probe.

## Phase 0 — Umgebung

- **Sync-CHECK:** Umbrella-`main` stand bereits korrekt auf gui @ `3ba8fa75`
  (`361383b chore(gui): bump qt-backend submodule pointer to 3ba8fa75`, bereits vor
  Sitzungsbeginn gepusht). Lokaler gui-Submodul-Checkout auf dieser Maschine war
  **stale**: `caef3e9c`, 3 Commits hinter `origin/qt-backend` (genau die drei
  Windows-Commits `dc5cef02`/`3a2b2d8e`/`3ba8fa75` — auf `origin/qt-backend` bereits
  vorhanden, per `git fetch` verifiziert vor jeder Aktion). Nutzer vor dem Pull gefragt
  (Regel 7) → bestätigt → Fast-Forward `caef3e9c` → `3ba8fa75` im Submodul, keine
  Netzwerk-Schreibaktion, reine lokale Zeigerbewegung.
- **Shim-Aktualität:** `qt-shim/src/shim.cpp` (mtime nach dem Fast-Forward) neuer als
  `qt-shim/build/linux-x64/libracketqtshim.so` → Rebuild nötig (stale-Shim-Falle,
  CLAUDE.md). `cmake --build qt-shim/build/linux-x64` — clean, keine Warnungen.
- **Light Mode verifiziert:** `framework:white-on-black?` = `#f` in
  `~/.config/racket/racket-prefs.rktd` (Legacy-Key `framework:color-scheme-light` =
  `classic`, nicht verwendet — analog Windows-Befund).
- **Re-Smoke vor der Probe:** 3/3 grün (`raco test tests/smoke.rkt` unter
  `PLT_QT=1 QT_PLUGIN_PATH=~/Qt/6.11.1/gcc_64/plugins`).

**Checkpoint 0:** alles grün, kein STOPP nötig.

## Phase 1/2 — Orakel/Implementierung

Entfällt — bereits auf Windows abgeschlossen (`docs/2026-07-13-2_report-win.md`,
`docs/HACKING.md` §20). Diese Session ändert keinen `wx/qt/*.rkt`- oder
`shim.cpp`-Code.

## Phase 3 — Probe als Beweis (Linux)

`examples/value-widgets-probe.rkt` unter X11 (`DISPLAY=:0`) gestartet, interaktiv durch
den Nutzer bedient: Dropdown-Auswahl (`choice%`), Radio-Klicks inkl. der
1-Button-`[selection #f]`-Gruppe (`radio-box%`), Slider-Drag (`slider%`), je ein
„set via code"-Button pro Widget.

**Nutzer-Bestätigung:** „Alles korrekt" — Rendering, Interaktion und die
„`set-*` löst den eigenen Callback nicht erneut aus"-Anforderung explizit geprüft,
keine Auffälligkeiten.

**Unterschied zu Windows:** das Konsolen-Log der Probe-`printf`s wurde dieses Mal
vollständig eingefangen (Linux-Hintergrundprozess-Capture puffert nicht wie
PowerShell/`Out-String`) und bestätigt die Nutzer-Aussage exakt:

```
initial: choice selection=0, radio-box selection=0, single radio-box selection=#f, slider value=20
choice% callback fired: selection=1 (Beta)
choice% callback fired: selection=2 (Gamma)
choice: set-selection 2 done, now selection=2      ; kein Callback davor/danach
choice: set-selection 2 done, now selection=2      ; erneut kein Callback
choice% callback fired: selection=1 (Beta)
choice: set-selection 2 done, now selection=2      ; erneut kein Callback
radio-box% callback fired: selection=1
radio-box% callback fired: selection=2
radio-box% callback fired: selection=1
radio-box% callback fired: selection=1
radio-box: set-selection 1 done, now selection=1   ; kein Callback
radio-box% callback fired: selection=2
radio-box: set-selection 1 done, now selection=1   ; kein Callback
single radio-box% callback fired: selection=0
single radio-box: set-selection #f done, now selection=#f   ; härtester Fall, kein Callback
slider% callback fired: value=... (22 … 100 … 13, laufendes Drag)
slider: set-value 75 done, now value=75            ; kein Callback
```

In jedem der drei Fälle feuert der Callback ausschließlich bei echten
Nutzer-Interaktionen, nie bei einem `set-*`-Aufruf via Code — bestätigt den
`QSignalBlocker`-Schutz (§20) auf Linux genauso wie auf Windows.

Beendet per `SIGTERM` (nicht über den Fenster-Schließen-Knopf, um das offene
Teardown-Thema „Crash B" nicht versehentlich zu berühren — bleibt außerhalb des
Scopes dieser Sitzung); Exit war ein reguläres `user break`, kein Absturz.

## Verifikation

- Klassen-Komposition lädt fehlerfrei (kein `public*`/`override*`-Konflikt) —
  bereits durch den erfolgreichen Probe-Start und die Smoke-Läufe bestätigt.
- Smoke 3/3 grün vor der Probe.
- Probe Nutzer-bestätigt **und** Konsolen-Log-bestätigt (Verbesserung gegenüber der
  Windows-Sitzung, wo das Log durch eine Tooling-Einschränkung nicht einfangbar war).

## Guardrails

Keine Shared-Code-Änderung. Kein `wx/qt/`-Code geändert. Kein `tab-panel%`. Kein
`exec()`/keine geschachtelte Event-Loop. Kein Push/Pull außer dem einen, vom Nutzer
vorab bestätigten Submodul-Fast-Forward (kein Netzwerkzugriff dabei, da bereits
gefetcht).

## Commits

Keine neuen Commits diese Sitzung (reine Validierung). Der lokale gui-Submodul-Checkout
wurde per Fast-Forward auf `3ba8fa75` gebracht (bereits `origin/qt-backend`,
kein neuer Commit). Umbrella-Arbeitsverzeichnis war vor und nach der Sitzung clean
bis auf diesen Report + Doku-Updates (`STATUS.md`, `docs/HACKING.md` §20-Addendum,
`CLAUDE.md`-Checkpoint-Tabelle).

## Nächster Schritt

macOS-Validierung dieser drei Widgets: weiterhin offen (nicht Teil dieser Sitzung).
`tab-panel%` (Block B) bleibt der Blocker für die volle Preferences-Dialog-
Ende-zu-Ende-Validierung auf allen drei Plattformen.

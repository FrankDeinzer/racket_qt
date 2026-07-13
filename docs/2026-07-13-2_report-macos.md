# Report — Block A: `choice%`/`radio-box%`/`slider%` echt — macOS-Validierung — 2026-07-13-2

**Racket:** `v9.2 [cs]` (gemessen, `racket --version`).

Fortsetzung von `docs/2026-07-13-2_report-win.md` (Implementierung dort abgeschlossen,
Windows-seitig Nutzer-bestätigt) und `docs/2026-07-13-2_report-linux.md`
(Linux-Validierung). Diese Session validiert dieselben drei Widgets auf macOS — kein
neuer Code, reiner Sync + Rebuild + Probe. Damit sind alle drei Plattformen abgedeckt.

## Phase 0 — Umgebung

- **Sync-CHECK:** Umbrella-`main` stand bereits korrekt auf gui @ `3ba8fa75`
  (bereits vor Sitzungsbeginn gepusht). Lokaler gui-Submodul-Checkout auf dieser
  macOS-Maschine war **stale**: `caef3e9c`, 3 Commits hinter `origin/qt-backend`
  (genau die drei Widget-Commits `dc5cef02`/`3a2b2d8e`/`3ba8fa75` — auf
  `origin/qt-backend` bereits vorhanden, per `git fetch` verifiziert vor jeder Aktion).
  Nutzer vor dem Pull gefragt (Regel 7) → bestätigt → Fast-Forward `caef3e9c` →
  `3ba8fa75` im Submodul, keine Netzwerk-Schreibaktion, reine lokale Zeigerbewegung.
- **Shim-Aktualität:** `qt-shim/src/shim.cpp` (mtime 13. Juli 19:41) neuer als
  `qt-shim/build/macos-arm64/libracketqtshim.dylib` (mtime 12. Juli 13:20) → Rebuild
  nötig (stale-Shim-Falle, CLAUDE.md). `cmake --build qt-shim/build/macos-arm64` —
  clean, keine Warnungen.
- **Light Mode verifiziert:** `framework:white-on-black?` = `#f` in
  `~/Library/Preferences/org.racket-lang.prefs.rktd` (Legacy-Keys
  `framework:color-scheme`/`framework:color-scheme-dark` = `white-on-black`, nicht
  verwendet — analog Windows-/Linux-Befund; Pfad selbst per `(find-system-path
  'pref-file)` ermittelt statt geraten, da `~/Library/Racket/...` auf dieser Maschine
  nicht existiert).
- **Re-Smoke vor der Probe:** 3/3 grün (`raco test tests/smoke.rkt` unter `PLT_QT=1`,
  `-S third_party/gui/gui-lib -S third_party/draw/draw-lib`).

**Checkpoint 0:** alles grün, kein STOPP nötig.

## Phase 1/2 — Orakel/Implementierung

Entfällt — bereits auf Windows abgeschlossen (`docs/2026-07-13-2_report-win.md`,
`docs/HACKING.md` §20). Diese Session ändert keinen `wx/qt/*.rkt`- oder
`shim.cpp`-Code.

## Phase 3 — Probe als Beweis (macOS)

`examples/value-widgets-probe.rkt` gestartet, interaktiv durch den Nutzer bedient:
Dropdown-Auswahl (`choice%`), Radio-Klicks inkl. der 1-Button-`[selection #f]`-Gruppe
(`radio-box%`), Slider-Drag (`slider%`), je ein „set via code"-Button pro Widget.

**Nutzer-Bestätigung:** „fertig. alles ok". Zusätzlich per Screenshot verifiziert:
Choice zeigt „Gamma", Radio-box zeigt „Three" gecheckt, die einzelne Radio-Box zeigt
korrekt **keinen** gecheckten Button, Slider steht nahe Maximum — durchgängig
konsistent mit den `set-*`-via-Code-Aufrufen aus der Probe.

**Konsolen-Log-Capture:** anders als bei der Implementierung auf Windows (dort
PowerShell-Puffer-Problem) blieb die Log-Datei bei laufendem Hintergrundprozess trotz
gesetztem `'line`-Puffermodus (`file-stream-buffer-mode` in der Probe) wiederholt bei
0 Byte — in dieser Hintergrund-Redirect-Konfiguration also effektiv block-gebuffert;
der genaue Mechanismus wurde nicht weiter isoliert (kein Anlass zum Raten, da die
Nutzer-/Screenshot-Bestätigung bereits ausreichte). Der Prozess wurde nach der
Nutzer-Bestätigung per `kill -TERM` beendet (bewusst **nicht** über den
Fenster-Schließen-Knopf, um das offene Teardown-Thema „Crash B" nicht zu berühren,
analog zur Linux-Sitzung). Erst der Flush im `user break`-Handler beim Beenden machte
das vollständige Log lesbar:

```
user break
  context...:
   .../wx/common/queue.rkt:639:3
initial: choice selection=0, radio-box selection=0, single radio-box selection=#f, slider value=20
choice% callback fired: selection=1 (Beta)
choice% callback fired: selection=0 (Alpha)
choice: set-selection 2 done, now selection=2          ; kein Callback davor/danach
radio-box% callback fired: selection=1
radio-box% callback fired: selection=2
radio-box: set-selection 1 done, now selection=1       ; kein Callback
single radio-box% callback fired: selection=0
single radio-box: set-selection #f done, now selection=#f   ; härtester Fall, kein Callback
slider% callback fired: value=21 … (laufendes Drag, viele Zwischenwerte) … value=63
slider: set-value 75 done, now value=75                ; kein Callback
radio-box% callback fired: selection=2
single radio-box% callback fired: selection=0
single radio-box: set-selection #f done, now selection=#f   ; erneut kein Callback
QThreadStorage: entry 0 destroyed before end of thread ...
```

In jedem der drei Fälle feuert der Callback ausschließlich bei echten
Nutzer-Interaktionen, nie bei einem `set-*`-Aufruf via Code — bestätigt den
`QSignalBlocker`-Schutz (§20) auf macOS genauso wie auf Windows und Linux.

Beendet per `SIGTERM` (nicht über den Fenster-Schließen-Knopf), Exit war ein reguläres
`user break`, kein Absturz.

## Verifikation

- Klassen-Komposition lädt fehlerfrei (kein `public*`/`override*`-Konflikt) — bereits
  durch den erfolgreichen Probe-Start und die Smoke-Läufe bestätigt.
- Smoke 3/3 grün vor der Probe.
- Probe Nutzer-bestätigt, per Screenshot verifiziert **und** Konsolen-Log-bestätigt.

## Guardrails

Keine Shared-Code-Änderung. Kein `wx/qt/`-Code geändert. Kein `tab-panel%`. Kein
`exec()`/keine geschachtelte Event-Loop. Kein Push/Pull außer dem einen, vom Nutzer
vorab bestätigten Submodul-Fast-Forward (kein Netzwerkzugriff dabei, da bereits
gefetcht).

## Commits

Keine neuen Commits diese Sitzung (reine Validierung). Der lokale gui-Submodul-Checkout
wurde per Fast-Forward auf `3ba8fa75` gebracht (bereits `origin/qt-backend`, kein neuer
Commit). Umbrella-Arbeitsverzeichnis war vor der Sitzung clean, nach der Sitzung
geändert durch diesen Report + Doku-Updates (`STATUS.md`, `docs/HACKING.md`
§20-Addendum, `CLAUDE.md`-Checkpoint-Tabelle) — Push/Sync-Entscheidung: siehe
Nutzer-Rückfrage am Ende dieser Sitzung.

## Nächster Schritt

`choice%`/`radio-box%`/`slider%` sind damit auf allen drei Plattformen (Windows, Linux,
macOS) validiert. `tab-panel%` (Block B, eigener Prompt) bleibt der Blocker für die
volle Preferences-Dialog-Ende-zu-Ende-Validierung auf allen drei Plattformen.

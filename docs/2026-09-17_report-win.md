# Report — Windows: gebündelter Cross-Platform-Validierungs-Sweep (kritischer Kern) — 2026-09-17

**Bezug:** `docs/2026-09-13_prompt.md` (Cluster-1-Block, Linux-geführt) plus die seither
angewachsene „später zu validieren"-Liste aus `docs/2026-09-13_report-linux.md` bis
`docs/2026-09-16-2_report-linux.md` (§23.3–§39, 11 Submodul-Commits). Dieser Report ist
**kein neuer Fix-Block**, sondern der auf Windows fällige, im Prompt vorregistrierte
gebündelte Durchlauf. Nutzerentscheidung zu Sessionbeginn: Sync jetzt durchführen,
Umfang auf den **kritischen Kern** begrenzen (Akzeptanztest + zwei Windows-exklusive
offene Fragen + Resize/Drag) statt aller elf Punkte.

`racket --version`: 9.3 [cs] (unverändert seit der 9.3-Migration, §24.1).

## Phase 0 — Sync + Rebuild + Gate

- RDP-Session aktiv/verbunden (`query session`) — GUI-Automatisierung verlässlich.
- `racket-prefs.rktd` gesichert + gehasht **vor** jeder GUI-Interaktion
  (`C:\Users\Deinzer\AppData\Local\Temp\claude\C--src-racket-qt\prefs-backup\racket-prefs.rktd.2026-09-17`,
  SHA256 `6E5F3B21…D265D1`), am Sessionende zurückgespielt und Hash erneut verglichen —
  **identisch**.
- Umbrella `main` war bereits sauber auf `origin/main`. Submodul-Arbeitsverzeichnis hing
  bei `a71d2e9a` (§27, letzter lokaler Windows-Stand), 11 Commits hinter dem, was der
  Umbrella-Zeiger bereits verlangte (`cbc506c5` — identisch mit `origin/qt-backend`-
  Spitze). Nutzer vorab gefragt (Regel 7) und zugestimmt: `git -C third_party/gui merge
  --ff-only origin/qt-backend` — sauberer Fast-Forward, **kein neuer Umbrella-Commit
  nötig**, da der Zeiger bereits stimmte.
- `qt-shim` neu gebaut (`cmake --preset windows-x64` + `cmake --build … --config Debug`),
  fällig seit vier Fixes mit neuen Exporten (§32/§33/§36/§37). Alle sechs erwarteten
  Exporte per `dumpbin /exports` verifiziert: `shim_window_set_resize_cb`,
  `shim_canvas_set_wheel_cb`, `shim_clipboard_get_text`, `shim_clipboard_has_text`,
  `shim_clipboard_set_text`, `shim_menu_set_about_to_show_cb`.
- Smoke-Gate: `raco test tests/smoke.rkt` **3/3 grün mit** `PLT_QT=1`, **3/3 grün ohne**.

## Akzeptanztest — `test-dock-size` (höchste Priorität)

Historisch 10/10 Crash auf allen drei Plattformen (`test-engine:test-dock-size`,
`given: '(1)`, Stack über `test-panel%::remove`). Linux hat das 2026-09-13 gefixt
(Commit `2f0755bd`, zehn hartcodierte `is-shown? #t`-Overrides entfernt) und dort 0/3
gemessen — **auf Windows bis heute nicht mit diesem Fix getestet.**

Methode: echte Maus-Automatisierung (PowerShell + .NET `user32`/`System.Drawing`,
Koordinaten aus `GetWindowRect`/Fenstergeometrie abgeleitet, nicht aus Screenshots
geschätzt — Lehre aus §21.10; `SetForegroundWindow` vor jeder Eingabe zur
Fokus-Verifikation, wie in `docs/2026-09-11_report-win.md` etabliert). Je Durchlauf
ein frischer DrRacket-Prozess (`tasklist`-Check vorab), `examples/htdp-tests-probe.rkt`
als Startdatei, Toolbar-**Run**-Klick per Maus (Tastatur-Akzeleratoren sind laut
2026-09-11-Report unter diesem Backend nicht zuverlässig), danach **File → Open**
(Maus-Klicks, Dateiname in den Qt-eigenen Dialog getippt) von
`examples/htdp-image-probe.rkt` als zweite Registerkarte.

**Ergebnis: n=3, 0/3 Crash.** Alle drei Läufe öffneten sauber zwei Tabs
(`1: htdp-tests-p…` / `2: htdp-image-…`), kein „DrRacket Internal Error"-Dialog, Prozess
jeweils per echtem Klick auf den Schließen-Button sauber beendet. **Der Linux-Fix
generalisiert auf Windows.**

Nebenbemerkung zur Automatisierung: im dritten Lauf ging die erste Eingabe in den
Datei-Dialog (Tippen des Dateinamens + Klick auf „Open") ins Leere, weil der Dialog
zwar offen war (Taskleisten-Eintrag „Select a file"), aber nicht automatisch den Fokus
hatte — der Fix war, den Dialog per `EnumWindows`/`SetForegroundWindow` explizit zu
adressieren, danach lief die Sequenz wie in Lauf 1/2. Kein Produktbefund, reine
Automatisierungslektion (analog zu den Linux-`xdotool`-Fallstricken aus §34.7).

## Windows-exklusive offene Fragen (Beobachtung, kein Fix-Versuch)

**§35 Hypothese 1 — orange/blau gestreiftes Rechteck** (Windows-Nebenbefund aus §24.5,
2026-09-11, Root-Cause nie untersucht): in keinem der drei `test-dock-size`-Läufe und
keinem der insgesamt vier geöffneten Tabs sichtbar (Zoom auf den oberen Fensterrand
extra geprüft). Deckt sich mit der Linux-Hypothese, dass der §35-Hide-on-Create-Fix
(`'deleted`-Stil) ihn mitbehoben hat. **Nicht als endgültig erledigt eingestuft** — der
genaue 2026-09-11-Auslöseschritt wurde nicht rekonstruiert/gezielt wiederholt, nur seine
Abwesenheit unter neuen Bedingungen beobachtet.

**§24.5-Windows-Symptom — Editor-Inhalt komplett weiß** (vor dem §33-Fix, degenerierte
Scroll-Range): in allen drei geöffneten Tabs (`htdp-tests-probe.rkt`,
`htdp-image-probe.rkt`, `canvas-panel-probe.rkt`) rendert der Inhalt korrekt, kein
Weißmal-Symptom. Scrollbar-Erscheinen unter echtem Platzmangel nur indirekt bestätigt
(die verfügbaren Beispieldateien sind zu kurz, um im ungestauchten Fenster eine
vertikale Scrollbar zu erzwingen) — beim Verkleinern des Fensters (s. u.) erschien
zuverlässig eine **horizontale** Scrollbar, was zeigt, dass die Scroll-Maschinerie
grundsätzlich aktiv ist.

## Resize/Drag (§32, höchstes Divergenzrisiko unter den reinen Racket-Fixes)

Failure-Modus laut Linux-Report ist ein **Hänger**, nicht ein falsches Pixel (Fix-Versuch
1 auf Linux lief bei dieser Änderungsklasse endlos). Getestet mit echtem
Maus-Drag (`SetCursorPos`/`mouse_event`, Button-Down → 9 Zwischenschritte à 45px →
Button-Up) am unteren Fensterrand von `canvas-panel-probe.rkt` in DrRacket:

- **Verkleinern (1077 → 717 px Höhe):** kein Hänger (Aufruf kehrte sofort zurück),
  Kind-Controls reflowten korrekt — eine horizontale Scrollbar erschien am Fuß der
  Definitions-Pane, die Interactions-Pane passte sich an.
- **Weiter unter die Mindestgröße ziehen (Ziel 717 → 117 px):** Fenster blieb bei 717 px
  stehen, **kein Hänger**, `Process.Responding = True` durchgehend — deckt sich mit dem
  Linux-Befund „Korrekturen bei Drag-Schritten unter der Mindestgröße, kein
  Kaskadieren".
- **Wieder vergrößern (717 → 1077 px):** zwei Versuche, Fenstergröße änderte sich nicht.
  Nach Regel 4 (max. zwei Hypothesenzyklen) nicht weiter verfolgt. **Automatisierungs-
  grenze, kein Produktbefund** — der Prozess blieb während beider Versuche
  `Responding = True` und in jeder Hinsicht bedienbar (spätere Interaktionen mit
  demselben Fenster, u. a. das saubere Schließen, funktionierten anschließend
  einwandfrei); plausibelste Erklärung ist, dass der Cursor nach dem ersten
  `mouse_event`-Release nicht mehr exakt auf der Resize-Border-Pixelzeile lag.

**Kein Hänger in keinem der beiden getesteten Fälle — das Kernrisiko dieses Fixes ist
für Windows entkräftet.**

## Nicht bearbeitet (Umfang bewusst begrenzt, Nutzerentscheidung)

Aus der „später zu validieren"-Liste bewusst **nicht** in dieser Session:

- Zwischenablage cross-process (§36) — Windows-Analogtest wäre `OpenClipboard`/
  `GetClipboardData` bzw. ein zweiter Prozess (z. B. Notepad).
- Mausrad-Schrittweite/-Richtung (§33).
- Preferences-Button-Zeile initial erreichbar (§31) — Windows war im ursprünglichen
  §25.1-Cluster betroffen, macOS diverierte dort positiv.
- Colors → Color Schemes: Scrollbar da, drei Buttons erreichbar und klickbar (§34).
- Menü-Enable-States (§37): Edit-Menü Copy/Cut nach Select All, Tabs-Menü Previous/Next
  Tab bei zwei offenen Tabs.
- Teardown-Probe (§39, Crash B).

Diese Punkte bleiben in der Liste „später zu validieren" offen für Windows, s. u.

## Liste „später zu validieren" (Rest, Windows)

- §36 Zwischenablage cross-process (Windows-native API oder zweiter Prozess).
- §33 Mausradschrittweite/-richtung.
- §31 Preferences-Button-Zeile initial erreichbar.
- §34 Colors → Color Schemes Scrollbar + drei Buttons klickbar.
- §37 Menü-Enable-States (Edit-Menü, Tabs-Menü).
- §39 Teardown-Probe (`examples/crash-b-teardown-probe.rkt`).
- macOS: der komplette Sweep (Sync, Rebuild, alle obigen Punkte plus die auf Windows
  jetzt erledigten) steht dort noch vollständig aus.

## Disziplin

- Keine Quelltextänderung — reine Validierung.
- `racket-prefs.rktd` zurückgespielt, Hash gegen Backup verifiziert (identisch).
- `git status` am Ende sauber, sowohl Umbrella als auch Submodul (`nothing to commit,
  working tree clean`, beide `up to date with origin`).
- Screenshots im Scratchpad-Verzeichnis der Session, nicht committet.

## Aktualisiert

- `CLAUDE.md`: Shim-Rebuild-Banner (nur noch macOS offen), Checkpoint-Zeile
  `test-dock-size` (Windows-Validierung ergänzt), §32-Resize-Absatz (Windows-Ergebnis),
  §33-Absatz (Windows-Editor-weiß-Gegenprüfung), §35-Nebenbefund (Streifenrechteck-
  Beobachtung).
- `STATUS.md`: neuer Eintrag oben.

# Report — Racket-9.3-Migration + Stabilisierungsrunde (macOS arm64) — 2026-09-13

**Prompt:** `docs/2026-09-11_prompt.md` (Fortsetzung für macOS, nach Windows-Abschluss
`docs/2026-09-11_report-win.md` und Linux `docs/2026-09-11_report-linux.md`). Gemessene
Version: **`racket --version` → v9.3 [cs]** (Homebrew, `/opt/homebrew/bin/racket`).

---

## Vorbereitung — Drei-Maschinen-Sync-Check (vor jeder Fix-Arbeit, Regel 7)

- **Umbrella `main`:** exakt synchron mit `origin/main` (`b45a50d`, §27-Commit bereits
  enthalten).
- **Submodul `third_party/gui` (`qt-backend`):** lokal ausgecheckt auf `54f2f702`,
  **5 Commits hinter** `origin/qt-backend` (dieselben 5 Windows-Session-Commits, die
  Linux bereits nachgezogen hat: §24.2 Slider-Zahl, §24.3 Colors-Rahmen, §26
  `is-shown-to-root?`-Rekursion, §27 `frame%` maximize/iconize/fullscreen). Reiner
  Fast-Forward, keine Divergenz.
- **Nutzer per `AskUserQuestion` gefragt** (Regel 7) → bestätigt: Fast-Forward jetzt
  durchführen. `git pull --ff-only origin qt-backend` → sauber auf `a71d2e9a`.
- **`-S`→Link-Parität (Windows/Linux-Angleich):** Nutzer nach Erklärung der
  Migrationsschritte (Backup/Link/Nativ-Gate, eigenes Rollback-Profil) **noch nicht
  final entschieden** — bleibt vorerst offen, s. Abschnitt am Ende dieses Reports.

---

## Phase 0 — Basislinie (kein Racket-Versionswechsel nötig)

### 0.1 Version
`v9.3 [cs]` bestätigt (`/opt/homebrew/bin/racket`). Kein Migrations-Gate nötig — diese
Maschine ist bereits seit 2026-08-19 (Homebrew-Auto-Update, außerhalb jeder Session) auf
9.3.

### 0.8 Stale-Shim-Falle — zutreffend, Rebuild durchgeführt
`qt-shim/src/shim.cpp` (13.09., nach dem Fast-Forward) war **massiv neuer** als
`libracketqtshim.dylib` (14.07.) — §24.3/§27 bringen sowohl eine geänderte
`shim_panel_create`-Signatur als auch 6 neue Shim-Funktionen; ohne Rebuild hätte der
Fork beim Laden mit `get-ffi-obj`-Fehlern abgebrochen (identisch zur Linux-Falle).
`cmake --build qt-shim/build/macos-arm64` sauber durchgelaufen.

### Fork-Recompile (macOS-spezifisch, kein Link-Schritt wie bei Linux)
Da macOS über `-S`-Override statt Installation-Link läuft, ist der Recompile ein
eigener, expliziter Schritt (bei Linux lief er implizit über `raco pkg update --link`
mit): `racket -S third_party/gui/gui-lib -S third_party/draw/draw-lib -l raco --
make <die 5 geänderten .rkt-Dateien>`. `.zo`-Zeitstempel danach neuer als die
Quelldateien, verifiziert.

### 0.7 Gate-Test nativ (bestanden)
- `racket -S ... -l raco -- test tests/smoke.rkt` **ohne** `PLT_QT`: **3/3 grün**.

### 0.10 Regressions-Basislinie (`PLT_QT=1`)
- `racket -S ... -l raco -- test tests/smoke.rkt`: **3/3 grün** (bekannte
  Nebenausgabe `QThreadStorage: entry 0 destroyed before end of thread` —
  vorbestehend seit Checkpoint C, `docs/2026-06-25_report_macos.md` u. a., **keine
  neue Regression**).

### 0.9 Light Mode
`org.racket-lang.prefs.rktd` (macOS-spezifischer Preference-Pfad, ermittelt via
`(find-system-path 'pref-file)`): `white-on-black-mode? #f` — bestätigt. Backup +
SHA-256-Hash vor jeder Interaktion angelegt.

**Self-Gate Checkpoint 0: bestanden.** Sync durchgeführt, Shim neu gebaut, Fork
neu kompiliert, Nativ-Gate grün, Qt-Smoke 3/3.

---

## Phase 1 — Validierung der Windows/Linux-Fixes auf macOS

### §27 — `frame%` maximize/iconize/fullscreen

**Status: bestätigt, identisch zu Windows/Linux.**

Ad-hoc-Probe (Scratchpad, nicht committet, spiegelt exakt `docs/2026-09-11_report-linux.md`
Zeilen 189–198), via `racket -S ... /pfad/zur/probe.rkt` unter `PLT_QT=1`:

```
initial (before show):              shown?=#f maximized?=#f iconized?=#f fullscreened?=#f
after maximize #t (still not shown): shown?=#f maximized?=#t iconized?=#f fullscreened?=#f
after show #t:                      shown?=#t maximized?=#t iconized?=#f fullscreened?=#f
after iconize #t:                   shown?=#t maximized?=#t iconized?=#t fullscreened?=#f
after iconize #f (expect max=#t):   shown?=#t maximized?=#t iconized?=#f fullscreened?=#f
after maximize #f:                  shown?=#t maximized?=#f iconized?=#f fullscreened?=#f
after fullscreen #t:                shown?=#t maximized?=#f iconized?=#f fullscreened?=#t
after fullscreen #f:                shown?=#t maximized?=#f iconized?=#f fullscreened?=#f
```

Beide auf Windows gegen verworfene Erstentwürfe getesteten Bugs reproduzieren sich
**nicht**: `maximize #t` vor `show` macht das Fenster nicht fälschlich sichtbar;
`iconize #f` nach `maximize #t` löscht den Maximize-Zustand nicht. **Bestätigt: keine
Cocoa-spezifische Divergenz.**

### §24.3 — Colors-Tab: dunkler Rahmen

**Status: bestätigt, identisch zu Windows/Linux.**

Statt über den Preferences-Dialog (Klick-Navigation nötig, s. u. Accessibility-Blocker)
mit einer eigenständigen Standalone-Probe geprüft (Scratchpad,
`panel-border-probe.rkt`): zwei `vertical-panel%`, eines ohne, eines mit
`'(border)`-Style, direkt nebeneinander. Screenshot bestätigt: **sichtbarer dunkler
Rahmen** nur beim `'(border)`-Panel, kein Rahmen beim Kontroll-Panel — deckt sich mit
dem in `wx/qt/panel.rkt`/`shim_panel_create(parent, border)` beschriebenen Fix.

### §24.2 — Font-Size-Slider zeigt Zahl

**Status: bestätigt, identisch zu Windows/Linux.**

`examples/value-widgets-probe.rkt`: Slider zeigt initial „20" unter dem Track; nach
Klick auf „slider: set-value 75 via code" (per UI-Scripting-Klick, s. u.) zeigt das
Label „75", Track bewegt sich synchron mit. **Bestätigt.**

### Automatisierungs-Blocker: Accessibility/Bedienungshilfen — gelöst

`osascript`/System Events verweigerte zunächst jeden UI-Element-Klick (`click button
... of window`) mit Fehler `-1719`, obwohl `claude`/`iTerm` bereits in den
Bedienungshilfen-Einstellungen aktiviert waren. **Root-Cause:** TCC prüft die
Berechtigung offenbar zum Startzeitpunkt des verantwortlichen App-Prozesses — die
laufende iTerm-Instanz war vor der Freigabe gestartet worden. Nach Neustart von iTerm
(Nutzer-Aktion) funktionierten UI-Element-Klicks sofort. **Für künftige Sessions:**
nach einer frischen Bedienungshilfen-Freigabe ggf. einen Prozess-Neustart des
Terminal-Hosts einplanen, bevor UI-Scripting als „nicht möglich" verworfen wird.

---

## Phase 2 — Sweep der sechs Preferences-Kategorien (macOS, erstmals durchgesehen)

Methode: echtes DrRacket unter `PLT_QT=1` (`racket -S ... -l drracket --`), Preferences
über Edit-Menü geöffnet (gefunden per Menü-Introspektion: „Preferences…" liegt im
Edit-Menü, nicht im App-Menü — konsistent mit dem §22-Fix). Navigation/Verifikation per
`osascript`/System Events (Tab-/Radio-Button-Klicks, Accessibility-Introspektion) +
`screencapture`. Kriterium wie im Prompt: Funktion/Vollständigkeit, nicht Pixelgleichheit.

**Positive Divergenz zu Windows/Linux:** Preferences öffnet bei Initialgröße
**1060×625** bereits mit sichtbarer Button-Zeile (OK/Undo/Revert) — anders als
Windows/Linux, wo dieselbe Zeile beim Erststart unerreichbar war (§25.1-Cluster). Kein
Negativbefund, daher nicht vertieft — Details/Einordnung: `docs/HACKING.md` §29.

**Nebenbefund (kein neuer Fund, reproduziert bekanntes Backlog-Item):** Menüleiste
zeigt nur **8 statt 9** App-eigene Menüs — „Windows"-Menü fehlt (mehrfach abgefragt,
kein Timing-Artefakt). Deckt sich mit dem seit Langem in `CLAUDE.md` vermerkten,
intermittierenden Befund. Nicht weiter verfolgt (Backlog-Item, nicht Teil dieser
Session). Details: `docs/HACKING.md` §29.

| Kategorie | Sub-Tabs | Ergebnis |
|---|---|---|
| **Editing** | Indenting, Square Bracket, General Editing, Racket | Vollständig funktional. Alle Listboxen (Begin-/Define-/Lambda-/For-fold-/Letrec-/Local-/Cond-like Keywords) befüllt, Add/Remove-Buttons + Extra-regexp-Felder vorhanden. „Automatically adjust opening square brackets" in Square Bracket **und** Racket vorhanden. General Editing: „Maximum character width guide"-Textfeld korrekt ausgegraut bei unchecked Checkbox (Disabled-State-Weiterleitung funktioniert). **Keine Befunde — identisch zu Windows/Linux.** |
| **Warnings** | — | 7 Checkboxen, Zustände identisch zu Windows/Linux (Ask about normalizing strings/Ask about clearing test coverage/Show 'evaluation terminated' an, Rest aus). **Keine Befunde.** |
| **General** | — | Slider „Number of recent items" zeigt „50" (§24.2-Fix bestätigt sich erneut für diese Instanz). Alle Checkboxen + Radiogruppen (Automatically Reload Changed Files, Printing Mode) korrekt. **Keine Befunde.** |
| **Profiling** | — | Selbstgemalte Farbverlaufs-Leiste (Grün→Rot, Beispieltext `(define (whee) (whee))`) rendert korrekt — bestätigt `on-paint`-Zeichnen auf `canvas%` unter Qt/macOS. Low/High-Buttons + Radiogruppe korrekt. **Keine Befunde.** |
| **Tools** | — | Listbox mit 20 Einträgen, Inhalt identisch zu Windows/Linux (screenshot-bestätigt). **Klick-Selektion nicht abschließend verifizierbar** — drei UI-Scripting-Strategien zeigten keine sichtbare Selektion/Textfeld-Sync; unklar ob Automatisierungsgrenze oder echter Befund (s. `docs/HACKING.md` §29 für Details). Radiogruppe „Load the tool when DrRacket starts?" korrekt. |
| **Background Expansion** | — | Checkbox + zwei weitere Checkboxen korrekt, drei `choice%`-Dropdowns korrekt befüllt (`in the margin`), Dropdown-Popup öffnet (mit Checkmark auf aktueller Auswahl) und schließt sauber (per `Escape` getestet). **Keine Befunde.** |

**Ergebnis Phase 2:** Von den sechs Kategorien zeigt keine einen eindeutigen
funktionalen Defekt — deckt sich mit Windows-Befund (§25) und Linux-Befund (§28). Ein
Punkt (Tools-Listbox-Klick) bleibt automatisierungsbedingt unklar, siehe oben.

**Betriebsdisziplin:** `org.racket-lang.prefs.rktd` vor jeder Interaktion gehasht;
Hash änderte sich nach der Sweep-Session (erwartet), nach sauberem `Quit racket`
(Menü, kein Absturz, kein Zombie-Prozess) zurückgespielt, Hash danach wieder
identisch zum Vor-Sitzungs-Stand. `git status` beider Repos: beide clean.

---

## Phase 3 — Regressions-Gate

- `racket -S ... -l raco -- test tests/smoke.rkt` **ohne** `PLT_QT`: **3/3 grün**
  (Nativ-Gate weiterhin bestanden).
- `PLT_QT=1 racket -S ... -l raco -- test tests/smoke.rkt`: **3/3 grün** (bekannte
  Nebenausgabe `QThreadStorage: ...` — vorbestehend, keine Regression).
- `git status` in Umbrella **und** Submodul: beide clean (nur die neue
  `docs/2026-09-11_report-macos.md` im Umbrella).
- **Musterabgleich über alle Befunde dieser Session:** keine neuen,
  macOS-spezifischen Code-Befunde. Die positive Divergenz (Button-Zeile initial
  erreichbar) und der reproduzierte Nebenbefund (8 statt 9 Menüs) sind beide bereits
  bekannte/dokumentierte Muster, keine neue Root-Cause-Klasse.

**Gesamtergebnis dieser Session:** Submodul-Sync + Shim-Rebuild + Fork-Recompile
erfolgreich, alle drei Windows-Fixes (§24.2/§24.3/§27) auf macOS funktional
bestätigt, sechs neue Preferences-Kategorien sauber (bis auf einen automatisierungs-
bedingt unklaren Punkt), beide Regressions-Gates grün. **Keine Code-Änderung nötig,
kein Commit in `wx/qt/`/`qt-shim/` fällig** — diese Session war reine Sync +
Validierung + Sweep, analog zu Linux (§28).

---

## Nachtrag 2026-09-13 (2) — `-S`→Link-Parität nachgezogen

Ursprünglich als „eigene Session" empfohlen (Advisor-Konsultation, Scope-Bündelungs-
Präferenz). Nutzer-Rückfrage: auf Windows/Linux war der Link-Status nie eine bewusste
Session-Entscheidung, sondern der Ist-Zustand — nach Prüfung der eigentlichen
Voraussetzungen stand nichts entgegen, also in derselben Session nachgezogen.

**Versionscheck:** installierte `gui-lib`/`draw-lib` (1.80/1.24) identisch zum Fork,
höchste geforderte Version (1.80/1.23) erfüllt — kein Angleich nötig, identisch zu
Windows/Linux.

**Schreibrechte:** `/Applications/Racket v9.3/share/pkgs/` ist user-owned, kein `sudo`
nötig (anders als ursprünglich vermutet — Homebrew installiert nach `/Applications`,
nicht in einen root-owned Systempfad).

**Backup:** `~/racket-link-backup-2026-09-13/` (29 MB).

**Link-Schritt vom Auto-Mode-Classifier blockiert** (`raco pkg update --link`, Grund
„Irreversible Local Destruction", dieselbe Blocker-Klasse wie Linux §28.1). Kein
Workaround versucht — Nutzer führte den Befehl selbst aus (Hintergrund-Task, exit 0).

**Gate-Tests (alle grün, `-S` vollständig entfernt):**
- Smoke ohne `PLT_QT`: 3/3.
- Natives DrRacket (`racket -l drracket`, kein `PLT_QT`): startet sauber, kein
  Linklet-Mismatch, sauber beendet.
- Smoke mit `PLT_QT=1`: 3/3.
- Echtes DrRacket unter `PLT_QT=1` (kein `-S` mehr): startet sauber, sauber beendet,
  kein Zombie-Prozess.

**Ergebnis:** macOS ist jetzt bezüglich Link-vs.-`-S` mit Windows/Linux angeglichen.
`CLAUDE.md`-Run-Rezepte aktualisiert. Details: `docs/HACKING.md` §29.1. Kein Commit
im gui-Submodul nötig (reine Installations-Änderung).

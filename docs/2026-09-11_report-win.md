# Report — Racket-9.3-Migration + Stabilisierungsrunde (Windows) — 2026-09-11

**Prompt:** `docs/2026-09-11_prompt.md`. Gemessene Version: **`racket --version` → v9.3 [cs]**
(via `C:\Program Files\Racket\racket.exe`, s. Fund unten zu PATH).

---

## Phase 0 — Racket-9.3-Migration + Basislinie

### 0.1 Version
`v9.3 [cs]` bestätigt — aber **nicht** über bloßes `racket --version` (PATH-Fund, s. u.),
sondern über den vollen Pfad `C:\Program Files\Racket\racket.exe`.

### 0.2 Sync-Check
- Umbrella `main`: 1 Commit **ahead** of `origin/main` (lokal, ungepusht — der
  `2026-09-11_prompt.md`-Commit). Kein Rückstand, keine Divergenz.
- Submodul `third_party/gui` (`qt-backend`): exakt auf `origin/qt-backend`
  (`54f2f702`), kein Rückstand.
→ Kein STOPP-Kriterium (0.2) erfüllt.

### 0.3 Link-Status (neue 9.3-Installation)
`raco pkg show -l`: `gui-lib`/`draw-lib` **nicht verlinkt** (Teil der 217
auto-installierten Pakete der Installation). Erwartung bestätigt.

### 0.4 Versions-Kompatibilität (Risikopunkt)
- Installierte `gui-lib` (Racket 9.3): **1.80**, Quelle
  `git://github.com/racket/gui/?path=gui-lib#6f0213fa0535d87dd4e35f56c8266d948c8c089e`.
- Installierte `draw-lib` (Racket 9.3): **1.24**.
- Fork (`third_party/gui/gui-lib/info.rkt` / `third_party/draw/draw-lib/info.rkt`):
  **1.80** / **1.24** — identisch zur System-Version.
- Vollständiger Sweep über alle 217 installierten Pakete (`grep -ho '"gui-lib"
  #:version "[^"]*"' */info.rkt`, analog `draw-lib`): höchste geforderte
  `gui-lib`-Version **1.80**, höchste geforderte `draw-lib`-Version **1.23**. Beide vom
  Fork erfüllt (1.80 ≥ 1.80, 1.24 ≥ 1.23).
- **Ergebnis: kein Versionsangleich nötig.** Anders als beim 1.78→1.80-Angleich
  (`docs/2026-07-02_report.md`) ist der Fork bereits auf dem exakten von 9.3
  benötigten Stand. 0.4-Gate: **grün**, weiter zu 0.5/0.6.
- **Bekannter, bewusst nicht verfolgter Punkt:** Versionsgleichheit (1.80/1.24) beweist
  keine Commit-Gleichheit — der Fork wurde nicht gegen `6f0213fa0535` diff-verifiziert.
  Out of scope dieser Session (kein Hinweis auf ein Problem).

### Fund — PATH
`racket` ist **weder im Machine- noch im User-PATH** persistiert (leerer Treffer in
`[Environment]::GetEnvironmentVariable("Path", ...)`). Betrifft alle drei Umgebungen
(Bash, PowerShell) — kein Shell-Artefakt. Alle weiteren Befehle dieser Session nutzen
den vollen Pfad `C:\Program Files\Racket\...`. **CLAUDE.md-Run-Rezepte für Windows
setzen bislang bloßes `racket ...` voraus** — das ist im Moment nicht lauffähig ohne
PATH-Fix oder volle Pfadangabe; wird am Session-Ende in `CLAUDE.md` vermerkt.

### Fund — kein 9.2-Fallback mehr vorhanden
`C:\Program Files\Racket` existiert nur **einmal**, Zeitstempel heutig — die 9.2-
Installation wurde beim 9.3-Update **in-place ersetzt**, nicht parallel installiert.
`AppData\Roaming\Racket\` enthält zwar noch `9.2`-Verzeichnisse (User-Scope-Reste,
u. a. `PLT-autosave-toc.rktd`, keine `pkgs.rktd` darunter — 9.2 nutzte auf dieser
Maschine ebenfalls Installation-Scope für den Link, kein User-Scope-Paket), aber
**keine eigene 9.2-Programminstallation mehr**. Der einzige Rollback-Weg ist damit das
Dateisystem-Backup aus 0.5 (installierte `gui-lib`/`draw-lib`-Verzeichnisse +
`share/pkgs/pkgs.rktd`), **kein** Umschalten auf eine parallele alte Installation.
→ Nutzer gefragt (Regel 7 + 0.5), s. u.

### Elevation
Aktuelle Shell läuft **nicht** erhöht (`IsAdmin: False`). `raco pkg update --link`
gegen `C:\Program Files\Racket\share\pkgs\` braucht Admin-Rechte (Präzedenzfall
`docs/2026-07-02_report.md` §4.1–4.3) → Nutzer-Einbindung nötig vor 0.6.

---

### 0.5 Backup
Angelegt unter `C:\Users\Deinzer\racket-link-backup-2026-09-11\` (`gui-lib/`,
`draw-lib/`, `pkgs.rktd`, 1513 Dateien). Nutzer bestätigte (Regel 7 + 0.5):
Backup-only-Rollback ist ausreichend, kein Versuch, die alte 9.2-Installation
wiederherzustellen.

### 0.6 Linken
Nutzer führte elevated aus:
```
& "C:\Program Files\Racket\raco.exe" pkg update --link "C:\src\racket_qt\third_party\gui\gui-lib" "C:\src\racket_qt\third_party\draw\draw-lib"
```
Lief ohne Fehler durch (volle `raco setup`-Neukompilierung). `raco pkg show -l`
danach bestätigt: `gui-lib`/`draw-lib` beide `(link "C:\src\racket_qt\third_party\...")`.

### 0.7 Gate-Test nativ (bestanden)
- `raco test tests/smoke.rkt` **ohne** `PLT_QT`: **3/3 grün**.
- DrRacket **ohne** `PLT_QT`: startet sauber, Prozess responsiv, Fenstertitel
  „Untitled - DrRacket" — kein Linklet-/Versions-Mismatch. Sauber beendet.

### 0.8 Stale-Shim-Check
`shim.cpp` (2026-07-14 18:36) älter als die gebaute `racketqtshim.dll`
(2026-09-10 14:45) → **kein Rebuild nötig**.

### 0.9 Light Mode
`racket-prefs.rktd`: `(plt:framework-pref:framework:white-on-black? #f)` — bestätigt.

### 0.10 Regressions-Basislinie (Racket 9.3, `PLT_QT=1`)
- `raco test tests/smoke.rkt`: **3/3 grün** (einmalige, bereits dort dokumentierte
  Nebenausgabe `qt.qpa.window: SetProcessDpiAwarenessContext() failed: Zugriff
  verweigert` — vorbestehend seit `docs/2026-06-30_report.md`, **keine 9.3-Regression**).
- **Automatisierungs-Methode dieser Session:** PowerShell + .NET
  (`System.Windows.Forms`/`System.Drawing` für Screenshots, `SetForegroundWindow`/
  `GetForegroundWindow` zur Fokus-Verifikation vor jeder Eingabe, Maus-Koordinaten
  für Menü-/Button-Klicks). **Wichtiger Negativbefund:** Tastatur-Akzeleratoren
  (`SendKeys` für `Ctrl+R`, `Ctrl+O`) werden vom Qt-Backend **nicht** zuverlässig
  entgegengenommen, obwohl sie laut UI-Automation-Baum korrekt als Menü-Shortcut
  hinterlegt sind (`Run␉Ctrl+R`, `Open…␉Ctrl+O`) — Maus-Klicks auf Toolbar-Button/
  Menüpunkt funktionieren zuverlässig. **Nicht weiter verfolgt** (kein Fix-Versuch,
  reine Methodik-Notiz für künftige Automatisierung); möglicher Zusammenhang mit
  historischen Key-Handling-Eigenheiten dieses Backends (`docs/2026-07-02_report.md`),
  aber nicht verifiziert. RDP-Session war während der gesamten Messung aktiv/verbunden
  (`query session` geprüft), Screenshots dadurch zuverlässig (kein Schwarzbild-Risiko).
  Automatisierungshygiene beachtet: `git status` nach jeder DrRacket-Sitzung geprüft,
  keine Quelldatei verändert (nur `docs/2026-09-11_report-win.md` neu, Submodul sauber).
- **Facette 1a — `htdp-image-probe.rkt`:** 5/5 Bilder korrekt (Kreis, Rechteck-
  Outline, overlay, beside, text+rectangle). **Baseline bestätigt, keine Abweichung.**
- **Facette 1b — `htdp-image-count-probe.rkt`:** 6/6 Bilder korrekt — Windows zeigt
  (wie erwartet) **nicht** den Linux-spezifischen „nur 4 von 6"-Defekt (§23.1).
  **Baseline bestätigt.**
- **Facette 1c — `htdp-text-isolated-probe.rkt`:** rendert sofort korrekt.
  **Baseline bestätigt.**
- **Facette 2 — `htdp-bigbang-probe.rkt`:** via `racket` direkt (nicht DrRacket,
  Kosten-/Automatisierungsersparnis) unter `PLT_QT=1` mit sichtbarer Konsole
  gestartet. Tick-Stream (`tick: 0` … `tick: 35`) und World-Fenster-Anzeige (`36`)
  korrelieren exakt. Kein `exec()`, keine geschachtelte Schleife — Kern-Wette
  bestätigt. **Baseline bestätigt**, `on-key`-Test bewusst ausgelassen (bringt für
  die Baseline nichts, nur Automatisierungsrisiko, s. §23-Nebenartefakt der
  2026-07-14-Session).
- **Facette 3 — `htdp-tests-probe.rkt`:** 1→2-Tab-Sequenz (Run mit fehlschlagendem
  `check-expect`, danach File→Open von `htdp-image-probe.rkt` als zweite
  Registerkarte) → **`DrRacket Internal Error`** reproduziert sich byte-identisch
  zum historischen Befund: `preferences:set: new value doesn't satisfy
  preferences:set-default predicate — pref symbol: 'test-engine:test-dock-size,
  given: '(1)`, Stack über `test-panel%::remove` (`test-tool.rkt:267`) ←
  `undock-tests` ← `on-tab-change`. Prozess überlebt den Crash (wie dokumentiert).
  **Baseline bestätigt — dies ist der erwartete, bereits auf allen drei Plattformen
  10/10 reproduzierte Befund, kein neuer Fund.** Datei unverändert (nur geöffnet,
  nicht editiert), Prozess sauber beendet, keine Autosave-Recovery ausgelöst
  (`PLT-autosave-toc.rktd` blieb leer/2 Bytes).

**Ergebnis Phase 0: Basislinie entspricht vollständig der 9.2-Erwartung aus §23 —
keine 9.3-Regression gefunden.**

**Self-Gate Checkpoint 0: bestanden.** 9.3 läuft, Fork verlinkt, Nativ-Gate grün,
Smoke 3/3, Basislinie deckt sich mit 9.2 → weiter zu Phase 1.

---

## Phase 1 — Bekannte flache Befunde

*(wird fortgeschrieben)*

# Bericht — macOS-Validierung addAction-/mapToGlobal-Fix + DrRacket-Startup-Crash gefixt (prompt08072026-4)

**Datum:** 2026-07-08
**Plattform:** macOS arm64 (`aarch64-macosx/cs`), Darwin 25.5.0
**Racket (gemessen, Phase 0):** v9.2 [cs] · **Qt:** 6.11.0 (`~/Qt/6.11.0/macos`)
**Repro:** `examples/menu-click-probe.rkt` (`mixed`/`dynamic`) + isolierter `client-to-screen`-Datentest
(Scratch-Skript, nicht im Repo) + echtes `PLT_QT=1 drracket` via `-S`-Source-Override
**Startrezept:** `PLT_QT=1 racket -S third_party/gui/gui-lib -S third_party/draw/draw-lib -l drracket`
(macOS nutzt Installation-scope-Link **nicht** für `gui-lib` — Katalog-Paket bleibt Upstream 1.80,
Source-Override ist zwingend, sonst stiller Fallback auf cocoa, siehe §2)

**Kurzfassung:** Ursprünglicher Auftrag war reine Validierung (kein Fix) der beiden von Windows
gebrachten Menü-Fixes (`report08072026-3.md`). Beide Fixes wurden auf Datenebene (Probe,
isolierter `client-to-screen`-Test) **und** visuell in echtem DrRacket bestätigt. Dabei kam ein
**neuer, unabhängiger Startup-Crash** zutage (`set-label`-Arity-Mismatch in der qt-`tab-panel%`-
Stub-Klasse), der DrRacket auf macOS am Hochfahren hinderte und damit die visuelle
Validierung blockierte. Nutzer hat die Scope-Erweiterung explizit autorisiert („Den DrRacket
Crash sollten wir fixen … Wenn der Weg klar ist, fixen wir auch das Kontextmenü.") — der Crash
wurde gefixt (Guardrail „keine Fix-Commits" damit für diesen einen Punkt bewusst aufgehoben),
danach waren beide ursprünglichen Fixes visuell grün. Das ursprünglich separat beobachtete
„kein Kontextmenü bei Rechtsklick" stellte sich als Testfall-Artefakt heraus (nacktes `text%`
ohne Default-Popup-Menü), nicht als Bug im mapToGlobal-Fix — kein weiterer Fix nötig.

---

## 1. Phase 0 — Umgebung verifiziert

- `racket --version` → **v9.2 [cs]** (gemessen, arm64 bestätigt via `system-library-subpath` →
  `aarch64-macosx/cs`).
- Umbrella (`main`): sauber, HEAD `45174c5`, referenziert bereits Submodul-SHA `1641f888`
  (Ziel-Commit aus `report08072026-3.md`).
- gui-Submodul (`third_party/gui`, Branch `qt-backend`): **vor** Sync 4 Commits hinter
  `origin/qt-backend`, stand auf `381425d5` (alt, vor beiden Menü-Fixes) — klassische
  stale-Shim-Falle, wie vom Prompt vorhergesagt.

## 2. Phase 1 — Sync + Rebuild

1. `git submodule update --init third_party/gui` → Submodul auf `1641f888` (enthält
   `0be24d85` addAction-Fix + `1641f888` mapToGlobal-Fix). Submodul-Checkout landet dabei
   erwartungsgemäß im **detached HEAD** (relevant für §6, Commit-Workflow).
2. `cmake --build qt-shim/build/macos-arm64` (Ninja) — sauberer Rebuild, `shim.cpp` neu
   übersetzt (beide Fixes ändern `shim.cpp`).
3. Re-Smoke: `PLT_QT=1 racket -S third_party/gui/gui-lib -S third_party/draw/draw-lib -l raco --
   test tests/smoke.rkt` → **3 tests passed** (einzige Nebenwirkung: harmlose
   `QThreadStorage: entry 0 destroyed before end of thread`-Teardown-Meldung, bekannt, kein
   Regressionszeichen).

**Ladecheck (wichtig, Advisor-Hinweis):** macOS hat `gui-lib` **nicht** als Installation-scope-Link
gesetzt (`raco pkg show gui-lib` → Installation-wide aus Katalog, User-specific `[none]`). Ein
direkter `drracket`- oder `PLT_QT=1 drracket`-Aufruf ohne `-S`-Override hätte still auf
Upstream-1.80/cocoa zurückgefallen — sichtbares, aber falsches „Grün". Verifiziert über
`PLT_QT_DEBUG=1`: die `[PLT_QT_DEBUG] menubar_create …`-Zeilen erscheinen nur mit `-S`-Override
im Kommando; das ist der Beleg, dass tatsächlich der qt-Backend-Pfad läuft.

## 3. Phase 2 — addAction-Fix, Validierung

**Probe (Datenebene, gated `shim_menu_debug_dump`):**

| Modus | Erwartet | Gemessen |
|---|---|---|
| `mixed` | `actions().size()=3`, Reihenfolge New/Recent(menu=1)/Save | ✅ exakt |
| `dynamic` | Separatoren Pos. 1/3, `Alpha enabled=0`, `Beta checked=1`, Größe 5→4 nach `delete` | ✅ exakt |

**Wichtige Nebenklärung:** Die Probe öffnet ihr Menü über `(send menu popup 100 100 …)` →
`shim_menu_popup` → `QMenu::popup(QPoint(100,100))` — das sind **globale Bildschirmkoordinaten**,
unabhängig von der Fensterposition. Das dabei sichtbare „Dropdown erscheint losgelöst vom
kleinen Probe-Fenster" (vom Nutzer beobachtet) ist **beabsichtigtes Verhalten der Probe, kein
Bug** — dieser Pfad läuft nicht über `client-to-screen`/`mapToGlobal` und sagt nichts über
den mapToGlobal-Fix aus (Beleg: `qt-shim/src/shim.cpp:596-599`).

**Echtes DrRacket (visuell, nach Crash-Fix aus §5):** File-Menü in der macOS-Systemleiste zeigt
alle Blatt-Items vollständig (New, New Tab, Open…, Open Require Path…, Reopen Closed Tab,
Install Package…, Package Manager…, Install .plt File…, Revert, Save Definitions, Save
Definitions As…, Log Definitions and Interactions…, Print Definitions…, Print Interactions…,
Search in Files…, Close Window, Close Tab) plus zwei Submenüs (Open Recent, Save Other) mit
korrekten Separatoren — Screenshot in der Session. **Ergebnis: grün.**

## 4. Phase 3 — mapToGlobal-Fix, Validierung

**4a. Isolierter Datentest (Advisor-Empfehlung, umgeht Popup/Rechtsklick/Event-Delivery komplett):**
Frame auf bekannte Position bewegt, `client-to-screen` direkt auf dem wx-Peer eines `canvas%`
aufgerufen (Diskriminator: alter No-op hätte Eingabe unverändert zurückgegeben, also `(0,0)`):

```
[CTS] frame get-x/get-y = (300,200)
[CTS] client(0,0)    -> screen(520,289)   -- nicht (0,0): am Fenster verankert
[CTS] client(100,50) -> screen(620,339)   -- Offset +(100,50) exakt
[CTS] client(200,100)-> screen(720,389)   -- Offset +(200,100) exakt
```

Translation ist exakt 1:1 (kein Skalierungsfehler, z. B. durch Retina/DPR), Basispunkt ist nicht
`(0,0)` → `QWidget::mapToGlobal` läuft wirklich, No-op ist weg. **Ergebnis: grün.**

**4b. Beobachtung vor dem Crash-Fix — „kein Kontextmenü" (kein Bug im Fix):** Ein Test-Vehikel
mit nacktem `editor-canvas%` + `text%` (ohne DrRacket-eigene Editor-Subklassen) zeigte bei
Rechtsklick **gar kein** Kontextmenü, an keiner Stelle im Fenster. Ein kaputtes `mapToGlobal`
hätte das Menü an eine *falsche Position* gesetzt, nicht zum *Verschwinden* gebracht — das
Symptom passt nicht zum Fix. Wahrscheinlichste Ursache: ein nacktes `text%` ohne DrRacket-
Editor-Wrapper hat schlicht kein Default-Popup-Menü (mehrere mögliche Ursachen auf einer
anderen Schicht: fehlendes Default-Menü / Event-Delivery / `popup-menu`-Stub — nicht
weiter diagnostiziert, da out of scope für die beiden Menü-Fixes).

**4c. Echtes DrRacket (visuell, nach Crash-Fix aus §5):** Rechtsklick in den
Definitions-Editor → Kontextmenü (Undo/Redo/Copy/Cut/Paste/Clear/Select All) erscheint
**genau am Klickpunkt**, mitten im Editor — nicht am Fensterrand oder -ursprung.
Screenshot in der Session, vom Nutzer selbst ausgelöst (Rechtsklick ließ sich nicht
zuverlässig synthetisieren — `cliclick`/`Quartz`/PyObjC nicht auf der Maschine verfügbar).
**Ergebnis: grün.**

## 5. Abweichung — DrRacket-Startup-Crash (gefunden, mit Nutzer-Autorisierung gefixt)

**Befund:** `PLT_QT=1 drracket` (korrekt via `-S`-Override, qt-Backend nachweislich geladen)
zeigte einen `DrRacket Internal Error` unmittelbar beim Start, bevor irgendeine Datei geöffnet
wurde:

```
set-label method in .../wx/qt/platform.rkt:25:2: arity mismatch;
  expected: 1   given: 2
context: update-tabs-labels method in frame-mixin (drracket .../unit.rkt:2308)
```

**Root Cause:** `mrpanel.rkt`s `tab-panel%`-Glue ruft beim Start (über `update-save-message` →
`update-tabs-labels` → `update-tab-label`) `(send (get-tab-widget) set-label i s)` — **2 Argumente**
(Index + Label) — sobald `tab-panel-available?` `#t` liefert, weil das dann ein natives
Tab-Widget mit Item-genauer Label-Kontrolle voraussetzt. Der qt-Backend meldet
`tab-panel-available? => #t` (`wx/qt/platform.rkt:217`), hat aber **keine** dedizierte
`tab-panel.rkt`-Implementierung wie gtk (`wx/gtk/tab-panel.rkt:300`, `set-label i str`) oder
win32 (`wx/win32/tab-panel.rkt:149`, `set-label pos str`) — `tab-panel%` ist im qt-Backend nur
der generische `make-stub-class`-Stub mit einem 1-Arg-`set-label` im Button-Stil
(`platform.rkt:34`, alt). Der Crash trifft **jeden** Start mit einem Tab, dessen Label vom
initialen `""` abweicht — also den Normalfall.

**Fix** (`wx/qt/platform.rkt`, gui-Submodul `ba2dacc9`): `set-label` variadic gemacht, exakt
gespiegelt an der bereits bestehenden Rest-Arg-Behandlung von `append` in derselben
Stub-Factory (`(define/public (append . args) (void))`):

```racket
(define/public (set-label . args) (void))
```

Sicher, weil `set-label` in `make-stub-class` ausschließlich von reinen No-op-Stub-Klassen genutzt
wird (`canvas-panel%`, `check-box%`, `choice%`, `group-panel%`, `list-box%`, `radio-box%`,
`slider%`, `tab-panel%`) — keine davon ist ein echtes Widget mit echtem Label-Rendering, die
Arität ist für den No-op irrelevant. Betrifft **nur** `wx/qt/`, keine Änderung an
cocoa/gtk/win32-Pfaden.

**Nach dem Fix:** `raco make` auf `platform.rkt`, DrRacket neu gestartet — `activeWindow=QMainWindow
title='Untitled - DrRacket'`, alle 9 Top-Level-Menüs sichtbar (File/Edit/View/Language/Racket/
Insert/Scripts/Windows/Help), kein Crash. Smoke 3/3 weiterhin grün nach dem Fix.

## 6. Guardrail-Abweichung — bewusst, mit Nutzer-Autorisierung

Der Original-Prompt (`prompt08072026-4.md`) sah für diese Session **keine Fix-Commits**
vor („nur Sync + Rebuild + Messung + Doku … bei Abweichung: STOPP, berichten, NICHT
selbständig nachbessern"). Der DrRacket-Crash aus §5 wurde dem Nutzer gemeldet und
gestoppt; der Nutzer hat die Scope-Erweiterung **explizit angewiesen**
(„Den DrRacket crash sollten wir fixen. Das ging nämlich schon mal.") und zusätzlich für
das Kontextmenü-Thema eine bedingte Freigabe erteilt („Wenn der Weg ist, fixen wir auch das
Kontextmenü.") — Letzteres erwies sich als nicht nötig (§4b: kein Bug im Fix, kein
Handlungsbedarf). Alle übrigen Guardrails (kein `exec()`/`QEventLoop`, cocoa/gtk/win32
unberührt, Redraw-Bug unberührt, gated Diagnose bleibt gated, nur ff-Pulls) wurden
eingehalten.

## 7. Commits & Stand

| Repo | Commit | Inhalt |
|---|---|---|
| gui-Submodul (`qt-backend`) | `ba2dacc9` | `set-label`-Arity-Fix (`wx/qt/platform.rkt`), fast-forward auf lokalen `qt-backend`-Branch nach detached-HEAD-Submodul-Checkout |
| Umbrella (`main`) | `ea92deb` | Submodul-Zeiger auf `ba2dacc9` |

**Push-Status:** **noch nicht gepusht** — ausstehende Nutzer-Bestätigung vor dem Push auf den
gemeinsamen Remote-Branch (Blast-Radius: teilt sich `qt-backend` mit Windows/Linux).

## 8. Offene Punkte / nächste Schritte

1. **Push von `ba2dacc9` (gui) / `ea92deb` (Umbrella)** auf `origin` — ausstehend, Nutzer-OK
   einholen.
2. **Linux-Validierung** (Phase 1–4 dieses Prompts) steht weiterhin aus — erst wenn Linux
   ebenfalls grün ist, darf die `CLAUDE.md`-Checkpoint-Tabelle E-0-Menü als vollständig
   geschlossen markiert werden (inkl. des neuen `set-label`-Fixes, den Linux zwangsläufig
   mitzieht).
3. Windows sollte informiert werden, dass ein dritter Fix (`set-label`-Arity) auf
   `qt-backend` hinzugekommen ist, bevor dort re-synced wird.
4. Redraw-Bug weiterhin separat offen (aus dieser Session unverändert beobachtet: nur die
   zuletzt getippte Zeile rendert im Definitions-Editor — nicht angefasst, eigene Session).
5. `docs/HACKING.md` könnte um eine kurze Lektion zum `tab-panel-available?`/`set-label`-
   Vertrag ergänzt werden (nicht in dieser Session erledigt, da nicht explizit angefordert).

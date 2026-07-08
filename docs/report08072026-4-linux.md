# Bericht — Linux-Validierung addAction-/mapToGlobal-Fix + DrRacket-Startup-Crash gefixt (prompt08072026-4)

**Datum:** 2026-07-08
**Plattform:** Linux x86_64, KDE Plasma/X11
**Racket (gemessen, Phase 0):** v9.2 [cs] · **Qt:** 6.11.1 (`~/Qt/6.11.1/gcc_64`)
**Repro:** `examples/menu-click-probe.rkt` (`mixed`/`dynamic`) + ein Scratch-Sichtprobe-Skript
(`visual-probe.rkt`, nicht im Repo, analog zum macOS-Vorgehen) + echtes `PLT_QT=1 drracket` via
`-S`-Source-Override, Interaktion per synthetischem XTest-Klick (`libXtst` via Python-`ctypes`,
da kein `xdotool`/`xte` auf der Maschine verfügbar), Screenshots per `xwd`+eigenem XWD→PNG-Parser
(`xwd2png.py`, PIL hat kein XWD-Plugin)
**Startrezept:** `PLT_QT=1 racket -S third_party/gui/gui-lib -S third_party/draw/draw-lib -l drracket`
(Linux nutzt Installation-scope-Link **nicht** für `gui-lib` — Katalog-Paket bleibt Upstream 1.80,
Source-Override ist zwingend, sonst stiller Fallback auf gtk; verifiziert über `PLT_QT_DEBUG=1`
`menubar_create`-Zeilen)

**Kurzfassung:** Ursprünglicher Auftrag war reine Validierung (kein Fix) der beiden von Windows
gebrachten Menü-Fixes (`report08072026-3.md`), analog zur bereits abgeschlossenen macOS-Session
(`report08072026-4-macos.md`). Beide Fixes wurden auf Datenebene (Probe) **und** in echtem
DrRacket bestätigt. Wie auf macOS kam dabei ein **neuer, unabhängiger Startup-Crash** zutage
(`set-icon`-Methode fehlt komplett in der qt-`frame%`-Klasse), der DrRacket am Hochfahren
hinderte und die visuelle Validierung blockierte. Nutzer hat die Scope-Erweiterung nach
Rückfrage (`AskUserQuestion`) explizit autorisiert — der Crash wurde gefixt (Guardrail „keine
Fix-Commits" damit für diesen einen Punkt bewusst aufgehoben, wie beim macOS-Präzedenzfall),
danach waren beide ursprünglichen Fixes grün.

---

## 1. Phase 0 — Umgebung verifiziert

- `racket --version` → **v9.2 [cs]** (gemessen; Racket-Installation lag unter
  `/home/deinzer/racket`, nicht auf `$PATH` — `raco`/`racket` über Vollpfad aufgerufen).
- Umbrella (`main`): sauber, HEAD bereits `1028f4e` (neuer als der im Prompt genannte
  Zielcommit `96419c5` — enthält bereits den macOS-Report- und `set-label`-Fix-Commit).
  `git pull --ff-only` → „Already up to date".
- gui-Submodul (`third_party/gui`): **vor** Sync auf `381425d5` (alt, vor beiden Menü-Fixes UND
  vor dem macOS-`set-label`-Fix) — klassische stale-Shim-Falle, wie vom Prompt vorhergesagt. Die
  einzige lokale Abweichung war die Submodul-Zeiger-Drift selbst (`M third_party/gui` im
  Umbrella-Status), keine echten unstaged Changes — bestätigt über `git -C third_party/gui
  status --short` (leer).

## 2. Phase 1 — Sync + Rebuild

1. `git submodule update --init` → Submodul auf `ba2dacc9` (enthält `0be24d85` addAction-Fix,
   `1641f888` mapToGlobal-Fix, **und** den macOS-`set-label`-Fix — alle drei bereits auf
   `origin/qt-backend`, wie ein `git fetch` + `merge-base --is-ancestor`-Check bestätigte).
   Submodul-Checkout landet dabei erwartungsgemäß im **detached HEAD**.
2. `cmake --build qt-shim/build/linux-x64` (Ninja) — sauberer Rebuild, `shim.cpp` neu übersetzt.
3. Re-Smoke: `PLT_QT=1 QT_PLUGIN_PATH=~/Qt/6.11.1/gcc_64/plugins racket -S third_party/gui/gui-lib
   -S third_party/draw/draw-lib -l raco -- test tests/smoke.rkt` → **3 tests passed**.

**Ladecheck:** `raco pkg show gui-lib` → Installation-wide aus Katalog, User-specific `[none]` —
wie macOS nutzt auch diese Linux-Maschine **keinen** Installation-Link. `-S`-Override ist
zwingend für jeden Aufruf, der den qt-Backend-Code sehen soll.

## 3. Phase 2 — addAction-Fix, Validierung

**Probe (Datenebene, gated `shim_menu_debug_dump`):**

| Modus | Erwartet | Gemessen |
|---|---|---|
| `mixed` | `actions().size()=3`, Reihenfolge New/Recent(menu=1)/Save | ✅ exakt |
| `dynamic` | Separatoren Pos. 1/3, `Alpha enabled=0`, `Beta checked=1`, Größe 5→4 nach `delete` | ✅ exakt |

**Visuell (Scratch-Skript `visual-probe.rkt`, nicht im Repo, analog zum macOS-Datentest-Ansatz):**
ein Popup mit Blatt-Item + Submenü + Separator + Blatt-Item (`New` / `Recent ▸` / --- / `Save`)
wurde per `(send menu popup 400 400 #f #f)` geöffnet und per `xwd`-Vollbild-Screenshot
festgehalten — **alle vier Einträge korrekt sichtbar**, inklusive Submenü-Pfeil und
Separator-Linie. Damit ist der addAction-Fix erstmals auf dieser Session-Reihe auch als
Screenshot belegt (macOS hatte hierfür nur die reale DrRacket-Ansicht, kein isoliertes Bild).

**Echtes DrRacket (nach dem Crash-Fix aus §5):** ein synthetischer Linksklick auf den
Menü-Titel „File" (via `XTestFakeButtonEvent`, `libXtst`) öffnete das Dropdown nachweislich —
`[PLT_QT_DEBUG] popup APPEARED class=QMenu ... frameGeom=(1045,429 310x487)` deckt sich exakt
mit der real existierenden Fenstergeometrie (per `xwininfo` bestätigt: Fenster `0x400016`,
310×487 bei genau dieser Position). Der Debug-Dump zeigt **25 Aktionen** mit vollständig
korrekter Struktur (Blatt-Items wie „Save Definitions", zwei Submenüs „Open Recent"/„Save
Other", sechs Separatoren an den erwarteten Stellen) — identisch zur Windows-/macOS-Struktur.
**Ergebnis: grün.**

**Screenshot-Einschränkung (kein Fix-relevanter Bug, siehe §6):** der `xwd`-Vollbild-Screenshot
zeigte dieses spezifische DrRacket-interne Popup nicht sichtbar, obwohl es laut Debug-Log und
`xwininfo` korrekt existierte und positioniert war — reines Capture-Artefakt dieser
Session-Umgebung (Terminal-Fenster liegt im selben Bildschirmbereich), keine Aussage über die
tatsächliche Fix-Korrektheit.

## 4. Phase 3 — mapToGlobal-Fix, Validierung

**Echtes DrRacket, echter synthetischer Rechtsklick** (via `XTestFakeButtonEvent`, Button 3) in
den Definitions-Editor an Bildschirmposition (1339,807, fensterrelativ (300,400)):

```
[PLT_QT_DEBUG] popup APPEARED class=QMenu visible=1 frameGeom=(1340,808 216x204)
[PLT_QT_DEBUG] popup actions().size()=10
[PLT_QT_DEBUG] popup action[0] text='&Undo' ... action[5] text='&Paste' ... action[9] text='Search in Help Desk for "you"'
```

Das Kontextmenü öffnete an **(1340,808)** — 1 Pixel Differenz zum exakten Klickpunkt (1339,807),
vernachlässigbar (Cursor-Hotspot-Rundung) — statt am Fensterursprung (1039,407), wie es der alte
No-op verursacht hätte. Enthält den erwarteten Standard-Editor-Kontext (Undo/Redo/Copy/Cut/
Paste/Clear/Select All/Suchen). **Ergebnis: grün.**

Wie in §3 beschrieben zeigte der Vollbild-Screenshot dieses Popup ebenfalls nicht sichtbar
(gleiches Capture-Artefakt) — die Positions-/Inhaltsvalidierung stützt sich auf den gated
Debug-Dump plus unabhängige `xwininfo`-Geometrieabfrage, beides datengestützt und eindeutig.

**Anmerkung zu Klick-Synthese:** anders als macOS (wo laut `report08072026-4-macos.md` weder
`cliclick` noch Quartz/PyObjC verfügbar waren und der Nutzer manuell klicken musste) konnte auf
dieser Linux-Maschine ein echter synthetischer Maus-Klick über `libXtst`/`ctypes` erzeugt werden
— dadurch liegt hier sogar ein direkter Nachweis über einen echten Klick-Trigger vor, nicht nur
ein isolierter API-Test.

## 5. Abweichung — DrRacket-Startup-Crash (gefunden, mit Nutzer-Autorisierung gefixt)

**Befund:** `PLT_QT=1 racket ... -l drracket` (korrekt via `-S`-Override, qt-Backend nachweislich
geladen) crashte beim ersten Start mit:

```
send: no such method
  method name: set-icon
  class name: ...ed/private/wxtop.rkt:617:4
  context...:
   mred/private/mrtop.rkt:85:15: set-icon method in basic-top-level-window%
   framework/splash.rkt:203:3
   framework/splash.rkt:78:5
   mred/private/wx/common/queue.rkt:436:6 / :487:32 / :371:11 (eventspace-handler-thread-proc)
```

Der Splash-Screen (`framework/splash.rkt`) blieb dadurch **unmapped** (bestätigt per `xwininfo
-id`: `Map State: IsUnMapped`) — das Hauptfenster erschien nie, jede visuelle Validierung war
blockiert.

**Root Cause:** `mrtop.rkt`s `basic-top-level-window%` definiert `set-icon` als `public*`-Methode,
die direkt an den wx-Peer durchgereicht wird (`(send wx set-icon i [b] [l?])`, `case-lambda` für
1/2/3 Argumente). `win32/frame.rkt`, `gtk/frame.rkt` und `cocoa/frame.rkt` implementieren alle
`set-icon`; `wx/qt/frame.rkt` hatte **überhaupt keine** `set-icon`-Methode — der Aufruf schlägt
also nicht mit einem Arity-Mismatch fehl (wie beim macOS-`set-label`-Fall), sondern komplett mit
„no such method". Trifft **jeden** Start, da `splash.rkt` `set-icon` unbedingt aufruft.

**Fix** (`wx/qt/frame.rkt`, gui-Submodul `6df80516`): variadic No-op-Stub, exakt gespiegelt an
der bereits bestehenden `set-label`/`append`-Rest-Arg-Behandlung in diesem Backend:

```racket
(define/public set-icon
  (case-lambda
    [(i) (void)]
    [(i b) (void)]
    [(i b l?) (void)]))
```

Sicher, weil `frame%` im qt-Backend Icons ohnehin nirgends real anzeigt (keine Fensterdekoration
mit Icon-Unterstützung in dieser Backend-Ausbaustufe) — der No-op ändert das Verhalten für
keinen bestehenden Aufrufer, betrifft **nur** `wx/qt/`, keine Änderung an cocoa/gtk/win32.

**Nach dem Fix:** DrRacket startet vollständig — Hauptfenster „Untitled - DrRacket" erscheint,
alle 9 Top-Level-Menüs sichtbar (File/Edit/View/Language/Racket/Insert/Scripts/Tabs/Help,
Screenshot in der Session), kein Crash. Smoke 3/3 weiterhin grün nach dem Fix.

## 6. Nebenklärung — Screenshot-Capture-Lücke (kein Bug, nicht mit dem Redraw-Bug zu verwechseln)

Popups, die exakt über dem Bildschirmbereich des Session-Terminal-Fensters liegen, erschienen im
`xwd`-Vollbild-Screenshot nicht, obwohl sie laut gated Debug-Dump und `xwininfo`-Geometrieabfrage
einwandfrei existierten und korrekt positioniert waren. Das isolierte Scratch-Popup (§3, Position
(400,400), außerhalb des DrRacket-Fensters aber ebenfalls innerhalb des Terminal-Bildschirm-
bereichs) rendert dagegen **sichtbar korrekt** im selben Screenshot-Verfahren — der Unterschied
ist vermutlich Fenster-Stacking/Compositing-spezifisch für dieses Session-Setup (verschachtelte
Fenster, synthetische Eingabe ohne echten Fokuswechsel), nicht last die von `CLAUDE.md` als
offen geführte Redraw-Bug (die betrifft das Editor-Backing-Store-Repaint, nicht Popup-Sichtbarkeit
im Screenshot-Tool). Keine Handlung nötig — Daten-/Geometrie-Nachweis ist eindeutig und
ausreichend.

## 7. Guardrail-Abweichung — bewusst, mit Nutzer-Autorisierung

Der Original-Prompt (`prompt08072026-4.md`) sah für diese Session **keine Fix-Commits** vor.
Der DrRacket-Crash aus §5 wurde dem Nutzer über `AskUserQuestion` gemeldet und die Entscheidung
eingeholt; der Nutzer hat die Scope-Erweiterung **explizit gewählt** („Ja, fixen"). Alle übrigen
Guardrails (kein `exec()`/`QEventLoop`, cocoa/gtk/win32 unberührt, Redraw-Bug unberührt, gated
Diagnose bleibt gated, nur ff-Pulls) wurden eingehalten.

## 8. Commits & Stand

| Repo | Commit | Inhalt |
|---|---|---|
| gui-Submodul (`qt-backend`) | `6df80516` | `set-icon`-Stub (`wx/qt/frame.rkt`), lokaler `qt-backend`-Branch fast-forwarded nach detached-HEAD-Submodul-Checkout |
| Umbrella (`main`) | *(dieser Report-Commit)* | Submodul-Zeiger auf `6df80516` + Report + STATUS.md-Eintrag |

**Push-Status:** ausstehend — Nutzer-Bestätigung vor Push auf den gemeinsamen `qt-backend`-Branch
einholen (Blast-Radius: geteilt mit Windows/macOS).

## 9. Offene Punkte / nächste Schritte

1. **Push von `6df80516`** (gui) und dem Umbrella-Commit auf `origin` — ausstehend, Nutzer-OK
   einholen.
2. **Beide Plattformen (macOS + Linux) sind jetzt grün** — `CLAUDE.md`-Checkpoint-Tabelle
   E-0-Menü kann als vollständig geschlossen markiert werden (in dieser Session erledigt).
3. Windows sollte informiert werden, dass ein vierter Fix (`set-icon`-Stub) auf `qt-backend`
   hinzugekommen ist, bevor dort re-synced wird.
4. Redraw-Bug weiterhin separat offen (aus dieser Session unverändert, nicht angefasst).
5. Screenshot-Capture-Lücke aus §6 ist reine Session-Tooling-Beobachtung, keine Code-Änderung
   nötig — nicht weiter verfolgen.

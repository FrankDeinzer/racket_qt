# Report — Linux — Konsolidierung: Crash-A/B-Rückprüfung + Qt-eigen×nativ-Matrix

**Kontext:** `docs/2026-07-11-2_prompt.md` (Phase 2 + 3). Reihenfolge: nach Windows
(Phase 0/1, `docs/2026-07-11-2_report-win.md`), vor macOS (Phase 4).

**Header:** `racket --version` = `Welcome to Racket v9.2 [cs].` (gemessen), Ubuntu 24.04.4
LTS, Kernel 6.8.0-134-generic.

## 1. Sync (Phase 2, nach Nutzer-Bestätigung)

- gui-Submodul (`qt-backend`) ff-Pull `19954ffd` → `caef3e9c` (die zwei macOS-Fixe
  `acc73108` id-to-menu-item, `caef3e9c` retained-callbacks). Umbrella-Zeiger auf `main`
  zeigte bereits auf `caef3e9c` (aus dem Windows-Sync) — kein neuer Umbrella-Commit
  nötig, nur der lokale Submodul-Checkout war zurück.
- Diff `19954ffd..caef3e9c`: nur `gui-lib/mred/private/wx/qt/menu.rkt` +
  `platform.rkt` — reiner Racket-Code, kein Shim-Rebuild nötig (bestätigt Windows-Notiz).
- `raco make` für `mred/mred.rkt`, `draw/racket/draw.rkt`,
  `PLT_QT=1 raco make .../wx/qt/queue.rkt` — alle sauber.
- Re-Smoke: `PLT_QT=1 QT_PLUGIN_PATH=~/Qt/6.11.1/gcc_64/plugins racket -S
  third_party/gui/gui-lib -S third_party/draw/draw-lib -l raco -- test tests/smoke.rkt`
  → **3 tests passed**.
- Light Mode bestätigt (`kreadconfig5 --group General --key ColorScheme` → `BreezeLight`).

## 2. Crash-A-Rückprüfung (Kernstück)

4 gezielte Versuche, jeweils frischer `PLT_QT=1 PLT_QT_DEBUG=1`-DrRacket-Start
(`stdbuf -oL -eL racket -S ... -l drracket`, Log mitgeschrieben), File → Open so früh wie
möglich nach Fenstererscheinen geklickt (genau die Bedingung aus §6.1 des
Vorberichts):

| Versuch | Ergebnis |
|---|---|
| 1 | Internal-Error-Dialog (htdp-Bug, siehe 2.1) — kein Crash-A-Repro |
| 2 | Sauber (Dialog öffnet, Datei lädt, kein Fehler im Log) |
| 3 | Sauber |
| 4 | Sauber |

Der ursprüngliche `pre: arity mismatch … terminated in atomic mode!`-Absturz
(Prozessende) trat in **keinem** der 4 Versuche auf. **Einordnung:** plausibel durch
`acc73108`/`caef3e9c` behoben, aber keine absolute Evidenz — das Original war n=1-
intermittierend, n=4-sauber (bzw. 3 sauber + 1 anderweitig konfundiert) ist ein starkes,
kein beweisendes Signal.

### 2.1 Neuer Datenpunkt: htdp-lib-Bug-Rezidiv (schon bei einem Tab)

Versuch 1 zeigte statt Crash A den bereits aus dem macOS-Bericht (§19, „dritter Fund")
bekannten Contract-Verstoß:

```
DrRacket Internal Error
preferences:set: new value doesn't satisfy
preferences:set-default predicate
 pref symbol: 'test-engine:test-dock-size
 given: '(1)
 predicate:
#<procedure:...ngine/test-tool.rkt:10:25>
 context...:
/home/deinzer/racket/collects/racket/contract/private/arrow-val-first.rkt:518:18
```

Screenshot bestätigt (Dialog + dahinterliegendes `a1.rkt`-Editor-Fenster, nur eine
Registerkarte offen). Anders als im macOS-Bericht (der einen zweiten geöffneten Tab als
Auslöser brauchte) trat der Fehler hier bereits beim **allerersten** File → Open mit nur
einer Registerkarte auf — der Auslöser ist also weiter gefasst als bisher dokumentiert.
Nach OK-Klick: Prozess blieb am Leben, Definitions-Editor blieb normal editierbar, aber
die Interactions-Leiste (unterer REPL-Bereich) fehlte sichtbar — konsistent mit einem
gestörten Panel-Layout durch die fehlgeschlagene `test-dock-size`-Preference. Nutzer
bestätigte explizit: `htdp` wurde nicht selbst geladen — der Fehler kommt aus DrRackets
eigenem Tools-Autoload, nicht aus Nutzer-Code. Nicht root-caused, außerhalb des Scopes
dieser Session (`htdp-lib`, nicht `wx/qt/`) — keine Fix-Versuche, reine Beobachtung für
die künftige dedizierte Session (siehe `docs/2026-07-11-2_prompt.md`, OUT OF SCOPE).

## 3. Crash-B-Rückprüfung

Isoliertes Skript ohne sichtbares `frame%`:

```
PLT_QT=1 PLT_QT_DEBUG=1 QT_PLUGIN_PATH=~/Qt/6.11.1/gcc_64/plugins \
  racket -S third_party/gui/gui-lib -S third_party/draw/draw-lib \
  -e '(require racket/gui) (displayln (put-file "Save test" #f #f "myfile" "rkt"))'
```

1/1 exakt reproduziert: Nutzer tippte Dateinamen, speicherte. Log druckte den korrekten
Pfad (`/home/deinzer/src/racket_qt/ffff.rkt`), **danach sofort**:

```
invalid memory reference.  Some debugging context lost
```

Prozessende. Identisches Fehlerbild wie im Ursprungsbericht (§6.2) — bestätigt die
bestehende Hypothese (Teardown-/`deleteLater()`-Reihenfolgeproblem zwischen
Event-Pump-Thread und Racket-Custodian-Shutdown), unabhängig von den beiden
Menü-Dispatch-Fixen. **Bleibt offener Befund für gemeinsamen Code — nicht gefixt
(Guardrail dieser Session), Entscheidung über Verfolgung liegt beim Nutzer.**

Kein `ffff.rkt` tatsächlich auf Platte gelandet (`put-file` liefert nur den Pfad zurück,
schreibt selbst nichts) — kein Aufräumbedarf, `git status` bestätigt sauberen Baum.

## 4. Qt-eigen×nativ-Matrix (Phase 3)

Qt-eigen (Default, `DontUseNativeDialog=true`) war aus der Vorsession bereits grün
(9/9, `docs/2026-07-11_report-linux.md`) — hier nicht wiederholt.

Nativer Pfad (`PLT_QT_NATIVE_FILE_DIALOG=1`, `examples/file-dialog-probe.rkt`):
**8/8 Zyklen grün** (gemischt Open/Save/Cancel über Button- und Menü-Pfad), `cb`-Adresse
(`0x458d9d60`) über alle 8 Aufrufe identisch (bestätigt Trampolin-Wiederverwendung auch
hier), kein Crash, kein Hang, `native=1` im Log durchgehend bestätigt. Welcher konkrete
Dialog (KDE-nativ vs. xdg-desktop-portal) erschien, konnte der Nutzer mangels
Vergleichsreferenz nicht zuordnen — funktional aber eindeutig grün, keine eigene Runloop
nötig, kein `exec()`.

**Matrix-Stand (3 Plattformen × 2 Dialog-Typen):**

| Plattform | Qt-eigen | Nativ |
|---|---|---|
| Windows | ✅ 7/7 (Vorsession) | ✅ 7/7 (Vorsession) |
| Linux | ✅ 9/9 (Vorsession) | ✅ 8/8 (diese Session) |
| macOS | ✅ 7/7 + DrRacket (Vorsession) | ⬜ offen (Phase 4) |

## 5. Guardrails eingehalten

- Kein `exec()`/`QEventLoop`, keine geschachtelte Schleife.
- Keine Fixe in gemeinsamem Code — Crash B und der htdp-Bug wurden gemessen und
  dokumentiert, nicht angefasst.
- Sync-Schritt (Submodul-Pull) vorab per `AskUserQuestion` bestätigt.
- Kein Umbrella-Commit nötig (Zeiger war bereits korrekt).
- Alle Testartefakte geprüft/aufgeräumt (`git status` sauber bis auf die beabsichtigten
  `docs/HACKING.md`-Änderungen).

## 6. Nächster Schritt

- macOS Phase 4 (nativ-Matrix) steht noch aus — damit wäre die 3×2-Matrix vollständig.
- Crash B und das htdp-Bug-Rezidiv zur Entscheidung beim Nutzer: eigene Session ansetzen
  oder zurückstellen.
- Umbrella-Zeiger/Doku-Commit dieser Session folgt (kein neuer gui-Submodul-Commit, nur
  `docs/HACKING.md` + `STATUS.md` + dieser Report im Umbrella).

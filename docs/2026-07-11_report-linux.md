# Report: 2026-07-11_prompt (Linux, Cross-Platform-Validierung)

**Racket-Version (gemessen):** Welcome to Racket v9.2 [cs].

## 1. Zusammenfassung

Validierungssession (kein neuer Fix-Code in `wx/qt/`) für den auf Windows gebauten
`file-selector` (`get-file`/`put-file` via non-modalem `QFileDialog`, `docs/HACKING.md`
§19). Kernmechanik + Einmal-Trampolin-Fix sind auf Linux grün: 9/9 aufeinanderfolgende
Dialog-Zyklen über den Probe-Treiber (Öffnen + Speichern gemischt), stabile
Callback-Adresse über alle 9 Aufrufe. Echtes DrRacket bestätigt File → Open und File →
Save funktional (Datei lädt in den Editor, Datei wird inhaltlich korrekt gespeichert).
Ein isolierter Zusatztest bestätigt, dass `setDefaultSuffix` (Extension-Anhängen) korrekt
arbeitet.

**Zwei unabhängige, seltene Abstürze wurden dabei beobachtet und sind dokumentiert, aber
nicht root-caused/gefixt** (Guardrail: nicht auf eigene Faust in gemeinsamem Code fixen).
Beide liegen nachweislich AUSSERHALB des `get-file`/`put-file`-Rückgabewert-Pfads selbst
(Details Abschnitt 6). Keine Fix-Commits diese Session — reine Validierung + Befund.

## 2. Phase 0 — Sync + Rebuild

- **Vor dem Pull geprüft** (CLAUDE.md Regel 7): Nutzer per `AskUserQuestion` gefragt, ob
  jetzt gepullt werden soll — bestätigt.
- gui-Submodul (`qt-backend`) lag 2 Commits hinter `origin/qt-backend`: `f92352e0` →
  `19954ffd` via `git pull` (Fast-Forward). Enthaltene Commits: `15dee9f9` (get-file via
  non-modalem `QFileDialog`), `19954ffd` (put-file auf demselben Pfad).
- Umbrella `main` war bereits mit `origin/main` deckungsgleich (`8c3e00d`), Zeiger auf
  `third_party/gui` bereits `19954ffd` — kein Umbrella-Pull nötig, keine Diskrepanz.
- **Shim neu gebaut** (`cmake --preset linux-x64 -S qt-shim && cmake --build
  qt-shim/build/linux-x64`): sauberer Build, `shim.cpp` enthält bereits
  `shim_file_dialog_create` (kam über den Umbrella-Commit `a40ae55`/`a773c8a`, war schon
  vor dem Submodul-Pull im Baum), Link ohne Fehler/Warnungen.
- **Bytecode neu:** `racket -S third_party/gui/gui-lib -S third_party/draw/draw-lib
  -l raco -- make -l mred` — durchgelaufen ohne Fehler/Warnungen.
- **Re-Smoke:** `PLT_QT=1 QT_PLUGIN_PATH=~/Qt/6.11.1/gcc_64/plugins racket -S ... -l raco
  -- test tests/smoke.rkt` → **3/3 grün**.
- **Light Mode bestätigt:** `~/.config/racket/racket-prefs.rktd` zeigt
  `color-scheme-light classic`, kein `white-on-black-mode?`-Override (Default `#f`).

## 3. Checkpoint 1/2 — Probe-Treiber (`examples/file-dialog-probe.rkt`)

Nutzer-Interaktion (echte Klicks, `PLT_QT_DEBUG=1`):

- **`get-file` (Öffnen):** 5 Zyklen — 3× Datei ausgewählt (`README.md` ×2,
  `examples/textfield-debug.rkt`), 2× Abbrechen. Alle Rückgabewerte korrekt (Pfad bzw.
  `#f`). `cb`-Adresse `0x464bffb0` über alle 5 Aufrufe identisch.
- **`put-file` (Speichern):** 4 weitere Zyklen (IDs 5–8) — 2× auf existierende Dateien
  gespeichert (`examples/menu-frame.rkt`, `examples/menu-click-probe.rkt`, Qt-eigene
  Overwrite-Warnung dabei mitgetestet), 2× Abbrechen. Dieselbe `cb`-Adresse
  `0x464bffb0` weiterhin identisch — **stabil über 9 Aufrufe hinweg und über den
  Moduswechsel `get`→`put`**, bestätigt das Einmal-Trampolin-Fix (§19, Fund 2) auch auf
  Linux.
- Parent-Frame während offenem Dialog sichtbar deaktiviert (Fix B, §18.3, wiederverwendet
  wie im Windows-Bericht beschrieben), danach wieder normal.
- Smoke 3/3 weiterhin grün.

## 4. Checkpoint 2 — Abschluss-Verifikation, echtes DrRacket

- `PLT_QT=1 PLT_QT_DEBUG=1 racket -S ... -l drracket` gestartet. **DrRacket startet auf
  dieser Maschine spürbar langsamer als die Probe-Skripte** — ein erster Interaktions-
  versuch kurz nach dem Start führte zu Crash A (Abschnitt 6.1); nach dem Hinweis des
  Nutzers ("DrRacket braucht lange zum Starten") und einem geduldigeren zweiten Versuch
  liefen beide Kernfälle sauber:
  - **File → Open:** Dialog erschien, Nutzer wählte eine `.rkt`-Datei, Datei erschien
    im Definitions-Editor. Bestätigt (Nutzer).
  - **File → Save As:** Dialog erschien, Nutzer tippte einen Dateinamen ohne Endung,
    Datei wurde inhaltlich korrekt gespeichert. Bestätigt (Nutzer).
- **Nebenbefund beim Speichern:** die reale DrRacket-Save-As-Dialogbox hängte im
  Nutzertest keine `.rkt`-Endung an einen extensions-losen Dateinamen an, obwohl
  `framework/private/racket.rkt`s `put-file`-Override `finder:default-extension` auf
  `"rkt"` setzt, sobald der Parameter leer ist, und dieser Wert über
  `framework/private/finder.rkt`s `*put-file*` bis zu unserem `file-selector` als
  `extension`-Argument durchgereicht wird. Ein isolierter Gegentest (Abschnitt 5) zeigt,
  dass der Mechanismus in `shim_file_dialog_create` (`setDefaultSuffix`) korrekt
  arbeitet — die Diskrepanz bleibt als ungeklärte Randnotiz stehen (mögliche Ursachen:
  ein bereits mit Endung vorbelegter Default-Dateiname im DrRacket-Fall, oder
  `default-extension` war zum Zeitpunkt dieses konkreten Aufrufs schon nicht mehr `""`;
  nicht weiter verfolgt, siehe Guardrail "nicht auf eigene Faust in gemeinsamem Code
  fixen").

## 5. Zusatztest — Extension-Anhängen isoliert bestätigt

Isoliertes Skript (`(put-file "Save test" #f #f "myfile" "rkt")`, `extension` explizit
gesetzt wie es `finder:put-file` tut): Nutzer tippte `myfile` (ohne Endung) und speicherte
— Rückgabewert `.../myfile.rkt`. **`setDefaultSuffix` in `shim_file_dialog_create` hängt
die Endung korrekt an**, wenn `extension` gesetzt ist und der Aufrufer keine eigene
Endung tippt. Der `file-selector`-Wertpfad ist damit für diesen Anwendungsfall bestätigt
korrekt; das DrRacket-Nebenbefund aus Abschnitt 4 liegt folglich nicht im Shim/Racket-
Glue-Code für `file-selector` selbst.

## 6. Zwei unabhängige Abstürze — dokumentiert, nicht root-caused

Beide Funde liegen außerhalb des eigentlichen `get-file`/`put-file`-Wertpfads: in Crash A
lief `file-selector`s Körper nachweislich nie an (kein `[qt-filedialog] calling
shim_file_dialog_create id=…`-Log vor dem Absturz, obwohl `dbg` nach jeder Zeile explizit
flusht); in Crash B war der korrekte Rückgabewert bereits gedruckt, bevor der Absturz
folgte. Kein Fix-Versuch (Guardrail: beide berühren mutmaßlich gemeinsamen Code
`wx/common/queue.rkt` bzw. Shutdown-Reihenfolge, nicht `wx/qt/`-Fachcode — Entscheidung
über Verfolgung liegt beim Nutzer, siehe Abschnitt 8).

### 6.1 Crash A — `pre: arity mismatch`, `terminated in atomic mode!` (n=1, nicht reproduziert)

Beim allerersten Interaktionsversuch mit einer frisch gestarteten (noch nicht vollständig
initialisierten) DrRacket-Instanz: Klick auf File → Open führte zum sofortigen
Prozessende. Log (mit `stdbuf -oL -eL`, um Pufferungsartefakte auszuschließen):

```
[PLT_QT_DEBUG] popup APPEARED class=QMenu … actions().size()=25
[PLT_QT_DEBUG] popup action[2] text='&Open…	Ctrl+O' …
… (23 weitere Menüpunkte geloggt) …
[qt-canvas] begin-refresh-sequence -> suspend-flush
[qt-canvas] end-refresh-sequence -> resume-flush
[qt-dc] queue-backing-flush called
…
pre: arity mismatch;
 the expected number of arguments does not match the given number
  expected: 0
  given: 1
  context...:
   .../wx/qt/queue.rkt:27:5
internal-error: terminated in atomic mode!
```

- Kontext-Frame `queue.rkt:27:5` ist der Event-Pump-Thread (`(atomically (shim_pump
  0))`), d.h. der Fehler wurde während eines laufenden `shim_pump()`-Aufrufs ausgelöst,
  in Racket-Atomic-Modus — konsistent mit „irgendein natives Callback rief eine Racket-
  Prozedur mit falscher Arität auf". **Kein `[qt-filedialog]`-Log erscheint vor dem
  Absturz** — `file-selector`s Körper (der explizit und sofort flusht) wurde nie
  betreten. Der Fehler liegt also VOR dem eigentlichen Dialog-Aufruf, nicht in
  `get-file`/`put-file` selbst.
- `(procedure-arity ...)`-Signatur `expected: 0, given: 1` passt zum Muster von
  `wx/common/queue.rkt`s `pre-event-sync`, das registrierte Boundary-Callbacks per `(p
  v)` (1 Argument) aufruft — alle bekannten Registrierungsstellen in `gui-lib`
  (`canvas-mixin.rkt`, `delay.rkt`) sind aber bereits arity-1. Die konkrete fehlerhafte
  Registrierung wurde NICHT identifiziert (kein Stack-Trace über den einen Frame hinaus,
  da Racket im Atomic-Modus die Continuation-Marks nicht sicher weiter auflösen kann).
- **Nicht reproduziert:** ein zweiter, geduldigerer Versuch (Nutzer wartete DrRackets
  vollständigen Start ab) führte File → Open sauber durch (Abschnitt 4). Ein gezielter
  Diskriminator-Test (Edit → Select All vor File → Open, um zu prüfen, ob JEDER
  Menü-Befehl früh im Start abstürzt oder nur der dialogauslösende) wurde begonnen, aber
  vom geduldigeren Erfolgstest überholt und nicht sauber isoliert abgeschlossen.
- **Einordnung:** n=1, intermittierend, nicht reproduziert. Naheliegende, aber NICHT
  bestätigte Hypothese: ein Timing-/Initialisierungs-Wettlauf beim frühen Interagieren
  mit einer noch nicht vollständig hochgefahrenen DrRacket-Instanz. Das wird hier bewusst
  als offene Beobachtung berichtet, nicht als bewiesene Ursache.

### 6.2 Crash B — `invalid memory reference` nach bereits korrektem Rückgabewert

Isoliertes Skript ohne sichtbares `frame%` (nur `(put-file …)` direkt aufgerufen, siehe
Abschnitt 5): nach Nutzer-Interaktion (Dateiname getippt, gespeichert) druckte das Skript
den korrekten Pfad (`.../myfile.rkt`), **danach** erschien:

```
#<thread:...ate/wx/qt/queue.rkt:27:5>
result: /home/deinzer/src/racket_qt/myfile.rkt
invalid memory reference.  Some debugging context lost
```

und der Prozess endete. Der `get-file`/`put-file`-Wertpfad hatte zu diesem Zeitpunkt
bereits korrekt zurückgegeben — der Absturz korreliert mit dem anschließenden
Racket-Prozessende (dieses Skript zeigt nie ein `frame%` und ruft `register-frame-shown`
nie auf, d.h. die Racket-Laufzeit beendet sich nach Auswertung des Modul-Bodys reines
Skript-Ende), nicht mit dem Dialogergebnis selbst. Naheliegende, nicht verifizierte
Hypothese: eine Teardown-Reihenfolge zwischen dem Event-Pump-Thread und einem noch
`deleteLater()`-anstehenden `QFileDialog`, die beim regulären Custodian-Shutdown mit
einer noch laufenden Qt-Aufräum-Operation kollidiert. Weder in der Probe (Fenster bleibt
offen) noch in echtem DrRacket (Hauptfenster bleibt offen) reproduziert — beide halten
den Prozess über ein sichtbares `frame%` am Leben.

## 7. Guardrails eingehalten

- Kein `exec()`/`QEventLoop`, keine geschachtelte Schleife — non-modaler `open()`+Pump-
  Mechanismus unverändert wie von Windows übernommen.
- cocoa/gtk/win32 nicht angefasst.
- Nur Fast-Forward-Pull, vorher per `AskUserQuestion` bestätigt.
- Gated Diagnose bleibt gated (`PLT_QT_DEBUG` nicht verändert, keine neuen permanenten
  Debug-Hooks hinzugefügt).
- Keine Fix-Commits in `wx/qt/` — reine Validierung + zwei dokumentierte, nicht
  root-caused Abstürze außerhalb des Fachcode-Pfads.
- Report-Header nutzt gemessene `racket --version`.

## 8. Commits & Stand

- gui-Submodul (`qt-backend`): ff-Pull `f92352e0` → `19954ffd`, keine neuen Commits.
- Umbrella (`main`): `docs/HACKING.md` §19 (Linux-Validierungsabsatz), `STATUS.md`-
  Eintrag, dieser Bericht. Kein Submodul-Zeiger-Commit nötig (Zeiger war bereits korrekt).

## 9. Nächste Schritte / offene Punkte

- **Cross-Platform:** macOS-Validierung dieses Prompts steht noch aus.
- **Native Windows-Dialog / volle Qt-eigen×nativ-Matrix auf Linux/macOS:** bewusst nächste
  Runde (wie im Prompt vorgesehen), hier nicht getestet.
- **Crash A + Crash B:** beide dem Nutzer zur Entscheidung vorgelegt — jetzt gezielt
  verfolgen (z. B. gated Instrumentierung in `pre-event-sync`, die `(object-name p)` +
  `(procedure-arity p)` vor `(p v)` loggt, um den fehlerhaften Callback bei Crash A zu
  identifizieren) oder einer eigenen, dedizierten Session überlassen.
- **DrRacket-Extension-Nebenbefund** (Abschnitt 4): ungeklärt, niedrige Priorität, nicht
  weiter verfolgt.
- Rest von Checkpoint E (choice%/radio-box%/slider%/tab-panel%, Preferences-Dialog)
  weiterhin offen.

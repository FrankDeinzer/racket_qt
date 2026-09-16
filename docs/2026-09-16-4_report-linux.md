# Report — „Crash B" (Teardown, `invalid memory reference`) gefixt (Linux) — 2026-09-16 (4)

**Auftrag:** Nutzerfrage zu Sessionbeginn: ist „Linux Crash B (Teardown, `invalid
memory reference`)" aus `CLAUDE.md` noch offen, und soll daran weitergemacht werden?
Letzter Stand war 2026-07-12 (`docs/2026-07-11-2_report-linux.md`): 1/1 exakt
reproduziert, Root-Cause nicht gefunden, per Guardrail für eine eigene Session
zurückgestellt.

**Ergebnis in drei Sätzen:** Crash B reproduziert 1/1 identisch zum Originalbefund;
per gdb-Backtrace root-caused auf einen fehlenden Pump-Zyklus zwischen
`QFileDialog::deleteLater()` und Racket-seitigem `(exit)` in einem frameless Skript —
Qts eigener atexit-Event-Flush lieferte das ausstehende `DeferredDelete` stattdessen
aus, während andere Qt-Globals schon abgebaut waren, und stürzte tief in
`QSettings::QSettings` ab. Fix: ein expliziter `(atomically (shim_pump 0))`-Aufruf in
`wx/qt/filedialog.rkt` nach dem synchronen Warten auf das Dialogergebnis — **keine
Shim-ABI-Änderung**, per gdb-Breakpoint-Nachweis auf `QFileDialog::~QFileDialog`
verifiziert, dass der Destruktor jetzt tatsächlich über diesen neuen Aufruf läuft.

**Eine Racket-seitige Änderung, kein Shim-Rebuild-Bedarf.**

**Inhalt:** Reproduktion · gdb-Backtrace/Root-Cause · Fix · Mechanismus-Verifikation
(gdb-Breakpoint) · Regressions-Gate · Nicht gemacht · Startpunkt.

Technik im Detail: `docs/HACKING.md` §39.

---

## Phase 1 — Reproduktion vor dem Fix

Minimalskript (kein `frame%`, `(put-file)` als letzte Aktion vor Modulende), per
`xdotool` bedient (Fenster über `xdotool search --name "Save As"` gefunden, echte
Klickkoordinaten/Tastatureingabe, kein geschätzter Klick):

```
[crash-b-repro] about to call put-file
[crash-b-repro] put-file returned: /home/deinzer/src/racket_qt/crashb-repro-test.rkt
invalid memory reference.  Some debugging context lost
```

1/1, exakt derselbe Wortlaut wie im 2026-07-11-Bericht. (`put-file` schreibt selbst
keine Datei — der zurückgegebene Pfad existiert nie auf Platte, bestätigt, kein
Aufräumbedarf.)

## Phase 2 — Root-Cause per gdb-Backtrace

`gdb -q -batch -ex run -ex "thread apply all bt" -ex quit --args ~/racket/bin/racket
…` (Dialog wie oben bedient), Absturzpunkt:

```
Thread 1 "racket" received signal SIGSEGV, Segmentation fault.
#0  QSettings::QSettings(…) () from libQt6Core.so.6
#1  QFileDialogPrivate::saveSettings() () from libQt6Widgets.so.6
#2  QFileDialog::~QFileDialog() ()
#3  QObject::event(QEvent*) ()
#4  QApplicationPrivate::notify_helper(QObject*, QEvent*) ()
#5  QCoreApplicationPrivate::sendPostedEvents(QObject*, int, QThreadData*) ()
#6  __run_exit_handlers (…) at ./stdlib/exit.c:108
#7  __GI_exit (…) at ./stdlib/exit.c:138
#8  c_exit ()
#9  S_call_help () / Scall2 () / racket_boot () / main ()
```

Von unten gelesen: Racket ruft am Modulende `(exit)` → glibc `exit()` durchläuft seine
`atexit`-Kette → eine darin registrierte Qt-Routine liefert ein noch ausstehendes
`DeferredDelete`-Event aus → das zerstört den `QFileDialog`, dessen Destruktor
`QFileDialogPrivate::saveSettings()` aufruft → das baut ein `QSettings`-Objekt →
Absturz in `libQt6Core`.

Grund für das ausstehende Event: `shim_file_dialog_create`s `finished`-Handler
(`qt-shim/src/shim.cpp:1341-1375`) ruft `dlg->deleteLater()` erst **nach** dem
Racket-Callback — ein synchrones `delete` an dieser Stelle wäre unsicher (der Dialog
steckt noch im eigenen Signal-Emissions-Stack). Mit offenem `frame%` drainiert der
laufende `qt-start-event-pump`-Thread (50ms-Poll, `wx/qt/queue.rkt:23-35`) dieses
Event längst, bevor irgendetwas `(exit)` ruft. In einem frameless Skript ist der
Rückgabewert von `put-file`/`get-file` aber der letzte Racket-Akt vor Prozessende —
nichts garantierte einen weiteren Pump-Zyklus dazwischen. Damit ist die
2026-07-11-Hypothese präzisiert: **kein** allgemeines Teardown-Reihenfolgeproblem,
sondern eine fehlende Pump-Garantie an genau einer Stelle.

## Phase 3 — Fix

`gui-lib/mred/private/wx/qt/filedialog.rkt`: nach dem `yield` auf `done-sema` einmal
mehr `(atomically (shim_pump 0))`, bevor der Ergebniswert zurückgegeben wird — dieselbe
Primitive/derselbe Aufrufstil wie `queue.rkt`s Wakeup-Hook. `shim_pump` war bereits
nach Racket exportiert; **keine neue Shim-Funktion, keine ABI-Änderung.**

## Phase 4 — Mechanismus verifiziert, nicht nur das Symptom

Advisor-Einwand vor dem Commit: „Symptom weg" beweist nicht *wie* — Qt gated
`DeferredDelete` an Loop-Level-Buchhaltung, ein zusätzlicher `processEvents()`-Aufruf
könnte ebenso gut nur reposten, und 3/3 grün wäre dann der 50ms-Poll-Thread, der das
Rennen zufällig gewinnt.

Entschieden per gdb-Breakpoint auf `QFileDialog::~QFileDialog` (`set breakpoint
pending on`, Symbol löst erst nach dem Laden von `libQt6Widgets.so.6` auf):

```
Thread 1 "racket" hit Breakpoint 1.2, … QFileDialog::~QFileDialog() ()
#0  QFileDialog::~QFileDialog() ()
#1  QObject::event(QEvent*) ()
#2  QApplicationPrivate::notify_helper(…) ()
#3  QCoreApplication::notifyInternal2(…) ()
#4  QCoreApplicationPrivate::sendPostedEvents(…) ()
#5  QEventDispatcherGlib::processEvents(…) ()
#6  QCoreApplication::processEvents(…) ()   [zweimal, Overload-Kette]
#8  shim_pump (max_ms=0) at qt-shim/src/shim.cpp:315
#9  S_call_help () / Scall2 () / racket_boot () / main ()
```

Der Destruktor läuft jetzt über **genau den neuen, expliziten `shim_pump`-Aufruf**,
direkt von Racket-Top-Level aus — nicht über den Poll-Thread, nicht über `atexit`.
Mechanismus empirisch bestätigt.

## Phase 5 — Regressions-Gate

- **Smoke 3/3 beide Wege** (Qt + nativ).
- **Neue Probe `examples/crash-b-teardown-probe.rkt`** (durables Äquivalent des
  Reproduktionsskripts): Accept-Pfad 3/3 grün (`EXITCODE=0`, kein Crash-Log-Eintrag
  mehr), Cancel-Pfad (Escape) 1/1 grün — beide Pfade rufen `deleteLater()` im selben
  Handler auf, beide vorher betroffen.
- **`examples/file-dialog-probe.rkt`** (frame-offen-Pfad, derselbe Code, dieselbe neue
  Pump-Zeile durchlaufen): `get-file` mit Cancel, drei aufeinanderfolgende
  `put-file`-Zyklen, `Force GC`-Menüpunkt (der historische §19-Stresstest für
  Callback-Retention) — alle grün, kein Regressions-Crash.
- **Echtes DrRacket** (`PLT_QT=1 ~/racket/bin/racket -l drracket`): File → Save
  Definitions As, Dateiname eingetippt, Datei landet korrekt auf Platte, kein Crash.

## Nicht gemacht (bewusst)

- **Crash A** (der zweite, seltenere §19-Nebenbefund, `arity mismatch` beim
  allerersten Interaktionsversuch) bleibt unberührt — anderer Codepfad
  (`wx/common/queue.rkt`s `pre-event-sync`-Boundary vs. hier `deleteLater()`/
  Exit-Timing), nicht Teil dieser Session. War laut §19 „plausibel mitbehoben, nicht
  absolut bewiesen" durch die 2026-07-12-Menü-Fixe — unverändert.
- **Kein Cross-Platform-Durchlauf** — nur Linux gefixt/getestet (Cross-Platform-Modell
  dieses Projekts: Divergenzmessung nur bei bekannten Plattformunterschieden; hier
  reine Racket-Logik ohne einen solchen). Windows/macOS validieren dies in einer
  späteren Session, brauchen aber **keinen** Shim-Rebuild dafür (reiner
  `raco make`/Source-Sync auf den bestehenden gui-lib-Branch reicht).

## Commits

Siehe `STATUS.md` (oberster Eintrag) für die genaue Commit-Reihenfolge
(Submodul zuerst, dann Umbrella-Zeiger, nach CLAUDE.md-Regel 8).

## Startpunkt für die nächste Sitzung

- Windows/macOS: `git pull` auf `qt-backend`, `raco make` (kein Rebuild), Crash-B-Probe
  + Smoke gegenprüfen — sollte identisch grün sein (reine Racket-Logik).
- Weiterhin unverändert offen: Windows/macOS-Rebuild für §32/§33/§36/§37 (vier
  ausstehende Shim-Exporte), macOS-Zeilen §29.2/§22 (Zombie-Prozess) mit echter
  Klick-Methode nachmessen (s. §38), Bild-Zwischenablage/`cursor-driver%`/`gauge%`/
  `printer-dc%`/`get-current-mouse-state`-Stubs, Windows-Streifenrechteck-Hypothese
  zu §35.

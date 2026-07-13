# Report — macOS Nativ-Datei-Dialog-Matrix (Phase 4) — 2026-07-13

**Kontext:** `docs/2026-07-13_prompt-macos.md`. Maschine: macOS arm64.

**Header:** `racket --version` gemessen → `Welcome to Racket v9.2 [cs].` (arm64,
`uname -m` bestätigt, `(system-type 'arch)` → `aarch64`).

## Phase 0 — Umgebung (alles grün)

- Sync-Check (kein Auto-Pull): gui-Submodul (`third_party/gui`, `qt-backend`) @
  `caef3e9c`, identisch mit Umbrella-Zeiger (`git ls-tree HEAD third_party/gui`).
  Beide Branches up to date mit ihren Remotes (`git fetch --dry-run` auf beiden Repos
  ohne neue Refs). Kein Pull nötig, keine Frage an den Nutzer erforderlich.
- Shim: `libracketqtshim.dylib` (12. Jul, 13:20) neuer als `shim.cpp` (12. Jul,
  13:18) → aktuell, kein Rebuild nötig.
- Light Mode: `framework:white-on-black-mode?` = `#f` in
  `org.racket-lang.prefs.rktd` bestätigt (nicht den Legacy-Key geprüft).
- Smoke: `PLT_QT=1 racket -S third_party/gui/gui-lib -S third_party/draw/draw-lib -l
  raco -- test tests/smoke.rkt` → **3/3**.
- Nebenfund (kein Blocker): unbekannte untracked Datei `foo` im Umbrella-Root (Rest
  aus einer früheren Session, 8. Juli) — unangetastet gelassen.

## Phase 1 — Nativ-Matrix: Kernfrage beantwortet

**Instrumentierung:** `examples/file-dialog-probe.rkt` um einen Racket-seitigen
`timer%`-Heartbeat (200 ms, gated hinter `PLT_QT_DEBUG`) erweitert — reine
Diagnose, kein `wx/qt`-Code, kein Effekt auf den Dialog-Wertpfad.

**Ergebnis (gemessen, `PLT_QT_NATIVE_FILE_DIALOG=1 PLT_QT_DEBUG=1`): der native
macOS-Dateidialog (NSOpenPanel/NSSavePanel) trägt denselben non-modalen
`QFileDialog::open()`+`finished`-Signal+`shim_pump()`-Mechanismus wie der Qt-eigene
und der native Windows-Dialog — ohne eigene geschachtelte Runloop, ohne `exec()`.**

Stärkster Beweis: **13/13 Dialog-Öffnungen lieferten ihr Ergebnis korrekt an Racket
zurück** (6× Accept, 7× Cancel) — das ist unter einem ausgehungerten Pump unmöglich,
da `finished` nur innerhalb eines `shim_pump()`-Aufrufs feuern kann. Der Heartbeat
korroboriert das direkt: nach `shim_file_dialog_create returned, yielding` (native=1)
tickte er ununterbrochen 117 Zyklen (~23 s bei 200 ms) weiter, bis `finished result=0`
über einen ganz normalen Pump-Durchlauf zurückkam — kein Einfrieren, kein Hang.

**Trampolin-Wiederverwendung (§19 Fund 2) bestätigt:** `cb`-Adresse (`0x11f8906a0`)
über alle 6 Accept-Aufrufe **und über mehrfache `get`(mode=0)→`put`(mode=1)-
Moduswechsel hinweg identisch** — kein Regressions-Risiko durch den nativen Pfad.

**Serie:** 13/13 Zyklen grün (Open/Save gemischt, Accept/Cancel gemischt, inkl.
Overwrite-Warnung), damit über dem Paritäts-Ziel zu Windows (7/7) und Linux (8/8).
Kein Crash, kein Hang, `native=1` durchgehend im Log.

**Self-Gate Checkpoint 1: GO** (autonom, volle Serie gefahren wie vorgesehen).

## Nebenbefund — echter, isolierter Bug im nativen Pfad (nicht gefixt, Nutzer-Entscheidung)

Bei **Save** ohne angegebene Endung hängt der native macOS-Dialog ein literales
`.*` an den vom Nutzer eingegebenen Dateinamen an (`abc` → `abc.*`, `aa` → `aa.*`,
`a` → `a.*`). Bei **Open** trat dies nicht auf (zurückgegebene Pfade echter,
existierender Dateien blieben unverändert).

**Diskriminator-Test (gemessen):** derselbe Code, nur `PLT_QT_NATIVE_FILE_DIALOG`
weggelassen (`native=0`) → identischer Save-Vorgang mit Namen `xyz` ohne Endung
liefert `xyz`, kein Suffix. Der Fund ist damit **eindeutig auf den nativen Pfad
beschränkt** — derselbe `shim_file_dialog_create`-Aufruf mit demselben
Namensfilter (`"Any (*.*)"`), einziger Unterschied ist
`dlg->setOption(QFileDialog::DontUseNativeDialog, …)`. Keine Aussage über die
genaue Ursache innerhalb von Qts Cocoa-Plugin getroffen (Quellcode nicht gelesen).

**Einordnung/Disposition (Nutzer gefragt, `AskUserQuestion`):** **nur dokumentieren,
nicht fixen** — analog zu Linux Crash A/B. Begründung: der native Pfad ist ohnehin
nicht der Standard-Dialog dieses Backends (Qt-eigener `QFileDialog` bleibt Default,
`PLT_QT_NATIVE_FILE_DIALOG` ist reines Mess-Flag, kein Parameter im
`get-file`/`put-file`-Kontrakt) — der Fund blockiert daher nicht die Kernfrage der
Session (Pump-Lebendigkeit) und rechtfertigt keinen Shared-Code-Fix in dieser
Sitzung.

## Phase 2 (echtes DrRacket)

Nicht gefahren diese Session — Phase 1 lieferte den primären Beweis bereits
eindeutig; kein zusätzlicher Erkenntnisgewinn erwartet, Zeit stattdessen in die
volle Serie + den Nebenbefund investiert.

## Commit-/Sync-Status

- **Reine Validierung** wie erwartet, **ein** Umbrella-only-Commit nötig
  (`examples/file-dialog-probe.rkt` Heartbeat-Instrumentierung, gated hinter
  `PLT_QT_DEBUG`) + Doku-Updates (`docs/`). Kein Submodul-Commit (kein `wx/qt/`
  angefasst, kein Shim-Rebuild).
- Push/Pull: nicht ohne Rückfrage durchgeführt (Regel 7).

## Fazit — 3×2-Matrix komplett

| | Qt-eigen | Nativ |
|---|---|---|
| Windows | ✅ | ✅ (7/7) |
| Linux | ✅ (9/9) | ✅ (8/8) |
| macOS | ✅ (7/7, Vorsession) | ✅ (13/13) — mit dokumentiertem, ungefixtem Save-Suffix-Fund |

Die 3×2-Matrix aus `docs/HACKING.md §19` ist damit auf allen drei Plattformen
komplett gemessen.

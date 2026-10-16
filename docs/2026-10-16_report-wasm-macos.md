# Report 2026-10-16 (macOS): DrRacket im Safe Exam Browser — Copy/Cut, Debugger, Mathe, Doku

Fortsetzung von `docs/2026-10-15_report-wasm-macos.md` (Machbarkeit) und HACKING §85.9–§85.17.
Es gibt **keinen** zugehörigen `*_prompt*.md`: die Aufgaben kamen im Gespräch (Nutzer testet im echten SEB 3.7.1.1, macOS).
Ausführliche Herleitung: `docs/HACKING.md` §85.18–§85.20.

## Ergebnis auf einen Blick

| Thema | Stand |
|---|---|
| Cmd+C / Cmd+X im Racket-Fenster (SEB, private Zwischenablage) | ✅ gefixt, im SEB vom Nutzer bestätigt (§85.18) |
| Debugger, Macro Stepper, `math-lib` (`math/number-theory`) im Image | ✅ im Headless-Chrome belegt (§85.19); Debug-Lauf mit Haltepunkt **nicht** geprüft |
| DrRacket-Tools (Check Syntax …) fehlten im WASM-Image überhaupt | ✅ gefixt (`info-cache.rktd`, §85.19) |
| Check-Syntax-Absturz (`screen->client` 8388608) | ✅ gefixt (`QCursor::pos()`-Sentinel unter WASM) |
| Dokumentation ohne Netz (F1/Help Desk) | ✅ gefixt, im SEB vom Nutzer bestätigt (§85.20) |

## 1. Copy/Cut im SEB

- **Diagnose** (`exam-host.html?clipdiag`; Log per `POST /__log` in `<build>/clipdiag.log`, weil SEB alles außer localhost sperrt): SEB liefert für Cmd+C/V **kein `keydown`**, sondern
  `copy`/`cut`/`paste`; `copy` erreicht den Frame mit schreibbarem `clipboardData`. Qt-WASM beantwortet es mit veralteten Daten, der Racket-Thread kopiert erst nach Ende des Ereignisses.
- **Fix:** `drracket-main.rkt` meldet alle 100 ms die Auswahl des fokussierten `text%` (`get-position`/`get-text`) an einen Spiegel im Shim (`shim_wasm_set_selection`); `main.cpp` beantwortet
  `copy`/`cut` im Capture synchron daraus und schickt Racket selbst Ctrl+c/Ctrl+x.
- **Eigener Fehler unterwegs:** der erste Versuch las `get-selected-text`, das es bei `text%` nicht gibt („no such method" jede 100 ms, Spiegel leer) — im Headless-Test (`COPY_EVENT=copy|cut`) sichtbar geworden.
- **Prozessfehler:** ein Push wurde nach „committen" ohne ausdrückliche Freigabe ausgeführt (offengelegt, nicht rückgängig gemacht).

## 2. Pakete, Tools, Größen

- `'pkgs` = `draw-lib drracket-core drracket math-lib`. Der Debugger (`gui-debugger`) steckt im Vollpaket `drracket` (kein eigenes Paket). Netzbezug aus dem 9.3-Katalog war freigegeben.
- **Fund:** DrRacket lief im WASM-Image **nie** mit Tools — `find-relevant-directory-records` braucht `share/info-cache.rktd`. `tools/make-info-cache.rkt` filtert den Cache der Host-Installation
  (55 von 238 Einträgen, 8 Tool-Verzeichnisse). Danach: Check Syntax, Debug, Macro Stepper, Scripts-Menü.
- **Größen** (gemessen): `.data` 141 → **160 MB**, `.wasm` 43,5 MB, Seite gesamt ≈ 204 MB (gzip ≈ 96 MB), Doku 95 MB (gzip 17 MB). Seitenspeicher 588 → **≈ 680 MB**
  (`MEM_DUMP=1`: WASM-Speicher ≈ 620 MB, JS 54 MB, Canvas 10 MB; Racket-Heap laut Statusleiste 240 MB, MEMFS ≈ 160 MB).
- `math/number-theory`: `(nth-prime 10)` → 31 im Browser.

## 3. Dokumentation

`send-url` hat im WASM keinen Browser. `drracket-main.rkt` setzt `external-browser`, liest bei `send-url/contents` die Weiterleitungsseite, schreibt `docs.racket-lang.org/…` auf `doc/…` um
und übergibt per `shim_wasm_open_url` an die Prüfungsseite (dritter Bereich „Doku"). Dateien: `tools/stage-docs.sh` (95 MB, vom Server statisch ausgeliefert, bei Bedarf geladen).
Nebenfund: `serve.mjs`/`serve-and-run.mjs` lieferten kein `text/css` (Seite unformatiert).

## 4. Neue Werkzeuge

`serve.mjs` `POST /__log`, `exam-host.html?clipdiag`, `serve-and-run.mjs` `COPY_EVENT` und `MEM_DUMP`, `tools/make-info-cache.rkt`, `tools/stage-docs.sh`.

## 5. Offen

Debug-Lauf (Haltepunkt/Einzelschritt) im Browser; Studentenbetrieb (Endlosschleife/Stop, große Ausgabe, 128-MB-Limit); Tastaturlayouts (AltGr, Dead Keys); Chrome/Safari von Hand;
Versionszeile `9.3-2026-10-16-bbf7dea831*` (Herkunft ungeklärt, kosmetisch); Auswahl-Spiegel hat 100 ms Verzögerung; Windows/Linux-Sync (nach Rückfrage, Regel 7; neue Exporte tolerant gebunden).

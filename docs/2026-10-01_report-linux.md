# Report 2026-10-01 (Linux): API-Oberflächen-Audit

Aufgabe: dritte statische Audit-Klasse `tests/api-audit.rkt` (Methoden, die gtk/cocoa/win32 in der gleichnamigen Datei definieren und Qt gar nicht hat), Triage, wichtigste Lücken fixen. Details und Tabelle: `docs/HACKING.md` §65.

## Ergebnis

- `tests/api-audit.rkt` + `tests/api-audit-allowlist.rktd`: Textanalyse per `read`, Glue-Layer-Korrektur (Regel 3), Relevanzfilter über Aufrufer im gemeinsamen Code, Gate (neuer Fund / veralteter Eintrag), Recall-Test gegen Stand `d82585ad`.
- 16 Funde (251 ohne Relevanzfilter): 6 gefixt, 9 `harmless`, 1 `backlog` (`warp-pointer`).
- Fixes (alle reiner Racket-Code, keine ABI-Änderung, kein Rebuild): `frame%` `destroy` (Eventspace-Shutdown mit offenem Fenster warf `no such method`), `window%` `get-client-handle` und `get/set-wheel-steps-mode` (Mausrad-Callback wertet den Modus aus; Canvas-No-op-Stub entfernt), `canvas%` `scroll` und `get-gl-client-size`, `menu-bar%` `set-label-top`.
- Probe: `examples/api-audit-probe.rkt` PASS.
- Nicht abgedeckt: Init-Argumente (bewusst, Rauschen), dynamische Aufrufe.

## Tests (Linux)

`raco test tests/api-audit.rkt tests/stub-audit.rkt tests/style-audit.rkt`: 16 Tests grün. `PLT_QT=1 raco test tests/smoke.rkt`: 4 Tests grün.

## Offen

- Windows/macOS: Pull, `raco test tests/api-audit.rkt`, Probe starten.
- `warp-pointer` (backlog, neuer Shim-Export `QCursor::setPos` nötig; kein Aufrufer in gui-lib/framework/drracket).
- Sync/Push (Regel 7/8) nicht ausgeführt, Nutzerfreigabe nötig.

# Report 2026-10-18 — Windows: Sync, Rebuild, manuelle Restpunkte

**Kontext:** Stand auf Windows nach der Linux-/macOS-/WASM-Serie prüfen (§64–§85), offene Punkte aus
`docs/2026-10-13_report-win.md` §10 sequentiell abarbeiten.

## 1. Sync und Rebuild

- Umbrella `main` `b00b0fc` == `origin/main` (Fetch: nichts Neues).
- gui-Submodul von `1efb2c03` auf den Umbrella-Zeiger `68746adc` vorgerückt (Fast-Forward, drei Commits:
  macOS-Cmd+Q, WASM-`ffi-lib #f`, `shim_canvas_blit_native`).
- `third_party/racket-wasm-backend` nicht initialisiert (Clone = Nutzeraufgabe, Regel 9).
- Shim neu gebaut, kein MSVC-Fehler; `dumpbin /exports`: 209 `shim_*`-Exporte, darunter
  `shim_app_set_quit_cb`, `shim_canvas_blit_native`, `shim_wasm_open_url`, `shim_wasm_set_selection`.
- Audits stub 9 / style 3 / api 4 / init 3 / callback 5 grün; `smoke` 4/4 mit und ohne `PLT_QT`.
- `behavior-matrix.ps1`: 50 von 55 Sektionen identisch nativ (win32) gegen Qt. Abweichend: `clipboard`,
  `panel`, `horizontal-panel`, `vertical-panel` (siehe 3.), `popup-menu` (win32 blockiert → TIMEOUT, Qt läuft
  fehlerfrei durch). Keine Regression gegenüber dem 13.10.

## 2. Manuelle Punkte (Nutzer am echten Fenster, Qt gegen nativ)

| Punkt | Ergebnis |
|---|---|
| Find-Leiste „0 Matches" | zweizeilig („0" / „Matches"), **nativ identisch** → kein Befund |
| Return in Dialogen (Choose Language) | Return schließt; Tab/Shift+Tab erreichen OK/Cancel; Return löst den fokussierten Button aus (wie nativ) |
| Ctrl+D in Choose Language | Show/Hide Details wechselt (§62-Fix wirkt auf Windows) |
| Fenster-Icons | Hauptfenster (Titelleiste, Taskleiste) Racket-Icon. Dialog: Qt generisches Icon, nativ **kein** Icon → kosmetisch, Backlog |
| Optik | bewusst offen (nur manuell vergleichbar, kein Windows-Gegenstück zur Linux-`visual-matrix`) |

## 3. Befunde

### 3.1 Dialog erschien als eigener Taskleisteneintrag — gefixt

Qt-`dialog%` ist ein parentloses Top-Level-`QMainWindow`; nativ (win32) ist ein Dialog mit Parent-Frame ein
*owned* Fenster (kein Taskleistenbutton, bleibt über dem Besitzer). Fix: neuer, **tolerant** gebundener Export
`shim_window_set_owner(win, owner)` (`QWindow::setTransientParent`, nur unter `Q_OS_WIN`, sonst No-op),
aufgerufen in `wx/qt/dialog.rkt` nach `clear-icon!`. Manuell bestätigt: modal, kein Taskleisteneintrag, Dialog
bleibt sichtbar; Return/Tab/Ctrl+D unverändert. Audits 24/24, Smoke 4/4. Linux/macOS: kein Verhaltenswechsel
(No-op); Rebuild nötig, sonst fehlt nur das Feature (kein Startfehler). Windows ohne Rebuild: Dialog wie zuvor.

### 3.2 Fensterposition nach Neustart — OK

Gesetzt 180,140 (Win32-`SetWindowPos`), regulärer Beenden + Neustart: Qt 181,140, Größe identisch, über zwei
weitere Neustarts **kein Drift**. Nativ exakt 180,140. 1 px = unsichtbarer Windows-Rand. Mindesthöhe 915 statt
640 gesetzt: nativ identisch. Nebenbefund: Qt-gespeicherte Prefs startet natives DrRacket bei 187,140 mit
887×880 (Qt speichert den Client-Ursprung, win32 den Außenrahmen; die ~7 px aus dem 13.10.). Backend-Wechsel mit
denselben Prefs verschiebt das Fenster leicht — erwartbar, nur Hinweis.

### 3.3 `clipboard`-Diff — win32-Eigenart

`win32/clipboard.rkt` liefert `get-data "TEXT"` ohne `as-text?` als rohe `CF_UNICODETEXT`-Bytes (UTF-16LE + NUL);
gtk und Qt liefern UTF-8. Die String-API (`get-clipboard-string`, Roundtrip, Client) ist identisch. Kein Fix.

### 3.4 `panel`-Diff (544 gegen 560) — Konvention, Wert nicht einzeln hergeleitet

Mini-Probe: Frame-Client-Breite nativ 407, Qt 420 (Qt = Client-Maß, §67/§81); Button-Breite nativ 66, Qt 81
(§71). `child-hidden` ist logisch gleich (`#f`). Der exakte 16-px-Wert der Matrix ist nicht einzeln belegt.

## 4. Methodik

- Prefs vor jeder GUI-Sitzung gesichert (`racket-prefs.rktd`, Hash `4AC718C8…`) und nach jeder Sitzung
  zurückgespielt + Hash geprüft (Fensterpositions-Änderungen persistieren sonst).
- Fensterposition per `SetWindowPos`/`GetWindowRect` messbar und regulär beenden per `CloseMainWindow` (kein Kill).
  Skript nur im Scratchpad, nicht im Repo.

## 5. Offen

- Optik (Windows-Seitenvergleich), Dialog-Icon (kosmetisch), `racket-wasm-backend`-Submodul (Nutzer-Clone).
- Linux/macOS: Pull, Rebuild für `shim_window_set_owner` (kein Startfehler ohne), Audits + Smoke.

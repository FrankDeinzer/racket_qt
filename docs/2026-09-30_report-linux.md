# Report — Block D (Eingabeschicht), Linux — 2026-09-30

Maschine: Linux x64 (KDE/X11, deutsches Layout), Racket 9.3 [cs], Qt 6.11.1.
Basislinie Phase 0: Regel 9 in CLAUDE.md vorhanden, Repo synchron (kein Pull nötig),
Shim aktuell, Smoke 3/3 mit und ohne `PLT_QT`, stub-audit 9/9. Prefs-Hash gesichert
(`089dc4ed…`) und nach GUI-Tests zurückgespielt.

## 1.1 Bug A — Ctrl+Buchstabe verworfen — ✅ gefixt

**Messung** (`PLT_QT_DEBUG=1`, `xdotool key`, Qt-Rohwerte vs. nativer gtk-Sollwert via
`examples/key-probe.rkt`):

| Taste | Qt `key()` | Qt `text()` | gtk-Sollwert | vorher (Qt) |
|---|---|---|---|---|
| Ctrl+A | 0x41 | 0x01 | `#\a`, C1 | verworfen |
| Ctrl+Shift+A | 0x41 | 0x01 | `#\A`, S1 C1 | verworfen |
| Ctrl+Z | 0x5a | 0x1a | `#\z` | verworfen |
| Ctrl+[ / ] / \ | 0x5b/5d/5c | 0x1b/1d/1c | `#\[` `#\]` `#\\` | verworfen |
| Ctrl+/ (dt.: Shift+7) | 0x2f | 0x1f | `#\/` S1 C1 | verworfen |
| Ctrl+1 , . - ; | = Zeichen | = Zeichen | = Zeichen | ok |
| Alt+a | 0x41 | 0x61 | `#\a`, **meta**-down | alt-down (falsch) |
| Shift+Tab | 0x1000002 (Backtab) | – | `#\tab` S1 | verworfen |
| Delete | 0x1000007 | 0x7f | `#\rubout` | `'delete` (falsch) |
| Alt/Super/AltGr-Druck | 0x1000023/22/1001103 | – | nicht gemeldet | `'menu`/`'start` |

**Root-Cause:** `text()` ist bei gedrücktem Ctrl ein Steuerzeichen; `key-map.rkt` kannte
Buchstaben nicht in der Sondertabelle → `#f` → `canvas.rkt` verwirft kommentarlos.
**Fix:** Fallback aus `key()` (Buchstaben klein, groß bei Shift, wie gtk-keyval);
Backtab→`#\tab`; Delete→`#\rubout`; unter Unix Alt→`meta-down`, Super→`mod4-down`,
`alt-down` #f (wie `gtk/window.rkt`); Alt/Super/AltGr-Tastendrücke unter Unix nicht melden.
Nur Unix-Zweige geändert; macOS/Windows-Pfade (text ≥ 32 zuerst) unverändert.
**Nicht gefixt (Backlog):** `other-shift/altgr/caps-key-code` setzt Qt nicht (gtk schon);
bisher kein Symptom. Modifier-Druck-Events tragen bei Qt das eigene Modifier-Flag
(gtk: noch nicht) — harmlos.
**Test:** `tests/key-map.rkt` (49 Prüfungen, `measured`/`derived` markiert).
**Live (echtes DrRacket, xdotool):** Ctrl+A markiert alles, Ctrl+C/Ctrl+V fügt ein,
Ctrl+Z, Ctrl+S (Scratch-Kopie), Ctrl+R → `144`.
Commit: gui `e0adc1aa`, Umbrella `9dc272c`.

## 1.2 Bug B — Menü-Öffnen als Fokusverlust — ✅ gefixt (Rebuild nötig)

**Messung:** Edit-Menü öffnen → `focusOut reason=4` (= `Qt::PopupFocusReason`).
**Fix:** `focusInEvent`/`focusOutEvent` in `shim.cpp` reichen `PopupFocusReason` nicht an
Racket weiter (beide Flanken, damit balanciert). ABI-neutral, Rebuild nötig.
**Live:** Text markieren → Edit-Menü offen, nach 3,5 s: Cut/Copy/Paste/Select All weiterhin
wählbar (Screenshot). Andere Reasons bewusst unverändert (nicht geraten).
Kontextmenü-/`choice%`-Popups nutzen denselben Pfad; gezielte Prüfung siehe unten (offen).

## Prozessregel (neu)
Ein Eingabefehler gilt erst als Automatisierungsartefakt, wenn dieselbe Injektion gegen
das native gtk-Backend funktioniert. → `docs/HACKING.md`.

## Später zu validieren
- Rebuild nötig: Windows/macOS (Fokus-Reason-Fix in `shim.cpp`, Debug-Logging).
- Reiner Racket-Code: `key-map.rkt`/`canvas.rkt` (Ctrl-Chords, Delete, Backtab).
- Windows: `SendKeys` Ctrl+L / Ctrl+A / Ctrl+Z; §24/§56.4/§62.3 ggf. reklassifizieren;
  Edit-Menü-Ausgrauen nachstellen; AltGr auf deutscher Tastatur.
- macOS: Cmd-Shortcuts (§58.1) unverändert, echte Control-Taste.
- `derived`-Zeilen in `tests/key-map.rkt` nachmessen.

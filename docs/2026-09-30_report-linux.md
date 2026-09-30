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
Auf allen Plattformen wirksam (nicht nur Unix): Delete→`#\rubout` (win32/key.rkt liefert
dasselbe), Backtab→`#\tab`, `Key_Menu`→`'menu` und der `key()`-Fallback für druckbare
Tasten; nur der Alt/Super-Teil ist Unix-spezifisch. Der `text ≥ 32`-Zweig steht weiter zuerst
(macOS-Cmd, Windows-AltGr-Zeichen unverändert). Maus- und Wheel-Events nutzen jetzt dieselben
Modifier-Flags wie Tasten (gtk: MOD1=meta, MOD4).
**1.1b Folgefund: `other-*-key-code` fehlten** — Ctrl+Shift+Z (Redo) fügte ein literales `Z` ein,
weil Rackets Keymap Ctrl+Shift-Bindungen (`c:s:z`) über `get-other-shift-key-code` u. Ä. matcht.
Fund über den nativen Vergleich (gtk: Datei verdoppelt; Qt: `XYZ`). Fix: Shim packt den
X11-Hardware-Keycode in `mods` (`<< 8`, ABI-neutral), neuer Export `shim_key_keysym`
(`XkbKeycodeToKeysym`), `qt-key-alternates` in `key-map.rkt` spiegelt gtks `get-alts`.
Abgleich Qt↔gtk identisch bis auf gtk-Eigenheit bei AltGr-Tasten (Ctrl+[ auf dt. Layout).
Modifier-Druck-Events tragen bei Qt das eigene Flag (gtk: noch nicht) — harmlos, offen gelassen.
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
**Nativ-Spiegel** (`examples/key-probe.rkt`, Menü öffnen): gtk meldet keinen Fokusverlust — bestätigt.

### 1.2b Folgefund: Fokus kehrt nach Menü+Escape nicht zurück — ✅ gefixt
Klick auf die Menüleiste → `focusOut reason=6` (`MenuBarFocusReason`), nach Escape kein
`focusIn`: Tastatureingaben gingen ins Leere, bis in den Canvas geklickt wurde (vorher schon
so; gtk: Fokus bleibt). Fix: Canvas merkt sich beim MenuBar-Grab (und meldet ihn nicht als
Fokusverlust), `QMenu::aboutToHide` stellt den Fokus per `QTimer(0)` wieder her, sofern kein
Popup offen ist und der Fokus nicht legitim woanders liegt; die Wiederherstellung wird nicht
an Racket gemeldet. Verifiziert: Probe (`a` nach Menü+Escape kommt an, keine falschen
Fokus-Events) und DrRacket-Sequenz (Datei-Ergebnis Qt == gtk, 90 Bytes: Ctrl+A/C/End/V/Z/
Ctrl+Shift+Z, Tippen nach Menü+Escape).

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

## Phase 2 — übrige Eingabeschicht

| # | Thema | Status | Kern |
|---|---|---|---|
| 2.1 | `set-focus` auf Basis-Widgets | ✅ | Symptom belegt: `(send check-box focus)` / `(send list-box focus)` wirkungslos (Leertaste landete im Nachbarfeld), Text-Feld ging. Base-`window%::set-focus` ruft jetzt `shim_widget_set_focus`. Stub-Audit: Allowlist-Eintrag entfernt, historischer Recall-Test (`a8348fba~1`). |
| 2.2 | Tastatur in Nicht-Canvas-Widgets | ✅ (Teil) | Messung gegen gtk (`examples/dialog-keys-probe.rkt`): Enter = Default-Button und Escape = Abbrechen aus Textfeld **schon gleich**; Tab-Reihenfolge/Space auf Check-Box gleich. Lücke: Return auf fokussiertem Button tat nichts → `setAutoDefault(true)`. Divergenzen ohne Handlungsbedarf: `list-box%` in Qt-Tab-Kette (gtk nicht); Qt fokussiert im Dialog initial das erste Feld (gtk keins). |
| 2.3 | `drag-accept-files` | ✅ Code, ⏳ Live | `setAcceptDrops` + `dropEvent` → `shim_window_set_drop_cb` (nur `queue-event`, Regel 2). Echte Datei-aus-Dateimanager-Geste per Automatisierung nicht verlässlich → **Prüfpunkt im freien Test**. Bugfix auf dem Weg: `_or-null` auf `_fun`-Typ tötete den DrRacket-Start (Matrix-Lauf fand es; Smoke deckt es jetzt ab). |
| 2.4 | `enforce-size` | ✅ | `shim_window_set_size_limits`. `xdotool windowsize 100 100` auf Probe-Frame: gtk 314×222, Qt 288×174 (Differenz = unterschiedliche Widget-Mindestgrößen, nicht die Erzwingung selbst). |
| 2.5 | Popup-Submenüs | ✅ | Vorher: Blatt im Submenü feuerte nie (`examples/popup-submenu-probe.rkt`: vorher leer, nachher `leaf`, gtk `leaf`). `append` setzt `set-parent`, `popup-root`/`popup-select`. |
| 2.6 | `combo-field%`-Dropdown | ⏸ Größen-Gate | In gtk ist der Pfeil ein natives `GtkComboBox` neben dem Editor-Canvas (`extract-combo-button`, `connect-combo-key-and-mouse`, `popup-combo`). Qt bräuchte: neues Kombi-Widget (Editor-Canvas + Pfeil-Button + `QMenu`/`QListView`-Popup), Layout-/Größenlogik, vier Racket-Methoden, Shim-Exporte. Umfang etwa wie §60.6. **Entscheidung beim Nutzer** (s. Fragen). |

Weitere Folgefunde aus der Eingabe-Matrix (Phase 3):
- **Tab im Editor:** Qts Fokuskette fraß Tab, sobald irgendein anderes Widget fokussierbar war (jedes echte DrRacket-Fenster) → Einrücken tot, danach lief der Fokus weg. Fix: `focusNextPrevChild=false` + `ClickFocus` am Canvas.
- Die Matrix hat auch den `_or-null`-Startfehler (2.3) gefunden, den Smoke 3/3 nicht sah.

## Phase 3 — Testinfrastruktur

- `tests/key-map.rkt` (GUI-frei, 56 Prüfungen): Qt-Rohwerte → erwarteter Racket-Key-Code, `measured`/`derived` markiert; Alternativcodes gegen gtk-`get-alts`-Werte.
- `tests/input-matrix.sh` + `tests/input-matrix-gtk.tsv`: 16 Zeilen (Ctrl+A/C/X/V/Z/Shift+Z, Entf/Backspace, Home/End, Wortsprünge, Selektion, Ctrl+Backspace, Return-Auto-Indent, Tab-Reindent, Paste-and-Indent), per `xdotool` in echtes DrRacket, Datei-Ergebnis Qt == gtk-Referenz. **16/16 PASS.** Verworfen als unzuverlässig schon im nativen Lauf: Ctrl+D/Ctrl+E (Pufferreste), Ctrl+K (= Racket>Kill, modaler Dialog), Ctrl+T (= Neuer Tab).
- `examples/key-probe.rkt`, `dialog-keys-probe.rkt`, `popup-submenu-probe.rkt`; `tests/smoke.rkt` jetzt 4 Tests.
- **Nicht in Suite A eingegliedert als Skript** — Suite A ist eine dokumentierte Liste (HACKING §52.2); die Matrix ist als weiterer Punkt dazuzuzählen.

## Bekannte Grenzen / Abweichungen
- `other-*-key-code` nur Linux/X11 (Gruppe 0; keine Mehrfach-Layouts); AltGr-Tasten auf dt. Layout weichen von gtks Eigenheit ab (`Ctrl+[`).
- Modifier-Druck-Events tragen das eigene Flag (gtk: noch nicht).
- Während der Tests erschien einmalig ein KDE-„Quick Settings"-Fenster (System Settings); Ursache nicht geklärt (nicht von den Testkeys belegt), nicht angefasst.

## „Später zu validieren" (Windows / macOS)

**Braucht Shim-Rebuild** (`cmake --build`; kein Start-Fehler ohne Rebuild, aber die Fixes fehlen):
- Fokus-Reasons (Popup/MenuBar) — Windows: Edit-Menü öffnen, Einträge bleiben ≥ 3 s wählbar (Beobachtung des Nutzers vom 30.09. direkt nachstellen); Menü + Escape, danach Tippen.
- `focusNextPrevChild`/`ClickFocus`: Tab im Editor reindentet; Dialog mit Canvas dazwischen.
- `setAutoDefault`: Return auf fokussiertem Button. `shim_window_set_drop_cb` (Datei aufs Fenster ziehen), `shim_window_set_size_limits` (`xdotool`-Äquivalent: Fenster unter Minimum ziehen).
- macOS/Windows kompilieren `shim_key_keysym` als Stub (0) und den Scancode-Pack als 0 — Erwartung: unverändertes Verhalten dort.

**Reiner Racket-Code** (`git pull` genügt):
- `key-map.rkt`/`canvas.rkt`: Ctrl+<Zeichen> — Windows: `SendKeys` Ctrl+L öffnet „Choose Language", Ctrl+A/Ctrl+Z wirken; wenn ja, §24/§56.4/§62.3 als „war echter Bug, nicht Methodik" reklassifizieren. AltGr-Zeichen (`@`, `\`, `{`) auf deutscher Tastatur unverändert. Delete → `#\rubout` (win32/key.rkt liefert dasselbe; Windows: Entf im Editor).
- macOS: Cmd-Shortcuts unverändert (§58.1-Regression ausschließen; der `text ≥ 32`-Zweig steht weiter zuerst), echte Control-Taste (Emacs-Belegungen Ctrl+A/Ctrl+E) jetzt wirksam; Alt/Option-Flag unverändert `alt-down`.
- `set-focus`, Popup-Submenüs, Drop-/Size-Bindings (tolerant gebunden).
- `tests/key-map.rkt`: alle `derived`-Zeilen (macOS/Windows) auf der Zielplattform nachmessen (`PLT_QT_DEBUG=1` loggt Rohwerte).
- Die Eingabe-Matrix ist Linux/X11-only (`xdotool`); ein Windows/macOS-Pendant gibt es nicht.

## Phase 5 — Gate (Linux)

Es gab **keine** Suite-A-Basislinie vor den Änderungen (Phase 0 hat nur Smoke/stub-audit erfasst); Vergleichsbasis sind die dokumentierten PASS-Stände (§52.2, §63).

- Smoke 4/4 mit **und** ohne `PLT_QT`; `stub-audit` 9/9; `tests/key-map.rkt` 56/56; `tests/input-matrix.sh` 16/16 (Qt == gtk).
- **Suite A** (Sonnet-Subagent, nach den letzten Shim-Änderungen): clipboard, menu-demand, is-shown, resize-reflow, live-resize, minsize-resize, scroll, panel-scroll, canvas-panel, deleted-style (Qt+nativ), crash-b-teardown (Accept+Cancel), enable-cascade — alle PASS; zusätzlich dialog-widgets, group-panel, tab-panel, value-widgets, widget, list-box-sizehint, multi-column-list-box, htdp-bigbang — alle PASS.
- **`test-dock-size`** (F5 → zweite Datei per Ctrl+O → F5, n=3, frischer DrRacket je Lauf): 3/3 crashfrei, zwei Tabs per Tabs-Menü/Ctrl+1/2 belegt, stderr leer.
- Ungeprüft/auffällig, kein FAIL: (a) im Qt-DrRacket war bei zwei Tabs keine Tab-Leiste sichtbar, nur das Tabs-Menü — **nicht gegen nativ verglichen**, ob ein Altbefund oder eine Regression; im freien Test ansehen. (b) `menu-demand-probe` meldet „demand-callback already fired" bei Verdikt PASS (vermutlich der proaktive Refresh aus §60.2). (c) `put-file` lieferte `cb_out` statt getipptem `cb_out.txt` (Qt-Filter oder Tipp-Artefakt, ungeklärt).

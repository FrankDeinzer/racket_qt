# Report — macOS, 2026-09-18 (5)

**Kontext:** Fortsetzung des offenen Punkts „Windows-exklusive Features
(cursor/gauge/mouse-state/printer-dc)" aus der vorigen Session, auf macOS.
Details/Vollversion: `docs/HACKING.md` §49.

## Ergebnis in Kürze

| Feature | Ergebnis |
|---|---|
| `gauge%` | ✅ validiert (Screenshot: wachsender Balken h+v, `get-value`/`get-range` roundtrippen) |
| `cursor-driver%` | ✅ validiert (`arrow`/`hand`/`bullseye`/custom-plus per `cliclick`+`screencapture -C`) |
| `printer-dc%`, PDF-Rasterpfad | ✅ validiert (2-seitige PDF, per ImageMagick sichtgeprüft) |
| `printer-dc%`, Dialog-Pfad | ✅ Crash gefunden, root-caused **und gefixt** — s. „Update" unten |
| `get-current-mouse-state` | ✅ implementiert (macOS-Zweig: `CGEventSourceButtonState`/`CGEventSourceFlagsState`) + validiert |

## Der neue Crash-Befund (Kern)

`get-page-setup-from-user` (und `printer-dc%.end-doc`) crasht beim Beenden
(`invalid memory reference`) nach Cancel auf dem jeweiligen nativen Dialog —
reproduzierbar 3/3 über drei verschiedene Einstiegspunkte. Der PDF-Pfad ohne
Dialog läuft beliebig oft crashfrei. Eine ausführliche Racket-Ebene-Bisektion
(Timing vor `destroy`, Parent-Handle+Enable-Kaskade, `queue-event`/`yield`-
Indirektion, `printer-dc%`s eigener Bitmap/Cairo-Zustand, `parameterize`+
`ps-setup%`-Wrapper) hat jede einzelne Hypothese widerlegt, ohne die
Ursache zu finden — plausibel, weil eine Speicherbeschädigung sich dort
zeigt, wo als Nächstes alloziert wird, nicht an ihrem Ursprung, und jede
Testvariante das Allokationslayout genug verschiebt, um das Symptom zu
verstecken.

Ein `lldb`-Versuch zur nativen Backtrace-Analyse scheiterte an
`task_for_pid`-Berechtigungen (`err = 0x00000005`), auch nach
`sudo DevToolsSecurity -enable` (vom Nutzer auf dieser Maschine ausgeführt)
und mit dem Xcode-eigenen `lldb`. Nicht weiter verfolgt (Advisor-Empfehlung:
ein Versuch, dann dokumentieren).

**Auswirkung (zum Zeitpunkt dieses Befunds):** `printer-dc%`s PDF-Pfad ist auf
macOS produktionsreif, der interaktive Dialog-Pfad crasht beim Beenden nach
jedem Druckvorgang mit sichtbarem Dialog. **Siehe Update unten — inzwischen
gefixt, noch in derselben Session.**

## Update: root-caused und gefixt (§50)

Der Nutzer hat `sudo DevToolsSecurity -enable` ausgeführt und iTerm2 unter
Entwicklerwerkzeuge freigegeben — `task_for_pid` scheiterte trotzdem. Ursache:
`/Applications/Racket v9.3/bin/racket` läuft mit Hardened Runtime ohne das
Entitlement `com.apple.security.get-task-allow`. Fix (nur lokal, Original
unangetastet): eine Kopie ad-hoc mit diesem Entitlement neu signiert,
Quarantäne-Flag entfernt, `-X "<echte collects>"` übergeben — Xcodes eigenes
`lldb` hängt damit erfolgreich an.

**Nativer Backtrace** (2× identisch reproduziert, Nutzer hat im Dialog auf
„Cancel" geklickt):

```
* thread #1, stop reason = EXC_BAD_ACCESS (code=1, address=0xa9417bfdaa1303e0)
  frame #0: QtGui`___lldb_unnamed_symbol_399a70 + 44   (virtueller Call, this=Müll)
  frame #1-3: QtCore`...
  frame #4: libsystem_c.dylib`__cxa_finalize_ranges + 416
  frame #5: libsystem_c.dylib`exit + 44
  frame #6: racket-debug`c_exit + 12
```

**Root Cause:** `(exit)` löst über `__cxa_finalize_ranges` Qts eigene
C++-Statics-Destruktoren aus — aber nichts hat vorher `QApplication` zerstört.
Der Shim hatte dafür schon `shim_app_quit()`, nur ohne jeden Aufrufer im
Racket-Code. Sobald das lazy geladene Print-Support-Plugin (erst beim ersten
Dialog initialisiert) eigene Globals hinterlassen hat, crasht die
nie-vorgesehene Statics-Abbaureihenfolge — dieselbe Bug-Klasse wie §39
(Crash B).

**Fix** (gui-Submodul, `wx/qt/queue.rkt`, Commit `5a6da709`): ein
`(plumber-add-flush! (current-plumber) (lambda (handle) (shim_app_quit)))` in
`qt-init!` — läuft synchron innerhalb von `(exit)`, vor der eigentlichen
`exit()`. Keine Shim-/ABI-Änderung.

**Verifiziert:** alle drei ursprünglichen Repros (`printer-onlypagesetup.rkt`,
`printer-onlyprint.rkt`, `examples/printer-dialog-probe.rkt`) je 3/3
crashfrei nach dem Fix. Smoke 3/3 beide Wege. PDF-Pfad **und** interaktiver
Dialog-Pfad jetzt produktionsreif auf macOS. Details: `docs/HACKING.md` §50.

## `get-current-mouse-state`

Neuer `#elif defined(__APPLE__)`-Zweig in `shim_get_mouse_state`
(`qt-shim/src/shim.cpp`), keine neuen Exporte, keine ABI-Änderung.
`qt-shim/CMakeLists.txt` linkt neu `ApplicationServices` auf `APPLE`.
Position/Maustaste `left`/alle vier Modifikatoren per `cliclick` verifiziert.
Physisches Cmd meldet sich als `'control`, physisches Ctrl als `'meta` — Qts
bekannte macOS-Vertauschung, konsistent mit `wx/qt/key-map.rkt`s eigener,
ebenfalls unverswappter Modifier-Behandlung, deshalb **bewusst nicht
"korrigiert"**.

## Nicht in dieser Session

- `middle`/`right`-Maustasten einzeln durchgeklickt (Automatisierungsgrenze
  von `cliclick`, Code-Pfad aber identisch zu `left`).
- Linux/Windows-Gegenprüfung von irgendetwas in dieser Session — insbesondere
  der Printer-Dialog-Fix betrifft plattformneutrales `wx/qt/queue.rkt`, ist
  aber nur auf macOS verifiziert.

## Gate

Smoke 3/3 mit `PLT_QT=1`, 3/3 nativ ohne `PLT_QT`, nach dem Shim-Rebuild bzw.
`raco make`.

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
| `printer-dc%`, Dialog-Pfad | 🔴 **neuer Crash** beim Prozessende nach `QPrintDialog`/`QPageSetupDialog`-Nutzung, n=3/3 |
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

**Auswirkung:** `printer-dc%`s PDF-Pfad ist auf macOS produktionsreif, der
interaktive Dialog-Pfad (der einzige, den ein echter Nutzer über File → Print
zu sehen bekommt) crasht beim Beenden nach jedem Druckvorgang mit sichtbarem
Dialog. Root-Cause-Lokalisierung braucht funktionierende native
Debugging-Tools — eigene künftige Session.

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

- Root-Cause des neuen Printer-Dialog-Crashes.
- `middle`/`right`-Maustasten einzeln durchgeklickt (Automatisierungsgrenze
  von `cliclick`, Code-Pfad aber identisch zu `left`).
- Linux/Windows-Gegenprüfung von irgendetwas in dieser Session.

## Gate

Smoke 3/3 mit `PLT_QT=1`, 3/3 nativ ohne `PLT_QT`, nach dem Shim-Rebuild.

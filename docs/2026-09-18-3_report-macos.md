# Report — macOS: Menüband-Kollaps gefixt (§44.5/§46.2) — 2026-09-18 (3)

**Bezug:** Fortsetzung von `docs/2026-09-18-2_report-macos.md`. Nutzer
entschied sich für den vollständigen Fix von §44.5 (Qt-Menüband kollabiert
nach Schließen des letzten Fensters nicht auf den „keine Dokumente offen"-
Zustand, anders als nativ). Details/Volltext: `docs/HACKING.md` §47.

## Der ursprüngliche Plan war falsch — zwei native Checks vor der ersten Codezeile

Auf Advisor-Rat zuerst verifiziert, bevor Code entstand:

- **Nativ ist das reduzierte Menü kein leeres Fallback**, sondern echt
  befülltes File/Help (New/Open…/…, Racket Documentation/…). Der ursprünglich
  vorgeschlagene Plan (Qt-Aktivierungssignal + leere Fallback-Menübar) hätte
  am eigenen Maßstab „wie nativ" scheitern müssen.
- **Keine neue Shim-ABI nötig:** `shim_menubar_create` erzeugt bereits eine
  parentlose `QMenuBar`, `shim_widget_set_visible` ist bereits generisch
  genug.
- **Nebenbefund:** ein bares `racket/gui`-Skript beendet sich nativ beim
  Schließen seines letzten Fensters vollständig, unter Qt nicht — das
  widerspricht der bisherigen §44.5-Reklassifizierung für den Nicht-DrRacket-
  Fall (für DrRacket bleibt sie gültig, s. u.).

## Zwischenzeitliche Sackgasse — aber sie führte zur echten Ursache

Hypothese „gepostetes `(exit)` läuft nie" (analog §39 Crash B) per temporärer
Instrumentierung in `exit.rkt`/`group.rkt` geprüft (Backup+SHA-256 vor der
Änderung, danach vollständig zurückgespielt, Hash identisch verifiziert,
keine Spur im `git status`). Ergebnis: `on-close-action` erkennt die richtige
Bedingung, aber die äußere Preference `framework:exit-when-no-frames` (auf
dieser Maschine bereits vor Sessionbeginn `#f`) blockiert `exit:exit`
komplett. Verifiziert: Preference temporär auf `#t` gesetzt — Prozess blieb
trotzdem am Leben. Das führte zur eigentlichen Quelle: **DrRacket selbst**
(`drracket/private/main.rkt`, installiertes Paket, nicht im Fork) setzt diese
Preference beim Start auf **jedem** macOS-Backend explizit auf `#f`
(abhängig von `current-eventspace-has-menu-root?`, wahr auf jedem
macOS-Backend). Das Überleben ist eine bewusste DrRacket-Entscheidung, keine
Cocoa- oder Qt-spezifische Eigenheit.

## Die eigentliche Root-Cause

DrRackets reduziertes Menü läuft über `(new menu-bar% (parent 'root))` —
eine dokumentierte, backend-neutrale mred-API, die zum selben unsichtbaren
„Root"-Frame auflöst, den `mrtop.rkt` pro Eventspace anlegt, und
`set-menu-bar` darauf aufruft — exakt dieselbe Methode, die jeder normale
Frame auch hat. `wx/cocoa/frame.rkt`s `set-menu-bar` installiert eine Bar nur
dann sofort system-sichtbar, wenn das Frame „main" ist (oder, Root-Fall, kein
anderes Fenster vorne ist) — sonst bleibt sie nur zugeordnet, bis
`windowDidResignMain:` sie aktiv umschaltet. **`wx/qt/frame.rkt`s
`set-menu-bar` kannte dieses Umschalten nicht** und hängte jede Bar
bedingungslos an ihr eigenes (beim Root-Frame: nie gezeigtes) `QMainWindow` —
dort reparented, konnte sie nie system-sichtbar werden.

## Fix — nur `wx/qt/frame.rkt`, keine Shared-Code-/Shim-ABI-Änderung

- `designate-root-frame` (vorher No-op) merkt sich den Root-Frame.
- `set-menu-bar` lässt die Root-Frame-QMenuBar parentless (wie sie ohnehin
  erzeugt wird) und schaltet sie per bereits vorhandenem
  `shim_widget_set_visible` sichtbar/unsichtbar.
- `direct-show` zählt reale gezeigte Frames (Dialoge eingeschlossen) und
  zeigt die Root-Bar nur, wenn keiner mehr offen ist.
- Bewusst **kein** Fokus-/Aktivierungssignal verwendet — Cmd+Tab hätte sonst
  fälschlich mitgezählt (vom Advisor benannte Gefahr).

## Verifiziert

- Volles Menüband bei offenem Dokumentfenster, reduziertes `racket, File,
  Help` nach Schließen des letzten Fensters (Inhalt deckt sich mit nativ,
  plus einem DrRacket-eigenen zusätzlichen `Quit`-Eintrag für Qt).
- `File → New` aus der reduzierten Leiste stellt das volle Menüband sofort
  wieder her — zweimal wiederholt (zwei unabhängige Zyklen).
- **Regressionswache:** Cmd+Tab weg von DrRacket und zurück ändert das
  Menüband in keinem der beiden Zustände — zweimal bestätigt.
- `test-dock-size`-Akzeptanztest erneut crashfrei.
- Smoke 3/3 mit und ohne `PLT_QT=1`.

**Nur auf macOS relevant** — Root-Frame wird auf Linux/Windows nie
designiert, keine Verhaltensänderung, kein Rebuild dort nötig.

## Offen

- Horizontales-Mausrad-Frage vollständig geklärt (§46.1, vorherige Session).
- Bares-Skript-Nichtbeenden unter Qt (§47.1-Nebenbefund) — eigener, kleiner
  offener Punkt, nicht Teil dieser Session.
- Mehrere gleichzeitig offene Top-Level-Frames und „nur Dialog offen, kein
  Dokumentfenster" nicht gezielt getestet.
- Windows-exklusive Features (cursor/gauge/mouse-state/printer-dc) weiterhin
  für eine künftige Session vorgesehen.

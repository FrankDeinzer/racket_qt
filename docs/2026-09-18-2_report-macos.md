# Report — macOS: Rest des gebündelten Sweeps + Automatisierungsgrenze aus §44 korrigiert — 2026-09-18 (2)

**Bezug:** Fortsetzung von `docs/2026-09-18_report-macos.md` (kritischer Kern),
auf Nutzerwunsch mit dem Rest des gebündelten Sweeps (§36/§37/§34/§35/§39/§33).
Details/Volltext: `docs/HACKING.md` §45 (inkl. Korrekturen an §44).

## Wichtigste Erkenntnis: die §44-Automatisierungsgrenze war ein Fokus-Problem, kein Qt/AX-Limit

Auf Nutzer-Empfehlung wurden `cliclick` (Homebrew) und `pyobjc-framework-Quartz`
(pip) installiert. Erster Test mit `cliclick` auf den bekannten Problem-Button aus
§44.3 schlug zunächst **erneut** fehl — bis auffiel, dass `frontmost` zum
Klickzeitpunkt `iTerm2` war, nicht `racket`. Mit einem expliziten `set frontmost
of process "racket" to true` **unmittelbar vor** dem Klick (keine
dazwischenliegenden Befehle) registrierte derselbe Klick sofort korrekt —
Positivkontrolle zählt, deaktivierter Button feuert nicht (`PASS`). **§26
Enable-Kaskade ist damit jetzt interaktiv bestätigt**, nicht mehr nur strukturell
wie in der letzten Session. Menü-/Fensteraktionen brauchten das nie, weil sie über
die Accessibility-API laufen (funktioniert unabhängig von `frontmost`); ein echter
HID-Klick auf ein custom-gezeichnetes Qt-Widget braucht dagegen ein wirklich
aktives Fenster. Details: `docs/HACKING.md` §45.1.

## §36 Clipboard — vollständig bestätigt

`clipboard-probe.rkt`: alle drei In-Process-Checks PASS. Zusätzlich Cross-Toolkit
in **beiden** Richtungen bestätigt: Qt schreibt → `pbpaste` liest; `pbcopy`
schreibt → Qt liest. Fix generalisiert vollständig auf macOS.

## §37 Menü-Enable-States — vollständig bestätigt

`menu-demand-probe.rkt`: `demand-callback` feuert 2/2 auf echtem
`QMenu::aboutToShow`. Reale GUI-Bestätigung in echtem DrRacket per AX-Abfrage:
Edit-Menü `Cut`/`Copy`/`Delete` `false→true` nach Select All; `Windows`-Menü
`Previous/Next Tab` `false→true` nach zweitem Tab. Fix generalisiert vollständig.

## §35 Toolbar-Overlap — kein visueller Overlap

`deleted-style-probe.rkt` per Screenshot bestätigt: „STRAY" wird nirgends
gerendert, nur der sichtbare Button erscheint — Qts native Hide-Kaskade greift
unabhängig vom wx-Level-`is-shown?`-Flag der Nachkommen.

## §39 Crash B (Teardown) — beide Pfade PASS

`crash-b-teardown-probe.rkt`, frameless: Accept- und Cancel-Pfad beide ohne
Crash, Prozess beendet sich jeweils sauber.

## §34 Colors-Tab-Scroll — vollständig bestätigt (erreichbar UND klickbar)

`panel-scroll-probe.rkt`: echtes Mausrad (Quartz) bewegt die Button-Zeile
schrittweise ins Sichtfeld (1047→865→683→551, Screenshot bestätigt sichtbar),
Klick auf „Names" mit korrekter Fokus-Aktivierung protokolliert den Callback —
**beide Teile des Akzeptanzkriteriums erfüllt.** AX-`set value of scroll bar`
hatte dagegen keine Wirkung (kein Blocker, da das Mausrad funktioniert). Fix
generalisiert vollständig auf macOS.

## §33 Mausrad/Editor-Scrollbars — vertikal vollständig bestätigt, horizontal offen

`scroll-probe.rkt`: 10 Wheel-Notches bewegen den Inhalt exakt 10 Zeilen,
PageDown exakt 16 Zeilen, volle Reichweite bis Zeile 99 (letzte Zeile,
Thumb am Ende) bestätigt. **Horizontales Wheel-Scrollen blieb ohne messbare
Wirkung** (zwei Simulationsvarianten versucht) — nicht als Defekt eingestuft
(plausibler Quartz-Simulationsartefakt, da macOS-Trackpads horizontal
kontinuierlich/Pixel-basiert scrollen, nicht in einfachen Notches), aber auch
nicht bewiesen funktionsfähig. Offener Punkt für eine künftige Session
(z. B. Klick-Drag auf den horizontalen Scrollbar-Thumb).

## Gate

Smoke 3/3 beide Wege. `git status` (Umbrella + Submodul) sauber — keine
Code-Änderung diese Session. `org.racket-lang.prefs.rktd` nach jeder
DrRacket-Runde zurückgespielt, Hash abschließend identisch.

## Damit aus dem ursprünglichen "Rest des Sweeps" offen

Nur noch: horizontales Mausrad (§33, s. o.) sowie die Windows-exklusiven Features
(`cursor-driver%` §40, `gauge%` §41, `get-current-mouse-state` §42, `printer-dc%`
§43) und der in der letzten Session neu gefundene Menüband-Kollaps-Befund (§44.5)
— letzterer jetzt potenziell leichter zu untersuchen, da echte Klicks/Fokus-
Aktivierung inzwischen zuverlässig funktionieren.

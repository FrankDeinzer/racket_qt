# Report — macOS: „Bares-Skript-Nichtbeenden unter Qt" (§47.1) nicht reproduzierbar — 2026-09-18 (4)

**Bezug:** Fortsetzung von `docs/2026-09-18-3_report-macos.md`. Nutzerauftrag:
weiter am §47.1-Nebenbefund arbeiten ("ein bares `racket/gui`-Skript beendet
sich nativ beim Schließen seines letzten Fensters vollständig, unter Qt
nicht"). Details/Volltext: `docs/HACKING.md` §48.

## Ausgangslage

§47.1 hatte diesen Befund nur beiläufig notiert, während die eigentliche
Session-Arbeit dem Menüband-Kollaps galt — nicht root-caused, kein Fix
versucht. Auftrag dieser Session: das nachholen.

## Erst den Exit-Gate gelesen (Advisor-Rat vor jeder Instrumentierung)

`executable-yield-handler` (`wx/common/queue.rkt:637`) blockiert vor dem
tatsächlichen Prozessende in `(yield main-eventspace)`, bis `check-done`
(Z. 213-225) postet — das passiert genau dann, wenn drei Bedingungen
gleichzeitig gelten: keine gequeueten Events, keine offenen Top-Level-Fenster,
keine Timer. Ein eigener Mini-Test widerlegte die naheliegendste Hypothese
("der endlos laufende `qt-start-event-pump`-Thread selbst hält den Prozess am
Leben") vorab empirisch: ein einfacher `(thread (lambda () (loop)))` blockiert
den Racket-Prozess-Exit **nicht**, selbst wenn er nie endet.

## Messung statt Theorie

- `examples/hello.rkt`, `PLT_QT=1`, echter Klick auf den nativen
  Schließen-Button (AXCloseButton-Subrole, `set frontmost` unmittelbar davor,
  §45.1): **3/3 sauberer Prozess-Exit**, identisch zum nativen Kontrolllauf
  (ebenfalls 3/3).
- Eigene Probe `exit-probe.rkt` mit Watchdog-Thread (druckt
  `get-top-level-windows`/Eventspace-„done"-Zustand sekündlich): identisches
  Bild — der ursprünglich vermutete Watchdog-Confound entfällt damit, da
  `hello.rkt` ganz ohne einen solchen Thread ebenso sauber beendet.
- `Cmd+W`: auf **beiden** Backends wirkungslos (kein Menüband im bare Skript,
  kein Accelerator gebunden) — erwartete Parität, keine Divergenz.

## Diskriminierender Gegentest zur „Fehlklick"-Hypothese

Naheliegende Erklärung: ein automatisierter Klick traf nicht den
Schließen-Knopf, sondern ein anderes Widget (`hello.rkt` hat einen
`Click me`-Button). Gezielt geprüft: derselbe ungefilterte
`click button 1 of window 1` trifft tatsächlich `Click me` — aber das Fenster
bleibt dabei vollständig sichtbar, der Prozess läuft unverändert weiter. Das
erzeugt nicht das in §47.1 beschriebene Symptombild „Fenster verschwindet,
Prozess bleibt am Leben", sondern schlicht „nichts passiert". Diese konkrete
Fehlklick-Mechanik scheidet damit als Erklärung aus.

## Verdikt

Weder die Pump-Thread- noch die Fehlklick-Hypothese tragen. Mit belegter
Klick-Methodik verhält sich `wx/qt` beim Schließen des letzten Fensters eines
bare Skripts auf macOS identisch zum nativen Backend (n=3/3 je Seite).
**Klassifiziert wie §21.9/§33.7: der Originalbefund reproduziert nicht; die
tatsächliche Ursache der damaligen Beobachtung ist nicht identifiziert, nicht
erfunden.** Keine Code-Änderung, keine Submodul-Berührung — es gibt (mit
dieser Messung) keinen Bug, der zu fixen wäre.

**Ausdrücklich unverändert:** die §44.5/§47.3-Reklassifizierung des
**DrRacket**-„Zombie"-Falls (bewusste `framework:exit-when-no-frames`-
Entscheidung von DrRacket selbst) — separater, weiterhin gültiger Befund,
hier nicht neu aufgerollt.

## Dokumentation korrigiert

- `docs/HACKING.md` §48 (neu).
- `CLAUDE.md`: der Satz „... gilt nachweislich **nicht** für bare
  `racket/gui`-Skripte (... unter Qt nicht — eigener, kleinerer offener
  Punkt)" korrigiert auf den §48-Befund.
- `STATUS.md`: neuer Session-Eintrag oben.

## Offen / bewusst nicht abgedeckt

- **Nur auf macOS gemessen** — Windows/Linux nicht gegengeprüft, keine
  Verallgemeinerung.
- Die exakte Ursache der ursprünglichen §47.1-Beobachtung bleibt unbekannt
  (vermutlich ein Automatisierungsartefakt der damaligen Sitzung, Klasse
  §44.6/§45.1, aber nicht belegt).
- Keine Shim-ABI-Änderung, kein Rebuild nötig, kein Submodul-Commit fällig
  (reine Umbrella-Doku-Korrektur).

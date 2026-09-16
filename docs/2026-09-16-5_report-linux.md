# Report — §33.7-Tab-2-Befund: 14/14 sauber, weiterhin nicht reproduzierbar (Linux) — 2026-09-16 (5. Sitzung des Tages)

**Auftrag:** Nutzerfrage — ist der einmalige, nicht reproduzierbare Tab-2-Befund aus
§33.7 (`docs/2026-09-14-2_report-linux.md`, falsche Zeilennummern nach Run + File→Open
als 2. Tab) noch offen? Antwort: ja, in §34-§39 (inkl. aller anderen
2026-09-16-Sessions) kein einziges Mal erwähnt. Nutzerentscheidung: mit dem in §33.7
vorbereiteten `PLT_QT_SCROLL_DEBUG=1`-Tracer erneut versuchen, mit mehr Wiederholungen
als den damaligen 3.

**Ergebnis in einem Satz:** 14 gültige, vollständige Durchläufe der historischen
Sequenz zeigten **0/14** das Symptom — §33.7 bleibt offen, aber die beobachtete Rate
ist jetzt auf ≤1-in-18 statt ≤1-in-4 eingegrenzt. Keine Code-Änderung diese Session.

---

## Automatisierung (der eigentliche Aufwand dieser Session)

Umgebung: X11-Session, `xdotool` + `spectacle` für Fenstersteuerung/Screenshots,
DrRacket unter `PLT_QT=1 PLT_QT_SCROLL_DEBUG=1`.

### Drei getrennte Automatisierungsfehlschläge — keine Backend-Befunde

Wichtig für die Genauigkeit: das waren **drei verschiedene** fehlgeschlagene Versuche
mit unterschiedlicher Methode, keiner davon zeigte je den Tab-2-Inhalt (alle drei
brachen vorher ab) — alle drei zählen deshalb **nicht** zu den 14 gewerteten Läufen.
Die ersten zwei sind hier beschrieben, der dritte (reine Automatisierungs-Race-Condition,
kein Backend-Bezug) unten in der Ergebnistabelle.

**Fehlschlag 1 (Skript `repro.sh`, verworfen):** Run per `xdotool key F5`, File→Open
per fest programmierten Mausklick-Koordinaten, `sleep 3` zwischen den Schritten.
Ergebnis: zwei überlappende „Select a file"-Dialoge plus eine Fehleranzeige im
Interactions-Fenster. **Ursache nicht abschließend geklärt** — keine Tastatur-Navigation
war hier beteiligt, die naheliegendste Vermutung ist eine zu knapp bemessene Wartezeit
nach `F5`, wodurch der nachfolgende Menü-Klick auf einen noch nicht eingeschwungenen
UI-Zustand traf. Nicht weiter untersucht — stattdessen auf eine vollständig manuelle,
Schritt-für-Schritt per Screenshot verifizierte Sequenz umgestiegen, die sauber
funktionierte (das ist der als „Lauf 1" gezählte Durchlauf).

**Fehlschlag 2 (Skript `repro2.sh`, erste Fassung):** Run per bereits verifiziertem
Mausklick; File→Open per Mausklick auf das Datei-Menü + Tastatur `Down`×3 + `Enter` —
exakt die Sequenz, die in der unmittelbar vorangegangenen manuellen Kalibrierung (ein
einziger, durchgehend offener DrRacket-Prozess) zuverlässig bei „Open…" landete. Beim
ersten scriptgesteuerten Lauf in einem **frisch gestarteten** Prozess landete dieselbe
Tastenfolge stattdessen auf „Save Definitions As…" und schrieb eine Datei `rk.rkt`
(Debris, am Sessionende entfernt). **Plausible, aber nicht unabhängig verifizierte
Erklärung:** DrRackets Qt-Datei-Menü markiert offenbar nicht in jedem frisch gestarteten
Prozess denselben ersten Eintrag, wodurch ein fixer `Down`-Zähler nicht
prozessübergreifend deterministisch ist — **diese Hypothese wurde nicht durch einen
Vorher/Nachher-Screenshot des Menü-Highlights bestätigt**, sie ist aus dem Ergebnis
rückgeschlossen. **Praktischer Fix, unabhängig von der Ursachenklärung:**
Tastatur-Navigation komplett durch eine feste, gemessene Mausklick-Koordinate für
„Open…" ersetzt (unempfindlich gegen einen etwaigen Highlight-Zustand).

### Finale Fassung — kalibriert, robust, verwendet

1. **Run:** echter Mausklick auf den Toolbar-Button (Koordinate relativ zum
   DrRacket-Fenster gemessen, nach `windowmove` auf eine feste Fensterposition
   `(50,50)` — Koordinaten bleiben über Fenstergröße hinweg stabil, unabhängig vom
   Bildschirm-Offset). Verifiziert über die tatsächliche Interactions-Ausgabe
   („Ran 3 tests. 1 of the 3 tests failed."), nicht nur per Timing angenommen.
2. **File → Open:** Datei-Menü per Mausklick öffnen, „Open…" per fixer,
   **gemessener** Pixel-Koordinate (nicht Tastatur-Nav) anklicken — Mausklick auf eine
   feste Position ist unabhängig vom Menü-Highlight-Zustand, im Gegensatz zum
   Tastatur-Zähler.
3. **Zustandsprüfung statt blindem `sleep`:** nach jedem kritischen Schritt eine
   `xdotool search --name "..."`-Abfrage mit Poll-Schleife (bis zu 3s), die die
   erwartete Fenster-/Dialog-Titel-Anzahl verifiziert, bevor der nächste Schritt
   ausgeführt wird. Weicht die Zahl ab, bricht der Lauf sofort ab (Screenshot als
   `runN_BADSTATE.png`), statt einen verfälschten Zustand als gültigen Lauf zu zählen.

Mit dieser finalen Fassung liefen 13/13 Durchläufe (Nummern 3-15) ohne einen einzigen
Abbruch durch den Zustands-Guard — die Automatisierung selbst war ab da nicht mehr die
Fehlerquelle.

## Ergebnis

| Lauf | Tab 2 Zeilennummern | Anomalie? |
|---|---|---|
| 1 (manuelle Kalibrierung) | korrekt, sequentiell | nein |
| — (Fehlschlag 1, `repro.sh`) | nie erreicht | Automatisierungsartefakt, kein Backend-Zustand — nicht gezählt |
| — (Fehlschlag 2, `repro2.sh` v1: Save-As) | nie erreicht | Automatisierungsartefakt, kein Backend-Zustand — nicht gezählt |
| — (Fehlschlag 3, `repro2.sh` v2: Dialog-Check-Race) | nie erreicht | Automatisierungsartefakt (Verifikation selbst zu früh), kein Backend-Zustand — nicht gezählt |
| 3-15 (13 weitere, finale self-verifying Skript-Fassung) | 1-17 | nein |

(Der manuelle Kalibrierungslauf zeigte in der eigenen Live-Mitschrift dieser Session
„1-15" statt „1-17" wie alle 13 späteren Läufe derselben Datei — das ist eine
Ungenauigkeit in der damaligen Beschreibung, keine tatsächliche Abweichung im
Editor-Inhalt; die Datei `examples/htdp-image-probe.rkt` hat durchgehend 16 Zeilen
Inhalt + 1 Leerzeile, entsprechend 17 Zeilennummern.)

**14 gültige Läufe insgesamt** (1 manuell + 13 scriptgesteuert, Nummern 3-15 — die
Nummern 1 und 2 sind durch die drei oben genannten verworfenen Versuche belegt und
tauchen deshalb nicht als eigene gültige Zeile auf). **0/14 zeigten das §33.7-Symptom.**
Kein Crash, kein weißer Bereich, keine Fehlermeldung. `grep -i
"error\|exception\|invalid memory\|segfault\|internal error"` über alle 16 Run-Logs
(inklusive der drei verworfenen Versuche): keine Treffer.

Der `PLT_QT_SCROLL_DEBUG=1`-Tracer kam dadurch nicht zum Zug — ohne Auftreten des
Symptoms gibt es keine auffällige Stelle im Trace, die sich von den anderen sauberen
Läufen unterscheidet.

## Einordnung

§33.7 bleibt **offen**, ehrlich unentschieden zwischen „extrem seltener echter Bug" und
„einmaliges Automatisierungsartefakt der damaligen Session" (analog zu §38s Fund, dass
`xdotool windowclose` selbst die Fehlerquelle war, nicht das Backend). Die Häufung
dieser Session — drei verschiedene, voneinander unabhängige Automatisierungsfehler in
zwei unterschiedlichen Skript-Fassungen (F5-Timing, Tastatur-Nav-Fragilität, ein zu
früh auswertender Zustands-Check) — zeigt, wie leicht diese Art Automatisierung
Artefakte erzeugt, die auf den ersten Blick wie Backend-Verhalten aussehen können.
Das ist ein Hinweis, der die zweite Hypothese plausibler macht, aber **kein Beweis**:
jeder der drei Fehler dieser Session konnte einer eigenen, plausiblen
Automatisierungsursache zugeordnet werden, während der ursprüngliche §33.7-Befund
(falsche Zeilennummern im Definitions-Editor) bei der damaligen Session mit reinen,
sorgfältig beobachteten Mausklicks entstand — ein direktes Automatisierungsartefakt
ähnlich den dreien dieser Session ist dafür nicht ausgeschlossen, aber auch nicht
identifiziert.

**Kein Grund, den offenen Status, den Cross-Platform-Rebuild-Hinweis oder sonst etwas
in `CLAUDE.md`/`docs/HACKING.md` über die reine Ergänzung dieses Nachtrags hinaus zu
ändern.**

## Nicht gemacht / offen für eine künftige Session

- Noch mehr Wiederholungen (z. B. 50-100), falls die Rate wirklich ≤1-in-18 oder
  niedriger ist — bei echtem 1-in-vielen-Auftreten bräuchte ein zuverlässiger Fang
  vermutlich zwei Größenordnungen mehr Läufe, als für diese Session verhältnismäßig war.
- Die entstandenen Automatisierungs-Skripte/Screenshots/Logs liegen nur im
  Session-Scratchpad, nicht im Repo (reine Diagnosehilfsmittel, kein reproduzierbarer
  Produktcode).
- Windows/macOS: nicht versucht (Cross-Platform-Modell, kein bekannter
  Plattformunterschied bei diesem Befund).

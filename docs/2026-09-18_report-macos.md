# Report — macOS: gebündelter Validierungs-Sweep (kritischer Kern) zu docs/2026-09-13_prompt.md — 2026-09-18

**Bezug:** `docs/2026-09-13_prompt.md` (Cluster-1-Block, Linux-geführt), bereits
gefixt/validiert auf Linux (`docs/2026-09-13_report-linux.md`) und Windows
(`docs/2026-09-17_report-win.md`). Dieser Report ist **kein neuer Fix-Block**,
sondern der auf macOS fällige, gebündelte Durchlauf. Nutzerentscheidung zu
Sessionbeginn (per `AskUserQuestion`): Umfang auf den **kritischen Kern**
begrenzen — Akzeptanztest + Enable-Kaskade + macOS-exklusive offene Fragen +
Resize/Drag — analog zum ersten Windows-Sweep, statt aller ausstehenden Punkte
in einer Session.

`racket --version`: 9.3 [cs] (Homebrew, arm64).

Details/Volltext aller Messungen: `docs/HACKING.md` §44.

## Phase 0 — Umgebung

- Umbrella `main` und Submodul `third_party/gui` (`qt-backend`) bereits synchron zu
  `origin` — kein Pull nötig, keine Sync-Nachfrage (Regel 7) erforderlich.
- `qt-shim/build/macos-arm64/libracketqtshim.dylib` war **bereits aktuell**
  (Timestamp vor Sessionbeginn) und trägt per `nm -gU` verifiziert alle seit §32
  fälligen Exporte (Resize-Callback, Wheel, Clipboard, Menu-about-to-show, Cursor,
  Gauge, Mouse-State, Printer). Der Build-Banner in `CLAUDE.md` war für macOS damit
  bereits überholt — hiermit aktualisiert.
- Fork per `raco pkg update --link` verlinkt (§29.1), kein `-S` nötig.
- Smoke 3/3 mit **und** ohne `PLT_QT=1` grün (vor und nach allen Messungen).

## Akzeptanztest `test-dock-size` — n=3, 0/3 Crash

**Bestanden.** Drei frische `racket -l drracket --`-Läufe mit
`examples/htdp-tests-probe.rkt`, Run + `File → Open…` von
`examples/htdp-image-probe.rkt` als zweiter Tab (per `Windows`-Menü als „Tab 1"/
„Tab 2" verifiziert) — **0/3 Crash**, kein „DrRacket Internal Error", jeweils
sauber über „Quit racket" beendet. **Der Linux-Fix (Commit `2f0755bd`)
generalisiert auf macOS.**

**Wichtiger Automatisierungsfund unterwegs:** rohe `click at {x,y}`-Koordinaten-
klicks auf den Toolbar-„Run"-Button (custom-gezeichneter Qt-Button, keine
Accessibility-Repräsentation) hatten trotz pixelgenau verifizierter Koordinaten
**keine Wirkung** — funktionierender Ersatz war der Klick über das Menü-Äquivalent
(`Racket → Run`, `File → Open…`). Native Menüs/Dialoge/Fenstersteuerung
funktionierten mit `click at`/AX-Actions durchgehend zuverlässig. Details + Lehre
für künftige Sessions: `docs/HACKING.md` §44.2/§44.6.

## Enable-Kaskade (§26 Fund 2)

**Interaktive Klick-Validierung durch dieselbe Automatisierungsgrenze blockiert**
(auch die AX-`click button`-Action auf den benannten Panel-Button lieferte keinen
Klick, Positivkontrolle der Probe selbst meldet „UNGÜLTIG") — nach Regel 4 geparkt,
kein spekulativer Fix versucht. **Strukturell ersatzverifiziert:** `is-shown?`
verhält sich auf macOS identisch zwischen nativ (Cocoa) und Qt (per-Widget-Flag,
nicht rekursiv — das beabsichtigte Verhalten). Zusammen mit dem sauber grünen
Akzeptanztest (der denselben Codepfad durchläuft) und der Tatsache, dass der
Cluster-1-Fix reiner, plattformunabhängiger Racket-Code ohne macOS-Zweig ist, wird
die Enable-Kaskade als funktional äquivalent eingeschätzt — **ohne** eigene
interaktive Bestätigung wie auf Windows. Diese Einschränkung ist bewusst offen
ausgewiesen. Details: `docs/HACKING.md` §44.3.

## §32 Resize/Reflow — bisher „macOS weiterhin offen", jetzt validiert

`examples/live-resize-probe.rkt`, Resize von außen über AX (`set size of window`):
Button folgt der Fensterbreite korrekt über zwei Resizes (300×200 → 700×372,
Button 696px → 870×472, Button 866px), kein Hänger, kein Kaskadieren.
`examples/minsize-resize-probe.rkt`: Unterschreitungsversuch korrigiert einmalig
auf 327×432 und bleibt stabil (zwölf weitere Ticks geprüft). **Der
Windows-validierte §32-Fix generalisiert auf macOS.** Details: `docs/HACKING.md`
§44.4.

## §29.2 „Zombie-Prozess" — reproduziert, teilweise reklassifiziert, ein neuer Befund

Erstmals per echtem Klick auf den nativen Schließen-Button (nicht nur eine andere
Automatisierung) gemessen: Fenster schließt, Prozess bleibt am Leben, CPU idle
(~20 ms/5 s) — reproduziert, deckt sich mit dem Windows-Muster. **Nativer
Kontrollversuch (ohne `PLT_QT`) zeigt exakt dasselbe Verhalten** — das ist
Standard-macOS-App-Konvention (Apps beenden sich nicht automatisch beim Schließen
des letzten Fensters), **kein Qt-Bug**. Der „Prozess überlebt"-Teil von §29.2 ist
damit analog zu §38 (Linux) reklassifiziert.

**Neuer, enger gefasster Befund dabei gefunden:** nach dem Schließen zeigt das
**native** Menüband korrekt den reduzierten Zustand (`racket, File, Help`),
während die **Qt**-Variante weiterhin das **volle** Achtmenü-Band zeigt, obwohl
keine Fenster mehr offen sind. Root-Cause nicht untersucht (außerhalb des
kritischen Kerns) — **neuer Backlog-Punkt für eine künftige Session.** Details:
`docs/HACKING.md` §44.5.

## Gate

Smoke 3/3 beide Wege (vor und nach allen Messungen). `git status` (Umbrella +
Submodul) am Ende sauber — **keine Code-Änderung diese Session** (reine
Validierung), keine neue Datei in `examples/`. `org.racket-lang.prefs.rktd`
gesichert (SHA-256 `be9b38f2…deefb9`) und nach jeder DrRacket-Runde
zurückgespielt, Hash abschließend identisch verifiziert.

## Was nicht Teil dieser Session war (Rest des gebündelten Sweeps)

Analog zum zweiten Windows-Sweep (`docs/2026-09-17-2_report-win.md`) bleiben für
eine künftige macOS-Session offen: Clipboard (§36), Menü-Enable-States (§37),
Colors-Tab-Scroll (§34), Toolbar-Overlap (§35), Crash B/Teardown (§39), Mausrad
(§33) — sowie die Windows-exklusiv bereits implementierten, auf macOS noch nicht
portierten Features `cursor-driver%` (§40), `gauge%` (§41),
`get-current-mouse-state` (§42), `printer-dc%` (§43, inkl. Shim bereits vorhanden,
aber Racket-seitige Nutzung/Verifikation auf macOS nicht Teil dieser Session).
Zusätzlich neu: der §44.5-Menüband-Kollaps-Befund.

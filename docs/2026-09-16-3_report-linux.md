# Report — „Zombie-Prozess beim Schließen des letzten Fensters" root-caused (Linux) — 2026-09-16 (3)

**Auftrag:** Nachtrag aus `docs/2026-09-16-2_report-linux.md` (§37-Session) aufgreifen:
der seit §29.2 (2026-09-13, macOS) bekannte Nebenbefund — natives Fenster schließen,
Fenster verschwindet visuell, Racket-Prozess läuft unverändert weiter, kein Absturz —
trat in der §37-Session erneut auf Linux auf. Zwei ungeprüfte Hypothesen standen im
Raum: DrRackets eigene Close-Logik vs. ein Qt-Pump-Loop-Bug bei `queue-callback`.
Auftrag: root-causen.

**Ergebnis in drei Sätzen:** Auf Linux ist der Befund **kein Bug in `wx/qt`** — er ist
ein Artefakt der bisherigen Testautomatisierung. `xdotool windowclose` liefert die
Close-Anfrage unter der hier verwendeten KWin/Plasma-X11-Session nie an die Anwendung
aus (das Fenster wird von außen zerstört, ohne dass `closeEvent` je feuert); derselbe
false positive tritt identisch unter dem **nativen gtk-Backend** auf (GTK meldet dabei
selbst `Gdk-WARNING: GdkWindow unexpectedly destroyed`). Ein echter simulierter Klick
auf den sichtbaren Schließen-Button beendet den Prozess dagegen zuverlässig — sowohl in
einer isolierten Probe (n=3/3) als auch in echtem, laufendem DrRacket (n=2/2).

**Keine Code-Änderung.** Reine Diagnose; eine temporäre Debug-Zeile in
`qt-shim/src/shim.cpp` wurde vor Abschluss der Session vollständig zurückgebaut
(`git status` im Submodul clean, `git diff qt-shim/` im Umbrella leer).

**Inhalt:** Wie der Exit-Pfad funktioniert · Diagnose · Kontrollversuch (nativ) ·
Gegenversuch (echter Klick) · Einordnung · Nicht gemacht · Startpunkt.

Technik im Detail: `docs/HACKING.md` §38.

---

## Phase 0 — Wie ein `racket`-Prozess mit GUI-Fenster überhaupt terminiert

Bevor irgendetwas an `wx/qt` verdächtigt wird, lohnt sich die Frage, was einen
`racket`-Prozess nach `(send frame show #t)` überhaupt am Leben hält und wie er wieder
beendet wird — das ist nirgends offensichtlich:

- `wx/common/queue.rkt:637-641` installiert einen `executable-yield-handler`, der vor
  dem eigentlichen Prozessende `(yield main-eventspace)` aufruft.
- Die `eventspace`-Struktur trägt `#:property prop:evt`, das auf einen internen
  `done-sema` zeigt. `check-done` (`queue.rkt:213-225`) postet diesen Semaphor genau
  dann, wenn drei Bedingungen gleichzeitig gelten: keine offenen Callback-Events in den
  `hi`/`med`/`lo`/`refresh`-Warteschlangen, keine offenen Top-Level-Fenster
  (`frames-hash`, gepflegt über `register-frame-shown` aus `frame%.direct-show`, CLAUDE.md
  Regel 5), keine anstehenden Timer.
- `(yield main-eventspace)` blockiert exakt so lange, kehrt dann zurück, und der
  `racket`-Prozess beendet sich normal (Exit-Code 0) — **ganz ohne dass irgendjemand
  `(exit)` aufruft.** Das ist der Pfad für ein schlichtes racket/gui-Skript ohne
  `framework`.
- Echtes DrRacket hat zusätzlich `framework`s `register-group-mixin`
  (`framework/private/frame.rkt:506-511`, `group.rkt:308-314`): dessen `on-close`
  ruft `remove-frame`, dann `group:on-close-action`, das bei leerer Frame-Liste
  `exit:exit` aufruft — und **das** postet erst `(queue-callback (lambda () (exit)))`
  (`framework/private/exit.rkt:68-78`), inklusive optionalem
  `user-oks-exit`-Bestätigungsdialog (nur wenn `framework:verify-exit` gesetzt ist;
  Default `#f`).

Zwei unterschiedliche Pfade also — aber beide hängen an derselben Vorbedingung: der
native Close-Request muss `frame%`s `on-close`/`direct-show #f` (Qt-Seite:
`wx/qt/frame.rkt:23-29`, `close-cb` → `qt-queue-window-event`) überhaupt erreichen.

## Phase 1 — Diagnose: `xdotool windowclose` erreicht die Anwendung nicht

Isolierte Probe (kein `framework`, nur `racket/gui`): ein `frame%`-Subklasse mit
`on-close`-Augment-Print, ein `exit-handler`-Wrapper mit Print, ein
Sekunden-Heartbeat-Thread, der `(get-top-level-windows)` mitzählt. Zusätzlich eine
temporäre, unbedingte Debug-Zeile in `RacketWindow::closeEvent`
(`qt-shim/src/shim.cpp`), um zu sehen, ob der C++-Handler überhaupt aufgerufen wird.

Unter `PLT_QT=1`, `xdotool windowclose <WID>` gegen ein frisch geöffnetes Fenster:

- Fenster verschwindet **visuell** sofort.
- Eine Sekunde später: `xdotool getwindowname <WID>` → `X Error of failed request:
  BadWindow (invalid Window parameter)` — die X11-Ressource ist vollständig zerstört,
  nicht nur unmapped.
- Der Debug-Print in `closeEvent` feuert **kein einziges Mal**. Bestätigt per
  `strings libracketqtshim.so | grep DEBUG-ZOMBIE` (String ist drin) und
  `grep racketqtshim /proc/<pid>/maps` + `stat -c '%i'` (exakt die frisch gebaute
  `.so`, keine Stale-Library).
- `on-close` (Racket-seitig) läuft nie, `(get-top-level-windows)` bleibt bei 1, der
  Prozess läuft nach 90+ Sekunden Beobachtung unverändert weiter. **n=3, identisch.**

## Phase 2 — Kontrollversuch: identischer False Positive unter nativem gtk

Dieselbe Probe, **ohne** `PLT_QT` (natives gtk-Backend), derselbe `xdotool
windowclose`-Aufruf:

```
(zombie-debug.rkt:<pid>): Gdk-WARNING **: GdkWindow 0x... unexpectedly destroyed
```

Das Fenster wird ebenfalls zerstört, ohne dass Racket-seitig irgendetwas reagiert —
und GTK meldet selbst „unexpectedly". Das ist der entscheidende Beleg: der Fehler
liegt nicht in `wx/qt`, sondern in der Interaktion von `xdotool windowclose` mit dieser
KWin/Plasma-X11-Session, unabhängig vom GUI-Toolkit. Was genau `xdotool
windowclose`/KWin hier intern tun (`_NET_CLOSE_WINDOW` an die WM vs. direktes
`WM_DELETE_WINDOW`-ClientMessage, ein möglicher Timeout-Fallback), wurde nicht weiter
seziert — für diese Codebase reicht der Befund, dass die Anfrage die Anwendung nie
erreicht.

## Phase 3 — Gegenversuch: echter simulierter Klick auf den Schließen-Button

Koordinaten **aus der Fenstergeometrie abgeleitet**, nicht aus dem Screenshot
geschätzt (§21.10-Konvention): `xdotool getwindowgeometry --shell <WID>` liefert
`X`/`Y`/`WIDTH`; die KWin-Titelleiste dieser Session ist 28px hoch (gemessen über
`xwininfo -root -tree` an einem Testfenster: Frame-Fenster liegt 28px über dem
Client-Fenster). Klickpunkt: `(X + WIDTH − 12, Y − 14)`.

- **Isolierte Probe, `PLT_QT=1`:** `closeEvent` feuert, `on-close` läuft,
  `exit-handler` wird mit Code 0 aufgerufen, Prozess vollständig beendet binnen der
  3s-Beobachtungsfrist. **n=3/3.**
- **Echtes laufendes DrRacket** (`~/racket/bin/racket -l drracket`, `PLT_QT=1`):
  Fenstergeometrie ermittelt, Klickpunkt berechnet, geklickt. **n=2/2** — einmal mit,
  einmal ohne den Autosave-Recovery-Dialog dazwischen (ein Backup aus einer früheren
  Session, per „Done" ohne Löschen verabschiedet, um kein Nutzer-Artefakt
  anzufassen). Beide Läufe: Fenster verschwindet, Prozess danach vollständig weg
  (kein Eintrag mehr in `ps aux`), kein Bestätigungsdialog blockiert (deckt sich mit
  `framework:verify-exit`-Default `#f`).

## Einordnung

Der komplette Ketten-Mechanismus — `closeEvent` → `close_cb` → `qt-queue-window-event`
→ Racket-seitiges `on-close` → `direct-show #f`/`exit:exit` → `queue-callback (exit)`
→ Prozessende über `(yield main-eventspace)` bzw. `(exit)` — funktioniert nachweislich,
**sobald der native Close-Request die Anwendung überhaupt erreicht.** Die
„Qt-Pump-Loop-Bug bei `queue-callback`"-Hypothese aus dem Startpunkt der letzten
Session ist damit **auf Linux widerlegt**. Was in den Session-Logs seit §29.2 als
„Zombie-Prozess" stand, war ein Testmethodik-Artefakt: `xdotool windowclose` ist unter
dieser KWin/Plasma-X11-Session **kein gültiger Ersatz** für einen echten Klick auf den
Schließen-Button.

**Nicht auf macOS gegengeprüft.** Die ursprüngliche §29.2-Beobachtung (2026-09-13) und
der ältere, separate §22-Nebenbefund (2026-07-14) liefen über eine andere
Automatisierung (`xdotool` existiert auf macOS nicht). Beide Zeilen bleiben in
`CLAUDE.md` offen stehen, jetzt mit dem Hinweis, dass sie mit einer anderen
Automatisierungsmethode gemessen wurden und erst nach einem äquivalenten „echter
Klick"-Test auf macOS ebenfalls als Artefakt eingeordnet werden könnten — oder als
echter, plattformspezifischer Bug bestätigt. `wx/qt/queue.rkt`s eigener Kommentar zu
`CFRunLoopRunInMode` vs. Racket CS' mach-port-Sleep beschreibt eine
macOS-spezifische Pump-Eigenheit, die diese Session nicht angerührt hat.

## Nicht gemacht (bewusst)

- **Kein Cross-Platform-Durchlauf** — reine Linux-Diagnose, kein Fix, keine
  Shim-ABI-Änderung, nichts, was einen Rebuild auf Windows/macOS erfordert.
- **`xdotool windowclose`/KWin-Innenleben nicht seziert** — der Kontrollversuch
  (identischer Fehler unter nativem gtk) genügt, um die Anwendungsseite zu entlasten;
  was genau die WM/`xdotool`-Interaktion verursacht, bleibt außerhalb des Scopes.
- **macOS-Zeilen (§29.2, §22) nicht nachgemessen** — s. Einordnung oben.

## Lehre für künftige Sessions

`xdotool windowclose` darf nicht mehr als Ersatz für „Klick auf den nativen
Schließen-Button" verwendet werden — wie bei jeder anderen Widget-Interaktion
(§21.10/§34.7 bereits etabliert) müssen echte Klickkoordinaten aus der
Fenstergeometrie abgeleitet und per `xdotool mousemove`+`click` simuliert werden.
Dieser eine Testfall war bisher die Ausnahme von der sonst schon befolgten Regel.

## Commits

Keiner. Reine Diagnose, keine Code-Änderung im Submodul oder Shim (Debug-Instrumentierung
vollständig zurückgebaut, `git status` clean). Dieser Report + die CLAUDE.md-/
STATUS.md-/HACKING.md-Doku-Änderungen sind ein reiner Umbrella-Commit.

## Startpunkt für die nächste Sitzung

Offen und unverändert bzw. neu:

- macOS-Zeilen §29.2/§22 (Zombie-Prozess-Beobachtung) mit einer äquivalenten
  „echter Klick"-Methode nachmessen, bevor sie als Artefakt geschlossen werden können.
- Windows/macOS-Rebuild für die vier ausstehenden Shim-Exporte (§32/§33/§36/§37) plus
  Cross-Platform-Validierung der Toolbar-, Scroll-, Zwischenablage- und
  Menü-Enable-State-Fixes (§33/§34/§35/§36/§37) — unverändert aus der letzten Session.
- Bild-Zwischenablage, `cursor-driver%`, `gauge%`, `printer-dc%`,
  `get-current-mouse-state` — weiterhin unangetastete Stubs aus der §36-Bestandsaufnahme.
- Windows-Streifenrechteck-Hypothese zu §35 bleibt von Linux aus nicht entscheidbar.

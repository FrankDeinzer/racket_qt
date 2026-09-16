# Report — Zwischenablage unter Qt gefixt (Linux) — 2026-09-16

**Auftrag:** Nachtrag „die Zwischenablage ist unter Qt ein No-op" aus
`docs/2026-09-14-4_report-linux.md` — gemessen dort: `set-clipboard-string` +
`get-clipboard-string` liefert nativ den String, unter Qt `#f`. Copy/Paste in
DrRacket unter Qt war damit tot, im Editor wie zu anderen Programmen.

Gemessene Version: `~/racket/bin/racket --version` → **v9.3 [cs]** (x86-64, `~/racket`,
nicht im PATH). Sitzungstyp `x11`. Qt 6.11.1.

> **Eine Shim-ABI-Änderung.** Drei neue Exporte: `shim_clipboard_set_text`,
> `shim_clipboard_get_text`, `shim_clipboard_has_text`. Windows/macOS brauchen nach dem
> Pull einen `qt-shim`-Rebuild — deckt sich mit dem bereits offenen Rebuild aus §32/§33
> (`shim_window_set_resize_cb`, `shim_canvas_set_wheel_cb`); **ein** Rebuild deckt jetzt
> alle drei ab.

**Ergebnis in drei Sätzen:** Der alte Stub war nicht nur unimplementiert, sondern trug
den falschen Methodenvertrag — `wx/common/clipboard.rkt` (die einzige Konsumentin von
`clipboard-driver%`) ruft `get-client`/`set-client`/`get-data`/`get-text-data`/
`get-bitmap-data`/`set-bitmap-data`, exakt wie bei gtk/cocoa, nicht die alten Namen
`set-data`/`clear-data`/`same-client?`. Neu implementiert nach gtk/cocoa-Vorbild, aber
eager statt Ownership-Callback, weil `QClipboard` ein schlichtes synchrones globales
Objekt ist. Verifiziert über eine neue Probe (3/3, Qt und nativ), Cross-Prozess/
Cross-Toolkit-Interop und den echten laufenden DrRacket-Prozess selbst; die
GUI-Bedienung über das Edit-Menü blieb wegen eines separaten, bereits bekannten
Menü-Enable-State-Befunds (§34.7) unverifiziert.

**Inhalt:** Root-Cause · Implementierung · Verifikation · Beobachtetes ·
Nicht Gemachtes · Commits · Startpunkt.

Technik im Detail: `docs/HACKING.md` §36.

---

## Phase 0 — Root-Cause: falscher Vertrag, nicht nur fehlende Implementierung

`wx/qt/platform.rkt` (alte Zeile 151) definierte `clipboard-driver%` mit den Methoden
`get-data`/`set-data`/`get-text-data`/`set-text-data`/`clear-data`/`get-client`/
`set-client`/`same-client?` — durchweg No-ops bzw. feste `#f`.

Bevor eine Zeile Implementierung entstand: wer ruft `clipboard-driver%` überhaupt auf?
`grep -rn "clipboard-driver%\|get-the-clipboard\|clipboard<%>"` über `mred/private/`
zeigt genau eine Konsumentin, `wx/common/clipboard.rkt`s `clipboard%`, die per
`wx/platform.rkt`s `define-values` direkt an den Backend-Export gebunden wird. Ihre
Methodenaufrufe an `driver`:

- `get-client`
- `set-client c (send c get-types)` — zwei Argumente: Client-Objekt, Typenliste
- `get-data type`
- `get-text-data`
- `get-bitmap-data`
- `set-bitmap-data bm timestamp`

Das deckt sich exakt mit `wx/gtk/clipboard.rkt` und `wx/cocoa/clipboard.rkt`s
`clipboard-driver%`-Signaturen (gelesen, um die Referenzimplementierung zu verstehen).
Der alte Qt-Stub hätte also selbst mit echter Implementierung von `set-data`/
`clear-data`/`same-client?` **nichts geändert** — diese Methoden werden von keiner
Stelle in der Codebase je gerufen. `get-client`/`set-client` trafen die Arität nur
zufällig (Racket prüft Namen nicht, nur Arität), weshalb der Stub nie laut gecrasht ist,
sondern still `#f` zurückgab.

## Phase 1 — Implementierung

**Modell:** gtk verwaltet die Zwischenablage über ein Ownership-Callback-Protokoll
(`gtk_clipboard_set_with_data` + `get_data`/`clear_owner`-Funktionszeiger) — andere
Prozesse fragen an, unser Prozess liefert erst dann. cocoa macht dasselbe über
`NSPasteboardOwner`. Beides existiert, weil GTK/Cocoa-Zwischenablagen historisch
asynchron/on-demand sind.

`QClipboard` ist dagegen ein schlichtes synchrones globales Objekt: `setText`/`text`
schreiben bzw. lesen sofort, Qt beantwortet das X11-/Wayland-Selection-Protokoll intern.
Die Implementierung folgt deshalb dem einfacheren Muster, das auch cocoas
`set-client`/`get-data` im Kern schon zeigt (dort zusätzlich mit `NSPasteboard`-
Ownership-Tracking): **eager write, live read.**

- `set-client c orig-types`: zieht sofort `(send c get-data "TEXT")`, schreibt den
  String über `shim_clipboard_set_text` in die native Zwischenablage. Cached
  `client`/`client-types`/`last-set-text` für den WXME-Pfad (s. u.).
- `get-text-data`/`get-data "TEXT"`: liest **live** über `shim_clipboard_get_text`/
  `shim_clipboard_has_text` — unabhängig vom Cache, also immer korrekt, auch wenn ein
  externes Programm zwischenzeitlich etwas anderes kopiert hat.
- `get-client`: liefert `client` nur, wenn `(equal? (native-text) last-set-text)` —
  d. h. die native Zwischenablage ist seit dem letzten `set-client` unverändert. Das
  ist die einzige Stelle, an der Staleness eine Rolle spielt.
- `get-data` für andere Formate (insbesondere `"WXME"`, das reichhaltige
  Selbst-Paste-Format aus `wxme/editor.rkt:1633`, für das es kein natives
  Qt-Gegenstück gibt): nur wenn `get-client` noch den eigenen Client liefert, sonst
  `#f` — ein externes Kopieren dazwischen fällt korrekt auf reinen Text zurück statt
  eine veraltete WXME-Struktur zu liefern.

**Scope bewusst nur Text.** `get-bitmap-data`/`set-bitmap-data` sind No-op-Stubs
geblieben (der alte Stub hatte dafür gar keine Methoden — ein Aufruf hätte hart
gecrasht, `object%` kennt keine dynamische Nachsicht). Bild-Zwischenablage war nie Teil
des gemessenen Befunds.

**Shim-Erweiterung** (`qt-shim/src/shim.cpp`, `#include <QClipboard>`/`<QMimeData>`):

```cpp
void shim_clipboard_set_text(const char* utf8)
{
    QApplication::clipboard()->setText(QString::fromUtf8(utf8), QClipboard::Clipboard);
}

const char* shim_clipboard_get_text(void)
{
    static QByteArray buf;
    buf = QApplication::clipboard()->text(QClipboard::Clipboard).toUtf8();
    return buf.constData();
}

int shim_clipboard_has_text(void)
{
    const QMimeData* md = QApplication::clipboard()->mimeData(QClipboard::Clipboard);
    return (md && md->hasText()) ? 1 : 0;
}
```

`shim_clipboard_get_text`s Rückgabe-Konvention folgt `shim_version`: ein statischer
Puffer, gültig bis zum nächsten Aufruf — ausreichend, weil Rackets `_string`-
Rückgabetyp den C-String beim FFI-Aufruf sofort in einen Racket-String kopiert, bevor
der Puffer wiederverwendet werden kann. Racket-seitige Bindings in
`wx/qt/utils.rkt:114-116/668-676`. `wx/qt/platform.rkt` requirt jetzt zusätzlich
`"utils.rkt"` — vorher nicht nötig, da `platform.rkt` selbst keine Shim-Funktion
aufrief.

Kein C-nach-Racket-Callback beteiligt (`clipboard-driver%`-Methoden werden direkt von
Racket-Code gerufen, nicht von einem Shim-Callback), also gilt hier keine der
`#:atomic?`-Regeln aus `CLAUDE.md` Regel 2.

## Phase 2 — Verifikation

**Neue Probe `examples/clipboard-probe.rkt`**, drei Prüfungen:

1. Direkter Round-trip: `set-clipboard-string`/`get-clipboard-string`.
2. Echtes `text%`-Copy einer Selektion → von außen sichtbarer reiner Text
   (`get-clipboard-string` liest zurück, was ein externes Programm sehen würde).
3. Echtes `text%`-Paste in einen zweiten Editor → übt den WXME-Selbstbesitz-Pfad aus,
   nicht nur den Text-Fallback.

Alle drei grün unter Qt **und** nativ (Kontrollmessung, gleiche Probe, kein `PLT_QT`):

```
[probe] direct string round-trip: expected="HALLO-QT-TEST" actual="HALLO-QT-TEST" OK
[probe] editor copy -> plain TEXT: expected="copied from editor 1" actual="copied from editor 1" OK
[probe] editor paste into second editor: expected="copied from editor 1" actual="copied from editor 1" OK
```

**Cross-Prozess/Cross-Toolkit:** ein `PLT_QT=1`-Prozess setzt die Zwischenablage und
hält sie offen (Event-Loop läuft weiter, beantwortet X11-Selection-Requests), ein
separater **nativer** (gtk) Prozess liest denselben String zurück:

```
[reader] got: "CROSS-PROCESS-QT-CLIPBOARD"
```

Das bestätigt, dass Qt das X11-`CLIPBOARD`-Protokoll korrekt bedient — nicht nur, dass
Racket-intern alles konsistent ist.

**Akzeptanztest in echtem DrRacket** (`~/racket/bin/racket -l drracket`, `PLT_QT=1`):
im Interactions-Pane direkt

```racket
> (send the-clipboard set-clipboard-string "REAL-DRRACKET-REPL-TEST" 0)
  (send the-clipboard get-clipboard-string 0)
"REAL-DRRACKET-REPL-TEST"
```

— im echten laufenden Prozess, nicht nur im isolierten Probe-Skript.

**Nicht bewiesen: die GUI-Bedienung selbst.** Der Versuch, Copy über das Edit-Menü
bzw. das Kontextmenü per `xdotool`-Klick auszulösen, blieb ergebnislos (Zwischenablage
danach leer bzw. unverändert). Dabei aufgefallen: das Edit-Menü zeigt `Copy`/`Cut`
**durchgehend ausgegraut**, obwohl eine Selektion aktiv war (per Screenshot bestätigt,
sichtbare Markierung im Editor). Das deckt sich mit dem bereits unter §34.7
dokumentierten, separaten Befund „Menü-Enable-States werden unter diesem Backend nicht
nachgeführt" (dort: Tabs-Menü „Previous/Next Tab" ausgegraut trotz zwei offener Tabs).
Ein Klick auf das im Kontextmenü scheinbar aktive `Copy` blieb ebenfalls wirkungslos —
vermutlich Klick-Timing/-Treffer bei einem sich schließenden Popup, nicht root-caused.

Damit ist die **Menü-Verdrahtung** selbst nicht bewiesen, wohl aber die zugrunde
liegende `clipboard-driver%`-Implementierung — dieselbe API, die das Edit-Menü
letztlich aufrufen würde, wurde im selben Prozess direkt erfolgreich geprüft (REPL-Test
oben). Die Menü-Diskrepanz ist ein Kandidat für dieselbe künftige Sitzung wie §34.7s
Tabs-Menü-Befund.

**Gate:** `raco test tests/smoke.rkt` 3/3 mit und ohne `PLT_QT`. Änderungen sind
additiv (`platform.rkt`/`utils.rkt`/`shim.cpp`), kein anderer Fix berührt.

## Beobachtet, aber nicht weiterverfolgt

- Edit-Menü zeigt `Copy`/`Cut` durchgehend ausgegraut trotz aktiver Selektion — siehe
  oben, deckt sich mit §34.7, eigene künftige Sitzung.
- `ctrl+q` (Quit) und `ctrl+c`/`ctrl+v` als Tastatur-Shortcuts erreichten DrRacket per
  `xdotool key` nicht (Fenster blieb offen bzw. Zwischenablage unverändert) — passt zu
  §34.7s bereits dokumentierter Beobachtung, dass `xdotool` nur Menüklicks und `F5`
  zuverlässig auslöst, keine Akzelerator-Tastenkombinationen. Schließen von DrRacket
  gelang stattdessen über den eigenen Fenster-Schließen-Knopf plus „Don't Save"-Dialog,
  wie von `docs/HACKING.md`s Linux-Automatisierungsnotizen empfohlen.
- Prozess beendete sich nach dem Schließen des letzten Fensters sauber (kein Zombie) —
  im Gegensatz zum bekannten, als macOS-spezifisch eingestuften Nebenbefund.

## Nicht gemacht (bewusst)

- **Bild-Zwischenablage** (`get-bitmap-data`/`set-bitmap-data`) — bleibt No-op-Stub,
  war nie Teil des gemessenen Befunds.
- **`cursor-driver%`/`gauge%`/`printer-dc%`/`get-current-mouse-state`** — aus derselben
  Bestandsaufnahme wie der Zwischenablage-Fund (`docs/2026-09-14-4_report-linux.md`,
  „Nachtrag"), weiterhin unangetastete Stubs, eigene künftige Sessions.
- **Kein Cross-Platform-Durchlauf** (gebündeltes Modell, wie bei den vorherigen
  Sessions). `QClipboard` ist plattformübergreifend dieselbe Qt-Klasse, aber die
  Windows/macOS-Rebuild-Pflicht und ein eigener Akzeptanztest stehen noch aus.
- **Menü-Enable-State-Bug (§34.7) nicht angefasst** — eigene, bereits vorgemerkte
  Sitzung; hier nur zusätzlich am Copy/Cut-Beispiel bestätigt.

## Liste „später zu validieren" (gebündelter Cross-Platform-Durchlauf)

Unverändert aus `docs/2026-09-14-4_report-linux.md` übernommen, plus:

- **Clipboard-Rebuild auf Windows/macOS:** `qt-shim` neu bauen (deckt sich mit dem
  bereits offenen §32/§33-Rebuild), dann `examples/clipboard-probe.rkt` unter Qt und
  nativ laufen lassen — muss auf beiden Plattformen 3/3 grün sein.
- **Cross-Prozess-Test auf Windows/macOS:** dort existiert kein X11-`CLIPBOARD`, daher
  ist der dortige Analogtest die jeweilige native Zwischenablage-API (Win32:
  `OpenClipboard`/`GetClipboardData`; macOS: ein zweiter Prozess über `NSPasteboard`).
  Reines Text-Round-trip-Verhalten sollte identisch sein, da `QClipboard` intern die
  jeweilige Plattform-API kapselt — aber ungeprüft, nicht angenommen.
- Menü-Enable-State-Befund (§34.7) bleibt eigene Sitzung, jetzt mit einem zweiten
  Beispiel (Copy/Cut) belegt.

## Commits

| Repo | SHA | Inhalt |
|---|---|---|
| gui-Submodul (`qt-backend`) | `5a7622d4` | `clipboard-driver%` neu implementiert (Text-only) |
| Umbrella (`main`) | _dieser Commit_ | Doku, Probe, Shim-Erweiterung + Submodul-Zeiger |

Reihenfolge nach Regel 8 eingehalten: Submodul-Stand gegen `origin` geprüft (bereits
synchron) → Submodul committet → Submodul **gepusht** → erst danach der
Umbrella-Pointer-Commit, ebenfalls gepusht. Vor beiden Push-Schritten wurde der Nutzer
gefragt (Regel 7).

## Startpunkt für die nächste Sitzung

Offen und unverändert bzw. neu:

- Windows/macOS-Rebuild für alle drei ausstehenden Shim-Exporte (§32/§33/§36) plus
  Cross-Platform-Validierung der Toolbar- und Scroll-Fixes (§33/§34/§35) und jetzt auch
  der Zwischenablage.
- Menü-Enable-States werden unter diesem Backend nicht nachgeführt (§34.7), jetzt mit
  zwei Belegen (Tabs-Menü, Edit-Menü Copy/Cut) — eigene Sitzung.
- Bild-Zwischenablage, `cursor-driver%`, `gauge%`, `printer-dc%`,
  `get-current-mouse-state` — weiterhin unangetastete Stubs aus derselben
  Bestandsaufnahme.
- Windows-Streifenrechteck-Hypothese zu §35 bleibt von Linux aus nicht entscheidbar.

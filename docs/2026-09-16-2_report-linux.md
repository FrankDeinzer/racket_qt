# Report — Menü-Enable/Check-States unter Qt gefixt (Linux) — 2026-09-16 (2)

**Auftrag:** Nachtrag aus `docs/2026-09-16_report-linux.md` (Zwischenablage-Fix, selber
Tag) und §34.7 (`docs/2026-09-14-3_report-linux.md`) aufgreifen: DrRackets Tabs-Menü
zeigt „Previous/Next Tab" bei zwei offenen Tabs weiterhin ausgegraut, und das Edit-Menü
zeigt `Copy`/`Cut` durchgehend ausgegraut trotz aktiver Selektion. Beide Symptome sehen
nach derselben Ursache aus: Menü-Enable/Check-States werden unter diesem Backend nicht
nachgeführt, bevor ein Menü erscheint.

Gemessene Version: `~/racket/bin/racket --version` → **v9.3 [cs]** (x86-64, `~/racket`,
nicht im PATH). Sitzungstyp `x11`. Qt 6.11.1.

> **Eine Shim-ABI-Änderung.** Ein neuer Export: `shim_menu_set_about_to_show_cb`.
> Windows/macOS brauchen nach dem Pull einen `qt-shim`-Rebuild — deckt sich mit dem
> bereits offenen Rebuild aus §32/§33/§36 (`shim_window_set_resize_cb`,
> `shim_canvas_set_wheel_cb`, `shim_clipboard_{set,get,has}_text`); **ein** Rebuild
> deckt jetzt alle vier ab.

**Ergebnis in drei Sätzen:** win32 (`WM_INITMENU`) und gtk (`GtkMenuItem`s
`"select"`-Signal) rufen je einmalig, kurz bevor irgendein Menü sichtbar wird,
`on-menu-click` → `on-demand` auf, was rekursiv durch die ganze Menü-Bar-Baumstruktur
läuft (auch Submenüs); `wx/qt/frame.rkt` definierte `on-menu-click` zwar korrekt als
`override*`-Ziel (Pflicht aus CLAUDE.md Regel 3), aber **nichts rief es je auf**, weil
das Qt-Äquivalent `QMenu::aboutToShow` nirgends verdrahtet war. Neu verdrahtet über
eine `RacketMenu`-QMenu-Subklasse im Shim plus eine Registrierung pro `menu%`-Instanz
in Racket, die `on-menu-click` async postet (nie synchron, Regel 2). Verifiziert über
eine neue Probe (2/2 programmatisch mit nativer Zustandsrückfrage) und direkt in
echtem, laufendem DrRacket an beiden ursprünglich gemeldeten Symptomen (Edit-Menü
Copy/Cut, Tabs-Menü Previous/Next Tab).

**Inhalt:** Root-Cause · Implementierung · Verifikation · Beobachtetes ·
Nicht Gemachtes · Commits · Startpunkt.

Technik im Detail: `docs/HACKING.md` §37.

---

## Phase 0 — Root-Cause: ein fehlender Aufruf, keine fehlende Methode

Ausgangspunkt: wer ruft in win32/gtk die Menü-Enable-State-Aktualisierung überhaupt
aus? `grep -n "on-demand" wxtop.rkt` zeigt `wxtop.rkt:738`s `on-menu-click`-Override:

```racket
[on-menu-click
 (entry-point
  (lambda ()
    (and menu-bar (send menu-bar on-demand))))]
```

`mrmenu.rkt`s `menu-bar%`/`menu%` `on-demand` (Zeilen 400-406/448-452) ruft den
`demand-callback` des jeweiligen Menüs/der Bar und rekursiert danach in jedes
Kind-Item — auch Submenüs, deren eigenes `on-demand` wieder in ihre Kinder rekursiert.
**Ein einziger Trigger pro Menü-Bar-Baum reicht also**, egal wie tief verschachtelt.

Wer ruft `on-menu-click` nativ auf?

- **win32** (`wx/win32/frame.rkt:367-370`): `WM_INITMENU` — Windows' Nachricht, die vor
  jedem Menü (Bar-Ebene oder Submenü) feuert, ruft `(on-menu-click)` über
  `constrained-reply` blockierend synchron.
- **gtk** (`wx/gtk/menu-bar.rkt:36-45`): das `"select"`-Signal auf jedem
  `GtkMenuItem`, das ein Top-Level-Menü in der Bar repräsentiert, ruft `(send frame
  on-menu-click)` über `constrained-reply`.
- **Qt** (`wx/qt/frame.rkt:198-201`, vor diesem Fix):

  ```racket
  (define/override (on-menu-command id)   (void))
  (define/override (on-menu-click)        (void))
  (define/override (on-toolbar-click)     (void))
  (define/override (on-mdi-activate on?)  (void))
  ```

  Beide Stubs erfüllen korrekt die `override*`-Pflicht (die Methode muss existieren,
  damit `wxtop.rkt` sie überschreiben kann) — aber `grep -rn "on-menu-click" wx/qt/`
  fand vor diesem Fix nur diese beiden Definitionen, **keinen einzigen Aufrufer**.
  `on-menu-command` dagegen wird sehr wohl aufgerufen — `wx/qt/menu.rkt`s
  `append`-Callback postet es bei jedem Action-Klick (`shim_action_create` → Klick →
  `queue-event` → `send frame on-menu-command id`) — weshalb Menüpunkt-Klicks lange
  funktionierten und nur die Enable/Check-**Anzeige** vor dem Öffnen fehlte, nicht die
  Funktion selbst. Das erklärt, warum der Befund lange unbemerkt blieb.

Qts Äquivalent zu `WM_INITMENU`/`"select"` ist `QMenu::aboutToShow()` — laut
Qt-Dokumentation synchron emittiert, bevor ein `QMenu` (top-level oder Submenü, ob per
`popup()` oder Bar-Klick-Aktivierung) sichtbar wird.

## Phase 1 — Implementierung

**Shim** (`qt-shim/src/shim.cpp`): `shim_menu_create` gab bisher ein rohes `new
QMenu(...)` zurück. Neue Subklasse:

```cpp
class RacketMenu : public QMenu {
public:
    shim_callback_t about_to_show_cb = nullptr;
    void* about_to_show_ud = nullptr;

    explicit RacketMenu(const QString& title) : QMenu(title)
    {
        QObject::connect(this, &QMenu::aboutToShow, [this]() {
            if (about_to_show_cb) about_to_show_cb(about_to_show_ud);
        });
    }
};

void* shim_menu_create(const char* title)
{
    return new RacketMenu(QString::fromUtf8(title));
}

void shim_menu_set_about_to_show_cb(void* menu, shim_callback_t cb, void* ud)
{
    auto* rm = static_cast<RacketMenu*>(menu);
    rm->about_to_show_cb = cb;
    rm->about_to_show_ud = ud;
}
```

Der Rückgabewert bleibt `void*`; jeder andere Aufrufer castet weiterhin
`static_cast<QMenu*>(menu)` (`shim_menu_add_submenu`, `shim_action_create`, …) — dasselbe
Offset-0-Cast-Muster, das `RacketWindow`/`QWidget*` im ganzen File bereits etabliert
(einfache, nicht-virtuelle Vererbung; jede der zahlreichen `static_cast<QWidget*>`-
Stellen in `shim.cpp` verlässt sich schon darauf, dass ein `void*`, das eine abgeleitete
Klasse referenziert, als Basisklassen-Pointer gecastet werden darf). `shim_callback_t`
(`void (*)(void* userdata)`) genügt, da `aboutToShow` keine Nutzdaten trägt — dieselbe
Signatur wie `shim_button_create`s `click_cb`.

**Racket** (`wx/qt/menu.rkt`): pro `menu%`-Instanz, direkt nach `qt-menu`-Erzeugung:

```racket
(define about-to-show-cb
  (lambda (_ud)
    (let ([frame (find-top-frame)])
      (when frame
        (queue-event (send frame get-eventspace)
          (lambda ()
            (send frame on-menu-click)))))))
(shim_menu_set_about_to_show_cb qt-menu about-to-show-cb #f)
```

`find-top-frame` existierte bereits (dieselbe Elternketten-Traversierung, die auch der
Action-Klick-Callback benutzt: über `the-parent` bis zu einem `menu-bar%`, dessen
`get-top-window` den Frame liefert). Der Callback postet `on-menu-click` **async** in
das Eventspace des gefundenen Frames — nie synchron, wie von CLAUDE.md Regel 2
gefordert. Diese Codebase definiert `_callback_t` (`wx/qt/utils.rkt:147-148`) als
`(_fun #:atomic? #t _pointer -> _void)`, ohne `#:async-apply` — dieselbe Konvention wie
jeder andere bestehende Qt-Callback (Klick, Resize, Wheel); die tatsächliche
Sicherheitsgrenze ist, dass der C-Callback nur postet und nie synchron zurück nach
Racket ruft (s. `docs/HACKING.md` §21 zur `#:async-apply`-Abweichung dieser Codebase).

Der Callback wird als schlichtes Objekt-Feld gehalten (gleiches Lebensdauer-Muster wie
`frame.rkt`s `resize-cb`) — solange die `menu%`-Instanz lebt, lebt der Callback mit ihr.
Kein Bedarf für das `retained-callbacks`-Hash-Muster, das `append`s Action-Callbacks
brauchen (dort ist der Callback lokal an die Methode gebunden, hier ist er ein Feld).

**`wx/qt/frame.rkt` ist unverändert.** Der Stub war bereits korrekt (erfüllte die
`override*`-Pflicht); es fehlte ausschließlich ein Aufrufer, und der sitzt jetzt in
`menu.rkt`, nicht in `frame.rkt`.

## Phase 2 — Verifikation

**Neue Probe `examples/menu-demand-probe.rkt`** (Qt-spezifisch, requirt `wx/qt/menu-bar`
direkt für `debug-get-appended-menu`, hinter `PLT_QT_DEBUG` gated wie
`menu-click-probe.rkt`): ein `menu%` mit `demand-callback`, der bei jedem Aufruf einen
Zähler erhöht und ein `checkable-menu-item%` togglet. Zwei echte
`(send wx-menu popup ...)`-Aufrufe (derselbe native Pfad wie ein Nutzerklick — Qts
`QMenu::popup()`, nicht der C-Callback direkt aufgerufen):

```
[probe] before any popup: demand-count=0
[probe] demand-callback fired, count=1 toggle=#t
[probe] after popup 1: demand-count=1 checked?=#t
[probe] demand-callback fired, count=2 toggle=#f
[probe] after popup 2: demand-count=2 checked?=#f
[probe] RESULT: PASS -- on-menu-click/on-demand fired on real QMenu::aboutToShow, 2 times
```

`is-checked?` liest über `shim_action_is_checked` den **nativen** QAction-Zustand
zurück, nicht nur Racket-seitige Buchführung — bestätigt, dass die Zustandsänderung
tatsächlich im Qt-Widget ankommt, nicht nur im Racket-Modell.

**Akzeptanztest in echtem DrRacket** (`~/racket/bin/racket -l drracket`, `PLT_QT=1`,
`xdotool`+`spectacle`, wie in §21.10/§34.7 etabliert):

1. Text in die Definitions-Editor getippt, Edit-Menü per Klick geöffnet → `Cut`/`Copy`
   korrekt greyed-out (keine Selektion vorhanden — das ist richtiges Verhalten, kein
   Bug).
2. `Select All` per Menüklick, Edit-Menü erneut geöffnet → `Cut`/`Copy` jetzt aktiv
   (schwarzer statt grauer Text), Selektion sichtbar im Editor-Hintergrund hinter dem
   Menü. `Redo`/`Replace`/`Replace All` bleiben korrekt greyed-out (keine
   Redo-Historie, kein Such-/Ersetzungstext).
3. `File → New Tab`, Tabs-Menü geöffnet → `Previous Tab`/`Next Tab` jetzt aktiv (vorher
   bei einem Tab korrekt greyed-out), `Tab 1: Untitled`/`Tab 2: Untitled 2` beide aktiv,
   `Tab 3`-`Tab 8` weiterhin greyed-out (existieren nicht).

Beide ursprünglich gemeldeten Symptome (§34.7, Zwischenablage-Nachtrag) damit direkt am
lebenden Prozess bestätigt, nicht nur in der isolierten Probe. Screenshots liegen im
Session-Scratchpad, nicht ins Repo übernommen (reine Verifikationsartefakte, kein
dauerhafter Doku-Wert über den Text hier hinaus).

**Gate:** `raco test tests/smoke.rkt` 3/3 mit **und** ohne `PLT_QT`, mehrfach
wiederholt für Stabilität. Änderungen sind additiv (`menu.rkt`/`utils.rkt`/`shim.cpp`),
kein anderer Fix berührt.

## Beobachtet, aber nicht weiterverfolgt

- Der bereits bekannte Nebenbefund „Prozess beendet sich nach dem Schließen des letzten
  Fensters nicht" (s. `CLAUDE.md`s „Offene Nebenbefunde") trat auch in dieser Sitzung
  wieder auf — Fenster schloss visuell, Prozess blieb am Leben (`ps aux` bestätigte),
  per `kill` aufgeräumt statt root-caused. Nicht Teil dieses Fixes.
- Popup-Menüs (`popup-menu%`, Kontextmenüs) wurden nicht gesondert getestet — ihr
  `the-parent` wird nicht über `menu-bar%` gesetzt, `find-top-frame` liefert für sie
  vermutlich `#f`, wodurch ihr eigenes `aboutToShow` keinen Effekt hätte. Das ist
  funktional unkritisch (kein Crash, `(when frame ...)` no-opt einfach), aber ob
  Popup-Menüs unter win32/gtk denselben `on-demand`-Vorlauf bekommen, wurde nicht
  geprüft — außerhalb des gemessenen Befunds (der ausschließlich die Menü-**Bar**
  betraf).

## Nicht gemacht (bewusst)

- **Kein Cross-Platform-Durchlauf** (gebündeltes Modell, wie bei den vorherigen
  Sessions). `QMenu::aboutToShow` ist plattformübergreifend dieselbe Qt-API, aber die
  Windows/macOS-Rebuild-Pflicht und ein eigener Akzeptanztest stehen noch aus.
- **Popup-Menüs nicht vertieft** — s. oben, außerhalb des gemessenen Befunds.
- **Windows-Streifenrechteck-Hypothese (§35 Hypothese 1)** weiterhin unberührt, von
  Linux aus nicht entscheidbar.

## Liste „später zu validieren" (gebündelter Cross-Platform-Durchlauf)

Unverändert aus `docs/2026-09-16_report-linux.md` übernommen, plus:

- **Menü-Rebuild auf Windows/macOS:** `qt-shim` neu bauen (deckt sich mit dem bereits
  offenen §32/§33/§36-Rebuild), dann `examples/menu-demand-probe.rkt` unter
  `PLT_QT_DEBUG=1` laufen lassen — muss auf beiden Plattformen 2/2 grün sein, plus der
  DrRacket-Akzeptanztest (Edit-Menü Copy/Cut, Tabs-Menü Previous/Next Tab).

## Commits

| Repo | SHA | Inhalt |
|---|---|---|
| gui-Submodul (`qt-backend`) | _siehe Umbrella-Zeiger_ | `menu.rkt`/`utils.rkt` Menü-Enable-State-Fix (§37) |
| Umbrella (`main`) | _dieser Commit_ | Doku, Probe, Shim-Erweiterung + Submodul-Zeiger |

Reihenfolge nach Regel 8 eingehalten: Submodul-Stand gegen `origin` geprüft → Submodul
committet → Submodul **gepusht** → erst danach der Umbrella-Pointer-Commit, ebenfalls
gepusht. Vor beiden Push-Schritten wurde der Nutzer gefragt (Regel 7).

## Startpunkt für die nächste Sitzung

Offen und unverändert bzw. neu:

- Windows/macOS-Rebuild für alle vier ausstehenden Shim-Exporte (§32/§33/§36/§37) plus
  Cross-Platform-Validierung der Toolbar-, Scroll-, Zwischenablage- und
  Menü-Enable-State-Fixes (§33/§34/§35/§36/§37).
- Bild-Zwischenablage, `cursor-driver%`, `gauge%`, `printer-dc%`,
  `get-current-mouse-state` — weiterhin unangetastete Stubs aus der §36-Bestandsaufnahme.
- Windows-Streifenrechteck-Hypothese zu §35 bleibt von Linux aus nicht entscheidbar.
- Prozess-bleibt-am-Leben-Nebenbefund beim Schließen des letzten Fensters — weiterhin
  nicht root-caused.

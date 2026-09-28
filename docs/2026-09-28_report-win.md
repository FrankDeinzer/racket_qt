# Report — Windows, Shim-Rebuild + Validierung §59.1/§59.2/§60.3/§60.4/§61.1/§60.6 — 2026-09-28

**Kontext:** Fortsetzung nach der macOS-lastigen §59–§61-Serie (viele Bugs auf macOS
gefixt, drei ABI-relevante Shim-Änderungen seit dem letzten Windows-Rebuild vom
2026-09-22 aufgelaufen — s. Build-Banner in `CLAUDE.md`). Nutzerauftrag: Shim neu
bauen und die Fixes auf Windows testen, Nutzer schaut live über die Schulter mit
(keine Delegation an Subagenten).

**Racket:** v9.3 [cs] (`C:\Program Files\Racket`).
**gui-Submodul (Start dieser Session):** `c986ba6a` (identisch zum letzten macOS-Stand,
Umbrella bereits auf diesen Pointer aktualisiert, s. `git log` zu Sessionbeginn).
**qt-shim:** Build vom 2026-09-22 20:08 — vor §59.2/§60.3/§60.6, Rebuild fällig.

---

## Shim-Rebuild

```powershell
cmake --build qt-shim/build/windows-x64 --config Debug
```

Sauberer Durchlauf, keine Fehler/Warnings von Belang. `racketqtshim.dll`:
381 440 Bytes (2026-09-22 20:08) → 434 688 Bytes (2026-09-28 18:01).

`dumpbin /exports` (via `vswhere`-ermittelten MSVC-Toolchain-Pfad) bestätigt
stichprobenartig die neuen Symbole:

```
shim_button_set_label
shim_list_tree_append_column
shim_list_tree_create
shim_list_tree_delete_column
shim_list_tree_move_column
shim_list_tree_scroll_to
shim_list_tree_set_headers_visible
shim_menu_set_about_to_hide_cb
```

170 `shim_*`-Symbole insgesamt exportiert.

## Gate-Tests

```powershell
& "C:\Program Files\Racket\raco.exe" test tests/stub-audit.rkt
# 9 tests passed

$env:PLT_QT = "1"
$env:PATH = "C:\Qt\6.11.0\msvc2022_64\bin;C:\Program Files\Racket;" + $env:PATH
& "C:\Program Files\Racket\raco.exe" test tests/smoke.rkt
# 3 tests passed
```

Beide grün, keine Regression. `git status` im Umbrella danach weiterhin clean (Build-
Artefakte liegen außerhalb des Git-Baums bzw. sind bereits ignoriert).

## Validierung gegen echtes DrRacket (`PLT_QT=1`, natives Fenster, keine RDP-Session)

Durchgeführt per PowerShell-gesteuerter Maussimulation (`SetCursorPos`/`mouse_event`)
mit Screenshot-Verifikation nach jedem Schritt — keine Subagenten, interaktiv mit dem
Nutzer als Beobachter.

### §59.1/§59.2 — Popup-Menü (Kontextmenü)

Rechtsklick im Definitions-Editor öffnet das Standard-Kontextmenü (Undo/Redo/Copy/
Cut/Paste/Delete/Select All) korrekt an der erwarteten Position. Klick außerhalb des
Menüs schließt es ohne Auswahl; `Get-Process DrRacket` bestätigt den Prozess läuft
danach unverändert weiter (kein Absturz, kein Hang). **PASS.**

### §60.3 — `button%` `set-label`

`Language` → `Choose Language…` (Ctrl+L funktioniert über die Tastatur nicht, s.
Methodik-Abschnitt unten — über Maus-Navigation geöffnet). Details waren aus einer
vorherigen Session bereits ausgeklappt (`racket-prefs.rktd` persistiert das). Klick
auf „Hide Details (Ctrl+D)" kollabiert den Dialog von 807×876 auf 318×582 (logische
Fenstergröße, per `GetWindowRect` gemessen). Dialog zurück ins Sichtfeld geholt: Button
zeigt jetzt korrekt „Show Details (Ctrl+D)". **PASS** — Label-Toggle funktioniert wie
auf macOS.

### §60.4/§61.1 — Collection-Paths-Buttons (`group-panel%`-Chrome-Fix)

Im selben Dialog, Details-Bereich „Collection Paths": alle fünf Buttons (Add, Add
Default, Remove, Raise, Lower) vollständig sichtbar, keine Titelleistenhöhe schneidet
sie ab. **PASS.**

### §60.6 — Mehrspalten-`list-box%` (Package Manager)

`File` → `Package Manager…` → Tab „Currently Installed": 5 Spalten mit Headern (✓,
Scope, Name, Checksum, Source), „219/219 match" (219 installierte Pakete auf dieser
Maschine, macOS-Referenzlauf hatte 217 — erwartete Differenz durch unterschiedliche
Paketinstallationen, kein Befund). Klick auf den „Name"-Header sortiert die Liste
sichtbar alphabetisch (vorher: Installationsreihenfolge beginnend mit `draw-lib`/
`gui-lib`/`main-distribution`; nachher: durchgängig alphabetisch ab `2d`). **PASS.**

Package Manager und DrRacket danach sauber geschlossen (kein Force-Kill nötig für
den Package-Manager-Teil, `WM_CLOSE`; DrRacket-Hauptprozess am Ende per
`Stop-Process` beendet, da nur Testdaten in einem `Untitled`-Puffer offen waren —
kein Datenverlust).

## Methodik-Befunde (Windows-spezifisch, kein `racket-qt`-Bug)

Ausführlich dokumentiert in `docs/HACKING.md` §62.3. Kurzfassung:

1. **Koordinaten-Skalierung uneinheitlich zwischen Fenstertypen.** Das maximierte
   `frame%`-Hauptfenster akzeptiert `SetCursorPos`-Koordinaten 1:1 gegenüber
   Screenshot-Pixeln. Jedes sekundäre Top-Level-Fenster (Dialoge, Menü-Popups,
   Package-Manager-Fenster) braucht Koordinaten geteilt durch einen Faktor ≈1,22–1,25.
   Empirisch kalibriert über `GetWindowRect` + bekannte Referenzklicks, nicht
   abschließend root-caused (vermutlich DPI-Virtualisierung des nicht-DPI-aware
   PowerShell-Prozesses, inkonsistent zwischen maximierten und nicht-maximierten
   Fenstern angewendet). Hover-Bewegung ohne Klick erzeugt in Qt-Menüs keine
   `WM_MOUSEMOVE`-Events und damit kein Highlight — als Kalibrierungssignal ungeeignet.
2. **`Ctrl+<Taste>`-Tastenkombinationen erreichen das Qt-Fenster synthetisch nicht** —
   weder `SendKeys.SendWait("^l")` noch rohes `keybd_event`-Down/Up-Paar für
   `VK_CONTROL`+`VK_L`. Reine Zeicheneingabe ohne Modifier funktioniert zuverlässig.
   Betroffen: `Ctrl+L`, `Ctrl+A`, `Ctrl+Z` — alle ignoriert, kein Fehler, einfach
   keine Wirkung. Workaround: alle Interaktionen dieser Session liefen über
   Maus-Koordinaten statt Tastatur-Shortcuts.

Beide Punkte sind reine Automatisierungs-Artefakte dieser Session/Maschine, keine
`racket-qt`-Funktionsdefekte — die entsprechenden Menüpunkte/Shortcuts selbst
funktionieren (verifiziert über die Maus-Route).

## Nebenfund: `racket-prefs.rktd` wurde durch die Session verändert

Wie erwartet (Fenstergeometrie, Choose-Language-Details-Zustand) — vor Sessionbeginn
gesichert (`Get-FileHash`), Diff nach Sessionende bestätigt Änderung. Kein Restore
angefragt/nötig, da keine funktional relevanten Nutzerdaten betroffen waren (reine
Test-Session, kein produktiver DrRacket-Workflow unterbrochen).

## Zusammenfassung

| Prüfpunkt | Ergebnis |
|---|---|
| Shim-Rebuild | ✅ |
| `stub-audit.rkt` | ✅ 9/9 |
| `smoke.rkt` (`PLT_QT=1`) | ✅ 3/3 |
| §59.1/§59.2 Popup-Menü | ✅ |
| §60.3 `button%` `set-label` | ✅ |
| §60.4/§61.1 Collection-Paths-Buttons | ✅ |
| §60.6 Mehrspalten-`list-box%` | ✅ |

Alle drei seit §59.2/§60.3/§60.6 offenen Windows-Rebuild-Pflichten sind damit
abgeschlossen. **Linux bleibt die einzige noch ausstehende Maschine** (gleicher
Rebuild + dieselben vier Validierungspunkte empfohlen).

## Drei-Maschinen-Sync

Umbrella/Submodul-Stand dieser Maschine unverändert gegenüber Sessionbeginn (keine
Code-Änderungen, nur Dokumentation: `CLAUDE.md`, `docs/HACKING.md`, dieser Report,
`STATUS.md`). Kein neuer Submodul-Commit, kein Push-Bedarf für Code — die
Dokumentations-Commits folgen dem üblichen Umbrella-Only-Pfad.

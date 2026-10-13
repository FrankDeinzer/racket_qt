#!/usr/bin/env python3
# Xdnd-Quelle fuer tests/sweep/dnd-drop.sh (HACKING §83.2): ein kleines GTK3-Fenster "dnd-src" (PyGObject, systemweit
# vorhanden -- nichts installiert), das beim Ziehen die uebergebenen Dateien als text/uri-list anbietet (wie Dolphin).
# Aufruf:  python3 -I tests/sweep/dnd-source.py <datei> [<datei> ...]     (laeuft bis es beendet wird)
import sys, pathlib
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk
uris = [pathlib.Path(a).resolve().as_uri() for a in sys.argv[1:]]
win = Gtk.Window(title="dnd-src")
win.set_default_size(160, 80); win.move(900, 600)
box = Gtk.EventBox(); lab = Gtk.Label(label="drag me"); box.add(lab); win.add(box)
box.drag_source_set(Gdk.ModifierType.BUTTON1_MASK, [Gtk.TargetEntry.new("text/uri-list", 0, 0)], Gdk.DragAction.COPY)
box.connect("drag-data-get", lambda w, ctx, data, info, t: data.set_uris(uris))
win.connect("destroy", Gtk.main_quit)
win.show_all()
Gtk.main()

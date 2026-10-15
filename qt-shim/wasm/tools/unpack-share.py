#!/usr/bin/env python3
"""Unpack an Emscripten-style package payload (share.data + share.data.js from the racket-wasm-backend orchestrator) into a
directory tree, so CMake can `--preload-file <tree>/share@/share` it into the combined Qt+Racket module.

The loader share.data.js carries `loadPackage({"files":[{"filename":..., "start":..., "end":...}, ...], ...})`; share.data is
the file contents concatenated, addressed by those offsets.

usage: unpack-share.py <share.data.js> <share.data> <outdir>
"""
import json
import os
import re
import sys

js_path, data_path, outdir = sys.argv[1:4]
js = open(js_path, encoding="utf-8").read()
i = js.index("loadPackage({")
j = i + len("loadPackage(")
depth, k = 0, j
while True:                      # balanced-brace scan of the JSON object literal
    c = js[k]
    if c == "{":
        depth += 1
    elif c == "}":
        depth -= 1
        if depth == 0:
            break
    k += 1
meta = json.loads(js[j:k + 1])
data = open(data_path, "rb").read()
n = 0
for f in meta["files"]:
    name = f["filename"]
    if not name.startswith("/"):
        raise SystemExit("unexpected non-absolute filename: %r" % name)
    dest = os.path.normpath(os.path.join(outdir, name.lstrip("/")))
    if not dest.startswith(os.path.abspath(outdir) + os.sep) and os.path.abspath(dest) != os.path.abspath(outdir):
        raise SystemExit("path escapes the output directory: %r" % name)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "wb") as out:
        out.write(data[f["start"]:f["end"]])
    n += 1
sys.stderr.write("unpack-share: %d files -> %s (data %d bytes)\n" % (n, outdir, len(data)))

#!/usr/bin/env python3
"""Vergleich zweier Geometrie-Protokolle (examples/visual-matrix-probe.rkt) + Bildhinweis.
Aufruf: visual-matrix-diff.py <szene> <gtk.proto> <qt.proto> <gtk.png> <qt.png> <side.png> <known.txt>
Ausgabe: Kennzahlenzeile + je Abweichung eine Zeile (CAND/theme/known); Exit 1 bei CAND."""
import sys, re, shlex, fnmatch
from PIL import Image, ImageChops

scene, gp, qp, gi, qi, side, known = sys.argv[1:8]

def parse(fn):
    d = {}
    try:
        for ln in open(fn):
            if not ln.startswith(scene + " "): continue
            ln = ln.rstrip("\n")
            try: parts = shlex.split(ln.replace('\\', '\\\\'))
            except ValueError: continue
            if len(parts) < 4 or parts[1] == "END": continue
            nums = parts[-7:]
            try: x, y, w, h, mw, mh = map(int, nums[:6])
            except ValueError: continue
            d[parts[1]] = dict(cls=parts[2], label=" ".join(parts[3:-7]), x=x, y=y, w=w, h=h, mw=mw, mh=mh)
    except FileNotFoundError: pass
    return d

G, Q = parse(gp), parse(qp)
rules = []
for ln in open(known):
    ln = ln.strip()
    if not ln or ln.startswith("#") or "|" not in ln: continue
    lhs, why = ln.split("|", 1); t = lhs.split()
    if len(t) == 2 and t[0] in (scene, "*"): rules.append((t[1], why.strip()))
def known_reason(path, cls, what=""):
    for pat, why in rules:
        kind = ""
        if "@" in pat: pat, kind = pat.split("@", 1)
        if kind and not what.startswith(kind): continue
        if pat == "*" or fnmatch.fnmatch(path, pat) or pat == "class=" + cls: return why
    return None
CONT = re.compile(r"(panel|pane|frame)%$")

def absrect(D, path):
    x = y = 0; p = ""
    for seg in ([] if path == "frame" else path.split("/")):
        p = seg if not p else p + "/" + seg
        x += D[p]["x"]; y += D[p]["y"]
    n = D[path]; return (x, y, x + n["w"], y + n["h"])
def bbox(D):
    leaves = [k for k in D if k != "frame" and not any(o.startswith(k + "/") for o in D)]
    if not leaves: return (0, 0)
    r = [absrect(D, k) for k in leaves]
    return (max(a[2] for a in r) - min(a[0] for a in r), max(a[3] for a in r) - min(a[1] for a in r))
def pct(a, b): return 100.0 * (b - a) / a if a else 0.0
def tol(a, b): return abs(b - a) <= max(6, 0.10 * max(a, b))

out = []; findings = []; cand = 0; nok = 0; ntheme = 0; nknown = 0
if "frame" not in G or "frame" not in Q:
    print(f"{scene}: PROTOKOLL FEHLT (gtk={'frame' in G} qt={'frame' in Q})"); sys.exit(1)
gf, qf = G["frame"], Q["frame"]
gb, qb = bbox(G), bbox(Q)

def judge(path, what, msg, cls):
    global cand, nknown, ntheme
    r = known_reason(path, cls, what)
    findings.append((path, what, msg, cls, r))

for k in sorted(set(G) | set(Q), key=lambda s: [int(t) if t.isdigit() else -1 for t in s.split("/")]):
    if k == "frame": continue
    if k not in G: judge(k, "extra", f"nur Qt: {Q[k]['cls']} '{Q[k]['label']}'", Q[k]['cls']); continue
    if k not in Q: judge(k, "fehlt", f"in Qt fehlt: {G[k]['cls']} '{G[k]['label']}'", G[k]['cls']); continue
    g, q = G[k], Q[k]
    nok_here = True
    for ax in "wh":
        if not tol(g[ax], q[ax]):
            nok_here = False
            judge(k, "size-" + ax, f"{g['cls']} '{g['label'][:24]}' gtk {g['w']}x{g['h']} Qt {q['w']}x{q['h']} ({pct(g['w'],q['w']):+.0f}%/{pct(g['h'],q['h']):+.0f}%)", g['cls'])
    # Beschnitten: Kind ragt aus dem Elternteil (nur Qt)
    if "/" in k:
        par = k.rsplit("/", 1)[0]
        def clip(D):
            p, c = D[par], D[k]; return max(0, c["x"] + c["w"] - p["w"], -c["x"], c["y"] + c["h"] - p["h"], -c["y"])
        cq, cg = clip(Q), clip(G)
        if cq > 2 and cq > cg + 2: nok_here = False; judge(k, "clip", f"ragt {cq}px aus dem Elternteil (gtk {cg})", g['cls'])
        # horizontale Ausrichtung (Mittelpunkt relativ zum Elternteil)
        pg, pq = G[par], Q[par]
        if tol(pg["w"], pq["w"]):
            cxg = g["x"] + g["w"] / 2 - pg["w"] / 2; cxq = q["x"] + q["w"] / 2 - pq["w"] / 2
            if abs(cxq - cxg) > max(12, 0.10 * pg["w"]):
                nok_here = False; judge(k, "align", f"Mittelpunkt relativ zum Elternteil gtk {cxg:+.0f} Qt {cxq:+.0f}", g['cls'])
    # abgeschnittenes Label: kleiner als eigenes Minimum
    if q["w"] < q["mw"] - 1 and g["w"] >= g["mw"] - 1:
        nok_here = False; judge(k, "shrunk", f"Breite {q['w']} < Minimum {q['mw']} (gtk {g['w']}/{g['mw']})", g['cls'])
    if nok_here: nok += 1
# Ueberlappung unter Geschwistern
def overlaps(D):
    res = set(); keys = [k for k in D if k != "frame"]
    for a in keys:
        for b in keys:
            if a < b and "/" in a and "/" in b and a.rsplit("/", 1)[0] == b.rsplit("/", 1)[0]:
                A, B = D[a], D[b]
                ox = min(A["x"] + A["w"], B["x"] + B["w"]) - max(A["x"], B["x"])
                oy = min(A["y"] + A["h"], B["y"] + B["h"]) - max(A["y"], B["y"])
                if ox > 2 and oy > 2: res.add((a, b))
    return res
for a, b in sorted(overlaps(Q) - overlaps(G)): judge(a, "overlap", f"überlappt {b} (nur Qt)", Q[a]['cls'])

# Abstaende (Spacing/Border) zwischen Geschwistern
def kids(D, par):
    pre = "" if par == "frame" else par + "/"
    ks = [k for k in D if k != "frame" and k.startswith(pre) and "/" not in k[len(pre):] and k[len(pre):].isdigit()]
    return sorted(ks, key=lambda k: int(k.rsplit("/", 1)[-1]))
def orient(D, ks):
    if len(ks) < 2: return None
    a, b = D[ks[0]], D[ks[1]]
    return "h" if b["x"] >= a["x"] + a["w"] - 2 and abs(b["y"] - a["y"]) < max(a["h"], b["h"]) else ("v" if b["y"] >= a["y"] + a["h"] - 2 else None)
for par in sorted(set(k.rsplit("/", 1)[0] if "/" in k else "frame" for k in G)):
    kg, kq = kids(G, par), kids(Q, par)
    if len(kg) < 2 or len(kg) != len(kq): continue
    og, oq = orient(G, kg), orient(Q, kq)
    if not og or og != oq: continue
    for i in range(len(kg) - 1):
        def gap(D, ks): a, b = D[ks[i]], D[ks[i+1]]; return (b["x"] - a["x"] - a["w"]) if og == "h" else (b["y"] - a["y"] - a["h"])
        dg, dq = gap(G, kg), gap(Q, kq)
        if abs(dg - dq) > 3: judge(kq[i + 1], "gap", f"Abstand zum Vorgaenger gtk {dg} Qt {dq}", Q[kq[i+1]]['cls'])

# Kaskade: Container-Groessenabweichungen, die Kinder erklaeren, sind keine eigenen Funde
leafsz = {p for p, w, m, c, r in findings if w.startswith("size") and not CONT.search(c)}
for p, w, m, c, r in findings:
    if w.startswith("size") and CONT.search(c) and any(l.startswith(p + "/") or p == "frame" for l in leafsz):
        out.append(f"  casc  {p} {w}: {m}"); continue
    if r: nknown += 1; out.append(f"  known {p} {w}: {m} ({r})")
    else: cand += 1; out.append(f"  CAND  {p} {w}: {m}")

# Bildhinweis
pix = "n/a"
try:
    A, B = Image.open(gi).convert("L"), Image.open(qi).convert("L")
    Bs = B.resize(A.size)
    diff = ImageChops.difference(A, Bs).point(lambda v: 255 if v > 48 else 0)
    pix = f"{100.0 * sum(1 for v in diff.getdata() if v) / (A.width * A.height):.1f}%"
    a, b = Image.open(gi).convert("RGB"), Image.open(qi).convert("RGB")
    c = Image.new("RGB", (a.width + b.width + 10, max(a.height, b.height)), (255, 0, 255))
    c.paste(a, (0, 0)); c.paste(b, (a.width + 10, 0)); c.save(side)
except Exception as e: pix = f"err({e})"

fdw, fdh = qf["w"] - gf["w"], qf["h"] - gf["h"]
verdict = "CAND" if cand else ("theme" if (not tol(gf["w"], qf["w"]) or not tol(gf["h"], qf["h"]) or nknown) else "ok")
print(f"{scene}: {verdict}  frame gtk {gf['w']}x{gf['h']} Qt {qf['w']}x{qf['h']} d={fdw:+d}x{fdh:+d} ({pct(gf['w'],qf['w']):+.0f}%/{pct(gf['h'],qf['h']):+.0f}%)  "
      f"bbox gtk {gb[0]}x{gb[1]} Qt {qb[0]}x{qb[1]}  nodes {len(G)}/{len(Q)} ok={nok} known={nknown} cand={cand}  pixel-diff(hint)={pix}")
print("\n".join(out))
sys.exit(1 if cand else 0)

#!/usr/bin/env python3
"""Extract the anatomical body model from react-native-body-highlighter (MIT,
(c) 2022 ELABBASSI Hicham) into a bundled JSON for Drift's native SwiftUI
renderer (#929).

Source (pinned): github.com/HichamELBSI/react-native-body-highlighter
  commit 15df9e2dbc621450001960bed5a30e6a75357faa
  assets/bodyFront.ts, assets/bodyBack.ts,
  assets/bodyFemaleFront.ts, assets/bodyFemaleBack.ts   -> muscle regions
  components/SvgMaleWrapper.tsx, SvgFemaleWrapper.tsx   -> body outline strokes

Output: DriftCore/Sources/DriftCore/Resources/bodyDiagram.json
  { "models": { "maleFront": {"viewBox": [w,h], "outline": [d...],
                 "muscles": {slug: [d...]}}, ... } }

All path data is normalized:
  - absolute commands only, reduced to M / L / C / Z (H,V->L; Q->C; S,T expanded;
    elliptical arcs A converted to cubic Beziers)  -> the Swift parser stays tiny
  - each view translated so its viewBox starts at (0,0) (the source back view
    lives at x+724, female views at -50/-40 and 756)

Run: python3 scripts/extract-body-highlighter.py   (fetches from GitHub)
"""

import json
import math
import re
import urllib.request
from pathlib import Path

COMMIT = "15df9e2dbc621450001960bed5a30e6a75357faa"
BASE = f"https://raw.githubusercontent.com/HichamELBSI/react-native-body-highlighter/{COMMIT}/"
OUT = Path(__file__).resolve().parent.parent / "DriftCore/Sources/DriftCore/Resources/bodyDiagram.json"

# viewBoxes straight from the library source (SvgMaleWrapper / SvgFemaleWrapper).
VIEWBOXES = {
    "maleFront": (0, 0, 724, 1448),
    "maleBack": (724, 0, 724, 1448),
    "femaleFront": (-50, -40, 734, 1538),
    "femaleBack": (756, 0, 774, 1448),
}

# ---------------------------------------------------------------- SVG path math

_NUM = re.compile(r"[ \t\n,]*(-?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?)")
_FLAG = re.compile(r"[ \t\n,]*([01])")
_CMD = re.compile(r"[ \t\n,]*([MmLlHhVvCcSsQqTtAaZz])")

# args per command; arcs are special-cased (flags may be glued: "0 012.89"
# is rot=0, large-arc=0, sweep=1, x=2.89 — a naive number regex eats "12.89").
_ARGC = {"M": 2, "L": 2, "H": 1, "V": 1, "C": 6, "S": 4, "Q": 4, "T": 2, "Z": 0}


def _tokenize(d):
    """Command-aware scanner -> flat [cmd, n, n, ..., cmd, ...] list. Emits an
    explicit command token for every argument group (implicit repeats and
    M->L promotion are resolved here, so the consumer never guesses)."""
    out = []
    i = 0
    n = len(d)
    cmd = None
    while i < n:
        m = _CMD.match(d, i)
        if m:
            cmd = m.group(1)
            i = m.end()
        elif cmd is None:
            raise ValueError(f"path does not start with a command: {d[:20]!r}")
        elif cmd in ("M", "m"):  # implicit repeat of M = L
            cmd = "L" if cmd == "M" else "l"
        C = cmd.upper()
        if C == "Z":
            out.append(cmd)
            # Z takes no args; next iteration must find a command
            m2 = _CMD.match(d, i)
            if not m2 and d[i:].strip():
                raise ValueError(f"garbage after Z: {d[i:i+20]!r}")
            continue
        args = []
        if C == "A":
            for k in range(7):
                rx_ = _FLAG if k in (3, 4) else _NUM
                m2 = rx_.match(d, i)
                if not m2:
                    raise ValueError(f"bad arc args at {d[i:i+30]!r}")
                args.append(float(m2.group(1)))
                i = m2.end()
        else:
            for _ in range(_ARGC[C]):
                m2 = _NUM.match(d, i)
                if not m2:
                    raise ValueError(f"bad args for {cmd} at {d[i:i+30]!r}")
                args.append(float(m2.group(1)))
                i = m2.end()
        out.append(cmd)
        out.extend(args)
        # peek: if more numbers follow (no command), same cmd repeats
        if not _CMD.match(d, i) and not _NUM.match(d, i) and not _FLAG.match(d, i):
            if d[i:].strip():
                raise ValueError(f"unparsed tail: {d[i:i+30]!r}")
    return out


def _arc_to_cubics(x1, y1, rx, ry, phi_deg, large_arc, sweep, x2, y2):
    """Standard endpoint->center parameterization + arc->cubic Bezier split
    (SVG spec appendix B.2). Returns a list of (c1, c2, end) tuples."""
    if rx == 0 or ry == 0:
        return [((x1, y1), (x2, y2), (x2, y2))]
    phi = math.radians(phi_deg % 360)
    cosp, sinp = math.cos(phi), math.sin(phi)
    # to center parameterization
    dx2, dy2 = (x1 - x2) / 2.0, (y1 - y2) / 2.0
    x1p = cosp * dx2 + sinp * dy2
    y1p = -sinp * dx2 + cosp * dy2
    rx, ry = abs(rx), abs(ry)
    lam = (x1p / rx) ** 2 + (y1p / ry) ** 2
    if lam > 1:
        s = math.sqrt(lam)
        rx *= s
        ry *= s
    num = rx**2 * ry**2 - rx**2 * y1p**2 - ry**2 * x1p**2
    den = rx**2 * y1p**2 + ry**2 * x1p**2
    co = math.sqrt(max(0.0, num / den)) if den else 0.0
    if large_arc == sweep:
        co = -co
    cxp = co * rx * y1p / ry
    cyp = -co * ry * x1p / rx
    cx = cosp * cxp - sinp * cyp + (x1 + x2) / 2
    cy = sinp * cxp + cosp * cyp + (y1 + y2) / 2

    def angle(ux, uy, vx, vy):
        dot = ux * vx + uy * vy
        n = math.hypot(ux, uy) * math.hypot(vx, vy)
        a = math.acos(max(-1, min(1, dot / n)))
        return -a if ux * vy - uy * vx < 0 else a

    th1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    dth = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if not sweep and dth > 0:
        dth -= 2 * math.pi
    elif sweep and dth < 0:
        dth += 2 * math.pi

    nseg = max(1, int(math.ceil(abs(dth) / (math.pi / 2))))
    delta = dth / nseg
    t = 4 / 3 * math.tan(delta / 4)
    curves = []
    for i in range(nseg):
        a0 = th1 + i * delta
        a1 = a0 + delta
        c0, s0, c1s, s1s = math.cos(a0), math.sin(a0), math.cos(a1), math.sin(a1)

        def pt(a_c, a_s):
            return (
                cx + rx * cosp * a_c - ry * sinp * a_s,
                cy + rx * sinp * a_c + ry * cosp * a_s,
            )

        p0, p3 = pt(c0, s0), pt(c1s, s1s)
        d0 = (-rx * cosp * s0 - ry * sinp * c0, -rx * sinp * s0 + ry * cosp * c0)
        d1 = (-rx * cosp * s1s - ry * sinp * c1s, -rx * sinp * s1s + ry * cosp * c1s)
        c1p = (p0[0] + t * d0[0], p0[1] + t * d0[1])
        c2p = (p3[0] - t * d1[0], p3[1] - t * d1[1])
        curves.append((c1p, c2p, p3))
    return curves


def normalize_path(d, ox, oy):
    """Parse an SVG path-d string -> absolute M/L/C/Z command string, with
    (ox, oy) subtracted so the view's origin is (0,0)."""
    toks = _tokenize(d)
    i = 0
    cx = cy = sx = sy = 0.0  # current + subpath-start
    pcx = pcy = None  # previous control point (for S/T)
    prev_cmd = ""
    out = []

    def emit(cmd, *pts):
        coords = " ".join(f"{p[0]-ox:.2f} {p[1]-oy:.2f}" for p in pts)
        out.append(f"{cmd}{coords}")

    while i < len(toks):
        cmd = toks[i]  # _tokenize guarantees explicit command per arg group
        i += 1

        def take(n):
            nonlocal i
            vals = toks[i : i + n]
            i += n
            return vals

        rel = cmd.islower()
        C = cmd.upper()
        if C == "M":
            x, y = take(2)
            if rel:
                x += cx
                y += cy
            cx, cy, sx, sy = x, y, x, y
            emit("M", (x, y))
            pcx = pcy = None
        elif C == "L":
            x, y = take(2)
            if rel:
                x += cx
                y += cy
            cx, cy = x, y
            emit("L", (x, y))
            pcx = pcy = None
        elif C == "H":
            (x,) = take(1)
            if rel:
                x += cx
            cx = x
            emit("L", (x, cy))
            pcx = pcy = None
        elif C == "V":
            (y,) = take(1)
            if rel:
                y += cy
            cy = y
            emit("L", (cx, y))
            pcx = pcy = None
        elif C == "C":
            x1, y1, x2, y2, x, y = take(6)
            if rel:
                x1 += cx; y1 += cy; x2 += cx; y2 += cy; x += cx; y += cy
            emit("C", (x1, y1), (x2, y2), (x, y))
            pcx, pcy = x2, y2
            cx, cy = x, y
        elif C == "S":
            x2, y2, x, y = take(4)
            if rel:
                x2 += cx; y2 += cy; x += cx; y += cy
            if prev_cmd.upper() in ("C", "S") and pcx is not None:
                x1, y1 = 2 * cx - pcx, 2 * cy - pcy
            else:
                x1, y1 = cx, cy
            emit("C", (x1, y1), (x2, y2), (x, y))
            pcx, pcy = x2, y2
            cx, cy = x, y
        elif C == "Q":
            qx, qy, x, y = take(4)
            if rel:
                qx += cx; qy += cy; x += cx; y += cy
            # quadratic -> cubic
            c1 = (cx + 2 / 3 * (qx - cx), cy + 2 / 3 * (qy - cy))
            c2 = (x + 2 / 3 * (qx - x), y + 2 / 3 * (qy - y))
            emit("C", c1, c2, (x, y))
            pcx, pcy = qx, qy
            cx, cy = x, y
        elif C == "T":
            x, y = take(2)
            if rel:
                x += cx
                y += cy
            if prev_cmd.upper() in ("Q", "T") and pcx is not None:
                qx, qy = 2 * cx - pcx, 2 * cy - pcy
            else:
                qx, qy = cx, cy
            c1 = (cx + 2 / 3 * (qx - cx), cy + 2 / 3 * (qy - cy))
            c2 = (x + 2 / 3 * (qx - x), y + 2 / 3 * (qy - y))
            emit("C", c1, c2, (x, y))
            pcx, pcy = qx, qy
            cx, cy = x, y
        elif C == "A":
            rx, ry, rot, laf, swf, x, y = take(7)
            if rel:
                x += cx
                y += cy
            for c1p, c2p, end in _arc_to_cubics(cx, cy, rx, ry, rot, int(laf), int(swf), x, y):
                emit("C", c1p, c2p, end)
            cx, cy = x, y
            pcx = pcy = None
        elif C == "Z":
            out.append("Z")
            cx, cy = sx, sy
            pcx = pcy = None
        else:
            raise ValueError(f"unsupported command {cmd}")
        prev_cmd = cmd
    return "".join(out)


# ---------------------------------------------------------------- TS extraction


def fetch(path):
    with urllib.request.urlopen(BASE + path) as r:
        return r.read().decode()


def parse_body_ts(src):
    """assets/*.ts -> {slug: [d-strings]} (left/right/common merged)."""
    muscles = {}
    for m in re.finditer(r'slug:\s*"([^"]+)"(.*?)(?=slug:\s*"|\Z)', src, re.S):
        slug, block = m.group(1), m.group(2)
        paths = re.findall(r'"((?:[^"\\]|\\.)*?)"', block)
        # keep only path-looking strings (start with M/m), drop colors etc.
        ds = [p for p in paths if p[:1] in ("M", "m")]
        if ds:
            muscles.setdefault(slug, []).extend(ds)
    return muscles


def parse_wrapper_tsx(src, side):
    """SvgMale/FemaleWrapper.tsx -> outline d-strings for the given side."""
    # Each side's <Path ... d="..." .../> sits inside a `side === "front"` block.
    blocks = re.split(r'side\s*===\s*"(front|back)"', src)
    outline = []
    for i in range(1, len(blocks), 2):
        if blocks[i] == side:
            outline += re.findall(r'd="([^"]+)"', blocks[i + 1])
    return outline


def build():
    files = {
        "maleFront": ("assets/bodyFront.ts", "components/SvgMaleWrapper.tsx", "front"),
        "maleBack": ("assets/bodyBack.ts", "components/SvgMaleWrapper.tsx", "back"),
        "femaleFront": ("assets/bodyFemaleFront.ts", "components/SvgFemaleWrapper.tsx", "front"),
        "femaleBack": ("assets/bodyFemaleBack.ts", "components/SvgFemaleWrapper.tsx", "back"),
    }
    wrappers = {}
    models = {}
    for key, (data_path, wrapper_path, side) in files.items():
        ox, oy, w, h = VIEWBOXES[key]
        muscles_raw = parse_body_ts(fetch(data_path))
        if wrapper_path not in wrappers:
            wrappers[wrapper_path] = fetch(wrapper_path)
        outline_raw = parse_wrapper_tsx(wrappers[wrapper_path], side)
        models[key] = {
            "viewBox": [w, h],
            "outline": [normalize_path(d, ox, oy) for d in outline_raw],
            "muscles": {
                slug: [normalize_path(d, ox, oy) for d in ds]
                for slug, ds in sorted(muscles_raw.items())
            },
        }
        print(f"{key}: {len(models[key]['muscles'])} muscle slugs, "
              f"{sum(len(v) for v in models[key]['muscles'].values())} paths, "
              f"{len(models[key]['outline'])} outline paths")
    doc = {
        "source": "react-native-body-highlighter",
        "commit": COMMIT,
        "license": "MIT (c) 2022 ELABBASSI Hicham",
        "models": models,
    }
    OUT.write_text(json.dumps(doc, separators=(",", ":")))
    print(f"wrote {OUT} ({OUT.stat().st_size/1024:.0f} KB)")


if __name__ == "__main__":
    build()

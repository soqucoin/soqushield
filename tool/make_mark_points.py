#!/usr/bin/env python3
"""Writes lib/theme/mark_points.dart: the Soqucoin mark as a set of points.

The splash draws the mark the way the site's scene does (soqu-web-next,
site/js/lattice.js, formLogo): points picked from the mark's own pixels on a
256 grid. The site samples at run time; the app ships the sample, so the
splash needs no image decode before its first frame and is the same on every
launch.

    python3 tool/make_mark_points.py path/to/soqucoin-mark.svg

The input is soqucoin-sites/soqu-web/images/soqucoin-mark.svg, pinned by hash.
The output is reproducible byte for byte (Pillow rasterises; the pick is
seeded). Needs Pillow.
"""

import base64
import hashlib
import random
import re
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

SVG_SHA256 = "39e3299f4f2f1628a822352eff847c295ad38d912914854b8d38d020cde2c016"
GRID = 256        # the site's sampling grid
SUPER = 8         # rasterise at GRID * SUPER, then keep cells more than half covered
COUNT = 2000      # points written, in an order where any prefix is evenly spread
MIN_GAP = 2.5     # grid cells between any two points
SEED = 20261013
OUT = Path(__file__).resolve().parent.parent / "lib" / "theme" / "mark_points.dart"


def subpaths(d):
    """Flatten one path's data (M m L l C c Z z) into closed polygons."""
    tokens = re.findall(r"[MmLlCcZz]|-?\d*\.?\d+(?:[eE][-+]?\d+)?", d)
    out, poly, i, cmd = [], [], 0, None
    x = y = sx = sy = 0.0

    def num():
        nonlocal i
        v = float(tokens[i])
        i += 1
        return v

    while i < len(tokens):
        if tokens[i].isalpha():
            cmd = tokens[i]
            i += 1
            if cmd in "Zz":
                if poly:
                    out.append(poly)
                poly, x, y = [], sx, sy
                continue
        if cmd in "Mm":
            nx, ny = num(), num()
            if cmd == "m":
                nx, ny = x + nx, y + ny
            if poly:
                out.append(poly)
            x, y, sx, sy = nx, ny, nx, ny
            poly = [(x, y)]
            cmd = "L" if cmd == "M" else "l"   # further pairs are line-tos
        elif cmd in "Ll":
            nx, ny = num(), num()
            if cmd == "l":
                nx, ny = x + nx, y + ny
            x, y = nx, ny
            poly.append((x, y))
        elif cmd in "Cc":
            c = [num() for _ in range(6)]
            if cmd == "c":
                c = [c[0] + x, c[1] + y, c[2] + x, c[3] + y, c[4] + x, c[5] + y]
            for s in range(1, 13):
                t = s / 12
                u = 1 - t
                poly.append((
                    u * u * u * x + 3 * u * u * t * c[0] + 3 * u * t * t * c[2] + t * t * t * c[4],
                    u * u * u * y + 3 * u * u * t * c[1] + 3 * u * t * t * c[3] + t * t * t * c[5],
                ))
            x, y = c[4], c[5]
        else:
            raise SystemExit(f"unsupported path command {cmd!r}")
    if poly:
        out.append(poly)
    return out


def rasterise(svg):
    vb = [float(v) for v in re.search(r'viewBox="([^"]+)"', svg).group(1).split()]
    tr = re.search(r"translate\(([-\d.]+),([-\d.]+)\) scale\(([-\d.]+),([-\d.]+)\)", svg)
    tx, ty, kx, ky = (float(v) for v in tr.groups())
    size = GRID * SUPER
    k = size / max(vb[2], vb[3])                      # xMidYMid meet
    ox, oy = (size - vb[2] * k) / 2, (size - vb[3] * k) / 2
    mask = Image.new("1", (size, size), 0)
    # the trace nests its outlines; even-odd over every outline is its fill
    for d in re.findall(r'<path d="([^"]+)"', svg):
        for poly in subpaths(d):
            layer = Image.new("1", (size, size), 0)
            ImageDraw.Draw(layer).polygon(
                [((tx + kx * px - vb[0]) * k + ox, (ty + ky * py - vb[1]) * k + oy) for px, py in poly], fill=1)
            mask = ImageChops.logical_xor(mask, layer)
    small = mask.convert("L").resize((GRID, GRID), Image.BOX)
    return [(x, y) for y in range(GRID) for x in range(GRID) if small.getpixel((x, y)) > 127]


def pick(cells):
    """COUNT cells, no two closer than MIN_GAP, so the mark reads evenly at a low count."""
    rng = random.Random(SEED)
    rng.shuffle(cells)
    taken, bins, gap2 = [], {}, MIN_GAP * MIN_GAP
    for x, y in cells:
        bx, by = x // 3, y // 3
        if any((x - px) ** 2 + (y - py) ** 2 < gap2
               for ax in (bx - 1, bx, bx + 1) for ay in (by - 1, by, by + 1)
               for px, py in bins.get((ax, ay), ())):
            continue
        bins.setdefault((bx, by), []).append((x, y))
        taken.append((x, y))
        if len(taken) == COUNT:
            return taken
    raise SystemExit(f"only {len(taken)} points fit at MIN_GAP {MIN_GAP}")


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    raw = Path(sys.argv[1]).read_bytes()
    if hashlib.sha256(raw).hexdigest() != SVG_SHA256:
        raise SystemExit("the mark's hash does not match SVG_SHA256")
    points = pick(rasterise(raw.decode("utf-8")))
    data = base64.b64encode(bytes(v for p in points for v in p)).decode("ascii")
    lines = "\n".join(f"    '{data[i:i + 72]}'" for i in range(0, len(data), 72))
    OUT.write_text(f"""// GENERATED by tool/make_mark_points.py. Do not edit by hand.
//
// The Soqucoin mark as {COUNT} points on a {GRID} grid, picked from the mark's own
// pixels (soqucoin-mark.svg, SHA-256
// {SVG_SHA256}).
// Any prefix of the list is spread evenly over the mark.
//
// Copyright 2026 Soqucoin Labs Inc.

import 'dart:convert';
import 'dart:typed_data';

/// The side of the grid the points sit on.
const int kMarkGrid = {GRID};

/// x, y pairs, one byte each, y down.
final Uint8List kMarkPoints = base64Decode(_data);

const String _data =
{lines};
""")
    print(f"{OUT}: {len(points)} points")


if __name__ == "__main__":
    main()

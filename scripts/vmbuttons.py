#!/usr/bin/env python3
"""Locate white-on-blue WinRE buttons/tiles in a guest screenshot.

WinRE draws white text and 1px white borders on a flat blue background, so
thresholding to pure white and clustering the survivors yields clickable
targets without any OCR dependency.

Usage: vmbuttons.py SCREENSHOT.png [min-y] [max-y]
"""
import re
import subprocess
import sys

WHITE = re.compile(r"^(\d+),(\d+):.*#([0-9A-Fa-f]{6})")


def white_pixels(path):
    out = subprocess.run(
        ["magick", path, "-colorspace", "gray", "-threshold", "70%", "txt:-"],
        capture_output=True, text=True, check=True).stdout
    pts = []
    for line in out.splitlines()[1:]:
        m = WHITE.match(line)
        if m and m.group(3).upper() == "FFFFFF":
            pts.append((int(m.group(1)), int(m.group(2))))
    return pts


def cluster(values, gap):
    groups = []
    for v in sorted(set(values)):
        if groups and v - groups[-1][-1] <= gap:
            groups[-1].append(v)
        else:
            groups.append([v])
    return groups


def main():
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    path = sys.argv[1]
    min_y = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    max_y = int(sys.argv[3]) if len(sys.argv) > 3 else 10 ** 6

    pts = [(x, y) for x, y in white_pixels(path) if min_y <= y <= max_y]
    if not pts:
        print("no white pixels in range")
        return 1

    for band in cluster([y for _, y in pts], 4):
        rows = [(x, y) for x, y in pts if band[0] <= y <= band[-1]]
        for col in cluster([x for x, _ in rows], 15):
            sel = [(x, y) for x, y in rows if col[0] <= x <= col[-1]]
            xs = [x for x, _ in sel]
            ys = [y for _, y in sel]
            cx = (min(xs) + max(xs)) // 2
            cy = (min(ys) + max(ys)) // 2
            print(f"x={min(xs)}-{max(xs)} y={min(ys)}-{max(ys)} "
                  f"center=({cx},{cy}) px={len(sel)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

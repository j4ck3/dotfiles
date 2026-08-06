#!/usr/bin/env python3
"""Click at absolute guest pixel coordinates and capture the result.

HMP `mouse_move` only queues relative motion, which a PS/2 mouse consumes with
pointer acceleration applied, so it cannot hit a target reliably. QMP
`input-send-event` with abs axes addresses the absolute pointer (usb tablet)
directly; axis values are a 0..32767 fraction of the display.

Usage: vmclick.py X Y [--name shot] [--settle 4] [--move-only]
"""
import argparse
import json
import subprocess
import sys
import time

ABS_MAX = 32767
URI = "qemu:///system"


def qmp(domain, command):
    subprocess.run(
        ["virsh", "-c", URI, "qemu-monitor-command", domain, json.dumps(command)],
        check=True, capture_output=True, text=True)


def screen_size(domain):
    ppm = "/tmp/.vmclick-probe.ppm"
    subprocess.run(["virsh", "-c", URI, "screenshot", domain, ppm],
                   check=True, capture_output=True)
    out = subprocess.run(["magick", "identify", "-format", "%w %h", ppm],
                         check=True, capture_output=True, text=True).stdout
    w, h = out.split()
    return int(w), int(h)


def send_events(domain, events):
    qmp(domain, {"execute": "input-send-event", "arguments": {"events": events}})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("x", type=int)
    ap.add_argument("y", type=int)
    ap.add_argument("--domain", default="windows11-stealth")
    ap.add_argument("--name", default="click")
    ap.add_argument("--settle", type=float, default=4.0)
    ap.add_argument("--move-only", action="store_true")
    args = ap.parse_args()

    w, h = screen_size(args.domain)
    ax = round(args.x / (w - 1) * ABS_MAX)
    ay = round(args.y / (h - 1) * ABS_MAX)
    print(f"display {w}x{h}: ({args.x},{args.y}) -> abs ({ax},{ay})")

    send_events(args.domain, [
        {"type": "abs", "data": {"axis": "x", "value": ax}},
        {"type": "abs", "data": {"axis": "y", "value": ay}},
    ])
    time.sleep(0.6)

    if not args.move_only:
        send_events(args.domain, [
            {"type": "btn", "data": {"down": True, "button": "left"}}])
        time.sleep(0.15)
        send_events(args.domain, [
            {"type": "btn", "data": {"down": False, "button": "left"}}])

    time.sleep(args.settle)

    ppm = f"/tmp/{args.name}.ppm"
    png = f"/tmp/{args.name}.png"
    subprocess.run(["virsh", "-c", URI, "screenshot", args.domain, ppm],
                   check=True, capture_output=True)
    subprocess.run(["magick", ppm, png], check=True, capture_output=True)
    colors = subprocess.run(["magick", "identify", "-format", "%k", png],
                            capture_output=True, text=True).stdout.strip()
    print(f"{'moved' if args.move_only else 'clicked'} -> {png} colors={colors}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

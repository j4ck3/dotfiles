#!/usr/bin/env python3
"""UltralightX battery via dongle HID (same protocol as xpanel.finalmouse.com)."""
from __future__ import annotations

import json
import os
import select
import sys
import time
from pathlib import Path

VID = 0x361D
PID = 0x0100
REPORT_OUT = 4
REPORT_IN = 5
PKT = 64
CMD_VBAT = 5
CMD_CHARGING = 37
TIMEOUT_S = 0.25

# Xpanel voltage→% curve (ZBMmZATE.js ns()).
VOLTS = (3.0, 3.62, 3.66, 3.74, 3.88, 4.17, 4.38)
PCTS = (0.2, 5.0, 10.0, 25.0, 50.0, 75.0, 100.0)

OFFLINE = {
    "ok": False,
    "pct": None,
    "mv": None,
    "charging": None,
    "display": "--",
    "error": "offline",
}


def emit(payload: dict) -> None:
    sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")


def find_hidraw() -> Path | None:
    root = Path("/sys/class/hidraw")
    if not root.is_dir():
        return None
    needle = f"v{VID:08X}p{PID:08X}".lower()
    for node in sorted(root.iterdir()):
        uevent = node / "device" / "uevent"
        try:
            txt = uevent.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        if needle in txt.lower() or "Finalmouse UltralightX dongle" in txt:
            return Path("/dev") / node.name
    return None


def voltage_pct(mv: int) -> int:
    s = mv / 1000.0
    if s > VOLTS[-1]:
        return 100
    if s < VOLTS[0]:
        return 0
    for i in range(len(VOLTS) - 1):
        lo, hi = VOLTS[i], VOLTS[i + 1]
        if lo <= s <= hi:
            t = (s - lo) / (hi - lo)
            return round(PCTS[i] + (PCTS[i + 1] - PCTS[i]) * t)
    return 100


def make_cmd(cmd: int, payload: bytes = b"") -> bytes:
    buf = bytearray(PKT)
    buf[0] = REPORT_OUT
    n = len(payload)
    buf[1] = 2 + n
    buf[2] = 0x80 | cmd
    buf[3] = n
    if n:
        buf[4 : 4 + n] = payload
    return bytes(buf)


def parse_vendor(data: bytes, cmd: int) -> bytes | None:
    if len(data) < 5 or data[0] != REPORT_IN:
        return None
    if (data[2] & 127) != cmd:
        return None
    plen = data[3]
    return data[4 : 4 + plen]


def transact(fd: int, cmd: int) -> bytes | None:
    os.write(fd, make_cmd(cmd))
    end = time.monotonic() + TIMEOUT_S
    while True:
        remain = end - time.monotonic()
        if remain <= 0:
            return None
        ready, _, _ = select.select([fd], [], [], remain)
        if not ready:
            return None
        try:
            data = os.read(fd, PKT)
        except BlockingIOError:
            continue
        payload = parse_vendor(data, cmd)
        if payload is not None:
            return payload


def query(path: Path) -> dict | None:
    fd = os.open(path, os.O_RDWR | os.O_NONBLOCK)
    try:
        vbat = transact(fd, CMD_VBAT)
        if vbat is None or len(vbat) < 2:
            return None
        mv = vbat[0] | (vbat[1] << 8)
        charging = None
        chg = transact(fd, CMD_CHARGING)
        if chg is not None and len(chg) >= 1:
            charging = bool(chg[0])
        pct = voltage_pct(mv)
        return {"mv": mv, "pct": pct, "charging": charging}
    finally:
        os.close(fd)


def main() -> int:
    path = find_hidraw()
    if path is None or not path.exists():
        emit(OFFLINE)
        return 0
    try:
        info = query(path)
    except OSError:
        emit(OFFLINE)
        return 0
    if not info:
        emit(OFFLINE)
        return 0

    pct = info["pct"]
    mv = info["mv"]
    charging = info["charging"]
    emit(
        {
            "ok": True,
            "pct": pct,
            "mv": mv,
            "charging": charging,
            "display": f"{pct}%",
            "error": "",
        }
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BrokenPipeError:
        raise SystemExit(0)

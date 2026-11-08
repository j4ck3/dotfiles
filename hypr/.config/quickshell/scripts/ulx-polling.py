#!/usr/bin/env python3
"""UltralightX polling rate via dongle HID (same protocol as xpanel.finalmouse.com).

Usage:
  ulx-polling.py            print current rate as JSON
  ulx-polling.py set HZ     set rate (500/1000/2000/4000/8000), then print JSON
"""
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
CMD_GET_POLLING = 4  # ULX dongle read-back (CMD_ID_ULX_GET_POLLING_RATE)
CMD_MOUSE_FW = 12
CMD_SET_POLLING = 17  # CMD_ID_POLLING_RATE, payload uint16 LE
TIMEOUT_S = 0.4
SETTLE_S = 1.5
RATES = (500, 1000, 2000, 4000, 8000)


def emit(payload: dict) -> None:
    sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")


def offline(error: str = "offline") -> dict:
    return {"ok": False, "hz": None, "rates": list(RATES), "max": 4000, "fw": "", "error": error}


def find_hidraw() -> Path | None:
    root = Path("/sys/class/hidraw")
    if not root.is_dir():
        return None
    needle = f"v{VID:08X}p{PID:08X}".lower()
    for node in sorted(root.iterdir()):
        try:
            txt = (node / "device" / "uevent").read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        if needle in txt.lower() or "Finalmouse UltralightX dongle" in txt:
            return Path("/dev") / node.name
    return None


def make_cmd(cmd: int, payload: bytes = b"") -> bytes:
    buf = bytearray(PKT)
    buf[0] = REPORT_OUT
    buf[1] = 2 + len(payload)
    buf[2] = 0x80 | cmd
    buf[3] = len(payload)
    buf[4 : 4 + len(payload)] = payload
    return bytes(buf)


def read_reply(fd: int, cmd: int) -> bytes | None:
    end = time.monotonic() + TIMEOUT_S
    while (remain := end - time.monotonic()) > 0:
        ready, _, _ = select.select([fd], [], [], remain)
        if not ready:
            return None
        try:
            data = os.read(fd, PKT)
        except BlockingIOError:
            continue
        if len(data) >= 5 and data[0] == REPORT_IN and (data[2] & 0x7F) == cmd:
            return data[4 : 4 + data[3]]
    return None


def transact(fd: int, cmd: int, payload: bytes = b"") -> bytes | None:
    os.write(fd, make_cmd(cmd, payload))
    return read_reply(fd, cmd)


def get_rate(fd: int) -> int | None:
    reply = transact(fd, CMD_GET_POLLING)
    if reply is None or len(reply) < 2:
        return None
    return reply[0] | (reply[1] << 8)


def get_fw(fd: int) -> str:
    reply = transact(fd, CMD_MOUSE_FW)
    if not reply:
        return ""
    return reply.split(b"\0", 1)[0].decode("ascii", errors="ignore")


def main(argv: list[str]) -> int:
    want: int | None = None
    if argv[:1] == ["set"]:
        try:
            want = int(argv[1])
        except (IndexError, ValueError):
            want = -1
        if want not in RATES:
            emit(offline(f"unsupported rate {argv[1:2]}"))
            return 2
    elif argv:
        emit(offline("usage: ulx-polling.py [set HZ]"))
        return 2

    path = find_hidraw()
    if path is None or not path.exists():
        emit(offline())
        return 0
    try:
        fd = os.open(path, os.O_RDWR | os.O_NONBLOCK)
    except OSError as exc:
        emit(offline(exc.strerror or "open failed"))
        return 0
    try:
        fw = get_fw(fd)
        # Xpanel only offers 8000 Hz on mouse firmware 8.x.
        max_hz = 8000 if fw.startswith("8.") else 4000
        if want is not None:
            if want > max_hz:
                emit({**offline(f"{want} Hz needs mouse fw 8.x"), "fw": fw})
                return 0
            os.write(fd, make_cmd(CMD_SET_POLLING, want.to_bytes(2, "little")))
            read_reply(fd, CMD_SET_POLLING)
            # The mouse applies the new rate over RF ~100-200 ms after the ack.
            deadline = time.monotonic() + SETTLE_S
            while (hz := get_rate(fd)) != want and time.monotonic() < deadline:
                time.sleep(0.05)
        else:
            hz = get_rate(fd)
    except OSError as exc:
        emit(offline(exc.strerror or "hid error"))
        return 0
    finally:
        os.close(fd)

    if hz is None:
        emit({**offline("no reply (mouse asleep?)"), "fw": fw})
        return 0
    err = "" if want is None or hz == want else f"asked {want}, mouse reports {hz}"
    emit({"ok": True, "hz": hz, "rates": list(RATES), "max": max_hz, "fw": fw, "error": err})
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except BrokenPipeError:
        raise SystemExit(0)

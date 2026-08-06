#!/usr/bin/env python3
"""Send keystrokes to a libvirt domain and capture the resulting screen.

Helper for driving a guest that only has a graphical console (e.g. Windows RE),
where no guest agent or serial console is available.
"""

import argparse
import subprocess
import sys
import time

DOMAIN_DEFAULT = "windows11-stealth"

PLAIN = {
    "\n": "KEY_ENTER",
    "\t": "KEY_TAB",
    " ": "KEY_SPACE",
    "-": "KEY_MINUS",
    "=": "KEY_EQUAL",
    "[": "KEY_LEFTBRACE",
    "]": "KEY_RIGHTBRACE",
    ";": "KEY_SEMICOLON",
    "'": "KEY_APOSTROPHE",
    "`": "KEY_GRAVE",
    "\\": "KEY_BACKSLASH",
    ",": "KEY_COMMA",
    ".": "KEY_DOT",
    "/": "KEY_SLASH",
}

SHIFTED = {
    "!": "KEY_1",
    "@": "KEY_2",
    "#": "KEY_3",
    "$": "KEY_4",
    "%": "KEY_5",
    "^": "KEY_6",
    "&": "KEY_7",
    "*": "KEY_8",
    "(": "KEY_9",
    ")": "KEY_0",
    "_": "KEY_MINUS",
    "+": "KEY_EQUAL",
    "{": "KEY_LEFTBRACE",
    "}": "KEY_RIGHTBRACE",
    ":": "KEY_SEMICOLON",
    '"': "KEY_APOSTROPHE",
    "~": "KEY_GRAVE",
    "|": "KEY_BACKSLASH",
    "<": "KEY_COMMA",
    ">": "KEY_DOT",
    "?": "KEY_SLASH",
}


def keys_for(char):
    if char.isdigit():
        return ["KEY_" + char]
    if char.isalpha():
        code = "KEY_" + char.upper()
        return ["KEY_LEFTSHIFT", code] if char.isupper() else [code]
    if char in PLAIN:
        return [PLAIN[char]]
    if char in SHIFTED:
        return ["KEY_LEFTSHIFT", SHIFTED[char]]
    raise ValueError(f"unmapped character: {char!r}")


def send(domain, keys, delay):
    subprocess.run(
        ["virsh", "-c", "qemu:///system", "send-key", domain, "--codeset", "linux", *keys],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    time.sleep(delay)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--domain", default=DOMAIN_DEFAULT)
    parser.add_argument("--delay", type=float, default=0.12)
    parser.add_argument("--text", help="literal text to type")
    parser.add_argument("--key", action="append", default=[],
                        help="raw KEY_* name, repeatable; use +A+B for a chord")
    args = parser.parse_args()

    for spec in args.key:
        send(args.domain, spec.split("+"), args.delay)

    for char in args.text or "":
        try:
            send(args.domain, keys_for(char), args.delay)
        except ValueError as exc:
            print(exc, file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

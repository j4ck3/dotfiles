#!/usr/bin/env python3
"""Resolve evdev fragment paths (supports globs) and merge into libvirt domain XML."""
from __future__ import annotations

import copy
import glob
import os
import sys
import xml.etree.ElementTree as ET


def resolve_dev(dev: str) -> list[str]:
    if any(ch in dev for ch in "*?[]"):
        return sorted(path for path in glob.glob(dev) if os.path.exists(path))
    return [dev] if os.path.exists(dev) else []


def expand_fragment_inputs(fragment_path: str) -> tuple[list[ET.Element], list[str]]:
    fragment = ET.fromstring(
        f"<devices>{open(fragment_path, encoding='utf-8').read()}</devices>"
    )
    inputs: list[ET.Element] = []
    skipped: list[str] = []
    for inp in fragment.findall("input"):
        source = inp.find("source")
        if source is None:
            continue
        dev = source.get("dev")
        if not dev:
            continue
        resolved = resolve_dev(dev)
        if not resolved:
            skipped.append(dev)
            continue
        for path in resolved:
            node = copy.deepcopy(inp)
            node.find("source").set("dev", path)
            inputs.append(node)
    return inputs, skipped


def merge_evdev_inputs(
    devices: ET.Element,
    fragment_path: str,
    *,
    replace: bool = False,
) -> tuple[bool, list[str]]:
    if replace:
        for inp in list(devices.findall("input")):
            devices.remove(inp)
    else:
        for inp in list(devices.findall("input")):
            if inp.get("type") != "evdev":
                continue
            source = inp.find("source")
            dev = source.get("dev") if source is not None else None
            if not dev or not os.path.exists(dev):
                devices.remove(inp)

    existing = {
        source.get("dev")
        for inp in devices.findall("input")
        if inp.get("type") == "evdev"
        for source in [inp.find("source")]
        if source is not None and source.get("dev")
    }
    changed = False
    new_inputs, skipped = expand_fragment_inputs(fragment_path)
    for inp in new_inputs:
        dev = inp.find("source").get("dev")
        if dev in existing:
            continue
        devices.append(inp)
        existing.add(dev)
        changed = True
    return changed, skipped


def main() -> None:
    if len(sys.argv) != 4:
        print(
            f"Usage: {sys.argv[0]} <domain.xml> <evdev-fragment.xml> <out.xml>",
            file=sys.stderr,
        )
        sys.exit(2)
    domain_path, fragment_path, out_path = sys.argv[1:4]
    tree = ET.parse(domain_path)
    root = tree.getroot()
    devices = root.find("devices")
    if devices is None:
        print("no <devices> in domain XML", file=sys.stderr)
        sys.exit(1)
    _, skipped = merge_evdev_inputs(devices, fragment_path)
    if skipped:
        print("Skipped missing evdev devices:", file=sys.stderr)
        for dev in skipped:
            print(f"  {dev}", file=sys.stderr)
    tree.write(out_path, encoding="unicode", xml_declaration=True)


if __name__ == "__main__":
    main()

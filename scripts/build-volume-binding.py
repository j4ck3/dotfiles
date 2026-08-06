#!/usr/bin/env python3
"""Rebuild the Volume class driver bindings that stealth hardening stripped.

The STORAGE\\Volume device nodes lost their ClassGUID/Driver values and were
flagged CONFIGFLAG_REINSTALL, so PnP treats them as uninstalled and cannot
start them at boot. This regenerates the Volume class subtree from a donor
hive and re-points each node at a driver instance.

Writes a .reg fragment; merge it with hivexregedit.
"""

import subprocess
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from regf import Hive  # noqa: E402

VOLUME_CLASS = "{71a27cdd-812a-11d0-bec7-08002be2092f}"
PREFIX = r"HKEY_LOCAL_MACHINE\SYSTEM"


def control_set(hive):
    return f"ControlSet{hive.key('Select').value('Current').value():03d}"


def export_class(donor_path, cs):
    out = subprocess.check_output([
        "hivexregedit", "--export", "--prefix", PREFIX,
        donor_path, f"{cs}\\Control\\Class\\{VOLUME_CLASS}",
    ], text=True)
    return out


def split_blocks(reg_text):
    header, blocks, current = [], [], None
    for line in reg_text.splitlines():
        if line.startswith("["):
            if current:
                blocks.append(current)
            current = [line]
        elif current is not None:
            current.append(line)
        else:
            header.append(line)
    if current:
        blocks.append(current)
    return header, blocks


def main():
    donor_path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/w11ctl/hives/SYSTEM"
    target_path = sys.argv[2] if len(sys.argv) > 2 else "/tmp/SYSTEM.repaired2"
    out_path = sys.argv[3] if len(sys.argv) > 3 else "/tmp/volbind.reg"

    donor = Hive(donor_path)
    target = Hive(target_path)
    dcs, tcs = control_set(donor), control_set(target)

    nodes = []
    vol_root = target.key(f"{tcs}\\Enum\\STORAGE\\Volume")
    for node in vol_root.subkeys():
        svc = node.value("Service")
        if svc and str(svc.value()).lower() == "volume":
            nodes.append(node.name)
    print(f"volume device nodes needing bindings: {len(nodes)}")

    reg = export_class(donor_path, dcs)
    header, blocks = split_blocks(reg)

    # Only keys exactly one level below the class GUID are driver instances;
    # the Properties subtree also contains numeric-looking key names.
    class_root = f"\\Control\\Class\\{VOLUME_CLASS}\\"
    template = None
    existing = []
    for block in blocks:
        key = block[0].rstrip("]")
        if class_root not in key:
            continue
        rest = key.split(class_root, 1)[1]
        if "\\" in rest or len(rest) != 4 or not rest.isdigit():
            continue
        existing.append(rest)
        if template is None:
            template = block
    print(f"donor class instances: {existing}")

    lines = list(header)
    for block in blocks:
        lines.extend(block)

    # One driver instance per device node; clone the template for any extras.
    needed = [f"{i:04d}" for i in range(len(nodes))]
    for inst in needed:
        if inst in existing:
            continue
        cloned = list(template)
        cloned[0] = (f"[{PREFIX}\\{tcs}\\Control\\Class\\{VOLUME_CLASS}\\{inst}]")
        lines.append("")
        lines.extend(cloned)
        print(f"  cloned driver instance {inst}")

    for inst, node in zip(needed, nodes):
        lines.append("")
        lines.append(f"[{PREFIX}\\{tcs}\\Enum\\STORAGE\\Volume\\{node}]")
        lines.append(f'"ClassGUID"="{VOLUME_CLASS}"')
        lines.append(f'"Driver"="{VOLUME_CLASS}\\\\{inst}"')
        lines.append('"ConfigFlags"=dword:00000000')
        print(f"  bind {node} -> {inst}")

    with open(out_path, "w") as handle:
        handle.write("\n".join(lines) + "\n")
    print(f"\nwrote {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Restore device-node driver bindings that stealth hardening stripped.

The hardening fingerprint on a gutted node is: ClassGUID and Driver deleted,
ConfigFlags set to 32 (CONFIGFLAG_REINSTALL) and InstallFlags added, which
makes PnP treat an installed device as needing reinstallation. When that is
done to a node in the boot path the kernel cannot reach the boot volume.

This copies the ClassGUID/Driver/ConfigFlags a donor hive of the same build
records for the same node paths, restores any device setup class the target is
missing, and clears the REINSTALL bit elsewhere on request.

Writes a .reg fragment; merge it with hivexregedit.

Usage:
  build-node-binding.py --donor HIVE --target HIVE --out FILE
                        [--node 'ROOT\\ACPI_HAL\\0000']...
                        [--clear-reinstall 'ROOT\\vdrvroot\\0000']...
"""

import argparse
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from regf import Hive  # noqa: E402

PREFIX = r"HKEY_LOCAL_MACHINE\SYSTEM"


def control_set(hive):
    return f"ControlSet{hive.key('Select').value('Current').value():03d}"


def export_key(hive_path, key_path):
    return subprocess.check_output(
        ["hivexregedit", "--export", "--prefix", PREFIX, hive_path, key_path],
        text=True)


def reg_escape(text):
    return text.replace("\\", "\\\\").replace('"', '\\"')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--donor", default="/tmp/w11ctl/hives/SYSTEM")
    ap.add_argument("--target", default="/tmp/SYSTEM.repaired3")
    ap.add_argument("--out", default="/tmp/nodebind.reg")
    ap.add_argument("--node", action="append", default=[],
                    help="Enum-relative node path to rebind from the donor")
    ap.add_argument("--clear-reinstall", action="append", default=[],
                    help="Enum-relative node path to clear REINSTALL on")
    args = ap.parse_args()

    donor = Hive(args.donor)
    target = Hive(args.target)
    dcs, tcs = control_set(donor), control_set(target)

    lines = ["Windows Registry Editor Version 5.00", ""]
    classes_needed = {}

    for node in args.node:
        dk = donor.key(f"{dcs}\\Enum\\{node}")
        tk = target.key(f"{tcs}\\Enum\\{node}")
        if dk is None:
            print(f"SKIP {node}: absent from donor")
            continue
        if tk is None:
            print(f"SKIP {node}: absent from target")
            continue
        cg = dk.value("ClassGUID")
        dv = dk.value("Driver")
        if not cg or not dv:
            print(f"SKIP {node}: donor node has no binding")
            continue
        guid = str(cg.value())
        classes_needed.setdefault(guid, [])

        lines.append(f"[{PREFIX}\\{tcs}\\Enum\\{node}]")
        lines.append(f'"ClassGUID"="{reg_escape(guid)}"')
        lines.append(f'"Driver"="{reg_escape(str(dv.value()))}"')
        lines.append('"ConfigFlags"=dword:00000000')
        if tk.value("InstallFlags") is not None:
            lines.append('"InstallFlags"=dword:00000000')
        lines.append("")
        print(f"bind {node} -> {dv.value()}")

    for node in args.clear_reinstall:
        tk = target.key(f"{tcs}\\Enum\\{node}")
        if tk is None:
            print(f"SKIP clear {node}: absent from target")
            continue
        cf = tk.value("ConfigFlags")
        current = cf.value() if cf else 0
        cleared = current & ~0x20
        lines.append(f"[{PREFIX}\\{tcs}\\Enum\\{node}]")
        lines.append(f'"ConfigFlags"=dword:{cleared:08x}')
        if tk.value("InstallFlags") is not None:
            lines.append('"InstallFlags"=dword:00000000')
        lines.append("")
        print(f"clear REINSTALL {node}: {current} -> {cleared}")

    # A binding is inert unless the setup class it points at exists.
    for guid in classes_needed:
        if target.key(f"{tcs}\\Control\\Class\\{guid}") is not None:
            print(f"class {guid} already present in target")
            continue
        print(f"restoring missing class {guid} from donor")
        exported = export_key(args.donor, f"{dcs}\\Control\\Class\\{guid}")
        for line in exported.splitlines():
            if line.startswith("Windows Registry Editor"):
                continue
            if line.startswith("[") and dcs != tcs:
                line = line.replace(f"\\{dcs}\\", f"\\{tcs}\\", 1)
            lines.append(line)
        lines.append("")

    with open(args.out, "w") as handle:
        handle.write("\n".join(lines) + "\n")
    print(f"\nwrote {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

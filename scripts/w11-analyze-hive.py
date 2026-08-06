#!/usr/bin/env python3
"""Audit boot-start drivers in an offline SYSTEM hive against the files on disk.

A boot-start service whose driver file is missing will fail to load; if its
ErrorControl is CRITICAL the kernel bugchecks (typically 0x7B) instead of
continuing, so these two facts have to be checked together.
"""

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from regf import Hive  # noqa: E402

START_NAMES = {0: "BOOT", 1: "SYSTEM", 2: "AUTO", 3: "DEMAND", 4: "DISABLED"}
ERROR_NAMES = {0: "IGNORE", 1: "NORMAL", 2: "SEVERE", 3: "CRITICAL"}


def load_present_drivers(listing_path):
    present = set()
    if not os.path.exists(listing_path):
        return present
    with open(listing_path) as handle:
        for line in handle:
            parts = line.split()
            if len(parts) >= 2:
                present.add(parts[1].lower())
    return present


def image_filename(image_path):
    if not image_path:
        return None
    return image_path.replace("/", "\\").split("\\")[-1].lower()


def main():
    hive_path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/w11diag/hives/SYSTEM"
    listing = sys.argv[2] if len(sys.argv) > 2 else "/tmp/w11diag/driver-listing.txt"

    hive = Hive(hive_path)
    present = load_present_drivers(listing)
    print(f"hive dirty: {hive.is_dirty()}   driver files on disk: {len(present)}")

    current = hive.key("Select").value("Current").value()
    cs = f"ControlSet{current:03d}"
    services = hive.key(f"{cs}\\Services")
    print(f"analyzing {cs}\\Services ({services.subkey_count} services)\n")

    boot_start = []
    for svc in services.subkeys():
        start = svc.value("Start")
        if start is None or start.value() != 0:
            continue
        err = svc.value("ErrorControl")
        img = svc.value("ImagePath")
        group = svc.value("Group")
        boot_start.append({
            "name": svc.name,
            "error": err.value() if err else None,
            "image": img.value() if img else None,
            "group": group.value() if group else None,
        })

    print(f"boot-start (Start=0) services: {len(boot_start)}\n")

    missing = []
    for svc in boot_start:
        fname = image_filename(svc["image"]) or f"{svc['name'].lower()}.sys"
        if fname not in present:
            missing.append((svc, fname))

    if not missing:
        print("all boot-start driver files present")
    else:
        print("=== BOOT-START DRIVERS WITH NO FILE ON DISK ===")
        for svc, fname in missing:
            err = ERROR_NAMES.get(svc["error"], svc["error"])
            print(f"  {svc['name']:<24} file={fname:<20} ErrorControl={err} "
                  f"group={svc['group']}")
            print(f"      ImagePath={svc['image']}")

    print("\n=== storage driver detail ===")
    for name in ("storahci", "stornvme", "viostor", "vioscsi", "storport",
                 "disk", "partmgr", "volmgr", "volsnap", "intelide", "msahci"):
        svc = services.subkey(name)
        if svc is None:
            print(f"  {name:<12} (no service key)")
            continue
        start = svc.value("Start")
        err = svc.value("ErrorControl")
        img = svc.value("ImagePath")
        fname = image_filename(img.value() if img else None) or f"{name}.sys"
        state = "on-disk" if fname in present else "NO FILE"
        print(f"  {name:<12} Start={START_NAMES.get(start.value() if start else None)} "
              f"ErrorControl={ERROR_NAMES.get(err.value() if err else None)} {state}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

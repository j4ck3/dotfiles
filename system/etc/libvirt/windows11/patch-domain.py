#!/usr/bin/env python3
"""Patch windows11 libvirt domain XML for passthrough vs console modes."""
from __future__ import annotations

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

NS_QEMU = "http://libvirt.org/schemas/domain/qemu/1.0"
ET.register_namespace("qemu", NS_QEMU)

KVMFR_SIZE_MB = 64
KVMFR_SIZE_BYTES = KVMFR_SIZE_MB * 1024 * 1024
SHM_PATH = "/dev/shm/looking-glass"
EVDEV_CONF = Path("/etc/libvirt/windows11/evdev.conf")


def kvmfr_available() -> bool:
    p = Path("/dev/kvmfr0")
    return p.exists() and p.is_char_device()


def load_evdev_conf() -> dict[str, str]:
    cfg: dict[str, str] = {}
    conf = EVDEV_CONF
    if not conf.is_file():
        dotfiles = Path.home() / "dotfiles/system/etc/libvirt/windows11/evdev.conf"
        if dotfiles.is_file():
            conf = dotfiles
        else:
            return cfg
    for line in conf.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        cfg[key.strip()] = val.strip()
    return cfg


def ensure_qemu_ns(root: ET.Element) -> None:
    """Register qemu NS for ElementTree output without duplicating xmlns:qemu on <domain>."""
    # root.set('xmlns:qemu', ...) plus ET.register_namespace() produces duplicate
    # xmlns:qemu attributes and libvirt rejects the XML.
    for key in list(root.attrib):
        if key == "xmlns:qemu":
            del root.attrib[key]


def remove_looking_glass(root: ET.Element) -> bool:
    changed = False
    for tag in ("commandline",):
        el = root.find(f"{{{NS_QEMU}}}{tag}")
        if el is not None:
            root.remove(el)
            changed = True
    return changed


def add_looking_glass_kvmfr(root: ET.Element) -> bool:
    remove_looking_glass_shm(root.find("devices"))
    remove_looking_glass(root)
    ensure_qemu_ns(root)
    ql = ET.SubElement(root, f"{{{NS_QEMU}}}commandline")
    args = [
        "-device",
        "{'driver':'ivshmem-plain','id':'shmem0','memdev':'looking-glass'}",
        "-object",
        (
            "{'qom-type':'memory-backend-file','id':'looking-glass',"
            f"'mem-path':'/dev/kvmfr0','size':{KVMFR_SIZE_BYTES},'share':true}}"
        ),
    ]
    for value in args:
        ET.SubElement(ql, f"{{{NS_QEMU}}}arg", value=value)
    return True


def remove_looking_glass_shm(devices: ET.Element | None) -> bool:
    if devices is None:
        return False
    changed = False
    for shmem in list(devices.findall("shmem")):
        if shmem.get("name") == "looking-glass":
            devices.remove(shmem)
            changed = True
    return changed


def add_looking_glass_shm(devices: ET.Element) -> bool:
    remove_looking_glass_shm(devices)
    shmem = ET.SubElement(devices, "shmem", name="looking-glass")
    ET.SubElement(shmem, "model", type="ivshmem-plain")
    size = ET.SubElement(shmem, "size", unit="M")
    size.text = str(KVMFR_SIZE_MB)
    return True


def add_looking_glass(root: ET.Element, devices: ET.Element) -> bool:
    if kvmfr_available():
        return add_looking_glass_kvmfr(root)
    remove_looking_glass(root)
    return add_looking_glass_shm(devices)


def remove_emulated_inputs(devices: ET.Element) -> bool:
    changed = False
    for inp in list(devices.findall("input")):
        itype = inp.get("type")
        bus = inp.get("bus")
        if itype == "evdev":
            devices.remove(inp)
            changed = True
        elif itype == "tablet" and bus == "usb":
            devices.remove(inp)
            changed = True
        elif itype in ("mouse", "keyboard") and bus == "ps2":
            devices.remove(inp)
            changed = True
    return changed


def add_console_inputs(devices: ET.Element) -> bool:
    changed = False
    has_tablet = any(
        i.get("type") == "tablet" and i.get("bus") == "usb"
        for i in devices.findall("input")
    )
    has_ps2 = sum(
        1
        for i in devices.findall("input")
        if i.get("bus") == "ps2" and i.get("type") in ("mouse", "keyboard")
    )
    if not has_tablet:
        inp = ET.SubElement(devices, "input", type="tablet", bus="usb")
        ET.SubElement(
            inp,
            "address",
            type="usb",
            bus="0",
            port="1",
        )
        changed = True
    if has_ps2 < 2:
        if not any(
            i.get("type") == "mouse" and i.get("bus") == "ps2"
            for i in devices.findall("input")
        ):
            ET.SubElement(devices, "input", type="mouse", bus="ps2")
            changed = True
        if not any(
            i.get("type") == "keyboard" and i.get("bus") == "ps2"
            for i in devices.findall("input")
        ):
            ET.SubElement(devices, "input", type="keyboard", bus="ps2")
            changed = True
    return changed


def add_evdev_inputs(devices: ET.Element, cfg: dict[str, str]) -> bool:
    kb = cfg.get("KEYBOARD_DEV", "")
    mouse = cfg.get("MOUSE_DEV", "")
    toggle = cfg.get("GRAB_TOGGLE", "ctrl-ctrl")
    if not kb or not mouse:
        print(f"Missing KEYBOARD_DEV or MOUSE_DEV in {EVDEV_CONF}", file=sys.stderr)
        sys.exit(1)

    for path, label in ((mouse, "mouse"), (kb, "keyboard")):
        if not Path(path).exists():
            print(f"Evdev {label} device not found: {path}", file=sys.stderr)
            sys.exit(1)

    remove_emulated_inputs(devices)

    mouse_inp = ET.SubElement(devices, "input", type="evdev")
    ET.SubElement(mouse_inp, "source", dev=mouse)

    kb_inp = ET.SubElement(
        devices,
        "input",
        type="evdev",
    )
    src = ET.SubElement(kb_inp, "source", dev=kb, grab="all", repeat="on")
    src.set("grabToggle", toggle)
    return True


def remove_virtual_sound(devices: ET.Element) -> bool:
    changed = False
    for sound in list(devices.findall("sound")):
        devices.remove(sound)
        changed = True
    for audio in list(devices.findall("audio")):
        devices.remove(audio)
        changed = True
    return changed


def set_memballoon(devices: ET.Element, model: str) -> bool:
    mb = devices.find("memballoon")
    if mb is None:
        if model == "none":
            ET.SubElement(devices, "memballoon", model="none")
            return True
        return False
    if mb.get("model") == model:
        return False
    mb.set("model", model)
    for child in list(mb):
        mb.remove(child)
    return True


def apply_mode(tree: ET.ElementTree, mode: str) -> bool:
    root = tree.getroot()
    devices = root.find("devices")
    if devices is None:
        print("no <devices> in domain XML", file=sys.stderr)
        sys.exit(1)

    changed = False
    if mode == "passthrough":
        changed |= remove_virtual_sound(devices)
        changed |= remove_emulated_inputs(devices)
        cfg = load_evdev_conf()
        changed |= add_evdev_inputs(devices, cfg)
        changed |= set_memballoon(devices, "none")
        changed |= add_looking_glass(root, devices)
    elif mode == "console":
        changed |= remove_looking_glass(root)
        changed |= remove_looking_glass_shm(devices)
        changed |= remove_emulated_inputs(devices)
        changed |= add_console_inputs(devices)
        changed |= set_memballoon(devices, "virtio")
    else:
        print(f"unknown mode: {mode}", file=sys.stderr)
        sys.exit(1)
    return changed


def main() -> None:
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <mode> <in.xml> <out.xml>", file=sys.stderr)
        sys.exit(1)
    mode, in_path, out_path = sys.argv[1:4]
    tree = ET.parse(in_path)
    root = tree.getroot()
    changed = apply_mode(tree, mode)
    if mode == "passthrough" and root.find(f"{{{NS_QEMU}}}commandline") is not None:
        ensure_qemu_ns(root)
    if changed or mode == "passthrough":
        tree.write(out_path, encoding="unicode", xml_declaration=True)
    else:
        Path(out_path).write_text(Path(in_path).read_text(encoding="utf-8"), encoding="utf-8")
    sys.exit(0)


if __name__ == "__main__":
    main()

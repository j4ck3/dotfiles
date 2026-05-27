#!/usr/bin/env python3
"""Patch windows11 libvirt domain XML for passthrough vs console modes."""
from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from pathlib import Path

NS_QEMU = "http://libvirt.org/schemas/domain/qemu/1.0"
ET.register_namespace("qemu", NS_QEMU)


def ensure_qemu_ns(root: ET.Element) -> None:
    for key in list(root.attrib):
        if key == "xmlns:qemu":
            del root.attrib[key]


def remove_looking_glass(root: ET.Element) -> bool:
    changed = False
    el = root.find(f"{{{NS_QEMU}}}commandline")
    if el is not None:
        root.remove(el)
        changed = True
    return changed


def remove_looking_glass_shm(devices: ET.Element | None) -> bool:
    if devices is None:
        return False
    changed = False
    for shmem in list(devices.findall("shmem")):
        if shmem.get("name") == "looking-glass":
            devices.remove(shmem)
            changed = True
    return changed


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
        ET.SubElement(inp, "address", type="usb", bus="0", port="1")
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


def normalize_amd_gpu_hostdev_topology(devices: ET.Element) -> bool:
    """Keep the RX 7900 GPU and HDMI audio as one guest multifunction device."""
    changed = False
    targets = {
        ("0x03", "0x00", "0x0"): {
            "type": "pci",
            "domain": "0x0000",
            "bus": "0x04",
            "slot": "0x00",
            "function": "0x0",
            "multifunction": "on",
        },
        ("0x03", "0x00", "0x1"): {
            "type": "pci",
            "domain": "0x0000",
            "bus": "0x04",
            "slot": "0x00",
            "function": "0x1",
        },
    }

    for hostdev in devices.findall("hostdev"):
        if hostdev.get("type") != "pci":
            continue
        src = hostdev.find("source/address")
        if src is None:
            continue
        key = (src.get("bus"), src.get("slot"), src.get("function"))
        wanted = targets.get(key)
        if wanted is None:
            continue

        driver = hostdev.find("driver")
        if driver is None:
            hostdev.insert(0, ET.Element("driver", name="vfio"))
            changed = True
        elif driver.get("name") != "vfio":
            driver.set("name", "vfio")
            changed = True

        addr = hostdev.find("address")
        if addr is None:
            ET.SubElement(hostdev, "address", **wanted)
            changed = True
            continue

        if dict(addr.attrib) != wanted:
            addr.attrib.clear()
            addr.attrib.update(wanted)
            changed = True

    return changed


def ensure_child(parent: ET.Element, tag: str, **attrs: str) -> tuple[ET.Element, bool]:
    child = parent.find(tag)
    if child is None:
        return ET.SubElement(parent, tag, **attrs), True

    changed = False
    for key, value in attrs.items():
        if child.get(key) != value:
            child.set(key, value)
            changed = True
    return child, changed


def ensure_passthrough_cpu(root: ET.Element) -> bool:
    changed = False
    cpu = root.find("cpu")
    if cpu is None:
        cpu = ET.SubElement(root, "cpu", mode="host-passthrough", check="none", migratable="off")
        changed = True
    else:
        wanted = {
            "mode": "host-passthrough",
            "check": "none",
            "migratable": "off",
        }
        for key, value in wanted.items():
            if cpu.get(key) != value:
                cpu.set(key, value)
                changed = True

    hypervisor = None
    for feature in cpu.findall("feature"):
        if feature.get("name") == "hypervisor":
            hypervisor = feature
            break
    if hypervisor is None:
        ET.SubElement(cpu, "feature", policy="disable", name="hypervisor")
        changed = True
    elif hypervisor.get("policy") != "disable":
        hypervisor.set("policy", "disable")
        changed = True

    return changed


def ensure_passthrough_features(root: ET.Element) -> bool:
    changed = False
    features, did_change = ensure_child(root, "features")
    changed |= did_change

    kvm, did_change = ensure_child(features, "kvm")
    changed |= did_change
    hidden, did_change = ensure_child(kvm, "hidden", state="on")
    changed |= did_change
    for child in list(kvm.findall("hidden")):
        if child is not hidden:
            kvm.remove(child)
            changed = True

    for hyperv in list(features.findall("hyperv")):
        features.remove(hyperv)
        changed = True

    vmport, did_change = ensure_child(features, "vmport", state="off")
    changed |= did_change
    for child in list(features.findall("vmport")):
        if child is not vmport:
            features.remove(child)
            changed = True

    return changed


def set_entry(parent: ET.Element, name: str, value: str) -> bool:
    for entry in parent.findall("entry"):
        if entry.get("name") == name:
            if (entry.text or "") != value:
                entry.text = value
                return True
            return False
    entry = ET.SubElement(parent, "entry", name=name)
    entry.text = value
    return True


def ensure_smbios_sysinfo(root: ET.Element) -> bool:
    changed = False
    os_el = root.find("os")
    if os_el is None:
        os_el = ET.Element("os")
        root.insert(0, os_el)
        changed = True
    smbios, did_change = ensure_child(os_el, "smbios", mode="sysinfo")
    changed |= did_change
    for child in list(os_el.findall("smbios")):
        if child is not smbios:
            os_el.remove(child)
            changed = True

    sysinfo = root.find("sysinfo")
    if sysinfo is None:
        sysinfo = ET.Element("sysinfo", type="smbios")
        root.insert(list(root).index(os_el) + 1, sysinfo)
        changed = True
    elif sysinfo.get("type") != "smbios":
        sysinfo.set("type", "smbios")
        changed = True

    values = {
        "bios": {
            "vendor": "American Megatrends International, LLC.",
            "version": "2802",
            "date": "10/27/2023",
        },
        "system": {
            "manufacturer": "ASUSTeK COMPUTER INC.",
            "product": "ROG STRIX Z790-E GAMING WIFI",
            "version": "Rev 1.xx",
            "serial": "System Serial Number",
        },
        "baseBoard": {
            "manufacturer": "ASUSTeK COMPUTER INC.",
            "product": "ROG STRIX Z790-E GAMING WIFI",
            "version": "Rev 1.xx",
            "serial": "Base Board Serial Number",
        },
    }
    for section_name, entries in values.items():
        section, did_change = ensure_child(sysinfo, section_name)
        changed |= did_change
        for key, value in entries.items():
            changed |= set_entry(section, key, value)

    return changed


def apply_mode(tree: ET.ElementTree, mode: str) -> bool:
    root = tree.getroot()
    devices = root.find("devices")
    if devices is None:
        print("no <devices> in domain XML", file=sys.stderr)
        sys.exit(1)

    changed = False
    changed |= remove_looking_glass(root)
    changed |= remove_looking_glass_shm(devices)

    if mode == "passthrough":
        changed |= remove_virtual_sound(devices)
        changed |= remove_emulated_inputs(devices)
        changed |= add_console_inputs(devices)
        changed |= set_memballoon(devices, "none")
        changed |= normalize_amd_gpu_hostdev_topology(devices)
        changed |= ensure_passthrough_cpu(root)
        changed |= ensure_passthrough_features(root)
        changed |= ensure_smbios_sysinfo(root)
    elif mode == "console":
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
    ensure_qemu_ns(tree.getroot())
    changed = apply_mode(tree, mode)
    if changed or mode == "passthrough":
        tree.write(out_path, encoding="unicode", xml_declaration=True)
    else:
        Path(out_path).write_text(Path(in_path).read_text(encoding="utf-8"), encoding="utf-8")
    sys.exit(0)


if __name__ == "__main__":
    main()

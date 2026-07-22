#!/usr/bin/env python3
"""Patch windows11 libvirt domain XML for passthrough, console, and stealth modes."""
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

        if hostdev.get("display") is not None:
            del hostdev.attrib["display"]
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

    # NOTE: do NOT disable the PS/2 controller (i8042). QEMU input-linux evdev
    # passthrough delivers keyboard/mouse events through the guest PS/2 devices;
    # libvirt auto-adds implicit PS/2 inputs which act as that sink. Disabling
    # i8042 leaves evdev with nowhere to deliver -> dead keyboard and mouse.
    for child in list(features.findall("ps2")):
        features.remove(child)
        changed = True

    return changed


def remove_leaky_devices(devices: ET.Element) -> bool:
    changed = False
    for tag in ("serial", "console", "parallel", "channel"):
        for el in list(devices.findall(tag)):
            devices.remove(el)
            changed = True
    for inp in list(devices.findall("input")):
        if inp.get("type") in ("mouse", "keyboard") and inp.get("bus") == "ps2":
            devices.remove(inp)
            changed = True
        if inp.get("type") == "tablet":
            devices.remove(inp)
            changed = True
    for g in list(devices.findall("graphics")):
        devices.remove(g)
        changed = True
    for audio in list(devices.findall("audio")):
        if audio.get("type") == "spice":
            devices.remove(audio)
            changed = True
    for video in list(devices.findall("video")):
        devices.remove(video)
        changed = True
    for ctrl in list(devices.findall("controller")):
        if ctrl.get("type") == "usb" and ctrl.get("model") == "qemu-xhci":
            ctrl.set("model", "nec-xhci")
            changed = True
    return changed


def ensure_stealth_clock(root: ET.Element) -> bool:
    changed = False
    clock = root.find("clock")
    if clock is None:
        clock = ET.SubElement(root, "clock", offset="localtime")
        changed = True
    timers = {
        "rtc": {"tickpolicy": "catchup"},
        "pit": {"tickpolicy": "delay"},
        "hpet": {"present": "no"},
        "kvmclock": {"present": "no"},
        "hypervclock": {"present": "no"},
        "tsc": {"present": "yes", "mode": "native"},
    }
    existing = {t.get("name"): t for t in clock.findall("timer")}
    for name, attrs in timers.items():
        timer = existing.get(name)
        if timer is None:
            ET.SubElement(clock, "timer", name=name, **attrs)
            changed = True
            continue
        for key, value in attrs.items():
            if timer.get(key) != value:
                timer.set(key, value)
                changed = True
    return changed


def ensure_stealth_firmware(os_el: ET.Element) -> bool:
    changed = False
    # Use distro secure-boot OVMF CODE: matches May NVRAM backups and avoids
    # 0 disk I/O hangs seen with mismatched AutoVirt CODE + old vars.
    code = "/usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd"
    vars_tpl = "/usr/share/edk2/x64/OVMF_VARS.4m.fd"
    nvram_path = "/var/lib/libvirt/qemu/nvram/windows11-stealth_VARS.fd"

    for fw in list(os_el.findall("firmware")):
        os_el.remove(fw)
        changed = True

    loader = os_el.find("loader")
    if loader is None:
        loader = ET.SubElement(
            os_el,
            "loader",
            readonly="yes",
            secure="yes",
            type="pflash",
            format="raw",
        )
        changed = True
    for key, value in {
        "readonly": "yes",
        "secure": "yes",
        "type": "pflash",
        "format": "raw",
    }.items():
        if loader.get(key) != value:
            loader.set(key, value)
            changed = True
    if (loader.text or "") != code:
        loader.text = code
        changed = True

    nvram = os_el.find("nvram")
    if nvram is None:
        nvram = ET.SubElement(
            os_el,
            "nvram",
            template=vars_tpl,
            templateFormat="raw",
            format="raw",
        )
        changed = True
    if nvram.get("template") != vars_tpl:
        nvram.set("template", vars_tpl)
        changed = True
    for key, value in {"templateFormat": "raw", "format": "raw"}.items():
        if nvram.get(key) != value:
            nvram.set(key, value)
            changed = True
    if (nvram.text or "") != nvram_path:
        nvram.text = nvram_path
        changed = True
    return changed


def remove_cpu_vmx(cpu: ET.Element) -> bool:
    changed = False
    for feature in list(cpu.findall("feature")):
        if feature.get("name") in ("vmx", "invtsc") and feature.get("policy") == "require":
            cpu.remove(feature)
            changed = True
    return changed


def ensure_smm_on(root: ET.Element) -> bool:
    features = root.find("features")
    if features is None:
        return False
    smm, changed = ensure_child(features, "smm", state="on")
    return changed


def read_sysinfo_entries(root: ET.Element) -> dict[str, dict[str, str]]:
    out: dict[str, dict[str, str]] = {}
    sysinfo = root.find("sysinfo")
    if sysinfo is None:
        return out
    for section in sysinfo:
        out[section.tag] = {
            (e.get("name") or ""): (e.text or "")
            for e in section.findall("entry")
        }
    return out


def ensure_qemu_commandline(root: ET.Element) -> bool:
    cmdline = root.find(f"{{{NS_QEMU}}}commandline")
    if cmdline is not None:
        root.remove(cmdline)
    cmdline = ET.SubElement(root, f"{{{NS_QEMU}}}commandline")
    info = read_sysinfo_entries(root)
    bios = info.get("bios", {})
    system = info.get("system", {})
    board = info.get("baseBoard", {})

    def add_arg(value: str) -> None:
        ET.SubElement(cmdline, f"{{{NS_QEMU}}}arg", value=value)

    # Do not pass -cpu here: libvirt already builds -cpu from <cpu>; a second -cpu
    # breaks OVMF boot (0 disk I/O) on QEMU 10.2.x.
    smbios_pairs = [
        (
            "type=0,version="
            f"{bios.get('version', '2802')},"
            f"date={bios.get('date', '10/27/2023')}"
        ),
        (
            "type=1,manufacturer="
            f"{system.get('manufacturer', 'ASUSTeK COMPUTER INC.')},"
            f"product={system.get('product', 'ROG STRIX Z790-E GAMING WIFI')},"
            f"version={system.get('version', 'Rev 1.xx')},"
            f"serial={system.get('serial', 'To be filled by O.E.M.')}"
        ),
        (
            "type=2,manufacturer="
            f"{board.get('manufacturer', 'ASUSTeK COMPUTER INC.')},"
            f"product={board.get('product', 'ROG STRIX Z790-E GAMING WIFI')},"
            f"version={board.get('version', 'Rev 1.xx')},"
            f"serial={board.get('serial', 'To be filled by O.E.M.')}"
        ),
        "type=3,manufacturer=Default string",
        "type=4,manufacturer=Intel,max-speed=6000,current-speed=3200",
        "type=17,manufacturer=KINGSTON,loc_pfx=DDR5,speed=6000,serial=00000000,part=KHX3000",
    ]
    for pair in smbios_pairs:
        add_arg("-smbios")
        add_arg(pair)
    return True


def ensure_lan_bridge_network(
    devices: ET.Element,
    *,
    bridge: str = "br0",
    model: str = "e1000e",
    mac: str = "02:74:72:32:e0:03",
) -> bool:
    """Single NIC on an existing host bridge (NetworkManager br0; managed=no)."""
    changed = False
    ifaces = devices.findall("interface")

    keep = ifaces[0] if ifaces else None
    for extra in ifaces[1:]:
        devices.remove(extra)
        changed = True

    if keep is None:
        keep = ET.SubElement(devices, "interface", type="bridge")
        changed = True
    elif keep.get("type") != "bridge":
        keep.set("type", "bridge")
        changed = True

    for child in list(keep.findall("portForward")):
        keep.remove(child)
        changed = True
    for child in list(keep.findall("source")):
        if child.get("network") is not None:
            keep.remove(child)
            changed = True

    src = keep.find("source")
    if src is None:
        src = ET.SubElement(keep, "source")
        changed = True
    wanted_src = {"bridge": bridge, "managed": "no"}
    for key in list(src.attrib):
        if key not in wanted_src:
            del src.attrib[key]
            changed = True
    for key, value in wanted_src.items():
        if src.get(key) != value:
            src.set(key, value)
            changed = True

    mac_el = keep.find("mac")
    if mac_el is None:
        ET.SubElement(keep, "mac", address=mac)
        changed = True
    elif mac_el.get("address") != mac:
        mac_el.set("address", mac)
        changed = True

    model_el = keep.find("model")
    if model_el is None:
        ET.SubElement(keep, "model", type=model)
        changed = True
    elif model_el.get("type") != model:
        model_el.set("type", model)
        changed = True

    addr_wanted = {
        "type": "pci",
        "domain": "0x0000",
        "bus": "0x01",
        "slot": "0x00",
        "function": "0x0",
    }
    addr = keep.find("address")
    if addr is None:
        ET.SubElement(keep, "address", **addr_wanted)
        changed = True
    elif dict(addr.attrib) != addr_wanted:
        addr.attrib.clear()
        addr.attrib.update(addr_wanted)
        changed = True

    return changed


def ensure_emulator_path(devices: ET.Element) -> bool:
    path = "/opt/AutoVirt/emulator/bin/qemu-system-x86_64"
    emu = devices.find("emulator")
    if emu is None:
        ET.SubElement(devices, "emulator").text = path
        return True
    if (emu.text or "") != path:
        emu.text = path
        return True
    return False


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
    elif mode == "stealth":
        changed |= ensure_lan_bridge_network(devices)
        changed |= remove_virtual_sound(devices)
        changed |= remove_leaky_devices(devices)
        changed |= set_memballoon(devices, "none")
        changed |= normalize_amd_gpu_hostdev_topology(devices)
        changed |= ensure_passthrough_cpu(root)
        changed |= ensure_passthrough_features(root)
        changed |= ensure_smbios_sysinfo(root)
        changed |= ensure_smm_on(root)
        cpu = root.find("cpu")
        if cpu is not None:
            changed |= remove_cpu_vmx(cpu)
        changed |= ensure_stealth_clock(root)
        os_el = root.find("os")
        if os_el is not None:
            changed |= ensure_stealth_firmware(os_el)
        changed |= ensure_emulator_path(devices)
        changed |= ensure_qemu_commandline(root)
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
    if changed or mode in ("passthrough", "stealth"):
        tree.write(out_path, encoding="unicode", xml_declaration=True)
    else:
        Path(out_path).write_text(Path(in_path).read_text(encoding="utf-8"), encoding="utf-8")
    sys.exit(0)


if __name__ == "__main__":
    main()

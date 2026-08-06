#!/usr/bin/env python3
"""Minimal read-only parser for Windows registry hive (regf) files.

Enough of the format to walk keys and read values offline, with no
external dependencies. Transaction logs are not replayed; use is_dirty()
to tell whether the primary file is stale.
"""

import struct
import sys

HBIN_BASE = 0x1000

REG_SZ = 1
REG_EXPAND_SZ = 2
REG_BINARY = 3
REG_DWORD = 4
REG_MULTI_SZ = 7
REG_QWORD = 11

TYPE_NAMES = {
    0: "NONE", 1: "SZ", 2: "EXPAND_SZ", 3: "BINARY", 4: "DWORD",
    5: "DWORD_BE", 6: "LINK", 7: "MULTI_SZ", 11: "QWORD",
}


class Value:
    def __init__(self, name, vtype, data):
        self.name = name
        self.type = vtype
        self.raw = data

    @property
    def type_name(self):
        return TYPE_NAMES.get(self.type, f"TYPE_{self.type}")

    def value(self):
        if self.type in (REG_SZ, REG_EXPAND_SZ):
            return self.raw.decode("utf-16-le", "replace").rstrip("\x00")
        if self.type == REG_MULTI_SZ:
            text = self.raw.decode("utf-16-le", "replace").rstrip("\x00")
            return [s for s in text.split("\x00") if s]
        if self.type == REG_DWORD and len(self.raw) >= 4:
            return struct.unpack_from("<I", self.raw)[0]
        if self.type == REG_QWORD and len(self.raw) >= 8:
            return struct.unpack_from("<Q", self.raw)[0]
        return self.raw

    def __repr__(self):
        return f"<Value {self.name}={self.value()!r} ({self.type_name})>"


class Key:
    def __init__(self, hive, offset):
        self.hive = hive
        self.offset = offset
        data = hive.cell(offset)
        if data[0:2] != b"nk":
            raise ValueError(f"not an nk cell at {offset:#x}")
        (self.flags,) = struct.unpack_from("<H", data, 0x02)
        (self.subkey_count,) = struct.unpack_from("<I", data, 0x14)
        (self.subkeys_offset,) = struct.unpack_from("<i", data, 0x1C)
        (self.value_count,) = struct.unpack_from("<I", data, 0x24)
        (self.values_offset,) = struct.unpack_from("<i", data, 0x28)
        (name_len,) = struct.unpack_from("<H", data, 0x48)
        raw_name = data[0x4C:0x4C + name_len]
        self.name = (raw_name.decode("ascii", "replace") if self.flags & 0x20
                     else raw_name.decode("utf-16-le", "replace"))

    def subkeys(self):
        if self.subkey_count == 0 or self.subkeys_offset in (-1, 0xFFFFFFFF):
            return []
        return [Key(self.hive, off) for off in self.hive.walk_list(self.subkeys_offset)]

    def subkey(self, name):
        target = name.lower()
        for key in self.subkeys():
            if key.name.lower() == target:
                return key
        return None

    def path(self, path):
        node = self
        for part in path.replace("/", "\\").split("\\"):
            if not part:
                continue
            node = node.subkey(part)
            if node is None:
                return None
        return node

    def values(self):
        if self.value_count == 0 or self.values_offset in (-1, 0xFFFFFFFF):
            return []
        raw = self.hive.cell(self.values_offset)
        out = []
        for i in range(self.value_count):
            (off,) = struct.unpack_from("<i", raw, i * 4)
            if off in (-1, 0xFFFFFFFF):
                continue
            try:
                out.append(self.hive.read_value(off))
            except (ValueError, struct.error):
                continue
        return out

    def value(self, name):
        target = name.lower()
        for val in self.values():
            if val.name.lower() == target:
                return val
        return None

    def __repr__(self):
        return f"<Key {self.name} subkeys={self.subkey_count} values={self.value_count}>"


class Hive:
    def __init__(self, path):
        with open(path, "rb") as handle:
            self.buf = handle.read()
        if self.buf[0:4] != b"regf":
            raise ValueError("not a regf hive")
        self.seq1, self.seq2 = struct.unpack_from("<II", self.buf, 0x04)
        (root_offset,) = struct.unpack_from("<I", self.buf, 0x24)
        self.root = Key(self, root_offset)

    def is_dirty(self):
        return self.seq1 != self.seq2

    def cell(self, offset):
        pos = HBIN_BASE + offset
        (size,) = struct.unpack_from("<i", self.buf, pos)
        length = abs(size) - 4
        return self.buf[pos + 4:pos + 4 + length]

    def walk_list(self, offset):
        data = self.cell(offset)
        sig = data[0:2]
        (count,) = struct.unpack_from("<H", data, 0x02)
        offsets = []
        if sig in (b"lf", b"lh"):
            for i in range(count):
                (off,) = struct.unpack_from("<I", data, 0x04 + i * 8)
                offsets.append(off)
        elif sig == b"li":
            for i in range(count):
                (off,) = struct.unpack_from("<I", data, 0x04 + i * 4)
                offsets.append(off)
        elif sig == b"ri":
            for i in range(count):
                (off,) = struct.unpack_from("<I", data, 0x04 + i * 4)
                offsets.extend(self.walk_list(off))
        return offsets

    def read_value(self, offset):
        data = self.cell(offset)
        if data[0:2] != b"vk":
            raise ValueError("not a vk cell")
        (name_len,) = struct.unpack_from("<H", data, 0x02)
        (size,) = struct.unpack_from("<I", data, 0x04)
        (data_off,) = struct.unpack_from("<I", data, 0x08)
        (vtype,) = struct.unpack_from("<I", data, 0x0C)
        (flags,) = struct.unpack_from("<H", data, 0x10)
        raw_name = data[0x14:0x14 + name_len]
        name = (raw_name.decode("ascii", "replace") if flags & 0x01
                else raw_name.decode("utf-16-le", "replace"))

        inline = bool(size & 0x80000000)
        length = size & 0x7FFFFFFF
        if inline:
            payload = struct.pack("<I", data_off)[:length]
        else:
            payload = self.cell(data_off)[:length]
        return Value(name or "(Default)", vtype, payload)

    def key(self, path):
        return self.root.path(path)


def main():
    if len(sys.argv) < 2:
        print(f"usage: {sys.argv[0]} <hive> [key-path]", file=sys.stderr)
        return 1
    hive = Hive(sys.argv[1])
    print(f"root={hive.root.name} dirty={hive.is_dirty()}")
    node = hive.key(sys.argv[2]) if len(sys.argv) > 2 else hive.root
    if node is None:
        print("key not found", file=sys.stderr)
        return 1
    print(f"[{node.name}]")
    for val in node.values():
        print(f"  {val.name} = {val.value()!r} ({val.type_name})")
    for sub in node.subkeys():
        print(f"  <{sub.name}>")
    return 0


if __name__ == "__main__":
    sys.exit(main())

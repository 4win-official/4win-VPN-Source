#!/usr/bin/env python3
"""Regression tests for Psiphon's gomobile ELF/JNI relocation."""

from __future__ import annotations

import importlib.util
import struct
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("relocate_psiphon_aar.py")
SPEC = importlib.util.spec_from_file_location("relocate_psiphon_aar", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
relocator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(relocator)


def make_elf_fixture(elf_class: int) -> bytes:
    """Create a small ELF shared object with SysV and GNU dynamic hashes."""
    endian = "<"
    word_size = 4 if elf_class == 1 else 8
    base = 0x10000
    data = bytearray(0x1000)
    ident = b"\x7fELF" + bytes((elf_class, 1, 1, 0)) + bytes(8)
    data[:16] = ident

    if elf_class == 2:
        phoff, phentsize = 64, 56
        struct.pack_into(endian + "HHIQQQIHHHHHH", data, 16,
                         3, 62, 1, 0, phoff, 0, 0, 64, phentsize, 2,
                         0, 0, 0)
        phfmt = endian + "IIQQQQQQ"
        struct.pack_into(phfmt, data, phoff,
                         1, 7, 0, base, base, len(data), len(data), 0x1000)
        dynamic_size = 7 * 16
        struct.pack_into(phfmt, data, phoff + phentsize,
                         2, 6, 0x200, base + 0x200, base + 0x200,
                         dynamic_size, dynamic_size, 8)
        dynfmt, symfmt, syment = endian + "qQ", endian + "IBBHQQ", 24
    else:
        phoff, phentsize = 52, 32
        struct.pack_into(endian + "HHIIIIIHHHHHH", data, 16,
                         3, 40, 1, 0, phoff, 0, 0, 52, phentsize, 2,
                         0, 0, 0)
        phfmt = endian + "IIIIIIII"
        struct.pack_into(phfmt, data, phoff,
                         1, 0, base, base, len(data), len(data), 7, 0x1000)
        dynamic_size = 7 * 8
        struct.pack_into(phfmt, data, phoff + phentsize,
                         2, 0x200, base + 0x200, base + 0x200,
                         dynamic_size, dynamic_size, 6, 4)
        dynfmt, symfmt, syment = endian + "iI", endian + "IIIBBH", 16

    symbol_names = (b"", b"Java_go_Seq_init", b"Java_go_Seq_destroyRef", b"Go_other")
    strings = bytearray(b"\0")
    name_offsets = [0]
    for name in symbol_names[1:]:
        name_offsets.append(len(strings))
        strings.extend(name + b"\0")
    data[0x300:0x300 + len(strings)] = strings

    for index, name_offset in enumerate(name_offsets):
        if elf_class == 2:
            entry = struct.pack(symfmt, name_offset, 0 if index == 0 else 0x12,
                                0, 0 if index == 0 else 1, 0, 0)
        else:
            entry = struct.pack(symfmt, name_offset, 0, 0,
                                0 if index == 0 else 0x12,
                                0, 0 if index == 0 else 1)
        data[0x400 + index * syment:0x400 + (index + 1) * syment] = entry

    dynamic_tags = (
        (4, base + 0x500),                 # DT_HASH
        (0x6FFFFEF5, base + 0x600),         # DT_GNU_HASH
        (5, base + 0x300),                 # DT_STRTAB
        (10, len(strings)),                # DT_STRSZ
        (6, base + 0x400),                 # DT_SYMTAB
        (11, syment),                      # DT_SYMENT
        (0, 0),                            # DT_NULL
    )
    for index, (tag, value) in enumerate(dynamic_tags):
        struct.pack_into(dynfmt, data, 0x200 + index * struct.calcsize(dynfmt), tag, value)

    # The old layout has three buckets; the transformer must fit the rebuilt
    # one-bucket tables into the same allocated ELF ranges.
    struct.pack_into(endian + "II", data, 0x500, 3, len(symbol_names))
    struct.pack_into(endian + "IIII", data, 0x600, 3, 1, 1, 5)
    marker = b"go/Seq\0"
    data[0x700:0x700 + len(marker)] = marker
    return bytes(data)


def install_old_sysv_hash(data: bytes) -> bytes:
    """Create an ordinary multi-bucket SysV table for the original names."""
    details = relocator._dynamic_symbols(data)
    endian, names, hash_offset = details[1], details[5], details[6]
    bucket_count = 5
    buckets = [0] * bucket_count
    chains = [0] * len(names)
    tails = [0] * bucket_count
    for index in range(1, len(names)):
        bucket = relocator._sysv_hash(names[index]) % bucket_count
        if buckets[bucket] == 0:
            buckets[bucket] = index
        else:
            chains[tails[bucket]] = index
        tails[bucket] = index
    table = (struct.pack(endian + "II", bucket_count, len(names)) +
             struct.pack(endian + f"{bucket_count}I", *buckets) +
             struct.pack(endian + f"{len(names)}I", *chains))
    out = bytearray(data)
    out[hash_offset:hash_offset + len(table)] = table
    return bytes(out)


class PsiphonElfRelocationTest(unittest.TestCase):
    def test_renamed_seq_initializer_resolves_through_both_hash_tables(self):
        for elf_class in (1, 2):
            with self.subTest(elf_class=elf_class):
                original = make_elf_fixture(elf_class)
                hashed_original, _ = relocator.rebuild_dynamic_symbol_hashes(original)
                hashed_original = install_old_sysv_hash(hashed_original)

                # Reproduce the old behavior: changing .dynstr alone leaves
                # Android's dynamic lookup hashes pointing at Java_go_*.
                stale = hashed_original.replace(b"Java_go_", b"Java_gi_")
                self.assertFalse(relocator.elf_dynamic_symbol_resolves(
                    stale, b"Java_gi_Seq_init", "gnu"))
                self.assertFalse(relocator.elf_dynamic_symbol_resolves(
                    stale, b"Java_gi_Seq_init", "sysv"))

                relocated, _ = relocator.patch_so(
                    original, ("go", "gi"), {b"go/Seq"})
                self.assertIn(b"Java_gi_Seq_init\0", relocated)
                self.assertIn(b"gi/Seq\0", relocated)
                self.assertNotIn(b"Java_go_Seq_init\0", relocated)
                self.assertNotIn(b"go/Seq\0", relocated)
                self.assertTrue(relocator.elf_dynamic_symbol_resolves(
                    relocated, b"Java_gi_Seq_init", "gnu"))
                self.assertTrue(relocator.elf_dynamic_symbol_resolves(
                    relocated, b"Java_gi_Seq_init", "sysv"))


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""
relocate_psiphon_aar.py — Make the Psiphon gomobile runtime coexist with Xray's.

WHY THIS EXISTS
===============
The 4win app embeds TWO gomobile-built Go libraries:

  * Xray   (libv2ray.aar + jniLibs/libgojni.so)  — Java bridge: package `go`
  * Psiphon(psiphontunnel AAR  + jni/*/libgojni.so) — Java bridge: package `go` too!

gomobile's magic class `go.Seq` has a static initializer that runs
`System.loadLibrary("gojni")`, and every gomobile binding (go.Seq natives,
`go/Seq` FindClass strings baked into the .so, `Java_go_*` JNI exports) is
hard-wired to that package/library name. Two different Go runtimes can NEVER
share one Android process: their native libraries export ~90 identical C
symbols with DEFAULT visibility (main.main, crosscall*, _cgo_*, go_seq_*),
and Android resolves symbols process-wide — the second runtime ends up
calling the first one's scheduler and the process dies.

The app therefore isolates Psiphon in the `:psiphon` process and Xray in the
main + `:psiphonbridge` processes. But process isolation alone is NOT enough
while both Java bridges are named `go.*`: in the `:psiphon` process, the
stripped Psiphon bindings still resolve `go.Seq` to the *Xray* copy that is
packaged in the APK, which (a) loads the whole 31MB Xray runtime into the
Psiphon process via `System.loadLibrary("gojni")` and (b) routes every
Psiphon Java->Go call into the Xray runtime, then `System.loadLibrary(
"psiphon-gojni")` loads a SECOND Go runtime on top -> native crash on the
first connection.

WHAT THIS SCRIPT DOES (all at build time, to the Psiphon AAR only)
==================================================================
1. Relocates the gomobile Java bridge package `go` -> `gi` in EVERY .class
   file of classes.jar (constant-pool rewrite of class references,
   `Lgo/...;` descriptors, and the loadLibrary("gojni") string constant ->
   "psiphon-gojni"). The `ca.psiphon.*` API package is left untouched.
2. For every jni/<abi>/libgojni.so inside the AAR:
     - renames the file to libpsiphon-gojni.so
     - rewrites the JNI export names in .dynstr:  Java_go_*  -> Java_gi_*
       (in-place, same length, so the ELF stays byte-layout identical)
     - rewrites the baked-in FindClass strings  go/Seq, go/Seq$Ref,
       go/Universe, ... -> gi/... (in-place, same length, derived from the
       set of `go/*` Java classes actually present in classes.jar)
3. Verifies the result and FAILS the build if any `go/` reference survives.

Result: `gi.Seq` (Psiphon) loads ONLY libpsiphon-gojni.so; `go.Seq` (Xray)
loads ONLY libgojni.so; and because each process uses only one of them, no
process ever hosts two Go runtimes.

USAGE
=====
  python3 relocate_psiphon_aar.py --in <original.aar> --out <relocated.aar>
                                  [--go-package go:gi]
                                  [--lib-name gojni:psiphon-gojni]
"""

from __future__ import annotations

import argparse
import struct
import sys
import zipfile
from io import BytesIO
from pathlib import Path


# --------------------------------------------------------------------------
# Java class file constant-pool rewriter
# --------------------------------------------------------------------------

class ClassFileRewriter:
    """Rewrites constant-pool UTF8 entries of a JVM class file.

    Only the constant pool is touched; all other structures reference pool
    entries by index, so shrinking/growing UTF8 constants is safe as long as
    the pool section itself is re-emitted with correct lengths.
    """

    def __init__(self, data: bytes, class_prefix: tuple[str, str],
                 lib_name: tuple[str, str],
                 class_name: str = "<unknown>"):
        self.data = data
        self.old_pkg, self.new_pkg = class_prefix  # e.g. ("go", "gi")
        self.old_lib, self.new_lib = lib_name      # e.g. ("gojni", "psiphon-gojni")
        self.class_name = class_name               # for error messages
        self.patches: list[str] = []

    def rewrite(self) -> bytes:
        data = self.data
        if data[:4] != b"\xca\xfe\xba\xbe":
            raise ValueError(f"{self.class_name}: not a Java class file")
        cp_count = struct.unpack_from(">H", data, 8)[0]

        # Walk the constant pool, collecting rewrite ops on UTF8 entries.
        ops: dict[int, bytes] = {}  # utf8 entry index -> new bytes
        idx = 10
        i = 1
        while i < cp_count:
            tag = data[idx]
            idx += 1
            if tag == 1:  # CONSTANT_Utf8
                ln = struct.unpack_from(">H", data, idx)[0]
                idx += 2
                raw = data[idx:idx + ln]
                idx += ln
                new = self._rewrite_utf8(raw)
                if new != raw:
                    ops[i] = new
            elif tag in (3, 4):        # Integer / Float
                idx += 4
            elif tag in (5, 6):        # Long / Double (take two slots)
                idx += 8
                i += 1
            elif tag in (7, 8):        # Class / String
                idx += 2
            elif tag in (9, 10, 11, 12, 17, 18):  # refs / NameAndType / dynamic
                idx += 4
            elif tag == 15:            # MethodHandle
                idx += 3
            elif tag in (16, 19, 20):  # Module/Package refs (module-info)
                idx += 2
            else:
                cn = self.class_name or "<unknown>"
                raise ValueError(f"{cn}: unsupported constant-pool tag "
                                 f"{tag} at #{i}")
            i += 1

        if not ops:
            return data  # nothing to do

        pool_end = idx
        out = bytearray(data[:10])
        # Re-emit the pool with patched UTF8 payloads.
        idx = 10
        i = 1
        while i < cp_count:
            tag = data[idx]
            entry_start = idx
            idx += 1
            if tag == 1:
                ln = struct.unpack_from(">H", data, idx)[0]
                idx += 2
                payload = ops.get(i, data[idx:idx + ln])
                if i in ops:
                    self.patches.append(
                        payload.decode("utf-8", "replace"))
                # tag byte only (old length is dropped, new one follows)
                out += data[entry_start:entry_start + 1]
                out += struct.pack(">H", len(payload))
                out += payload
                idx += ln
            elif tag in (3, 4):
                out += data[entry_start:idx + 4]
                idx += 4
            elif tag in (5, 6):
                out += data[entry_start:idx + 8]
                idx += 8
                i += 1
            elif tag in (7, 8):
                out += data[entry_start:idx + 2]
                idx += 2
            elif tag in (9, 10, 11, 12, 17, 18):
                out += data[entry_start:idx + 4]
                idx += 4
            elif tag == 15:
                out += data[entry_start:idx + 3]
                idx += 3
            elif tag in (16, 19, 20):
                out += data[entry_start:idx + 2]
                idx += 2
            else:
                cn = self.class_name or "<unknown>"
                raise ValueError(f"{cn}: unsupported tag {tag}")
            i += 1
        out += data[pool_end:]
        return bytes(out)

    def _rewrite_utf8(self, raw: bytes) -> bytes:
        old_pkg_b = self.old_pkg.encode()
        new_pkg_b = self.new_pkg.encode()

        # Exact library-name string constant ("gojni") -> "psiphon-gojni".
        if raw == self.old_lib.encode() and self.old_lib != self.new_lib:
            return self.new_lib.encode()

        out = raw
        # Internal class names used as CONSTANT_Class payloads: go/... -> gi/...
        if out.startswith(old_pkg_b + b"/"):
            out = new_pkg_b + out[len(old_pkg_b):]
            return out
        # Descriptors / signatures: Lgo/...; -> Lgi/...;
        if b"L" + old_pkg_b + b"/" in out:
            out = out.replace(b"L" + old_pkg_b + b"/",
                              b"L" + new_pkg_b + b"/")
        return out


def rewrite_classes_jar(jar_bytes: bytes, class_prefix: tuple[str, str],
                        lib_name: tuple[str, str]) -> tuple[bytes, list[str]]:
    """Rewrites every .class entry of classes.jar (constant pool AND entry
    path). Returns (jar, report)."""
    report: list[str] = []
    old_pkg, new_pkg = class_prefix
    out_jar = BytesIO()
    with zipfile.ZipFile(BytesIO(jar_bytes), "r") as zin, \
            zipfile.ZipFile(out_jar, "w", zipfile.ZIP_DEFLATED) as zout:
        for info in zin.infolist():
            payload = zin.read(info.filename)
            name = info.filename
            if name.startswith(old_pkg + "/"):
                name = new_pkg + name[len(old_pkg):]
            if name.endswith(".class"):
                payload = ClassFileRewriter(
                    payload, class_prefix, lib_name, class_name=name).rewrite()
            zout.writestr(name, payload)
            if info.filename != name:
                report.append(f"  {info.filename} -> {name}")
    return out_jar.getvalue(), report


def collect_go_class_names(jar_bytes: bytes, old_pkg: str) -> set[bytes]:
    """Full internal names of every `go/*` Java class in the jar
    (before rewrite). Used to patch FindClass strings inside the .so."""
    names: set[bytes] = set()
    prefix = (old_pkg + "/").encode()
    with zipfile.ZipFile(BytesIO(jar_bytes), "r") as zin:
        for info in zin.infolist():
            n = info.filename
            if n.endswith(".class") and n.startswith(old_pkg + "/"):
                names.add(n[:-len(".class")].encode())
                # nested names are prefixes of one another (go/Seq vs
                # go/Seq$Ref) — the set keeps both; patching the shorter
                # prefix also fixes the longer one, so this is enough.
    if not names:
        names.add(prefix + b"Seq")
        names.add(prefix + b"Universe")
    return names


# --------------------------------------------------------------------------
# ELF patching (JNI export names + FindClass strings)
# --------------------------------------------------------------------------
#
# JNI and FindClass names are length-preserving rewrites, but changing exported
# JNI names also invalidates the ELF dynamic symbol hash tables. We rebuild
# those tables below; merely changing .dynstr leaves names visible to `nm` but
# unreachable to Android's linker/dlsym lookup.


def patch_so(data: bytes, class_prefix: tuple[str, str],
             go_class_names: set[bytes]) -> tuple[bytes, list[str]]:
    """In-place, length-preserving patches for a gomobile .so.

    1. JNI export/name occurrences  Java_<old>_...  ->  Java_<new>_...
    2. Baked-in class-name strings  go/Seq -> gi/Seq, go/Seq$Ref -> ... etc.

    Returns (patched_bytes, report).
    """
    old_pkg, new_pkg = class_prefix
    report: list[str] = []
    buf = bytearray(data)

    # ---- 1. JNI symbol names --------------------------------------------
    old_sym = b"Java_" + old_pkg.encode() + b"_"
    new_sym = b"Java_" + new_pkg.encode() + b"_"
    assert len(old_sym) == len(new_sym)
    total = buf.count(old_sym)
    if total:
        idx = 0
        for _ in range(total):
            idx = buf.find(old_sym, idx)
            buf[idx:idx + len(old_sym)] = new_sym
            idx += len(new_sym)
    report.append(f"  renamed {total} occurrence(s) of JNI prefix "
                  f"'Java_{old_pkg}_*' -> 'Java_{new_pkg}_*'")

    # ---- 2. baked-in FindClass strings ---------------------------------
    replaced = 0
    for cls in sorted(go_class_names, key=len, reverse=True):
        new = new_pkg.encode() + cls[len(old_pkg):]
        count = buf.count(cls)
        if count:
            idx = 0
            for _ in range(count):
                idx = buf.find(cls, idx)
                buf[idx:idx + len(cls)] = new
                idx += len(new)
            replaced += count
            report.append(f"  {cls.decode()} -> {new.decode()} x{count}")

    patched, hash_report = rebuild_dynamic_symbol_hashes(bytes(buf))
    report.extend(hash_report)
    return patched, report


def _elf_dynamic_info(data: bytes):
    """Read ELF class, dynamic tags, and a virtual-address-to-file mapper."""
    if len(data) < 52 or data[:4] != b"\x7fELF":
        raise ValueError("not an ELF shared library")
    elf_class, encoding = data[4], data[5]
    if elf_class not in (1, 2) or encoding not in (1, 2):
        raise ValueError("unsupported ELF class or byte order")
    endian = "<" if encoding == 1 else ">"
    word_size = 4 if elf_class == 1 else 8

    if elf_class == 2:
        phoff = struct.unpack_from(endian + "Q", data, 32)[0]
        phentsize, phnum = struct.unpack_from(endian + "HH", data, 54)
        phfmt = endian + "IIQQQQQQ"
        dynfmt = endian + "qQ"
    else:
        phoff = struct.unpack_from(endian + "I", data, 28)[0]
        phentsize, phnum = struct.unpack_from(endian + "HH", data, 42)
        phfmt = endian + "IIIIIIII"
        dynfmt = endian + "iI"

    expected_phentsize = struct.calcsize(phfmt)
    if phentsize < expected_phentsize or phoff + phentsize * phnum > len(data):
        raise ValueError("invalid ELF program-header table")

    load_segments: list[tuple[int, int, int]] = []
    dynamic_segment: tuple[int, int] | None = None
    for index in range(phnum):
        fields = struct.unpack_from(phfmt, data, phoff + index * phentsize)
        if elf_class == 2:
            p_type, _flags, p_offset, p_vaddr, _paddr, p_filesz, _memsz, _align = fields
        else:
            p_type, p_offset, p_vaddr, _paddr, p_filesz, _memsz, _flags, _align = fields
        if p_type == 1:  # PT_LOAD
            load_segments.append((p_offset, p_vaddr, p_filesz))
        elif p_type == 2:  # PT_DYNAMIC
            dynamic_segment = (p_offset, p_filesz)
    if dynamic_segment is None or not load_segments:
        raise ValueError("ELF is missing PT_DYNAMIC or PT_LOAD")

    def vaddr_to_offset(address: int, size: int = 1) -> int:
        for file_offset, virtual_address, file_size in load_segments:
            if virtual_address <= address and address + size <= virtual_address + file_size:
                result = file_offset + address - virtual_address
                if result + size <= len(data):
                    return result
        raise ValueError(f"ELF virtual address 0x{address:x} is not file-backed")

    dyn_offset, dyn_size = dynamic_segment
    dyn_entsize = struct.calcsize(dynfmt)
    if dyn_offset + dyn_size > len(data) or dyn_size % dyn_entsize:
        raise ValueError("invalid ELF dynamic segment")
    tags: dict[int, int] = {}
    for offset in range(dyn_offset, dyn_offset + dyn_size, dyn_entsize):
        tag, value = struct.unpack_from(dynfmt, data, offset)
        if tag == 0:  # DT_NULL
            break
        if tag in (4, 5, 6, 10, 11, 0x6FFFFEF5):
            tags[tag] = value
    return elf_class, endian, word_size, tags, vaddr_to_offset


def _dynamic_symbols(data: bytes):
    """Return ELF details, dynamic symbol names, and hash-table locations."""
    elf_class, endian, word_size, tags, vaddr_to_offset = _elf_dynamic_info(data)
    required = (4, 5, 6, 10, 11)
    missing = [tag for tag in required if tag not in tags]
    if missing:
        raise ValueError(f"ELF lacks required dynamic tags: {missing}")
    symtab_entry_size = 24 if elf_class == 2 else 16
    if tags[11] != symtab_entry_size:
        raise ValueError(f"unexpected DT_SYMENT size {tags[11]}")

    hash_offset = vaddr_to_offset(tags[4], 8)
    old_bucket_count, symbol_count = struct.unpack_from(endian + "II", data, hash_offset)
    if old_bucket_count < 1 or symbol_count < 1:
        raise ValueError("invalid ELF DT_HASH header")
    old_hash_size = 8 + 4 * (old_bucket_count + symbol_count)
    vaddr_to_offset(tags[4], old_hash_size)

    symtab_offset = vaddr_to_offset(tags[6], symbol_count * symtab_entry_size)
    strtab_offset = vaddr_to_offset(tags[5], tags[10])
    strings = data[strtab_offset:strtab_offset + tags[10]]
    names: list[bytes] = []
    for index in range(symbol_count):
        name_offset = struct.unpack_from(endian + "I", data,
                                          symtab_offset + index * symtab_entry_size)[0]
        if name_offset >= len(strings):
            raise ValueError(f"dynamic symbol {index} has invalid st_name")
        end = strings.find(b"\0", name_offset)
        if end < 0:
            raise ValueError(f"dynamic symbol {index} name is unterminated")
        names.append(strings[name_offset:end])

    gnu_offset = None
    gnu_size = None
    gnu_header = None
    if 0x6FFFFEF5 in tags:
        gnu_offset = vaddr_to_offset(tags[0x6FFFFEF5], 16)
        gnu_header = struct.unpack_from(endian + "IIII", data, gnu_offset)
        old_gnu_buckets, symoffset, bloom_size, _bloom_shift = gnu_header
        if old_gnu_buckets < 1 or bloom_size < 1 or symoffset > symbol_count:
            raise ValueError("invalid ELF DT_GNU_HASH header")
        gnu_size = (16 + bloom_size * word_size + 4 * old_gnu_buckets +
                    4 * (symbol_count - symoffset))
        vaddr_to_offset(tags[0x6FFFFEF5], gnu_size)

    return (elf_class, endian, word_size, tags, vaddr_to_offset, names,
            hash_offset, old_hash_size, gnu_offset, gnu_size, gnu_header)


def _gnu_hash(name: bytes) -> int:
    value = 5381
    for byte in name:
        value = ((value << 5) + value + byte) & 0xFFFFFFFF
    return value


def rebuild_dynamic_symbol_hashes(data: bytes) -> tuple[bytes, list[str]]:
    """Rebuild DT_HASH and DT_GNU_HASH after changing .dynstr symbol names.

    One bucket deliberately keeps the existing dynsym order valid: all hashed
    symbols form a single contiguous bucket chain. This avoids moving dynsym
    entries (and therefore avoids changing relocation/version-table indexes).
    The existing tables are large enough because reducing the bucket count can
    only make each replacement table smaller or equal in size.
    """
    (elf_class, endian, word_size, tags, _vaddr_to_offset, names,
     hash_offset, old_hash_size, gnu_offset, old_gnu_size, gnu_header) = _dynamic_symbols(data)
    symbol_count = len(names)
    out = bytearray(data)

    # Valid SysV hash table with a single bucket and a complete linear chain.
    sysv_chains = [0] * symbol_count
    for index in range(1, symbol_count):
        sysv_chains[index] = index + 1 if index + 1 < symbol_count else 0
    sysv = (struct.pack(endian + "II", 1, symbol_count) +
            struct.pack(endian + "I", 1 if symbol_count > 1 else 0) +
            struct.pack(endian + f"{symbol_count}I", *sysv_chains))
    if len(sysv) > old_hash_size:
        raise ValueError("rebuilt DT_HASH does not fit the original ELF table")
    out[hash_offset:hash_offset + len(sysv)] = sysv

    messages = [f"rebuilt DT_HASH with one bucket for {symbol_count} symbols"]
    if gnu_offset is not None and gnu_header is not None and old_gnu_size is not None:
        _old_buckets, symoffset, bloom_size, bloom_shift = gnu_header
        bloom_word_bits = word_size * 8
        bloom = [0] * bloom_size
        chain_values: list[int] = []
        for index in range(symoffset, symbol_count):
            value = _gnu_hash(names[index])
            bloom_index = (value // bloom_word_bits) % bloom_size
            bloom[bloom_index] |= 1 << (value % bloom_word_bits)
            bloom[bloom_index] |= 1 << ((value >> bloom_shift) % bloom_word_bits)
            chain_values.append(value & 0xFFFFFFFE)
        if chain_values:
            chain_values[-1] |= 1  # end of the single bucket's chain
        gnu = (struct.pack(endian + "IIII", 1, symoffset, bloom_size, bloom_shift) +
               struct.pack(endian + f"{bloom_size}{'Q' if word_size == 8 else 'I'}", *bloom) +
               struct.pack(endian + "I", symoffset if symoffset < symbol_count else 0))
        if chain_values:
            gnu += struct.pack(endian + f"{len(chain_values)}I", *chain_values)
        if len(gnu) > old_gnu_size:
            raise ValueError("rebuilt DT_GNU_HASH does not fit the original ELF table")
        out[gnu_offset:gnu_offset + len(gnu)] = gnu
        messages.append("rebuilt DT_GNU_HASH with one bucket and a refreshed bloom filter")
    return bytes(out), messages


def elf_dynamic_symbol_resolves(data: bytes, name: bytes, table: str) -> bool:
    """Simulate a SysV or GNU dynamic-hash lookup for an ELF symbol name."""
    (_, endian, word_size, tags, vaddr_to_offset, names, _hash_offset,
     _old_hash_size, gnu_offset, _gnu_size, gnu_header) = _dynamic_symbols(data)
    if table == "sysv":
        offset = vaddr_to_offset(tags[4], 8)
        bucket_count, symbol_count = struct.unpack_from(endian + "II", data, offset)
        bucket_offset = offset + 8
        chain_offset = bucket_offset + 4 * bucket_count
        bucket = struct.unpack_from(endian + "I", data,
                                    bucket_offset + 4 * (_sysv_hash(name) % bucket_count))[0]
        seen = 0
        while bucket and bucket < symbol_count and seen < symbol_count:
            if names[bucket] == name:
                return True
            bucket = struct.unpack_from(endian + "I", data, chain_offset + 4 * bucket)[0]
            seen += 1
        return False
    if table != "gnu" or gnu_offset is None or gnu_header is None:
        return False

    bucket_count, symoffset, bloom_size, bloom_shift = struct.unpack_from(
        endian + "IIII", data, gnu_offset)
    if bucket_count < 1 or bloom_size < 1:
        return False
    word_fmt = "Q" if word_size == 8 else "I"
    bloom_offset = gnu_offset + 16
    bloom_index = (_gnu_hash(name) // (word_size * 8)) % bloom_size
    bloom_word = struct.unpack_from(endian + word_fmt, data,
                                    bloom_offset + bloom_index * word_size)[0]
    value = _gnu_hash(name)
    mask = (1 << (value % (word_size * 8))) | (1 << ((value >> bloom_shift) % (word_size * 8)))
    if bloom_word & mask != mask:
        return False
    bucket_offset = bloom_offset + bloom_size * word_size
    chain_offset = bucket_offset + 4 * bucket_count
    index = struct.unpack_from(endian + "I", data,
                               bucket_offset + 4 * (value % bucket_count))[0]
    symbol_count = len(names)
    while index >= symoffset and index < symbol_count:
        chain = struct.unpack_from(endian + "I", data,
                                   chain_offset + 4 * (index - symoffset))[0]
        if (chain | 1) == (value | 1) and names[index] == name:
            return True
        if chain & 1:
            return False
        index += 1
    return False


def _sysv_hash(name: bytes) -> int:
    value = 0
    for byte in name:
        value = (value << 4) + byte
        high = value & 0xF0000000
        if high:
            value ^= high >> 24
        value &= ~high
    return value & 0xFFFFFFFF


# --------------------------------------------------------------------------
# AAR driver
# --------------------------------------------------------------------------

def relocate_aar(src: Path, dst: Path, class_prefix: tuple[str, str],
                 lib_name: tuple[str, str]) -> None:
    old_pkg, _ = class_prefix
    old_lib, new_lib = lib_name
    with zipfile.ZipFile(src, "r") as aar:
        entries = {info.filename: aar.read(info.filename)
                   for info in aar.infolist()}

    if "classes.jar" not in entries:
        raise SystemExit(f"{src}: not an AAR (classes.jar missing)")

    jar = entries["classes.jar"]
    go_classes = collect_go_class_names(jar, old_pkg)
    print(f"go package classes found in classes.jar: "
          f"{sorted(c.decode() for c in go_classes)}")

    entries["classes.jar"], class_report = rewrite_classes_jar(
        jar, class_prefix, lib_name)
    print(f"rewrote classes.jar ({len(class_report)} relocated files)")

    # Rename jni/<abi>/libgojni.so -> jni/<abi>/libpsiphon-gojni.so first so
    # the patch pass below sees the final file set.
    renames: list[tuple[str, str]] = []
    for name in sorted(list(entries)):
        base = name.rsplit("/", 1)[-1]
        if name.startswith("jni/") and base == f"lib{old_lib}.so":
            new_name = name[: -len(f"lib{old_lib}.so")] + f"lib{new_lib}.so"
            entries[new_name] = entries.pop(name)
            renames.append((name, new_name))
    if not renames:
        print(f"WARNING: no jni/*/lib{old_lib}.so found in {src} — "
              f"nothing to rename (is this the right AAR?)")

    so_count = 0
    for name in sorted(entries):
        if name.startswith("jni/") and name.endswith(".so"):
            patched, rep = patch_so(entries[name], class_prefix, go_classes)
            entries[name] = patched
            so_count += 1
            print(f"patched native library {name}:")
            for line in rep:
                print(f"    {line}")
    for old_name, new_name in renames:
        print(f"renamed {old_name} -> {new_name}")
        so_count += 1

    # ---------------------- verification (hard fail) -------------------
    verify(entries, class_prefix, lib_name, go_classes)

    dst.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as aar:
        for name in sorted(entries):
            aar.writestr(name, entries[name])
    print(f"\nOK: wrote {dst} ({dst.stat().st_size} bytes, "
          f"{so_count} native libs processed)")


def verify(entries: dict[str, bytes], class_prefix: tuple[str, str],
           lib_name: tuple[str, str], go_classes: set[bytes]) -> None:
    old_pkg, new_pkg = class_prefix
    old_lib, new_lib = lib_name
    problems: list[str] = []

    # classes.jar: no go/* class refs, no "gojni" utf8, gi/* present,
    # ca/psiphon present.
    jar = entries["classes.jar"]
    with zipfile.ZipFile(BytesIO(jar), "r") as z:
        names = z.namelist()
        if not any(n.startswith(new_pkg + "/") for n in names):
            problems.append(f"no {new_pkg}/* classes in rewritten jar")
        if any(n.startswith(old_pkg + "/") for n in names):
            problems.append(f"{old_pkg}/* classes still present in jar")
        has_psiphon = any(n.startswith("ca/psiphon/") for n in names)
        if not has_psiphon:
            print("  note: no ca/psiphon classes (unexpected for "
                  "psiphontunnel AAR)")
        for info in z.infolist():
            if not info.filename.endswith(".class"):
                continue
            blob = z.read(info.filename)
            old_cls = ("L" + old_pkg + "/").encode()
            if old_cls in blob:
                problems.append(
                    f"{info.filename}: descriptor still references "
                    f"L{old_pkg}/")
            cp_names = utf8_constants(blob)
            if old_lib.encode() in cp_names:
                problems.append(
                    f"{info.filename}: still contains loadLibrary "
                    f"string \"{old_lib}\"")
            for cls in go_classes:
                # Substring test on the raw class bytes: catches both real
                # CONSTANT_Class refs and any utf8 (log strings, descriptors)
                # that still mentions the old bridge class names.
                if cls in blob:
                    problems.append(
                        f"{info.filename}: reference to {cls.decode()} "
                        f"survived")

    # Native libs: no Java_go_ exports / go/Seq strings may survive anywhere;
    # every packaged Psiphon ABI must resolve the initializer through both
    # ELF hash tables, not merely contain its renamed string in .dynstr.
    saw_gi_exports = False
    saw_gi_init = False
    gi_init = b"Java_" + new_pkg.encode() + b"_Seq_init"
    for name, blob in entries.items():
        if not (name.startswith("jni/") and name.endswith(".so")):
            continue
        if b"Java_" + old_pkg.encode() + b"_" in blob:
            problems.append(f"{name}: Java_{old_pkg}_* JNI exports survived")
        if (b"Java_" + new_pkg.encode() + b"_") in blob:
            saw_gi_exports = True
        if name.endswith(f"/lib{new_lib}.so"):
            abi = name.split("/")[1]
            if gi_init not in blob:
                problems.append(f"{name}: {gi_init.decode()} export is missing")
            else:
                saw_gi_init = True
                for table, table_tag in (("gnu", "DT_GNU_HASH"), ("sysv", "DT_HASH")):
                    try:
                        resolves = elf_dynamic_symbol_resolves(blob, gi_init, table)
                    except (ValueError, struct.error) as error:
                        problems.append(f"{name}: cannot validate {table_tag} symbol lookup: {error}")
                        continue
                    if not resolves:
                        problems.append(
                            f"{name}: {gi_init.decode()} is unreachable through {table_tag}"
                        )
                print(f"  {abi}: {gi_init.decode()} resolves through DT_GNU_HASH and DT_HASH")
        for cls in go_classes:
            if cls in blob:
                problems.append(
                    f"{name}: FindClass string {cls.decode()} survived")
    if not saw_gi_exports:
        problems.append(f"no jni/*.so carries Java_{new_pkg}_* exports — "
                        "the rename was a no-op?")
    if not saw_gi_init:
        problems.append(f"no lib{new_lib}.so exports {gi_init.decode()}")

    if problems:
        print("\nVERIFICATION FAILED:", file=sys.stderr)
        for p in problems:
            print("  - " + p, file=sys.stderr)
        raise SystemExit(2)
    print("verification passed: no `go` bridge references survive")


def utf8_constants(class_bytes: bytes) -> set[bytes]:
    """All CONSTANT_Utf8 payloads of a class file."""
    out: set[bytes] = set()
    data = class_bytes
    cp_count = struct.unpack_from(">H", data, 8)[0]
    idx = 10
    i = 1
    while i < cp_count:
        tag = data[idx]
        idx += 1
        if tag == 1:
            ln = struct.unpack_from(">H", data, idx)[0]
            idx += 2
            out.add(data[idx:idx + ln])
            idx += ln
        elif tag in (3, 4):
            idx += 4
        elif tag in (5, 6):
            idx += 8
            i += 1
        elif tag in (7, 8):
            idx += 2
        elif tag in (9, 10, 11, 12, 17, 18):
            idx += 4
        elif tag == 15:
            idx += 3
        elif tag in (16, 19, 20):
            idx += 2
        else:
            raise ValueError("malformed class file: bad pool tag "
                             f"{tag} at #{i} (rewrite corrupted it)")
        i += 1
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--in", dest="src", required=True, type=Path)
    ap.add_argument("--out", dest="dst", required=True, type=Path)
    ap.add_argument("--go-package", default="go:gi",
                    help="old:new gomobile bridge package (default go:gi)")
    ap.add_argument("--lib-name", default="gojni:psiphon-gojni",
                    help="old:new native library short name "
                         "(default gojni:psiphon-gojni)")
    args = ap.parse_args()

    class_prefix = tuple(args.go_package.split(":"))  # type: ignore
    lib_name = tuple(args.lib_name.split(":"))        # type: ignore
    if len(class_prefix) != 2 or len(lib_name) != 2:
        raise SystemExit("--go-package/--lib-name must be old:new")
    if len(class_prefix[0]) != len(class_prefix[1]):
        raise SystemExit("go package names must have equal length "
                         "(ELF patching is length-preserving)")

    relocate_aar(args.src, args.dst, class_prefix, lib_name)  # type: ignore


if __name__ == "__main__":
    main()

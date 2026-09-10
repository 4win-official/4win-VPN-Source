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
                 lib_name: tuple[str, str]):
        self.data = data
        self.old_pkg, self.new_pkg = class_prefix  # e.g. ("go", "gi")
        self.old_lib, self.new_lib = lib_name      # e.g. ("gojni", "psiphon-gojni")
        self.patches: list[str] = []

    def rewrite(self) -> bytes:
        data = self.data
        if data[:4] != b"\xca\xfe\xba\xbe":
            raise ValueError("not a Java class file")
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
            elif tag == 16:            # Module/Package
                idx += 2
            else:
                raise ValueError(f"unsupported constant-pool tag {tag} at #{i}")
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
            elif tag == 16:
                out += data[entry_start:idx + 2]
                idx += 2
            else:
                raise ValueError(f"unsupported tag {tag}")
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
                    payload, class_prefix, lib_name).rewrite()
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
# ELF patching (.dynstr JNI export names + FindClass strings)
# --------------------------------------------------------------------------

def elf_sh_link(data: bytes, index: int) -> int:
    """Returns sh_link of the given section header."""
    if data[:4] != b"\x7fELF":
        raise ValueError("not an ELF file")
    is64 = data[4] == 2
    little = data[5] == 1
    end = "<" if little else ">"
    if is64:
        e_shoff = struct.unpack_from(end + "Q", data, 0x28)[0]
        e_shentsize = struct.unpack_from(end + "H", data, 0x3A)[0]
    else:
        e_shoff = struct.unpack_from(end + "I", data, 0x20)[0]
        e_shentsize = struct.unpack_from(end + "H", data, 0x2E)[0]
    base = e_shoff + index * e_shentsize
    if is64:
        return struct.unpack_from(end + "I", data, base + 0x28)[0]
    return struct.unpack_from(end + "I", data, base + 0x18)[0]


def elf_sections(data: bytes):
    """Yields (index, name, sh_type, sh_offset, sh_size) for ELF32/ELF64."""
    if data[:4] != b"\x7fELF":
        raise ValueError("not an ELF file")
    is64 = data[4] == 2
    little = data[5] == 1
    end = "<" if little else ">"
    if is64:
        e_shoff = struct.unpack_from(end + "Q", data, 0x28)[0]
        e_shentsize = struct.unpack_from(end + "H", data, 0x3A)[0]
        e_shnum = struct.unpack_from(end + "H", data, 0x3C)[0]
        e_shstrndx = struct.unpack_from(end + "H", data, 0x3E)[0]
    else:
        e_shoff = struct.unpack_from(end + "I", data, 0x20)[0]
        e_shentsize = struct.unpack_from(end + "H", data, 0x2E)[0]
        e_shnum = struct.unpack_from(end + "H", data, 0x30)[0]
        e_shstrndx = struct.unpack_from(end + "H", data, 0x32)[0]

    def sh(i: int):
        base = e_shoff + i * e_shentsize
        if is64:
            name, typ, _f, _a, off, size = struct.unpack_from(
                end + "IIQQQQ", data, base)
        else:
            name, typ, _f, _a, off, size = struct.unpack_from(
                end + "IIIIII", data, base)
        return name, typ, off, size

    strtab_off = sh(e_shstrndx)[2]
    def cstr(off: int) -> str:
        endpos = data.index(b"\x00", strtab_off + off)
        return data[strtab_off + off:endpos].decode()

    for i in range(e_shnum):
        name_off, typ, off, size = sh(i)
        yield i, cstr(name_off), typ, off, size


SHT_DYNSYM = 11
SHT_SYMTAB = 2
SHT_STRTAB = 3


def patch_symtab(buf: bytes, sym_off: int, sym_size: int, str_off: int,
                 old_pkg: str, new_pkg: str) -> tuple[int, set[bytes], set[bytes]]:
    """Renames Java_<old>_* symbol names inside one symtab/strtab pair.
    Returns (renamed_count, names_before, names_after)."""
    renamed = 0
    entry = 24 if buf[4] == 2 else 16
    old_prefix = ("Java_" + old_pkg + "_").encode()
    new_prefix = ("Java_" + new_pkg + "_").encode()
    assert len(old_prefix) == len(new_prefix)
    names_before: set[bytes] = set()
    for pos in range(sym_off, sym_off + sym_size, entry):
        st_name = struct.unpack_from("<I", buf, pos)[0]
        if st_name == 0:
            continue
        start = str_off + st_name
        nul = buf.index(0, start)
        names_before.add(bytes(buf[start:nul]))
        if bytes(buf[start:nul]).startswith(old_prefix):
            base = start + len("Java_")
            buf[base:base + len(old_pkg)] = new_pkg.encode()
            renamed += 1
    names_after: set[bytes] = set()
    for pos in range(sym_off, sym_off + sym_size, entry):
        st_name = struct.unpack_from("<I", buf, pos)[0]
        if st_name == 0:
            continue
        start = str_off + st_name
        nul = buf.index(0, start)
        names_after.add(bytes(buf[start:nul]))
    expected = {(n if not n.startswith(old_prefix)
                 else new_prefix + n[len(old_prefix):])
                for n in names_before}
    if names_after != expected:
        raise ValueError("strtab patch corrupted unrelated symbol names")
    return renamed, names_before, names_after


def patch_so(data: bytes, class_prefix: tuple[str, str],
             go_class_names: set[bytes]) -> tuple[bytes, list[str]]:
    """In-place, length-preserving patches for a gomobile .so.

    1. .dynstr (+ .strtab if present): rename JNI exports
       Java_<old>_...  ->  Java_<new>_...
    2. Whole file: rewrite baked-in class-name strings go/Seq -> gi/Seq etc.
    Returns (patched_bytes, report).
    """
    old_pkg, new_pkg = class_prefix
    report: list[str] = []
    buf = bytearray(data)

    # ---- 1. symbol table names -----------------------------------------
    renamed = 0
    tables: list[tuple[int, int, int, int]] = []  # (sym_off, sym_size, str_off, str_size)
    strtabs: dict[int, tuple[int, int]] = {}      # section index -> (off, size)
    section_list = list(elf_sections(data))
    for si, _name, typ, off, size in section_list:
        if typ == SHT_STRTAB:
            strtabs[si] = (off, size)
    for si, _name, typ, off, size in section_list:
        if typ in (SHT_DYNSYM, SHT_SYMTAB):
            link = elf_sh_link(data, si)
            if link in strtabs:
                str_off, str_size = strtabs[link]
                tables.append((off, size, str_off, str_size))
    if not tables:
        raise ValueError("no symbol tables found — unexpected .so layout")

    seen_tables = 0
    for sym_off, sym_size, str_off, str_size in tables:
        n, _before, _after = patch_symtab(
            buf, sym_off, sym_size, str_off, old_pkg, new_pkg)
        renamed += n
        seen_tables += 1
    report.append(f"  renamed {renamed} JNI export(s) Java_{old_pkg}_* "
                  f"-> Java_{new_pkg}_* across {seen_tables} symbol table(s)")

    # ---- 2. baked-in FindClass strings ---------------------------------
    total = 0
    for cls in sorted(go_class_names, key=len, reverse=True):
        old = cls
        new = new_pkg.encode() + cls[len(old_pkg):]
        count = buf.count(old)
        if count:
            idx = 0
            for _ in range(count):
                idx = buf.find(old, idx)
                buf[idx:idx + len(old)] = new
                idx += len(new)
            total += count
            report.append(f"  {old.decode()} -> {new.decode()} x{count}")

    return bytes(buf), report


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

    # native libs: no Java_go_ exports, no go/Seq strings, expected gi ones.
    for name, blob in entries.items():
        if not (name.startswith("jni/") and name.endswith(".so")):
            continue
        if b"Java_" + old_pkg.encode() + b"_" in blob:
            problems.append(f"{name}: Java_{old_pkg}_* JNI exports survived")
        for cls in go_classes:
            if cls in blob:
                problems.append(
                    f"{name}: FindClass string {cls.decode()} survived")
        if ("Java_" + new_pkg + "_").encode() not in blob:
            problems.append(f"{name}: no Java_{new_pkg}_* exports found")

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
        elif tag == 16:
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

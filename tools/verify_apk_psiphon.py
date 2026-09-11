#!/usr/bin/env python3
"""
verify_apk_psiphon.py — CI/local guard for the Psiphon runtime isolation.

Asserts the built APK contains the result of the go -> gi relocation:

  1. lib/<abi>/libpsiphon-gojni.so  present for every ABI shipped
     (the relocated Psiphon Go runtime)
  2. lib/<abi>/libgojni.so          present for every ABI shipped
     (the Xray Go runtime — must keep its own name)
  3. classes*.dex contain the relocated bridge class  Lgi/Seq;
     alongside Xray's own bridge  Lgo/Seq;  and ca/psiphon/PsiphonTunnel
  4. no dex references the removed  com.forwin.psiphon_bridge  plugin

Exit code 0 = APK is correctly assembled, 2 = something is wrong.

Usage: python3 verify_apk_psiphon.py <app-release.apk>
"""

from __future__ import annotations

import sys
import zipfile
from pathlib import Path

ABIS = ("arm64-v8a", "armeabi-v7a", "x86", "x86_64")


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 1
    apk = Path(sys.argv[1])
    if not apk.is_file():
        print(f"ERROR: {apk} not found")
        return 2

    problems: list[str] = []
    with zipfile.ZipFile(apk, "r") as z:
        names = z.namelist()

        shipped = {abi for abi in ABIS
                   if any(f"lib/{abi}/" in n for n in names)}
        if not shipped:
            problems.append("no native libraries found in APK")
        for abi in sorted(shipped):
            if f"lib/{abi}/libpsiphon-gojni.so" not in names:
                problems.append(f"lib/{abi}/libpsiphon-gojni.so MISSING — "
                                f"Psiphon runtime was not relocated/renamed")
            if f"lib/{abi}/libgojni.so" not in names:
                problems.append(f"lib/{abi}/libgojni.so MISSING — "
                                f"Xray runtime lost from the APK")

        dex_blob = b""
        for n in names:
            if n.startswith("classes") and n.endswith(".dex"):
                dex_blob += z.read(n)
        if not dex_blob:
            problems.append("no classes*.dex found")

        for marker, why in (
            (b"Lgi/Seq;", "relocated Psiphon bridge gi.Seq not in dex"),
            (b"Lgo/Seq;", "Xray bridge go.Seq not in dex"),
            (b"Lca/psiphon/PsiphonTunnel;",
             "ca.psiphon.PsiphonTunnel not in dex"),
        ):
            if marker not in dex_blob:
                problems.append(f"{why} ({marker.decode()})")

        if b"Lcom/forwin/psiphon_bridge/" in dex_blob:
            problems.append("removed psiphon_bridge plugin still in the dex")

    if problems:
        print(f"APK VERIFICATION FAILED for {apk}:")
        for p in problems:
            print("  - " + p)
        return 2
    print(f"APK verification passed: {apk}")
    print(f"  ABIs: {', '.join(sorted(shipped))}")
    print("  libpsiphon-gojni.so + libgojni.so present, "
          "gi/Seq + go/Seq + ca/psiphon classes present, plugin removed")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""
trim_libv2ray_aar.py — Strip the unused GeoIP/GeoSite databases out of the
Xray core AAR (libv2ray.aar) at build time.

WHY THIS EXISTS
===============
libv2ray.aar (AndroidLibXrayLite, a.k.a. the exact core v2rayNG ships)
bundles three asset files meant for `geoip:*` / `geosite:*` routing-rule
tags:

    assets/geoip.dat                  (~20 MB)
    assets/geosite.dat                (~10 MB)
    assets/geoip-only-cn-private.dat  (~75 KB)

4win VPN's Xray configs (see lib/services/xray_config_builder.dart) route
purely on literal IP/CIDR ranges and plain outbound tags — grep the whole
Dart/Kotlin tree and there is not a single `geoip:` or `geosite:` reference
anywhere. Those ~31 MB are therefore pure dead weight that AGP happily packs
into every release APK for no functional benefit, and are the single
largest contributor to the app's installed/download size after Psiphon's
own runtime was added.

This script does NOT touch any native code, any ABI, or remove any
protocol/feature — it only deletes three unused data files from the AAR's
`assets/` folder before it is compiled in. If a future feature ever needs
geoip/geosite routing, this task should simply be dropped (or the two
files re-added under `assets/` before this task runs).

USAGE
=====
  python3 trim_libv2ray_aar.py --in <original.aar> --out <trimmed.aar>
                                [--drop assets/geoip.dat,assets/geosite.dat,assets/geoip-only-cn-private.dat]
"""

from __future__ import annotations

import argparse
import sys
import zipfile
from pathlib import Path

DEFAULT_DROP = (
    "assets/geoip.dat",
    "assets/geosite.dat",
    "assets/geoip-only-cn-private.dat",
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--in", dest="inp", required=True, help="input libv2ray.aar")
    parser.add_argument("--out", dest="out", required=True, help="output trimmed .aar")
    parser.add_argument(
        "--drop",
        default=",".join(DEFAULT_DROP),
        help="comma-separated zip entry names to drop",
    )
    args = parser.parse_args()

    src = Path(args.inp)
    dst = Path(args.out)
    if not src.is_file():
        print(f"ERROR: input AAR not found: {src}", file=sys.stderr)
        return 2

    drop = {p.strip() for p in args.drop.split(",") if p.strip()}

    dst.parent.mkdir(parents=True, exist_ok=True)

    dropped: list[str] = []
    kept = 0
    with zipfile.ZipFile(src, "r") as zin:
        names = zin.namelist()
        missing = drop - set(names)
        if missing:
            # Not fatal: the AAR may already be trimmed (e.g. a re-run), or a
            # newer libv2ray release may have renamed/removed these assets.
            print(f"NOTE: some entries to drop were not present: {sorted(missing)}")

        with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as zout:
            for item in zin.infolist():
                if item.filename in drop:
                    dropped.append(item.filename)
                    continue
                zout.writestr(item, zin.read(item.filename))
                kept += 1

    saved = sum(
        zipfile.ZipFile(src).getinfo(n).file_size
        for n in dropped
        if n in zipfile.ZipFile(src).namelist()
    )
    print(
        f"Trimmed {src.name} -> {dst.name}: dropped {len(dropped)} entr"
        f"{'y' if len(dropped) == 1 else 'ies'} ({saved / 1_000_000:.1f} MB "
        f"uncompressed), kept {kept} entries."
    )
    for n in dropped:
        print(f"  - {n}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

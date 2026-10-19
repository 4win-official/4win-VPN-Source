#!/usr/bin/env python3
"""Build the official, checksum-pinned dnstt client as an Android executable.

The .so suffix lets Android install/extract this PIE executable into its trusted
nativeLibraryDir. It is executed, never loaded with System.loadLibrary.
No Go runtime is added to the app process. Build/cache outputs stay under build/.
"""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.request
import zipfile

VERSION = '20260501'
URL = f'https://www.bamsoftware.com/software/dnstt/dnstt-{VERSION}.zip'
SHA256 = 'a7b21d3d787570d9127643e360e150d2da7b33aa8039d0546a04dcfe8ee1864f'
TARGETS = {
    'arm64-v8a': ('arm64', 'aarch64-linux-android24-clang'),
    'armeabi-v7a': ('arm', 'armv7a-linux-androideabi24-clang'),
    'x86_64': ('amd64', 'x86_64-linux-android24-clang'),
    'x86': ('386', 'i686-linux-android24-clang'),
}


def source(cache: Path) -> Path:
    archive = cache / f'dnstt-{VERSION}.zip'
    cache.mkdir(parents=True, exist_ok=True)
    if not archive.exists():
        print(f'Downloading official dnstt {VERSION}', flush=True)
        temporary = archive.with_suffix('.download')
        try:
            with urllib.request.urlopen(URL, timeout=60) as response:
                temporary.write_bytes(response.read())
            if hashlib.sha256(temporary.read_bytes()).hexdigest() != SHA256:
                raise RuntimeError('dnstt archive checksum mismatch')
            temporary.replace(archive)
        finally:
            temporary.unlink(missing_ok=True)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
        raise RuntimeError(f'dnstt archive checksum mismatch: {archive}')
    destination = cache / f'dnstt-{VERSION}'
    # Re-extract the trusted archive so local edits cannot silently enter builds.
    if destination.exists():
        shutil.rmtree(destination)
    with zipfile.ZipFile(archive) as zipped:
        root = cache.resolve()
        for member in zipped.infolist():
            if not (cache / member.filename).resolve().is_relative_to(root):
                raise RuntimeError('Unsafe path in dnstt archive')
        zipped.extractall(cache)
    return destination


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ndk', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--cache', type=Path, default=Path('build/slowdns-source'))
    parser.add_argument('--abi', choices=TARGETS, action='append')
    args = parser.parse_args()
    if not shutil.which('go'):
        raise RuntimeError('Go 1.21 or later is required to build Slow DNS')
    host = 'darwin-x86_64' if sys.platform == 'darwin' else 'linux-x86_64'
    if sys.platform == 'win32':
        host = 'windows-x86_64'
    compiler_dir = args.ndk.resolve() / 'toolchains/llvm/prebuilt' / host / 'bin'
    src = source(args.cache.resolve())
    output = args.output.resolve()
    for abi in args.abi or list(TARGETS):
        arch, compiler = TARGETS[abi]
        cc = compiler_dir / (compiler + ('.cmd' if sys.platform == 'win32' else ''))
        if not cc.exists():
            raise RuntimeError(f'Android NDK compiler not found: {cc}')
        env = dict(os.environ, GOOS='android', GOARCH=arch, CGO_ENABLED='1', CC=str(cc))
        if arch == 'arm':
            env['GOARM'] = '7'
        destination = output / abi / 'libdnstt.so'
        destination.parent.mkdir(parents=True, exist_ok=True)
        print(f'Building dnstt {VERSION} for {abi}', flush=True)
        subprocess.run([
            'go', 'build', '-mod=readonly', '-trimpath', '-buildmode=pie',
            '-ldflags=-s -w -linkmode=external -extldflags=-Wl,-z,max-page-size=16384',
            '-o', str(destination), './dnstt-client',
        ], cwd=src, env=env, check=True)
    # Keep upstream licensing/provenance next to the generated build artifacts.
    shutil.copyfile(src / 'COPYING', output / 'DNSTT-COPYING.txt')


if __name__ == '__main__':
    main()

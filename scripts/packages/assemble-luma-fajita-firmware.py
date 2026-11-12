#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Assemble the OnePlus 6T firmware set as a tar of usr/lib/firmware.

The set is exactly devices/oneplus/fajita/firmware.manifest, taken from the
postmarketOS and Alpine packages below (pinned by SHA-256). postmarketOS keeps
some files in /usr/lib/firmware/postmarketos; the manifest has them at the
top level, where the kernel looks. Firmware is not kept in Git: the archives
are downloaded once into CACHE, and the tar is the input of
scripts/packages/build-luma-fajita-firmware.sh.

usage: assemble-luma-fajita-firmware.py --cache DIR --output FILE.tar
"""
from __future__ import annotations

import argparse
import hashlib
import io
import os
import subprocess
import tarfile
import tempfile
import tomllib
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEVICE = ROOT / "devices/oneplus/fajita"

# (name, url, sha256): postmarketOS v26.06 and Alpine v3.24, the packages the
# phone was tested with (device.toml [firmware]).
SOURCES = (
    ("firmware-oneplus-sdm845-14-r0.apk",
     "https://mirror.postmarketos.org/postmarketos/v26.06/aarch64/firmware-oneplus-sdm845-14-r0.apk",
     "af3396d85df18fe84bcf00f65c51edc61f92d5807a1dd7b184f7121c45511f27"),
    ("linux-firmware-ath10k-20260519-r0.apk",
     "https://dl-cdn.alpinelinux.org/alpine/v3.24/main/aarch64/linux-firmware-ath10k-20260519-r0.apk",
     "bbd2732620c479f146638d2d9bee0cd0732e982a2304f2473b3f749f97cebe9e"),
    ("linux-firmware-qca-20260519-r0.apk",
     "https://dl-cdn.alpinelinux.org/alpine/v3.24/main/aarch64/linux-firmware-qca-20260519-r0.apk",
     "6b3a815e06afe10aed121f3815bb15930f5bb76d6c45a5f96d86cc019293f63a"),
    ("linux-firmware-qcom-20260519-r0.apk",
     "https://dl-cdn.alpinelinux.org/alpine/v3.24/main/aarch64/linux-firmware-qcom-20260519-r0.apk",
     "9f9001e32005ba40b7df7357bf6e9e9b05966846654912ed99f93d03a529509f"),
)


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def fetch(cache: Path, name: str, url: str, sha256: str) -> Path:
    path = cache / name
    if not path.exists():
        partial = path.with_name(name + ".part")
        with urllib.request.urlopen(url, timeout=300) as remote, partial.open("wb") as out:
            while chunk := remote.read(1 << 20):
                out.write(chunk)
        partial.rename(path)
    if path.is_symlink() or digest(path) != sha256:
        raise SystemExit(f"{name}: hash mismatch")
    return path


def manifest() -> list[tuple[str, str, str, str, str]]:
    device = tomllib.loads((DEVICE / "device.toml").read_text())
    raw = (DEVICE / "firmware.manifest").read_bytes()
    if hashlib.sha256(raw).hexdigest() != device["firmware"]["manifest_sha256"]:
        raise SystemExit("firmware.manifest does not match device.toml")
    rows = [tuple(line.split("\t")) for line in raw.decode().splitlines()]
    header, rows = rows[0], rows[1:]
    if header[0] != "H" or int(header[1]) != device["firmware"]["files"]:
        raise SystemExit("firmware.manifest header")
    return rows


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.cache.mkdir(parents=True, exist_ok=True)
    rows = manifest()
    with tempfile.TemporaryDirectory() as tmp:
        tree = Path(tmp)
        for name, url, sha256 in SOURCES:
            # An apk is concatenated gzip tar segments; GNU tar reads them all.
            subprocess.run(["tar", "-xzf", fetch(args.cache, name, url, sha256), "-C", tmp,
                            "--no-same-owner", "--wildcards", "*lib/firmware/*"],
                           check=True, stderr=subprocess.DEVNULL)
        sources = [tree / "usr/lib/firmware/postmarketos", tree / "usr/lib/firmware", tree / "lib/firmware"]

        def locate(relative: str, sha256: str) -> bytes:
            # Alpine and postmarketOS can both carry a name; the manifest's
            # digest says which one the phone was tested with.
            for base in sources:
                candidate = base / relative
                if candidate.is_file() and not candidate.is_symlink():
                    data = candidate.read_bytes()
                    if hashlib.sha256(data).hexdigest() == sha256:
                        return data
            raise SystemExit(f"{relative}: no package carries the manifest's file")

        files = 0
        buffer = io.BytesIO()
        with tarfile.open(fileobj=buffer, mode="w", format=tarfile.GNU_FORMAT) as out:
            def add(info: tarfile.TarInfo, data: bytes | None = None) -> None:
                info.uid = info.gid = 0
                info.uname = info.gname = "root"
                info.mtime = 0
                out.addfile(info, io.BytesIO(data) if data is not None else None)
            for parent in ("usr", "usr/lib", "usr/lib/firmware"):
                info = tarfile.TarInfo(parent)
                info.type, info.mode = tarfile.DIRTYPE, 0o755
                add(info)
            for kind, mode, sha256, relative, target in rows:
                info = tarfile.TarInfo("usr/lib/firmware/" + relative)
                info.mode = int(mode, 8)
                if kind == "D":
                    info.type = tarfile.DIRTYPE
                    add(info)
                elif kind == "L":
                    info.type, info.linkname, info.mode = tarfile.SYMTYPE, target, 0o777
                    add(info)
                elif kind == "F":
                    data = locate(relative, sha256)
                    info.size = len(data)
                    add(info, data)
                    files += 1
                else:
                    raise SystemExit(f"unknown manifest row {kind}")
        if files != len([r for r in rows if r[0] == "F"]):
            raise SystemExit("file count")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        partial = args.output.with_name(args.output.name + ".part")
        partial.write_bytes(buffer.getvalue())
        os.replace(partial, args.output)
    print(f"{files} firmware files: {args.output} {digest(args.output)}")


if __name__ == "__main__":
    main()

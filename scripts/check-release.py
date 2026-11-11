#!/usr/bin/env python3
"""Validate release versions and packages before anything is published."""

import argparse
import hashlib
import os
from pathlib import Path
import re
import struct
import xml.etree.ElementTree as ET


def check_version(root=Path("."), tag=None):
    match = re.search(r"^version: ['\"]?(\d+\.\d+\.\d+)['\"]?\s*$",
                      (root / "shard.yml").read_text(), re.MULTILINE)
    if not match:
        raise ValueError("shard.yml must contain a release version")
    version = match.group(1)
    latest = ET.parse(root / "com.github.kojix2.memo.metainfo.xml").find("releases/release")
    if latest is None or latest.get("version") != version:
        raise ValueError(f"AppStream's latest release must be {version}")
    if tag is not None and tag != f"v{version}":
        raise ValueError(f"Tag {tag!r} does not match shard.yml: v{version}")
    return version


def check_artifacts(directory, version):
    required = [f"memo_{version}_amd64.deb", f"memo_{version}_ucrt64.exe",
                f"memo_{version}_ucrt64_setup.exe"]
    dmgs = sorted(directory.glob(f"memo_{version}_*.dmg"))
    if not dmgs:
        raise ValueError("Missing macOS DMG")
    allowed_dmgs = {f"memo_{version}_aarch64.dmg", f"memo_{version}_x86_64.dmg"}
    if any(dmg.name not in allowed_dmgs for dmg in dmgs):
        raise ValueError("Unexpected macOS package architecture")
    packages = [directory / name for name in required] + dmgs
    actual = {file for file in directory.iterdir() if file.suffix in {".deb", ".exe", ".dmg"}}
    if actual != set(packages):
        raise ValueError("Release must contain the matching DMG, DEB, Windows EXE and installer")
    for package in packages:
        if not package.is_file() or package.stat().st_size == 0:
            raise ValueError(f"Missing or empty package: {package.name}")
        with package.open("rb") as stream:
            header = stream.read(64)
            if package.suffix == ".deb":
                valid = header.startswith(b"!<arch>\n")
            elif package.suffix == ".dmg":
                valid = package.stat().st_size >= 512
                if valid:
                    stream.seek(-512, 2)
                    valid = stream.read(4) == b"koly"
            else:
                valid = len(header) == 64 and header[:2] == b"MZ"
                if valid:
                    stream.seek(struct.unpack_from("<I", header, 60)[0])
                    valid = stream.read(4) == b"PE\0\0"
            if not valid:
                raise ValueError(f"Invalid package format: {package.name}")
    checksums = []
    for package in sorted(packages):
        with package.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        checksums.append(f"{digest}  {package.name}\n")
    (directory / "SHA256SUMS").write_text("".join(checksums))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifacts", type=Path)
    args = parser.parse_args()
    tag = os.environ.get("GITHUB_REF_NAME") if os.environ.get("GITHUB_REF_TYPE") == "tag" else None
    try:
        version = check_version(tag=tag)
        if args.artifacts:
            check_artifacts(args.artifacts, version)
        print(version)
    except (ValueError, OSError, ET.ParseError) as error:
        parser.exit(1, f"Release validation failed: {error}\n")

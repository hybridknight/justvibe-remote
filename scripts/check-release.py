#!/usr/bin/env python3
"""Reject release tags that disagree with the shipped app metadata."""
import pathlib
import plistlib
import re
import sys
import xml.etree.ElementTree as ET


def check_release(tag, root):
    if not re.fullmatch(r"v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", tag, flags=re.ASCII):
        raise ValueError("Use a stable release tag such as v1.0.0.")
    version = tag[1:]
    with (root / "macos/Info.plist").open("rb") as source:
        macos = plistlib.load(source)["CFBundleShortVersionString"]
    windows = ET.parse(root / "windows/JustVibeRemote.App/JustVibeRemote.App.csproj").findtext("PropertyGroup/Version")
    identity = ET.parse(root / "windows/JustVibeRemote.App/app.manifest").find("{urn:schemas-microsoft-com:asm.v1}assemblyIdentity")
    manifest = identity.attrib["version"]
    for name, actual, expected in (("macOS", macos, version), ("Windows", windows, version), ("Windows manifest", manifest, version + ".0")):
        if actual != expected:
            raise ValueError(f"{name} version is {actual}; expected {expected} for {tag}.")
    return version


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 scripts/check-release.py vMAJOR.MINOR.PATCH")
    try:
        version = check_release(sys.argv[1], pathlib.Path(__file__).resolve().parents[1])
    except (ValueError, KeyError, OSError, ET.ParseError) as error:
        raise SystemExit(str(error)) from None
    print(f"Release versions match {version}.")

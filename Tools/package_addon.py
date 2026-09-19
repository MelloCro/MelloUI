#!/usr/bin/env python3
"""
Package the addon for distribution: a zip that unpacks straight into
Interface\\AddOns as a `MelloUI` folder, holding only what the client needs
(TOC, Core, Modules, Media, README, LICENSE), none of the tooling.

Usage:
  python Tools/package_addon.py            -> Tools/output/MelloUI-v<version>.zip
"""

import os
import re
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
INCLUDE_DIRS = ("Core", "Modules", "Media")
INCLUDE_FILES = ("MelloUI.toc", "README.md", "LICENSE")


def version():
    for line in open(os.path.join(ROOT, "MelloUI.toc"), encoding="utf-8-sig"):
        m = re.match(r"##\s*Version:\s*(\S+)", line)
        if m:
            return m.group(1)
    return "0.0.0"


def main():
    out_dir = os.path.join(HERE, "output")
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, f"MelloUI-v{version()}.zip")
    count = 0
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for name in INCLUDE_FILES:
            zf.write(os.path.join(ROOT, name), f"MelloUI/{name}")
            count += 1
        for d in INCLUDE_DIRS:
            for root, _, files in os.walk(os.path.join(ROOT, d)):
                for f in files:
                    full = os.path.join(root, f)
                    zf.write(full, "MelloUI/" + os.path.relpath(full, ROOT).replace(os.sep, "/"))
                    count += 1
    print(f"{out}: {count} files, {os.path.getsize(out) / 1e6:.1f} MB", file=sys.stderr)
    print(out)


if __name__ == "__main__":
    main()

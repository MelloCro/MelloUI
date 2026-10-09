"""MelloUI's feature addons (0.19.9, docs/plans/split-addons.md): every MelloUI_<x> folder at the addon's root whose
own MelloUI_<x>.toc says `## X-MelloUI-Feature: <module>`. Their Lua files are MelloUI's own code, checked like
Modules/ (check_panels, check_new_tags, the code map); the data companions (load on demand, no such line) are not.

    feature_folders(root) -> ["MelloUI_CombatText", ...]   (sorted)
    feature_files(root)   -> ["MelloUI_CombatText/CombatText.lua", ...]   (each TOC's order)
"""
import os
import re

MARK = re.compile(r"^## X-MelloUI-Feature:[ \t]*(\S+)", re.M)


def _toc(root, name):
    return os.path.join(root, name, name + ".toc")


def feature_folders(root):
    out = []
    if not os.path.isdir(root):
        return out
    for name in sorted(os.listdir(root)):
        toc = _toc(root, name)
        if name.startswith("MelloUI_") and os.path.isfile(toc):
            with open(toc, encoding="utf-8-sig", errors="replace") as fh:
                if MARK.search(fh.read()):
                    out.append(name)
    return out


def feature_files(root):
    out = []
    for name in feature_folders(root):
        with open(_toc(root, name), encoding="utf-8-sig", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if line and not line.startswith("#") and line.lower().endswith(".lua"):
                    out.append(name + "/" + line.replace("\\", "/"))
    return out

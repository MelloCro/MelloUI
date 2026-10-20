"""MelloUI's feature addons (0.19.9, docs/plans/split-addons.md): every MelloUI_<x> folder at the addon's root whose
own MelloUI_<x>.toc says `## X-MelloUI-Feature: <module>`. Their Lua files are MelloUI's own code, checked like
Modules/ (check_panels, check_new_tags, the code map); the data companions (load on demand, no such line) are not.

    feature_folders(root) -> ["MelloUI_Oldschool", "MelloUI_Chat", ...]   (the game's order: OptionalDeps first,
                             then by name)
    feature_files(root)   -> ["MelloUI_CombatText/CombatText.lua", ...]   (each TOC's order)
"""
import os
import re

MARK = re.compile(r"^## X-MelloUI-Feature:[ \t]*(\S+)", re.M)
OPTIONAL_DEPS = re.compile(r"^## OptionalDeps:[ \t]*(.+?)[ \t]*$", re.M)


def _toc(root, name):
    return os.path.join(root, name, name + ".toc")


def feature_folders(root):
    out, first = [], set()
    if not os.path.isdir(root):
        return out
    for name in sorted(os.listdir(root)):
        toc = _toc(root, name)
        if name.startswith("MelloUI_") and os.path.isfile(toc):
            with open(toc, encoding="utf-8-sig", errors="replace") as fh:
                text = fh.read()
            if MARK.search(text):
                out.append(name)
                for m in OPTIONAL_DEPS.finditer(text):
                    first.update(d.strip() for d in m.group(1).split(","))
    # (one look stage I) the game loads an addon's OptionalDeps before it: a feature another names there comes first
    # (MelloUI_Oldschool, right after MelloUI), the rest by name
    return sorted(out, key=lambda n: (n not in first, n))


def feature_files(root):
    out = []
    for name in feature_folders(root):
        with open(_toc(root, name), encoding="utf-8-sig", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if line and not line.startswith("#") and line.lower().endswith(".lua"):
                    out.append(name + "/" + line.replace("\\", "/"))
    return out

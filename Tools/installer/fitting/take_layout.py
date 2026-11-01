"""Take a new Edit Mode layout for MelloUI: Media/EditModeLayout.lua's `layout`, the user's arrangement read from the
client's own files or from a share string (2.1.0, el-15; the user, 2026-11-01, of their 3440 x 1440 arrangement: "this
is how it should look like").

    python take_layout.py --cache <WTF/Account/<acct>/edit-mode-cache-account.txt> --name <layout>   a look
    python take_layout.py --string <file>                                                          a look
    ... --write    writes it into Media/EditModeLayout.lua and keeps the source in the build data
                   (installer/editmode_<date>/: the cache or string as read, and the string written)

The account cache holds every account layout in the share string's own records (layoutcodec.decode_account_cache);
the layout named is taken as it is, its version and input style the shipped string's. A look prints what changes
against the shipped layout: each system whose anchor or settings differ, and its rect at the design screen
(hud.solve, the fitter's own size model) before and after. Read only: the client's file is only read.

Then, as for every new layout the user exports:
    python anchor_layout.py --write    every frame held to its third's edge, its rect at the design screen unchanged
    python golden.py                   the bake's goldens/source.json
    python ../bake_full.py --snapshot <SavedVariables/MelloUI.lua> --write    MelloUI's own places in the profile
"""
import argparse
import os
import shutil
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "lib"))
sys.path.insert(0, os.path.normpath(os.path.join(HERE, "..")))
import layoutcodec as C                                   # noqa: E402
import hud                                                # noqa: E402
from anchor_layout import DESIGN_H, DESIGN_W, FILE, LAYOUT_RX  # noqa: E402


def label(s):
    return s["key"] + " " + s["systemName"] + (("." + s["systemIndexName"]) if s.get("systemIndexName") else "")


def anchor_text(a):
    if not a:
        return "-"
    return "%s->%s %s (%.1f, %.1f)" % (a["point"], a["relativePoint"], a["relativeTo"], a["offsetX"], a["offsetY"])


def from_cache(path, name):
    raw = open(path, "rb").read().decode("latin-1")
    cache = C.decode_account_cache(raw)
    names = [lay["name"] for lay in cache["layouts"]]
    for lay in cache["layouts"]:
        if lay["name"] == name:
            return lay, raw
    raise SystemExit("no account layout named %r in %s (it has: %s)" % (name, path, ", ".join(repr(n) for n in names)))


def changes(old, new):
    ro, _ = hud.solve(old, DESIGN_W, DESIGN_H)
    rn, _ = hud.solve(new, DESIGN_W, DESIGN_H)
    by = {s["key"]: s for s in old["systems"]}
    out = []
    for s in new["systems"]:
        o = by.get(s["key"])
        if o is None:
            out.append("%-40s new system" % label(s))
            continue
        what = []
        if anchor_text(o["anchor"]) != anchor_text(s["anchor"]) or anchor_text(o.get("anchor2")) != anchor_text(s.get("anchor2")):
            what.append("anchor %s -> %s" % (anchor_text(o["anchor"]), anchor_text(s["anchor"])))
        so = {e["id"]: e["value"] for e in o.get("settings", [])}
        sn = {e["id"]: e["value"] for e in s.get("settings", [])}
        for e in s.get("settings", []):
            if so.get(e["id"]) != e["value"]:
                what.append("%s %s -> %s" % (e["name"], so.get(e["id"]), e["value"]))
        for e in o.get("settings", []):
            if e["id"] not in sn:
                what.append("%s %s -> (none)" % (e["name"], e["value"]))
        if o["isInDefaultPosition"] != s["isInDefaultPosition"]:
            what.append("isInDefaultPosition %s -> %s" % (o["isInDefaultPosition"], s["isInDefaultPosition"]))
        a, b = ro.get(s["key"]), rn.get(s["key"])
        if what and a and b:
            what.append("rect L%.0f T%.0f R%.0f B%.0f -> L%.0f T%.0f R%.0f B%.0f" % (tuple(a) + tuple(b)))
        if what:
            out.append("%-40s %s" % (label(s), "; ".join(what)))
    for k in by:
        if k not in {s["key"] for s in new["systems"]}:
            out.append("%-40s gone" % label(by[k]))
    return out


def main():
    ap = argparse.ArgumentParser()
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--cache", help="the client's edit-mode-cache-account.txt (only read)")
    src.add_argument("--string", help="a file holding a share string")
    ap.add_argument("--name", help="the account layout's name (with --cache)")
    ap.add_argument("--write", action="store_true")
    a = ap.parse_args()
    lua = open(FILE, encoding="utf-8", newline="").read()
    m = LAYOUT_RX.search(lua)
    if not m:
        raise SystemExit("no `layout = [[...]]` in " + FILE)
    old_txt = m.group(3)
    old = C.decode(old_txt)
    if a.cache:
        if not a.name:
            raise SystemExit("--cache needs --name (the account layout to take)")
        lay, raw = from_cache(a.cache, a.name)
        systems = lay["systems"]
        new = {"format": "EditModeLayoutShareString", "version": old["version"], "systemCount": len(systems),
               "systems": systems}
        if "interfaceStyle" in lay or "interfaceStyle" in old:
            new["interfaceStyle"] = lay.get("interfaceStyle", old.get("interfaceStyle"))
        source_name = "edit-mode-cache-account.txt"
    else:
        raw = open(a.string, "rb").read().decode("latin-1")
        new = C.decode(raw.strip())
        new.pop("trailer", None)
        source_name = "share_string.txt"
    new_txt = C.encode(new)
    back = C.decode(new_txt)
    if C.encode(back) != new_txt:
        raise SystemExit("the string does not survive its own decode: refused")
    for w in C.validate(back):
        print("warning: " + w)
    diff = changes(old, back)
    print("%d systems (shipped: %d); %d differ from the shipped layout:" % (len(back["systems"]), len(old["systems"]), len(diff)))
    for line in diff:
        print("  " + line)
    if new_txt == old_txt:
        print("the same string as shipped: nothing to write")
        return
    if not a.write:
        print("a look only: --write takes it")
        return
    import bakeworld as B
    keep = B.build_data("installer", "editmode_" + time.strftime("%Y-%m-%d_%H%M%S"))
    os.makedirs(keep, exist_ok=True)
    if a.cache:
        shutil.copyfile(a.cache, os.path.join(keep, source_name))
        with open(os.path.join(keep, "layout_name.txt"), "w", encoding="utf-8") as fh:
            fh.write(a.name + "\n")
    else:
        shutil.copyfile(a.string, os.path.join(keep, source_name))
    with open(os.path.join(keep, "EditModeLayout.taken.txt"), "w", encoding="latin-1", newline="") as fh:
        fh.write(new_txt)
    out = lua[:m.start(3)] + new_txt + lua[m.end(3):]
    with open(FILE, "w", encoding="utf-8", newline="") as fh:
        fh.write(out)
    print("wrote " + FILE + "; the source kept in " + keep)
    print("next: python anchor_layout.py --write, then python golden.py")


if __name__ == "__main__":
    main()

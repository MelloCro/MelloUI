"""Shared bits of the fitter's tests: the lupa world, JSON <-> Lua, the goldens.

In Tools/installer the Full bake uses new_world, to_lua, from_lua,
source_info and approved_string. Only the approved layout's info
(../fitting/goldens/source.json) is kept here: golden(), inputs() and
results() read the fitting track's other golden files, which stay with that
track and are not part of the bake.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PREP = os.path.normpath(os.path.join(HERE, "..", "fitting"))
GOLD = os.path.join(PREP, "goldens")
# the addon folder (this file is Tools/installer/fit/common.py)
REPO = os.path.normpath(os.path.join(HERE, "..", "..", "..")).replace("\\", "/")
FILE = REPO + "/Core/LayoutFit.lua"
sys.path.insert(0, PREP)
sys.path.insert(0, os.path.join(PREP, "lib"))

import layoutcodec as C   # noqa: E402
import golden as G        # noqa: E402
import lupa.lua51 as L51  # noqa: E402

SCREENS = ["3440x1440", "2560x1080", "5120x1440", "3840x1080", "2560x1440", "1920x1080", "3840x2160", "1366x768",
           "1600x900", "1920x1200", "2560x1600", "1680x1050", "1280x1024", "1024x768", "2880x1800",
           "3440x1440@0.64", "3440x1440@0.70", "1024x768@0.80"]


def new_world():
    lua = L51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(open(os.path.join(HERE, "world.lua"), encoding="utf-8").read())
    fit = lua.globals().Load(FILE)
    return lua, fit


def to_lua(lua, v):
    if isinstance(v, dict):
        t = lua.table()
        for k, x in v.items():
            if x is None:
                continue
            t[k] = to_lua(lua, x)
        return t
    if isinstance(v, list):
        t = lua.table()
        for i, x in enumerate(v):
            t[i + 1] = to_lua(lua, x)
        return t
    return v


def from_lua(lua, v):
    """A Lua value in Python, every number exact (through the world's ToJSON)."""
    if lupa_type(lua, v) != "table":
        return v
    return json.loads(lua.globals().ToJSON(v))


_TYPE = {}


def lupa_type(lua, v):
    f = _TYPE.get(id(lua))
    if f is None:
        f = lua.eval("type")
        _TYPE[id(lua)] = f
    return f(v)


def golden(sid):
    return json.load(open(os.path.join(GOLD, sid.replace("@", "_at_") + ".json")))


def source_info():
    return json.load(open(os.path.join(GOLD, "source.json")))


def inputs():
    return json.load(open(os.path.join(GOLD, "inputs.json")))["inputs"]


def results():
    return json.load(open(os.path.join(PREP, "results.json"), encoding="utf-8"))


def approved_string():
    lua = open(REPO + "/Media/EditModeLayout.lua", encoding="latin-1").read()
    got = {m.group(1): m.group(3) for m in re.finditer(r"(\w+)\s*=\s*\[(=*)\[(.*?)\]\2\]", lua, re.S)}
    return got["layout"]


def game_info_from_lua(lua, fitted):
    """The Lua result in the golden's game shape (systemIndex None for a single system)."""
    d = from_lua(lua, fitted)
    out = {"layoutName": d.get("layoutName"), "layoutType": d.get("layoutType"), "systems": []}
    for s in d["systems"]:
        out["systems"].append({
            "system": int(s["system"]),
            "systemIndex": int(s["systemIndex"]) if s.get("systemIndex") is not None else None,
            "isInDefaultPosition": bool(s["isInDefaultPosition"]),
            "anchorInfo": s["anchorInfo"],
            "anchorInfo2": s.get("anchorInfo2"),
            "settings": [{"setting": int(e["setting"]), "value": int(e["value"]) if float(e["value"]).is_integer() else e["value"]} for e in s["settings"]],
        })
    return out


def share_string(info, src_decoded):
    return C.encode(G.from_game_info(info, src_decoded))

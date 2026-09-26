"""Golden data for the Lua port's test harness (lupa has no
C_EditMode.ConvertStringToLayoutInfo, so the harness never parses a share
string: it is fed the game's own info shape, written here).

    python golden.py      -> goldens/source.json, goldens/<screen>.json, goldens/inputs.json

The game's shape (what C_EditMode.ConvertStringToLayoutInfo returns and
SaveLayouts takes; Core/EditModeLayout.lua:120-161 works on it):
    { layoutName, layoutType, systems = { { system, systemIndex (nil for a
      single system), isInDefaultPosition, anchorInfo = { point, relativeTo,
      relativePoint, offsetX, offsetY }, anchorInfo2 (or nil), settings = {
      { setting = id, value = raw }, ... } }, ... } }
layoutcodec's JSON shape (lib/layoutcodec.py) has the same content under other
names: anchor / anchor2, settings entries { name, id, value, meaning }, a key
"system:index" with index -1 for a single system.

The comparison the harness runs (compare_infos): the same systems in the same
order, the same anchor points and frames, every offset within 0.05 (the port
works in floats, the share string rounds to %.1f, so a byte compare can flip
at a rounding tie), every setting value exactly equal. W and H come from the
screen list here at full precision (goldens/<screen>.json "W", "H"), never
from results.json's rounded uiParent.

In Tools/installer the Full bake reads goldens/source.json (the approved
layout in the game's shape) and uses from_game_info to prove it is still
Media/EditModeLayout.lua's `layout`. When the approved layout changes, run
this file again to write a new source.json (it also writes the per-screen
goldens and inputs.json, which the fitter's own tests use).
"""
import copy
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "lib"))
import layoutcodec as C   # noqa: E402
import hud                # noqa: E402
import fit as F           # noqa: E402

OUT = os.path.join(HERE, "goldens")
TOL = 0.05


def _anchor_to_game(a):
    if a is None:
        return None
    return {"point": a["point"], "relativeTo": a["relativeTo"], "relativePoint": a["relativePoint"],
            "offsetX": a["offsetX"], "offsetY": a["offsetY"]}


def _anchor_from_game(a):
    if a is None:
        return None
    return {"point": a["point"], "relativePoint": a["relativePoint"], "relativeTo": a["relativeTo"],
            "offsetX": a["offsetX"], "offsetY": a["offsetY"]}


def to_game_info(lay, name="MelloUI"):
    systems = []
    for s in lay["systems"]:
        systems.append({
            "system": s["system"],
            "systemIndex": None if s["systemIndex"] in (-1, None) else s["systemIndex"],
            "isInDefaultPosition": bool(s["isInDefaultPosition"]),
            "anchorInfo": _anchor_to_game(s["anchor"]),
            "anchorInfo2": _anchor_to_game(s.get("anchor2")),
            "settings": [{"setting": e["id"], "value": e["value"]} for e in s["settings"]],
        })
    return {"layoutName": name, "layoutType": "Account", "systems": systems}


def from_game_info(info, template):
    """Back into layoutcodec's shape (names and meanings from `template`, the
    decoded source), so the result can be encoded and compared."""
    lay = copy.deepcopy(template)
    for s, g in zip(lay["systems"], info["systems"]):
        assert s["system"] == g["system"] and (s["systemIndex"] if s["systemIndex"] != -1 else None) == g["systemIndex"], s["key"]
        s["isInDefaultPosition"] = g["isInDefaultPosition"]
        s["anchor"] = _anchor_from_game(g["anchorInfo"])
        if "anchor2" in s:
            s["anchor2"] = _anchor_from_game(g.get("anchorInfo2"))
        vals = {e["setting"]: e["value"] for e in g["settings"]}
        for e in s["settings"]:
            if vals[e["id"]] != e["value"]:
                hud.set_setting(s, e["name"], vals[e["id"]])
    return lay


def compare_infos(got, want, tol=TOL):
    """The harness's check: [] when the port's result matches the golden."""
    diff = []
    if len(got["systems"]) != len(want["systems"]):
        return ["%d systems, want %d" % (len(got["systems"]), len(want["systems"]))]
    for g, w in zip(got["systems"], want["systems"]):
        tag = "%s:%s" % (w["system"], w["systemIndex"])
        if (g["system"], g["systemIndex"]) != (w["system"], w["systemIndex"]):
            diff.append("%s: system order" % tag)
            continue
        if bool(g["isInDefaultPosition"]) != bool(w["isInDefaultPosition"]):
            diff.append("%s: isInDefaultPosition" % tag)
        for k in ("anchorInfo", "anchorInfo2"):
            ga, wa = g.get(k), w.get(k)
            if (ga is None) != (wa is None):
                diff.append("%s: %s present/absent" % (tag, k))
                continue
            if ga is None:
                continue
            for f in ("point", "relativeTo", "relativePoint"):
                if ga[f] != wa[f]:
                    diff.append("%s: %s.%s %s, want %s" % (tag, k, f, ga[f], wa[f]))
            for f in ("offsetX", "offsetY"):
                if abs(ga[f] - wa[f]) > tol:
                    diff.append("%s: %s.%s %.2f, want %.2f" % (tag, k, f, ga[f], wa[f]))
        gs = [(e["setting"], e["value"]) for e in g["settings"]]
        ws = [(e["setting"], e["value"]) for e in w["settings"]]
        if gs != ws:
            diff.append("%s: settings %s, want %s" % (tag, [x for x in gs if x not in ws], [x for x in ws if x not in gs]))
    return diff


def main():
    os.makedirs(OUT, exist_ok=True)
    src_txt = F.load_layouts()[0]
    src = C.decode(src_txt)
    mello = F.load_mello(F.SV_21)
    base = hud.check(src, F.DESIGN_W, F.DESIGN_H, F.approved_mello(mello))
    inh = frozenset(frozenset((a["name"], b["name"])) for kd, a, b, ox, oy in hud.conflicts(base["elements"]))
    src_info = to_game_info(src)
    # the converter round-trips the source exactly
    assert C.encode(from_game_info(src_info, src)) == src_txt
    json.dump(src_info, open(os.path.join(OUT, "source.json"), "w"), indent=1)
    inputs = copy.deepcopy(mello)
    json.dump({"note": "what the fitter reads besides the layout (fit.py load_mello); the port reads the same from "
                       "MelloUI's settings: QuestTracker pos/width/maxHeight/scale, QuestList width, Tweaks.hideBagBar, "
                       "Stats on, UI Modifications positions (the windows), and barsWithActions (decision 6); since the "
                       "refit (build round 4) the minimap column (MinimapPanel on, shape, squareBorder, servicesMerge; "
                       "Services on and showBar, buttonLayout, barOffset, roundIcons; QuestTracker matchMinimap) and your "
                       "buff rows (Auras on and player, playerColumn, playerSize, playerPerRow)",
               "inputs": inputs, "inherited": sorted(" x ".join(sorted(p)) for p in inh)},
              open(os.path.join(OUT, "inputs.json"), "w"), indent=1)
    n = 0
    for sid, w, h, sc, label in F.SCREENS:
        f = F.fit(src, mello, w, h, sc, label, inh)
        want = to_game_info(f.lay)
        # the golden itself survives the share string (what the game stores)
        back = from_game_info(want, src)
        s = C.encode(back)
        again = to_game_info(C.decode(s))
        d = compare_infos(again, want)
        assert not d, (sid, d[:3])
        json.dump({"id": sid, "screen": [w, h], "scale": f.scale, "W": f.W, "H": f.H, "label": label,
                   "expected": want, "places": F.places(f), "compare": "offsets within %.2f, settings exact" % TOL},
                  open(os.path.join(OUT, sid.replace("@", "_at_") + ".json"), "w"), indent=1)
        n += 1
    print("goldens: %d screens, converter round trip ok" % n)


if __name__ == "__main__":
    main()

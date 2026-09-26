"""Screen fitting prototype: the approved 21:9 layout ('MelloUI 21:9 Immersive',
Media/EditModeLayout.lua `layout`) fitted to any screen, with the UI scale left
alone. Scratch only -- the reference for the installer's Lua port.

    python fit.py            all screens -> out/<id>/, results.json, contact_sheet.png

The algorithm in words is fitting_spec.md; the rule numbers there (F0, F0b,
F1..F12, F9g) are the functions below. hud.py is the model of sizes, the
'show together' table and the checks. golden.py writes the port's golden
data; settings_table.py the setting ids and conversions it touches.

In Tools/installer this file is here because golden.py imports it (the Full
bake uses golden.py's converter only): it is the reference Core/LayoutFit.lua
was ported from. Its main() needs the fitting track's sketch.py and
compare16.py, which are not part of the bake.
"""
import copy
import json
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "lib"))
import layoutcodec as C  # noqa: E402
import hud               # noqa: E402
from hud import GAP, EPS  # noqa: E402

# the addon folder (this file is Tools/installer/fitting/fit.py) and the
# build data beside it (MELLOUI_BUILD_DATA when set, as Tools/paths.py has it)
REPO = os.path.normpath(os.path.join(HERE, "..", "..", "..")).replace("\\", "/")
BD = (os.environ.get("MELLOUI_BUILD_DATA", "").strip()
      or os.path.join(os.path.dirname(REPO), "MelloUI-BuildData")).replace("\\", "/") + "/installer"
SV_21 = BD + "/2026-09-24_21x9_3440x1440/MelloUI.SavedVariables.lua"
SV_16 = BD + "/2026-09-24_16x9_2560x1440/MelloUI.SavedVariables.lua"
FINAL_TXT = BD + "/2026-09-26_21x9_immersive/EditModeLayout.final.txt"
# (main()'s output: into the build data, never into the addon)
OUT = BD + "/fitting_out"

# ============================================================ F0 the screen in UI units
# Observed on this client (1.60.1.70009) with 'Use UI Scale' OFF: the game picks
# its own scale, 768 / screen height, but never below 0.64 (at 3440x1440 the
# slider says 100 % while the UI draws at 0.64: the user's screenshot measures
# UIParent 2866.67 x 1200). UIParent is then 768/scale units tall and as wide as
# the screen's shape: 1 unit = 1 pixel up to 1200 pixels tall, above that the
# units grow. This is the scale BUG's behaviour and changes when Blizzard fixes it.
MIN_SCALE = 0.64
DESIGN_SCREEN = (3440, 1440)


def ui_parent(w, h, scale=None):
    s = scale if scale is not None else max(MIN_SCALE, 768.0 / h)
    H = 768.0 / s
    return H * w / h, H, s


DESIGN_W, DESIGN_H, _ = ui_parent(*DESIGN_SCREEN)      # 2866.67 x 1200
DESIGN_ASPECT = DESIGN_W / DESIGN_H                      # 2.3889 (21:9)

SCREENS = [
    ("3440x1440", 3440, 1440, None, "21:9 (the design screen: must come back unchanged)"),
    ("2560x1080", 2560, 1080, None, "21:9 at 1080p"),
    ("5120x1440", 5120, 1440, None, "32:9"),
    ("3840x1080", 3840, 1080, None, "32:9 at 1080p"),
    ("2560x1440", 2560, 1440, None, "16:9 1440p"),
    ("1920x1080", 1920, 1080, None, "16:9 1080p"),
    ("3840x2160", 3840, 2160, None, "16:9 4K"),
    ("1366x768", 1366, 768, None, "16:9 laptop"),
    ("1600x900", 1600, 900, None, "16:9 900p"),
    ("1920x1200", 1920, 1200, None, "16:10"),
    ("2560x1600", 2560, 1600, None, "16:10 1600p"),
    ("1680x1050", 1680, 1050, None, "16:10 1050p"),
    ("1280x1024", 1280, 1024, None, "5:4"),
    ("1024x768", 1024, 768, None, "4:3"),
    ("2880x1800", 2880, 1800, None, "16:10 (MacBook-class)"),
    ("3440x1440@0.64", 3440, 1440, 0.64, "21:9 with the scale given explicitly (0.64): the scale-override path"),
    ("3440x1440@0.70", 3440, 1440, 0.70, "21:9 at the Config.wtf uiScale 0.70 -- what the slider would give once Blizzard fixes the bug (preview only)"),
    ("1024x768@0.80", 1024, 768, 0.80, "4:3 at a UI scale of 0.80 -- only once Blizzard fixes the bug (preview only)"),
]

# ============================================================ inputs

def load_layouts():
    lua = open(REPO + "/Media/EditModeLayout.lua", encoding="latin-1").read()
    got = {m.group(1): m.group(3) for m in re.finditer(r"(\w+)\s*=\s*\[(=*)\[(.*?)\]\2\]", lua, re.S)}
    return got["layout"], got["layout16x9"]


def load_mello(path):
    from lupa import LuaRuntime
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(open(path, encoding="utf-8", errors="replace").read())
    db = lua.globals().MelloUIDB

    def py(t):
        if lua.eval("type")(t) != "table":
            return t
        return {k: py(v) for k, v in t.items()}
    mods = py(db.modules)
    qt = mods.get("QuestTracker", {})
    pos = {k: dict(v) for k, v in mods["UIModifications"]["positions"].items()}
    # the places wave 3 moved into the one store, as the modules' own moves
    # write them (Tools/installer/bake_full.py expected_moves): the whisper
    # popups' corner and the voice overlay's anchor
    wp = mods.get("Chat", {}).get("whisperPopupPos")
    if isinstance(wp, dict) and isinstance(wp.get("x"), (int, float)) and isinstance(wp.get("y"), (int, float)) and "whisper" not in pos:
        pos["whisper"] = {"relPoint": "BOTTOMLEFT", "x": wp["x"], "y": wp["y"]}
    vo = mods.get("VoiceOver", {})
    if isinstance(vo.get("overlayPoint"), str) and "voiceOverlay" not in pos:
        pt = vo["overlayPoint"].strip().upper()
        rp = (vo.get("overlayRelativePoint") or pt).strip().upper()
        e = {"x": vo.get("overlayX") or 0, "y": vo.get("overlayY") or 0}
        if pt != "BOTTOMLEFT":
            e["point"] = pt
        if rp != "CENTER":
            e["relPoint"] = rp
        pos["voiceOverlay"] = e
    en = py(db.enabled)
    mm, sv, au = mods.get("MinimapPanel", {}), mods.get("Services", {}), mods.get("Auras", {})
    return {
        "positions": pos,
        "tracker": {"pos": {"x": round(qt["pos"]["x"], 1), "y": round(qt["pos"]["y"], 1)}, "width": qt.get("width", 300),
                    "maxHeight": qt.get("maxHeight", 440), "scale": qt.get("scale", 1)},
        "questlist": {"width": mods.get("QuestList", {}).get("width", 380)},
        "hideBagBar": bool(mods.get("Tweaks", {}).get("hideBagBar")),
        "statsOn": bool(py(db.enabled).get("Stats")),
        # the minimap column (layout E) and your buff rows by it: the modules'
        # defaults where the snapshot has no value (Modules/*.lua defaults)
        "column": {"kit": en.get("MinimapPanel", True) is not False, "shape": mm.get("shape", "round"),
                   "border": mm.get("squareBorder", "window"), "merge": mm.get("servicesMerge", True) is not False,
                   "bar": en.get("Services", True) is not False and sv.get("showBar", True) is not False,
                   "groups": sv.get("buttonLayout", "groups") != "all", "barOffset": sv.get("barOffset", -26),
                   "roundIcons": sv.get("roundIcons", True) is not False,
                   "match": bool(en.get("QuestTracker")) and qt.get("matchMinimap", True) is not False},
        "auras": {"rows": bool(en.get("Auras")) and au.get("player", True) is not False,
                  "attached": au.get("playerColumn", True) is not False, "size": au.get("playerSize", 30),
                  "perRow": au.get("playerPerRow", 12)},
    }


# ============================================================ the working state

class Fit:
    def __init__(self, src, mello, W, H, label, inherited=frozenset()):
        self.inherited = inherited
        self.src = src
        self.lay = copy.deepcopy(src)
        self.mello = copy.deepcopy(mello)
        self.W, self.H = W, H
        self.label = label
        self.recs = {s["key"]: s for s in self.lay["systems"]}
        self.log = []      # what the fitter changed, in order
        self.eye = []      # changes the user should look at
        self.flags = []    # what the fitter could not solve (the verdict fails)
        self.notes = []    # pieces that show now and then and still meet something
        self.inset = 0.0
        self.frames_d = 0.0
        self.chat_lifted = False

    # ---------------------------------------------------------- edits
    def anchor(self, key):
        return self.recs[key]["anchor"]

    def move(self, key, rule, why, point=None, rel_point=None, rel=None, x=None, y=None):
        rec = self.recs[key]
        a = rec["anchor"]
        before = (a["point"], a["relativePoint"], a["relativeTo"], a["offsetX"], a["offsetY"])
        if point:
            a["point"] = point
        if rel_point:
            a["relativePoint"] = rel_point
        if rel:
            a["relativeTo"] = rel
        if x is not None:
            a["offsetX"] = round(float(x), 1) + 0.0
        if y is not None:
            a["offsetY"] = round(float(y), 1) + 0.0
        after = (a["point"], a["relativePoint"], a["relativeTo"], a["offsetX"], a["offsetY"])
        if after != before:
            rec["isInDefaultPosition"] = False
            self.log.append({"rule": rule, "key": key, "what": "%s %s->%s %s (%.1f, %.1f) [was %s->%s %s (%.1f, %.1f)]" % (
                (rec["systemName"] + ("." + rec["systemIndexName"] if rec["systemIndexName"] else "")),
                after[0], after[1], after[2], after[3], after[4], before[0], before[1], before[2], before[3], before[4]), "why": why})

    def shift(self, key, rule, why, dx=0.0, dy=0.0):
        a = self.anchor(key)
        self.move(key, rule, why, x=a["offsetX"] + dx, y=a["offsetY"] + dy)

    def set(self, key, name, raw, rule, why):
        rec = self.recs[key]
        old = hud.setting(rec, name)
        if old == raw:
            return
        hud.set_setting(rec, name, raw)
        self.log.append({"rule": rule, "key": key, "what": "%s %s %s -> %s" % (rec["systemName"], name, old, raw), "why": why})

    # ---------------------------------------------------------- views
    def els(self):
        return hud.elements(self.lay, self.W, self.H, self.mello)[0]

    def rects(self):
        return hud.solve(self.lay, self.W, self.H)[0]

    def by_name(self, E=None):
        return {e["name"]: e for e in (E or self.els())}

    def tracker(self):
        r = self.rects()
        return hud.tracker_rect(self.mello, self.W, self.H, r, hud.column(self.lay, r, self.mello))

    def column(self):
        return hud.column(self.lay, self.rects(), self.mello)

    def unit_conflicts(self, unit, E=None):
        """Conflicts of one unit's pieces, leaving out pairs the approved layout
        already has at its own screen (the fitter keeps the design, it does not
        redesign it)."""
        E = E or self.els()
        mine = [e for e in E if e["unit"] == unit]
        return [c for c in hud.conflicts(E, extra=mine)
                if c[0] != "info" and frozenset((c[1]["name"], c[2]["name"])) not in self.inherited]


def yov(a, b, g=0.0):
    return min(a[3], b[3]) - max(a[1], b[1]) > -g + EPS


def xov(a, b, g=0.0):
    return min(a[2], b[2]) - max(a[0], b[0]) > -g + EPS


def ui_edge(rel_point):
    return {0: "L", 0.5: "C", 1: "R"}[hud.AX[rel_point][0]]


# ============================================================ F1 the 21:9 zone (32:9)

def f1_zone(f):
    """F1. Wider than 21:9: the HUD keeps the 21:9 width, centred; every piece held
    to the left / right edge is held to the zone's edge instead (plan: '32:9
    centre zone'). Centre-anchored pieces do not move."""
    zone = min(f.W, DESIGN_ASPECT * f.H)
    inset = (f.W - zone) / 2.0
    f.inset = inset if inset >= 0.05 else 0.0
    if not f.inset:
        return
    for s in f.lay["systems"]:
        a = s["anchor"]
        if a["relativeTo"] != "UIParent" or s["isInDefaultPosition"]:
            continue
        e = ui_edge(a["relativePoint"])
        if e == "L":
            f.shift(s["key"], "F1 zone", "held to the 21:9 zone's left edge, %.1f in from the screen's" % inset, dx=inset)
        elif e == "R":
            f.shift(s["key"], "F1 zone", "held to the 21:9 zone's right edge, %.1f in from the screen's" % inset, dx=-inset)
    f.eye.append("32:9 zone: the HUD sits in a centred 21:9 zone, %.0f units in from each side (the outer %.0f%% of the screen stays world)"
                 % (inset, 100 * 2 * inset / f.W))


def third(f):
    """The centre third (of the 21:9 zone on a wider screen)."""
    zone = f.W - 2 * f.inset
    return f.inset + zone / 3.0, f.inset + 2 * zone / 3.0


# ============================================================ F0b bars that hold actions (decision 6)

# the Immersive hides Action Bars 3, 4, 6, 7 and 8 (VisibleSetting 3 = Hidden);
# their action slots (Blizzard_ActionBar/Shared/MultiActionBars.lua:1-8: page
# p holds slots (p - 1) x 12 + 1 .. p x 12)
BAR_SLOTS = {
    "0:2": (49, 60, "Action Bar 3 (MultiBarBottomRight, page 5)"),
    "0:3": (25, 36, "Action Bar 4 (MultiBarRight, page 3)"),
    "0:5": (145, 156, "Action Bar 6 (MultiBar5, page 13)"),
    "0:6": (157, 168, "Action Bar 7 (MultiBar6, page 14)"),
    "0:7": (169, 180, "Action Bar 8 (MultiBar7, page 15)"),
}
PANEL_BARS = ("0:1", "0:2", "0:3")        # chained on Bar 1 inside the painted panel
WHATIF_BARS = ("3440x1440", "2560x1440", "1920x1080", "1600x900", "1366x768")


def f0b_bars(f):
    """F0b (only when the user takes decision 6's second choice). A hidden bar
    that holds actions (the port reads HasAction for its 12 slots) is shown
    (VisibleSetting 0 = Always). Bars 3 and 4 add rows on top of the panel:
    every BOTTOM-anchored piece above the panel and over its bars (stance, pet,
    totem tabs, cast bar, swing timers, taxi exit; possess follows the stance)
    is lifted by the rows' height. Bars 6-8 add rows on the tray: the tracker
    (F5), the doll and the tooltip corner (F8) make room by their own rules.
    Then the band is solved as usual."""
    want = [k for k in f.mello.get("barsWithActions", []) if k in f.recs and not hud.visible(f.recs[k])]
    if not want:
        return
    r0 = f.rects()
    b1 = r0["0:0"]
    old_top = min(r0[k][1] for k in ("0:0",) + PANEL_BARS if k in r0 and hud.visible(f.recs[k]))
    for k in want:
        f.set(k, "VisibleSetting", 0, "F0b bars", "%s holds actions: shown" % BAR_SLOTS[k][2])
        if k in ("0:5", "0:6", "0:7"):
            # on the tray: its width (6 a row), so all 12 buttons show in 2 rows
            f.set(k, "NumRows", 2, "F0b bars", "%s in 2 rows of 6, the tray's width" % BAR_SLOTS[k][2])
    r1 = f.rects()
    new_top = min(r1[k][1] for k in ("0:0",) + PANEL_BARS if k in r1 and hud.visible(f.recs[k]))
    lift = round(old_top - new_top, 1)
    if lift > EPS:
        for rec in f.lay["systems"]:
            a = rec["anchor"]
            if a["relativeTo"] != "UIParent" or a["relativePoint"] != "BOTTOM" or rec["isInDefaultPosition"]:
                continue
            rc = r0.get(rec["key"])
            if rc and rec["key"] not in ("0:0",) + PANEL_BARS and rc[3] <= old_top + EPS and rc[0] < b1[2] and rc[2] > b1[0]:
                f.shift(rec["key"], "F0b bars", "lifted %.1f above the panel's new bar rows" % lift, dy=lift)
        # the taller panel now reaches the unit frames beside it: the pair
        # steps out, GAP clear of the panel's backdrop (focus and extra ability
        # keep their gaps to them)
        N = f.by_name()
        back, pl = N["Bar panel backdrop"]["rect"], N["Player frame"]["rect"]
        if yov(back, pl) and pl[2] > back[0] - GAP:
            d = math.ceil((pl[2] - (back[0] - GAP)) * 10) / 10.0
            for key, sign in (("3:0", -1), ("3:2", -1), ("3:1", 1), ("5:-1", 1)):
                f.shift(key, "F0b bars", "the unit frames step %.1f out, clear of the taller panel" % d, dx=sign * d)
    f.eye.append("shown because they hold actions: %s%s" % (", ".join(BAR_SLOTS[k][2] for k in want),
                 " (the panel grows %.0f taller)" % lift if lift > EPS else ""))


# ============================================================ F11 compact sizes

COMPACT = [
    ("unit frames 100%", [("3:0", "FrameSize", 0), ("3:1", "FrameSize", 0)]),
    ("micro menu 70% and bag bar 75%", [("13:-1", "Size", 0), ("14:-1", "Size", 0)]),
    ("action bars 90%", [("0:0", "IconSize", 4), ("0:1", "IconSize", 4), ("0:2", "IconSize", 4), ("0:3", "IconSize", 4)]),
    ("action bars 80%", [("0:0", "IconSize", 3), ("0:1", "IconSize", 3), ("0:2", "IconSize", 3), ("0:3", "IconSize", 3)]),
    ("action bars 70%", [("0:0", "IconSize", 2), ("0:1", "IconSize", 2), ("0:2", "IconSize", 2), ("0:3", "IconSize", 2)]),
]


def apply_compact(f, level):
    """F11. Smaller Edit Mode sizes, cumulative up to `level`, tried only when the
    bottom band cannot be solved at the approved sizes. The painted panel keeps
    its shape: the end caps stay 92.2 outside the bars, the frames' inner edge
    stays 3 outside the bars, focus / extra ability keep their gaps to them."""
    if level == 0:
        return
    r0 = f.rects()
    b = r0["0:0"]
    half0 = (b[2] - b[0]) / 2.0
    pl, tg = r0["3:0"], r0["3:1"]
    inner_gap = b[0] - pl[2]                       # 3 at the design
    cap_out = f.anchor("26:1")["offsetX"] - half0  # 92.2 at the design
    focus_gap = pl[0] - r0["3:2"][2]
    extra_gap = r0["5:-1"][0] - tg[2]
    for i in range(level):
        name, changes = COMPACT[i]
        for key, sname, raw in changes:
            f.set(key, sname, raw, "F11 compact", "compact step %d: %s" % (i + 1, name))
    f.eye.append("compact sizes: " + ", ".join(COMPACT[i][0] for i in range(level)))
    r1 = f.rects()
    b = r1["0:0"]
    half = (b[2] - b[0]) / 2.0
    f.move("26:0", "F11 compact", "end cap stays %.1f outside the bars" % cap_out, x=-(half + cap_out))
    f.move("26:1", "F11 compact", "end cap stays %.1f outside the bars" % cap_out, x=half + cap_out)
    # the totem tab (a fixed 230 wide, BOTTOMRIGHT on the centre -50) stays
    # inside the narrower bars' left edge, as it is at the design
    tt = f.rects().get("25:-1")
    if tt and tt[0] < b[0] - EPS:
        f.shift("25:-1", "F11 compact", "totem tab stays inside the bars' left edge", dx=math.ceil((b[0] - tt[0]) * 10) / 10.0)
    r1 = f.rects()
    pw = r1["3:0"][2] - r1["3:0"][0]
    off = half + inner_gap + pw / 2.0
    f.move("3:0", "F11 compact", "inner edge %.0f outside the bars, as designed" % inner_gap, x=-off)
    f.move("3:1", "F11 compact", "mirror of the player frame", x=off)
    fw = r1["3:2"][2] - r1["3:2"][0]
    f.move("3:2", "F11 compact", "keeps its %.0f gap to the player frame" % focus_gap, x=-(off + pw / 2 + focus_gap + fw / 2))
    ew = r1["5:-1"][2] - r1["5:-1"][0]
    f.move("5:-1", "F11 compact", "keeps its %.0f gap to the target frame" % extra_gap, x=off + pw / 2 + extra_gap + ew / 2)


# ============================================================ the bottom band (F2..F5)

def persistent(E, *units):
    return [e for e in E if e["cat"] in hud.PERSISTENT and (not units or e["unit"] in units)]


def centre_group(f):
    """Every record held to the screen's bottom centre (they slide together)."""
    return [s["key"] for s in f.lay["systems"] if s["anchor"]["relativeTo"] == "UIParent"
            and s["anchor"]["relativePoint"] == "BOTTOM" and not s["isInDefaultPosition"]]


def frames_dmax(f, E):
    """How far the player / target frames can come in: until the nearest persistent
    centre piece beside them (cast bar, swing timer) is GAP away, and the pet frame
    that hangs under the player frame (hunters, warlocks) touches the bar panel."""
    N = f.by_name(E)
    pl, tg = N["Player frame"]["rect"], N["Target frame"]["rect"]
    pet = N["Pet frame"]["rect"]
    dl = dr = 1e9
    for e in E:
        if e["unit"] != "core" or e["cat"] not in hud.PERSISTENT | {"P"}:
            continue
        g = GAP if e["cat"] in hud.PERSISTENT else 0.0       # class-only tabs may touch
        r = e["rect"]
        if yov(r, pl) and r[0] >= pl[2] - EPS:
            dl = min(dl, r[0] - pl[2] - g)
        if yov(r, tg) and r[2] <= tg[0] + EPS:
            dr = min(dr, tg[0] - r[2] - g)
        if yov(r, pet) and r[0] >= pet[2] - EPS:
            dl = min(dl, r[0] - pet[2])
    return max(0.0, min(dl, dr))


def bottom_obstacles(f, E, dmax):
    """Persistent bottom-centre pieces, the frames at their tightest."""
    out = []
    for e in persistent(E, "core", "frames"):
        r = e["rect"]
        if e["unit"] == "frames":
            s = 1 if (r[0] + r[2]) / 2 < f.W / 2 else -1
            r = (r[0] + s * dmax, r[1], r[2] + s * dmax, r[3])
        out.append(r)
    return out


CHAT_MIN_W = 300      # beside the bars: never narrower than the damage meter
CHAT_GAME_MIN_W = 250  # lifted, out of the centre third: the game's own minimum
CHAT_MIN_H = 120      # the game's own minimum


def chat_size(f):
    rec = f.recs["8:-1"]
    return (hud.setting(rec, "WidthHundreds") * 100 + hud.setting(rec, "WidthTensAndOnes"),
            hud.setting(rec, "HeightHundreds") * 100 + hud.setting(rec, "HeightTensAndOnes"))


def set_chat(f, w=None, h=None, why=""):
    if w is not None:
        f.set("8:-1", "WidthHundreds", w // 100, "F2 chat", why)
        f.set("8:-1", "WidthTensAndOnes", w % 100, "F2 chat", "%s (%d wide)" % (why, w))
    if h is not None:
        f.set("8:-1", "HeightHundreds", h // 100, "F2 chat", why)
        f.set("8:-1", "HeightTensAndOnes", h % 100, "F2 chat", "%s (%d tall)" % (why, h))


def f2_chat(f):
    """F2. The chat keeps its place when it clears the bottom centre; else it gets
    narrower, down to 300; else it is lifted above the bottom centre, narrowed to
    stay out of the centre third (not below the game's 250) and shortened to fit
    under the damage meter (not below 120)."""
    E = f.els()
    N = f.by_name(E)
    block = hud.union([N["Chat panel"]["rect"], N["Chat tabs"]["rect"]])
    cf = f.rects()["8:-1"]
    kit_r, kit_b, tabs = block[2] - cf[2], block[3] - cf[3], cf[1] - block[1]     # 40, 29, 28
    cur_w, cur_h = chat_size(f)

    def width_beside(dmax):
        hit = [o for o in bottom_obstacles(f, E, dmax) if yov(o, block, GAP) and o[0] < block[2] + GAP]
        if not hit:
            return None
        return int(math.floor(min(o[0] for o in hit) - GAP - kit_r - cf[0]))

    need_w = width_beside(0.0)
    if need_w is None:
        return
    dmax = frames_dmax(f, E)
    if need_w < CHAT_MIN_W and dmax > EPS:
        need_w = width_beside(dmax)          # F3 then brings the frames in by what the chat needs
    obst = bottom_obstacles(f, E, dmax)
    if need_w >= CHAT_MIN_W:
        w = min(cur_w, need_w)
        set_chat(f, w=w, why="narrower to clear the bar panel and frames")
        f.eye.append("chat %d wide (from %d) to sit beside the bar panel" % (w, cur_w))
        return
    # the bottom centre slides right (towards the bottom-right corner) to make
    # the missing room, when the right side has it
    lack = CHAT_MIN_W - need_w
    room = right_room(f, E, dmax)
    if lack <= min(room, 0.12 * f.W) + EPS:
        slide = math.ceil(lack * 10) / 10.0
        for k in centre_group(f):
            f.shift(k, "F2 chat", "the bottom centre slides %.1f right so the chat keeps its corner at %d wide" % (slide, CHAT_MIN_W), dx=slide)
        set_chat(f, w=CHAT_MIN_W, why="narrower to clear the bar panel and frames")
        f.eye.append("chat %d wide (from %d) in its corner; bar panel and frames %.0f units right of the centre (%.1f%% of the width)"
                     % (CHAT_MIN_W, cur_w, slide, 100 * slide / f.W))
        f.slid_right = slide
        return
    under = [o for o in obst if xov(o, block, GAP)]
    top = min(o[1] for o in under)
    y_off = f.H - (top - GAP - kit_b)
    x0, _ = third(f)
    w = int(min(cur_w, math.floor(x0 - GAP - kit_r - cf[0])))
    if w < CHAT_GAME_MIN_W:
        f.flags.append("chat: only %d units left of the centre third (the game's minimum width is %d)" % (w, CHAT_GAME_MIN_W))
        w = CHAT_GAME_MIN_W
    meter = N["Damage meter"]["rect"]
    room = int(math.floor((f.H - y_off) - tabs - (meter[3] + GAP)))
    h = min(cur_h, room)
    if h < CHAT_MIN_H:
        f.flags.append("chat: only %d units of height between the damage meter and the bottom centre (the game's minimum is %d)" % (h, CHAT_MIN_H))
        h = CHAT_MIN_H
    f.move("8:-1", "F2 chat", "lifted above the bottom centre: the screen is too narrow for the chat beside the bar panel", y=y_off)
    set_chat(f, w=w if w != cur_w else None, h=h if h != cur_h else None, why="lifted chat: out of the centre third, under the damage meter")
    f.eye.append("chat lifted off the bottom edge (its bottom %.0f units up), %d x %d (from %d x %d)" % (y_off, w, h, cur_w, cur_h))
    f.chat_lifted = True


def right_room(f, E, dmax=0.0):
    """How far the bottom centre can slide right: GAP before the persistent
    pieces on its right (bottom-right corner, tracker, auras, minimap) that share
    its height, and before the screen's edge."""
    centre = persistent(E, "core", "frames")
    right = persistent(E, "br", "tracker", "auras", "minimap")
    room = f.W - GAP - max(c["rect"][2] for c in centre)
    for c in centre:
        for b in right:
            if yov(c["rect"], b["rect"], GAP) and b["rect"][0] >= c["rect"][2] - EPS:
                room = min(room, b["rect"][0] - GAP - c["rect"][2])
    return max(0.0, room)


def f3_frames(f):
    """F3. The player / target frames come in as a mirrored pair, just enough to
    clear the chat and the bottom-right corner, never past frames_dmax; focus
    and extra ability move with them."""
    E = f.els()
    dmax = frames_dmax(f, E)
    N = f.by_name(E)
    pl, tg = N["Player frame"]["rect"], N["Target frame"]["rect"]
    need = 0.0
    for e in persistent(E):
        r = e["rect"]
        if e["unit"] == "chat" and yov(r, pl, GAP):
            need = max(need, r[2] + GAP - pl[0])
        if e["unit"] == "br" and yov(r, tg, GAP):
            need = max(need, tg[2] + GAP - r[0])
    f.frames_d = 0.0
    if need <= EPS:
        return
    d = math.ceil(min(need, dmax) * 10) / 10.0
    if d <= EPS:
        return
    why = "frames %.1f closer to the centre (their room: %.1f, up to the bar panel's pieces beside them)" % (d, dmax)
    for key, sign in (("3:0", 1), ("3:2", 1), ("3:1", -1), ("5:-1", -1)):
        f.shift(key, "F3 frames", why, dx=sign * d)
    f.frames_d = d


def f4_slide(f):
    """F4. The bottom centre still runs into the right side (bottom-right corner,
    quest tracker): the whole bottom centre slides left, at most 12 % of the
    width and never into the chat or off the screen. False when it cannot."""
    E = f.els()
    centre = persistent(E, "core", "frames")
    right = persistent(E, "br", "tracker", "auras", "minimap")
    left = persistent(E, "chat", "meter")
    delta = 0.0
    for c in centre:
        for b in right:
            if yov(c["rect"], b["rect"], GAP) and c["rect"][2] + GAP > b["rect"][0]:
                delta = max(delta, c["rect"][2] + GAP - b["rect"][0])
    if delta <= EPS:
        return True
    room = min(c["rect"][0] for c in centre) - GAP
    for c in centre:
        for l in left:
            if yov(c["rect"], l["rect"]):
                room = min(room, c["rect"][0] - l["rect"][2] - GAP)
    delta = math.ceil(delta * 10) / 10.0
    if delta > 0.12 * f.W or delta > room + EPS:
        f.band_note = "the bottom centre needs %.0f to the left (room %.0f, limit %.0f)" % (delta, room, 0.12 * f.W)
        return False
    for k in centre_group(f):
        f.shift(k, "F4 slide", "the bottom centre slides %.1f left, clear of the right side" % delta, dx=-delta)
    f.eye.append("bar panel and frames %.0f units left of the screen's centre (%.1f%% of the width)" % (delta, 100 * delta / f.W))
    return True


TRACKER_MIN = 200          # never shorter
TRACKER_KEEP = 300         # shortened for the bottom centre only down to this; below it the centre slides


# The minimap's Edit Mode Size for layout E (the flip, user 2026-09-25 "yes,
# flip it"): the map about as wide as the Quest Tracker's design width, 300:
# 198 x 150 % = 297 (160 % would be 317). Smaller steps, down to the approved
# layout's own size, only while the tracker has no room under the column.
SIZE_DESIGN = 10           # Minimap Size raw: 50 + 10 x raw = 150 %
TRACKER_DESIGN_W = 300


def f5m_column(f):
    """F5m. The minimap column of layout E: the minimap at the Size that makes
    the map about as wide as the Quest Tracker's design width, a step smaller
    (down to the approved layout's size) while the tracker would get less
    than TRACKER_KEEP under the column (the corner's pieces under it and the
    screen's bottom, as F5); the game's tracker (12:-1, which MelloUI's hangs
    on) right under the column, its right edge on the column's frame's, so the
    tracker, as wide as that frame, lines up with it."""
    rec = f.recs["2:-1"]
    start = hud.setting(rec, "Size")
    E = f.els()
    br = persistent(E, "br")
    t = f.mello["tracker"]
    need = min(TRACKER_KEEP, t["maxHeight"])
    # your buff rows by the column: the room beside it for 6 a row (fewer
    # when yours are fewer) of icons at 80 % -- what F6 sets, or tells the
    # player to set (F6 tries smaller ones only where the minimap is at its
    # least); where no step leaves room for both, the least, with an eye line
    # that says which is short
    rows = hud.aura_rows(f.column(), f.mello, f.W) is not None
    a = hud.auras_input(f.mello)
    narrow = (min(a["size"], row_icon(a["size"], 80)) + 6) * min(a["perRow"], ROWS_LEAST)
    x0, x1 = third(f)
    chosen = None
    tracker_ok = rows_ok = True
    for raw in range(SIZE_DESIGN, start - 1, -1):
        hud.set_setting(rec, "Size", raw)                        # trial, logged once below
        col = f.column()
        ref = col["ref"]
        tw = hud.tracker_match_w(col, t.get("scale", 1) or 1) if col["match"] else t["width"] * (t.get("scale", 1) or 1)
        tt = round(col["bottom"] + GAP, 1)
        trr = (ref[2] - tw, tt, ref[2], tt)
        floor_y = f.H - GAP
        for e in br:
            if xov(e["rect"], trr) and e["rect"][1] > tt:
                floor_y = min(floor_y, e["rect"][1] - GAP)
        tracker_ok = math.floor((floor_y - tt) / 20.0) * 20 >= need
        rows_ok = not rows or hud.rows_room(col, f.W, x0, x1) >= narrow
        if tracker_ok and rows_ok:
            chosen = raw
            break
    # no step with room for both: the least, the most room for both, and the
    # eye line says which has less than it wants there
    short = None
    if chosen is None:
        chosen = start
        short = ("the quest tracker and your buff rows get" if not tracker_ok and not rows_ok
                 else "the quest tracker gets" if not tracker_ok else "your buff rows get")
    hud.set_setting(rec, "Size", start)
    pct, pct0 = 50 + 10 * chosen, 50 + 10 * SIZE_DESIGN
    if chosen == SIZE_DESIGN:
        why = "layout E: the map about as wide as the Quest Tracker (%d of its %d units)" % (round(198 * pct / 100.0), TRACKER_DESIGN_W)
    elif short:
        why = "the smallest size (the approved layout's): even there %s less room than wanted" % short
    else:
        why = "the largest size that leaves the quest tracker %d units under the minimap%s" % (need, rows and ", and your buff rows room beside it" or "")
    f.set("2:-1", "Size", chosen, "F5m column", why)
    if short:
        f.eye.append("minimap at %d%% (from %d%%), its smallest: even so %s less room than wanted" % (pct, pct0, short))
    elif chosen != SIZE_DESIGN:
        f.eye.append("minimap at %d%% (from %d%%): room for the quest tracker under it%s" % (pct, pct0, rows and " and your buff rows beside it" or ""))
    col = f.column()
    f.move("12:-1", "F5m column", "the quest tracker right under the minimap column, its right edge on the column's frame's",
           point="TOPRIGHT", rel_point="TOPRIGHT", x=col["ref"][2] - f.W, y=-(col["bottom"] + GAP))


def f5_tracker(f, with_centre, keep=TRACKER_MIN):
    """F5. MelloUI's Quest Tracker keeps its top (under the minimap) and is as tall
    as the approved 440, but stops GAP above the persistent pieces under it (the
    bottom-right corner; after F4 also the bottom centre) and above the screen's
    bottom. Never below 200."""
    E = f.els()
    tr = f.tracker()
    floor_y = f.H - GAP
    units = ("br", "core", "frames") if with_centre else ("br",)
    for e in persistent(E, *units):
        if xov(e["rect"], tr) and e["rect"][1] > tr[1]:
            floor_y = min(floor_y, e["rect"][1] - GAP)
    cur = f.mello["tracker"]["maxHeight"]
    h = int(min(cur, math.floor((floor_y - tr[1]) / 20.0) * 20))      # the Height slider's step
    if with_centre and keep > TRACKER_MIN and h < keep:
        return                                                         # leave it to F4's slide
    if h < TRACKER_MIN:
        f.flags.append("quest tracker: only %d units under the minimap (the fitter's minimum is %d)" % (h, TRACKER_MIN))
        h = TRACKER_MIN
    if h != cur:
        f.mello["tracker"]["maxHeight"] = h
        f.log.append({"rule": "F5 tracker", "key": "QuestTracker.maxHeight", "what": "maxHeight %d -> %d" % (cur, h),
                      "why": "stops %d above the pieces under it" % GAP})
        f.set("12:-1", "Height", (max(400, min(1000, h)) - 400) // 10, "F5 tracker",
              "the game's own (hidden) tracker: its Height in the dialog's 400..1000")


def band_ok(f):
    """The bottom band and the right column solved at this compact level."""
    why = [x for x in f.flags if x.startswith(("chat:", "quest tracker:"))]
    E = f.els()
    main = {"core", "frames", "chat", "br", "tracker", "minimap", "meter"}
    for kd, a, b, ox, oy in hud.conflicts(E):
        if kd == "hard" and a["unit"] != b["unit"] and a["unit"] in main and b["unit"] in main \
                and frozenset((a["name"], b["name"])) not in f.inherited:
            why.append("%s x %s" % (a["name"], b["name"]))
    for e in persistent(E):
        l, t, r, b = e["rect"]
        if l < -EPS or t < -EPS or r > f.W + EPS or b > f.H + EPS:
            why.append("%s off the screen" % e["name"])
    top = hud.centre_top(E)
    x0, x1 = third(f)
    for e in persistent(E, "chat"):
        if e["rect"][1] < top and e["rect"][2] > x0 + EPS:
            why.append("chat in the centre third")
    f.band_why = why
    return not why


# ============================================================ F6 auras

AURA_SIZES = [(5, "100%"), (4, "90%"), (3, "80%")]     # AuraFrame IconSize raw (default conversion: 50 + 10 x raw)


def aura_hits(f, E):
    """What the aura blocks run into: the buffs (always on) into anything always
    on; the debuffs and external defensives into what shows with them in a
    fight (hud.kind 'hard'). The blocks of one column and the minimap they
    hang from do not count; neither do pieces placed later (F7-F9)."""
    N = f.by_name(E)
    hits = []
    for nm in ("Buffs", "Debuffs", "External defensives"):
        a = N[nm]
        for e in E:
            if e["unit"] in ("auras", "minimap") or e["cat"] not in hud.PERSISTENT or hud.pair_rule(a, e):
                continue
            if frozenset((a["name"], e["name"])) in f.inherited:
                continue
            ox, oy = hud.overlap(a["rect"], e["rect"])
            if ox > EPS and oy > EPS and hud.kind(a, e) == "hard":
                hits.append("%s x %s" % (nm, e["name"]))
        l, t, r, b = a["rect"]
        if l < -EPS or t < -EPS or r > f.W + EPS or b > f.H + EPS:
            hits.append("%s off the screen" % nm)
    return hits


ROWS_LEAST = 6            # Auras' Icons Per Row slider's least


def row_icon(size, pct):
    """pct % of an icon size, whole, not below Auras' Icon Size slider's least (20)."""
    return max(20, int(math.floor(size * pct / 100.0 + 0.5)))


def row_sizes(size):
    """The icon sizes F6 tries for your buff rows: yours, then 90, 80, 70 and
    60 % of it, then the slider's least (20), each only when smaller than
    yours. (F5m sizes the minimap for the 80 % icons: the smaller ones only
    where the minimap is at its smallest already.)"""
    out = [size]
    for pct in (90, 80, 70, 60, 0):
        s = row_icon(size, pct)
        if s not in out and s < size:
            out.append(s)
    return out


def approved_mello(mello):
    """MelloUI's settings as the approved layout was drawn with them (the
    2026-09-24 snapshot, before layout E's options): the Services bar's two
    rows, the Quest Tracker at its own width, your buff rows on the game's
    buff bar's place. What that layout overlaps at its own screen with them
    is 'inherited'."""
    m = copy.deepcopy(mello)
    m["column"] = dict(hud.column_input(m), groups=False, match=False)
    m["auras"] = dict(hud.auras_input(m), attached=False)
    return m


def f6_rows(f):
    """F6 for your buff rows by the minimap column (Auras, Attach To The
    Minimap Column): the game's buff and debuff bars are hidden then, so their
    Edit Mode settings are left as they are. The rows (all 32 buffs) stay out
    of the centre third and clear of the persistent pieces -- fewer icons a
    row (Auras' Icons Per Row, down to its least, 6), then smaller icons
    (row_sizes); when nothing clears everything, the first that clears the
    centre third is kept and the rest is reported. The caller writes them
    (places' Auras) only with auras.fitRows; without it nothing would, so the
    eye line asks the player to set them, never "wrap at" as if done. The
    game's external defensives hang on its hidden debuff bar: when the rows
    run over them, they step down under the rows."""
    a = f.mello.setdefault("auras", {})
    for key, v in hud.DESIGN_AURAS.items():
        a.setdefault(key, v)
    x0, x1 = third(f)
    size0, start = a["size"], a["perRow"]
    least = min(start, ROWS_LEAST)          # (yours below the slider's least, from an older profile: yours only)
    best_third = chosen = own_in = None
    for size in row_sizes(size0):
        for per in range(start, least - 1, -1):
            a["size"], a["perRow"] = size, per                    # trial, logged once below
            E = f.els()
            b = f.by_name(E)["Buffs"]["rect"]
            in_third = b[0] < x1 - EPS and b[2] > x0 + EPS
            if own_in is None:
                own_in = in_third                                 # (the first trial is your own rows)
            hits = [e["name"] for e in persistent(E) if e["unit"] not in ("auras", "minimap") and
                    hud.overlap(b, e["rect"])[0] > EPS and hud.overlap(b, e["rect"])[1] > EPS]
            if not in_third and best_third is None:
                best_third = (size, per)
            if not in_third and not hits:
                chosen = (size, per)
                break
        if chosen:
            break
    if chosen is None:
        chosen = best_third or (row_sizes(size0)[-1], least)
    a["size"], a["perRow"] = size0, start
    if best_third is None:
        f.flags.append("your buff rows: even %d a row at icon size %d reach into the centre third" % (chosen[1], chosen[0]))
    if not a.get("fitRows"):
        # nothing writes your rows' settings (no places' Auras): the fit is
        # laid for the rows it found, and the player is asked to set them
        if chosen != (size0, start):
            f.eye.append("your buff rows %s: set Buffs & Debuffs to %d a row, icon size %d (now %d, %d)"
                         % ("reach into the centre third" if own_in else "run into other pieces", chosen[1], chosen[0], start, size0))
    else:
        if chosen[0] != size0:
            f.log.append({"rule": "F6 auras", "key": "Auras.playerSize", "what": "playerSize %d -> %d" % (size0, chosen[0]),
                          "why": "your buff rows by the minimap: smaller icons keep them out of the centre third"})
            f.eye.append("your buff icons at %d (from %d)" % (chosen[0], size0))
        if chosen[1] != start:
            f.log.append({"rule": "F6 auras", "key": "Auras.playerPerRow", "what": "playerPerRow %d -> %d" % (start, chosen[1]),
                          "why": "your buff rows by the minimap: %d a row keep all 32 buffs out of the centre third" % chosen[1]})
            f.eye.append("your buff rows wrap at %d a row (from %d)" % (chosen[1], start))
    a["size"], a["perRow"] = chosen
    # the game's external defensives hang on its debuff bar, which your rows
    # hide: when the rows run over them, they step down under the rows
    E = f.els()
    N = f.by_name(E)
    x, rb = N["External defensives"], N["Debuffs"]["rect"]
    over = [nm for nm in ("Buffs", "Debuffs") if frozenset((nm, x["name"])) not in f.inherited
            and hud.overlap(N[nm]["rect"], x["rect"])[0] > EPS and hud.overlap(N[nm]["rect"], x["rect"])[1] > EPS]
    if over:
        f.shift("6:2", "F6 auras", "external defensives step down under your buff rows (the game's debuff bar they hang on is hidden)",
                dy=-math.ceil((rb[3] + 4 - x["rect"][1]) * 10) / 10.0)
    hits = aura_hits(f, f.els())
    if hits:
        f.notes.append("your buff rows at %d a row: %s" % (chosen[1], "; ".join(hits)))


def f6_auras(f):
    """F6. The aura column: buffs a row (F6a), the tracker beside the column
    (F6b), and when the debuffs or external defensives still run into what
    shows with them in a fight, the icons get smaller (100 -> 90 -> 80 %),
    then the least bad size is kept (the checks report what remains). Your
    buff rows by the minimap column instead: f6_rows."""
    col = f.column()
    if hud.aura_rows(col, f.mello, f.W) is not None:
        f6_rows(f)
        return
    # the game's buff bar hangs on the minimap cluster's top left: a bigger
    # minimap's painted frame (the round ring, a square border) reaches past
    # the cluster's left edge into it, so the bar steps left, GAP clear
    N = f.by_name()
    b, m = N["Buffs"]["rect"], N["Minimap (kit frame + zone plate)"]["rect"]
    if yov(b, m) and b[0] < m[0] and b[2] > m[0] - GAP + EPS:
        f.shift("6:0", "F6 auras", "the buff bar steps left, %d clear of the bigger minimap's frame" % GAP,
                dx=-math.ceil((b[2] - (m[0] - GAP)) * 10) / 10.0)
    tried = []
    for raw, label in AURA_SIZES:
        snap = copy.deepcopy((f.lay, f.mello, f.log, f.eye, f.notes, f.flags))
        f6_try(f, raw, label)
        hits = aura_hits(f, f.els())
        if not hits:
            return
        tried.append((len(hits), raw, label, hits, snap))
        f.lay, f.mello, f.log, f.eye, f.notes, f.flags = snap
        f.recs = {x["key"]: x for x in f.lay["systems"]}
    n, raw, label, hits, _ = min(tried, key=lambda t: (t[0], -t[1]))
    f6_try(f, raw, label)
    f.notes.append("aura column at %s: %s" % (label, "; ".join(hits)))


def f6_try(f, size_raw, size_label):
    """F6a. Buffs are always on: their block (all 32 buffs) stays right of the
    centre third and clear of the persistent pieces -- fewer icons a row, more
    rows. When no row length clears everything, the longest that clears the
    centre third is kept and the rest is reported. Debuffs a row: at most
    buffs - 1."""
    for key in ("6:0", "6:1", "6:2"):
        f.set(key, "IconSize", size_raw, "F6 auras", "aura icons at %s: the column fits beside the tracker and above the bottom centre" % size_label)
    if size_raw != AURA_SIZES[0][0]:
        f.eye.append("aura icons at %s (from 100%%)" % size_label)
    x0, x1 = third(f)
    start = hud.setting(f.recs["6:0"], "IconLimitBuffFrame")
    best_third = None
    chosen = None
    rec = f.recs["6:0"]
    for per in range(start, 1, -1):
        hud.set_setting(rec, "IconLimitBuffFrame", per)          # trial, logged once below
        E = f.els()
        b = f.by_name(E)["Buffs"]["rect"]
        in_third = b[0] < x1 - EPS
        hits = [e["name"] for e in persistent(E) if e["unit"] not in ("auras", "minimap") and
                hud.overlap(b, e["rect"])[0] > EPS and hud.overlap(b, e["rect"])[1] > EPS]
        if not in_third and best_third is None:
            best_third = per
        if not in_third and not hits:
            chosen = per
            break
    if chosen is None:
        chosen = best_third or 2
        if best_third is None:
            f.flags.append("buffs: even 2 a row reach into the centre third")
    hud.set_setting(rec, "IconLimitBuffFrame", start)
    f.set("6:0", "IconLimitBuffFrame", chosen, "F6 auras", "buffs %d a row: the block (32 buffs) stays right of the centre third" % chosen)
    if chosen < start:
        f.eye.append("buffs wrap at %d a row (from %d)" % (chosen, start))
    perd = hud.setting(f.recs["6:1"], "IconLimitDebuffFrame")
    if perd > chosen - 1:
        f.set("6:1", "IconLimitDebuffFrame", max(4, chosen - 1), "F6 auras", "debuffs a row no wider than the buffs above them")
    f6b_column(f)
    E = f.els()
    b = f.by_name(E)["Buffs"]["rect"]
    hits = [e["name"] for e in persistent(E) if e["unit"] not in ("auras", "minimap") and
            hud.overlap(b, e["rect"])[0] > EPS and hud.overlap(b, e["rect"])[1] > EPS]
    if hits:
        f.notes.append("buffs %d a row: a full 32 buffs would reach %s" % (chosen, ", ".join(hits)))


def f6b_column(f):
    """F6b. A taller aura column (buffs wrapped into more rows) runs past the quest
    tracker's top: the tracker (300 wide, wider than the minimap above it) gets
    narrower, not below 270, so the column runs down beside it; if that is not
    enough the debuff rows step left of it."""
    E = f.els()
    N = f.by_name(E)
    tr = f.tracker()
    col = [N["Buffs"]["rect"], N["Debuffs"]["rect"], N["External defensives"]["rect"]]
    hits = [c[2] + GAP - tr[0] for c in col if yov(c, tr) and xov(c, tr, GAP)]
    if not hits:
        return
    t = f.mello["tracker"]
    cut = int(math.ceil(max(hits) / 10.0) * 10)                 # the Width slider's step
    if not f.column()["match"] and t["width"] - cut >= 270:     # (a tracker matching the minimap's width keeps it)
        f.log.append({"rule": "F6 auras", "key": "QuestTracker.width", "what": "width %d -> %d" % (t["width"], t["width"] - cut),
                      "why": "the aura column (32 buffs, 16 debuffs) runs down beside the tracker"})
        f.eye.append("quest tracker %d wide (from %d) beside the taller aura column" % (t["width"] - cut, t["width"]))
        t["width"] -= cut
        return
    d = N["Debuffs"]["rect"]
    if yov(d, tr) or yov(N["External defensives"]["rect"], tr):
        f.shift("6:1", "F6 auras", "debuff rows step left of the quest tracker", dx=-math.ceil((d[2] + GAP - tr[0]) * 10) / 10.0)


# ============================================================ F7..F9 pieces that show now and then

# the biggest first (they have the fewest places); each piece avoids the ones
# placed before it, and the ones after it make room for it
ORDER = ["boss", "party", "raid", "focus", "extra", "doll", "tooltip"]


PIECE = {"boss": ("Boss frames", "3:5"), "party": ("Party frames", "3:3"), "raid": ("Raid frames (8 groups of 5)", "3:4"),
         "focus": ("Focus frame", "3:2"), "extra": ("Extra ability", "5:-1"), "doll": ("Durability doll", "16:-1"),
         "tooltip": ("Tooltip fallback corner", "11:-1")}
GRID = 8.0


def grid_spot(f, unit, later, prep=None):
    """F9g. The free spot nearest the piece's designed place, when none of its
    listed places is free: a grid of GRID units over the screen, never in the
    centre third above the bottom centre, at least GAP from every piece placed
    before it -- first from all of them, then only from the pieces it shows
    together with. The piece is then held to the screen corner nearest it, so
    it keeps its distance to that corner's edges."""
    if prep:
        prep()
    name, key = PIECE[unit]
    E = [e for e in f.els() if e["unit"] not in later]
    me = [e for e in E if e["name"] == name]
    if not me:
        return
    me = me[0]
    l0, t0, r0, b0 = me["rect"]
    w, h = r0 - l0, b0 - t0
    cx0, cy0 = (l0 + r0) / 2, (t0 + b0) / 2
    x0, x1 = third(f)
    ctop = hud.centre_top(E)
    W, H = f.W, f.H
    found = None
    for strict in (True, False):
        obst = []
        for o in E:
            if o["unit"] in (unit, "popup") or o["cat"] == "Q" or hud.pair_rule(me, o)                     or frozenset((me["name"], o["name"])) in f.inherited:
                continue
            if strict or hud.kind(me, o) == "hard":
                ol, ot, orr, ob = o["rect"]
                obst.append((ol - GAP, ot - GAP, orr + GAP, ob + GAP))
        y = GAP
        while y + h <= H - GAP + EPS:
            band = [o for o in obst if o[1] < y + h and o[3] > y]
            x = GAP
            while x + w <= W - GAP + EPS:
                if not (x < x1 and x + w > x0 and y < ctop):
                    hit = None
                    for o in band:
                        if o[0] < x + w and o[2] > x:
                            hit = o
                            break
                    if hit is None:
                        d = math.hypot(x + w / 2 - cx0, y + h / 2 - cy0)
                        if found is None or d < found[0]:
                            found = (d, x, y)
                    else:
                        x = max(x, math.floor((hit[2] - x) / GRID) * GRID + x)   # jump past the piece in the way
                x += GRID
            y += GRID
        if found:
            break
    if not found:
        return
    _, L, T = found
    right = L + w / 2 > W / 2
    bottom = T + h / 2 > H / 2
    point = ("BOTTOM" if bottom else "TOP") + ("RIGHT" if right else "LEFT")
    f.move(key, "F9g grid", "", point=point, rel_point=point,
           x=-(W - (L + w)) if right else L, y=(H - (T + h)) if bottom else -T)


def pick(f, unit, cands, rule):
    """F7-F9. The first candidate with no overlap at all and out of the centre
    third above the bottom centre; else the least bad one (off the screen, then
    hard overlaps, then the centre third, then soft, rare overlaps, then the
    candidate order).
    Pieces placed after this one (ORDER) do not count: they make room for it.
    When no listed place is free of hard overlaps and of the centre third, F9g's nearest free spot is
    tried as one more candidate (with the raid's smallest frames too)."""
    later = set(ORDER[ORDER.index(unit) + 1:])
    cands = list(cands)
    best, best_score = None, None
    grid_added = False
    i = -1
    while i + 1 < len(cands):
        i += 1
        desc, apply = cands[i]
        snap = copy.deepcopy((f.lay, f.mello, f.log))
        apply()
        f.recs = {s["key"]: s for s in f.lay["systems"]}
        E = [e for e in f.els() if e["unit"] not in later]
        cs = f.unit_conflicts(unit, E)
        on = all(-EPS <= e["rect"][0] and e["rect"][2] <= f.W + EPS and -EPS <= e["rect"][1] and e["rect"][3] <= f.H + EPS
                 for e in E if e["unit"] == unit)
        x0, x1 = third(f)
        ctop = hud.centre_top(E)
        mid = any(e["rect"][0] < x1 - EPS and e["rect"][2] > x0 + EPS and e["rect"][1] < ctop - EPS for e in E if e["unit"] == unit)
        score = (0 if on else 1, sum(c[0] == "hard" for c in cs), 1 if mid else 0, sum(c[0] == "soft" for c in cs), sum(c[0] == "rare" for c in cs), i)
        f.lay, f.mello, f.log = snap
        f.recs = {s["key"]: s for s in f.lay["systems"]}
        if best_score is None or score < best_score:
            best, best_score = i, score
        if score[:5] == (0, 0, 0, 0, 0):
            break
        if i == len(cands) - 1 and not grid_added and best_score[:3] != (0, 0, 0):
            grid_added = True
            cands.append(("the free spot nearest its designed place (grid search)", lambda: grid_spot(f, unit, later)))
            if unit == "raid":
                def small():
                    f.set("3:4", "FrameWidth", 0, "F9 raid", "raid frames at the game's smallest size")
                    f.set("3:4", "FrameHeight", 0, "F9 raid", "raid frames at the game's smallest size")
                cands.append(("the free spot nearest its designed place (grid search), 72 x 36 frames", lambda: grid_spot(f, unit, later, small)))
    desc, apply = cands[best]
    apply()
    f.recs = {s["key"]: s for s in f.lay["systems"]}
    for x in f.log:
        if x["rule"] in (rule, "F9g grid") and not x["why"]:
            x["why"] = desc
    if best_score[:5] != (0, 0, 0, 0, 0):
        cs = f.unit_conflicts(unit, [e for e in f.els() if e["unit"] not in later])
        txt = "; ".join("%s x %s (%s)" % (a["name"], b["name"], k) for k, a, b, ox, oy in cs) or ("in the centre third" if best_score[2] else "off the screen")
        (f.flags if best_score[0] or best_score[1] else f.notes).append("%s ('%s'): %s" % (unit, desc, txt))
    return best


def onto_screen_dx(f, r):
    return (-r[0] + GAP if r[0] < 0 else 0) - (r[2] - f.W + GAP if r[2] > f.W else 0)


def f7_focus_extra(f):
    """F7. Focus frame and extra ability button follow the frames; when they meet
    something: pulled onto the screen, lifted above the chat / bottom-right
    corner, stacked on top of their frame, or put beside the tracker / meter."""
    E = f.els()
    N = f.by_name(E)
    H, W = f.H, f.W
    chat = hud.union([N["Chat panel"]["rect"], N["Chat tabs"]["rect"]])
    pl, tg = N["Player frame"]["rect"], N["Target frame"]["rect"]
    fo, ex = N["Focus frame"]["rect"], N["Extra ability"]["rect"]
    ax_fo, ax_ex = f.anchor("3:2")["offsetX"], f.anchor("5:-1")["offsetX"]
    a_pl, a_tg = f.anchor("3:0")["offsetX"], f.anchor("3:1")["offsetX"]
    br_top = min(e["rect"][1] for e in persistent(E, "br"))
    meter = N["Damage meter"]["rect"]
    tr = f.tracker()
    dfo, dex = onto_screen_dx(f, fo), onto_screen_dx(f, ex)
    centre_top = hud.centre_top(E)
    group_x = f.anchor("0:0")["offsetX"]            # the bottom centre's slide (F2 / F4)
    fc = [("beside the player frame", lambda: None),
          ("pulled onto the screen", lambda: f.move("3:2", "F7 focus", "", x=ax_fo + dfo)),
          ("lifted above the chat", lambda: f.move("3:2", "F7 focus", "", x=ax_fo + dfo, y=H - (chat[1] - GAP))),
          ("on top of the player frame", lambda: f.move("3:2", "F7 focus", "", x=a_pl, y=H - (pl[1] - GAP))),
          ("under the damage meter", lambda: f.move("3:2", "F7 focus", "", point="TOPLEFT", rel_point="TOPLEFT", x=meter[0], y=-(meter[3] + GAP))),
          ("right of the chat, level with its bottom", lambda: f.move("3:2", "F7 focus", "", point="BOTTOMLEFT", rel_point="BOTTOMLEFT",
                                                                     x=chat[2] + GAP, y=H - chat[3]))]
    pick(f, "focus", fc, "F7 focus")
    ec = [("beside the target frame", lambda: None),
          ("pulled onto the screen", lambda: f.move("5:-1", "F7 extra", "", x=ax_ex + dex)),
          ("lifted above the bottom-right corner", lambda: f.move("5:-1", "F7 extra", "", x=ax_ex + dex, y=H - (br_top - GAP))),
          ("on top of the target frame", lambda: f.move("5:-1", "F7 extra", "", x=a_tg, y=H - (tg[1] - GAP))),
          ("left of the quest tracker's bottom", lambda: f.move("5:-1", "F7 extra", "", point="BOTTOMRIGHT", rel_point="BOTTOMRIGHT",
                                                                x=-(W - tr[0] + GAP), y=H - tr[3])),
          # the game's own default: centred above the bars (it shows only in a
          # fight or a quest, so the centre third's rule for always-on pieces
          # does not apply); over the centre group's top, centred on it
          ("above the bottom centre, the game's own place", lambda: f.move("5:-1", "F7 extra", "", point="BOTTOM", rel_point="BOTTOM",
                                                                         x=group_x, y=H - (centre_top - GAP)))]
    pick(f, "extra", ec, "F7 extra")


def f8_corner(f):
    """F8. Durability doll and the tooltip fallback corner (MelloUI anchors the
    tooltips to the cursor, so the corner is a fallback)."""
    E = f.els()
    W, H = f.W, f.H
    tr = f.tracker()
    br = hud.union([e["rect"] for e in persistent(E, "br")])
    dc = [("above the tray", lambda: None),
          ("left of the quest tracker, level with its top", lambda: f.move("16:-1", "F8 doll", "", point="TOPRIGHT", rel_point="TOPRIGHT",
                                                                            x=-(W - tr[0] + GAP), y=-tr[1])),
          ("left of the micro menu row", lambda: f.move("16:-1", "F8 doll", "", x=-(W - br[0] + GAP), y=H - br[3]))]
    pick(f, "doll", dc, "F8 doll")
    tc = [("above the doll", lambda: None),
          ("left of the quest tracker's bottom", lambda: f.move("11:-1", "F8 tooltip", "", x=-(W - tr[0] + GAP), y=H - tr[3])),
          ("above the bottom-right corner", lambda: f.move("11:-1", "F8 tooltip", "", x=-18, y=H - (br[1] - GAP)))]
    pick(f, "tooltip", tc, "F8 tooltip")


RAID_COMPACT = [(None, "as designed"), ((0, 0), "72 x 36 frames (the game's smallest)")]   # FrameWidth / FrameHeight raw
BOSS_GAP = 20              # the design's gap between the boss frames and the quest tracker (-325.8 against -5.8 - 300)


def f9_boss(f):
    """F9 boss (placed first of the pieces that show now and then: the biggest).
    Left of the tracker as designed; under the aura column; left of the aura
    column; left of the tracker with its bottom on the bottom centre's top;
    right of the chat, level with its top or with its bottom on the bottom
    centre's top; under the damage meter; left of the doll beside the tracker."""
    W = f.W
    E = f.els()
    N = f.by_name(E)
    tr = f.tracker()
    doll = N["Durability doll"]["rect"]
    col = hud.union([N["Buffs"]["rect"], N["Debuffs"]["rect"], N["External defensives"]["rect"]])
    left = min(tr[0], doll[0] if yov(doll, tr) and doll[2] <= tr[0] + EPS else tr[0])
    ctop = hud.centre_top(E)
    b0 = N["Boss frames"]["rect"]
    bh = b0[3] - b0[1]
    m = N["Damage meter"]["rect"]
    chat = hud.union([N["Chat panel"]["rect"], N["Chat tabs"]["rect"]])
    # (left of the quest tracker as designed: the boss frames' right edge
    # BOSS_GAP left of the tracker's left edge, wherever the tracker now is --
    # under the minimap column since the refit)
    bx = -(W - tr[0] + BOSS_GAP)
    c = [("left of the quest tracker", lambda: f.move("3:5", "F9 boss", "", x=bx)),
         ("left of the quest tracker, under the aura column", lambda: f.move("3:5", "F9 boss", "", x=bx, y=-(col[3] + GAP))),
         ("left of the aura column, level with the tracker's top", lambda: f.move("3:5", "F9 boss", "", x=-(W - col[0] + GAP), y=-tr[1])),
         ("left of the quest tracker, its bottom on the bottom centre's top", lambda: f.move("3:5", "F9 boss", "", x=bx, y=-(ctop - GAP - bh))),
         ("right of the chat, level with its top", lambda: f.move("3:5", "F9 boss", "", point="TOPLEFT", rel_point="TOPLEFT", x=chat[2] + GAP, y=-chat[1])),
         ("right of the chat, its bottom on the bottom centre's top", lambda: f.move("3:5", "F9 boss", "", point="TOPLEFT", rel_point="TOPLEFT", x=chat[2] + GAP, y=-(ctop - GAP - bh))),
         ("under the damage meter", lambda: f.move("3:5", "F9 boss", "", point="TOPLEFT", rel_point="TOPLEFT", x=m[0], y=-(m[3] + GAP))),
         ("left of the doll beside the tracker", lambda: f.move("3:5", "F9 boss", "", x=-(W - left + 20)))]
    pick(f, "boss", c, "F9 boss")


def f9_groups(f):
    """F9. Party / raid frames (in a group / raid / boss fight: they show
    with everything on the screen then, so an overlap with it counts as hard).
    Party and raid: as designed, under the damage meter, right of it, right of
    the chat; then the same places with the raid's smallest frames."""
    E = f.els()
    N = f.by_name(E)
    m = N["Damage meter"]["rect"]
    chat = hud.union([N["Chat panel"]["rect"], N["Chat tabs"]["rect"]])
    W = f.W
    for unit, key in (("party", "3:3"), ("raid", "3:4")):
        c = []
        for size, sdesc in (RAID_COMPACT if unit == "raid" else RAID_COMPACT[:1]):
            def sized(size=size, key=key):
                if size:
                    f.set(key, "FrameWidth", size[0], "F9 " + unit, "raid frames at the game's smallest size")
                    f.set(key, "FrameHeight", size[1], "F9 " + unit, "raid frames at the game's smallest size")
            tag = "" if size is None else ", " + sdesc
            c += [("where the design has it" + tag, lambda sized=sized: sized()),
                  ("under the damage meter" + tag, lambda key=key, sized=sized: (sized(), f.move(key, "F9 " + unit, "", point="TOPLEFT", rel_point="TOPLEFT", x=f.anchor(key)["offsetX"], y=-(m[3] + GAP)))),
                  ("right of the damage meter" + tag, lambda key=key, sized=sized: (sized(), f.move(key, "F9 " + unit, "", point="TOPLEFT", rel_point="TOPLEFT", x=m[2] + GAP, y=-m[1]))),
                  ("right of the chat, level with its top" + tag, lambda key=key, sized=sized: (sized(), f.move(key, "F9 " + unit, "", point="TOPLEFT", rel_point="TOPLEFT", x=chat[2] + GAP, y=-chat[1])))]
        pick(f, unit, c, "F9 " + unit)
        if unit == "raid" and hud.setting(f.recs["3:4"], "FrameWidth") != hud.setting(src_recs(f)["3:4"], "FrameWidth"):
            f.eye.append("raid frames at the game's smallest size, 72 x 36 (from 98 x 44): 8 groups are %d wide instead of %d"
                         % (8 * 72, 8 * 98))


def src_recs(f):
    return {s["key"]: s for s in f.src["systems"]}


# ============================================================ F10 pop-ups

def f10_popups(f):
    """F10. Pieces the game centres (loot, loss of control, encounter bar, timers):
    kept where they are, pulled onto the screen when they would leave it."""
    E = f.els()
    for e in E:
        if e["unit"] != "popup" or not e["keys"]:
            continue
        l, t, r, b = e["rect"]
        dx = (-l if l < 0 else 0) - (r - f.W if r > f.W else 0)
        down = (-t if t < 0 else 0) - (b - f.H if b > f.H else 0)     # screen y grows downward
        key = e["keys"][0]
        if (abs(dx) > EPS or abs(down) > EPS) and not f.recs[key]["isInDefaultPosition"]:
            f.shift(key, "F10 pop-up", "%s pulled onto the screen" % e["name"], dx=dx, dy=-down)


# ============================================================ F0 one store per place

def f0_store(f):
    """F0. One store per place: Edit Mode places the minimap, the damage meter,
    the chat and the game's tracker, so MelloUI's store keeps no place for
    them, and the Quest Tracker has no place of its own (it hangs on the game's
    tracker, Edit Mode 12:-1). Removes the snapshot's entries, and on a player's
    machine any stale entries from an earlier MelloUI profile. Runs first: the
    tracker's place below is read from 12:-1."""
    P = f.mello["positions"]
    for key in hud.EDIT_MODE_FRAMES:
        if key in P:
            old = P.pop(key)
            f.log.append({"rule": "F0 store", "key": "positions." + key, "what": "removed (was %s)" % old,
                          "why": "Edit Mode places this frame; one store per place (Reset positions then returns to the fitted place)"})
    if f.mello["tracker"].get("pos") is not None:
        f.log.append({"rule": "F0 store", "key": "QuestTracker.pos", "what": "removed (was %s)" % f.mello["tracker"]["pos"],
                      "why": "the tracker hangs on the game's tracker, placed by Edit Mode 12:-1 (QuestTracker.lua:302-310)"})
        f.mello["tracker"]["pos"] = None


# ============================================================ F12 MelloUI's own windows

def f12_windows(f):
    """F12. The windows in the user's snapshot (ship only if the user says so,
    decision 7). W1: on a screen wider than 21:9 a window held to the left /
    right edge is held to the 21:9 zone's edge instead. W2: a window that would
    leave the screen at its size (times the game's checkFit scale) is pulled
    back by what is missing plus GAP, keeping its anchor. Then the world map +
    Quest List pair stays on the screen (wave 3's FitOnScreen with extraRects),
    the Quest List narrower (not below its 260) when the pair is wider than the
    screen."""
    P = f.mello["positions"]
    W, H = f.W, f.H
    for name in sorted(P):
        if name not in hud.WINDOWS:
            continue
        p = P[name]
        before = dict(p)
        rp = p.get("relPoint") or "CENTER"
        edge = {0: "L", 0.5: "C", 1: "R"}[hud.AX[rp][0]]
        s = hud.window_scale(name, W, H)
        if f.inset and edge in ("L", "R"):
            p["x"] = round(p.get("x", 0) + (f.inset if edge == "L" else -f.inset) / s, 1)
        rc, s = hud.window_rect(name, p, W, H)
        dx = (GAP - rc[0] if rc[0] < 0 else 0) - (rc[2] - W + GAP if rc[2] > W else 0)
        down = (GAP - rc[1] if rc[1] < 0 else 0) - (rc[3] - H + GAP if rc[3] > H else 0)
        if rc[2] - rc[0] > W - 2 * GAP:
            dx = (W - (rc[2] - rc[0])) / 2.0 - rc[0]
            f.flags.append("%s is wider than the screen (%.0f of %.0f)" % (name, rc[2] - rc[0], W))
        if rc[3] - rc[1] > H - 2 * GAP:
            down = (H - (rc[3] - rc[1])) / 2.0 - rc[1]
            f.flags.append("%s is taller than the screen (%.0f of %.0f)" % (name, rc[3] - rc[1], H))
        if abs(dx) > EPS or abs(down) > EPS:
            p["x"] = round(p.get("x", 0) + dx / s, 1)
            p["y"] = round(p.get("y", 0) - down / s, 1)
        if p != before:
            why = []
            if f.inset and edge in ("L", "R"):
                why.append("W1: held to the 21:9 zone's %s edge" % ("left" if edge == "L" else "right"))
            if abs(dx) > EPS or abs(down) > EPS:
                why.append("W2: pulled onto the screen by %.1f, %.1f (%s is %.0f x %.0f%s)" % (
                    dx, -down, name, hud.WINDOWS[name][0] * s, hud.WINDOWS[name][1] * s, ", scaled %.2f by the game" % s if s < 0.999 else ""))
            f.log.append({"rule": "F12 windows", "key": "positions." + name, "what": "%s -> %s" % (before, p), "why": "; ".join(why)})
    ql = f.mello["questlist"]

    def pull(with_log):
        m, q = hud.worldmap_rects(f.mello, W, H, with_log)
        u = hud.union([m, q])
        dx = (-u[0] if u[0] < 0 else 0) - (u[2] - W if u[2] > W else 0)
        down = (-u[1] if u[1] < 0 else 0) - (u[3] - H if u[3] > H else 0)
        if abs(dx) > EPS or abs(down) > EPS:
            p = P["WorldMapFrame"]
            p["x"] = round(p.get("x", 0) + dx, 1)
            p["y"] = round(p.get("y", 0) - down, 1)
            f.log.append({"rule": "F12 map", "key": "positions.WorldMapFrame", "what": "moved %.1f, %.1f" % (dx, -down),
                          "why": "the map%s and the Quest List stay on the screen together" % (" with its quest log" if with_log else "")})
        return u

    for with_log in (True, False):
        m, q = hud.worldmap_rects(f.mello, W, H, with_log)
        u = hud.union([m, q])
        if u[2] - u[0] <= W and u[3] - u[1] <= H:
            pull(with_log)
            if not with_log:
                f.notes.append("world map with its quest log open (1035) + Quest List (%d) are wider than %d units: fits with the log closed" % (ql["width"], W))
            return
    room = int((W - 702 - 2) // 10 * 10)
    if room >= 260:
        old = ql["width"]
        ql["width"] = min(old, room)
        f.log.append({"rule": "F12 map", "key": "QuestList.width", "what": "%d -> %d" % (old, ql["width"]), "why": "map + Quest List fit the width"})
        f.eye.append("Quest List %d wide (from %d)" % (ql["width"], old))
        pull(False)
        f.notes.append("world map with its quest log open (1035 wide, the game's own panel) + the Quest List do not fit %d units" % W)
    else:
        f.flags.append("world map + Quest List cannot fit %d units" % W)


# ============================================================ the whole fit

def fit(src, mello, w, h, scale=None, label="", inherited=frozenset()):
    W, H, s = ui_parent(w, h, scale)
    tried = []
    for level in range(len(COMPACT) + 1):
        f = Fit(src, mello, W, H, label, inherited)
        f.scale, f.level = s, level
        f0_store(f)
        f1_zone(f)
        apply_compact(f, level)
        f0b_bars(f)
        f5m_column(f)
        f5_tracker(f, with_centre=False)
        f2_chat(f)
        f3_frames(f)
        f5_tracker(f, with_centre=True, keep=TRACKER_KEEP)
        slid = f4_slide(f)
        f5_tracker(f, with_centre=True)
        ok = band_ok(f)
        if slid and ok:
            break
        tried.append("level %d: %s" % (level, "; ".join(f.band_why) or getattr(f, "band_note", "")))
    else:
        f.flags.append("bottom band not solved even at the smallest compact sizes: %s" % (getattr(f, "band_note", "") or "; ".join(f.band_why)))
    f.levels_tried = tried
    f6_auras(f)
    f9_boss(f)
    f9_groups(f)
    f7_focus_extra(f)
    f8_corner(f)
    f10_popups(f)
    f12_windows(f)
    return f


# ============================================================ encode + validate

CODEC_KEYS = ("key", "system", "systemName", "systemIndex", "systemIndexName", "frame", "isInDefaultPosition", "anchor", "anchor2")


def codec_checks(lay, src):
    out = {}
    s = C.encode(lay)
    d = C.decode(s)
    out["roundTrip"] = C.encode(d) == s
    out["sameAsJson"] = all({k: a[k] for k in CODEC_KEYS} == {k: b[k] for k in CODEC_KEYS} and
                            [(e["id"], e["value"]) for e in a["settings"]] == [(e["id"], e["value"]) for e in b["settings"]]
                            for a, b in zip(d["systems"], lay["systems"]))
    out["header"] = " ".join(s.split(" ")[:3])
    out["sameSystems"] = [x["key"] for x in d["systems"]] == [x["key"] for x in src["systems"]]
    out["sameSettingIds"] = all([e["id"] for e in a["settings"]] == [e["id"] for e in b["settings"]] for a, b in zip(d["systems"], src["systems"]))
    out["newRangeWarnings"] = sorted(set(C.validate(d)) - set(C.validate(src)))
    toks = s.split(" ")
    fl, i = [], 3
    for _ in d["systems"]:
        fl += [toks[i + 6], toks[i + 7]]
        i += 10
    out["offsetsOneDecimal"] = all(re.match(r"^-?\d+\.\d$", t) for t in fl) and i == len(toks)
    out["chars"] = len(s)
    out["ok"] = out["roundTrip"] and out["sameAsJson"] and out["sameSystems"] and out["sameSettingIds"] and not out["newRangeWarnings"] and out["offsetsOneDecimal"] and out["header"].startswith("4 0 ")
    return s, out


# ============================================================ run

def verdict(rep, codec, f):
    """FAIL: something always on leaves the screen; two pieces that show
    together overlap (hud.kind: both always on, or a boss / raid / extra ability
    piece over what is on the screen with it); something always on sits in the
    centre third; MelloUI's store keeps a place for an Edit Mode system; a
    window leaves the screen; the string does not round-trip; or a rule could
    not reach its minimum. PASS, needs the user's eye: solved, but the look
    changed where the user should see it (including every remaining overlap of
    a piece that shows now and then, never with the other). PASS: only the
    design's own places."""
    bad = []
    if rep["off"]:
        bad.append("off screen")
    if rep["hard"]:
        bad.append("pieces that show together overlap")
    if rep["centre"]:
        bad.append("centre third")
    if rep["stores"]:
        bad.append("store holds an Edit Mode system")
    if [w for w in rep["windows"] if not w.startswith("world map with its quest log")]:
        bad.append("window off the screen")
    if not codec["ok"]:
        bad.append("codec")
    if f.flags:
        bad.append("unsolved")
    if bad:
        return "FAIL (" + ", ".join(bad) + ")"
    if f.eye:
        return "PASS, needs the user's eye"
    return "PASS"


def places(f):
    """What the installer writes into MelloUI's own settings for this screen."""
    return {
        "UIModifications.positions": {
            "remove": list(hud.EDIT_MODE_FRAMES),
            "windows (decision 7: shipped only if the user says so)": {k: v for k, v in sorted(f.mello["positions"].items())},
        },
        "QuestTracker": {"pos": None, "maxHeight": f.mello["tracker"]["maxHeight"], "width": f.mello["tracker"]["width"]},
        "QuestList": {"width": f.mello["questlist"]["width"]},
        "UIModifications.layoutFitFor": "%.1fx%.1f" % (f.W, f.H),
        # your buff rows by the column: Icons Per Row and Icon Size as fitted
        # (None while the rows are not by the column, or for a caller that
        # does not write them: auras.fitRows)
        "Auras": ({"playerPerRow": hud.auras_input(f.mello)["perRow"], "playerSize": hud.auras_input(f.mello)["size"]}
                  if hud.aura_rows(f.column(), f.mello, f.W) is not None and hud.auras_input(f.mello).get("fitRows") else None),
    }


def summarize_changes(f, src):
    changed = []
    for a, b in zip(src["systems"], f.lay["systems"]):
        if C._encode_system(a) != C._encode_system(b):
            changed.append(a["key"])
    return changed


def design_diff(a_txt, b_txt):
    """The systems (and what in them) that differ between two share strings."""
    a, b = C.decode(a_txt), C.decode(b_txt)
    out = []
    for x, y in zip(a["systems"], b["systems"]):
        if C._encode_system(x) == C._encode_system(y):
            continue
        what = []
        if x["anchor"] != y["anchor"]:
            what.append("anchor %s %s->%s %.1f, %.1f -> %s %s->%s %.1f, %.1f" % (
                x["anchor"]["relativeTo"], x["anchor"]["point"], x["anchor"]["relativePoint"], x["anchor"]["offsetX"], x["anchor"]["offsetY"],
                y["anchor"]["relativeTo"], y["anchor"]["point"], y["anchor"]["relativePoint"], y["anchor"]["offsetX"], y["anchor"]["offsetY"]))
        for e, g in zip(x["settings"], y["settings"]):
            if e["value"] != g["value"]:
                what.append("%s %s -> %s" % (e["name"], e["value"], g["value"]))
        if x["isInDefaultPosition"] != y["isInDefaultPosition"]:
            what.append("isInDefaultPosition %s -> %s" % (x["isInDefaultPosition"], y["isInDefaultPosition"]))
        out.append("%s %s%s: %s" % (x["key"], x["systemName"], ("." + x["systemIndexName"]) if x["systemIndexName"] else "", "; ".join(what)))
    return out


def main():
    import sketch
    os.makedirs(OUT, exist_ok=True)
    src_txt, txt16 = load_layouts()
    final_txt = open(FINAL_TXT, encoding="latin-1").read()
    assert src_txt == final_txt, "Media/EditModeLayout.lua `layout` is not EditModeLayout.final.txt"
    src = C.decode(src_txt)
    assert C.encode(src) == src_txt
    mello = load_mello(SV_21)
    # what the approved layout already has at its own screen (not the fitter's to change)
    base = hud.check(src, DESIGN_W, DESIGN_H, approved_mello(mello))
    inherited = set()
    for kd, a, b, ox, oy in hud.conflicts(base["elements"]):
        inherited.add(frozenset((a["name"], b["name"])))
    results = {"model": {
        "uiParent": "UIParent height = 768 / scale, width = height x (screen w / h); scale = max(0.64, 768 / screen height) "
                    "(observed with 'Use UI Scale' off on client 1.60.1.70009; changes when Blizzard fixes the UI-scale bug)",
        "designUIParent": [round(DESIGN_W, 2), DESIGN_H], "gap": GAP,
        "source": "Media/EditModeLayout.lua `layout` (= MelloUI-BuildData/installer/2026-09-26_21x9_immersive/EditModeLayout.final.txt)",
        "melloSnapshot": SV_21,
        "inheritedFromSource": sorted(" x ".join(sorted(p)) for p in inherited),
        "sourceNearMisses": base["near"],
        "showTogether": {"situationsByCategory": {k: sorted(v) for k, v in hud.SIT_BY_CAT.items()},
                         "situationsByPiece": {k: sorted(v) for k, v in hud.SIT_BY_NAME.items()},
                         "rule": "two pieces overlap HARD when both are always on, or their situations meet (hud.kind)"},
        "windowSizes": {k: {"w": v[0], "h": v[1], "fit": v[2], "source": v[3]} for k, v in hud.WINDOWS.items()},
    }, "screens": []}
    sketches = []
    for sid, w, h, sc, label in SCREENS:
        f = fit(src, mello, w, h, sc, label, frozenset(inherited))
        s, codec = codec_checks(f.lay, src)
        rep = hud.check(f.lay, f.W, f.H, f.mello, inherited, inset=f.inset)
        for t in rep["soft"]:
            f.eye.append("now and then (never at the same time as the piece under it): " + t)
        for t in rep["centreNowAndThen"]:
            f.eye.append("in the centre third when it shows: " + t)
        v = verdict(rep, codec, f)
        d = os.path.join(OUT, sid.replace("@", "_at_"))
        os.makedirs(d, exist_ok=True)
        open(os.path.join(d, "layout.txt"), "w", encoding="latin-1", newline="").write(s)
        store = places(f)
        json.dump(store, open(os.path.join(d, "melloui_places.json"), "w"), indent=1)
        png = os.path.join(d, "sketch.png")
        sketch.draw(rep, f, png, title="%s  %s" % (sid, label), verdict=v)
        sketches.append((png, sid, v, f))
        changed = summarize_changes(f, src)
        entry = {
            "id": sid, "screen": [w, h], "label": label, "scale": round(f.scale, 4),
            "uiParent": [round(f.W, 2), round(f.H, 2)], "uiParentExact": [f.W, f.H], "zoneInset": round(f.inset, 1), "compactLevel": f.level,
            "verdict": v,
            "shareString": s, "codec": codec,
            "changedSystems": changed,
            "rules": f.log, "needsUsersEye": f.eye, "unsolved": f.flags, "notes": f.notes,
            "checks": {k: rep[k] for k in ("off", "hard", "soft", "rare", "inherited", "info", "near", "centre", "centreNowAndThen", "stores", "windows")},
            "unitFrameTop": round(rep["unit_top"], 1),
            "melloPlaces": store,
            "files": {"layout": os.path.relpath(os.path.join(d, "layout.txt"), HERE), "sketch": os.path.relpath(png, HERE),
                      "places": os.path.relpath(os.path.join(d, "melloui_places.json"), HERE)},
        }
        results["screens"].append(entry)
        print("%-16s %8.2f x %7.2f  s=%.3f  inset=%6.1f  compact=%d  changed=%2d  %s" % (sid, f.W, f.H, f.scale, f.inset, f.level, len(changed), v))
        for x in f.eye:
            print("      eye: " + x)
        for x in f.flags:
            print("      UNSOLVED: " + x)
        for x in f.notes:
            print("      note: " + x)
        for k in ("off", "hard", "centre", "stores", "windows", "soft"):
            for x in rep[k]:
                print("      %s: %s" % (k, x))
        if rep["rare"]:
            print("      rare (both only now and then): %d" % len(rep["rare"]))
    # the design screen against the approved string: since the flip it
    # differs in the minimap's Size and what that forces (refit, build round 4)
    ident = [e for e in results["screens"] if e["id"] in ("3440x1440", "3440x1440@0.64")]
    results["identity"] = {e["id"]: e["shareString"] == src_txt for e in ident}
    results["designDiff"] = {e["id"]: design_diff(src_txt, e["shareString"]) for e in ident}
    print("identity (fit of the design screen == the approved string):", results["identity"])
    for sid, d in results["designDiff"].items():
        print("design screen %s against the approved string:" % sid)
        for x in d:
            print("   %s" % x)
    # decision 6, what if: a player whose hidden bars (3, 4, 6, 7, 8) all hold actions
    results["whatIfBarsWithActions"] = []
    mb = copy.deepcopy(mello)
    mb["barsWithActions"] = list(BAR_SLOTS)
    print("\n== what if: Action Bars 3, 4, 6, 7 and 8 hold actions (decision 6, second choice)")
    for sid, w, h, sc, label in SCREENS:
        if sid not in WHATIF_BARS:
            continue
        f = fit(src, mb, w, h, sc, label, frozenset(inherited))
        s, codec = codec_checks(f.lay, src)
        rep = hud.check(f.lay, f.W, f.H, f.mello, inherited, inset=f.inset)
        for t in rep["soft"]:
            f.eye.append("now and then (never at the same time as the piece under it): " + t)
        for t in rep["centreNowAndThen"]:
            f.eye.append("in the centre third when it shows: " + t)
        v = verdict(rep, codec, f)
        d = os.path.join(OUT, "_whatif_bars", sid)
        os.makedirs(d, exist_ok=True)
        open(os.path.join(d, "layout.txt"), "w", encoding="latin-1", newline="").write(s)
        png = os.path.join(d, "sketch.png")
        sketch.draw(rep, f, png, title="%s  what if bars 3, 4, 6-8 hold actions" % sid, verdict=v)
        results["whatIfBarsWithActions"].append({
            "id": sid, "verdict": v, "compactLevel": f.level, "codecOk": codec["ok"], "needsUsersEye": f.eye,
            "unsolved": f.flags, "checks": {k: rep[k] for k in ("off", "hard", "centre", "centreNowAndThen")},
            "rules": [x for x in f.log if x["rule"].startswith("F0b")], "shareString": s,
            "files": {"layout": os.path.relpath(os.path.join(d, "layout.txt"), HERE), "sketch": os.path.relpath(png, HERE)}})
        print("%-16s compact=%d  %s" % (sid, f.level, v))
        for x in f.eye:
            print("      eye: " + x)
        for x in f.flags:
            print("      UNSOLVED: " + x)
        for x in rep["hard"] + rep["off"] + rep["centre"]:
            print("      check: " + x)
    # 16:9 comparison
    import compare16
    results["compare16x9"] = compare16.run(src, txt16, mello, load_mello(SV_16), inherited)
    json.dump(results, open(os.path.join(OUT, "results.json"), "w", encoding="utf-8"), indent=1)
    sketch.contact_sheet(sketches, os.path.join(OUT, "contact_sheet.png"))


if __name__ == "__main__":
    main()

"""HUD model for the screen-fitting prototype (scratch, not shipped).

  solve(layout, W, H)            -> {key: rect}   system rects (L, T, R, B; UIParent
                                    units, origin top-left, y down)
  elements(layout, W, H, mello)  -> [piece]      what the player sees: game systems
                                    plus MelloUI's own pieces and kit footprints
  check(layout, W, H, mello)     -> report       inside the screen / overlaps /
                                    centre third / no MelloUI store entry for
                                    an Edit Mode system / windows on the screen

Sizes come from lib/rects_orig.py (the 21:9 work's estimates from the client
source and the user's screenshot); kit footprints from lib/validate_orig.py.
The Lua port uses the same rule: every size comes from the layout's own
settings plus the constant kit footprints and window sizes below. It never
measures live frames, which are sized for the player's current layout, not
the fitted one (fitting_spec.md section 5, "Sizes").
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "lib"))
import layoutcodec as C          # noqa: E402
import rects_orig as R0          # noqa: E402

AX = R0.AX
GAP = 8.0            # the smallest gap the fitter leaves between two pieces
EPS = 0.05

# ------------------------------------------------------------------ settings

def setting(rec, name):
    for e in rec["settings"]:
        if e["name"] == name:
            return e["value"]
    return None


def disp(rec, name):
    for e in rec["settings"]:
        if e["name"] == name:
            return C.raw_to_display(rec["systemName"], e["id"], e["value"])
    return None


def set_setting(rec, name, raw):
    for e in rec["settings"]:
        if e["name"] == name:
            e["value"] = int(raw)
            e["meaning"] = C._meaning(rec["systemName"], e["name"], e["id"], int(raw), None)
            return
    raise KeyError("%s has no setting %s" % (rec["key"], name))


def visible(rec):
    """Hidden bars / timers do not draw (the game still shows a bar's grid while a
    spell is dragged, so their system rects are still checked for the screen)."""
    v = disp(rec, "VisibleSetting") if rec["systemName"] == "ActionBar" else None
    if rec["systemName"] == "SwingTimer":
        v = disp(rec, "Visibility")
    return v not in ("HIDDEN", "Hidden", 3, 2) if v is not None else True


def bar_cat(rec):
    v = disp(rec, "VisibleSetting")
    return {"IN_COMBAT": "C", "OUT_OF_COMBAT": "O"}.get(v, "A")


# ------------------------------------------------------------------ rects

def solve(layout, W, H):
    """System rects at UIParent W x H. The same anchor maths as the game
    (EditModeSystemMixin:ApplySystemAnchor: offsets are UIParent units)."""
    R0.W, R0.H = W, H
    R0.EXTRA_FRAMES["UIParent"] = (0.0, 0.0, W, H)
    notes = R0.solve(layout)
    rects = {k: tuple(n["rect"]) for k, n in notes.items() if n and n.get("rect")}
    return rects, notes


def rect_at(W, H, point, rel_point, x, y, w, h, rel=None):
    return R0.anchor_rect(rel or (0.0, 0.0, W, H), point, rel_point, x, y, w, h)


def overlap(a, b):
    ox = min(a[2], b[2]) - max(a[0], b[0])
    oy = min(a[3], b[3]) - max(a[1], b[1])
    return ox, oy


def gap(a, b):
    return max(a[0] - b[2], b[0] - a[2]), max(a[1] - b[3], b[1] - a[3])


def union(rs):
    rs = [r for r in rs if r]
    return (min(r[0] for r in rs), min(r[1] for r in rs), max(r[2] for r in rs), max(r[3] for r in rs))


# ------------------------------------------------------------------ pieces
# categories: A always, T with a target, O out of combat, C in combat,
# K while casting, M on mouseover  (persistent: they overlap the play for real)
# S situational, V on a taxi/vehicle, L while looting, P pet/totem class only
# Q test client only (reported, never counted)
PERSISTENT = set("ATOCKM")
CAT_TEXT = {"A": "always", "T": "with a target", "O": "out of combat", "C": "in combat", "K": "while casting",
            "M": "on mouseover", "S": "when needed", "V": "on a taxi", "L": "while looting", "P": "class-specific",
            "Q": "test client only"}

AURA_MAX = {"buff": 32, "debuff": 16}


def aura_blocks(lay, r):
    """The buff / debuff / external-defensive blocks at their worst case (every
    row the frame can fill), so a full row never runs into anything."""
    recs = {s["key"]: s for s in lay["systems"]}
    b = recs["6:0"]
    per = setting(b, "IconLimitBuffFrame") or 11
    k = (disp(b, "IconSize") or 100) / 100.0
    pad = disp(b, "IconPadding") or 5
    bR, bT = r["6:0"][2], r["6:0"][1]
    rows = math.ceil(AURA_MAX["buff"] / per)
    buffs = (bR - per * (30 + pad) * k - 15, bT, bR, bT + rows * (40 + pad) * k)
    d = recs["6:1"]
    perd = setting(d, "IconLimitDebuffFrame") or 8
    dr = math.ceil(AURA_MAX["debuff"] / perd)
    dR, dT = bR - 15, buffs[3] + 4
    debuffs = (dR - perd * (30 + pad) * k, dT, dR, dT + dr * (40 + pad) * k)
    # the external defensives hang on the debuffs' bottom right by their own
    # offsets (the design's 0, -4; F6 may lower them under your buff rows)
    ea = recs["6:2"]["anchor"]
    eR, eT = debuffs[2] + ea["offsetX"], debuffs[3] - ea["offsetY"]
    ext = (eR - 5 * (30 + pad) * k, eT, eR, eT + (40 + pad) * k)
    return buffs, debuffs, ext, per, perd


TRACK_FOLLOW = (180, 700)        # QuestTracker FOLLOW_MIN, FOLLOW_MAX (its own units)


def tracker_match_w(col, s):
    """The tracker's width on the screen while it matches the minimap's."""
    return min(TRACK_FOLLOW[1], max(TRACK_FOLLOW[0], (col["ref"][2] - col["ref"][0]) / s)) * s


def tracker_rect(mello, W, H, rects=None, col=None):
    """MelloUI's Quest Tracker. With no place of its own (pos = nil, what the
    installer writes) its right edge hangs on the game's tracker's TOPRIGHT,
    which Edit Mode places by record 12:-1 (Modules/QuestTracker.lua:302-310 at
    HEAD 56375c4: SetPoint("TOPRIGHT", f, "TOPRIGHT") and its width set)."""
    t = mello["tracker"]
    s = t.get("scale", 1) or 1
    w, h = t["width"] * s, t["maxHeight"] * s
    if col is not None and col["match"]:
        # Match The Minimap's Width (QuestTracker, the flip): as wide on the
        # screen as the column's frame, whatever its own width, within the
        # grip's bounds (180..700 of its own units)
        w = tracker_match_w(col, s)
    if t.get("pos") is None:
        r = rects["12:-1"]
        return (r[2] - w, r[1], r[2], r[1] + h)
    x, y = t["pos"]["x"] * s, t["pos"]["y"] * s
    return (W + x - w, -y, W + x, -y + h)


# The windows whose places are in the user's snapshot (UI Modifications'
# store), with their sizes in UI units from the client source in
# layout2/codec/src_all (the Camelot files where the game type has its own).
# checkFit: the game's panel manager scales the window down to fit the screen
# (UIParentPanelManager.lua:73-75), with this extra room; "fit": MelloUI's own
# FitToScreen (Core/Config.lua:2479-2500 at HEAD 56375c4, 16 of room). None: drawn at 1.
WINDOWS = {
    "CharacterFrame": (631, 484, None, "Camelot/CharacterFrameConstants.lua:4-5 (398 wide with the right pane closed)"),
    "FriendsFrame": (385, 424, None, "Blizzard_FriendsFrame/Camelot/FriendsFrame.xml:391"),
    "MacroFrame": (338, 424, None, "Blizzard_MacroUI.xml:26"),
    "ProfessionsFrame": (673, 594, ("checkFit", 20, 20), "Blizzard_Professions/Camelot/Blizzard_ProfessionsFrame.xml:11, checkFit in Blizzard_ProfessionsRegistration.lua:8"),
    "LFGParentFrame": (458, 535, None, "Blizzard_GroupFinder_VanillaStyle/Mainline/Blizzard_LFGVanilla_ParentFrame.xml:31 (the [Family] file)"),
    "CommunitiesFrame": (814, 426, None, "Blizzard_Communities/CommunitiesFrame.xml:304"),
    "PlayerSpellsFrame": (1618, 883, ("checkFit", 200, 140), "Blizzard_PlayerSpells/Camelot/Blizzard_PlayerSpellsFrame.xml:12 (spellbook maximised; 809 minimised), checkFit in Blizzard_PlayerSpellsRegistration.lua:6-8"),
    "CollectionsJournal": (703, 606, None, "Blizzard_Collections/Shared/Blizzard_Collections.xml:5"),
    "LegacySystemFrame": (920, 575, None, "Blizzard_LegacySystem/Blizzard_LegacySystem.xml:5"),
    "ContainerFrameCombinedBags": (430, 440, None, "estimate: 10 columns of 37 + 5 spacing (Mainline/ContainerFrame.lua:2879-2885), ~80 slots"),
    "MelloUIConfigFrame": (1080, 760, ("fit", 16, 16), "Core/Config.lua WIDE_WIDTH, WINDOW_HEIGHT (the width when UI Modifications' tabs need it); Modules/KitWindow.lua Shell:Fit, 16 of room, with its dressing (DRESS)"),
    # the store places wave 3 moved into the one store (refit, build round 4)
    "voiceOverlay": (600, 200, None, "Modules/VoiceOver.lua FRAME_W, FRAME_H, at its default Overlay Scale (1)"),
    "whisper": (340, 210, None, "Modules/Chat.lua POPUP_W, POPUP_H: the stored corner is the first popup's"),
}
# windows that open one after the other from their stored place: how far the
# last reaches right and down past the first (the whisper popups: six places,
# each 24 right and 24 down of the one before, Modules/Chat.lua)
CASCADE = {"whisper": 5 * 24}
# how far a window's own dressing reaches past its frame (left, right, top,
# bottom, in its units): counted by its fit and in its rect. The configurator
# with the kit: the outer rail (Kit:OuterRailOutset, 42 x 0.375) on every side
# and the crest over the top (Kit:RailMiddle 6.375 + half the ring, 197 x 0.375
# x 1.25 / 2)
DRESS = {"MelloUIConfigFrame": (15.75, 15.75, 52.546875, 15.75)}


def window_scale(name, W, H):
    w, h, fitmode, _ = WINDOWS[name]
    if not fitmode:
        return 1.0
    _, ew, eh = fitmode
    d = DRESS.get(name, (0.0, 0.0, 0.0, 0.0))
    return min(1.0, (W - ew) / (w + d[0] + d[1]), (H - eh) / (h + d[2] + d[3]))


def window_rect(name, place, W, H):
    """A window at its stored place: the store's compact form (point nil =
    BOTTOMLEFT, relPoint nil = CENTER; Modules/UIModifications.lua PutBack),
    offsets and size in the window's own units (times its scale)."""
    w, h, _, _ = WINDOWS[name]
    s = window_scale(name, W, H)
    point, rp = place.get("point") or "BOTTOMLEFT", place.get("relPoint") or "CENTER"
    rc = rect_at(W, H, point, rp, place.get("x", 0) * s, place.get("y", 0) * s, w * s, h * s)
    c = CASCADE.get(name)
    if c:
        rc = (rc[0], rc[1], rc[2] + c * s, rc[3] + c * s)
    d = DRESS.get(name)
    if d:
        rc = (rc[0] - d[0] * s, rc[1] - d[2] * s, rc[2] + d[1] * s, rc[3] + d[3] * s)
    return rc, s


def worldmap_rects(mello, W, H, with_log):
    """The world map (windowed: 702x534, 1035 with its quest log, Blizzard_WorldMap.lua
    SetupMinimizeMaximizeButton / QuestLogOwnerMixin.lua:166) and the Quest List
    docked on its right (+2, Modules/QuestListPanel.lua:656-658)."""
    p = mello["positions"].get("WorldMapFrame", {})
    mw = 702 + (333 if with_log else 0)
    point, rp = p.get("point") or "BOTTOMLEFT", p.get("relPoint") or "CENTER"
    m = rect_at(W, H, point, rp, p.get("x", 0), p.get("y", 0), mw, 534)
    ql = (m[2] + 2, m[1], m[2] + 2 + mello["questlist"]["width"], m[3])
    return m, ql


# ------------------------------------------------------------------ the minimap column (layout E)
# MelloUI's column under the minimap (Modules/MinimapPanel.lua's column
# contract; top to bottom as M:ColumnOrder has it by default: the zone band,
# the map, Route's distance line, the Services row, then the Quest Tracker),
# at the minimap's Edit Mode Size k. Since the flip (build round 4) the map's
# size is Edit Mode's alone; the painted frame and the Services bar live in
# the map's container, which that Size scales, so their measures below are
# map units, times k on the screen.
#   rims (left, top, right, bottom) of the painted frame round the map, as
#   LaySquare lays them (a rail's opaque depth at Kit.scale x the border's
#   scale, less the 1 px it lies over the map): the kit's square borders, the
#   kit's round ring (window/portrait_ring from the map x 0.75 of its opening:
#   its opaque box past the map), the game's own frame art (the container)
RAILS = {"window": (17.0, 17.375, 16.625, 17.375), "single": (5.6, 5.6, 5.6, 5.6),
         "red": (9.875, 11.75, 9.875, 11.75), "iron": (9.875, 11.75, 9.875, 11.75), "none": (0.0, 0.0, 0.0, 0.0)}
RING_RIM = 20.65
GAME_RIM = (8.5, 14.0, 8.5, 14.0)
# the Services bar (Modules/Services.lua LayoutBar): width, height and the
# stone above it merged (the divider rail's band, MinimapPanel's
# M:DividerHeight(), 26 with either Button Layout). Groups: one row of 5
# cells min(38, (198 - 6 x 4) / 5) plus 5 above and under; All Buttons: two
# rows (merged: cells as wide as the map allows; loose: 26 px icons in the
# kit's rim, the round rim or none)
ROW_GROUPS = (198.0, 44.8, 26.0)
ROW_ALL_MERGED = (198.0, 81.6, 26.0)
ROW_ALL_KIT = (244.0, 100.6)
ROW_ALL_ROUND = (222.0, 91.8)
ROW_ALL_PLAIN = (160.0, 67.0)
LINE_GAP, LINE_H = 2.0, 12.0    # Route's distance line (MinimapPanel LINE_GAP, LINE_H)
# the design's MelloUI settings for the column and the buff rows (Full's:
# the square map in the window frame merged with the Services groups, the
# Quest Tracker matching the minimap's width, your buff rows by the column)
DESIGN_COLUMN = {"kit": True, "shape": "square", "border": "window", "merge": True, "bar": True, "groups": True,
                 "barOffset": -26, "roundIcons": True, "match": True}
DESIGN_AURAS = {"rows": True, "attached": True, "size": 38, "perRow": 12}
AURA_GAP = 13                    # Modules/Auras.lua ATTACH_GAP


def column_input(mello):
    c = dict(DESIGN_COLUMN)
    c.update(mello.get("column") or {})
    return c


def auras_input(mello):
    a = dict(DESIGN_AURAS)
    a.update(mello.get("auras") or {})
    return a


def column(lay, r, mello):
    """The column at the layout's minimap Size, from the cluster's rect r["2:-1"]:
    the map; the painted frame round it (merged: round the Services bar too);
    the pieces the player sees (the frame with the zone band or plate, and the
    Services row); the column's left and right as M:ColumnRect has them (the
    square frame or the map, and a loose bar) for the buff rows; its bottom
    (the frame, a loose bar, Route's line) for the tracker; `ref`, the frame
    the Quest Tracker matches and lines up with (M:ColumnWidth's line: the
    kit's square border or merged frame where it shows, else the map -- the
    round ring is not in it)."""
    c = column_input(mello)
    rec = [x for x in lay["systems"] if x["key"] == "2:-1"][0]
    k = (disp(rec, "Size") or 100) / 100.0
    mc = r["2:-1"]
    mL, mT, mR, mB = R0.map_rect(mc, k)
    kit, square = bool(c["kit"]), c["shape"] == "square"
    border = c["border"] if c["border"] in RAILS else "window"
    if kit and square:
        rim = RAILS[border]
    elif kit:
        rim = (RING_RIM, RING_RIM, RING_RIM, RING_RIM)
    else:
        rim = GAME_RIM
    merged = kit and square and border in ("window", "single") and bool(c["merge"]) and bool(c["bar"])
    row = None
    if c["bar"]:
        if c["groups"]:
            row = ROW_GROUPS
        elif merged:
            row = ROW_ALL_MERGED
        elif kit:
            row = ROW_ALL_KIT
        elif c["roundIcons"]:
            row = ROW_ALL_ROUND
        else:
            row = ROW_ALL_PLAIN
    loose = None
    if merged:
        bt = mB + row[2] * k
        bb = bt + row[1] * k
        frame = (mL - rim[0] * k, mT - rim[1] * k, mR + rim[2] * k, bb + rim[3] * k)
        top = frame[1] - 2 * k                     # the zone plate on the frame's top rail
        piece = (frame[0], top, frame[2], bt)
        bar = (frame[0], bt, frame[2], frame[3])
    else:
        frame = (mL - rim[0] * k, mT - rim[1] * k, mR + rim[2] * k, mB + rim[3] * k)
        # the zone band at home (175 x 16, 15 right of the cluster's middle, 4
        # down; the kit's plate 1.4 x it), its buttons at its ends
        cc = (mc[0] + mc[2]) / 2
        if kit:
            bl, bt0, br = cc - 107.5, mc[1] + 0.8, cc + 137.5
        else:
            bl, bt0, br = cc - 91.5, mc[1] + 4.0, cc + 122.5
        top = min(frame[1], bt0)
        piece = (min(frame[0], bl), top, max(frame[2], br), frame[3])
        bar = None
        if row is not None:
            cx = (mL + mR) / 2
            bt = mB - c["barOffset"] * k
            loose = (cx - row[0] / 2 * k, bt, cx + row[0] / 2 * k, bt + row[1] * k)
            bar = loose
    # Route's distance line: 2 under the map, under a loose bar that leaves it no room (M:ColumnSlot("route"))
    lt = mB + LINE_GAP * k
    lb = lt + LINE_H * k
    if loose is not None and lb > loose[1] and lt < loose[3]:
        lt = loose[3] + LINE_GAP * k
        lb = lt + LINE_H * k
    bottom = max(frame[3], lb)
    if loose is not None:
        bottom = max(bottom, loose[3])
    mp = (mL, mT, mR, mB)
    block = frame if kit and square and border != "none" else mp
    ref = block
    # your buff rows stand beside the painted frame (Auras reads
    # M:ColumnPart("frame")): with the Minimap Kit its round ring's or square
    # border's outer edges, else the map's; never a loose bar
    side = frame if kit else mp
    left, right = side[0], side[2]
    return {"k": k, "map": mp, "frame": frame, "ref": ref, "piece": piece, "bar": bar, "left": left, "right": right,
            "bottom": bottom, "kit": kit, "match": kit and bool(c["match"]), "merged": merged}


def aura_rows(col, mello, W):
    """Your buff rows by the column (Modules/Auras.lua, Attach To The Minimap
    Column): their top corner AURA_GAP beside M:ColumnPart("frame")'s edge, level with
    the map's top; left of it growing leftwards, or right of it growing
    rightwards when the column stands in the screen's left half. Each line
    (size + 6) x perRow wide, size + 16 apart (the time under each icon); the
    buffs (32 at worst) then the debuffs (16) on the lines under them. None
    while the rows are not by the column (off, or the Minimap Kit off: the
    game's buff bar's place, modelled by aura_blocks)."""
    a = auras_input(mello)
    if not (a["rows"] and a["attached"] and col["kit"]):
        return None
    size, per = a["size"], a["perRow"]
    return rows_at(col, W, size, per)


def rows_room(col, W, x0, x1):
    """The room for your buff rows between the column and the centre third
    (x0, x1), beside the column as aura_rows puts them."""
    if col["left"] + col["right"] < W:
        return x0 - (col["right"] + AURA_GAP)
    return col["left"] - AURA_GAP - x1


def rows_at(col, W, size, per):
    line = (size + 6) * per
    pitch = size + 16
    nb, nd = math.ceil(AURA_MAX["buff"] / per), math.ceil(AURA_MAX["debuff"] / per)
    top = col["map"][1]
    if col["left"] + col["right"] < W:
        l = col["right"] + AURA_GAP
        r = l + line
    else:
        r = col["left"] - AURA_GAP
        l = r - line
    return (l, top, r, top + nb * pitch), (l, top + nb * pitch, r, top + (nb + nd) * pitch)


def elements(lay, W, H, mello):
    r, notes = solve(lay, W, H)
    recs = {s["key"]: s for s in lay["systems"]}
    E = []

    def add(name, cat, rc, unit, keys=()):
        if rc is None:
            return
        E.append({"name": name, "cat": cat, "rect": tuple(float(v) for v in rc), "unit": unit, "keys": list(keys)})

    # ---- top left: damage meter, party, raid
    add("Damage meter", "A" if disp(recs["23:-1"], "Visibility") in ("ALWAYS", None) else "S", r.get("23:-1"), "meter", ["23:-1"])
    if "3:3" in r:
        add("Party frames", "S", r["3:3"], "party", ["3:3"])
    ra = recs["3:4"]["anchor"]
    if ra["relativeTo"] == "UIParent":
        fw, fh = disp(recs["3:4"], "FrameWidth") or 98, disp(recs["3:4"], "FrameHeight") or 44
        add("Raid frames (8 groups of 5)", "S", rect_at(W, H, ra["point"], ra["relativePoint"], ra["offsetX"], ra["offsetY"], 8 * fw, 5 * fh + 14), "raid", ["3:4"])
    # ---- chat (MelloUI kit box + edit box below, tabs above)
    cf = r["8:-1"]
    add("Chat panel", "A", (cf[0] - 26, cf[1] - 8, cf[2] + 40, cf[3] + 29), "chat", ["8:-1"])
    add("Chat tabs", "M", (cf[0], cf[1] - 28, cf[0] + 218, cf[1] - 10), "chat", ["8:-1"])
    # ---- bottom centre
    b1 = r["0:0"]
    top_bar = b1
    for k in ("0:1", "0:2", "0:3"):
        if k in r and visible(recs[k]) and recs[k]["anchor"]["relativeTo"] != "UIParent":
            top_bar = r[k]
    add("Bar panel backdrop", "A", (b1[0] - 13, top_bar[1] - 16, b1[2] + 13, b1[3] + 8), "core", ["0:0"])
    for k, nm in (("0:0", "Action Bar 1"), ("0:1", "Action Bar 2"), ("0:2", "Action Bar 3"), ("0:3", "Action Bar 4"),
                  ("0:4", "Action Bar 5"), ("0:5", "Action Bar 6"), ("0:6", "Action Bar 7"), ("0:7", "Action Bar 8")):
        if k in r and visible(recs[k]):
            unit = "core" if recs[k]["anchor"]["relativeTo"] != "UIParent" or k == "0:0" else ("br" if k == "0:4" else "bars")
            if k in ("0:5", "0:6", "0:7") and recs[k]["anchor"]["relativeTo"] in ("MultiBarLeft", "MultiBar5", "MultiBar6"):
                unit = "br" if recs["0:4"]["anchor"]["relativePoint"].endswith("RIGHT") else "bars"
            add(nm if k != "0:4" else "Action Bar 5 (utility tray)", bar_cat(recs[k]), r[k], unit, [k])
    if "26:0" in r and not setting(recs["26:0"], "Hidden"):
        l, t, rr, b = r["26:0"]
        add("End cap left (painted)", "A", (l + 13.4, t + 9, rr - 11.6, b - 10), "core", ["26:0"])
    if "26:1" in r and not setting(recs["26:1"], "Hidden"):
        l, t, rr, b = r["26:1"]
        add("End cap right (painted)", "A", (l + 11.6, t + 9, rr - 13.4, b - 10), "core", ["26:1"])
    add("XP bar", "A", r.get("15:0"), "core", ["15:0"])
    add("Second tracked bar", "S", r.get("15:1"), "core", ["15:1"])
    if "0:10" in r:
        s = r["0:10"]
        add("Stance tab (kit plate)", "A", (s[0] - 15, s[1] - 16, s[2] + 12, s[3]), "core", ["0:10"])
    add("Pet bar tab", "P", r.get("0:11"), "core", ["0:11"])
    add("Possess bar", "S", r.get("0:12"), "core", ["0:12"])
    add("Totem bar tab (Wrath-style shaman)", "P", r.get("25:-1"), "core", ["25:-1"])
    cb = r["1:-1"]
    add("Cast bar + kit text", "K", (cb[0], cb[1], cb[2], cb[3] + 18), "core", ["1:-1"])
    for k, nm in (("29:0", "Swing timer main hand"), ("29:1", "Swing timer off hand"), ("29:2", "Swing timer ranged")):
        if k in r and visible(recs[k]):
            add(nm, "C", r[k], "core", [k])
    add("Vehicle / taxi exit", "V", r.get("9:-1"), "core", ["9:-1"])
    pl, tg = r["3:0"], r["3:1"]
    add("Player frame", "A", pl, "frames", ["3:0"])
    add("Target frame", "T", tg, "frames", ["3:1"])
    kt = (tg[2] - tg[0]) / 232.0
    add("Target auras (MelloUI row)", "T", (tg[0] + 142 * kt, tg[3] - 20 * kt, tg[0] + 236 * kt, tg[3] - 6 * kt), "frames", ["3:1"])
    kp = (pl[2] - pl[0]) / 232.0
    pcx, ptop = (pl[0] + pl[2]) / 2 + 30 * kp, pl[3] - 25 * kp
    add("Pet frame", "P", (pcx - 60 * kp, ptop, pcx + 60 * kp, ptop + 49 * kp), "frames", ["3:7"])
    add("Focus frame", "S", r.get("3:2"), "focus", ["3:2"])
    add("Extra ability", "S", r.get("5:-1"), "extra", ["5:-1"])
    # ---- top right: minimap column, auras, tracker, boss
    col = column(lay, r, mello)
    add("Minimap (kit frame + zone plate)", "A", col["piece"], "minimap", ["2:-1"])
    add("Services panel (MelloUI)", "A", col["bar"], "minimap", ["2:-1"])
    add("Queue eye", "S", r.get("27:-1"), "minimap", ["27:-1"])
    buffs, debuffs, ext, per, perd = aura_blocks(lay, r)
    rows = aura_rows(col, mello, W)
    if rows is not None:
        buffs, debuffs = rows
    add("Buffs", "A", buffs, "auras", ["6:0"])
    add("Debuffs", "S", debuffs, "auras", ["6:1"])
    add("External defensives", "S", ext, "auras", ["6:2"])
    add("Quest Tracker (MelloUI)", "A", tracker_rect(mello, W, H, r, col), "tracker", ["12:-1"])
    ba = recs["3:5"]["anchor"]
    if ba["relativeTo"] == "UIParent":
        add("Boss frames", "S", rect_at(W, H, ba["point"], ba["relativePoint"], ba["offsetX"], ba["offsetY"], 232, 300), "boss", ["3:5"])
    # ---- bottom right: micro menu, bags, tray, doll, tooltip corner
    mm = r["13:-1"]
    k = (disp(recs["13:-1"], "Size") or 100) / 100.0
    if setting(recs["13:-1"], "Orientation") == 0:
        ml = mm[2] - 11 * 27 * k - 5 * k
        add("Micro menu (kit row)", "A", (ml - 14, mm[1] - 14, mm[2] + 14, mm[3] + 14), "br", ["13:-1"])
    else:
        add("Micro menu (kit column)", "A", (mm[0] - 14, mm[1] - 14, mm[2] + 14, mm[3] + 14), "br", ["13:-1"])
    if not mello.get("hideBagBar"):
        add("Bag bar", "A", r.get("14:-1"), "br", ["14:-1"])
    add("Durability doll", "S", r.get("16:-1"), "doll", ["16:-1"])
    add("Tooltip fallback corner", "S", r.get("11:-1"), "tooltip", ["11:-1"])
    # ---- centre pop-ups the game places
    add("Loot window", "L", r.get("10:-1"), "popup", ["10:-1"])
    add("Loss of control alert", "S", r.get("28:-1"), "popup", ["28:-1"])
    add("Encounter bar", "S", r.get("4:-1"), "popup", ["4:-1"])
    add("Mirror timers", "S", r.get("17:-1"), "popup", ["17:-1"])
    rw = recs["24:-1"]["anchor"]
    add("Raid warning text", "S", rect_at(W, H, rw["point"], rw["relativePoint"], rw["offsetX"], rw["offsetY"], 800, 100), "popup", ["24:-1"])
    if mello.get("statsOn"):
        add("FPS / latency text", "A", (W - 18 - 90, H - 120 - 13, W - 18, H - 120), "br", [])
    add("Issue Reporter (test client)", "Q", (W - 580.67, H - 103, W - 508.67, H - 3), "client", [])
    return E, r, notes


# ------------------------------------------------------------------ pair rules
NEST = {
    ("Bar panel backdrop", "Action Bar 1"), ("Bar panel backdrop", "Action Bar 2"), ("Bar panel backdrop", "Action Bar 3"),
    ("Bar panel backdrop", "Action Bar 4"), ("Bar panel backdrop", "Stance tab (kit plate)"),
    ("Bar panel backdrop", "End cap left (painted)"), ("Bar panel backdrop", "End cap right (painted)"),
    ("Bar panel backdrop", "Pet bar tab"), ("Bar panel backdrop", "Totem bar tab (Wrath-style shaman)"),
    ("Minimap (kit frame + zone plate)", "Queue eye"), ("Target frame", "Target auras (MelloUI row)"),
    ("Minimap (kit frame + zone plate)", "Services panel (MelloUI)"),   # one column (a bar offset may lay the bar on the frame's rim)
    ("Player frame", "Pet frame"), ("XP bar", "Second tracked bar"),
    ("Chat panel", "Chat tabs"),
    # joined backdrops by design (Modules/ActionBarPanel.lua:415-417: "the bag bar on the micro menu")
    ("Micro menu (kit row)", "Bag bar"),
}
EXCL = [
    ({"Cast bar + kit text", "Vehicle / taxi exit"}, "on a taxi you do not cast"),
    ({"Possess bar", "Vehicle / taxi exit"}, "possess and taxi never together"),
    ({"Pet bar tab", "Stance tab (kit plate)"}, "no Classic class has both"),
    ({"Pet bar tab", "Totem bar tab (Wrath-style shaman)"}, "class-exclusive"),
    ({"Possess bar", "Pet bar tab"}, "the possess bar replaces the pet bar"),
    ({"Possess bar", "Stance tab (kit plate)"}, "the stance bar hides while possessing"),
    ({"Party frames", "Raid frames (8 groups of 5)"}, "party frames hide in a raid"),
    ({"Totem bar tab (Wrath-style shaman)", "Stance tab (kit plate)"}, "shamans have no stance bar in Classic"),
    ({"Totem bar tab (Wrath-style shaman)", "Possess bar"}, "only priests possess (Mind Control); shamans do not"),
]


def pair_rule(a, b):
    k = (a["name"], b["name"])
    if k in NEST or (k[1], k[0]) in NEST:
        return "nest"
    names = {a["name"], b["name"]}
    for s, why in EXCL:
        if names == s:
            return "excl"
    if {a["cat"], b["cat"]} in ({"V", "C"}, {"V", "K"}):
        return "excl"
    return None


# ------------------------------------------------------------------ show together
# When a piece is on the screen. Two pieces 'show together' when their
# situations meet; such a pair counts as HARD even when one or both of them
# show only now and then (critic, 2026-09-25: boss frames always come with a
# target, the raid frames sit on the chat in every raid).
#   idle: out of combat, solo      combat: a solo fight      group: in a group, out of combat
#   gfight: a group fight          boss: a boss fight        taxi: on a flight path
ALL_SIT = frozenset(("idle", "combat", "group", "gfight", "boss", "taxi"))
FIGHT = frozenset(("combat", "gfight", "boss"))
SIT_BY_CAT = {
    "A": ALL_SIT, "M": ALL_SIT,
    "T": ALL_SIT - {"taxi"}, "K": ALL_SIT - {"taxi"},
    "O": frozenset(("idle", "group", "taxi")),
    "C": FIGHT,
    "P": ALL_SIT,                     # pet / totem: always there for that class
}
SIT_BY_NAME = {
    "Boss frames": frozenset(("boss",)),
    "Extra ability": frozenset(("combat", "boss")),       # quest and encounter buttons
    "Focus frame": frozenset(("gfight", "boss")),
    "Debuffs": FIGHT, "External defensives": FIGHT,
    "Party frames": frozenset(("group", "gfight", "boss")),
    "Raid frames (8 groups of 5)": frozenset(("group", "gfight", "boss")),
    "Durability doll": ALL_SIT,                           # stays while the gear is damaged
    "Second tracked bar": ALL_SIT,
    "Queue eye": ALL_SIT,
    "Possess bar": frozenset(("combat", "boss")),
    "Vehicle / taxi exit": frozenset(("taxi",)),
    # the tooltip fallback corner shows for a moment while the cursor rests on
    # something (MelloUI puts tooltips at the cursor): never counted as together
    "Tooltip fallback corner": frozenset(),
}


def situations(e):
    if e["name"] in SIT_BY_NAME:
        return SIT_BY_NAME[e["name"]]
    return SIT_BY_CAT.get(e["cat"], frozenset())


def together(a, b):
    """The situations in which both pieces are on the screen."""
    return situations(a) & situations(b)


def kind(a, b):
    """hard: both always on, or they show together (see SIT_BY_*); soft: one is
    always on, the other shows now and then but never with it; rare: both show
    only now and then and never together; info: the test client's own button"""
    if "Q" in (a["cat"], b["cat"]):
        return "info"
    n = (a["cat"] in PERSISTENT) + (b["cat"] in PERSISTENT)
    if n == 2 or together(a, b):
        return "hard"
    return {1: "soft", 0: "rare"}[n]


def conflicts(E, extra=None, popups=False):
    """Overlapping pairs (both extents > EPS) that no rule allows. extra: only
    pairs with at least one piece in this list (the fitter's incremental test).
    The game's own pop-ups (loot window, loss of control, encounter bar, mirror
    timers, raid warning text) are drawn over the HUD for a few seconds by
    design: left out unless popups=True."""
    out = []
    pool = E if extra is None else extra
    seen = set()
    for a in pool:
        for b in E:
            if a is b or (id(b), id(a)) in seen:
                continue
            seen.add((id(a), id(b)))
            if pair_rule(a, b):
                continue
            if not popups and "popup" in (a["unit"], b["unit"]):
                continue
            ox, oy = overlap(a["rect"], b["rect"])
            if ox > EPS and oy > EPS:
                out.append((kind(a, b), a, b, ox, oy))
    return out


def near_misses(E, limit=4.0):
    out = []
    for i in range(len(E)):
        for j in range(i + 1, len(E)):
            a, b = E[i], E[j]
            if pair_rule(a, b) or "Q" in (a["cat"], b["cat"]) or "popup" in (a["unit"], b["unit"]):
                continue
            dx, dy = gap(a["rect"], b["rect"])
            g = max(dx, dy)
            if -EPS <= g < limit - EPS and (dx > -EPS or dy > -EPS):
                out.append("%s / %s %.1f" % (a["name"], b["name"], g))
    return out


# ------------------------------------------------------------------ checks

def centre_top(E):
    """The top of the bottom-centre group (unit frames, cast bar, swing timers):
    'above the unit frames' in the 21:9 design's rule."""
    return min(e["rect"][1] for e in E if e["unit"] in ("frames", "core") and e["cat"] in PERSISTENT)


def check(lay, W, H, mello, inherited=None, inset=0.0):
    E, r, notes = elements(lay, W, H, mello)
    off = []
    for k, n in notes.items():
        if n and n.get("rect"):
            l, t, rr, b = n["rect"]
            if l < -EPS or t < -EPS or rr > W + EPS or b > H + EPS:
                off.append("system %s L%.1f T%.1f R%.1f B%.1f" % (k, l, t, rr, b))
    for e in E:
        l, t, rr, b = e["rect"]
        if l < -EPS or t < -EPS or rr > W + EPS or b > H + EPS:
            off.append("%s [%s] L%.1f T%.1f R%.1f B%.1f" % (e["name"], e["cat"], l, t, rr, b))
    hard, soft, rare, info, inh = [], [], [], [], []
    inherited = inherited or set()
    for kd, a, b, ox, oy in conflicts(E):
        txt = "%s [%s] x %s [%s] (%.1f x %.1f)" % (a["name"], a["cat"], b["name"], b["cat"], ox, oy)
        if kd == "hard" and not (a["cat"] in PERSISTENT and b["cat"] in PERSISTENT):
            txt += " shows together: " + ", ".join(sorted(together(a, b)))
        sig = frozenset((a["name"], b["name"]))
        if sig in inherited:
            inh.append(txt)
        elif kd == "hard":
            hard.append(txt)
        elif kd == "soft":
            soft.append(txt)
        elif kd == "rare":
            rare.append(txt)
        else:
            info.append(txt)
    near = near_misses(E)
    pops = []
    for kd, a, b, ox, oy in conflicts(E, popups=True):
        if "popup" in (a["unit"], b["unit"]) and kd != "rare" and kd != "info":
            pops.append("%s x %s (%.0f x %.0f)" % (a["name"], b["name"], ox, oy))
    unit_top = centre_top(E)
    zone = W - 2 * inset                       # 32:9: the third of the 21:9 zone
    x0, x1 = inset + zone / 3.0, inset + 2 * zone / 3.0
    centre, centre_sit = [], []
    for e in E:
        l, t, rr, b = e["rect"]
        if t < unit_top - EPS and rr > x0 + EPS and l < x1 - EPS and e["unit"] != "frames":
            if e["cat"] in PERSISTENT:
                centre.append("%s [%s]" % (e["name"], e["cat"]))
            elif e["unit"] not in ("popup", "client") and e["cat"] != "Q":
                centre_sit.append("%s [%s]" % (e["name"], e["cat"]))
    # one store per place: an Edit Mode system has no entry in MelloUI's own
    # store (UI Modifications' PutBack would move it again with raw SetPoint,
    # UIModifications.lua:428-470), and the Quest Tracker has no place of its
    # own (it hangs on the game's tracker, which Edit Mode places)
    same = []
    for key in EDIT_MODE_FRAMES:
        if key in mello["positions"]:
            same.append("UI Modifications' store holds a place for %s, an Edit Mode system" % key)
    if mello["tracker"].get("pos") is not None:
        same.append("QuestTracker.pos is set: the tracker would not follow Edit Mode 12:-1")
    # windows (only 'on the screen' matters: they open over the HUD by design)
    win = []
    for with_log in (False, True):
        m, ql = worldmap_rects(mello, W, H, with_log)
        u = union([m, ql])
        if u[0] < -EPS or u[1] < -EPS or u[2] > W + EPS or u[3] > H + EPS:
            win.append("world map%s + Quest List %d L%.0f R%.0f (screen %.0f)" % (" with its quest log" if with_log else "", mello["questlist"]["width"], u[0], u[2], W))
    wrects = {}
    for name, place in sorted(mello["positions"].items()):
        if name not in WINDOWS:
            continue
        rc, s = window_rect(name, place, W, H)
        wrects[name] = (rc, s)
        if rc[0] < -EPS or rc[1] < -EPS or rc[2] > W + EPS or rc[3] > H + EPS:
            win.append("%s L%.0f T%.0f R%.0f B%.0f (screen %.0f x %.0f)" % (name, rc[0], rc[1], rc[2], rc[3], W, H))
    return {"W": W, "H": H, "off": off, "hard": hard, "soft": soft, "rare": rare, "info": info, "inherited": inh, "near": near,
            "centre": centre, "centreNowAndThen": centre_sit, "popups": pops, "unit_top": unit_top, "third": [x0, x1], "stores": same, "windows": win,
            "windowRects": wrects, "elements": E, "rects": r}


# Frames Edit Mode places; UI Modifications' movers can also store a place for
# them: PLAIN_HUD (Modules/UIModifications.lua:1274-1296 at HEAD 56375c4) and
# CHAT_FRAMES (:1362-1365, ChatFrame1..10; only ChatFrame1 is an Edit Mode system)
EDIT_MODE_FRAMES = ("MinimapCluster", "DamageMeter", "ChatFrame1", "ObjectiveTrackerFrame")

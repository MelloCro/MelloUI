"""Estimate each Edit Mode system's rect (UIParent units, origin TOP-LEFT, y down)
from a decoded layout, the client's default frame sizes and the size settings.

UIParent = 2866.67 x 1200 units: measured from the user's 2000x837 screenshot of
the 3440x1440 screen (bags bar TOPLEFT x=2821.1 -> 1968 px, micro menu centre
x=2633.3 -> 1837 px, XP bar right edge 1731.4 -> 1208 px, main bar top 1102 ->
769 px: 0.6977 screenshot px per unit = 2000/2866.67). That is an effective UI
scale of 768/1200 = 0.64 (1.2 physical px per unit), not the 0.70 in
Config.wtf (0.70 would give 2621 x 1097 and put the bags bar off-screen).
"""
import json, math, sys
import layoutcodec as C

W, H = 2866.67, 1200.0
PX = 2000.0 / W  # screenshot px per UI unit

AX = {"TOPLEFT": (0, 0), "TOP": (.5, 0), "TOPRIGHT": (1, 0), "LEFT": (0, .5), "CENTER": (.5, .5),
      "RIGHT": (1, .5), "BOTTOMLEFT": (0, 1), "BOTTOM": (.5, 1), "BOTTOMRIGHT": (1, 1)}


def setting(rec, name):
    for e in rec["settings"]:
        if e["name"] == name:
            return e["value"]
    return None


def disp(rec, name):
    v = setting(rec, name)
    if v is None:
        return None
    for e in rec["settings"]:
        if e["name"] == name:
            return C.raw_to_display(rec["systemName"], e["id"], v)


# The minimap cluster at Edit Mode's Size k (refit, build round 4: the map's
# size is Edit Mode's since the flip). MinimapCluster is a ResizeLayoutFrame
# (Blizzard_SharedXML/LayoutFrame.lua ResizeLayoutMixin:Layout; widthPadding
# 20, Blizzard_Minimap/Mainline/Minimap.xml) sized round its shown children:
# the MinimapContainer (215 x 226, the frame art's size, Camelot/Skin.lua),
# scaled by k, its TOP 10 right and 30 down of the cluster's top middle in the
# cluster's own units at any Size (SetHeaderUnderneath lays it again at
# offset / scale, Minimap.lua ResetFramePoints); the zone band (175 x 16, TOP
# 15 right, 4 down) with the tracking button (17 + 2) on its left and the
# calendar (1 + 19) on its right. The map (198 x 198) in the container's middle.
BOX_W, BOX_H, BOX_X, BOX_Y = 215.0, 226.0, 10.0, 30.0
MAP_PX = 198.0


def cluster_size(k):
    lo = min(BOX_X - BOX_W / 2 * k, -91.5)
    hi = max(BOX_X + BOX_W / 2 * k, 122.5)
    return hi - lo + 20, BOX_Y + BOX_H * k - 4


def map_rect(rr, k):
    """The map (198 x 198 at k) in the cluster rect rr (L, T, R, B)."""
    cx = rr[0] + (rr[2] - rr[0]) / 2 + BOX_X
    cy = rr[1] + BOX_Y + BOX_H * k / 2
    half = MAP_PX / 2 * k
    return (cx - half, cy - half, cx + half, cy + half)


def size_of(rec):
    """(w, h, how, confidence) in UIParent units, or None when not placeable."""
    s, idx = rec["systemName"], rec["systemIndex"]
    if s == "ActionBar":
        if idx in (11, 12, 13):
            btn = 30
            n = {11: 2, 12: 10, 13: 2}[idx]
            note = {11: "2 stance buttons (warrior lvl 15: Battle + Defensive; 3 from lvl 30)",
                    12: "10 pet buttons (hidden: no pet)", 13: "possess bar (hidden normally)"}[idx]
        else:
            btn = 45
            n = setting(rec, "NumIcons") or 12
            note = "%d x 45px buttons" % n
        rows = disp(rec, "NumRows") or 1
        scale = (disp(rec, "IconSize") or 100) / 100.0
        pad = max(2, disp(rec, "IconPadding") or 2)
        stride = math.ceil(n / rows)
        horiz = (setting(rec, "Orientation") or 0) == 0
        a = stride * btn * scale + (stride - 1) * pad
        b = rows * btn * scale + (rows - 1) * pad
        w, h = (a, b) if horiz else (b, a)
        return w, h, "%s, %d row(s), icon %d%%, padding %d, %s" % (note, rows, scale * 100, pad, "horizontal" if horiz else "vertical"), \
            "high" if idx in range(1, 9) else "medium"
    if s == "CastBar":
        k = disp(rec, "BarSize") / 100.0
        return 208 * k, 11 * k, "PlayerCastingBarFrameTemplate 208x11 x BarSize %d%% (bar only, not its text/border)" % (k * 100), "medium"
    if s == "Minimap":
        k = (disp(rec, "Size") or 100) / 100.0
        w, h = cluster_size(k)
        return w, h, "MinimapCluster (ResizeLayoutFrame) round its children at Size %d%% (the container scaled)" % disp(rec, "Size"), "medium"
    if s == "UnitFrame":
        k = disp(rec, "FrameSize") / 100.0 if setting(rec, "FrameSize") is not None else 1.0
        if idx in (1, 2):
            return 232 * k, 100 * k, "232x100 x FrameSize %d%%" % (k * 100), "high"
        if idx == 3:
            small = not setting(rec, "UseLargerFrame")
            f = 0.75 if small else 1.0
            return 232 * k * f, 100 * k * f, "232x100 x FrameSize %d%% x %s (UseLargerFrame off -> SMALL_FOCUS_SCALE 0.75)" % (k * 100, f), "medium"
        if idx == 4:
            return 120 * k, 4 * 53 * k, "4 PartyMemberFrames 120x53 stacked (classic style; FrameWidth/Height only apply to raid-style), spacing ignored", "low"
        if idx == 8:
            return 120 * k, 49 * k, "PetFrame 120x49", "low"
        return None
    if s == "AuraFrame":
        k = disp(rec, "IconSize") / 100.0
        pad = disp(rec, "IconPadding")
        if idx == 1:
            per = disp(rec, "IconLimitBuffFrame")
            return (30 + pad) * per * k, (40 + pad) * k, "%d x (30x40 aura + %d) per row x %d%%, one row shown (grows down per 11 buffs)" % (per, pad, k * 100), "medium"
        if idx == 2:
            per = disp(rec, "IconLimitDebuffFrame")
            return (30 + pad) * per * k, (40 + pad) * k, "%d x (30x40 + %d) x %d%%, one row" % (per, pad, k * 100), "low"
        return 5 * (30 + pad) * k, (40 + pad) * k, "5 auras", "low"
    if s == "ChatFrame":
        w = setting(rec, "WidthHundreds") * 100 + setting(rec, "WidthTensAndOnes")
        h = setting(rec, "HeightHundreds") * 100 + setting(rec, "HeightTensAndOnes")
        return w, h, "ChatFrame1 %dx%d from the composite width/height settings (message area; tabs sit above, edit box below)" % (w, h), "high"
    if s == "DamageMeter":
        w = disp(rec, "FrameWidth"); h = disp(rec, "FrameHeight")
        return w, h, "FrameWidth %d x FrameHeight %d (raw + min)" % (w, h), "high"
    if s == "ObjectiveTracker":
        h = disp(rec, "Height")
        return 260, h, "ObjectiveTrackerContainerTemplate width 260, Height setting %d (MelloUI draws its own tracker instead)" % h, "medium"
    if s == "MicroMenu":
        k = disp(rec, "Size") / 100.0
        n = 12
        return (32 + (n - 1) * 27) * k, 40 * k, "%d micro buttons 32x40, childXPadding -5 (pitch 27) x Size %d%%; the screenshot shows the kit-dressed row ~470 wide" % (n, k * 100), "medium"
    if s == "Bags":
        k = disp(rec, "Size") / 100.0
        vert = setting(rec, "Orientation") == 1
        length = 45 * 5 + 33 + 5 * 2
        return (45 * k, length * k, "backpack + 4 bags 45px + keyring 33, padding 2, x Size %d%% (screenshot: 7 slots, ~41x299)" % (k * 100), "medium") if vert else \
            (length * k, 45 * k, "horizontal", "medium")
    if s == "StatusTrackingBar":
        k = disp(rec, "Size") / 100.0
        return 1192 * k, 17, "Camelot STATUS_BAR_CONTAINER_WIDTH 1192 x Size %d%%, height 17" % (k * 100), "high" if idx == 1 else "medium"
    if s == "MainActionBarEndCap":
        return 154, 95, "end cap frame 154x95 (MainMenuBarEndCaps.xml; the kit paints a round cap inside it)", "medium"
    if s == "DurabilityFrame":
        k = disp(rec, "Size") / 100.0
        return 60 * k, 75 * k, "60x75 x Size %d%% (shown only when gear is damaged)" % (k * 100), "medium"
    if s == "LootFrame":
        return 220, 290, "LootFrame 220x290 (shown while looting)", "medium"
    if s == "HudTooltip":
        return 250, 150, "GameTooltipDefaultContainer 250x150 (the default-anchored tooltip grows from it)", "medium"
    if s == "VehicleLeaveButton":
        return 32, 32, "32x32 (vehicles / taxi only)", "medium"
    if s == "EncounterBar":
        return 250, 30, "EncounterBar 250x30 (alt power / encounter bar only)", "medium"
    if s == "ExtraAbilities":
        return 256, 128, "ExtraAbilityContainer (layout frame, ~ one extra button + zone ability)", "low"
    if s == "SwingTimer":
        k = disp(rec, "Scale") / 100.0
        w = disp(rec, "Width"); h = disp(rec, "Height")
        return w * k, h * k, "Width %d x Height %d x Scale %d%% (Visibility %s)" % (w, h, k * 100, disp(rec, "Visibility")), "medium"
    if s == "GroupFinder":
        k = disp(rec, "Size") / 100.0
        return 45 * k, 45 * k, "QueueStatusButton 45x45 x Size %d%%" % (k * 100), "low"
    if s == "LossOfControl":
        k = disp(rec, "Size") / 100.0
        return 256 * k, 58 * k, "LossOfControlFrame 256x58 x %d%%" % (k * 100), "medium"
    if s == "TimerBars":
        k = disp(rec, "Size") / 100.0
        return 206 * k, 32 * k, "one MirrorTimer 206x32 (breath/fatigue)", "low"
    if s == "TalkingHeadFrame":
        return 570, 155, "570x155", "low"
    if s == "VehicleSeatIndicator":
        k = disp(rec, "Size") / 100.0
        return 128 * k, 128 * k, "128x128", "low"
    if s == "ArchaeologyBar":
        k = disp(rec, "Size") / 100.0
        return 200 * k, 30 * k, "200x30", "low"
    if s == "PersonalResourceDisplay":
        return 200, 75, "200x75 (only when the personal resource display is enabled)", "low"
    if s == "TotemActionBar":
        return 230, 38, "MultiCastActionBarFrame 230x38 (shaman only)", "low"
    return None


# frames the game's managed-frame containers place while the system is in its
# default position (BottomManagedFrameTemplate / RightManagedFrameTemplate /
# PlayerBottomManagedFrameTemplate in the client XML, plus the bottom action
# bar stack of EditModeUtil.GetBottomActionBars for Camelot)
MANAGED = {
    ("ActionBar", 11): "bottom action bar stack", ("ActionBar", 12): "bottom action bar stack",
    ("ActionBar", 13): "bottom action bar stack", ("CastBar", None): "bottom managed frame container",
    ("EncounterBar", None): "bottom managed frame container", ("ExtraAbilities", None): "bottom managed frame container",
    ("TalkingHeadFrame", None): "bottom managed frame container", ("VehicleLeaveButton", None): "bottom action bar stack",
    ("ArchaeologyBar", None): "bottom managed frame container", ("SwingTimer", None): "bottom managed frame container",
    ("ObjectiveTracker", None): "right managed frame container", ("DurabilityFrame", None): "right managed frame container",
    ("VehicleSeatIndicator", None): "right managed frame container", ("UnitFrame", 6): "right managed frame container",
    ("UnitFrame", 7): "right managed frame container", ("UnitFrame", 8): "player-frame bottom container",
    ("StatusTrackingBar", 1): "bottom action bar stack", ("StatusTrackingBar", 2): "bottom action bar stack",
}

# frames that are not systems but that systems anchor to
EXTRA_FRAMES = {"UIParent": (0.0, 0.0, W, H)}


def anchor_rect(rel_rect, point, rel_point, ox, oy, w, h):
    l, t, r, b = rel_rect
    rx, ry = AX[rel_point]
    px = l + (r - l) * rx + ox
    py = t + (b - t) * ry - oy
    ax, ay = AX[point]
    L = px - ax * w
    T = py - ay * h
    return (L, T, L + w, T + h)


def solve(layout, overrides=None):
    """overrides: {frameName: (point, relPoint, x, y, scaleOrNone)} placed on UIParent
    (MelloUI's window mover puts these frames back after every SetPoint)."""
    overrides = overrides or {}
    by_frame = {}
    for rec in layout["systems"]:
        if rec["frame"]:
            by_frame[rec["frame"]] = rec
    rects = dict(EXTRA_FRAMES)
    notes = {}
    pending = list(layout["systems"])
    for _ in range(6):
        left = []
        for rec in pending:
            sz = size_of(rec)
            fr = rec["frame"]
            if sz is None:
                a0 = rec["anchor"]
                n0 = {"size": None, "rect": None, "confidence": "low", "source": "edit mode" if not rec["isInDefaultPosition"] else "default position",
                      "why": "size is dynamic (group/raid/boss/cooldown/encounter content) or the system does not exist in Camelot"}
                if a0["relativeTo"] == "UIParent":
                    rx, ry = AX[a0["relativePoint"]]
                    n0["anchorPointAt"] = [round(W * rx + a0["offsetX"], 1), round(H * ry - a0["offsetY"], 1)]
                    n0["anchorPoint"] = a0["point"]
                notes[rec["key"]] = n0
                continue
            w, h, how, conf = sz
            a = rec["anchor"]
            src = "edit mode"
            if fr in overrides:
                p, rp, x, y, sc = overrides[fr]
                if sc:
                    x, y, w, h = x * sc, y * sc, w * sc, h * sc
                a = {"point": p, "relativePoint": rp, "relativeTo": "UIParent", "offsetX": x, "offsetY": y}
                src = "MelloUI saved position (overrides Edit Mode)"
            managed = MANAGED.get((rec["systemName"], rec["systemIndex"])) or MANAGED.get((rec["systemName"], None))
            if rec["isInDefaultPosition"] and fr not in overrides:
                if managed:
                    notes[rec["key"]] = {"size": [round(w, 1), round(h, 1)], "how": how, "confidence": "low", "rect": None,
                                         "source": "default position",
                                         "why": "in its default position the game's %s places it (stacked with the others), not this anchor" % managed}
                    continue
                src = "default position (preset anchor)"
                conf = "low" if conf != "high" else "medium"
            relname = a["relativeTo"]
            if relname not in rects:
                if relname in by_frame and by_frame[relname] in pending and relname not in rects:
                    left.append(rec)
                    continue
                if relname not in by_frame:
                    notes[rec["key"]] = {"size": [round(w, 1), round(h, 1)], "how": how, "confidence": "low",
                                         "source": src, "rect": None,
                                         "why": "anchored to %s, which is not an Edit Mode system (position depends on it)" % relname}
                    continue
            rel_rect = rects.get(relname)
            if rel_rect is None:
                left.append(rec)
                continue
            rr = anchor_rect(rel_rect, a["point"], a["relativePoint"], a["offsetX"], a["offsetY"], w, h)
            if fr:
                rects[fr] = rr
            if fr == "MinimapCluster":
                k = (disp(rec, "Size") or 100) / 100.0
                rects["Minimap"] = map_rect(rr, k)
            notes[rec["key"]] = {"size": [round(w, 1), round(h, 1)], "how": how, "confidence": conf, "source": src,
                                 "rect": [round(v, 1) for v in rr],
                                 "screenshotPx": [round(v * PX) for v in rr]}
        pending = left
        if not pending:
            break
    return notes


def fmt_table(layout, notes):
    rows = []
    for rec in layout["systems"]:
        n = notes.get(rec["key"])
        name = "%s%s" % (rec["systemName"], ("." + rec["systemIndexName"]) if rec["systemIndexName"] else "")
        r = n["rect"]
        if r:
            rs = "L%.0f T%.0f R%.0f B%.0f" % tuple(r)
        elif n.get("anchorPointAt"):
            rs = "%s at (%.0f, %.0f)" % (n["anchorPoint"], n["anchorPointAt"][0], n["anchorPointAt"][1])
        else:
            rs = "-"
        sz = "%gx%g" % tuple(n["size"]) if n.get("size") else "?"
        rows.append("%-6s %-34s %-32s %-7s %-10s | %s%s" % (rec["key"], name, rs, n["confidence"], sz, n["source"], ("; " + n["why"]) if n.get("why") and not r else ""))
    return "\n".join(rows)


if __name__ == "__main__":
    lay = C.decode(open(sys.argv[1], encoding="latin-1").read()) if len(sys.argv) > 1 else None
    print(fmt_table(lay, solve(lay)))

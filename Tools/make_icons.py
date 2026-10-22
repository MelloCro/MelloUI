"""
Build the game textures of MelloUI's own icon set (0.25.0; the user, 2026-10-19: the cartoon WoW map-marker icons
cut from their ChatGPT sheets, docs/plans/icons-and-palette.md): every icon as a 32-bit TGA at a power-of-two size,
its master under MelloUI-BuildData/masters/Media/Textures/Icons/ (Tools/paths.py) and a byte copy in the addon's
Media/Textures/Icons/ so it ships at once; texture_pack.py ship keeps them as their masters' bytes (STAY_TGA: their
soft alpha edges band as DXT).

The art: MelloUI-BuildData/masters/icons_v2/out/<group>/png128/<name>.png (cut by icons_v1/cut_sheet.py and
cut_buttons.py from icons_v2/src/sheet*.png), ring/ring_gold_256.png and ring/hover_glow_256.png. Drawn here: the
count badge's disc and its edge (white, the palette tints them). Each picture is scaled premultiplied (no dark fringe).
Deterministic: the same art gives the same bytes. Also the modern look's light effects (FX_LIGHT, from icons_v2/out/fx):
Media/FrameFX/Light/, the addon's only; and the map icons' lifts (HALO): Media/Textures/Icons/Halo/, the addon's only.

    python Tools/make_icons.py            write them
    python Tools/make_icons.py --check    exit 1 unless all are up to date
"""
import hashlib
import io
import json
import os
import sys

import numpy as np
from PIL import Image, ImageFilter
from paths import ADDON_MEDIA, master

ART = os.path.normpath(os.path.join(os.path.dirname(os.path.dirname(master("x"))), "icons_v2"))
OUT = ("Textures", "Icons")

# (group, art name, the file's name, size) -- size an int (square) or (w, h)
SET = []
for n in ("kill", "kill_elite", "kill_rare", "quest_mark", "turnin_mark", "loot"):
    SET.append(("marks", n, n, 64))
for n in ("pin_collect", "pin_portal", "pin_dungeon", "pin_raid", "pin_boat", "pin_zeppelin", "pin_tram"):
    SET.append(("pins", n, n, 64))
for n in ("track_todo", "track_handin", "svc_repair", "svc_mail", "svc_inn", "svc_flight", "svc_auction", "svc_bank",
          "svc_classtrainer", "svc_proftrainer", "svc_barber", "svc_vendor",
          # (Batch 30, 2026-10-20: Services' Errands and AddOns groups, the user's "needs its own icon to fit the theme")
          "svc_errands", "svc_addons"):
    SET.append(("services", n, n, 64))
for n in ("chat_general", "chat_combat", "chat_loot", "chat_whispers", "chan_say", "chan_party", "chan_raid",
          "chan_instance", "chan_guild", "chan_yell", "chan_whisper", "chan_emote", "chat_channels", "chat_friends",
          "chat_history", "chat_settings"):
    SET.append(("chat", n, n, 64))
for n in ("goal_red", "goal_cream", "goal_pin", "obj_use", "obj_explore"):
    SET.append(("route", n, n, 64))
for n in ("voice_greeting", "voice_page", "voice_progress"):
    SET.append(("voice", n, n, 32))
SET += [("trail", "map_dot", "map_dot", 32), ("trail", "route_bead", "route_bead", 32),
        ("trail", "edge_arrow", "edge_arrow", (64, 32))]
for n in ("btn_pause", "btn_play", "btn_next", "btn_stop", "btn_list", "btn_locked", "btn_unlocked", "btn_accept",
          "btn_decline", "btn_way", "btn_reply", "btn_meter", "btn_expand", "btn_collapse", "btn_friend", "btn_invite",
          "btn_ignore", "btn_report", "btn_sort", "btn_discard", "btn_arrow"):
    SET.append(("buttons", n, n, 64))
for n in ("ql_completed", "ql_chest", "ql_notyet"):
    SET.append(("questlist", n, n, 64))
SET += [("bags", "bag_backpack", "bag_backpack", 128), ("bags", "bag_reagent", "bag_reagent", 64)]
SET += [("controls", "ctl_check_off", "ctl_check_off", 64), ("controls", "ctl_check_on", "ctl_check_on", 64),
        ("controls", "ctl_knob", "ctl_knob", 64), ("controls", "ctl_dropdown", "ctl_dropdown", 32)]
for n in ("meter_damage", "meter_time", "meter_heal"):
    SET.append(("meter", n, n, 32))
for n in ("ct_taken", "ct_heal", "ct_notice", "ct_avoid", "ct_gain"):
    SET.append(("combattext", n + "_lift", n, 32))   # (the user's pick: the lifted ones, 2026-10-19)
# (2026-10-20, the user: "go all the way with the new icons") the configurator's side list: a picture per page and
# per category heading (Batches 15 to 17)
for n in ("page_look", "page_windows", "page_fader", "page_oldschool", "page_frames", "page_nameplates", "page_bars",
          "page_minimap", "page_meter", "page_chat", "page_tooltip", "page_screentext", "page_tracker", "page_questlist",
          "page_route", "page_reminders", "page_automation", "page_voice", "page_sounds", "page_profiles"):
    SET.append(("pages", n, n, 64))
for n in ("cat_look", "cat_frames", "cat_chat", "cat_quests", "cat_sound"):
    SET.append(("cats", n, n, 64))
# (the user's pick 2, Sapphire, 2026-10-20) the player arrow: it turns round its gem, the gem the picture's middle
# (cut_pieces.py arrows()); square, never cropped (SET's oblong rule would move the gem)
SET.append(("arrows", "arrow_sapphire", "arrow_player", 128))
# (2026-10-20, Batch 23) the action buttons' frames, square, hollow (Modules/ActionButtons.lua draws them as one
# nine-slice each: the corners kept, the band at the rim's width)
for n in ("normal", "hover", "pressed", "active", "empty", "range"):
    SET.append(("pieces", "btn_frame_" + n, "frame_" + n, 128))
SET.append(("pieces", "bar_spark", "bar_spark", (64, 48)))   # (Batch 24: the light on the fill's leading edge)
# (Batch 25) the unit frames' level badge (the ring and the bar frames are drawn into UF_FRAMES' pictures)
SET.append(("pieces", "uf_badge", "uf_badge", 64))
# (Batch 31, 2026-10-20, the user: "clean icons for party members ... in the theme" -- then "enough just in the
# color, we dont need the icons in the middle of it, so they can be scaled down") a plain disc per class in the set's
# pin style, its colour the sheet's disc's: CLASS_DISCS below, by the game's class file name
# (W.IconPath("class_" .. classFile)): the map's party
CLASSES = ("WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID")

# (2026-10-20, the user: the sheets were asked for with no glow and no shadow, "added later in the game" -- "you didnt
# add those effects to them") the lift of every icon shown on the maps and the minimap (MelloUI.Shade:Lift, Core/
# Shade.lua): a soft white copy of its outline, grown and blurred, on a canvas reaching HALO_PAD of the icon past each
# side; the game tints it -- the set's disc pins (HALO_DISCS, Shade.lua's DISCS) a gold glow reaching well out, the
# standalone marks a dark shade hugging their shape. (grow, blur, gain): the first two as shares of the icon's size
HALO_GROUPS = ("marks", "pins", "route", "questlist")
HALO_DISCS = ("pin_", "goal_", "obj_", "class_")
HALO_PAD, HALO_SIZE, HALO_WORK = 0.25, 64, 128   # (HALO_WORK: the icon's size while it is made, the canvas half again)
HALO_GLOW, HALO_SHADE = (0.05, 0.08, 2.6), (0.035, 0.04, 2.2)
HALO_OUT = ("Textures", "Icons", "Halo")


def load(group, name):
    if group == "ring":
        return Image.open(os.path.join(ART, "ring", name + ".png")).convert("RGBA")
    if group == "arrows":   # (cut_pieces.py: one square per arrow, its gem the middle)
        return Image.open(os.path.join(ART, "out", "arrows", name + ".png")).convert("RGBA")
    if group == "pieces":   # (cut_pieces.py: each piece whole, at the sheet's size)
        return key_pockets(Image.open(os.path.join(ART, "out", "pieces", name + ".png")).convert("RGBA"))
    return key_pockets(Image.open(os.path.join(ART, "out", group, "png128", name + ".png")).convert("RGBA"))


# A pixel this magenta (min(R, B) - G) is the sheets' key colour, never art: the most purple art in the set reaches
# 0.42 (pin_portal), a leftover of the key 1.0 (measured 2026-10-19).
POCKET = 0.6
KEY_LEVEL = 0.85   # the key's own magenta-ness, as the cutter's level: from here on fully keyed


def key_pockets(img):
    """the cutter keeps an icon's inside solid from the sheet (so a purple icon stays purple), so a hole in the art the
    sheet's magenta showed through -- the hourglass's glass, the user 2026-10-19: 'magenta leftovers' -- came out
    opaque magenta. Each such pocket and its soft rim (2 px round it) keyed out as the cutter keys the outside: alpha
    from the magenta share, the colour unmixed from the key, the cast left on the rim taken out."""
    a = np.asarray(img).astype(np.float32) / 255.0
    mag = np.minimum(a[..., 0], a[..., 2]) - a[..., 1]
    seed = (mag > POCKET) & (a[..., 3] > 0)
    if not seed.any():
        return img
    near = np.asarray(Image.fromarray((seed * 255).astype(np.uint8), "L").filter(ImageFilter.MaxFilter(5))) > 0
    keep = 1.0 - np.clip(mag / KEY_LEVEL, 0, 1)
    k = np.array([1.0, 0.0, 1.0], dtype=np.float32)
    col = np.clip((a[..., :3] - (1 - keep)[..., None] * k) / np.maximum(keep, 1e-3)[..., None], 0, 1)
    spill = np.clip(np.minimum(col[..., 0], col[..., 2]) - col[..., 1], 0, None)
    col[..., 0] -= spill
    col[..., 2] -= spill
    out = a.copy()
    out[near, :3] = col[near]
    out[near, 3] = a[near, 3] * keep[near]
    out[out[..., 3] <= 0, :3] = 0
    return Image.fromarray((out * 255 + 0.5).astype(np.uint8), "RGBA")


def scaled(img, size):
    w, h = (size, size) if isinstance(size, int) else size
    if img.size == (w, h):
        return img
    if not isinstance(size, int):
        # an oblong one: the picture cropped to its shape, laid on the middle of the frame at its own aspect
        a = np.asarray(img)[..., 3]
        ys, xs = np.nonzero(a > 4)
        img = img.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
        k = min((w - 2) / img.width, (h - 2) / img.height)
        inner = img.convert("RGBa").resize((max(1, round(img.width * k)), max(1, round(img.height * k))), Image.LANCZOS)
        out = Image.new("RGBa", (w, h), (0, 0, 0, 0))
        out.paste(inner, ((w - inner.width) // 2, (h - inner.height) // 2))
        return out.convert("RGBA")
    return img.convert("RGBa").resize((w, h), Image.LANCZOS).convert("RGBA")


# the class discs: drawn 4 times over and scaled down; the outline the set's pins' (its share of the radius and its
# dark brown, measured on the sheet), the fill the sheet's disc colour lit from the top left as the pins are, a soft
# highlight there
CLASS_SS, CLASS_LINE, CLASS_INK = 4, 0.1, (27, 15, 10)


def class_colour(name):
    # the disc's own colour on the sheet: the band between its emblem and its outline, the median
    a = np.asarray(load("classes", "class_" + name)).astype(np.float64)
    n = a.shape[0]
    c = (n - 1) / 2
    yy, xx = np.mgrid[0:n, 0:n]
    d = np.hypot(xx - c, yy - c) / (n / 2)
    band = (d > 0.80) & (d < 0.86) & (a[..., 3] > 250)
    return np.median(a[band][:, :3], axis=0)


def class_disc(name, size=64):
    col = class_colour(name)
    n = size * CLASS_SS
    c = (n - 1) / 2
    r = n / 2 - CLASS_SS
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float64)
    dx, dy = (xx - c) / r, (yy - c) / r
    d = np.hypot(dx, dy)
    alpha = np.clip((1 - d) * r + 0.5, 0, 1)
    # cel shaded as the pins: the colour flat, its top left a tone lighter and its bottom right a tone darker (soft
    # steps, no gloss), a thin lighter crescent just inside the top left of the rim
    lit = 1 + 0.08 * np.tanh(-(dx + dy) * 2.5)
    crescent = ((d < 1 - CLASS_LINE * 1.6) & (np.hypot(dx - 0.09, dy - 0.09) > 0.86)).astype(np.float64) * 0.18
    fill = np.clip(col[None, None, :] * lit[..., None] + (255 - col[None, None, :]) * crescent[..., None], 0, 255)
    ink = np.array(CLASS_INK, np.float64)
    line = np.clip((d - (1 - CLASS_LINE)) * r + 0.5, 0, 1)[..., None]
    rgb = fill * (1 - line) + ink * line
    img = Image.fromarray(np.dstack([rgb, alpha * 255]).round().astype(np.uint8), "RGBA")
    return img.convert("RGBa").resize((size, size), Image.LANCZOS).convert("RGBA")


def halo(name, img):
    grow, blur, gain = HALO_GLOW if name.startswith(HALO_DISCS) else HALO_SHADE
    w = HALO_WORK
    n = round(w * (1 + 2 * HALO_PAD))
    a = scaled(img, w).getchannel("A")
    canvas = Image.new("L", (n, n), 0)
    canvas.paste(a, ((n - w) // 2, (n - w) // 2))
    k = 2 * round(grow * w) + 1
    if k > 1:
        canvas = canvas.filter(ImageFilter.MaxFilter(k))
    canvas = canvas.filter(ImageFilter.GaussianBlur(blur * w))
    alpha = np.clip(np.asarray(canvas).astype(np.float64) / 255 * gain, 0, 1)
    rgba = np.dstack([np.full((n, n, 3), 255.0), alpha * 255]).round().astype(np.uint8)
    return Image.fromarray(rgba, "RGBA").convert("RGBa").resize((HALO_SIZE, HALO_SIZE), Image.LANCZOS).convert("RGBA")


def halos():
    out = [(name, halo(name, load(group, art))) for group, art, name, _ in SET if group in HALO_GROUPS]
    out += [("class_" + name, halo("class_" + name, class_disc(name, HALO_WORK))) for name in CLASSES]
    return out


def disc(size, inner=None, edge=1.0):
    # a white disc (or ring from `inner` out), its edge one texel soft
    n = size
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float64)
    d = np.hypot(xx - (n - 1) / 2, yy - (n - 1) / 2)
    r = n / 2 - 1
    a = np.clip(r - d + 0.5, 0, 1)
    if inner is not None:
        a *= np.clip(d - inner + 0.5, 0, 1)
    img = np.zeros((n, n, 4), np.uint8)
    img[..., :3] = 255
    img[..., 3] = (a * 255 + 0.5).astype(np.uint8)
    return Image.fromarray(img, "RGBA")


# (2026-10-20) the configurator's stretchable pieces (Batches 18 and 20, icons_v2/work/cut_pieces.py): each scaled to a
# power-of-two width at its own aspect and laid at the top left of a power-of-two canvas -- its picture's height
# there is round(height * width / its width); Core/Widgets.lua's MODERN table holds those heights and the ends' widths
PIECES = [("div_diamond", 512, 32), ("dd_closed", 512, 64), ("dd_hover", 512, 64), ("dd_open", 512, 64),
          ("dd_panel", 256, 256), ("dd_row", 256, 64), ("tab_off", 256, 128), ("tab_hover", 256, 128),
          ("tab_on", 256, 128), ("pill_off", 256, 64), ("pill_on", 256, 64),
          # (Batch 24) the experience and reputation bars' frame, track and notch (Modules/ActionBars.lua)
          ("bar_frame", 512, 64), ("bar_track", 512, 32), ("bar_notch", 16, 64)]


def piece(name, width, canvas_h):
    mirror = name.endswith("_r")
    img = Image.open(os.path.join(ART, "out", "pieces", (name[:-2] if mirror else name) + ".png")).convert("RGBA")
    if mirror:
        img = img.transpose(Image.FLIP_LEFT_RIGHT)
    h = max(1, round(img.height * width / img.width))
    inner = img.convert("RGBa").resize((width, h), Image.LANCZOS)
    out = Image.new("RGBa", (width, canvas_h), (0, 0, 0, 0))
    out.paste(inner, (0, 0))
    return out.convert("RGBA"), h


# (2026-10-20) the modern look's light flipbooks (icons_v2/work/cut_fx.py, out/fx/fb_<name>_strip.png: 8 frames in a
# row, light as alpha): each scaled to FB_FRAME a frame, one strip 8 * FB_FRAME wide
FLIPBOOKS = ["questdone", "cooldown"]
FB_FRAME = 64
# (the cooldown ready flash, Modules/ActionButtons.lua: the user, 2026-10-20, "this animation can be reused on the
# Action bars to notify when something comes off cooldown") its frames re-centred on their own square -- the sheet's
# drifts, the last four 55 texels higher -- each square FB_SQUARE of its frame (the button's edge in the game)
FB_SQUARED = ("cooldown",)
FB_SQUARE = 0.8


def square_of(frame):
    # the rounded square's sides: the outermost columns and rows its long lines run along (lit over a third of the
    # way: a glint lights a short stretch) -- read on the first frame, whole and evenly lit
    a = np.asarray(frame)[..., 3] > 40
    cols, rows = a.sum(0), a.sum(1)
    long_c = np.nonzero(cols > len(rows) / 3)[0]
    long_r = np.nonzero(rows > len(cols) / 3)[0]
    l, r, t, b = long_c.min(), long_c.max(), long_r.min(), long_r.max()
    return (l + r) / 2, (t + b) / 2, r - l, b - t


def shift_to(frame, ref):
    # where `frame`'s light lies against `ref`'s: the shift (dx, dy) that lays it best on it (a cross-correlation of
    # their alpha; the later frames' top line is faint, a glint sits on one side: neither moves this)
    a = np.asarray(frame)[..., 3].astype(np.float64)
    b = np.asarray(ref)[..., 3].astype(np.float64)
    c = np.real(np.fft.ifft2(np.fft.fft2(b) * np.conj(np.fft.fft2(a))))
    dy, dx = np.unravel_index(int(np.argmax(c)), c.shape)
    n = a.shape[0]
    return (dx if dx <= n // 2 else dx - n), (dy if dy <= n // 2 else dy - n)


def flipbook(name):
    img = Image.open(os.path.join(ART, "out", "fx", "fb_%s_strip.png" % name)).convert("RGBa")
    if name not in FB_SQUARED:
        return img.resize((8 * FB_FRAME, FB_FRAME), Image.LANCZOS).convert("RGBA")
    cell = img.height
    out = Image.new("RGBa", (8 * FB_FRAME, FB_FRAME), (0, 0, 0, 0))
    first = img.crop((0, 0, cell, cell))
    cx, cy, w, h = square_of(first.convert("RGBA"))
    half = max(w, h) / FB_SQUARE / 2   # (the first frame's square to FB_SQUARE of the frame)
    for i in range(8):
        frame = img.crop((i * cell, 0, (i + 1) * cell, cell))
        dx, dy = shift_to(frame.convert("RGBA"), first.convert("RGBA")) if i else (0, 0)
        box = (cx - dx - half, cy - dy - half, cx - dx + half, cy - dy + half)
        out.paste(frame.transform((FB_FRAME, FB_FRAME), Image.EXTENT, box, Image.BICUBIC), (i * FB_FRAME, 0))
    return out.convert("RGBA")


# (2026-10-20) the modern look's light effects (the user, 2026-10-20: "more fitting to the Default Modernized look"):
# Core/FrameFX.lua reads Media/FrameFX/Light/<name> for the names here while Oldschool's painted look is off (the
# kit's area "effects"), Media/FrameFX/<name> (Tools/heal_flight_art.py) otherwise and for every name not here (the
# glows, pillars, fire lines and the rune are the same in both). Each from icons_v2/out/fx (work/cut_fx.py: light as
# alpha, its colour unmixed) at its old file's place: its shape cut out, laid on the middle of the canvas; a colour
# the sheets have no sprite in is the nearest sprite turned to its hue. Written to the addon only, as
# heal_flight_art.py's are (no master: texture_pack.py leaves Media/FrameFX as it is)
FX_OUT = ("FrameFX", "Light")
# the sheets' own colours (the prompts'): hue in degrees, None keeps it; then the saturation's share
TINT = {"gold": (44, 1.0), "blue": (211, 0.8), "green": (138, 1.0), "red": (4, 1.0), "white": (None, 0.08)}
# (name, art, canvas, colour or None, how): "fit" its shape on the middle, "fill" stretched over the canvas, "level"
# turned level first, "upright" its biggest piece alone, turned upright, "box" the cooldown flipbook's first frame
# (a rounded square of light) stretched to the canvas by its corners (the shield over a frame's oblong)
FX_LIGHT = [("plus_green", "heal_cross", 64, None, "fit"), ("plus_gold", "heal_cross", 64, "gold", "fit"),
            ("plus_blue", "heal_cross", 64, "blue", "fit"),
            ("leaf", "heal_leaf", 64, None, "level"), ("drop", "heal_drop", 64, "blue", "fit"),
            ("spark_gold", "holy_spark", 64, None, "fit"), ("rays_gold", "heal_rays", 256, None, "fit"),
            # (1.2.0, the swing badge's sun rays from its icon's middle: drawn at about 30-120 px, so a copy at 128,
            # about a texel a pixel -- the 256's thin rays shimmered small; the user: "sun rays sparking")
            ("rays_gold_small", "heal_rays", 128, None, "fit"),
            ("ring_gold", "cooldown_ring", 128, None, "fit"), ("ring_fire", "roar_ring", 128, None, "fit"),
            ("wave_red", "taunt_ring", 128, None, "fit"), ("wave_teal", "heal_wave", 128, None, "fit"),
            ("wave_gold", "heal_wave", 128, "gold", "fit"), ("ripple_blue", "heal_wave", 128, "blue", "fit"),
            ("halo_white", "heal_wave", 128, "white", "fit"),
            ("bubble_round", "shield_bubble", 128, None, "fit"),
            ("bubble_gold_round", "shield_bubble", 128, "gold", "fit"),
            ("bubble", "fb_cooldown_strip", (256, 128), "blue", "box"),
            ("bubble_gold", "fb_cooldown_strip", (256, 128), None, "box"),
            ("crest_gold", "prot_crest", 128, None, "fit"), ("crest_steel", "fortify_crest", 128, None, "fit"),
            ("crest_blue", "prot_crest", 128, "blue", "fit"), ("crest_green", "prot_crest", 128, "green", "fit"),
            ("sheen", "sheen", (64, 128), None, "fill"), ("shard_blue", "shield_shards", 64, None, "upright")]
FX_LIGHT += [("streak_" + c, "sheen", (256, 64), c, "level") for c in ("white", "gold", "green", "blue", "red")]
FX_MARGIN = 0.04   # of the canvas, round a fitted shape
FX_SHAPE = 40      # the alpha a shape's own extent is read at (its faint glow round it left out of the middle)
SHARD_CORE = 150   # the alpha the shards are told apart at (their glows touch below it)
BOX_RIM, BOX_GLOW, BOX_FILL = 2.4, (4, 0.7), 16   # the oblong shield: its rim's gain, glow (blur, share), fill


def fx_tint(img, colour):
    if not colour:
        return img
    hue, sat = TINT[colour]
    a = img.getchannel("A")
    h, s, v = img.convert("RGB").convert("HSV").split()
    if hue is not None:
        h = Image.new("L", img.size, round(hue / 360 * 255))
    s = s.point(lambda x: round(x * sat))
    out = Image.merge("HSV", (h, s, v)).convert("RGB")
    out.putalpha(a)
    return out


def fx_turn(img, upright):
    # turned so its long axis (the light's own, weighted by alpha) lies level, or stands upright
    a = np.asarray(img)[..., 3].astype(np.float64)
    ys, xs = np.nonzero(a > FX_SHAPE)
    w = a[ys, xs]
    mx, my = np.average(xs, weights=w), np.average(ys, weights=w)
    cov = np.cov(np.vstack([xs - mx, ys - my]), aweights=w)
    vals, vecs = np.linalg.eigh(cov)
    vx, vy = vecs[:, np.argmax(vals)]
    deg = np.degrees(np.arctan2(vy, vx)) + (90 if upright else 0)   # (the axis's angle, the image's y down)
    return img.convert("RGBa").rotate(deg, Image.BICUBIC, expand=True).convert("RGBA")


def fx_biggest(img):
    # the biggest piece alone (the shards fly apart: one of them), its own glow kept
    from scipy import ndimage
    arr = np.asarray(img).copy()
    lab, n = ndimage.label(arr[..., 3] > SHARD_CORE)
    sizes = ndimage.sum(np.ones_like(lab), lab, range(1, n + 1))
    keep = ndimage.binary_dilation(lab == 1 + int(np.argmax(sizes)), iterations=8)
    arr[..., 3] = np.where(keep, arr[..., 3], 0)
    return Image.fromarray(arr, "RGBA")


def fx_crop(img, level=FX_SHAPE):
    a = np.asarray(img)[..., 3]
    ys, xs = np.nonzero(a > level)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def fx_fit(img, size):
    # its shape on the middle of the canvas, a margin round it (the faint glow beyond the shape kept as far as it fits)
    w, h = (size, size) if isinstance(size, int) else size
    l, t, r, b = fx_crop(img)
    cx, cy, half_w, half_h = (l + r) / 2, (t + b) / 2, (r - l) / 2, (b - t) / 2
    k = min(w * (0.5 - FX_MARGIN) / half_w, h * (0.5 - FX_MARGIN) / half_h)
    span_w, span_h = w / 2 / k, h / 2 / k
    box = (round(cx - span_w), round(cy - span_h), round(cx + span_w), round(cy + span_h))
    return img.convert("RGBa").crop(box).resize((w, h), Image.LANCZOS).convert("RGBA")


def fx_box(img, size):
    # the cooldown flipbook's first frame (its rounded square whole, evenly lit), cut by its corners and stretched
    # over the oblong: the corners at their own shape, the sides drawn out, the middle left empty
    w, h = size
    frame = img.crop((0, 0, img.height, img.height))
    l, t, r, b = fx_crop(frame, 24)
    pad = round((r - l) * 0.03)
    frame = frame.crop((l - pad, t - pad, r + pad, b + pad)).convert("RGBa")
    side = frame.width
    m = round(side * 0.24)                          # the corner: its round and its glow
    mo = max(2, round(m * (h * 0.5) / side * 1.6))  # drawn at the scale of the square laid at half the canvas's height
    xs_src, xs_dst = (0, m, side - m, side), (0, mo, w - mo, w)
    ys_src, ys_dst = (0, m, side - m, side), (0, mo, h - mo, h)
    out = Image.new("RGBa", (w, h), (0, 0, 0, 0))
    for i in range(3):
        for j in range(3):
            src = frame.crop((xs_src[i], ys_src[j], xs_src[i + 1], ys_src[j + 1]))
            out.paste(src.resize((xs_dst[i + 1] - xs_dst[i], ys_dst[j + 1] - ys_dst[j]), Image.LANCZOS),
                      (xs_dst[i], ys_dst[j]))
    # brighter (the first frame is the flipbook's dimmest; the shield is held at full), a soft glow either side of
    # the rim and the faintest light inside it (a barrier seen through, as the old one's)
    out = out.convert("RGBA")
    arr = np.asarray(out).astype(np.float64)
    rim = np.clip(arr[..., 3] * BOX_RIM, 0, 255)
    glow = np.asarray(Image.fromarray(rim.astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(BOX_GLOW[0])),
                      np.float64) * BOX_GLOW[1]
    inside = np.zeros((h, w))
    inside[mo // 2:h - mo // 2, mo // 2:w - mo // 2] = BOX_FILL
    lit = arr[..., 3] > 60
    colour = np.median(arr[..., :3][lit], axis=0)
    a = np.maximum(np.maximum(rim, glow), inside)
    rgb = np.where((arr[..., 3] > 8)[..., None], arr[..., :3], colour)   # (the glow and the fill in the rim's colour)
    return Image.fromarray(np.dstack([rgb, a]).round().astype(np.uint8), "RGBA")


def fx_light(name, art, size, colour, how):
    img = Image.open(os.path.join(ART, "out", "fx", art + ".png")).convert("RGBA")
    if how == "box":
        return fx_tint(fx_box(img, size), colour)
    if how == "upright":
        img = fx_turn(fx_biggest(img), True)
    elif how == "level":
        img = fx_turn(img, False)
    if how == "fill":
        l, t, r, b = fx_crop(img, 8)
        img = img.convert("RGBa").crop((l, t, r, b)).resize(size, Image.LANCZOS).convert("RGBA")
    else:
        img = fx_fit(img, size)
    return fx_tint(img, colour)


# (2026-10-20, the user: "look at how the original unitframe looks like, take the new art, recreate it exactly how it
# looks like just with the new borders, make it a single texture and apply it") the unit frames' art, one picture
# each, laid exactly where the game's own frame picture is (Modules/UnitFrames.lua, MelloUI Frames). Drawn on the
# game's own layout -- client 70425's c60 2x art, measured once on it (none of its pixels used): the portrait ring's
# centre and opening, each slot's inside (name, health, mana, the class resource) between the borders, the borders'
# width -- with Batch 25's pieces: the health frame's gold band round every slot (the power frame's silver round the
# power ones), the name plate's slate in the name slot, a darker slate in the bars' (a little see-through, as the
# game's), the portrait ring over them all, its opening cut clear (the portrait shows through it).
#   canvas, the picture (w, h) at its top left, the ring (centre x, y, opening radius), the band, each band's top
#   (the slots between: name, health, mana, the class resource), and across: under the ring (where the borders
#   start), the slots' inside edge by the ring (the game's: each slot and its bar start there -- the user's
#   screenshot of 2026-10-20, a dark piece of slot between the ring and the party's health bar) and the far edge.
#   Between the ring and the slots the frame's top and foot borders run on under the ring, a dark iron between them
UF_FRAMES = {
    # (the player: UI-HUD-UnitFrame-Player-PortraitOn-c60-2x, 396 x 142; with the class resource bar 396 x 148)
    "uf_frame_player": ((512, 256), (396, 142), (73, 71, 52), 7, (22, 58, 90, 113), (100, 144, 391)),
    "uf_frame_player_res": ((512, 256), (396, 148), (73, 71, 52), 6, (23, 58, 90, 112, 134), (100, 144, 391)),
    # (the target's and focus's, its minus mob's the same: Target-PortraitOn-c60-2x, 388 x 136, the ring at the right)
    "uf_frame_target": ((512, 256), (388, 136), (318.5, 67.5, 49.5), 6, (17, 52, 84, 106), (290, 249, 3)),
    # (the target of target's -- TargetofTarget-PortraitOn-c60-2x -- and the party's, the same shape:
    # CharacterFrameOnParty-PortraitOn-c60-2x, 240 x 98)
    "uf_frame_small": ((256, 128), (240, 98), (45, 45.5, 33), 6, (6, 32, 55, 71), (55, 92, 234)),
}
UF_KINDS = ("name", "health", "power", "power")   # the slots from the top: their pieces
UF_FILL_A = (0.92, 0.85, 0.85, 0.85)               # each slot's inside: its slate's alpha
UF_BAND_M = 22                                     # a piece's band on its file, from its edge (cut to its picture)
UF_IRON = (19, 22, 25)                             # the dark iron between the ring and the slots (the bands' own)


def uf_piece(name):
    img = load("pieces", name)
    return img.crop(img.getbbox())


def uf_slot(piece, w, h, b):
    # the piece's band round a w x h box, b texels wide, hollow: its straight left end at both ends (mirrored at the
    # right), its straight middle drawn out along the sides
    pw, ph = piece.size
    m = UF_BAND_M
    src = piece.convert("RGBa")
    mid = (pw // 4, pw * 3 // 4)
    parts = {"tl": src.crop((0, 0, m, m)), "bl": src.crop((0, ph - m, m, ph)),
             "t": src.crop((mid[0], 0, mid[1], m)), "b": src.crop((mid[0], ph - m, mid[1], ph)),
             "l": src.crop((0, m, m, ph - m))}
    flip = Image.FLIP_LEFT_RIGHT
    out = Image.new("RGBa", (w, h), (0, 0, 0, 0))
    for key, box in (("t", (b, 0, w - b, b)), ("b", (b, h - b, w - b, h)), ("l", (0, b, b, h - b)),
                     ("r", (w - b, b, w, h - b)), ("tl", (0, 0, b, b)), ("tr", (w - b, 0, w, b)),
                     ("bl", (0, h - b, b, h)), ("br", (w - b, h - b, w, h))):
        src_key = {"r": "l", "tr": "tl", "br": "bl"}.get(key, key)
        img = parts[src_key]
        if key in ("r", "tr", "br"):
            img = img.transpose(flip)
        out.paste(img.resize((box[2] - box[0], box[3] - box[1]), Image.LANCZOS), box[:2])
    return out.convert("RGBA")


def uf_fill(plate, w, h, alpha, dark):
    # the name plate's slate down a slot's inside (its own light top and darker foot), or a darker one for the bars
    pw, ph = plate.size
    col = np.asarray(plate.convert("RGB"), np.float64)[UF_BAND_M:ph - UF_BAND_M, pw // 2]
    ys = np.linspace(0, len(col) - 1, h)
    shade = np.stack([np.interp(ys, np.arange(len(col)), col[:, c]) for c in range(3)], 1) * (0.55 if dark else 1)
    arr = np.zeros((h, w, 4))
    arr[..., :3] = shade[:, None, :]
    arr[..., 3] = alpha * 255
    return Image.fromarray(arr.round().astype(np.uint8), "RGBA")


def uf_rail(piece, w, b, foot):
    # a piece's straight top (or foot) band drawn out to w, b high: a border running on under the ring
    pw, ph = piece.size
    m = UF_BAND_M
    box = (pw // 4, ph - m, pw * 3 // 4, ph) if foot else (pw // 4, 0, pw * 3 // 4, m)
    return piece.convert("RGBa").crop(box).resize((w, b), Image.LANCZOS).convert("RGBA")


def uf_frame(name):
    canvas, (w, h), (cx, cy, r_open), b, lines, (under, inner, far) = UF_FRAMES[name]
    plate, gold, silver = uf_piece("uf_plate"), uf_piece("uf_health"), uf_piece("uf_power")
    art = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    # the slots from their inside edge by the ring (less the band) to the far edge; the borders from under the ring
    if far > inner:
        x0, x1, r0, r1, i0, i1 = inner - b, far, under, far, under, inner - b
    else:
        x0, x1, r0, r1, i0, i1 = far, inner + b, far, under, inner + b, under
    top, foot = lines[0], lines[-1] + b
    art.paste(Image.new("RGBA", (i1 - i0, foot - top), UF_IRON + (255,)), (i0, top))
    last = silver if UF_KINDS[len(lines) - 2] == "power" else gold
    art.alpha_composite(uf_rail(gold, r1 - r0, b, False), (r0, top))
    art.alpha_composite(uf_rail(last, r1 - r0, b, True), (r0, foot - b))
    for i in range(len(lines) - 1):
        top, foot = lines[i], lines[i + 1] + b
        kind = UF_KINDS[i]
        art.alpha_composite(uf_fill(plate, x1 - x0 - 2 * b, foot - top - 2 * b, UF_FILL_A[i], kind != "name"),
                            (x0 + b, top + b))
        art.alpha_composite(uf_slot(silver if kind == "power" else gold, x1 - x0, foot - top, b), (x0, top))
    # the ring over them, its opening the game's (the art's opening measured on it), then that opening cut clear
    ring = uf_piece("uf_ring")
    a = np.asarray(ring)[..., 3]
    row = a[a.shape[0] // 2]
    lit = np.nonzero(row > 128)[0]
    gaps = [x for x in range(lit.min(), lit.max()) if row[x] <= 128]
    k = r_open / ((gaps[-1] - gaps[0] + 1) / 2)
    size = (round(ring.width * k), round(ring.height * k))
    ring = ring.convert("RGBa").resize(size, Image.LANCZOS).convert("RGBA")
    art.alpha_composite(ring, (round(cx - size[0] / 2), round(cy - size[1] / 2)))
    arr = np.asarray(art).astype(np.float64)
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.hypot(xx + 0.5 - cx, yy + 0.5 - cy)
    arr[..., 3] *= np.clip(d - (r_open - 1.5), 0, 1)
    out = Image.new("RGBA", canvas, (0, 0, 0, 0))
    out.paste(Image.fromarray(arr.round().astype(np.uint8), "RGBA"), (0, 0))
    return out


# (Batch 29, icons_v2/work/cut_dragons.py) the target's elite, boss and rare dragons: each on a square canvas, the
# portrait's circle (the sheet's guide) its middle, that circle UF_DRAGON_R texels round -- the target ring's outer
# band, so the dragon lies over the ring's rim as the game's does (Modules/UnitFrames.lua lays it on the ring's centre)
UF_DRAGONS = ("elite", "boss", "rare")
UF_DRAGON_CANVAS, UF_DRAGON_R = 256, 60


def uf_dragon(name):
    with open(os.path.join(ART, "out", "pieces", "uf_dragon.json")) as f:
        r = json.load(f)[name]["radius"]
    img = load("pieces", "uf_dragon_" + name)
    side = round(img.width * UF_DRAGON_R / r)
    img = img.convert("RGBa").resize((side, side), Image.LANCZOS)
    out = Image.new("RGBa", (UF_DRAGON_CANVAS, UF_DRAGON_CANVAS), (0, 0, 0, 0))
    out.paste(img, ((UF_DRAGON_CANVAS - side) // 2, (UF_DRAGON_CANVAS - side) // 2))
    return out.convert("RGBA")


def files():
    out = []
    for name in sorted(UF_FRAMES):
        out.append((name, uf_frame(name)))
    for name in UF_DRAGONS:
        out.append(("uf_boss_" + name, uf_dragon(name)))
    for name in CLASSES:
        out.append(("class_" + name, class_disc(name)))
    for name in FLIPBOOKS:
        out.append(("fx_" + name, flipbook(name)))
    for name, width, canvas_h in PIECES:
        out.append(("piece_" + name, piece(name, width, canvas_h)[0]))
    for group, art, name, size in SET:
        img = load(group, art)
        if name == "edge_arrow":
            img = img.rotate(180)   # (the minimap's edge chevron points down, Route.lua turns it)
        out.append((name, scaled(img, size)))
    out.append(("ring_gold", scaled(load("ring", "ring_gold_256"), 128)))
    out.append(("hover_glow", scaled(load("ring", "hover_glow_256"), 128)))
    # the count badge: a disc and its edge, white (Look.Count paints them innerPanel and trim)
    out.append(("badge_disc", disc(64)))
    out.append(("badge_edge", disc(64, inner=64 / 2 - 1 - 64 * 0.075)))
    return out


def tga(img):
    buf = io.BytesIO()
    img.save(buf, format="TGA")
    return buf.getvalue()


def main():
    bad = [a for a in sys.argv[1:] if a != "--check"]
    if bad:
        print("unknown argument: %s (nothing written)\n" % " ".join(bad))
        print(__doc__[__doc__.index("    python Tools/"):].rstrip())
        return 2
    check = "--check" in sys.argv
    stale = []
    sums = hashlib.sha256()
    icons = files()
    every = [(name, img, (master(*OUT, name + ".tga"), os.path.join(ADDON_MEDIA, *OUT, name + ".tga")))
             for name, img in icons]
    every += [(e[0], fx_light(*e), (os.path.join(ADDON_MEDIA, *FX_OUT, e[0] + ".tga"),)) for e in FX_LIGHT]
    lifts = halos()
    every += [(name, img, (os.path.join(ADDON_MEDIA, *HALO_OUT, name + ".tga"),)) for name, img in lifts]
    for name, img, paths in every:
        data = tga(img)
        if paths[0].startswith(master()):
            sums.update(name.encode() + data)   # (the icon set's sum: the light effects not in it)
        for path in paths:
            if check:
                try:
                    with open(path, "rb") as f:
                        if f.read() != data:
                            stale.append(path)
                except OSError:
                    stale.append(path)
                continue
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as f:
                f.write(data)
    if check:
        for path in stale:
            print("stale:", os.path.normpath(path))
        print("ok" if not stale else "STALE")
        return 1 if stale else 0
    print("%d icons written (masters + Media/Textures/Icons), set sha256 %s; %d light effects (Media/FrameFX/Light); "
          "%d lifts (Media/Textures/Icons/Halo)" % (len(icons), sums.hexdigest()[:16], len(FX_LIGHT), len(lifts)))
    return 0


if __name__ == "__main__":
    sys.exit(main())

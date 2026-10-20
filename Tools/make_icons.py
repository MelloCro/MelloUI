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
Media/FrameFX/Light/, the addon's only.

    python Tools/make_icons.py            write them
    python Tools/make_icons.py --check    exit 1 unless all are up to date
"""
import hashlib
import io
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
          "svc_classtrainer", "svc_proftrainer", "svc_barber", "svc_vendor"):
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
# (Batch 25) the unit frames' portrait ring, level badge and the elite and rare wings
SET += [("pieces", "uf_ring", "uf_ring", 128), ("pieces", "uf_badge", "uf_badge", 64),
        ("pieces", "uf_elite", "uf_elite", (128, 116)), ("pieces", "uf_rare", "uf_rare", (128, 116))]


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
          ("bar_frame", 512, 64), ("bar_track", 512, 32), ("bar_notch", 16, 64),
          # (Batch 25) the unit frames' name plate and bar frames (Modules/UnitFrames.lua), each also mirrored ("_r":
          # the target's and focus's, their portrait at the right)
          ("uf_plate", 512, 64), ("uf_health", 512, 64), ("uf_power", 512, 32),
          ("uf_plate_r", 512, 64), ("uf_health_r", 512, 64), ("uf_power_r", 512, 32)]


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
FLIPBOOKS = ["questdone"]
FB_FRAME = 64


def flipbook(name):
    img = Image.open(os.path.join(ART, "out", "fx", "fb_%s_strip.png" % name)).convert("RGBa")
    return img.resize((8 * FB_FRAME, FB_FRAME), Image.LANCZOS).convert("RGBA")


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


def files():
    out = []
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
    print("%d icons written (masters + Media/Textures/Icons), set sha256 %s; %d light effects (Media/FrameFX/Light)"
          % (len(icons), sums.hexdigest()[:16], len(FX_LIGHT)))
    return 0


if __name__ == "__main__":
    sys.exit(main())

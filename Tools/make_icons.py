"""
Build the game textures of MelloUI's own icon set (0.25.0; the user, 2026-10-19: the cartoon WoW map-marker icons
cut from their ChatGPT sheets, docs/plans/icons-and-palette.md): every icon as a 32-bit TGA at a power-of-two size,
its master under MelloUI-BuildData/masters/Media/Textures/Icons/ (Tools/paths.py) and a byte copy in the addon's
Media/Textures/Icons/ so it ships at once; texture_pack.py ship keeps them as their masters' bytes (STAY_TGA: their
soft alpha edges band as DXT).

The art: MelloUI-BuildData/masters/icons_v2/out/<group>/png128/<name>.png (cut by icons_v1/cut_sheet.py and
cut_buttons.py from icons_v2/src/sheet*.png), ring/ring_gold_256.png and ring/hover_glow_256.png. Drawn here: the
count badge's disc and its edge (white, the palette tints them). Each picture is scaled premultiplied (no dark fringe).
Deterministic: the same art gives the same bytes.

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
          ("tab_on", 256, 128), ("pill_off", 256, 64), ("pill_on", 256, 64)]


def piece(name, width, canvas_h):
    img = Image.open(os.path.join(ART, "out", "pieces", name + ".png")).convert("RGBA")
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
    for name, img in files():
        data = tga(img)
        sums.update(name.encode() + data)
        for path in (master(*OUT, name + ".tga"), os.path.join(ADDON_MEDIA, *OUT, name + ".tga")):
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
    print("%d icons written (masters + Media/Textures/Icons), set sha256 %s" % (len(files()), sums.hexdigest()[:16]))
    return 0


if __name__ == "__main__":
    sys.exit(main())

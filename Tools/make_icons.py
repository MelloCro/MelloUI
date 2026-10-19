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
from PIL import Image
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


def load(group, name):
    if group == "ring":
        return Image.open(os.path.join(ART, "ring", name + ".png")).convert("RGBA")
    return Image.open(os.path.join(ART, "out", group, "png128", name + ".png")).convert("RGBA")


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


def files():
    out = []
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

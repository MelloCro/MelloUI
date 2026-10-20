"""MelloUI's new logo and banner (the user, 2026-10-20: Downloads/newIcons "Glossy Gold Navigation Badge.png" and
"MelloUI Fantasy Map Interface.png", kept as MelloUI-BuildData/sources/logo/badge.png and banner.png; "you can add a
mask soft fade on the edges of the banner"). A build tool (Tools/ never ships); then python Tools/texture_pack.py ship.

  LogoIcon.tga     256 x 256: the badge's inner disc (inside its gold ring), as the old one was cut ("round_inner"):
                   MelloUI's rims frame it (the configurator's crest, the title strip, the TOC's addon-list icon)
  LogoFull.tga     256 x 256: the whole badge with its ring (the configurator home page's header box)
  InstallerBanner  1024 x 512 file, the banner drawn 1024 x 341 at its top: its edges faded to nothing (a soft mask
                   baked into the alpha: smoothstep ramps, 4 % of the width at the sides, 16 % of the height at the
                   top and bottom, multiplied, so the corners fade most)
  docs/logo.png       the banner as given (README, CurseForge description)
  docs/logo-icon.png  512 x 512: the whole badge (Discord's server icon, CurseForge's project picture)
Every texture's colour is bled outward under its transparent texels (the client filters straight alpha: black under
alpha 0 draws a dark fringe), written as 32-bit TGA masters into MelloUI-BuildData/masters/Media/Textures; the old
masters kept beside them in BuildData/backup/logo-2026-10-20.

    python Tools/make_logo.py [--write] [--brand]   (without --write: only MelloUI-BuildData/output/logo;
                                                     --brand: docs/brand, the places outside the game)
"""
import os
import shutil
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import paths as P  # noqa: E402  (Tools/paths.py: where the build data lives)

BUILD = os.environ.get("MELLOUI_BUILD_DATA", "").strip() or P.SIBLING
SRC = os.path.join(BUILD, "sources", "logo")   # the user's art as given (Downloads/newIcons, 2026-10-20)
BADGE = os.path.join(SRC, "badge.png")
BANNER = os.path.join(SRC, "banner.png")
MASTERS = os.path.join(BUILD, "masters", "Media", "Textures")
BACKUP = os.path.join(BUILD, "backup", "logo-2026-10-20")
REPO = os.path.dirname(HERE)
OUT = os.path.join(BUILD, "output", "logo")
INNER_R = 500.0          # the badge's dark disc, inside the gold ring (measured: the ring's outline from 504)
BANNER_DRAWN = (1024, 341)
FADE_X, FADE_Y = 0.04, 0.16


def bleed(rgba, steps=16):
    """colour spread outward under alpha 0 (each step: a transparent texel takes its opaque neighbours' mean)"""
    a = rgba[..., 3] > 0
    rgb = rgba[..., :3].astype(np.float64)
    have = a.copy()
    for _ in range(steps):
        acc = np.zeros_like(rgb)
        n = np.zeros(have.shape)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)):
            sh = np.roll(np.roll(have, dy, 0), dx, 1)
            acc += np.roll(np.roll(rgb, dy, 0), dx, 1) * sh[..., None]
            n += sh
        grow = (~have) & (n > 0)
        rgb[grow] = acc[grow] / n[grow][:, None]
        have |= grow
        if have.all():
            break
    out = rgba.copy()
    out[..., :3] = np.clip(np.round(rgb), 0, 255).astype(np.uint8)
    return out


def centre(img):
    a = np.asarray(img)[..., 3] > 128
    ys, xs = np.nonzero(a)
    return (xs.min() + xs.max()) / 2.0, (ys.min() + ys.max()) / 2.0, (xs.max() - xs.min()) / 2.0


def disc(img, cx, cy, r, size):
    """the square round (cx, cy) of half-side r, at size x size, its alpha cut to the circle (a 1.5 px soft edge)"""
    box = (cx - r, cy - r, cx + r, cy + r)
    sq = img.crop(tuple(int(round(v)) for v in box)).resize((size, size), Image.LANCZOS)
    arr = np.asarray(sq).copy()
    yy, xx = np.mgrid[0:size, 0:size]
    d = np.hypot(xx + 0.5 - size / 2, yy + 0.5 - size / 2)
    edge = np.clip((size / 2 - d) / 1.5, 0, 1)
    arr[..., 3] = np.round(arr[..., 3] * edge).astype(np.uint8)
    return arr


def smooth(t):
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


def banner_tex():
    src = Image.open(BANNER).convert("RGBA").resize(BANNER_DRAWN, Image.LANCZOS)
    arr = np.asarray(src).copy()
    h, w = arr.shape[:2]
    x = (np.arange(w) + 0.5) / w
    y = (np.arange(h) + 0.5) / h
    fx = smooth(np.minimum(x, 1 - x) / FADE_X)
    fy = smooth(np.minimum(y, 1 - y) / FADE_Y)
    arr[..., 3] = np.round(255 * fy[:, None] * fx[None, :]).astype(np.uint8)
    canvas = np.zeros((512, 1024, 4), np.uint8)
    canvas[:h, :w] = arr
    return bleed(canvas, 24)


BRAND = os.path.join(REPO, "docs", "brand")
# the places outside the game (the user, 2026-10-20: "update the logos, the banners"): each its own size
BRAND_BANNERS = {"github-social-preview-1280x640.png": (1280, 640), "discord-server-banner-960x540.png": (960, 540)}


def on_ground(size):
    """the banner whole on its own dark ground at `size`: scaled to fit, its top and bottom faded into the ground
    (never stretched, never cut)"""
    W, H = size
    src = Image.open(BANNER).convert("RGB")
    arr = np.asarray(src).astype(np.float64)
    edge = max(4, int(min(arr.shape[:2]) * 0.04))
    ring = np.concatenate([arr[:edge].reshape(-1, 3), arr[-edge:].reshape(-1, 3), arr[:, :edge].reshape(-1, 3),
                           arr[:, -edge:].reshape(-1, 3)])
    ground = ring.mean(axis=0)
    k = min(W / src.width, H / src.height)
    w, h = round(src.width * k), round(src.height * k)
    pic = np.asarray(src.resize((w, h), Image.LANCZOS)).astype(np.float64)
    y = (np.arange(h) + 0.5) / h
    fade = smooth(np.minimum(y, 1 - y) / 0.12)[:, None, None] if h < H else np.ones((h, 1, 1))
    out = np.empty((H, W, 3))
    out[:] = ground
    top, left = (H - h) // 2, (W - w) // 2
    out[top:top + h, left:left + w] = pic * fade + ground * (1 - fade)
    return np.clip(np.round(out), 0, 255).astype(np.uint8)


def brand(badge, cx, cy, half):
    """docs/brand: the logo and the banner at the sizes the places outside the game take"""
    os.makedirs(BRAND, exist_ok=True)
    Image.fromarray(disc(badge, cx, cy, half + 2, 512)).save(os.path.join(BRAND, "melloui-icon-512.png"))
    shutil.copy2(BANNER, os.path.join(BRAND, "melloui-banner.png"))
    for name, size in BRAND_BANNERS.items():
        Image.fromarray(on_ground(size)).save(os.path.join(BRAND, name))
    old = os.path.join(BACKUP, "logo-icon.png")   # (MelloUI Oldschool keeps the old emblem)
    if os.path.exists(old):
        shutil.copy2(old, os.path.join(BRAND, "oldschool-icon-512.png"))
    print("wrote %s" % BRAND)


def main():
    write = "--write" in sys.argv
    os.makedirs(OUT, exist_ok=True)
    badge = Image.open(BADGE).convert("RGBA")
    cx, cy, half = centre(badge)
    icon = bleed(disc(badge, cx, cy, INNER_R, 256))
    full = bleed(disc(badge, cx, cy, half + 2, 256))
    ban = banner_tex()
    made = {"LogoIcon.tga": icon, "LogoFull.tga": full, "InstallerBanner.tga": ban}
    for name, arr in made.items():
        Image.fromarray(arr).save(os.path.join(OUT, name))
        Image.fromarray(arr).save(os.path.join(OUT, name.replace(".tga", ".png")))
    docs_icon = disc(badge, cx, cy, half + 2, 512)
    Image.fromarray(docs_icon).save(os.path.join(OUT, "logo-icon.png"))
    print("made", ", ".join("%s %s" % (k, v.shape[1::-1]) for k, v in made.items()), "| centre %.1f %.1f r %.1f" % (cx, cy, half))
    if "--brand" in sys.argv:
        brand(badge, cx, cy, half)
    if not write:
        return
    os.makedirs(BACKUP, exist_ok=True)
    for name in made:
        old = os.path.join(MASTERS, name)
        if os.path.exists(old) and not os.path.exists(os.path.join(BACKUP, name)):
            shutil.copy2(old, os.path.join(BACKUP, name))
        Image.fromarray(made[name]).save(old)
    for name in ("logo.png", "logo-icon.png"):
        old = os.path.join(REPO, "docs", name)
        if os.path.exists(old) and not os.path.exists(os.path.join(BACKUP, name)):
            shutil.copy2(old, os.path.join(BACKUP, name))
    shutil.copy2(BANNER, os.path.join(REPO, "docs", "logo.png"))
    Image.fromarray(docs_icon).save(os.path.join(REPO, "docs", "logo-icon.png"))
    print("wrote the masters and docs (old ones in %s)" % BACKUP)


if __name__ == "__main__":
    main()

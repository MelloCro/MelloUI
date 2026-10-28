"""The configurator's motion art (1.2.4; docs/plans/configurator-shell.md, the user's picks of 2026-10-27): what moves
over each skin's painting while the window is open (Core/ConfigMotion.lua), baked from the sketch's motion
(MelloUI-BuildData/output/configurator_shell_sketch, patch_motion_v3.py / patch_motion_skins.py) and from the paintings
themselves. Every colour is baked in; the code only places, fades and moves the pieces.

  Flame.tga          512 x 128: three flame strips (rows of 32), each tiling across, for the fiery lines (Modern)
  Glow.tga           64 x 64: the warm glow dot (the lines' sparks, Oldschool's embers)
  RingGlow.tga       128 x 128: the crest ring's glow (its radius 48 of 64: drawn 96 across for the painted ring's 36)
  Streak.tga         128 x 16: a lamp's light running along a metal rail (Default)
  RingGlint.tga      128 x 128: a glint and its trail on the ring (radius 48.6 of 64: drawn 100 across, Default)
  Candle.tga         512 x 512: a candle's warm light (Oldschool's corners)
  Cracks_Oldschool.tga  2048 x 1024: the painting's own ember-lit cracks, the painting's place in the file
                     (0..0.75 across: Painting_Oldschool's), lit in patches (Oldschool)
  PatchMask.tga      128 x 128: a soft round patch, the mask a crack patch is lit through
  Card1_Modern.tga, Card2_Modern.tga  256 x 256: the two compass roses' inner cards, cut round from the painting
                     (Modern; their outer rings stay painted)

    python Tools/make_configurator_motion.py
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "Workspace", "BuildData", "output", "ai_art", "configurator_bg")
OUT = os.path.join(ROOT, "Media", "Textures", "Configurator")
WARM = (255, 170, 60)


def save(arr, name):
    im = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    path = os.path.join(OUT, name)
    im.save(path)
    print(path, im.size)


def rgba(h, w, rgb, alpha):
    out = np.zeros((h, w, 4))
    out[..., 0], out[..., 1], out[..., 2] = rgb
    out[..., 3] = np.clip(alpha, 0, 1) * 255
    return out


def flame():
    # three strips, each a tiling run of peaks (sums of sines with whole cycles over 512), shaped peaky, under a soft
    # band across: the sketch's three waves of unrelated speeds as three strips moving apart
    x = np.arange(512) / 512.0
    y = np.arange(32) - 15.5
    band = np.exp(-(y / 5.5) ** 2)
    out = np.zeros((128, 512, 4))
    for row, cycles in enumerate(((2, 3, 5), (5, 7, 9), (11, 13, 17))):
        n = sum(math.e ** (-i * 0.4) * np.sin(2 * np.pi * c * x + i * 1.7) for i, c in enumerate(cycles))
        n = (n - n.min()) / (n.max() - n.min())
        peaks = np.clip((n - 0.35) / 0.65, 0, 1) ** 1.6
        a = band[:, None] * peaks[None, :]
        out[row * 32:(row + 1) * 32] = rgba(32, 512, WARM, a)
    save(out, "Flame.tga")


def glow():
    s = 64
    yy, xx = np.mgrid[0:s, 0:s] + 0.5
    r = np.hypot(xx - s / 2, yy - s / 2) / (s / 2)
    # the sketch's dot: full warm in the middle, (255,140,40,.45) at .35, nothing at the edge
    a = np.where(r < 0.35, 1 - (1 - 0.45) * r / 0.35, 0.45 * np.clip((1 - r) / 0.65, 0, 1))
    g = np.where(r < 0.35, 190 - 50 * r / 0.35, 140)
    out = rgba(s, s, (255, 0, 40), a)
    out[..., 1] = g
    save(out, "Glow.tga")


def ring(name, radius, width, rgb, size=128):
    yy, xx = np.mgrid[0:size, 0:size] + 0.5
    r = np.hypot(xx - size / 2, yy - size / 2)
    a = np.exp(-((r - radius) / width) ** 2)
    save(rgba(size, size, rgb, a), name)


def streak():
    x = np.linspace(-1, 1, 128)
    y = np.arange(16) - 7.5
    a = np.clip(1 - np.abs(x), 0, 1) ** 1.3
    b = np.exp(-(y / 2.6) ** 2)
    save(rgba(16, 128, (255, 248, 230), b[:, None] * a[None, :]), "Streak.tga")


def ring_glint():
    # nine dots trailing round the ring behind the head (the sketch's), the head at the top: turned once clockwise
    size = 128
    radius = 38 * size / 100
    img = Image.new("RGBA", (size * 4, size * 4), (0, 0, 0, 0))
    for i in range(9):
        q = math.pi / 2 + i * 0.06   # (counter-clockwise of the head: behind it as it turns clockwise)
        f = (1 - i / 9)
        cx = size * 2 + math.cos(q) * radius * 4
        cy = size * 2 - math.sin(q) * radius * 4
        dot = Image.open(os.path.join(OUT, "Glow.tga")).resize((48, 48), Image.LANCZOS)
        a = np.asarray(dot).astype(float)
        a[..., 3] *= f
        img.alpha_composite(Image.fromarray(a.astype(np.uint8), "RGBA"), (int(cx - 24), int(cy - 24)))
    img = img.resize((size, size), Image.LANCZOS)
    arr = np.asarray(img).astype(float)
    arr[..., 0:3] = np.maximum(arr[..., 0:3], np.array([255, 235, 190]) * (arr[..., 3:4] > 0))
    save(arr, "RingGlint.tga")


def candle():
    s = 512
    yy, xx = np.mgrid[0:s, 0:s] + 0.5
    r = np.hypot(xx - s / 2, yy - s / 2) / (s / 2)
    a = np.where(r < 0.45, 1 - (1 - 0.38) * r / 0.45, 0.38 * np.clip((1 - r) / 0.55, 0, 1))
    out = rgba(s, s, (255, 160, 60), a)
    out[..., 1] = np.where(r < 0.45, 170 - 30 * r / 0.45, 140 - 20 * np.clip((r - 0.45) / 0.55, 0, 1))
    save(out, "Candle.tga")


def cracks():
    # (make_cracks.py's map at the painting's own size: the window's units x 1536 / 1140)
    src = Image.open(os.path.join(SOURCE, "configurator_bg_oldschool_v2.png")).convert("RGB")
    a = np.asarray(src).astype(float)
    r, b = a[..., 0], a[..., 2]
    crack = np.clip((r - b - 22) / 30, 0, 1) * np.clip((r - 50) / 50, 0, 1)
    k = 1536 / 1140.0
    keep = np.ones_like(crack)

    def box(y0, y1, x0, x1):
        keep[int(y0 * k):int(y1 * k), int(x0 * k):int(x1 * k)] = 0

    box(146, 648, 266, 1140)   # the parchment
    box(0, 760, 252, 270)      # the side band
    box(132, 149, 252, 1140)   # the header band
    box(644, 661, 252, 1140)   # the footer band
    box(100, 114, 0, 270)      # under the crest
    yy, xx = np.mgrid[0:1024, 0:1536]
    keep[(xx - 55 * k) ** 2 + (yy - 55 * k) ** 2 < (48 * k) ** 2] = 0   # the crest ring
    crack *= keep
    out = np.zeros((1024, 2048, 4))
    out[:, :1536] = rgba(1024, 1536, (255, 0, 40), np.clip(crack * 1.4, 0, 1))
    out[:, :1536, 1] = 150 + 70 * crack
    im = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")
    im.putalpha(im.split()[3].filter(ImageFilter.GaussianBlur(2)))
    path = os.path.join(OUT, "Cracks_Oldschool.tga")
    im.save(path)
    print(path, im.size, int((crack > .2).sum()), "crack pixels")


def patch_mask():
    # a soft round patch (white, its alpha falling off): the mask that lights the cracks a patch at a time
    s = 128
    yy, xx = np.mgrid[0:s, 0:s] + 0.5
    r = np.hypot(xx - s / 2, yy - s / 2) / (s / 2)
    a = np.clip(1 - r, 0, 1) ** 1.6
    save(rgba(s, s, (255, 255, 255), a), "PatchMask.tga")


def card(name, cx, cy, r):
    src = Image.open(os.path.join(SOURCE, "configurator_bg_modern_v3_calm.png")).convert("RGBA")
    box = Image.new("RGBA", (2 * r, 2 * r), (0, 0, 0, 0))
    box.paste(src.crop((cx - r, cy - r, cx + r, cy + r)), (0, 0))
    m = Image.new("L", (8 * r, 8 * r), 0)
    ImageDraw.Draw(m).ellipse((6, 6, 8 * r - 6, 8 * r - 6), fill=255)
    m = m.resize((2 * r, 2 * r), Image.LANCZOS)
    alpha = Image.fromarray((np.asarray(m).astype(float) * (np.asarray(box)[..., 3] > 0)).astype(np.uint8), "L")
    box.putalpha(alpha)
    box = box.resize((256, 256), Image.LANCZOS)
    path = os.path.join(OUT, name)
    box.save(path)
    print(path, box.size)


def main():
    os.makedirs(OUT, exist_ok=True)
    flame()
    glow()
    ring("RingGlow.tga", 48, 4.5, WARM)
    streak()
    ring_glint()
    candle()
    cracks()
    patch_mask()
    card("Card1_Modern.tga", 1438, 105, 82)    # the header's rose
    card("Card2_Modern.tga", 38, 815, 118)     # the side column's rose (past the painting's left edge: clear there)


if __name__ == "__main__":
    main()

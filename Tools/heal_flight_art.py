"""The heal flight's sprites (docs/plans/heal-flight.md; the user's picks 2026-10-09: all three looks of
MelloUI-BuildData/output/heal_flight_sketch). Every sprite is light, drawn by the game's ADD blend: its colour is
added to the screen at its alpha's strength, so the colour is baked in (the art's own colours, no tint) and a
bright core goes towards white. Written to Media/FrameFX (the core's: MelloUI.FrameFX, the engine Heal Flight
and Frame Effects share) as 32-bit TGA, power-of-two sizes.

    python Tools/heal_flight_art.py
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Media", "FrameFX")
SS = 4   # drawn this many times over, then scaled down

# the looks' colours (the sketch's): A gold, B green and teal, the leaves
GOLD = (255, 186, 70)
GREEN = (90, 255, 140)
TEAL = (70, 225, 210)
LEAF = (120, 255, 110)
# Water (the user, 2026-10-09: "a watery effect for the shaman"; heal_water_ticks.jpg)
WATER = (70, 160, 255)
FOAM = (190, 232, 255)
# the tanks' tools and defensives (the user, 2026-10-09: "a roar effect, repeatable pulsing red waves"): red for
# the roar, a taunt and Last Stand, steel for a fortify, gold for an immunity
RED = (255, 62, 40)
STEEL = (185, 205, 230)
# the roar's (the user's reference, 2026-10-09: a champion's scream in a video, "aggressive vibrating sound waves
# coming out of his mouth"; then square, the user: "instead of making them round and jittery, why not make them
# square, spawning in the middle and spreading trough the whole unitframe, like a square agressive water ripple")
FIRE = (255, 120, 45)
WHITE = (255, 248, 225)


def light(intensity, colour, hot=0.0):
    """an RGBA sprite from an intensity map (0..1): the colour at that strength, its brightest part
    `hot` of the way to white"""
    i = np.clip(intensity, 0, 1)
    c = np.array(colour, np.float32)[None, None, :]
    w = np.array(WHITE, np.float32)[None, None, :]
    mix = np.clip((i - 0.6) / 0.4, 0, 1)[..., None] * hot
    rgb = c * (1 - mix) + w * mix
    a = (i * 255).round().astype(np.uint8)
    return Image.fromarray(np.dstack([rgb.round().astype(np.uint8), a]), "RGBA")


def canvas(size):
    img = Image.new("L", (size * SS, size * SS), 0)
    return img, ImageDraw.Draw(img)


def down(img, size, blur=0.0, gain=1.0):
    """the supersampled drawing scaled down, softened by `blur` px, as an intensity map"""
    small = img.resize((size, size), Image.LANCZOS)
    if blur:
        small = small.filter(ImageFilter.GaussianBlur(blur))
    return np.clip(np.asarray(small).astype(np.float32) / 255.0 * gain, 0, 1)


def radial(size, sigma):
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    c = (size - 1) / 2
    r = np.hypot(x - c, y - c) / (size / 2)
    g = np.exp(-(r / sigma) ** 2)
    g[r >= 1] = 0
    return g * np.clip((1 - r) * 4, 0, 1)   # (nothing reaches the edge)


def glow(colour, size=64):
    # (richer, the user 2026-10-09: "in game they are more watered down": a wide strong halo round a hot core)
    core = radial(size, 0.2)
    halo = radial(size, 0.62) * 0.85
    return light(np.clip(core + halo, 0, 1), colour, hot=1.0)


def streak(colour, w=256, h=64):
    """a lens streak: a thin bright line across, its glow round it, brightest in the middle"""
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    cx, cy = (w - 1) / 2, (h - 1) / 2
    along = np.exp(-((x - cx) / (w * 0.3)) ** 2) * np.clip((1 - np.abs(x - cx) / (w / 2)) * 3, 0, 1)
    line = np.exp(-((y - cy) / (h * 0.045)) ** 2)
    soft = np.exp(-((y - cy) / (h * 0.22)) ** 2) * 0.45
    edge = np.clip((1 - np.abs(y - cy) / (h / 2)) * 3, 0, 1)
    return light(np.clip(along * (line + soft) * edge, 0, 1), colour, hot=1.0)


def crest(colour, size=128):
    img, d = canvas(size)
    s = size * SS
    c = s / 2
    k = s * 0.36
    pts = [(c - k, c - k * 1.0), (c + k, c - k * 1.0), (c + k, c - k * 0.1), (c, c + k * 1.15), (c - k, c - k * 0.1)]
    d.polygon(pts, fill=45)
    d.line(pts + [pts[0]], fill=255, width=3 * SS, joint="curve")
    d.line((c, c - k * 0.8, c, c + k * 0.75), fill=220, width=2 * SS)
    d.line((c - k * 0.62, c - k * 0.3, c + k * 0.62, c - k * 0.3), fill=220, width=2 * SS)
    sharp = down(img, size, 0.6)
    halo = down(img, size, 4.0, 1.1)
    return light(np.clip(sharp + halo, 0, 1), colour, hot=0.7)


def pillar(colour, w=64, h=256):
    """a column of light: brightest at its foot, fading upwards, a hot line down its middle"""
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    cx = (w - 1) / 2
    up = np.clip(y / (h - 1), 0, 1) ** 1.4
    foot = np.clip((h - 1 - y) / (h * 0.06), 0, 1)
    across = np.exp(-((x - cx) / (w * 0.34)) ** 2)
    core = np.exp(-((x - cx) / (w * 0.07)) ** 2)
    edge = np.clip((1 - np.abs(x - cx) / (w / 2)) * 3, 0, 1)
    return light(np.clip((across * 0.8 + core) * up * foot * edge, 0, 1), colour, hot=0.9)


def sheen(w=64, h=128):
    """a soft diagonal band of light (a barrier's shimmer passing across)"""
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    u = (x - (w - 1) / 2) + (y - (h - 1) / 2) * 0.45
    band = np.exp(-(u / (w * 0.16)) ** 2)
    edge = np.clip((1 - np.abs(y - (h - 1) / 2) / (h / 2)) * 4, 0, 1) * np.clip((1 - np.abs(x - (w - 1) / 2) / (w / 2)) * 4, 0, 1)
    return light(np.clip(band * edge * 0.9, 0, 1), WHITE, hot=0.0)


def spark(colour, size=32):
    img, d = canvas(size)
    c = size * SS / 2
    arm = size * SS * 0.46
    d.polygon([(c - arm, c), (c, c - SS), (c + arm, c), (c, c + SS)], fill=255)
    d.polygon([(c, c - arm), (c - SS, c), (c, c + arm), (c + SS, c)], fill=255)
    lines = down(img, size, 0.6, 1.6)
    return light(np.clip(lines + radial(size, 0.18) + radial(size, 0.4) * 0.3, 0, 1), colour, hot=0.9)


def leaf(size=32):
    img, d = canvas(size)
    s = size * SS
    pts = []
    for i in range(25):
        u = i / 24
        pts.append((s * 0.08 + u * s * 0.84, s / 2 - s * 0.15 * math.sin(math.pi * u) ** 1.2))
    for i in range(23, 0, -1):
        u = i / 24
        pts.append((s * 0.08 + u * s * 0.84, s / 2 + s * 0.15 * math.sin(math.pi * u) ** 1.2))
    d.polygon(pts, fill=150)
    d.line((s * 0.1, s / 2, s * 0.9, s / 2), fill=255, width=SS)
    body = down(img, size, 0.5)
    halo = down(img, size, 2.5, 0.5)
    return light(np.clip(body + halo, 0, 1), LEAF, hot=0.25)


def ring(colour, size=128):
    img, d = canvas(size)
    s = size * SS
    c = s / 2
    R = s * 0.34
    d.ellipse((c - R, c - R, c + R, c + R), outline=210, width=2 * SS)
    for i in range(16):
        a = i * math.pi / 8 + 0.2
        x, y = c + (R + 6 * SS) * math.cos(a), c + (R + 6 * SS) * math.sin(a)
        if i % 2:
            d.line((x - 2.5 * SS * math.sin(a), y + 2.5 * SS * math.cos(a), x + 2.5 * SS * math.sin(a),
                    y - 2.5 * SS * math.cos(a)), fill=230, width=SS)
        else:
            k = 3 * SS
            d.polygon([(x + k * math.cos(a), y + k * math.sin(a)), (x - 0.6 * k * math.sin(a), y + 0.6 * k * math.cos(a)),
                       (x - k * math.cos(a), y - k * math.sin(a)), (x + 0.6 * k * math.sin(a), y - 0.6 * k * math.cos(a))],
                      fill=240)
    r2 = R * 0.78
    d.ellipse((c - r2, c - r2, c + r2, c + r2), outline=120, width=SS)
    sharp = down(img, size, 0.5)
    halo = down(img, size, 3.0, 0.7)
    return light(np.clip(sharp + halo, 0, 1), colour, hot=0.6)


def rays(colour, size=256, seed=7):
    rnd = np.random.default_rng(seed)
    img, d = canvas(size)
    s = size * SS
    c = s / 2
    for i in range(18):
        a = i * 2 * math.pi / 18 + rnd.uniform(-0.1, 0.1)
        r1 = s * 0.5 * rnd.uniform(0.62, 0.97)
        r0 = s * 0.06
        w = 0.045
        d.polygon([(c + r0 * math.cos(a - w), c + r0 * math.sin(a - w)), (c + r1 * math.cos(a), c + r1 * math.sin(a)),
                   (c + r0 * math.cos(a + w), c + r0 * math.sin(a + w))], fill=int(rnd.uniform(150, 230)))
    sharp = down(img, size, 0.8)
    halo = down(img, size, 5.0, 0.6)
    return light(np.clip(sharp + halo + radial(size, 0.16) * 0.8, 0, 1), colour, hot=0.8)


def wave(colour, size=128):
    img, d = canvas(size)
    s = size * SS
    c = s / 2
    R = s * 0.42
    d.ellipse((c - R, c - R, c + R, c + R), outline=230, width=3 * SS)
    sharp = down(img, size, 1.0)
    halo = down(img, size, 4.0, 0.8)
    return light(np.clip(sharp + halo, 0, 1), colour, hot=0.5)


def plus(colour, size=32):
    img, d = canvas(size)
    s = size * SS
    c = s / 2
    t, L = s * 0.09, s * 0.32
    d.rectangle((c - t, c - L, c + t, c + L), fill=215)
    d.rectangle((c - L, c - t, c + L, c + t), fill=215)
    sharp = down(img, size, 0.4)
    halo = down(img, size, 2.5, 0.7)
    return light(np.clip(sharp + halo, 0, 1), colour, hot=0.35)


def rune(colour, size=32):
    img, d = canvas(size)
    s = size * SS
    c = s / 2
    k = s * 0.2
    d.polygon([(c, c - k), (c + k * 0.6, c), (c, c + k), (c - k * 0.6, c)], fill=255)
    sharp = down(img, size, 0.4)
    halo = down(img, size, 2.0, 0.6)
    return light(np.clip(sharp + halo, 0, 1), colour, hot=0.7)


def drop(size=32):
    """a droplet, its point up (turned in the game to the way it moves)"""
    img, d = canvas(size)
    s = size * SS
    c = s / 2
    r = s * 0.2
    cy = c + s * 0.1
    d.ellipse((c - r, cy - r, c + r, cy + r), fill=235)
    d.polygon([(c - r * 0.98, cy - r * 0.2), (c, cy - s * 0.42), (c + r * 0.98, cy - r * 0.2)], fill=235)
    d.ellipse((c - r * 0.45, cy - r * 0.55, c - r * 0.05, cy - r * 0.15), fill=255)
    body = down(img, size, 0.4)
    halo = down(img, size, 2.2, 0.8)
    return light(np.clip(body + halo, 0, 1), FOAM, hot=0.6)


def ripple(colour, size=128):
    img, d = canvas(size)
    s = size * SS
    c = s / 2
    R = s * 0.43
    d.ellipse((c - R, c - R, c + R, c + R), outline=235, width=2 * SS)
    sharp = down(img, size, 0.7)
    halo = down(img, size, 3.0, 0.7)
    return light(np.clip(sharp + halo, 0, 1), colour, hot=0.4)


def bubble(w=256, h=128, colour=None, high_colour=None):
    """a bubble on a frame's edge: a soft rim, a bright highlight at its upper left, a faint inside; its corners
    square like the frames' (the user, 2026-10-09: "the borders here are square and they have round edges")"""
    img = Image.new("L", (w * SS, h * SS), 0)
    d = ImageDraw.Draw(img)
    m = 4 * SS
    d.rounded_rectangle((m, m, w * SS - m, h * SS - m), radius=h * SS * 0.05, outline=220, width=3 * SS)
    rim = np.asarray(img.resize((w, h), Image.LANCZOS).filter(ImageFilter.GaussianBlur(1.0))).astype(np.float32) / 255
    halo = np.asarray(img.resize((w, h), Image.LANCZOS).filter(ImageFilter.GaussianBlur(4))).astype(np.float32) / 255 * 0.8
    hi = Image.new("L", (w * SS, h * SS), 0)
    dh = ImageDraw.Draw(hi)
    # (a straight glint along the top left corner, square like the frame: no round arc)
    g = m * 2.6
    dh.line(((g, h * SS * 0.55), (g, g), (w * SS * 0.32, g)), fill=255, width=2 * SS, joint="curve")
    high = np.asarray(hi.resize((w, h), Image.LANCZOS).filter(ImageFilter.GaussianBlur(0.8))).astype(np.float32) / 255
    inside = Image.new("L", (w * SS, h * SS), 0)
    ImageDraw.Draw(inside).rounded_rectangle((m, m, w * SS - m, h * SS - m), radius=h * SS * 0.05, fill=255)
    fill = np.asarray(inside.resize((w, h), Image.LANCZOS).filter(ImageFilter.GaussianBlur(8))).astype(np.float32) / 255 * 0.12
    a = np.clip(rim + halo + high + fill, 0, 1)
    base = np.array(colour or WATER, np.float32)[None, None, :]
    shine = np.array(high_colour or FOAM, np.float32)[None, None, :]
    rgb = base * (1 - high[..., None]) + shine * high[..., None]
    return Image.fromarray(np.dstack([rgb.round().astype(np.uint8), (a * 255).round().astype(np.uint8)]), "RGBA")


def ring_fire(size=128):
    """the roar's ripple on a round piece (a portrait's ring, the split of a portrait-and-bars frame; the user,
    2026-10-09, C of the sketch): the square ripples' fire as a ring, its line at 0.84 of the sprite"""
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    c = (size - 1) / 2
    d = np.hypot(x - c, y - c) - size * 0.42
    core = np.exp(-(d / 1.3) ** 2)
    glow = np.exp(-(d / 5.0) ** 2) * 0.75
    return light(np.clip(core + glow, 0, 1), FIRE, hot=0.7)


def halo(size=128):
    """a round border's light (on a portrait's ring): a thin bright line at 0.8 of the sprite, its glow either
    side; white, tinted in the game (the border's colour)"""
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    c = (size - 1) / 2
    d = np.hypot(x - c, y - c) - size * 0.40
    line = np.exp(-(d / 1.2) ** 2)
    glow = np.exp(-(d / 6.0) ** 2) * 0.7
    return light(np.clip(line + glow, 0, 1), WHITE, hot=0.0)


def bubble_round(size=128, colour=None, high_colour=None):
    """the bubble on a round piece: a soft rim on the ring, a curved glint at its upper left, a faint inside"""
    img = Image.new("L", (size * SS, size * SS), 0)
    d = ImageDraw.Draw(img)
    m = 4 * SS
    d.ellipse((m, m, size * SS - m, size * SS - m), outline=220, width=3 * SS)
    rim = np.asarray(img.resize((size, size), Image.LANCZOS).filter(ImageFilter.GaussianBlur(1.0))).astype(np.float32) / 255
    glow = np.asarray(img.resize((size, size), Image.LANCZOS).filter(ImageFilter.GaussianBlur(4))).astype(np.float32) / 255 * 0.8
    hi = Image.new("L", (size * SS, size * SS), 0)
    g = m * 3
    ImageDraw.Draw(hi).arc((g, g, size * SS - g, size * SS - g), 190, 250, fill=255, width=2 * SS)
    high = np.asarray(hi.resize((size, size), Image.LANCZOS).filter(ImageFilter.GaussianBlur(0.8))).astype(np.float32) / 255
    inside = Image.new("L", (size * SS, size * SS), 0)
    ImageDraw.Draw(inside).ellipse((m, m, size * SS - m, size * SS - m), fill=255)
    fill = np.asarray(inside.resize((size, size), Image.LANCZOS).filter(ImageFilter.GaussianBlur(8))).astype(np.float32) / 255 * 0.12
    a = np.clip(rim + glow + high + fill, 0, 1)
    base = np.array(colour or WATER, np.float32)[None, None, :]
    shine = np.array(high_colour or FOAM, np.float32)[None, None, :]
    rgb = base * (1 - high[..., None]) + shine * high[..., None]
    return Image.fromarray(np.dstack([rgb.round().astype(np.uint8), (a * 255).round().astype(np.uint8)]), "RGBA")


def fire_line(across=True, length=128, thick=32):
    """a fiery line (the roar's square ripples are built of four: the same sharp width at any size): a thin hot
    core, its glow either side, full strength to its ends (the corners meet another line)"""
    t = np.arange(thick, dtype=np.float32) - (thick - 1) / 2
    core = np.exp(-(t / 1.3) ** 2)
    glow = np.exp(-(t / 5.0) ** 2) * 0.75
    profile = np.clip(core + glow, 0, 1)
    band = np.repeat(profile[:, None], length, axis=1)   # thick x length
    img = light(band, FIRE, hot=0.7)
    return img if across else img.transpose(Image.ROTATE_90)


SPRITES = {
    "glow_gold": lambda: glow(GOLD),
    "glow_green": lambda: glow(GREEN),
    "glow_white": lambda: glow(WHITE),
    "spark_gold": lambda: spark(GOLD),
    "leaf": leaf,
    "ring_gold": lambda: ring(GOLD),
    "rays_gold": lambda: rays(GOLD),
    "wave_gold": lambda: wave(GOLD),
    "wave_teal": lambda: wave(TEAL),
    "plus_gold": lambda: plus(GOLD),
    "plus_green": lambda: plus(GREEN),
    "rune_gold": lambda: rune(GOLD),
    "streak_gold": lambda: streak(GOLD),
    "streak_green": lambda: streak(GREEN),
    "crest_gold": lambda: crest(GOLD),
    "crest_green": lambda: crest(GREEN),
    "pillar_gold": lambda: pillar(GOLD),
    "pillar_green": lambda: pillar(GREEN),
    "sheen": sheen,
    "glow_blue": lambda: glow(WATER),
    "streak_blue": lambda: streak(WATER),
    "pillar_blue": lambda: pillar(WATER),
    "crest_blue": lambda: crest(WATER),
    "plus_blue": lambda: plus(FOAM),
    "ripple_blue": lambda: ripple(WATER),
    "drop": drop,
    "bubble": bubble,
    "glow_red": lambda: glow(RED),
    "wave_red": lambda: wave(RED),
    "streak_red": lambda: streak(RED),
    "crest_steel": lambda: crest(STEEL),
    "glow_steel": lambda: glow(STEEL),
    "streak_white": lambda: streak(WHITE),
    "bubble_gold": lambda: bubble(colour=GOLD, high_colour=WHITE),
    "line_fire_h": lambda: fire_line(True),
    "line_fire_v": lambda: fire_line(False),
    "glow_fire": lambda: glow(FIRE),
    "ring_fire": ring_fire,
    "halo_white": halo,
    "bubble_round": bubble_round,
    "bubble_gold_round": lambda: bubble_round(colour=GOLD, high_colour=WHITE),
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, make in SPRITES.items():
        path = os.path.join(OUT, name + ".tga")
        make().save(path, format="TGA")
        print(path)


if __name__ == "__main__":
    main()

"""The Route's light beam (user, 2026-09-23: "can you build that beam, but make
it red"): a column of light rising from the destination into the sky; the
light at its foot and the trail's dots (0.16.0, the user's picks D and A of
MelloUI-BuildData/output/route_marks_sketch).

Drawn procedurally and seeded (no borrowed art), all white so the game tints
them (MelloUI.Meaning's route colours, SetVertexColor). The beam's four are
added to what is behind them (blend mode ADD):

  beam_glow.tga     128 x 512  the column: a bright core, soft sides, full at
                               the foot and fading out into the sky; also the
                               MASK that keeps the streaks inside the column
  beam_streaks.tga   64 x 256  thin vertical streaks of light, tiling top to
                               bottom, scrolled upward in the game so the light
                               seems to rise
  beam_ring.tga     256 x 64   a ring of light on the ground round the foot (an
                               ellipse, thicker at its sides, a faint fill), drawn
                               72 x 27
  beam_halo.tga      64 x 64   a soft round glow behind the gem, drawn 72 x 72

and one is laid over the map (blend mode BLEND):

  trail_dot.tga      64 x 64   the trail's dot: a white disc (0.25 of the width in
                               radius) with a rim at 0.28 of its light (to 0.34),
                               so one tint colours the dot and darkens its rim

Writes the TGA masters (Tools/paths.py); `texture_pack.py ship` makes Media.

    python Tools/make_route_beam.py
"""
import math
import os
import random

from PIL import Image, ImageFilter
from paths import master  # the TGA masters: MelloUI-BuildData/masters/Media

OUT = master("Textures", "Route")  # the TGA master (Tools/paths.py); `texture_pack.py ship` makes what Media ships
SEED = 4711


def glow():
    w, h = 128, 512
    img = Image.new("L", (w, h), 0)
    px = img.load()
    for y in range(h):
        up = y / (h - 1)                       # 0 at the top, 1 at the foot
        # fades into the sky, strongest over the lower third, a flare at the foot
        v = up ** 1.6
        v = min(1.0, v * 1.15 + 0.25 * math.exp(-((1 - up) / 0.04) ** 2))
        # narrower towards the sky
        width = 0.16 + 0.10 * up
        for x in range(w):
            c = (x + 0.5) / w - 0.5
            core = math.exp(-(c / (width * 0.35)) ** 2)
            soft = math.exp(-(c / width) ** 2)
            px[x, y] = int(255 * min(1.0, v * (0.55 * soft + 0.6 * core)))
    return img


def streaks():
    w, h = 64, 256
    rnd = random.Random(SEED)
    img = Image.new("L", (w, h), 0)
    px = img.load()
    for _ in range(46):
        x = rnd.randint(0, w - 1)
        y0 = rnd.randint(0, h - 1)
        length = rnd.randint(24, 120)
        bright = rnd.uniform(0.35, 1.0)
        for i in range(length):
            y = (y0 + i) % h                    # wraps: the texture tiles top to bottom
            t = i / length
            a = bright * math.sin(math.pi * t) ** 0.8
            px[x, y] = min(255, px[x, y] + int(255 * a))
    # soften sideways a little so a streak is a ray, not a pixel line
    img = img.filter(ImageFilter.GaussianBlur(0.9))
    return img


def supersampled(w, h, k, fn):
    """an L image of w x h: fn(x, y) in 0..1 over the pixel's k x k samples, averaged"""
    img = Image.new("L", (w, h), 0)
    px = img.load()
    for y in range(h):
        for x in range(w):
            acc = 0.0
            for j in range(k):
                for i in range(k):
                    acc += fn(x + (i + 0.5) / k, y + (j + 0.5) / k)
            px[x, y] = int(round(255 * min(1.0, max(0.0, acc / (k * k)))))
    return img


def ring():
    w, h = 256, 64                            # (drawn 72 x 27: the ellipse is laid out for that stretch)
    rx, ry, t = 101.0, 20.9, 2.9              # the ellipse and its line's softness (px)

    def v(x, y):
        dx, dy = (x - w / 2) / rx, (y - h / 2) / ry
        d = math.sqrt(dx * dx + dy * dy)
        return math.exp(-(((d - 1) * ry) ** 2) / (2 * t * t)) + 0.25 * max(0.0, 1 - d)
    return supersampled(w, h, 2, v)


def halo():
    w = 64
    sigma = 9.8

    def v(x, y):
        r2 = (x - w / 2) ** 2 + (y - w / 2) ** 2
        return math.exp(-r2 / (2 * sigma * sigma))
    return supersampled(w, w, 2, v)


def trail_dot():
    w = 64
    fill_r, rim_r, rim_light = 0.25 * w, 0.34 * w, 0.28
    cover = supersampled(w, w, 8, lambda x, y: 1.0 if math.hypot(x - w / 2, y - w / 2) <= rim_r else 0.0)
    light = supersampled(w, w, 8, lambda x, y: 1.0 if math.hypot(x - w / 2, y - w / 2) <= fill_r
                         else rim_light)
    return Image.merge("RGBA", (light, light, light, cover))


def save(mask, name):
    white = Image.new("L", mask.size, 255)
    path = os.path.join(OUT, name + ".tga")
    Image.merge("RGBA", (white, white, white, mask)).save(path)
    return path


def main():
    os.makedirs(OUT, exist_ok=True)
    print(save(glow(), "beam_glow"))
    print(save(streaks(), "beam_streaks"))
    print(save(ring(), "beam_ring"))
    print(save(halo(), "beam_halo"))
    path = os.path.join(OUT, "trail_dot.tga")
    trail_dot().save(path)
    print(path)


if __name__ == "__main__":
    main()

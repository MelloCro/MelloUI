"""The Route's light beam (user, 2026-09-23: "can you build that beam, but make
it red"): a column of light rising from the destination into the sky.

Two textures, drawn procedurally and seeded (no borrowed art), both white so
the game tints them (red, SetVertexColor) and adds them to what is behind them
(blend mode ADD):

  beam_glow.tga     128 x 512  the column: a bright core, soft sides, full at
                               the foot and fading out into the sky; also the
                               MASK that keeps the streaks inside the column
  beam_streaks.tga   64 x 256  thin vertical streaks of light, tiling top to
                               bottom, scrolled upward in the game so the light
                               seems to rise

Writes Media/Textures/Route/.

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


def save(mask, name):
    white = Image.new("L", mask.size, 255)
    path = os.path.join(OUT, name + ".tga")
    Image.merge("RGBA", (white, white, white, mask)).save(path)
    return path


def main():
    os.makedirs(OUT, exist_ok=True)
    print(save(glow(), "beam_glow"))
    print(save(streaks(), "beam_streaks"))


if __name__ == "__main__":
    main()

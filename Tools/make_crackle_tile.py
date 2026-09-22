"""
make_crackle_tile.py -- tiles/crackle: a seamless tile of the crackled dark
stone the profession banners (cards/<profession>) are painted on, so a page
behind those cards is the same surface at the same magnification (the cards
show the 804 px banners at 664 px: 0.83 px per px; the kit scale is 0.375, so
the tile's rule scale is 0.83 / 0.375 = 2.2).

Cut from the plain-stone part of a banner (no still-life), made seamless by
rolling it half a tile and cross-fading the centre band back to the original
along both axes. Writes kit/v2_2x/tiles/crackle.png + manifest; build_kit.py
resizes tiles to a power of two.
"""
import os, json
import numpy as np
from PIL import Image

KIT = r"C:\Users\mortu\Downloads\UITest\kit\v2_2x"
SRC = os.path.join(KIT, "cards", "alchemy.png")
REGION = (0, 0, 430, 215)       # plain stone, left of the still-life
BAND = 48                       # px of cross-fade either side of the seam


def seamless(a):
    h, w = a.shape[:2]
    out = np.roll(a, (h // 2, w // 2), axis=(0, 1)).astype(float)
    src = a.astype(float)
    # vertical seam (now at x = w/2): blend the band back to the original
    cx, cy = w // 2, h // 2
    x = np.arange(cx - BAND, cx + BAND)
    tri = 1 - np.abs((x - cx) / BAND)               # 0 at the band's edges, 1 at the seam
    out[:, x] = out[:, x] * (1 - tri)[None, :, None] + src[:, x] * tri[None, :, None]
    y = np.arange(cy - BAND, cy + BAND)
    tri = 1 - np.abs((y - cy) / BAND)
    out[y] = out[y] * (1 - tri)[:, None, None] + src[y] * tri[:, None, None]
    return np.clip(out, 0, 255).astype(np.uint8)


def main():
    im = Image.open(SRC).convert("RGBA").crop(REGION)
    a = np.array(im)
    t = seamless(a)
    out = os.path.join(KIT, "tiles", "crackle.png")
    Image.fromarray(t).save(out)
    man_path = os.path.join(KIT, "manifest.json")
    man = json.load(open(man_path))
    man["v2_2x/tiles/crackle"] = { "w": t.shape[1], "h": t.shape[0], "scale": 1.0, "src": "cards/alchemy stone, made seamless" }
    json.dump(man, open(man_path, "w"), indent=1, sort_keys=True)
    # preview: the tile repeated 3 x 3 next to the banner it came from
    W, H = t.shape[1], t.shape[0]
    prev = Image.new("RGBA", (W * 3 + 20 + 804, max(H * 3, 215)), (60, 60, 60, 255))
    for j in range(3):
        for i in range(3):
            prev.paste(Image.fromarray(t), (i * W, j * H))
    prev.paste(Image.open(SRC).convert("RGBA"), (W * 3 + 20, 0))
    prev.save(os.path.join(os.path.dirname(KIT), "..", "kit_raw", "crackle_preview.png"))
    print(f"tiles/crackle: {W}x{H}")


if __name__ == "__main__":
    main()

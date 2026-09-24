"""
Build Media/Textures/Chat/name_shade.tga: the soft band the chat lays behind
a line's channel tag and player name on its parchment sheet (Modules/Chat.lua,
ShadeLines). White with a feathered alpha: its left and right quarters are the
band's rounded ends (drawn at their own shape), its middle half is stretched;
the top and bottom fade softly, so the band has no hard edge on the paper.
The colour and strength are set in game.

    python Tools/make_chat_shade.py
"""
import os

import numpy as np
from PIL import Image
from paths import master  # the TGA masters: MelloUI-BuildData/masters/Media

OUT = master("Textures", "Chat", "name_shade.tga")  # the TGA master (Tools/paths.py); `texture_pack.py ship` makes what Media ships
W, H = 64, 32


def smooth(t):
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


ys = (np.arange(H) + 0.5) / H          # 0..1
xs = (np.arange(W) + 0.5) / W
# vertical: full in the middle, fading over the outer 40 % top and bottom
v = smooth(np.minimum(ys, 1 - ys) / 0.4)
# horizontal: each end quarter fades out smoothly (the cap's inner edge
# matches the middle exactly, so the stretched middle shows no seam)
cap = 0.25
edge = np.minimum(xs, 1 - xs)
hx = smooth(edge / cap)
a = np.outer(v, hx)
img = np.zeros((H, W, 4), np.uint8)
img[..., :3] = 255
img[..., 3] = np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
Image.fromarray(img).save(OUT)
print("->", os.path.normpath(OUT))

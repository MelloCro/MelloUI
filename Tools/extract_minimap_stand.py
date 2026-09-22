"""
SUPERSEDED by Tools/make_minimap_frame.py, which builds MinimapStand.tga from
docs/minimap-frame.webp with the ring, slot, zone bar and sun disc constants the
modules now use. Running this script overwrites that texture with the old art.

Turn docs/minimap-stand.webp (the ring-and-legs artwork, with alpha) into
Media/Textures/MinimapStand.tga, a 512 x 512 texture (or the size given as the
first argument), and print the ring's centre and inner radius on that canvas:
the numbers STAND_CX, STAND_CY and STAND_INNER_R in Modules/Services.lua.

    python Tools\\extract_minimap_stand.py          # 512
    python Tools\\extract_minimap_stand.py 1024

The ring is measured by fitting a circle to the outer edge of its upper half
(the legs hide the lower half). The constants that ship were set from the
1024 canvas the artwork was first tuned on and halved, so a rebuild at 512
changes nothing on screen; adjust them only if the artwork changes.
"""
import os
import sys
import numpy as np
from PIL import Image
from paths import OUTPUT

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "docs", "minimap-stand.webp")
OUT_TGA = os.path.join(HERE, "..", "Media", "Textures", "MinimapStand.tga")
OUT_PREVIEW = os.path.join(OUTPUT, "minimap-stand-preview.png")
CANVAS = int(sys.argv[1]) if len(sys.argv) > 1 else 512

im = Image.open(SRC).convert("RGBA")
w, h = im.size
# trim to the artwork's bounding box first
alpha = np.asarray(im)[:, :, 3]
ys, xs = np.nonzero(alpha > 8)
im = im.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
w, h = im.size
scale = min(CANVAS / w, CANVAS / h)
art = im.resize((int(round(w * scale)), int(round(h * scale))), Image.LANCZOS)
canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
ox = (CANVAS - art.size[0]) // 2
canvas.paste(art, (ox, 0))
canvas.save(OUT_TGA)

# --- measure the ring: circle through the outer edge of its upper half
mask = np.asarray(canvas)[:, :, 3] > 128
H, W = mask.shape
top = next(y for y in range(H) if mask[y].any())
points = []
for y in range(top, int(H * 0.45)):
    row = np.nonzero(mask[y])[0]
    if len(row):
        points.append((row.min(), y))
        points.append((row.max(), y))
P = np.array(points, float)
A = np.c_[P[:, 0], P[:, 1], np.ones(len(P))]
b = -(P[:, 0] ** 2 + P[:, 1] ** 2)
D, E, F = np.linalg.lstsq(A, b, rcond=None)[0]
cx, cy = -D / 2, -E / 2
r_out = float(np.sqrt(cx ** 2 + cy ** 2 - F))
y0 = int(round(cy))
row = np.nonzero(mask[y0])[0]
x = xl = row.min()
while mask[y0, x]:
    x += 1
thickness = x - xl
r_in = r_out - thickness
print(f"canvas {CANVAS}x{CANVAS}, art {art.size[0]}x{art.size[1]} at x offset {ox}")
print(f"STAND_CX, STAND_CY = {cx:.1f}, {cy:.1f}   STAND_INNER_R = {r_in:.1f}   (outer {r_out:.1f}, ring {thickness}px, feet at y {art.size[1]})")

os.makedirs(os.path.dirname(OUT_PREVIEW), exist_ok=True)
prev = Image.new("RGBA", canvas.size, (60, 80, 60, 255))
prev.alpha_composite(canvas)
prev.save(OUT_PREVIEW)

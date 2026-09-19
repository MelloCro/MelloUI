"""
Turn docs/minimap-stand.webp (the ring-and-legs artwork, with alpha) into
Media/Textures/MinimapStand.tga, a 1024 x 1024 texture, and print the ring's
centre and inner radius on that canvas: the numbers STAND_CX, STAND_CY and
STAND_INNER_R in Modules/Services.lua.

    python Tools\\extract_minimap_stand.py
"""
import os
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "docs", "minimap-stand.webp")
OUT_TGA = os.path.join(HERE, "..", "Media", "Textures", "MinimapStand.tga")
OUT_PREVIEW = os.path.join(HERE, "output", "minimap-stand-preview.png")
CANVAS = 1024

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

# --- measure the ring on the canvas
mask = np.asarray(canvas)[:, :, 3] > 128
H, W = mask.shape
best = None
for y in range(int(H * 0.05), int(art.size[1] * 0.6)):
    row = np.nonzero(mask[y])[0]
    if len(row) == 0:
        continue
    width = row.max() - row.min()
    if best is None or width > best[0]:
        best = (width, y, row.min(), row.max())
width, cy, xl, xr = best
cx = (xl + xr) / 2
r_out = width / 2
x = xl
while x < cx and mask[cy, x]:
    x += 1
thickness = x - xl
r_in = r_out - thickness
print(f"canvas {CANVAS}x{CANVAS}, art {art.size[0]}x{art.size[1]} at x offset {ox}")
print(f"STAND_CX, STAND_CY = {cx:.1f}, {cy:.1f}   STAND_INNER_R = {r_in:.1f}   (outer {r_out:.1f}, ring {thickness}px, feet at y {art.size[1]})")

os.makedirs(os.path.dirname(OUT_PREVIEW), exist_ok=True)
prev = Image.new("RGBA", canvas.size, (60, 80, 60, 255))
prev.alpha_composite(canvas)
prev.save(OUT_PREVIEW)

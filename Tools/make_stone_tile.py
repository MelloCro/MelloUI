"""
Build Media/Textures/StoneDarkTile.tga, a repeatable dark stone surface,
from docs/stone-dark-tile.png (1586 x 992, wraps as delivered: its edges
differ from each other about as much as neighbouring pixels do). The image
is resized whole to 1024 x 512 (its 1.6 : 1 kept nearer than a square
would), no mirroring, so a texture drawn with "REPEAT" wrap and texture
coordinates past 1 tiles it seamlessly. Painted windows use the same
source at the same scale (see make_professions_frame.py: stone_tile()),
0.75 tile px per frame px.

    python Tools\\make_stone_tile.py
"""
import os
from PIL import Image
from paths import master  # the TGA masters: MelloUI-BuildData/masters/Media

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "docs", "stone-dark-tile.png")
OUT = master("Textures", "StoneDarkTile.tga")  # the TGA master (Tools/paths.py); `texture_pack.py ship` makes what Media ships
TILE_W, TILE_H = 1024, 512

tile = Image.open(SRC).convert("RGBA").resize((TILE_W, TILE_H), Image.LANCZOS)
tile.save(OUT)
print(f"-> {OUT}  ({TILE_W} x {TILE_H})")

"""Media/Textures/Masks/ring_corner.tga: the mask Kit cuts a window's top-left
corner with where the portrait ring sits (white = shown, as the edge masks).
Hidden: a round hole (the ring's body) and the whole quarter above and left
of its centre. Used with CLAMP, so the quarter reaches on past the mask's
square (its top row and left column repeat outward) while everything right of
and below the ring stays shown. The title plate and the outer rail then run
behind the ring, which stands as the window's corner. The hole's edge is
HOLE_R of the half-size, softened over 2 px."""
import os
import numpy as np
from PIL import Image
from paths import master  # the TGA masters: MelloUI-BuildData/masters/Media

SIZE = 128
HOLE_R = 62 / 64      # the hole's radius as a share of the half-size (Kit's RING_HOLE_FILL)
SOFT = 2.0            # px of soft edge

out = master("Textures", "Masks", "ring_corner.tga")  # the TGA master (Tools/paths.py); `texture_pack.py ship` makes what Media ships
c = (SIZE - 1) / 2
y, x = np.mgrid[0:SIZE, 0:SIZE]
r = np.hypot(x - c, y - c)
edge = HOLE_R * SIZE / 2
disc = np.clip((r - (edge - SOFT / 2)) / SOFT, 0, 1)
# the quarter above and left of the centre: hidden (its two straight edges run
# into the disc, so no seam shows past the ring's rim)
quarter = np.minimum(np.clip((x - c) / SOFT + 0.5, 0, 1) + np.clip((y - c) / SOFT + 0.5, 0, 1), 1)
v = np.minimum(disc, quarter)
a = (v * 255).round().astype(np.uint8)
Image.fromarray(np.dstack([a, a, a, a]), "RGBA").save(out)
print("wrote", os.path.normpath(out))

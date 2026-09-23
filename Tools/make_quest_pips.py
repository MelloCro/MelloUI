"""Media/Textures/Quests/pip_fill.tga and pip_ring.tga: the quest difficulty
pips (user, 2026-09-23: quest titles in black ink on parchment, the
difficulty shown by 1 to 5 diamonds, "D"). pip_fill is a white diamond the
game tints with the difficulty's colour; pip_ring its dark ink outline, drawn
over it (an empty pip is the ring alone). Drawn 8x larger and scaled down, so
the edges are smooth."""
import os
from PIL import Image, ImageDraw

SIZE, SS = 32, 8
here = os.path.dirname(os.path.abspath(__file__))
out = os.path.join(here, "..", "Media", "Textures", "Quests")


def diamond(inset):
    big = SIZE * SS
    c = big / 2
    r = c - inset * SS
    return [(c, c - r), (c + r, c), (c, c + r), (c - r, c)]


def save(name, draw):
    big = Image.new("RGBA", (SIZE * SS, SIZE * SS), (0, 0, 0, 0))
    draw(ImageDraw.Draw(big))
    big.resize((SIZE, SIZE), Image.LANCZOS).save(os.path.join(out, name))


INK = (42, 29, 18, 255)
save("pip_fill.tga", lambda d: d.polygon(diamond(4), fill=(255, 255, 255, 255)))
# the outline: an ink diamond with the fill's diamond cut out of it
def ring(d):
    d.polygon(diamond(2), fill=INK)
    d.polygon(diamond(5.2), fill=(0, 0, 0, 0))
save("pip_ring.tga", ring)
print("wrote pip_fill.tga, pip_ring.tga")

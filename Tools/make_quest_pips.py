"""Media/Textures/Quests/pip_fill.tga and pip_ring.tga: the quest difficulty
pips (user, 2026-09-23: quest titles in black ink on parchment, the
difficulty shown by 1 to 5 diamonds, "D"). pip_fill is a white diamond the
game tints with the difficulty's colour; pip_ring its dark ink outline, drawn
over it (an empty pip is the ring alone). Drawn 8x larger and scaled down, so
the edges are smooth.

pip_gem.tga (0.14.0, user 2026-09-26: the class gem before a name in the
chat on parchment): the same gem baked into ONE picture for a text's inline
texture escape (QuestInk's QI.GemCode), which draws one picture and tints all
of it: the white fill with the dark ring over it, so the tint gives the fill
its colour and the ring stays dark. The gem in the left 32 x 32 of a 64 x 32
canvas, the right half empty: the escape takes the gap after the gem from
it."""
import os
from PIL import Image, ImageDraw
from paths import master  # the TGA masters: MelloUI-BuildData/masters/Media

SIZE, SS = 32, 8
out = master("Textures", "Quests")  # the TGA master (Tools/paths.py); `texture_pack.py ship` makes what Media ships


def diamond(inset):
    big = SIZE * SS
    c = big / 2
    r = c - inset * SS
    return [(c, c - r), (c + r, c), (c, c + r), (c - r, c)]


def save(name, draw):
    big = Image.new("RGBA", (SIZE * SS, SIZE * SS), (0, 0, 0, 0))
    draw(ImageDraw.Draw(big))
    small = big.resize((SIZE, SIZE), Image.LANCZOS)
    small.save(os.path.join(out, name))
    return small


INK = (42, 29, 18, 255)
fill = save("pip_fill.tga", lambda d: d.polygon(diamond(4), fill=(255, 255, 255, 255)))
# the outline: an ink diamond with the fill's diamond cut out of it
def ring(d):
    d.polygon(diamond(2), fill=INK)
    d.polygon(diamond(5.2), fill=(0, 0, 0, 0))
ring_img = save("pip_ring.tga", ring)
# the inline gem: the ring laid over the fill (as QI.Gem draws the two), on
# the left of a canvas twice as wide
gem = Image.new("RGBA", (SIZE * 2, SIZE), (0, 0, 0, 0))
gem.paste(Image.alpha_composite(fill, ring_img), (0, 0))
gem.save(os.path.join(out, "pip_gem.tga"))
print("wrote pip_fill.tga, pip_ring.tga, pip_gem.tga")

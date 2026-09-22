"""
Build Media/Textures/GroupFinderFrame.tga from docs/groupfinder-frame.webp:
the 966 x 1024 artwork in the left part of a 1024 x 1024 texture (the Group
Finder module reads the left 966 columns).

    python Tools\\make_groupfinder_frame.py
"""
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "docs", "groupfinder-frame.webp")
OUT = os.path.join(HERE, "..", "Media", "Textures", "GroupFinderFrame.tga")

art = Image.open(SRC).convert("RGBA")
# the third checkbox is painted ticked: cover it with a copy of the first, empty one
empty = art.crop((134, 180, 172, 220))
art.paste(empty, (520, 180))
tex = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
tex.paste(art, (0, 0))
tex.save(OUT)
print(f"{art.size[0]}x{art.size[1]} art in a {tex.size[0]}x{tex.size[1]} texture -> {OUT}")

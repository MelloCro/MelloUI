"""
Build Media/Textures/VoiceOver/ScrollFrame.tga from docs/voiceover-frame.webp:
the 2000 x 668 artwork scaled to 1024 wide in the top rows of a 1024 x 512
texture (the Voice Over module reads the top 342 rows). The speech bubble
painted over the top edge of the parchment is covered with a copy of the
plain frame to its left, so the top of the parchment stays free for text.

    python Tools\\make_voiceover_frame.py
"""
import os
from PIL import Image
from paths import master  # the TGA masters: MelloUI-BuildData/masters/Media

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "docs", "voiceover-frame.webp")
OUT = master("Textures", "VoiceOver", "ScrollFrame.tga")  # the TGA master (Tools/paths.py); `texture_pack.py ship` makes what Media ships
BUBBLE = (1090, 0, 1410, 250)      # where the bubble and its shadow sit on the art
DONOR_X = 760                      # plain frame and parchment of the same rows, to the left

art = Image.open(SRC).convert("RGBA")
w, h = BUBBLE[2] - BUBBLE[0], BUBBLE[3] - BUBBLE[1]
patch = art.crop((DONOR_X, BUBBLE[1], DONOR_X + w, BUBBLE[3]))
# feathered edges so the copied parchment blends into the surrounding grain
from PIL import ImageDraw, ImageFilter
mask = Image.new("L", (w, h), 0)
ImageDraw.Draw(mask).rectangle((18, 0, w - 19, h - 19), fill=255)
mask = mask.filter(ImageFilter.GaussianBlur(9))
art.paste(patch, (BUBBLE[0], BUBBLE[1]), mask)
scaled = art.resize((1024, round(art.size[1] * 1024 / art.size[0])), Image.LANCZOS)
tex = Image.new("RGBA", (1024, 512), (0, 0, 0, 0))
tex.paste(scaled, (0, 0))
tex.save(OUT)
print(f"{scaled.size[0]}x{scaled.size[1]} art in a {tex.size[0]}x{tex.size[1]} texture -> {OUT}")

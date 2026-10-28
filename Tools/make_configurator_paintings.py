"""The configurator's paintings (1.2.4; docs/plans/configurator-shell.md): one painting a skin, the window's whole
ground -- the side column, the header, the content and the footer with their lines and the crest's ring painted in.

Each source is ChatGPT's 1536 x 1024 painting (MelloUI-BuildData/output/ai_art/configurator_bg, the user's picks of
2026-10-27, toned down): it goes into the left three quarters of a 2048 x 1024 canvas (a power of two each way), drawn
at 1140 x 760 in the window (texture coordinates 0..0.75 across, never drawn bigger than its file at the UI's usual
scales). Writes Media/Textures/Configurator/Painting_<Skin>.tga.

    python Tools/make_configurator_paintings.py
"""
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "Workspace", "BuildData", "output", "ai_art", "configurator_bg")
OUT = os.path.join(ROOT, "Media", "Textures", "Configurator")
PAINTINGS = {
    "Modern": "configurator_bg_modern_v3_calm.png",
    "Default": "configurator_bg_default_v2.png",
    "Oldschool": "configurator_bg_oldschool_v2.png",
}
CANVAS = (2048, 1024)
SIZE = (1536, 1024)


def main():
    os.makedirs(OUT, exist_ok=True)
    for skin, name in PAINTINGS.items():
        im = Image.open(os.path.join(SOURCE, name)).convert("RGB")
        if im.size != SIZE:
            im = im.resize(SIZE, Image.LANCZOS)
        canvas = Image.new("RGB", CANVAS, (0, 0, 0))
        canvas.paste(im, (0, 0))
        # (the painting's right column repeated into the spare quarter: no dark seam if a filter ever reads past 0.75)
        edge = im.crop((SIZE[0] - 1, 0, SIZE[0], SIZE[1])).resize((CANVAS[0] - SIZE[0], SIZE[1]))
        canvas.paste(edge, (SIZE[0], 0))
        path = os.path.join(OUT, "Painting_%s.tga" % skin)
        canvas.save(path)
        print(path, os.path.getsize(path) // 1024, "KB")


if __name__ == "__main__":
    main()

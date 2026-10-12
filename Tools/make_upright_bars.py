"""
make_upright_bars.py -- a bar bracket stood upright, for an upright bar (0.21.0: the Personal Display's shield column,
docs/plans/personal-display.md; the user's pick A of personal_display_sketch: the unit frames' gem-capped bracket).

  bars/framev_cap_t    the bracket's right cap turned a quarter left: its gem on top
  bars/framev_mid      the bracket's middle turned a quarter left (tiles in y)
  bars/framev_cap_b    the bracket's left cap turned a quarter left: its gem at the bottom
  bars/castbarv_*      (0.21.0, the Personal Resource Border: the column in every bar look) the cast bar's bracket the
                       same; the thin rims' upright pieces are build_kit.py's own (barv:), made with their bars

A turn a quarter left (PIL's rotate(90)): a piece's pixel (x, y) lands on (y, w - 1 - x). Kit:VBar reads the opening
from the horizontal pieces they were turned from (an upright middle is open end to end: build_kit.py's opening() reads
none). Writes into pack_sources and its manifest (the same scale as the pieces turned); then build_kit.py, texture_pack.py
ship (a full client restart: new textures).

    python Tools/make_upright_bars.py
"""
import json
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
KIT = os.path.join(HERE, "pack_sources", "kit", "v2_2x")
MANIFEST = os.path.join(KIT, "manifest.json")

# upright piece -> the horizontal piece it is turned from
TURNS = {
    "bars/framev_cap_t": "bars/frame_cap_r",
    "bars/framev_mid": "bars/frame_mid",
    "bars/framev_cap_b": "bars/frame_cap_l",
    "bars/castbarv_cap_t": "bars/castbar_cap_r",
    "bars/castbarv_mid": "bars/castbar_mid",
    "bars/castbarv_cap_b": "bars/castbar_cap_l",
}


def main():
    man = json.load(open(MANIFEST, encoding="utf-8"))
    for name, src in TURNS.items():
        im = Image.open(os.path.join(KIT, src + ".png")).convert("RGBA")
        up = im.rotate(90, expand=True)
        up.save(os.path.join(KIT, name + ".png"))
        old = man.get("v2_2x/" + src, {})
        man["v2_2x/" + name] = {"w": up.width, "h": up.height, "scale": old.get("scale", 1),
                                "src": "%s turned a quarter left (Tools/make_upright_bars.py)" % src}
        print("%-20s %dx%d  (from %s)" % (name, up.width, up.height, src))
    with open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump(man, f, indent=1, sort_keys=True)


if __name__ == "__main__":
    main()

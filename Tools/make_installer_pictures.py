"""The installer's pictures (1.2.4; the user, 2026-10-28: "here i have taken and labled pictures for the Installer,
everything else does not need the picture"). A build tool (Tools/ never ships); then python Tools/texture_pack.py ship.

The user's own pictures, six per skin, kept as they came in MelloUI-BuildData/masters/installer_pictures
(<Skin>UI<part>.png, Skin: Default, Modern, OldSchool). Each becomes one file of Media/Installer, the picture at its
top left of a power-of-two canvas (black, opaque: the rest is never drawn):
  <Skin>UI.png                                 look_<skin>             the Skin step (the whole UI)
  <Skin>UI_PartyFrames.png                     party_portraits_<skin>  Party and raid: Portraits
  <Skin>UI_Nameplates.png                      nameplates_<skin>       Combat (its Nameplates)
  <Skin>UI_Chat.png                            chat_<skin>             Chat: MelloUI's chat view
  <Skin>UI_Minimap_Services_QuestTracker.png   column_<skin>           Minimap and widgets
  <Skin>UI_Backpack.png                        bags_<skin>             Bags: the bag window by kind
Every other card and step has none. The cut-outs keep their own size; the whole UI is made SCREEN_W wide (its shape
kept: wider than any screen draws the Skin step's picture). Core/InstallerWindow.lua draws each at most at its own
size on screen (never bigger than its file) and knows each file's sizes from its PICTURE_SIZE table, which --check
compares with what this tool makes.
Written as 32-bit TGA masters into MelloUI-BuildData/masters/Media/Installer (--write; any other master there is named,
never deleted: the pictures of before were moved to MelloUI-BuildData/scrapped/installer_pictures_old_2026-10-28);
PNG previews into --out.

    python Tools/make_installer_pictures.py [--out DIR] [--write] [--check]
"""
import argparse
import os
import re
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import paths as P  # noqa: E402  (Tools/paths.py: where the build data lives)

BUILD = os.environ.get("MELLOUI_BUILD_DATA", "").strip() or P.SIBLING
SOURCE = os.path.join(BUILD, "masters", "installer_pictures")
MASTERS = os.path.join(BUILD, "masters", "Media", "Installer")
OUT = os.path.join(BUILD, "output", "installer_pictures")
WINDOW = os.path.join(os.path.dirname(HERE), "Core", "InstallerWindow.lua")
SKINS = {"default": "DefaultUI", "modern": "ModernUI", "oldschool": "OldSchoolUI"}
PARTS = {"look": "", "party_portraits": "_PartyFrames", "nameplates": "_Nameplates", "chat": "_Chat",
         "column": "_Minimap_Services_QuestTracker", "bags": "_Backpack"}
SCREEN_W = 1820   # the whole UI's width in its file (16:9: 1820 x 1024, in a 2048 x 1024 canvas)


def pot(n):
    p = 1
    while p < n:
        p *= 2
    return p


def made():
    """name -> (the picture, its canvas size)"""
    out = {}
    for skin, prefix in SKINS.items():
        for name, part in PARTS.items():
            im = Image.open(os.path.join(SOURCE, prefix + part + ".png")).convert("RGB")
            if name == "look":
                im = im.resize((SCREEN_W, round(im.size[1] * SCREEN_W / im.size[0])), Image.LANCZOS)
            out["%s_%s" % (name, skin)] = (im, (pot(im.size[0]), pot(im.size[1])))
    return out


def canvas(im, size):
    c = Image.new("RGBA", size, (0, 0, 0, 255))
    c.paste(im.convert("RGBA"), (0, 0))
    return c


def window_sizes():
    """InstallerWindow.lua's PICTURE_SIZE: name -> (w, h, canvas w, canvas h)"""
    src = open(WINDOW, encoding="utf-8").read()
    block = src[src.index("local PICTURE_SIZE = {"):]
    block = block[:block.index("\n\t}")]
    return {m[0]: tuple(int(v) for v in m[1:])
            for m in re.findall(r"(\w+) = \{ (\d+), (\d+), (\d+), (\d+) \}", block)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=OUT, help="the PNG previews (default %s)" % OUT)
    ap.add_argument("--write", action="store_true", help="the TGA masters into %s" % MASTERS)
    ap.add_argument("--check", action="store_true", help="only compare InstallerWindow.lua's PICTURE_SIZE")
    args = ap.parse_args()
    pictures = made()
    sizes = {n: (im.size[0], im.size[1], c[0], c[1]) for n, (im, c) in pictures.items()}
    if args.check:
        have = window_sizes()
        if have != sizes:
            for n in sorted(set(have) | set(sizes)):
                if have.get(n) != sizes.get(n):
                    print("%-26s window %s, files %s" % (n, have.get(n), sizes.get(n)))
            sys.exit(1)
        print("PICTURE_SIZE matches the %d pictures" % len(sizes))
        return
    os.makedirs(args.out, exist_ok=True)
    for name, (im, _) in pictures.items():
        im.save(os.path.join(args.out, name + ".png"))
    if args.write:
        os.makedirs(MASTERS, exist_ok=True)
        for name, (im, size) in pictures.items():
            canvas(im, size).save(os.path.join(MASTERS, name + ".tga"))
        # (never deleted here: the build data keeps scrapped work -- moved out by hand, MelloUI-BuildData/scrapped)
        other = sorted(f for f in os.listdir(MASTERS)
                       if f.lower().endswith(".tga") and os.path.splitext(f)[0] not in pictures)
        if other:
            print("not made by this tool, still in %s (texture_pack ships them): %s" % (MASTERS, ", ".join(other)))
    for name in sorted(sizes):
        print("\t\t%s = { %d, %d, %d, %d }," % ((name,) + sizes[name]))
    print("%d pictures -> %s%s" % (len(pictures), args.out, (" and " + MASTERS) if args.write else ""))


if __name__ == "__main__":
    main()

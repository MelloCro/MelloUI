"""The installer's step pictures (1.2.4; the user, 2026-10-26: "every skin should also be acompanied by a picture how
that looks, and so on for every other feature"; "Maybe have like 1 preview picture on top of the 3 choices, the picture
changes depending on which skin is selected"). A build tool (Tools/ never ships); then python Tools/texture_pack.py ship.

The scenes are the simulator's (wowsim, its forest-road scene, our painted portraits and minimap: the game's servers
were offline when they were taken), four per skin, 1920 x 1080, kept in MelloUI-BuildData/output/installer_pictures/
shots as pic_<scene>_<skin>.png:
  look           the plain screen
  combat         a fight: the target, the meter, the damage line
  features       the party preview (Group Frames), the bag window, Chat View
  gamechatbags   the game's own chat and its combined backpack (Chat View and the bag window off)
Each picture is cut from one scene and written into a 1024 x 512 file at its top left (Core/InstallerWindow.lua draws
that part):
  look_<skin>    the whole screen, 910 x 512 (16:9): the Skin step's picture
  <name>_<skin>  a 2.5:1 band of the screen, 1024 x 410: every other step's
Written as 32-bit TGA masters into MelloUI-BuildData/masters/Media/Installer (opaque: no colour to bleed).

    python Tools/make_installer_pictures.py [--write]   (without --write: only MelloUI-BuildData/output/installer_pictures)
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import paths as P  # noqa: E402  (Tools/paths.py: where the build data lives)

BUILD = os.environ.get("MELLOUI_BUILD_DATA", "").strip() or P.SIBLING
SHOTS = os.path.join(BUILD, "output", "installer_pictures", "shots")
OUT = os.path.join(BUILD, "output", "installer_pictures")
MASTERS = os.path.join(BUILD, "masters", "Media", "Installer")
SKINS = ("default", "modern", "oldschool")
FILE = (1024, 512)
SCREEN = (910, 512)    # the Skin step's picture (16:9), its file's top left
BAND = (1024, 410)     # every other step's (2.5:1)
# name -> (scene, crop box in the 1920 x 1080 scene: left, top, right, bottom; 2.5:1)
BANDS = {
    "party_group": ("features", (0, 130, 1000, 530)),
    "party_portraits": ("look", (150, 410, 800, 670)),
    "quests": ("look", (1270, 250, 1920, 510)),
    "column": ("look", (1270, 20, 1920, 280)),
    "combat": ("combat", (420, 640, 1500, 1072)),
    "chat": ("look", (0, 740, 650, 1000)),
    "chatgame": ("gamechatbags", (0, 700, 650, 960)),
    "bags": ("features", (1130, 662, 1920, 978)),
    "bagsgame": ("gamechatbags", (1100, 640, 1800, 920)),
}


def scene(name, skin):
    return Image.open(os.path.join(SHOTS, "pic_%s_%s.png" % (name, skin))).convert("RGB")


def into_file(im):
    canvas = Image.new("RGBA", FILE, (0, 0, 0, 255))
    canvas.paste(im.convert("RGBA"), (0, 0))
    return canvas


def main():
    write = "--write" in sys.argv[1:]
    made = {}
    for skin in SKINS:
        made["look_" + skin] = into_file(scene("look", skin).resize(SCREEN, Image.LANCZOS))
        for name, (sc, box) in BANDS.items():
            w, h = box[2] - box[0], box[3] - box[1]
            assert abs(w / h - BAND[0] / BAND[1]) < 0.01, (name, w, h)
            made["%s_%s" % (name, skin)] = into_file(scene(sc, skin).crop(box).resize(BAND, Image.LANCZOS))
    os.makedirs(OUT, exist_ok=True)
    for name, im in made.items():
        im.convert("RGB").save(os.path.join(OUT, name + ".png"))
    if write:
        os.makedirs(MASTERS, exist_ok=True)
        for name, im in made.items():
            im.save(os.path.join(MASTERS, name + ".tga"))
    print("%d pictures -> %s%s" % (len(made), OUT, (" and " + MASTERS) if write else ""))


if __name__ == "__main__":
    main()

"""
Build the small copies of MelloUI's icons (2026-10-21; the user: "all icons and its borders should always stay smooth"):
for every icon file of the families below, one sheet of copies, each made for its size (Tools/icon_sizes.py), at
Media/IconSizes/<the file's folder>/<name>.tga, and Media/IconSizes.lua, the sheets' layouts and each file's size,
which MelloUI.Icons (Core/Icons.lua) reads to draw the copy made for an icon's size on screen.

The families (Media-relative folder, where the big art comes from):
  Textures/Icons   MelloUI's icon set: each icon's own art (Tools/make_icons.py bigs(): the 128 px cuts, the drawn
                   discs at 128 or 256), so a copy is made from twice its file's detail or more
  Icons/Class      the class medallions and their plain ones (128 px masters, MelloUI-BuildData/masters/Media/...)
  Icons/Faction    the faction medallions (128 px masters)
Deterministic: the same art gives the same bytes. The sheets ship as they are written (TGA: their soft edges band as
DXT), like Media/Textures/Icons/Halo; Tools/texture_pack.py never sees them (they have no masters).

    python Tools/make_icon_sizes.py            write them
    python Tools/make_icon_sizes.py --check    exit 1 unless all are up to date
    python Tools/make_icon_sizes.py --set oldschool [--check]   a look's own set (Tools/make_icons.py LOOK_SETS): its
        pictures' sheets at <its addon's Media>/IconSizes/Icons/<name>.tga and <its addon's Media>/IconSizes.lua, which
        registers the set with MelloUI.Icons as the addon loads (Icons.AddSet: its root, area, square, halos, sheets,
        files) -- run after make_icons.py --set
"""
import hashlib
import io
import os
import struct
import sys

from PIL import Image

import icon_sizes
import make_icons
from paths import ADDON_MEDIA, master

OUT = "IconSizes"
LUA = os.path.join(ADDON_MEDIA, "IconSizes.lua")


def shipped_width(path):
    """a shipped texture's width: a TGA's, or a BLP2's from its header"""
    if path.lower().endswith(".blp"):
        with open(path, "rb") as f:
            head = f.read(20)
        return struct.unpack("<I", head[12:16])[0]
    return Image.open(path).width


def medallions(folder):
    """the shipped medallions of Media/<folder>, their art their masters (as big as the file or bigger):
    [(name, picture, the shipped file's size)]"""
    here = os.path.join(ADDON_MEDIA, *folder.split("/"))
    out = []
    for f in sorted(os.listdir(here)):
        name, ext = os.path.splitext(f)
        if ext.lower() not in (".tga", ".blp"):
            continue
        img = Image.open(master(*folder.split("/"), name + ".tga")).convert("RGBA")
        out.append((name, img, shipped_width(os.path.join(here, f))))
    return out


def families():
    return [("Textures/Icons", make_icons.bigs()), ("Icons/Class", medallions("Icons/Class")),
            ("Icons/Faction", medallions("Icons/Faction"))]


def tga(img):
    buf = io.BytesIO()
    img.save(buf, format="TGA")
    return buf.getvalue()


def main():
    look, args = make_icons.look_arg(sys.argv[1:])
    bad = [a for a in args if a != "--check"]
    if look is not None and look not in make_icons.LOOK_SETS:
        bad.append("--set " + look)
    if bad:
        print("unknown argument: %s (nothing written)\n" % " ".join(bad))
        print(__doc__[__doc__.index("    python Tools/"):].rstrip())
        return 2
    check = "--check" in args
    layout = icon_sizes.check_layouts()
    if layout:
        print("the sheets' layouts:", "; ".join(layout))
        return 1
    media, lua, fams = ADDON_MEDIA, LUA, None
    if look:
        spec = make_icons.LOOK_SETS[look]
        media, lua = spec["addon"], os.path.join(spec["addon"], "IconSizes.lua")
        fams = [("Icons", make_icons.look_bigs(look))]
    stale, sums, files = [], hashlib.sha256(), {}
    writes = []
    for folder, icons in fams or families():
        for name, img, size in icons:
            if size not in icon_sizes.SHEET:
                print("no sheet for a %s px file: %s/%s" % (size, folder, name))
                return 1
            fw, fh = icon_sizes.dims(size)
            if img.width * fh != img.height * fw or img.width < fw:
                print("%s/%s: its art (%d x %d) is not its file's shape or smaller" % (folder, name, *img.size))
                return 1
            files[folder.replace("/", "\\") + "\\" + name] = size
            data = tga(icon_sizes.sheet(img, size))
            sums.update(name.encode() + data)
            writes.append((os.path.join(media, OUT, *folder.split("/"), name + ".tga"), data))
    if look:
        spec = make_icons.LOOK_SETS[look]
        halos = sorted(name for name, _img in make_icons.look_halos(look))
        writes.append((lua, icon_sizes.lua_set_layout(files, look, spec, halos).encode("utf-8")))
    else:
        writes.append((LUA, icon_sizes.lua_layout(files).encode("utf-8")))
    for path, data in writes:
        if check:
            try:
                with open(path, "rb") as f:
                    if f.read() != data:
                        stale.append(path)
            except OSError:
                stale.append(path)
            continue
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)
    if check:
        for path in stale:
            print("stale:", os.path.normpath(path))
        print("ok" if not stale else "STALE")
        return 1 if stale else 0
    print("%d icons' sheets written (%s) and %s, sha256 %s"
          % (len(files), os.path.normpath(os.path.join(media, OUT)), os.path.normpath(lua), sums.hexdigest()[:16]))
    return 0


if __name__ == "__main__":
    sys.exit(main())

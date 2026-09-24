"""
texture_pack.py -- MelloUI's TGA art as BLP2 / DXT textures: build, verify,
measure, atlas and side-by-side samples, and the step that makes the addon's
Media from the masters.

A build tool (Tools/ never ships). The TGA MASTERS live outside the addon
(Tools/paths.py: MelloUI-BuildData/masters/Media; user, 2026-09-24): every
tool that paints art writes them there, and they are never shipped.

  python Tools/texture_pack.py ship                   THE build step: the masters -> Media
                                                      (option d, below; --check: only say
                                                      what would change, exit 1 if anything)

`ship` builds option d from the masters into a staging folder
(MelloUI-BuildData/output/texture_ship), verifies every file (and every path
the layout, the slices and the Lua name), and only then brings the addon's
Media in line with it: each file written where its bytes differ, the files
it shipped before and no longer makes removed, Media/KitLayout.lua (the
sheets' files and uvs) and Media/KitSlices.lua written. It writes nowhere
else in the addon, never into the masters, and touches no file in Media it
did not make (VoiceOver's BLPs, Media/CustomTextures.lua's user files): a
file there it would replace or remove must be one it shipped (its own
record), a copy of its master, or a BLP / atlas sheet only it writes, or it
stops without changing anything. Deterministic: the same masters give the
same bytes, so a second run changes nothing.

The other commands write only under --out (the comparisons the choice of d
was made on):

  python Tools/texture_pack.py all --out DIR          a, b, c, d, the samples and the probe
  python Tools/texture_pack.py convert --out DIR      option a: every TGA as a BLP at its size
  python Tools/texture_pack.py rightsize --out DIR    option b: a + files sized to what the screen shows
  python Tools/texture_pack.py atlas --out DIR        option c: b + the small kit pieces in DXT sheets
  python Tools/texture_pack.py recommended --out DIR  option d: c behind the quality gate
  python Tools/texture_pack.py verify --out DIR       every file under DIR re-read (Pillow and blp_dxt)
  python Tools/texture_pack.py samples --out DIR      PNG side-by-sides (original / BLP / difference)
  python Tools/texture_pack.py probe --out DIR        diagnostic BLPs for the in-game test
Options: --jobs N (processes), --effort 0..3 (encoder search; 2 default),
         --only REGEX (Media-relative paths, for a quick run; not for ship),
         --src DIR (the TGA tree to read; default the masters),
         --gate-psnr DB / --gate-p999 N (option d's gate, to see what a
         looser or stricter one costs; not for ship).

What stays TGA in option d (and so in Media):
  STAY_TGA   the bar fills (paths saved in profiles, 4-8 KB) and LogoIcon
             (the TOC's IconTexture and Core/Config.lua name it LogoIcon.tga):
             their masters' bytes, as they are
  '.tga'     any file a Lua or TOC path names WITH '.tga' (the client then
             loads that file only): found by scanning the addon's Lua
             (lua_refs); a path built at run time is listed in DYNAMIC_PATHS,
             and a '.tga' the scan cannot account for stops the ship
  the gate   a file, or an atlas piece in its sheet, whose DXT fails the
             quality gate below: a TGA at its right size (the pieces in
             uncompressed sheets, <look>/atlas/sheethq_*, pictureshq_*)
Media/CustomTextures.lua's user files are not masters: never touched.
NOT_SHIPPED masters (nothing in the addon names them) are not shipped at
all; a copy shipped before is removed.

Per file (Media-relative path, e.g. KitWarm/window/frame_t.tga):
  format  alpha all 255 -> DXT1 (alpha depth 0); alpha only 0 / 255 -> DXT1
          with 1-bit alpha; anything else (anti-aliased edges, soft shadows,
          masks) -> DXT5, its colour under alpha 0 bled first (blp_dxt).
  mips    written where the file is drawn at 1 / MIP_AT of its size or
          smaller on the reference screen, or at sizes that vary (the route
          beam on the map); complete chains, down to 1 x 1. A UI texture
          drawn near 1:1 gains nothing from mips but +33 % memory.

Quality is measured on what is DRAWN, never on canvas padding:
  drawn    a kit piece's uv rectangle (Media/KitLayout.lua); the rectangle a
           module's texcoords draw of a whole file (TEX_DRAWN); an atlas
           piece's own rectangle in its sheet. The colour error is on
           premultiplied RGB (what is blended onto the screen), each texel
           weighted by its alpha (the larger of source and decode), so
           transparent texels and padding count for nothing -- a piece's box
           is where its weight is. The alpha error covers the texels where
           either side shows.
  display  at the size the reference screen draws it, through a GPU model:
           bilinear with straight alpha (the RGB is filtered before the
           alpha, as the client blends), from the mip levels a GPU picks
           (trilinear: the two levels round the minification, blended),
           compared with the same sampling of the uncompressed levels. A file
           with mips is also measured from level 0 alone, in case the client
           ignores mips. A file drawn at its size or larger is measured at its
           own resolution.
  dark     colour drift on dark opaque texels (luminance < DARK_LUM: the
           stone, a rail's dark edge line), at display size: the mean per
           channel over the piece, and the largest per-channel mean in any
           DARK_WIN x DARK_WIN area (a dark line beside a red plate turning
           red).
The gate (option d) holds all of them: GATE_PSNR / GATE_P999 on the display
error (both models for a file with mips), GATE_DARK_BIAS / GATE_DARK_LOCAL
on the drift. A file, or an atlas piece measured in its own sheet, that
fails any of them stays uncompressed.

Screen model: a file pixel covers `upp` UI units on screen (the kit:
build_kit.py's density audit, "N px shown at M"; the rest: the sizes their
modules draw them at), and a UI unit is screen_height * uiScale / 768 screen
pixels. The reference screen is the user's client (Config.wtf: 3440 x 1440,
uiScale 0.70 -> 1.31 screen px per UI unit).

Kit tuning: a `pieces` override in Media/KitTuning.lua of uv, file or tile
is written against the piece's own file; such pieces (and the pieces whose
file an override points at) are never put in a sheet, so the override keeps
meaning what it meant. Every atlased or right-sized piece carries `was` in
the layout it writes (the shipped Media/KitLayout.lua too) -- its uv in its
former own file -- for the runtime remap of live overrides made in game
(Modules/Kit.lua's Kit:ApplyTuning). Each option's layout is tested here
against that code itself, in Lua 5.1 (test_tuning_remap: the overrides land
on the same art, a second application gives the same pieces as the first);
a failed check stops the ship.

One-texture nine-slices: Media/KitSlices.lua (Tools/build_nineslice.py)
records the file, w, h and uv of each rail family's eight pieces, and
Kit.lua's SliceFamily draws a family as one picture only while its pieces
still match that record. Those pieces are therefore never atlased or
right-sized (their files and uvs stay as recorded), and the pictures
(<look>/slices/*.tga) are measured on their grid at the rails' density and
never right-sized (their margins are in the file's texels).
"""
import argparse
import csv
import json
import math
import os
import re
import shutil
import sys
import time
from concurrent.futures import ProcessPoolExecutor

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import blp_dxt  # noqa: E402
from paths import ADDON_MEDIA, MASTER_MEDIA, OUTPUT  # noqa: E402

ROOT = os.path.dirname(HERE)
MEDIA = MASTER_MEDIA                                  # the TGA tree the options are made from (--src)
LAYOUT_LUA = os.path.join(MEDIA, "KitLayout.lua")     # build_kit.py's: each piece in its own file
TUNING_LUA = os.path.join(ADDON_MEDIA, "KitTuning.lua")   # the shipped tuning (kitforge writes it)
SLICES_LUA = os.path.join(MEDIA, "KitSlices.lua")     # build_nineslice.py's
SHIP_DIR = os.path.join(OUTPUT, "texture_ship")       # ship's staging tree, report and record
LOOKS = ("Kit", "KitWarm", "KitBronze")
SKIP_DIRS = ("Fonts", "Sounds")

# screen px per UI unit
DISPLAYS = [
    ("1440p_ui070", "1440 px tall, uiScale 0.70 (this client)", 1440 * 0.70 / 768),
    ("1440p_ui100", "1440 px tall, uiScale 1.00", 1440 * 1.00 / 768),
    ("4k_ui070", "2160 px tall, uiScale 0.70", 2160 * 0.70 / 768),
    ("4k_ui100", "2160 px tall, uiScale 1.00", 2160 * 1.00 / 768),
]
TARGET = DISPLAYS[0][2]
MIP_AT = 1.5                 # file px per screen px at which mips start to pay
MINIFY_AT = 1.05             # drawn smaller than this: measured through the display model

# The kit: UI units per PAINTED (2x) px, from build_kit.py's density audit
# (its DENSITY comments: "<painted> px shown at <UI units>"). First match wins.
KIT_SHOWN = [
    (r"^window/single_body$", 307 / 512, "512 px stone shown at 307 per repeat"),
    (r"^window/single_", 6.6 / 11, "11 px rails shown at 6.6"),
    (r"^window/portrait_ring$", 95 / 197, "197 px ring shown at 95"),
    (r"^window/frame_gem_", 60 / 160, "160 px gem corners shown at 60"),
    (r"^window/", 19 / 50, "50 px edges shown at 19"),
    (r"^buttons/checkbox_", 26 / 43, "43 px shown at 26"),
    (r"^buttons/cog_", 23 / 50, "50 px shown at 23"),
    (r"^buttons/(redbtn|textbtn)_", 24 / 89, "89 px plates shown at 24"),
    (r"^buttons/arrow_", 16 / 44, "44 px arrows shown at 16"),
    (r"^buttons/close_", 24 / 64, "64 px close shown at 24"),
    (r"^buttons/", 51 / 135, "135 px slot rims shown at 48-55"),
    (r"^lists/(catplate|category)_", 25 / 101, "101 px plates shown at 25"),
    (r"^lists/row_", 25 / 71, "71 px plates shown at 25"),
    (r"^lists/scrollthumb", 10 / 33, "33 px thumb shown at 10"),
    (r"^lists/", 27 / 76, "row plates 71 at 24-30, headers 82 at 20-29"),
    (r"^bars/trough_v$", 8 / 41, "41 px shown at 8"),
    (r"^bars/", 26 / 64, "64 px brackets shown at 23-29"),
    (r"^tabs/", 30 / 89, "89 px title plate shown at 30"),
    (r"^inputs/", 20 / 57, "57 px plates shown at 20"),
    (r"^tiles/", 192 / 512, "512 px tile shown at 192 per repeat"),
    (r"^deco/gem", 12 / 25, "25 px gems shown at 9-15"),
    (r"^backdrops/page_stone$", 669 / 1024, "1024 px shown at 669"),
    (r"^backdrops/page_parchment$", 806 / 1024, "1024 px shown at 806"),
    (r"^backdrops/profession_(cooking|fishing|firstaid)", 225 / 512, "512 px shown at 225"),
    (r"^backdrops/", 360 / 352, "352 px panels shown at 360"),
    (r"^icons/", 62 / 192, "192 px round icons shown at 62"),
    (r"^cards/mining$", 531 / 1024, "1024 px shown at 531"),
    (r"^cards/", 531 / 804, "804 px shown at 531"),
    (r"", 0.375, "Kit.scale (0.375 UI units per painted px)"),
]

# Everything else: UI units per FILE px (None: not known / varies), whether
# mips are forced, and where the size comes from.
TEX_SHOWN = [
    (r"^Textures/GameMenuFrame", 340 / 910, False, "GameMenuPanel: 910 px art in a 340-unit frame"),
    (r"^Icons/", 62 / 256, False, "class / faction medallions in the 62-unit portrait"),
    (r"^Textures/LogoIcon", 64 / 256, False, "logo: 16-64 units (addon list, configurator)"),
    (r"^Textures/Quests/pip_", 11 / 32, False, "QuestInk.Pips: 11 units"),
    (r"^Textures/Quests/tag_classic", 12 / 32, False, "QuestList logo: 12 units tall"),
    (r"^Textures/Quests/tag_forever", 20 / 64, False, "QuestList logo: 20 units tall"),
    (r"^Textures/VoiceOver/ScrollFrame", 600 / 1024, False, "VoiceOver: 1024 px art in a 600-unit frame"),
    (r"^Textures/Masks/", 1.0, False, "masks: at least 512 units for 512 px"),
    (r"^Textures/(Flat|Smooth|Gloss|Minimalist)", 4.0, False, "bar fills: stretched along the bars"),
    (r"^Textures/Chat/", 4.0, False, "chat name band: stretched behind a name"),
    (r"^Textures/Route/", None, True, "route beam: any world map zoom"),
    (r"^Textures/Stone", None, False, "not referenced by any Lua file"),
]

# The part of a whole file a module draws (its texcoords), as fractions of
# the file (so a halved file keeps them); the rest is never on screen.
TEX_DRAWN = [
    (r"^Textures/GameMenuFrame", (910 / 1024, 1728 / 2048), "GameMenuPanel TEX_RIGHT / TEX_BOTTOM"),
    (r"^Textures/VoiceOver/ScrollFrame", (1.0, 342 / 512), "VoiceOver TEX_BOTTOM"),
    (r"^Textures/Quests/tag_classic", (278 / 512, 1.0), "QuestList logo w / fw"),
    (r"^Textures/Quests/tag_forever", (255 / 256, 1.0), "QuestList logo w / fw"),
]
# whole files drawn with a repeating wrap (SetTexture's wrap arguments)
TEX_WRAP = [(r"^Textures/Route/beam_streaks", "y")]

ATLAS_MAX_SIDE = 256          # pieces up to this (file px, after right-sizing) go in sheets
KIT_MIN_SHRINK = 0.8          # a kit piece is right-sized only by this factor or more

# The quality gate of option d, at the size the reference screen draws the
# file: below it DXT's four-colours-per-block shows (a rail's dark edge line
# tinted by the red plate beside it, block noise on a 16 px arrow), and the
# file or piece stays an uncompressed TGA.
GATE_PSNR = 33.0              # dB, premultiplied RGB, alpha-weighted, drawn texels only
GATE_P999 = 48.0              # 99.9th percentile (alpha-weighted) of the per-texel error, 0..255
GATE_DARK_BIAS = 4.0          # levels: mean drift of any channel over the dark opaque texels
GATE_DARK_LOCAL = 16.0        # levels: ... over the dark texels of any DARK_WIN x DARK_WIN area
DARK_LUM = 64                 # "dark": luminance under this, alpha >= 250
DARK_MIN_PX = 16              # a piece needs this many dark texels for the drift to count
DARK_WIN = 8
DARK_WIN_MIN = 8              # ... and an area this many
# ... and files that stay TGA whatever the gate says: shipped as their
# masters are, byte for byte (not right-sized)
STAY_TGA = [
    (r"^Textures/(Flat|Smooth|Gloss|Minimalist)\.tga$", "bar fills: 4-8 KB, stretched along bars (565 banding), paths saved in profiles"),
    (r"^Textures/LogoIcon\.tga$", "addressed as LogoIcon.tga by Core/Config.lua and the TOC's IconTexture; 256 KB, loaded once"),
]
# Media paths the Lua builds at run time, which lua_refs cannot follow: the
# file it is in, the known start of the path (Media-relative, no extension)
# -> the endings the rest can add. A '.tga' written after such a path pins
# every file it can name to TGA; lua_refs lists every other built path it
# meets (they are checked by hand), and stops the ship at a '.tga' it can
# not account for.
DYNAMIC_PATHS = {
    ("Modules/GameMenuPanel.lua", "Textures/GameMenuFrame"): ("", "_warm", "_bronze"),   # TextureFile(): LOOK_SUFFIX[look]
}
# Paths the Lua finishes at run time from a table's values: (the file the
# values are written in, a pattern for a value's Media-relative path) -> the
# endings the code adds. Each such value also names value + ending, which
# must ship like any other path.
VALUE_ENDINGS = {
    ("Media/ClassIcons.lua", r"^Icons/Class/[A-Z]+$"): ("_plain",),   # MelloUI:ClassIconPath(class, "plain")
}
# Masters that never ship: no layout piece, KitSlices picture, Lua or TOC
# path names them (review, 2026-09-24). They stay in the masters for the
# tools; the ship removes the copy it shipped before, and a path the addon
# starts to write to one of them stops the ship (check_refs: missing).
NOT_SHIPPED = [
    (r"^Kit/tiles/crackle\.tga$", "a page stone tried and rejected (docs/KIT-MAPPING.md); no layout piece"),
    (r"^Textures/(StoneTile|StoneDarkTile)\.tga$", "the tile makers' stone bodies; no Lua path names them"),
    (r"^Icons/Class/unmapped_\d+\.tga$", "a medallion extract_icons.py cut but mapped to no class"),
]
# Lua files that list the user's own files (dropped into Media, never masters)
USER_FILE_LISTS = ("Media/CustomTextures.lua", "Media/CustomFonts.lua")
ATLAS_SHEET = 1024
ATLAS_PAD = 2                 # extruded edge px after each piece (and before it in an uncompressed sheet)
BLOCK = 4                     # a DXT sheet puts each piece's first texel on the block grid
GATE_ROUNDS = 6               # atlas re-packs while a piece fails in its sheet
DARK = (0x1F, 0x1B, 0x16)     # MelloUI.Palette.mainWindow
MASKS = ["Textures/Masks/edge_brush_%s" % k for k in ("tl", "br", "fine_tl", "fine_br", "wide_tl", "wide_br")]
MIB = float(1 << 20)


# ---------------------------------------------------------------- helpers

def pot_up(n):
    return 1 << max(0, math.ceil(math.log2(max(n, 1))))


def ceil4(n):
    return (n + 3) // 4 * 4


def load_rgba(path):
    with Image.open(path) as im:
        return np.asarray(im.convert("RGBA")).copy()


def _lua_to_py(v):
    if hasattr(v, "keys"):
        keys = list(v.keys())
        if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [_lua_to_py(v[i]) for i in range(1, len(keys) + 1)]
        return {k: _lua_to_py(v[k]) for k in keys}
    return v


def _lua_global(path, name):
    """A global table a Lua file assigns, as Python dicts / lists (lupa)."""
    import lupa
    lua = lupa.LuaRuntime()
    lua.execute(open(path, encoding="utf-8").read())
    t = lua.globals()[name]
    return _lua_to_py(t) if t is not None else None


def load_layout(path=None):
    """MelloUI_KitLayout.pieces as {name: dict}."""
    path = path or LAYOUT_LUA
    try:
        return _lua_global(path, "MelloUI_KitLayout")["pieces"]
    except ImportError:
        text = open(path, encoding="utf-8").read()
        out = {}
        for m in re.finditer(r'\["([^"]+)"\] = \{ (.*) \},\n', text):
            body = m.group(2)
            d = {"file": re.search(r'file = "([^"]+)"', body).group(1).replace("\\\\", "\\")}
            for k in ("w", "h", "overhang", "radius"):
                mm = re.search(r"\b%s = (\d+)" % k, body)
                if mm:
                    d[k] = int(mm.group(1))
            for k in ("uv", "box", "open", "was"):
                mm = re.search(r"\b%s = \{ ([^}]*) \}" % k, body)
                if mm:
                    d[k] = [float(x) for x in mm.group(1).split(",")]
            mm = re.search(r'tile = "(\w+)"', body)
            if mm:
                d["tile"] = mm.group(1)
            out[m.group(1)] = d
        return out


KT_NIL = "\0nil"               # Core/KitTuning.lua's KT.NIL: "this field removed"


def load_tuning():
    """Media/KitTuning.lua's `pieces` overrides, and the pieces that must not
    be atlased because of them: {name: why}."""
    keep = {}
    if not os.path.exists(TUNING_LUA):
        return {}, keep
    try:
        t = _lua_global(TUNING_LUA, "MelloUI_KitTuning") or {}
    except ImportError:
        return {}, keep
    pieces = t.get("pieces") or {}
    if isinstance(pieces, list):
        pieces = {}
    for name, over in pieces.items():
        if not isinstance(over, dict):
            continue
        for field in ("uv", "file", "tile"):
            if field in over:
                keep[name] = "KitTuning overrides its %s" % field
        f = over.get("file")
        if isinstance(f, str) and f != KT_NIL:
            keep[f.replace("\\", "/")] = "KitTuning points %s at its file" % name
    return pieces, keep


def load_slices():
    """Media/KitSlices.lua's families ({prefix: entry}, empty without the
    file) and the pieces they hold in place: {name: why}. Kit.lua's
    SliceFamily draws a family as one picture only while each of its eight
    pieces has the file, w, h and uv recorded there; a piece moved into a
    sheet (or right-sized) would put the family back into pieces."""
    keep = {}
    if not os.path.exists(SLICES_LUA):
        return {}, keep
    try:
        data = _lua_global(SLICES_LUA, "MelloUI_KitSlices") or {}
    except ImportError:
        return {}, keep
    for prefix, e in data.items():
        for part in (e.get("pieces") or {}):
            keep[prefix + "_" + part] = "KitSlices.lua records it for the %s picture" % prefix
    return data, keep


def slice_pictures(slices):
    """{picture file under a look ('slices/window_frame'): (family, entry)}."""
    out = {}
    for prefix, e in slices.items():
        for k in ("full", "hollow"):
            f = e.get(k)
            if isinstance(f, str):
                out[f.replace("\\", "/")] = (prefix, e)
    return out


def piece_name(rel):
    top, rest = rel.split("/", 1)
    if top in LOOKS:
        return rest[:-4]
    return None


def kit_shown(name):
    for pat, v, note in KIT_SHOWN:
        if re.search(pat, name):
            return v, pat or "(default)", note
    raise AssertionError


def classify(a):
    al = a[..., 3]
    if (al == 255).all():
        return "opaque"
    if ((al == 0) | (al == 255)).all():
        return "1bit"
    return "smooth"


FMT_OF = {"opaque": "dxt1", "1bit": "dxt1a", "smooth": "dxt5"}


def dxt_bytes(w, h, fmt, mips):
    bs = 16 if fmt == "dxt5" else 8
    n = blp_dxt.mip_count(w, h) if mips else 1
    return sum(((max(1, w >> i) + 3) // 4) * ((max(1, h >> i) + 3) // 4) * bs for i in range(n))


# ---------------------------------------------------------------- the plan

def screen_info(rel, size, layout, pictures=None):
    """How the screen shows a file: upp (UI units per file px, or None),
    forced mips, category, note, the drawn rectangle (w, h from the top
    left) and the tiling axes. `pictures`: slice_pictures()."""
    cw, ch = size
    name = piece_name(rel)
    if name and pictures and name in pictures:
        # a one-texture nine-slice: its grid at the rails' density (texel
        # painted px per file texel), never right-sized
        prefix, e = pictures[name]
        r, _, note = kit_shown(prefix + "_t")
        texel = e.get("texel") or 1
        gw, gh = e["grid"]
        return {"upp": r * texel, "forced": False, "cat": "kit slices", "tile": "", "drawn": "KitSlices grid",
                "note": "%s nine-slice picture: %s, %s painted px per texel" % (prefix, note, texel),
                "content": (min(gw, cw), min(gh, ch)), "keep_size": "KitSlices margins are in its texels"}
    if name and name in layout:
        p = layout[name]
        uv = p["uv"]
        sw, sh = max(1, round(uv[1] * cw)), max(1, round(uv[3] * ch))
        r, cat, note = kit_shown(name)
        return {"upp": r * p["w"] / sw, "forced": False, "cat": "kit " + cat, "note": note,
                "content": (sw, sh), "tile": p.get("tile") or "", "drawn": "uv"}
    content, drawn = (cw, ch), "whole file"
    for pat, (fx, fy), note in TEX_DRAWN:
        if re.search(pat, rel):
            content, drawn = (max(1, round(fx * cw)), max(1, round(fy * ch))), note
    tile = ""
    for pat, axes in TEX_WRAP:
        if re.search(pat, rel):
            tile = axes
    for pat, v, forced, note in TEX_SHOWN:
        if re.search(pat, rel):
            return {"upp": v, "forced": forced, "cat": pat, "note": note, "content": content, "tile": tile, "drawn": drawn}
    return {"upp": None, "forced": False, "cat": "(unmapped)", "note": "not in the screen model", "content": content,
            "tile": tile, "drawn": drawn}


def resize_plan(rel, size, info, target):
    """Right-size: the smallest file that still has >= 1 file px per screen
    px on the target screen. Kit pieces: any factor (build_kit writes their
    uv); other files: halvings of the whole canvas (their Lua texcoords are
    fractions of the file, which a power-of-two factor keeps).
    Returns None (keep) or dict(scale, content, canvas)."""
    upp, tile = info["upp"], info["tile"]
    sw, sh = info["content"]
    if upp is None or info.get("keep_size"):
        return None
    c = 1 / upp                            # file px per UI unit
    f = target / c
    if f >= 1:
        return None
    cw, ch = size
    kit = piece_name(rel) is not None
    if not kit or tile:
        k = int(math.floor(math.log2(1 / f)))
        if k < 1:
            return None
        s = 2.0 ** -k
        if kit:
            nsw = round(sw * s) if "x" not in tile else cw >> k
            nsh = round(sh * s) if "y" not in tile else ch >> k
            ncw = cw >> k if "x" in tile else pot_up(nsw)
            nch = ch >> k if "y" in tile else pot_up(nsh)
        else:
            ncw, nch = cw >> k, ch >> k
            nsw, nsh = max(1, round(sw * s)), max(1, round(sh * s))
    else:
        tw, th = pot_up(math.ceil(sw * f)), pot_up(math.ceil(sh * f))
        tw, th = max(4, tw), max(4, th)
        if tw * th >= cw * ch:
            return None
        s = min(tw / sw, th / sh, 1.0)
        if s > KIT_MIN_SHRINK:
            return None                    # a few % off for a smaller canvas: not worth the lost margin
        nsw, nsh = min(tw, max(1, round(sw * s))), min(th, max(1, round(sh * s)))
        ncw, nch = tw, th
    if ncw < 4 or nch < 4 or ncw * nch >= cw * ch:
        return None
    return {"scale": s, "content": (nsw, nsh), "canvas": (ncw, nch)}


def wants_mips(upp, forced):
    if forced:
        return True
    if upp is None:
        return False
    return (1 / upp) / TARGET >= MIP_AT


def build_image(src_path, rel, info, rs):
    """The image a job encodes: the TGA, or its right-sized version."""
    a = load_rgba(src_path)
    if rs is None:
        return a
    tile = info["tile"]
    sw, sh = info["content"]
    nsw, nsh = rs["content"]
    ncw, nch = rs["canvas"]
    if piece_name(rel) is None:
        return np.asarray(Image.fromarray(a).resize((ncw, nch), Image.LANCZOS))
    crop = a[:sh, :sw]
    if tile:
        # a repeating axis resampled with its wrap: three repeats, the
        # middle one kept (the factor is a power of two, so it cuts exactly)
        rx, ry = (3 if "x" in tile else 1), (3 if "y" in tile else 1)
        big = Image.fromarray(np.tile(crop, (ry, rx, 1))).resize((nsw * rx, nsh * ry), Image.LANCZOS)
        ox, oy = (nsw if "x" in tile else 0), (nsh if "y" in tile else 0)
        content = np.asarray(big)[oy:oy + nsh, ox:ox + nsw]
    else:
        content = np.asarray(Image.fromarray(crop).resize((nsw, nsh), Image.LANCZOS))
    canvas = np.zeros((nch, ncw, 4), np.uint8)
    canvas[:nsh, :nsw] = content
    # a piece tiled along one axis: the padding repeats its edge rows /
    # columns, the far half wrapping to the first (as build_kit.py does)
    if "x" in tile and "y" not in tile and nsh < nch:
        half = (nsh + nch) // 2
        for r in range(nsh, nch):
            canvas[r] = canvas[nsh - 1] if r < half else canvas[0]
    if "y" in tile and "x" not in tile and nsw < ncw:
        half = (nsw + ncw) // 2
        for c in range(nsw, ncw):
            canvas[:, c] = canvas[:, nsw - 1] if c < half else canvas[:, 0]
    return canvas


def plan_image(p, rs):
    return build_image(p["src"], p["rel"], p["info"], rs)


# ---------------------------------------------------------------- metrics

def psnr(mse):
    return 99.0 if mse <= 1e-10 else float(10 * np.log10(255.0 ** 2 / mse))


def _premul(x):
    return x[..., :3] * x[..., 3:4] / 255


def _wpercentile(v, w, q):
    v, w = v.ravel(), w.ravel()
    keep = w > 0
    v, w = v[keep], w[keep]
    if not len(v):
        return 0.0
    o = np.argsort(v, kind="stable")
    v, c = v[o], np.cumsum(w[o])
    i = int(np.searchsorted(c, q / 100 * c[-1]))
    return float(v[min(i, len(v) - 1)])


def err_stats(ref, dec):
    """ref / dec: float (h, w, 4) straight RGBA of the drawn texels. Colour
    on premultiplied RGB, each texel weighted by the larger of its two
    alphas; alpha over the texels where either side shows."""
    e = _premul(ref) - _premul(dec)
    w = np.maximum(ref[..., 3], dec[..., 3]) / 255
    wsum = float(w.sum())
    pe = np.abs(e).max(-1)
    out = {}
    if wsum < 1e-6:
        out.update(psnr_rgb=99.0, max_rgb=0.0, p999_rgb=0.0)
    else:
        mse = float(((e ** 2).mean(-1) * w).sum() / wsum)
        out.update(psnr_rgb=round(psnr(mse), 2), max_rgb=round(float(pe[w > 0].max()), 1),
                   p999_rgb=round(_wpercentile(pe, w, 99.9), 1))
    ea = ref[..., 3] - dec[..., 3]
    sup = (ref[..., 3] > 0) | (dec[..., 3] > 0)
    out["psnr_a"] = round(psnr(float((ea[sup] ** 2).mean())), 2) if sup.any() else 99.0
    out["max_a"] = round(float(np.abs(ea).max()), 1) if ea.size else 0.0
    out["drawn_px"] = round(wsum, 1)
    return out


def dark_stats(ref, dec):
    """Colour drift on the dark opaque texels: mean per channel (signed),
    mean absolute, and the largest per-channel mean over the dark texels of
    any DARK_WIN x DARK_WIN area (the areas start at the drawn rectangle's
    corner, which is on the block grid)."""
    lum = 0.2126 * ref[..., 0] + 0.7152 * ref[..., 1] + 0.0722 * ref[..., 2]
    dark = (ref[..., 3] >= 250) & (lum < DARK_LUM)
    n = int(dark.sum())
    if n < DARK_MIN_PX:
        return {"dark_px": n}
    diff = dec[..., :3] - ref[..., :3]
    bias = diff[dark].mean(0)
    h, w = dark.shape
    ph, pw = -(-h // DARK_WIN) * DARK_WIN, -(-w // DARK_WIN) * DARK_WIN
    dm = np.zeros((ph, pw), np.float32)
    dm[:h, :w] = dark
    dd = np.zeros((ph, pw, 3), np.float32)
    dd[:h, :w] = diff * dark[..., None]
    k = DARK_WIN
    cnt = dm.reshape(ph // k, k, pw // k, k).sum((1, 3))
    sm = dd.reshape(ph // k, k, pw // k, k, 3).sum((1, 3))
    ok = cnt >= DARK_WIN_MIN
    local = float(np.abs(sm[ok] / cnt[ok][:, None]).max()) if ok.any() else 0.0
    return {"dark_px": n, "dark_bias": [round(float(x), 2) for x in bias],
            "dark_mae": round(float(np.abs(diff[dark]).mean()), 2), "dark_local": round(local, 1)}


def sample(img, lvl, rect, out_wh, wrap):
    """The GPU's bilinear sample of one mip level (float (H, W, 4), straight
    RGBA) for a screen of out_wh px showing `rect` (x0, y0, w, h in level-0
    texels); texel centres at +0.5, clamped at the level's edge or wrapped
    on a tiling axis."""
    x0, y0, cw, ch = rect
    ow, oh = out_wh
    s = float(1 << lvl)
    H, W = img.shape[:2]
    xs = (x0 + (np.arange(ow) + 0.5) * cw / ow) / s - 0.5
    ys = (y0 + (np.arange(oh) + 0.5) * ch / oh) / s - 0.5

    def taps(c, n, wr):
        i0 = np.floor(c).astype(np.int64)
        f = (c - i0).astype(np.float32)
        i1 = i0 + 1
        if wr:
            return i0 % n, i1 % n, f
        return np.clip(i0, 0, n - 1), np.clip(i1, 0, n - 1), f
    yi0, yi1, fy = taps(ys, H, wrap[1])
    xi0, xi1, fx = taps(xs, W, wrap[0])
    rows = img[yi0] * (1 - fy)[:, None, None] + img[yi1] * fy[:, None, None]
    return rows[:, xi0] * (1 - fx)[None, :, None] + rows[:, xi1] * fx[None, :, None]


def display(levels, rect, minify, wrap, trilinear):
    """The drawn rectangle as the screen shows it at `minify` file px per
    screen px: trilinear over the chain, or level 0 alone."""
    cw, ch = rect[2], rect[3]
    ow, oh = max(1, round(cw / minify)), max(1, round(ch / minify))
    if not trilinear or len(levels) == 1:
        return sample(levels[0], 0, rect, (ow, oh), wrap)
    lod = max(0.0, math.log2(max(cw / ow, ch / oh)))     # magnified: level 0
    lo = min(int(math.floor(lod)), len(levels) - 1)
    hi = min(lo + 1, len(levels) - 1)
    f = lod - math.floor(lod)
    a = sample(levels[lo], lo, rect, (ow, oh), wrap)
    if hi == lo or f < 1e-3:
        return a
    return a * (1 - f) + sample(levels[hi], hi, rect, (ow, oh), wrap) * f


def edge_stats(ref, dec, orig=None):
    """Bilinear midpoints (straight alpha, then premultiplied) that touch a
    faint texel (alpha <= 32) beside a visible one: the largest DXT error
    there (a fringe), and -- given the TGA as painted -- how far the bleed
    moved them from what the TGA draws today."""
    def mid(x):
        m = (x[:-1, :-1] + x[1:, :-1] + x[:-1, 1:] + x[1:, 1:]) / 4
        return _premul(m)
    if ref.shape[0] < 2 or ref.shape[1] < 2:
        return {}
    a = ref[..., 3]
    faint = a <= 32
    vis = a > 0
    def touch(m):
        return m[:-1, :-1] | m[1:, :-1] | m[:-1, 1:] | m[1:, 1:]
    rim = touch(faint) & touch(vis)
    if not rim.any():
        return {}
    out = {"edge_err": round(float(np.abs(mid(ref) - mid(dec)).max(-1)[rim].max()), 1)}
    if orig is not None:
        out["bleed_edge"] = round(float(np.abs(mid(orig) - mid(ref)).max(-1)[rim].max()), 1)
    return out


def measure(ref_levels, dec_levels, rect, minify, wrap, mips, orig=None):
    """Every number the report and the gate use, for one drawn rectangle:
    file_* at the file's resolution, disp_* at display size (the GPU model;
    disp0_* from level 0 alone for a file with mips), dark_* and edge_*."""
    x0, y0, cw, ch = rect
    r0 = ref_levels[0][y0:y0 + ch, x0:x0 + cw].astype(np.float32)
    d0 = dec_levels[0][y0:y0 + ch, x0:x0 + cw].astype(np.float32)
    out = {"file_" + k: v for k, v in err_stats(r0, d0).items()}
    o0 = orig[y0:y0 + ch, x0:x0 + cw].astype(np.float32) if orig is not None else None
    out.update(edge_stats(r0, d0, o0))
    if minify and minify > MINIFY_AT:
        need = len(ref_levels) if mips else 1
        R = [lv.astype(np.float32) for lv in ref_levels[:need]]
        D = [lv.astype(np.float32) for lv in dec_levels[:need]]
        rt, dt = display(R, rect, minify, wrap, mips), display(D, rect, minify, wrap, mips)
        disp, dark = err_stats(rt, dt), dark_stats(rt, dt)
        if mips:
            rz, dz = display(R, rect, minify, wrap, False), display(D, rect, minify, wrap, False)
            out.update({"disp0_" + k: v for k, v in err_stats(rz, dz).items() if k in ("psnr_rgb", "p999_rgb", "max_rgb")})
            dz_dark = dark_stats(rz, dz)
            # the worse of the two models for the drift too
            if dz_dark.get("dark_bias") and (not dark.get("dark_bias") or
                                              max(map(abs, dz_dark["dark_bias"])) > max(map(abs, dark["dark_bias"]))):
                dark["dark_bias"] = dz_dark["dark_bias"]
            if dz_dark.get("dark_local", 0) > dark.get("dark_local", 0):
                dark["dark_local"] = dz_dark["dark_local"]
    else:
        disp = {k[5:]: v for k, v in out.items() if k.startswith("file_")}
        dark = dark_stats(r0, d0)
    out.update({"disp_" + k: v for k, v in disp.items() if k != "drawn_px"})
    out.update(dark)
    return out


def gate_fail(r):
    """Why a measured file / piece fails option d's gate ('' when it passes)."""
    why = []
    if r["disp_psnr_rgb"] < GATE_PSNR or r["disp_p999_rgb"] > GATE_P999:
        why.append("%.1f dB, p99.9 %.0f at display size" % (r["disp_psnr_rgb"], r["disp_p999_rgb"]))
    if r.get("disp0_psnr_rgb") is not None and (r["disp0_psnr_rgb"] < GATE_PSNR or r["disp0_p999_rgb"] > GATE_P999):
        why.append("%.1f dB, p99.9 %.0f from level 0 alone (no mips)" % (r["disp0_psnr_rgb"], r["disp0_p999_rgb"]))
    b = r.get("dark_bias")
    if isinstance(b, str):
        b = json.loads(b) if b else None
    if b and max(abs(x) for x in b) > GATE_DARK_BIAS:
        why.append("dark texels drift %+.1f/%+.1f/%+.1f" % tuple(b))
    loc = r.get("dark_local")
    if loc not in (None, "") and float(loc) > GATE_DARK_LOCAL:
        why.append("dark texels drift %.0f in an 8x8 area" % float(loc))
    return "; ".join(why)


LOSSLESS = {"file_psnr_rgb": 99.0, "file_p999_rgb": 0.0, "file_max_rgb": 0.0, "file_psnr_a": 99.0, "file_max_a": 0.0,
            "disp_psnr_rgb": 99.0, "disp_p999_rgb": 0.0, "disp_max_rgb": 0.0, "disp_psnr_a": 99.0, "disp_max_a": 0.0}


# ---------------------------------------------------------------- workers

def _wrap(tile):
    return ("x" in tile, "y" in tile)


def encode_job(job):
    """job: src (abs), dst (abs), rel, fmt, mips, rs, info, content, minify,
    effort. Writes the BLP; returns its record, measured on what is drawn."""
    t = time.time()
    orig = job["image"] if job.get("image") is not None else build_image(job["src"], job["rel"], job["info"], job["rs"])
    fmt = job["fmt"] or FMT_OF[classify(orig)]
    wrap = _wrap(job["info"]["tile"])
    levels, bled = blp_dxt.mip_chain(orig, fmt, job["mips"], wrap)
    data = blp_dxt.encode_blp(orig, fmt, mips=job["mips"], effort=job["effort"], level_images=levels)
    os.makedirs(os.path.dirname(job["dst"]), exist_ok=True)
    with open(job["dst"], "wb") as fh:
        fh.write(data)
    dec = [blp_dxt.decode_blp(data, "gpu", level=i) for i in range(len(levels))]
    hd = blp_dxt.read_blp_header(data)
    cw, ch = job["content"]
    rec = {"rel": job["rel"], "dst": job["dst"], "fmt": fmt, "mips": bool(job["mips"]), "levels": len(levels),
           "w": orig.shape[1], "h": orig.shape[0], "content": [cw, ch], "bytes": len(data), "gpu": sum(hd["sizes"]),
           "minify": round(job["minify"], 3) if job["minify"] else None, "bled_texels": bled}
    rec.update(measure(levels, dec, (0, 0, cw, ch), job["minify"], wrap, job["mips"], orig if bled else None))
    rec["gate"] = gate_fail(rec)
    rec["secs"] = round(time.time() - t, 2)
    return rec


def copy_job(job):
    """A file shipped exactly as its master (STAY_TGA): the TGA's bytes."""
    os.makedirs(os.path.dirname(job["dst"]), exist_ok=True)
    shutil.copyfile(job["src"], job["dst"])
    with Image.open(job["dst"]) as im:
        w, h = im.size
    same = open(job["src"], "rb").read() == open(job["dst"], "rb").read()
    rec = {"rel": job["rel"], "dst": job["dst"], "fmt": "tga", "mips": False, "levels": 1, "w": w, "h": h,
           "content": list(job["info"]["content"]), "bytes": os.path.getsize(job["dst"]), "gpu": w * h * 4,
           "minify": round(job["minify"], 3) if job.get("minify") else None, "exact": same, "master_copy": 1,
           "gate": ""}
    rec.update(LOSSLESS)
    return rec


def tga_job(job):
    """Write a file as 32-bit TGA (kept uncompressed: a file that failed the
    quality gate, or one a Lua path names with '.tga') -- the pixels as
    painted, unbled, at the file's right size."""
    img = job["image"] if job.get("image") is not None else build_image(job["src"], job["rel"], job["info"], job["rs"])
    os.makedirs(os.path.dirname(job["dst"]), exist_ok=True)
    Image.fromarray(img).save(job["dst"])
    back = load_rgba(job["dst"])
    rec = {"rel": job["rel"], "dst": job["dst"], "fmt": "tga", "mips": False, "levels": 1, "w": img.shape[1],
           "h": img.shape[0], "content": list(job.get("content") or (img.shape[1], img.shape[0])),
           "bytes": os.path.getsize(job["dst"]), "gpu": img.shape[0] * img.shape[1] * 4,
           "minify": round(job["minify"], 3) if job.get("minify") else None,
           "exact": bool(np.array_equal(back, img)), "gate": ""}
    rec.update(LOSSLESS)
    return rec


def keep_job(job):
    """A file option d keeps uncompressed: its master's bytes (STAY_TGA) or
    a TGA of its right-sized image."""
    return copy_job(job) if job.get("copy") else tga_job(job)


def sheet_job(job):
    """An atlas sheet of one look: written as DXT (each piece then measured
    in its own rectangle, with the gate) or as an uncompressed TGA.
    Returns (sheet record, piece records)."""
    img = job["image"]
    H, W = img.shape[:2]
    if job["raw"]:
        rec = tga_job({"image": img, "dst": job["dst"], "rel": job["rel"]})
        pieces = []
        for pc in job["pieces"]:
            pr = {"rel": pc["rel"], "name": pc["name"], "look": job["look"], "sheet": job["rel"], "fmt": "tga",
                  "rect": list(pc["rect"]), "minify": pc["minify"], "gate": ""}
            pr.update(LOSSLESS)
            pieces.append(pr)
    else:
        fmt = FMT_OF[classify(img)]
        levels, bled = blp_dxt.mip_chain(img, fmt, False)
        data = blp_dxt.encode_blp(img, fmt, mips=False, effort=job["effort"], level_images=levels)
        os.makedirs(os.path.dirname(job["dst"]), exist_ok=True)
        with open(job["dst"], "wb") as fh:
            fh.write(data)
        dec = [blp_dxt.decode_blp(data, "gpu")]
        rec = {"rel": job["rel"], "dst": job["dst"], "fmt": fmt, "mips": False, "levels": 1, "w": W, "h": H,
               "content": [W, H], "bytes": len(data), "gpu": len(data) - blp_dxt.HEADER_SIZE, "minify": None,
               "bled_texels": bled, "gate": ""}
        pieces = []
        for pc in job["pieces"]:
            pr = {"rel": pc["rel"], "name": pc["name"], "look": job["look"], "sheet": job["rel"], "fmt": fmt,
                  "rect": list(pc["rect"]), "minify": pc["minify"]}
            pr.update(measure(levels, dec, tuple(pc["rect"]), pc["minify"], (False, False), False,
                              img if bled else None))
            pr["gate"] = gate_fail(pr)
            pieces.append(pr)
    rec.update({"pieces": len(job["pieces"]), "used_px": job["used_px"], "group": job["group"], "look": job["look"]})
    return rec, pieces


def verify_job(job):
    """Re-read a written file from disk. A BLP: header fields, a complete mip
    chain (every level's offset and size, the last level 1 x 1), Pillow's
    decode bit for bit what blp_dxt's Pillow-mode decoder gives, and every
    level through the GPU decoder against the level it was encoded from. A
    TGA: read back exactly."""
    problems = []
    ref = job["image"] if job.get("image") is not None else build_image(job["src"], job["rel"], job["info"], job["rs"])
    if job["dst"].endswith(".tga"):
        back = load_rgba(job["dst"])
        if not np.array_equal(back, ref):
            problems.append("TGA does not read back as written")
        return {"rel": job["rel"], "dst": job["dst"], "fmt": "tga", "pillow_exact": True, "levels": 1,
                "problems": "; ".join(problems)}
    data = open(job["dst"], "rb").read()
    hd = blp_dxt.read_blp_header(data)
    fmt = blp_dxt.fmt_of(hd)
    w, h = hd["w"], hd["h"]
    if data[:4] != b"BLP2" or hd["type"] != 1 or hd["encoding"] != 2:
        problems.append("magic/type/encoding")
    want_ad = {"dxt1": 0, "dxt1a": 1, "dxt5": 8}[fmt]
    if hd["alpha_depth"] != want_ad:
        problems.append("alpha depth %d" % hd["alpha_depth"])
    if any(data[148:blp_dxt.HEADER_SIZE]):
        problems.append("palette not zero")
    n = blp_dxt.mip_count(w, h) if hd["has_mips"] else 1
    pos = blp_dxt.HEADER_SIZE
    for i in range(16):
        exp = dxt_bytes(max(1, w >> i), max(1, h >> i), fmt, False) if i < n else 0
        if hd["sizes"][i] != exp or (i < n and hd["offsets"][i] != pos) or (i >= n and hd["offsets"][i] != 0):
            problems.append("level %d offset/size" % i)
        pos += exp
    if pos != len(data):
        problems.append("file size %d != %d" % (len(data), pos))
    last = blp_dxt.mip_size(w, h, n - 1)
    if hd["has_mips"] and last != (1, 1):
        problems.append("chain ends at %dx%d" % last)
    with Image.open(job["dst"]) as im:
        im.load()
        pil = np.asarray(im.convert("RGBA"))
        pil_mode = im.mode
    emu = blp_dxt.decode_blp(data, "pillow")
    if fmt == "dxt1":
        emu = emu.copy()
        emu[..., 3] = 255
    exact = bool(np.array_equal(pil, emu))
    if not exact:
        problems.append("Pillow decode differs from the reference decoder")
    levels, _ = blp_dxt.mip_chain(ref, fmt, bool(hd["has_mips"]), _wrap(job["info"]["tile"]) if job.get("info") else (False, False))
    if len(levels) != n:
        problems.append("%d levels, the source chain has %d" % (n, len(levels)))
    worst = 99.0
    for i in range(min(n, len(levels))):
        lv = blp_dxt.decode_blp(data, "gpu", level=i)
        if lv.shape != levels[i].shape:
            problems.append("level %d shape" % i)
            break
        if i:
            worst = min(worst, err_stats(levels[i].astype(np.float32), lv.astype(np.float32))["psnr_rgb"])
    cw, ch = job.get("content") or (w, h)
    rec = {"rel": job["rel"], "dst": job["dst"], "fmt": fmt, "pil_mode": pil_mode, "pillow_exact": exact,
           "levels": n, "last_level": "%dx%d" % last, "mip_worst_psnr": worst if n > 1 else None}
    ps = err_stats(ref[:ch, :cw].astype(np.float32), pil[:ch, :cw].astype(np.float32))
    rec.update({"pil_" + k: v for k, v in ps.items() if k in ("psnr_rgb", "max_rgb", "psnr_a")})
    rec["problems"] = "; ".join(problems)
    return rec


# ---------------------------------------------------------------- options

def not_shipped(rel):
    """Why the master `rel` never ships (NOT_SHIPPED), or None."""
    for pat, why in NOT_SHIPPED:
        if re.search(pat, rel):
            return why
    return None


def inventory(only=None, every=False):
    """The TGA masters (Media-relative), NOT_SHIPPED ones left out unless
    `every`."""
    items = []
    for dp, dns, fns in os.walk(MEDIA):
        rd = os.path.relpath(dp, MEDIA).replace(os.sep, "/")
        if rd.split("/")[0] in SKIP_DIRS:
            continue
        for fn in fns:
            if fn.lower().endswith(".tga"):
                rel = (fn if rd == "." else rd + "/" + fn)
                if only and not re.search(only, rel):
                    continue
                if not every and not_shipped(rel):
                    continue
                items.append(rel)
    return sorted(items)


def plan_files(only=None):
    layout = load_layout()
    slices, slice_keep = load_slices()
    pictures = slice_pictures(slices)
    plans = []
    for rel in inventory(only):
        path = os.path.join(MEDIA, rel.replace("/", os.sep))
        with Image.open(path) as im:
            size = im.size
            a = np.asarray(im.convert("RGBA"))
        cls = classify(a)
        hidden = a[..., 3] == 0
        info = screen_info(rel, size, layout, pictures)
        name = piece_name(rel)
        if name in slice_keep:
            info["keep_size"] = slice_keep[name]
        rs = resize_plan(rel, size, info, TARGET)
        plans.append({"rel": rel, "src": path, "size": size, "cls": cls, "info": info, "rs": rs,
                      "tga_bytes": os.path.getsize(path), "tga_gpu": size[0] * size[1] * 4,
                      "hidden_rgb": int((a[..., :3][hidden] != 0).any(-1).sum()) if hidden.any() else 0})
    return plans, layout, slices, slice_keep


def file_job(p, out, option, effort):
    rs = p["rs"] if option != "a" else None
    upp = p["info"]["upp"]
    if rs and upp:
        upp = upp / rs["scale"]
    return {"src": p["src"], "rel": p["rel"], "info": p["info"], "rs": rs,
            "dst": os.path.join(out, option, p["rel"][:-4].replace("/", os.sep) + ".blp"),
            "content": rs["content"] if rs else p["info"]["content"],
            "fmt": FMT_OF[p["cls"]], "mips": wants_mips(upp, p["info"]["forced"]), "effort": effort,
            "minify": (1 / upp) / TARGET if upp else None}


def run_pool(fn, jobs, workers):
    if workers <= 1 or len(jobs) <= 1:
        return [fn(j) for j in jobs]
    # the big files first, so the pool ends together
    def weight(j):
        if j.get("image") is not None:
            return -j["image"].size
        return -os.path.getsize(j["src"]) if j.get("src") and os.path.exists(j["src"]) else 0
    order = sorted(range(len(jobs)), key=lambda i: weight(jobs[i]))
    with ProcessPoolExecutor(max_workers=workers) as ex:
        res = list(ex.map(fn, [jobs[i] for i in order], chunksize=1))
    back = [None] * len(jobs)
    for k, i in enumerate(order):
        back[i] = res[k]
    return back


# ---------------------------------------------------------------- atlas (options c, d)

class MaxRects:
    """MaxRects bin packing, best short side fit; all sizes multiples of 4
    so every rect starts on a DXT block."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.free = [(0, 0, w, h)]

    def insert(self, rw, rh):
        best = None
        for fx, fy, fw, fh in self.free:
            if rw <= fw and rh <= fh:
                score = (min(fw - rw, fh - rh), max(fw - rw, fh - rh), fy, fx)
                if best is None or score < best[0]:
                    best = (score, fx, fy)
        if best is None:
            return None
        _, x, y = best
        self._split(x, y, rw, rh)
        return x, y

    def _split(self, x, y, w, h):
        out = []
        for fx, fy, fw, fh in self.free:
            if x >= fx + fw or x + w <= fx or y >= fy + fh or y + h <= fy:
                out.append((fx, fy, fw, fh))
                continue
            if x > fx:
                out.append((fx, fy, x - fx, fh))
            if x + w < fx + fw:
                out.append((x + w, fy, fx + fw - x - w, fh))
            if y > fy:
                out.append((fx, fy, fw, y - fy))
            if y + h < fy + fh:
                out.append((fx, y + h, fw, fy + fh - y - h))
        # drop rects inside others
        keep = []
        for i, a in enumerate(out):
            inside = False
            for j, b in enumerate(out):
                if i != j and a[0] >= b[0] and a[1] >= b[1] and a[0] + a[2] <= b[0] + b[2] and a[1] + a[3] <= b[1] + b[3]:
                    if a != b or i > j:
                        inside = True
                        break
            if not inside and a[2] > 0 and a[3] > 0:
                keep.append(a)
        self.free = keep


SHEET_SIZES = sorted({(w, h) for w in (64, 128, 256, 512, 1024, 2048) for h in (64, 128, 256, 512, 1024, 2048)
                      if max(w, h) <= 2 * min(w, h) * 2}, key=lambda s: (s[0] * s[1], abs(s[0] - s[1])))
SHEET_PENALTY = 65536         # px: what one more file is worth against empty sheet area


def _pack(rects, W, H):
    mr = MaxRects(W, H)
    placed, rest = {}, []
    for rid, w, h in rects:
        pos = mr.insert(w, h) if (w <= W and h <= H) else None
        if pos is None:
            rest.append((rid, w, h))
        else:
            placed[rid] = pos
    return placed, rest


def _smallest_fit(rects, maxside):
    need = sum(w * h for _, w, h in rects)
    mw, mh = max(w for _, w, _ in rects), max(h for _, _, h in rects)
    for W, H in SHEET_SIZES:
        if W > maxside or H > maxside or W * H < need or mw > W or mh > H:
            continue
        placed, rest = _pack(rects, W, H)
        if not rest:
            return (W, H, placed)
    return None


def pack_sheets(rects, sheet=ATLAS_SHEET):
    """rects: [(id, w, h)] -> [(sheet_w, sheet_h, {id: (x, y)})]: one sheet
    of the smallest power-of-two size that holds them all, or two (a full
    first sheet and the smallest that takes the rest) when that wastes less
    (SHEET_PENALTY per extra file); more only when they must."""
    todo = sorted(rects, key=lambda r: (-max(r[1], r[2]), -r[1] * r[2], r[0]))
    one = _smallest_fit(todo, sheet)
    best, best_area = ([one], one[0] * one[1]) if one else (None, float("inf"))
    for W, H in [s for s in SHEET_SIZES if s[0] <= sheet and s[1] <= sheet][::-1][:10]:
        placed, rest = _pack(todo, W, H)
        if not placed or not rest:
            continue
        second = _smallest_fit(rest, sheet)
        if second is None:
            continue
        area = W * H + second[0] * second[1] + SHEET_PENALTY
        if area < best_area:
            best, best_area = [(W, H, placed), second], area
    if best is not None:
        return best
    return _pack_greedy(todo, sheet)


def _pack_greedy(rects, sheet=ATLAS_SHEET):
    """Full sheets, the last shrunk to the smallest size that holds its rects."""
    todo = list(rects)
    sheets = []
    while todo:
        placed, rest = _pack(todo, sheet, sheet)
        if not placed:
            raise ValueError("a piece larger than the sheet")
        if not rest:
            last = _smallest_fit(todo, sheet)
            sheets.append(last or (sheet, sheet, placed))
        else:
            sheets.append((sheet, sheet, placed))
        todo = rest
    return sheets


def atlas_candidates(plans, layout, keep_out):
    """The kit pieces a sheet can take: not tiling, not wanting mips, at most
    ATLAS_MAX_SIDE after right-sizing, and not held out by kit tuning.
    {name: (content w, h, recoloured, minify)}."""
    import kit_palette
    cand = {}
    for p in plans:
        name = piece_name(p["rel"])
        if not name or name not in layout or p["rel"].split("/")[0] != "Kit" or layout[name].get("tile"):
            continue
        if name in keep_out:
            continue
        upp = p["info"]["upp"]
        if p["rs"]:
            upp = upp / p["rs"]["scale"]
            sw, sh = p["rs"]["content"]
        else:
            sw, sh = p["info"]["content"]
        if max(sw, sh) > ATLAS_MAX_SIDE or wants_mips(upp, p["info"]["forced"]):
            continue
        cand[name] = (sw, sh, kit_palette.recoloured(name), (1 / upp) / TARGET)
    return cand


def atlas_specs(cand, hq, sheet=ATLAS_SHEET):
    """Pack the candidates: recoloured pieces in sheets shared by Kit,
    KitWarm and KitBronze (the same uv in every look), the pieces every look
    reads from Media/Kit (kit_palette.SKIP) in Kit-only sheets; `hq` pieces
    apart, in sheets kept uncompressed. A DXT sheet starts each piece
    BLOCK px into its rectangle, so the piece's blocks are its own (the
    same 4x4 grid as its own file) and the edge it extrudes into the lead
    fills whole blocks. Returns (sheet specs, uv map)."""
    groups = {"sheet": [n for n in cand if cand[n][2] and n not in hq],
              "pictures": [n for n in cand if not cand[n][2] and n not in hq],
              "sheethq": [n for n in cand if cand[n][2] and n in hq],
              "pictureshq": [n for n in cand if not cand[n][2] and n in hq]}
    specs, uvmap = [], {}
    for gname, names in groups.items():
        if not names:
            continue
        raw = gname.endswith("hq")
        lead = ATLAS_PAD if raw else BLOCK
        rects = []
        for n in sorted(names):
            sw, sh = cand[n][:2]
            rw = ceil4(sw + 2 * ATLAS_PAD) if raw else lead + ceil4(sw + ATLAS_PAD)
            rh = ceil4(sh + 2 * ATLAS_PAD) if raw else lead + ceil4(sh + ATLAS_PAD)
            rects.append((n, rw, rh))
        for si, (W, H, placed) in enumerate(pack_sheets(rects, sheet), 1):
            sheet_file = "atlas\\%s_%d" % (gname, si)
            sizes = {r[0]: (r[1], r[2]) for r in rects}
            for n, (x, y) in placed.items():
                sw, sh = cand[n][:2]
                cx, cy = x + lead, y + lead
                uvmap[n] = {"file": sheet_file, "uv": (cx / W, (cx + sw) / W, cy / H, (cy + sh) / H),
                            "rect": (cx, cy, sw, sh), "cell": (x, y) + sizes[n], "raw": raw}
            specs.append({"group": gname, "index": si, "file": sheet_file, "W": W, "H": H, "raw": raw, "lead": lead,
                          "placed": placed, "sizes": sizes,
                          "looks": LOOKS if gname.startswith("sheet") else ("Kit",)})
    return specs, uvmap


def sheet_jobs(specs, cand, by_rel, out, option, effort, report_dir=None):
    """The sheet images of every look, as jobs for sheet_job."""
    jobs, atlased = [], set()
    for sp in specs:
        W, H, lead = sp["W"], sp["H"], sp["lead"]
        for look in sp["looks"]:
            img = np.zeros((H, W, 4), np.uint8)
            pieces, used = [], 0
            for n, (x, y) in sorted(sp["placed"].items()):
                rel = look + "/" + n + ".tga"
                p = by_rel.get(rel)
                if p is None:
                    continue
                src = plan_image(p, p["rs"])
                sw, sh = cand[n][:2]
                rw, rh = sp["sizes"][n]
                cell = np.pad(src[:sh, :sw], ((lead, rh - sh - lead), (lead, rw - sw - lead), (0, 0)), mode="edge")
                img[y:y + rh, x:x + rw] = cell
                pieces.append({"name": n, "rel": rel, "rect": (x + lead, y + lead, sw, sh), "minify": cand[n][3]})
                used += rw * rh
                atlased.add(rel)
            rel_sheet = look + "/" + sp["file"].replace("\\", "/") + ".tga"
            if report_dir and look in ("Kit", "KitWarm"):
                Image.fromarray(img).save(os.path.join(report_dir, "atlas_%s_%s_%s_%d.png" % (option, look, sp["group"], sp["index"])))
            jobs.append({"rel": rel_sheet, "image": img, "raw": sp["raw"], "look": look, "group": sp["group"],
                         "dst": os.path.join(out, option, rel_sheet[:-4].replace("/", os.sep) + (".tga" if sp["raw"] else ".blp")),
                         "effort": effort, "pieces": pieces, "used_px": used})
    return jobs, atlased


def check_slices(layout_path, slices, out, option):
    """Kit.lua's SliceFamily test on the option's layout: every piece a
    KitSlices.lua family records still has that file, w, h and uv (to 1e-5,
    as Kit.lua compares), and each family's pictures exist in every look of
    the option's tree as exactly one of .blp / .tga. Returns problems."""
    problems = []
    if not slices:
        return problems
    pieces = load_layout(layout_path)
    for prefix, e in sorted(slices.items()):
        for part, src in sorted((e.get("pieces") or {}).items()):
            n = prefix + "_" + part
            p = pieces.get(n)
            if p is None:
                problems.append("%s: not in the layout (KitSlices %s)" % (n, prefix))
                continue
            if p["file"] != src["file"] or p["w"] != src["w"] or p["h"] != src["h"] or \
                    any(abs(a - b) > 1e-5 for a, b in zip(p["uv"], src["uv"])):
                problems.append("%s: file/size/uv differ from KitSlices.lua (%s %s -> %s %s): the %s family would fall "
                                "back to pieces" % (n, src["file"], src["uv"], p["file"], p["uv"], prefix))
        for look in LOOKS:
            for k in ("full", "hollow"):
                f = e.get(k)
                if not isinstance(f, str) or not os.path.isdir(os.path.join(out, option, look)):
                    continue
                base = os.path.join(out, option, look, f.replace("\\", os.sep))
                have = [x for x in (".blp", ".tga") if os.path.exists(base + x)]
                if len(have) != 1:
                    problems.append("%s/%s: %s" % (look, f, "missing" if not have else "both .blp and .tga"))
    return problems


def check_atlas(layout_path, jobs, uvmap, plans, out, option):
    """The preview KitLayout.lua parses and names every piece; each atlased
    piece's uv, read back as pixels, is exactly its (right-sized) image in
    the sheet of every look; every file the layout names exists in the
    option's tree as exactly one of .blp / .tga. Returns problems."""
    import kit_palette
    problems = []
    by_rel = {p["rel"]: p for p in plans}
    for sj in jobs:
        img = sj["image"]
        H, W = img.shape[:2]
        for pc in sj["pieces"]:
            v = uvmap[pc["name"]]
            u0, u1, v0, v1 = v["uv"]
            x0, x1, y0, y1 = round(u0 * W), round(u1 * W), round(v0 * H), round(v1 * H)
            p = by_rel[pc["rel"]]
            src = plan_image(p, p["rs"])
            sw, sh = (p["rs"]["content"] if p["rs"] else p["info"]["content"])
            if (x1 - x0, y1 - y0) != (sw, sh) or not np.array_equal(img[y0:y1, x0:x1], src[:sh, :sw]):
                problems.append("%s: uv does not address its pixels" % pc["rel"])
            if not sj["raw"] and (x0 % BLOCK or y0 % BLOCK):
                problems.append("%s: off the block grid" % pc["rel"])
    pieces = load_layout(layout_path)
    for n, pc in pieces.items():
        for look in LOOKS:
            if look != "Kit" and not os.path.isdir(os.path.join(out, option, look)):
                continue
            root = look if (look == "Kit" or kit_palette.recoloured(n)) else "Kit"
            base = os.path.join(out, option, root, pc["file"].replace("\\", os.sep))
            have = [e for e in (".blp", ".tga") if os.path.exists(base + e)]
            if len(have) != 1:
                problems.append("%s/%s: %s" % (root, pc["file"], "missing" if not have else "both .blp and .tga"))
    return problems


def lua_num(v):
    return ("%.6f" % v).rstrip("0").rstrip(".") if isinstance(v, float) else str(v)


PREVIEW_HEADER = [
    "-- PREVIEW written by Tools/texture_pack.py (not the addon's file): the masters' KitLayout.lua",
    "-- with the right-sized uvs and the atlas sheets' files and uvs put in.",
    "--   was   the piece's uv in its former file (file = its own name), where the uv or the",
    "--         file changed: the frame a KitTuning `pieces` override of uv / file was",
    "--         written in, for the remap in Modules/Kit.lua's Kit:ApplyTuning",
]
SHIP_HEADER = [
    "-- Generated by Tools/texture_pack.py ship from the masters' KitLayout.lua (Tools/build_kit.py). Do not edit by hand.",
    "--",
    "-- One entry per painted kit piece (naming per docs/UI-KIT.md):",
    "--   file  path under Media\\Kit (no extension: a BLP, or a TGA where DXT failed the quality gate);",
    "--         atlas\\<sheet>_<n> for the small pieces packed into one sheet per look (the same uv in",
    "--         Media\\Kit, Media\\KitWarm and Media\\KitBronze)",
    "--   w, h  size of the piece as painted (2x px); the file holds it at a lower density, the uv accounts for that",
    "--   uv    left, right, top, bottom of the piece inside its file (its sheet)",
    "--   was   where the ship moved the piece into a sheet or right-sized its file: its uv in its own",
    "--         former file (file = its name), the frame a KitTuning `pieces` uv / file override is written in",
    "--   tile  \"x\", \"y\" or \"xy\": the file repeats exactly along that axis (use REPEAT wrap); never in a sheet",
    "--   box   left, top, right, bottom of the opaque part of the piece, in piece pixels (strips fit and centre by it)",
    "--   open  left, top, right, bottom of the transparent interior, in piece pixels",
    "--   overhang  an oversized corner: how far its rails' outer edges sit inside its canvas, in piece pixels (the gem reaches that far past the frame)",
    "--   radius  a round piece's body radius from its centre, in piece pixels, without the gems at its compass points",
]


def write_layout(layout, path, uvmap=None, resized=None, header=None):
    """KitLayout.lua as build_kit.py writes it, with atlas files / uvs and
    right-sized uvs put in (PREVIEW_HEADER: a preview; SHIP_HEADER: the
    addon's). A piece whose uv changed (atlased or right-sized) keeps
    `was`: its uv in its former own file, the frame a KitTuning override of
    its uv or file was written in."""
    lines = list(header or PREVIEW_HEADER) + [
        "",
        "MelloUI_KitLayout = {",
        "\troot = \"Interface\\\\AddOns\\\\MelloUI\\\\Media\\\\Kit\\\\\",",
        "\tpieces = {",
    ]
    for name in sorted(layout):
        p = dict(layout[name])
        uv = list(p["uv"])
        f = p["file"]
        was = None
        if resized and name in resized:
            (nsw, nsh), (ncw, nch) = resized[name]
            was = list(p["uv"])
            uv = [0.0, nsw / ncw, 0.0, nsh / nch]
        if uvmap and name in uvmap:
            was = list(p["uv"])
            f = uvmap[name]["file"]
            uv = list(uvmap[name]["uv"])
        s = "\t\t[\"%s\"] = { file = \"%s\", w = %d, h = %d, uv = { %s }" % (
            name, f.replace("\\", "\\\\"), p["w"], p["h"], ", ".join(lua_num(float(v)) for v in uv))
        if was:
            s += ", was = { %s }" % ", ".join(lua_num(float(v)) for v in was)
        if p.get("tile"):
            s += ", tile = \"%s\"" % p["tile"]
        s += ", box = { %s }" % ", ".join(str(int(v)) for v in p["box"])
        if p.get("open"):
            s += ", open = { %s }" % ", ".join(str(int(v)) for v in p["open"])
        if p.get("overhang") is not None:
            s += ", overhang = %d" % p["overhang"]
        if p.get("radius") is not None:
            s += ", radius = %d" % p["radius"]
        lines.append(s + " },")
    lines += ["\t},", "}", ""]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", newline="\n") as fh:
        fh.write("\n".join(lines))


# ---------------------------------------------------------------- kit tuning remap (Modules/Kit.lua, tested here)

KIT_LUA = os.path.join(ROOT, "Modules", "Kit.lua")
KIT_TUNING_LUA = os.path.join(ROOT, "Core", "KitTuning.lua")

# Just enough of the client for Core/KitTuning.lua and Modules/Kit.lua to
# load, and for Kit:ApplyTuning to run, in Lua 5.1: a frame method not
# listed does nothing, a field not set is nil.
KIT_STUBS_LUA = r'''
loadstring = loadstring or load
unpack = unpack or table.unpack
SlashCmdList = {}
GameFontNormal = {}
function GetTime() return 0 end
function issecretvalue() return false end
function hooksecurefunc() end
function Mixin(target, ...)
	for i = 1, select("#", ...) do
		for k, v in pairs((select(i, ...))) do target[k] = v end
	end
	return target
end
C_Timer = { NewTicker = function() return { Cancel = function() end } end,
	NewTimer = function() return { Cancel = function() end } end,
	After = function() end }
local Noop = function() end
local FrameMT = { __index = function(_, k) if type(k) == "string" and k:find("^%u") then return Noop end end }
local function MakeFrame(parent)
	local f = setmetatable({ stubParent = parent }, FrameMT)
	function f:CreateTexture() return MakeFrame(self) end
	function f:CreateMaskTexture() return MakeFrame(self) end
	function f:GetParent() return self.stubParent end
	function f:GetFrameLevel() return 1 end
	function f:GetFrameStrata() return "MEDIUM" end
	function f:GetSize() return 100, 100 end
	function f:GetWidth() return 100 end
	function f:GetHeight() return 100 end
	function f:GetScale() return 1 end
	function f:GetEffectiveScale() return 1 end
	function f:IsShown() return true end
	return f
end
function CreateFrame(_, _, parent) return MakeFrame(parent) end
UIParent = MakeFrame(nil)
MelloUI_KitTuning = nil
KitStubNS = { MelloUI = { db = {} } }
MelloUI = KitStubNS.MelloUI
MelloUI.Perf = { Scope = function() return { hooksecurefunc = hooksecurefunc, C_Timer = C_Timer,
	SetScript = Noop, HookScript = Noop, Shared = function(_, fn) return fn end } end }
MelloUI.modules = { UIModifications = { db = {} } }
function MelloUI:GetModule(name) return self.modules[name] end
MelloUI.Print, MelloUI.Notice = Noop, Noop
'''

# One game session on the loaded Kit.lua: s.apply(section) is one
# Kit:ApplyTuning with that `pieces` section (PIECES and the backups live
# across every pass, as in game); s.get(name) a piece's file, uv and tile;
# s.pristine() the first piece not exactly as the layout has it (nil: every
# piece is, and no piece the tuning made is left).
KIT_SESSION_LUA = r'''function()
	local P = MelloUI_KitLayout.pieces
	local function copy(v)
		if type(v) ~= "table" then return v end
		local c = {}
		for k, x in pairs(v) do c[k] = copy(x) end
		return c
	end
	local function same(a, b)
		if type(a) ~= "table" or type(b) ~= "table" then return a == b end
		for k, x in pairs(a) do if not same(x, b[k]) then return false end end
		for k in pairs(b) do if a[k] == nil then return false end end
		return true
	end
	local layout = copy(P)
	local Kit, KT = MelloUI.Kit, MelloUI.KitTuning
	local s = {}
	function s.apply(section)
		local fake = setmetatable({}, { __index = KT })
		function fake:Globals() return {} end
		function fake:Section(name) if name == "pieces" then return section end return {} end
		Kit:ApplyTuning(fake)
	end
	function s.get(name)
		local p = P[name]
		if not p then return nil end
		local uv = p.uv or {}
		return p.file, uv[1], uv[2], uv[3], uv[4], p.tile
	end
	function s.pristine()
		for k, v in pairs(layout) do
			if not same(v, P[k]) then return k end
		end
		for k in pairs(P) do
			if layout[k] == nil then return k end
		end
		return nil
	end
	return s
end'''


class KitLoadError(Exception):
    """Modules/Kit.lua (or Core/KitTuning.lua) did not load under KIT_STUBS_LUA."""


def kit_tuning_session(layout_path, kit_path=None, tuning_path=None):
    """Core/KitTuning.lua and Modules/Kit.lua loaded in Lua 5.1 (the client's
    Lua, where lupa has it) over the layout at `layout_path`. Returns (lua,
    session): KIT_SESSION_LUA's."""
    try:
        import lupa.lua51 as lupa
    except ImportError:
        import lupa
    lua = lupa.LuaRuntime()
    load = None
    try:
        lua.execute(KIT_STUBS_LUA)
        lua.execute(open(layout_path, encoding="utf-8").read())
        load = lua.eval("function(src, name) return assert(loadstring(src, name)) end")
        for path, chunk in ((tuning_path or KIT_TUNING_LUA, "=Core/KitTuning.lua"), (kit_path or KIT_LUA, "=Modules/Kit.lua")):
            load(open(path, encoding="utf-8").read(), chunk)("MelloUI", lua.globals().KitStubNS)
        return lua, lua.eval(KIT_SESSION_LUA)()
    except lupa.LuaError as e:
        raise KitLoadError(str(e).splitlines()[0] if str(e) else repr(e))


def test_tuning_remap(layout_path, kit_path=None, tuning_path=None):
    """Modules/Kit.lua's Kit:ApplyTuning on the option's layout, in Lua 5.1,
    as the game runs it: one Kit.lua, its PIECES and backups kept across
    every pass. Each case: a uv override in the former file's frame lands
    in the sheet; one past the piece is clamped; a file override to another
    atlased piece takes that piece's sheet; one to an unmoved piece
    restores the former-frame uv; a tile override on an atlased piece is
    dropped; an unmoved piece's override is left as written; a right-sized
    piece maps like an atlased one; a removed uv is the layout's; a piece
    the tuning invents with only a file draws the piece it names (a
    standalone or an atlased one), or its whole file, and goes with its
    tuning. Then, as the game does it: the same tuning applied three times
    gives the same PIECES; two tuned pieces pointing at each other are
    order-free; a field the override stops carrying and a piece no longer
    tuned go back to the layout exactly (checked before every case too).
    Returns (checks passed, checks run, failures); raises KitLoadError when
    the Lua does not load."""
    lay = load_layout(layout_path)
    atl = sorted(n for n, p in lay.items() if p.get("was") and p["file"].startswith("atlas"))
    rsz = sorted(n for n, p in lay.items() if p.get("was") and not p["file"].startswith("atlas"))
    std = sorted(n for n, p in lay.items() if not p.get("was") and not p.get("tile"))
    if (len(atl) < 2 and not rsz) or not std:
        return 0, 0, []                     # no moved pieces: nothing to remap
    lua, s = kit_tuning_session(layout_path, kit_path, tuning_path)
    tbl = lua.table_from
    fails, n = [], 0

    def fresh():
        # every tuning taken away: every piece exactly as the layout has it
        s.apply(tbl({}))
        left = s.pristine()
        if left is not None:
            fails.append("no tuning: the layout not restored at %s" % left)
        return s

    def run(name, over):
        fresh()
        s.apply(tbl({name: over}))
        return s.get(name)

    def check(label, got, want):
        nonlocal n
        n += 1
        ok = isinstance(got, tuple) and len(got) == 6 and got[0] == want[0] and \
            all(isinstance(x, (int, float)) and abs(x - y) < 1e-9 for x, y in zip(got[1:5], want[1:5])) and got[5] == want[5]
        if not ok:
            fails.append("%s: got %s want %s" % (label, tuple(got) if isinstance(got, tuple) else got, tuple(want)))

    def truth(label, cond, detail=""):
        nonlocal n
        n += 1
        if not cond:
            fails.append("%s%s" % (label, (": " + detail) if detail else ""))

    def mapped(uv, was, rect):
        res = []
        for i in range(4):
            lo, hi = (0, 1) if i < 2 else (2, 3)
            f = min(1.0, max(0.0, (uv[i] - was[lo]) / (was[hi] - was[lo])))
            res.append(rect[lo] + f * (rect[hi] - rect[lo]))
        return res
    s0 = lay[std[0]]
    # an unmoved piece's own override: as written
    check("unmoved uv", run(std[0], tbl({"uv": tbl([0, 0.5, 0, 0.5])})), (s0["file"], 0, 0.5, 0, 0.5, s0.get("tile")))
    # an override that removes the uv: the layout's (every piece is drawn by a uv)
    check("uv removed", run(std[0], tbl({"uv": KT_NIL})), (s0["file"], *s0["uv"], s0.get("tile")))
    # a piece the tuning invents, given only a file: what that file shows
    inv = "tuningtest/invented"
    while inv in lay:
        inv += "_"
    check("invented piece, file -> unmoved piece", run(inv, tbl({"file": std[0].replace("/", "\\")})),
          (s0["file"], *s0["uv"], None))
    check("invented piece, file no piece has: the whole file", run(inv, tbl({"file": "tuningtest\\new_art"})),
          ("tuningtest\\new_art", 0, 1, 0, 1, None))
    if atl:
        a0 = lay[atl[0]]
        check("invented piece, file -> atlased piece", run(inv, tbl({"file": atl[0].replace("/", "\\")})),
              (a0["file"], *a0["uv"], None))
    s.apply(tbl({}))
    truth("an invented piece goes with its tuning", s.get(inv) is None)
    if rsz:
        # a right-sized piece keeps its file; its uv maps like a sheet's
        r = lay[rsz[0]]
        check("right-sized uv = was", run(rsz[0], tbl({"uv": tbl(r["was"])})), (r["file"], *r["uv"], r.get("tile")))
        check("right-sized uv past the piece", run(rsz[0], tbl({"uv": tbl([0.0, 1.0, 0.0, 1.0])})),
              (r["file"], *r["uv"], r.get("tile")))
    # the re-apply cases, on an atlased piece where there is one (else a
    # right-sized one)
    mv = atl[0] if atl else rsz[0]
    m = lay[mv]
    half = [m["was"][0], (m["was"][0] + m["was"][1]) / 2, m["was"][2], m["was"][3]]
    want_half = (m["file"], m["uv"][0], (m["uv"][0] + m["uv"][1]) / 2, m["uv"][2], m["uv"][3], m.get("tile"))
    fresh()
    sec = tbl({mv: tbl({"uv": tbl(half)})})
    for k in range(3):
        s.apply(sec)
        check("uv = left half, pass %d of 3 (no compounding)" % (k + 1), s.get(mv), want_half)
    # the override loses its uv while the piece stays tuned: uv back to the layout
    s.apply(tbl({mv: tbl({"scale": 2})}))
    check("uv dropped, piece still tuned", s.get(mv), (m["file"], *m["uv"], m.get("tile")))
    # the tuning goes: the whole layout exactly as it was
    s.apply(tbl({}))
    left = s.pristine()
    truth("untuned: every piece as the layout has it", left is None, "differs at %s" % left)
    if len(atl) < 2:
        return n - len(fails), n, fails
    a, b = lay[atl[0]], lay[atl[1]]
    # the override repeats the piece's own former uv: exactly its sheet rect
    check("uv = was", run(atl[0], tbl({"uv": tbl(a["was"])})), (a["file"], *a["uv"], None))
    # past the piece (into its former canvas padding): clamped to its rect
    check("uv past the piece", run(atl[0], tbl({"uv": tbl([0.0, 1.0, 0.0, 1.0])})), (a["file"], *a["uv"], None))
    # file -> another atlased piece, no uv: that piece's sheet, this piece's
    # former uv mapped through its frame
    want_ab = (b["file"], *mapped(a["was"], b["was"], b["uv"]), None)
    check("file -> atlased piece", run(atl[0], tbl({"file": atl[1].replace("/", "\\")})), want_ab)
    # file -> atlased piece with a uv: the uv mapped through that frame
    check("file + uv -> atlased piece", run(atl[0], tbl({"file": atl[1].replace("/", "\\"), "uv": tbl(b["was"])})),
          (b["file"], *b["uv"], None))
    # file -> an unmoved piece, no uv: its file, this piece's former uv
    check("file -> unmoved piece", run(atl[0], tbl({"file": std[0].replace("/", "\\")})),
          (s0["file"], *a["was"], None))
    # tile on an atlased piece: dropped, file and uv untouched
    check("tile on an atlased piece", run(atl[0], tbl({"tile": "x"})), (a["file"], *a["uv"], None))
    # a points at b while b has its own uv override, applied three times:
    # a reads b's LAYOUT frame whichever piece the loop meets first
    fresh()
    half_b = [b["was"][0], (b["was"][0] + b["was"][1]) / 2, b["was"][2], b["was"][3]]
    want_bh = (b["file"], b["uv"][0], (b["uv"][0] + b["uv"][1]) / 2, b["uv"][2], b["uv"][3], None)
    sec = tbl({atl[0]: tbl({"file": atl[1].replace("/", "\\")}), atl[1]: tbl({"uv": tbl(half_b)})})
    for k in range(3):
        s.apply(sec)
        check("a -> b, b tuned too, pass %d: a" % (k + 1), s.get(atl[0]), want_ab)
        check("a -> b, b tuned too, pass %d: b" % (k + 1), s.get(atl[1]), want_bh)
    s.apply(tbl({}))
    left = s.pristine()
    truth("a -> b untuned: every piece as the layout has it", left is None, "differs at %s" % left)
    return n - len(fails), n, fails


# ---------------------------------------------------------------- summaries

def folder_of(rel):
    return rel.split("/")[0]


def summarise(rows, key_bytes, key_gpu):
    out = {}
    for r in rows:
        f = folder_of(r["rel"])
        for k in (f, "TOTAL"):
            s = out.setdefault(k, {"files": 0, "disk": 0, "gpu": 0})
            s["files"] += 1
            s["disk"] += r[key_bytes]
            s["gpu"] += r[key_gpu]
    for s in out.values():
        s["disk_mib"] = round(s["disk"] / MIB, 2)
        s["gpu_mib"] = round(s["gpu"] / MIB, 2)
    return out


def quality_summary(files, pieces):
    """Over every drawn item of an option -- a standalone file's drawn
    rectangle, or a piece in its sheet -- the compressed ones' display
    quality and gate failures, and how many are uncompressed."""
    items = [r for r in files if not r.get("pieces")] + list(pieces)
    dxt = [r for r in items if r["fmt"] != "tga"]
    out = {"items": len(items), "dxt_items": len(dxt), "uncompressed_items": len(items) - len(dxt)}
    if not dxt:
        return out
    ps = np.array([float(r["disp_psnr_rgb"]) for r in dxt])
    fp = np.array([float(r["file_psnr_rgb"]) for r in dxt])
    fails = [r for r in dxt if r["gate"]]

    def kind(r, word):
        return word in r["gate"]
    out.update({
        "disp_psnr_median": round(float(np.median(ps)), 2), "disp_psnr_p5": round(float(np.percentile(ps, 5)), 2),
        "disp_psnr_min": round(float(ps.min()), 2),
        "file_psnr_median": round(float(np.median(fp)), 2), "file_psnr_min": round(float(fp.min()), 2),
        "disp_p999_max": round(max(float(r["disp_p999_rgb"]) for r in dxt), 1),
        "alpha_psnr_min": round(min(float(r["file_psnr_a"]) for r in dxt), 2),
        "alpha_max": round(max(float(r["file_max_a"]) for r in dxt), 1),
        "gate_fail": len(fails),
        "gate_fail_display": sum(1 for r in fails if kind(r, "at display size")),
        "gate_fail_nomip": sum(1 for r in fails if kind(r, "no mips")),
        # failing ONLY under the no-mip model (level 0 alone), nothing else
        "gate_fail_nomip_only": sum(1 for r in fails if kind(r, "no mips") and r["gate"].count(";") == 0),
        "gate_fail_dark_mean": sum(1 for r in fails if re.search(r"drift [+-]", r["gate"])),
        "gate_fail_dark_local": sum(1 for r in fails if kind(r, "8x8 area")),
        "worst": [{"rel": r["rel"], "where": r.get("sheet") or "", "disp_psnr": r["disp_psnr_rgb"],
                   "disp_p999": r["disp_p999_rgb"], "file_psnr": r["file_psnr_rgb"], "gate": r["gate"]}
                  for r in sorted(dxt, key=lambda r: float(r["disp_psnr_rgb"]))[:12]],
        "worst_dark": [{"rel": r["rel"], "where": r.get("sheet") or "", "dark_bias": r.get("dark_bias"),
                        "dark_local": r.get("dark_local"), "gate": r["gate"]}
                       for r in sorted([r for r in dxt if r.get("dark_bias")],
                                       key=lambda r: -max(abs(x) for x in r["dark_bias"]))[:10]],
    })
    return out


def preload_stats(layout, rows_by_stem):
    """The loading-screen preload of each look (Kit:KitFiles: the six edge
    masks and every piece's file in the look, each file once)."""
    import kit_palette
    out = {}
    for look in LOOKS:
        files = {m for m in MASKS}
        for n, p in layout.items():
            root = look if (look == "Kit" or kit_palette.recoloured(n)) else "Kit"
            files.add(root + "/" + p["file"].replace("\\", "/"))
        disk = gpu = 0
        missing = []
        for f in files:
            r = rows_by_stem.get(f)
            if r is None:
                missing.append(f)
                continue
            disk += r[0]
            gpu += r[1]
        out[look] = {"files": len(files), "disk_mib": round(disk / MIB, 2), "gpu_mib": round(gpu / MIB, 2),
                     "missing": missing[:5]}
    return out


def write_csv(path, rows, keys=None):
    if not rows:
        return
    keys = keys or sorted({k for r in rows for k in r.keys() if k not in ("image", "src", "info", "rs")})
    with open(path, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=keys, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow({k: (json.dumps(v) if isinstance(v, (list, tuple, dict)) else v) for k, v in r.items() if k in keys})


def read_csv(path):
    if not os.path.exists(path):
        return []
    rows = list(csv.DictReader(open(path, encoding="utf-8")))
    for r in rows:
        for k, v in list(r.items()):
            if v and v[:1] in "[{":
                try:
                    r[k] = json.loads(v)
                except ValueError:
                    pass
    return rows


# ---------------------------------------------------------------- samples

def _font(size, bold=False):
    path = os.path.join(ADDON_MEDIA, "Fonts", "NotoSans", "NotoSans-%s.ttf" % ("Bold" if bold else "Regular"))
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.load_default()


def _over(img, bg):
    a = img[..., 3:4].astype(np.float32) / 255
    if not isinstance(bg, np.ndarray):
        bg = np.array(bg, np.float32)[None, None, :]
    return np.clip(img[..., :3] * a + bg * (1 - a) + 0.5, 0, 255).astype(np.uint8)


def _tile_bg(tile_rgba, h, w):
    t = tile_rgba[..., :3]
    reps = (h // t.shape[0] + 1, w // t.shape[1] + 1, 1)
    return np.tile(t, reps)[:h, :w].astype(np.float32)


def _worst_window(err, win):
    h, w = err.shape
    win_h, win_w = min(win, h), min(win, w)
    c = np.pad(err, ((1, 0), (1, 0))).cumsum(0).cumsum(1)
    s = c[win_h:, win_w:] - c[:-win_h, win_w:] - c[win_h:, :-win_w] + c[:-win_h, :-win_w]
    y, x = np.unravel_index(np.argmax(s), s.shape)
    return int(y), int(x), win_h, win_w


def _triple(src_rgb, dec_rgb, zoom, win):
    err = np.abs(src_rgb.astype(np.int32) - dec_rgb.astype(np.int32)).sum(-1).astype(np.float64)
    y, x, hh, ww = _worst_window(err, win)
    cs = src_rgb[y:y + hh, x:x + ww]
    cd = dec_rgb[y:y + hh, x:x + ww]
    diff = np.clip(np.abs(cs.astype(np.int32) - cd.astype(np.int32)) * 8, 0, 255).astype(np.uint8)
    return (x, y, ww, hh), [np.repeat(np.repeat(t, zoom, 0), zoom, 1) for t in (cs, cd, diff)]


COLUMNS = ("Original (TGA)", "BLP, as the GPU decodes it", "|difference| x 8")
COLUMNS_RS = ("Source: the TGA right-sized (d's master)", "BLP, as the GPU decodes it", "|difference| x 8")
INK, SUB, OK_INK, WARN_INK = (238, 228, 205), (178, 168, 148), (150, 205, 140), (240, 170, 90)


def _text_lines(dr, x, y, lines):
    for text, font, colour in lines:
        dr.text((x, y), text, fill=colour, font=font)
        y += font.size + 8
    return y


def sample_panel(head, src_rgb, dec_rgb, path, big=512, columns=COLUMNS):
    """Rows 1x / 2x / 4x (nearest neighbour) round the worst area; columns
    source / BLP / |difference| x 8; head: [(text, font, colour)]."""
    rows = [(zoom,) + _triple(src_rgb, dec_rgb, zoom, big // zoom) for zoom in (1, 2, 4)]
    small = _font(17)
    colw = max(t.shape[1] for _, _, ts in rows for t in ts)
    pad = 14
    probe = ImageDraw.Draw(Image.new("RGB", (8, 8)))
    head_h = sum(f.size + 8 for _, f, _ in head) + 36
    rowh = [max(t.shape[0] for t in ts) + 30 for _, _, ts in rows]
    W = max(pad + 3 * (colw + pad), 900, max(int(probe.textlength(t, font=f)) for t, f, _ in head) + 2 * pad)
    H = head_h + sum(rowh) + pad
    canvas = Image.new("RGB", (W, H), (28, 26, 24))
    dr = ImageDraw.Draw(canvas)
    y = _text_lines(dr, pad, 10, head)
    for i, lab in enumerate(columns):
        dr.text((pad + i * (colw + pad), y + 4), lab, fill=SUB, font=small)
    y0 = head_h
    for (zoom, (x, y, ww, hh), tiles), rh in zip(rows, rowh):
        dr.text((pad, y0), "%dx  (file px %d,%d, %dx%d)" % (zoom, x, y, ww, hh), fill=SUB, font=small)
        for i, t in enumerate(tiles):
            canvas.paste(Image.fromarray(t), (pad + i * (colw + pad), y0 + 24))
        y0 += rh
    canvas.save(path)
    return path


def _on_dark(img):
    """Straight RGBA (float) over the dark window colour, as uint8 RGB."""
    a = img[..., 3:4] / 255
    return np.clip(img[..., :3] * a + np.array(DARK, np.float32) * (1 - a) + 0.5, 0, 255).astype(np.uint8)


def display_compare(title, notes, variants, sizes, path, ref=0, diff=None):
    """Right-sizing at the size the screen shows it. variants: [(label,
    straight RGBA levels (level 0 first), mips, drawn (w, h) in level-0
    texels)], each through the GPU model at each on-screen size (w, h px),
    over the dark window colour, side by side, with its dB against
    variants[ref] at that size (premultiplied, alpha-weighted, as the
    report); `diff`: a last column |variants[diff] - variants[ref]| x 8.
    Returns {size label: {variant label: dB}}."""
    font, small = _font(28, True), _font(20)
    pad = 14
    cells, scores = [], {}
    for lab_s, (w, h) in sizes:
        shown = []
        for lab_v, levels, mips, (cw, ch) in variants:
            lv = [x.astype(np.float32) for x in levels]
            shown.append(display(lv, (0, 0, cw, ch), max(cw / w, ch / h), (False, False), mips))
        hh, ww = min(x.shape[0] for x in shown), min(x.shape[1] for x in shown)
        shown = [x[:hh, :ww] for x in shown]
        k = 200 // max(ww, hh) + 1 if max(ww, hh) < 200 else 1
        label = lab_s if k == 1 else "%s (shown %dx, nearest neighbour)" % (lab_s, k)
        row, sc = [], {}
        for (lab_v, _, _, _), img in zip(variants, shown):
            db = err_stats(shown[ref], img)["psnr_rgb"]
            sc[lab_v] = db
            row.append((lab_v, "reference" if img is shown[ref] else "%.1f dB against the reference" % db, _on_dark(img)))
        if diff is not None:
            e = np.abs(_on_dark(shown[diff]).astype(np.int32) - _on_dark(shown[ref]).astype(np.int32)) * 8
            row.append(("|%s - reference| x 8" % variants[diff][0].split(":")[0], "", np.clip(e, 0, 255).astype(np.uint8)))
        row = [(a, b, Image.fromarray(c).resize((c.shape[1] * k, c.shape[0] * k), Image.NEAREST) if k > 1
                else Image.fromarray(c)) for a, b, c in row]
        cells.append((label, row))
        scores[lab_s] = sc
    ncol = len(cells[0][1])
    probe = ImageDraw.Draw(Image.new("RGB", (8, 8)))
    colw = max(260, max(im.width for _, r in cells for _, _, im in r),
               max(int(probe.textlength(a, font=small)) for _, r in cells for a, _, _ in r) + 8)
    W = max(pad + ncol * (colw + pad), int(probe.textlength(title, font=font)) + 2 * pad,
            max([int(probe.textlength(t, font=small)) for t in notes] or [0]) + 2 * pad)
    head_h = 56 + len(notes) * 28
    H = head_h + sum(max(im.height for _, _, im in r) + 96 for _, r in cells) + pad
    canvas = Image.new("RGB", (W, H), (28, 26, 24))
    dr = ImageDraw.Draw(canvas)
    dr.text((pad, 10), title, fill=INK, font=font)
    for i, t in enumerate(notes):
        dr.text((pad, 52 + i * 28), t, fill=SUB, font=small)
    y0 = head_h + 6
    for label, r in cells:
        dr.text((pad, y0), label, fill=INK, font=small)
        for i, (lab_v, lab_db, im) in enumerate(r):
            x = pad + i * (colw + pad)
            dr.text((x, y0 + 27), lab_v, fill=INK, font=small)
            dr.text((x, y0 + 52), lab_db, fill=SUB, font=small)
            canvas.paste(im, (x, y0 + 82))
        y0 += max(im.height for _, _, im in r) + 96
    canvas.save(path)
    return scores


# key, title, parts (Media-relative TGAs, side by side), background, note
SAMPLES = [
    ("page_stone", "Page stone (painted, the stone behind every page)", ["Kit/backdrops/page_stone.tga"], "dark", ""),
    ("page_parchment", "Page parchment", ["Kit/backdrops/page_parchment.tga"], "dark", ""),
    ("gem_corner_warm", "Gem corner, Warm iron", ["KitWarm/window/frame_gem_tl.tga"], "stone", ""),
    ("gem_corner_bronze", "Gem corner, Bronze (gold bevels)", ["KitBronze/window/frame_gem_tl.tga"], "stone", ""),
    ("portrait_ring", "Portrait ring, Warm iron", ["KitWarm/window/portrait_ring.tga"], "stone", ""),
    ("rail_kitwarm", "Top rail with its dark edge lines, Warm iron (frame_t x3)", ["KitWarm/window/frame_t.tga"] * 3, "stone",
     "the dark lines are the rail's shadow on the stone (kit-art-edge-shadows)"),
    ("rail_kit", "Top rail with its dark edge lines, painted (frame_t x3)", ["Kit/window/frame_t.tga"] * 3, "stone",
     "the dark lines are the rail's shadow on the stone (kit-art-edge-shadows)"),
    ("railmid_kitwarm", "Horizontal rail, Warm iron", ["KitWarm/deco/rail_mid.tga"], "stone", ""),
    ("railmid_kit", "Horizontal rail, painted", ["Kit/deco/rail_mid.tga"], "stone", ""),
    ("slice_frame_warm", "Window rails as one nine-slice picture, Warm iron (KitSlices)", ["KitWarm/slices/window_frame.tga"],
     "stone", "the eight rail pieces in one file (/mellokit slices on); every edge line as painted"),
    ("red_button_kitwarm", "Red button plate, Warm iron (cap, mid x2, cap)",
     ["KitWarm/buttons/redbtn_%s_normal.tga" % k for k in ("cap_l", "mid", "mid", "cap_r")], "dark",
     "Warm iron's red is built on the palette's deep red #4E1812 (kit_palette's RED ramp)"),
    ("red_button_kit", "Red button plate, painted (cap, mid x2, cap)",
     ["Kit/buttons/redbtn_%s_normal.tga" % k for k in ("cap_l", "mid", "mid", "cap_r")], "dark",
     "the painted look's own bright red, beside the rail's dark edge line"),
    ("frame_mid_bronze", "Bar frame middle, Bronze (dark line beside gold)", ["KitBronze/bars/frame_mid.tga"], "dark", ""),
    ("profession_card", "Profession card (alchemy)", ["Kit/cards/alchemy.tga"], "dark", ""),
    ("profession_backdrop", "Profession panel (alchemy)", ["Kit/backdrops/profession_alchemy.tga"], "dark", ""),
    ("profession_icon", "Profession round icon (herbalism)", ["Kit/icons/profession_herbalism.tga"], "dark", ""),
    ("medallion_alliance", "Faction medallion, Alliance", ["Icons/Faction/Alliance.tga"], "dark", ""),
    ("tag_forever", "Quest logo, Forever (thin white letters, blue border)", ["Textures/Quests/tag_forever.tga"], "vellum", ""),
    ("game_menu", "Game menu frame, Warm iron", ["Textures/GameMenuFrame_warm.tga"], "dark", ""),
    ("chat_shade", "Chat name shade (tinted #2E1F14 x 0.55 over vellum, as Chat.lua draws it)",
     ["Textures/Chat/name_shade.tga"], "vellum", "a soft gradient band; banding would show here first"),
]

# right-sized files shown at the size the screen draws them: key, file, title
ONSCREEN = [
    ("rightsize_gamemenu", "Textures/GameMenuFrame_warm.tga", "Game menu frame, Warm iron"),
    ("rightsize_alliance", "Icons/Faction/Alliance.tga", "Faction medallion, Alliance"),
    ("rightsize_classicon", "Icons/Class/MAGE.tga", "Class medallion, Mage"),
    ("rightsize_tag_forever", "Textures/Quests/tag_forever.tga", "Quest logo, Forever"),
]


def make_samples(out, layout):
    """The side-by-sides the user judges by eye, and one contact sheet.

    Per part of a sample: where option d ships it as DXT, the file (or the
    sheet rectangle) d ships; where d keeps it uncompressed, option b's DXT
    of it -- b's own file is what d's gate measures first (right-sized where
    b right-sizes it), so the panel shows what was rejected and d's verdict
    says why. A right-sized part is compared at file px against its
    right-sized master (the column says so); what the right-sizing itself
    costs, and d's file as shipped, show at on-screen size in the
    rightsize_* panels (against today's TGA)."""
    sdir = os.path.join(out, "samples")
    os.makedirs(sdir, exist_ok=True)
    for fn in os.listdir(sdir):
        if fn.lower().endswith(".png"):
            os.remove(os.path.join(sdir, fn))
    rep = os.path.join(out, "report")
    plans = {p["rel"]: p for p in plan_files()[0]}
    rec = {o: {r["rel"]: r for r in read_csv(os.path.join(rep, "files_%s.csv" % o))} for o in "abcd"}
    prec = {o: {r["rel"]: r for r in read_csv(os.path.join(rep, "pieces_%s.csv" % o))} for o in "cd"}
    cache = {}

    def decode(path, level=0):
        key = (path, level)
        if key not in cache:
            if path.endswith(".tga"):
                cache[key] = load_rgba(path)
            else:
                cache[key] = blp_dxt.decode_blp(open(path, "rb").read(), "gpu", level=level)
        return cache[key]

    def levels_of(path):
        """Every level of a written file (a TGA: its one), and whether it has mips."""
        if path.endswith(".tga"):
            return [load_rgba(path)], False
        data = open(path, "rb").read()
        hd = blp_dxt.read_blp_header(data)
        n = blp_dxt.mip_count(hd["w"], hd["h"]) if hd["has_mips"] else 1
        return [blp_dxt.decode_blp(data, "gpu", level=i) for i in range(n)], n > 1

    def fmt_name(r):
        f = r["fmt"].upper().replace("DXT1A", "DXT1 1-bit alpha")
        return "uncompressed TGA" if f == "TGA" else f

    def part(rel, option):
        """(source, decoded, record, where) of the drawn part of rel in option."""
        p = plans[rel]
        if option in prec and rel in prec[option]:
            r = prec[option][rel]
            x, y, w, h = r["rect"]
            sheet = os.path.join(out, option, r["sheet"][:-4].replace("/", os.sep) + (".tga" if r["fmt"] == "tga" else ".blp"))
            src = plan_image(p, p["rs"])[:h, :w]
            return src, decode(sheet)[y:y + h, x:x + w], r, "in sheet %s (option %s)" % (r["sheet"][:-4], option)
        r = rec[option][rel]
        rs = p["rs"] if option != "a" else None
        src = plan_image(p, rs)
        cw, ch = r["content"]
        return src[:ch, :cw], decode(r["dst"])[:ch, :cw], r, "own file %sx%s (option %s)" % (r["w"], r["h"], option)

    vellum = load_rgba(os.path.join(MEDIA, "Kit", "tiles", "vellum.tga"))
    stone = load_rgba(os.path.join(MEDIA, "KitWarm", "window", "frame_body.tga"))
    title_f, info_f = _font(24, True), _font(18)

    # right-sizing at the size the screen shows it, through the GPU model,
    # against today's TGA: first, so the samples can quote it
    comps, onscreen = [], {}
    for key, rel, label in ONSCREEN:
        if rel not in plans or rel not in rec["b"] or rel not in rec["d"] or not plans[rel]["rs"]:
            continue
        p = plans[rel]
        upp = p["info"]["upp"]
        today = load_rgba(p["src"])
        cw0, ch0 = p["info"]["content"]
        chain, _ = blp_dxt.mip_chain(today, FMT_OF[p["cls"]], True)
        chain = [today] + chain[1:]            # level 0 exactly as painted (mip_chain bleeds it)
        rb, rd = rec["b"][rel], rec["d"][rel]
        lb, mb = levels_of(rb["dst"])
        ld, md = levels_of(rd["dst"])
        cb, cd = tuple(rb["content"]), tuple(rd["content"])
        d_is_b = rd["fmt"] != "tga"
        vs = [("TGA today %dx%d, ideally filtered" % (today.shape[1], today.shape[0]), chain, True, (cw0, ch0)),
              ("TGA today, level 0 alone (a TGA has no mips)", [today], False, (cw0, ch0))]
        if d_is_b:
            vs.append(("option d (= b): %s %sx%s%s, as shipped" % (fmt_name(rd), rd["w"], rd["h"], " + mips" if md else ""), ld, md, cd))
        else:
            why = (rd.get("why") or "").replace("gate: ", "")
            vs.append(("option b: %s %sx%s%s, rejected by d's gate" % (fmt_name(rb), rb["w"], rb["h"], " + mips" if mb else ""), lb, mb, cb))
            vs.append(("option d: %s %sx%s, as shipped" % (fmt_name(rd), rd["w"], rd["h"]), ld, md, cd))
        sizes = []
        for dk, _, px in (DISPLAYS[0], DISPLAYS[2]):
            w, h = max(1, round(cw0 * upp * px)), max(1, round(ch0 * upp * px))
            sizes.append(("%s: %dx%d screen px" % (dk, w, h), (w, h)))
        notes = ["Reference: today's %dx%d TGA (its drawn %dx%d) with ideal mips. Right-sized to %sx%s for options b and d; "
                 "the dB here count both the halving and DXT." % (today.shape[1], today.shape[0], cw0, ch0, rd["w"], rd["h"]),
                 "A TGA carries no mips: if the client makes none for it, today's TGA looks like the second column (and "
                 "option d's TGA likewise samples its one level)."]
        if not d_is_b:
            notes.append("Option d keeps it uncompressed (no DXT) because %s." % why)
        path = os.path.join(sdir, key + ".png")
        sc = display_compare("%s at on-screen size (GPU model), option d against today's TGA" % label, notes, vs, sizes, path,
                             ref=0, diff=len(vs) - 1)
        first = sc[sizes[0][0]]
        onscreen[rel] = {"png": key + ".png", "d_db": first[vs[-1][0]], "today_l0_db": first[vs[1][0]],
                         "b_db": first[vs[2][0]]}
        comps.append({"key": key, "title": label + " at on-screen size", "png": path, "scores": sc})

    made = []
    for key, title, parts, bg, note in SAMPLES:
        if not all(r in plans and r in rec["b"] and (r in rec["d"] or r in prec["d"]) for r in parts):
            continue
        uniq = list(dict.fromkeys(parts))
        dstat = {r: prec["d"].get(r) or rec["d"].get(r) for r in uniq}
        use = {r: "d" if dstat[r]["fmt"] != "tga" else "b" for r in uniq}
        d_dxt = all(u == "d" for u in use.values())
        got = {r: part(r, use[r]) for r in uniq}
        hmin = min(got[r][0].shape[0] for r in uniq)
        s = np.concatenate([got[r][0][:hmin] for r in parts], 1)
        d = np.concatenate([got[r][1][:hmin] for r in parts], 1)
        if key == "chat_shade":
            def shade(img):
                o = img.astype(np.float32).copy()
                o[..., :3] = o[..., :3] * np.array([0.180, 0.122, 0.078], np.float32)
                o[..., 3] = o[..., 3] * 0.55
                return np.clip(o + 0.5, 0, 255).astype(np.uint8)
            s, d = np.tile(shade(s), (4, 2, 1)), np.tile(shade(d), (4, 2, 1))
        bgi = {"stone": lambda h, w: _tile_bg(stone, h, w), "vellum": lambda h, w: _tile_bg(vellum, h, w)}.get(bg)
        bgi = bgi(*s.shape[:2]) if bgi else DARK
        so, do = _over(s, bgi), _over(d, bgi)
        resized = [r for r in uniq if plans[r]["rs"]]
        # the head: what is shown, per part, and option d's verdict on it
        shown, verdict = [], []
        for r in uniq:
            _, _, rr, where = got[r]
            shown.append("%s: %s, %s | %.1f dB on screen, %.1f at file px" % (
                r[:-4], fmt_name(rr), where, float(rr["disp_psnr_rgb"]), float(rr["file_psnr_rgb"])))
            st, short = dstat[r], r[:-4].split("/", 1)[1]
            if use[r] == "d":
                verdict.append("%s: option d ships this DXT" % short)
                continue
            where = ("in uncompressed sheet " + st["sheet"][:-4]) if st.get("sheet") else \
                "as a %sx%s TGA file" % (st["w"], st["h"])
            verdict.append("%s: option d keeps it UNCOMPRESSED, %s" % (short, where))
            why = (st.get("why") or "").replace("gate: ", "")
            if why:
                verdict.append("    because %s" % why)
            own = rec["b"][r]["gate"]
            if st.get("sheet") and not own:
                verdict.append("    (option b's DXT of this look's own file, shown, passes the gate itself)")
            elif own and not why.endswith(own):
                verdict.append("    option b's DXT of this file, shown: %s" % own)
        if d_dxt:
            line = ("Shown: what option d ships", info_f, SUB)
        elif all(u == "b" for u in use.values()):
            line = ("Shown: option b's DXT -- what d's gate measured; option d ships it uncompressed (lossless)", info_f, WARN_INK)
        else:
            line = ("Shown: option d's DXT where it ships one; option b's DXT (what d's gate measured) where d keeps a part "
                    "uncompressed", info_f, WARN_INK)
        head = [(title, title_f, INK), line]
        head += [(t, info_f, SUB) for t in shown]
        head += [(t, info_f, OK_INK if "ships" in t else WARN_INK) for t in verdict]
        for r in resized:
            p = plans[r]
            (cw0, ch0), (ncw, nch), (nsw, nsh) = p["info"]["content"], p["rs"]["canvas"], p["rs"]["content"]
            txt = "Right-sized: %s draws %dx%d of its %dx%d TGA; option b / d draw %dx%d of a %dx%d file. The first column is " \
                  "that right-sized master, not today's TGA." % (r[:-4].split("/")[-1], cw0, ch0, p["size"][0], p["size"][1],
                                                                 nsw, nsh, ncw, nch)
            head.append((txt, info_f, SUB))
            if r in onscreen:
                o = onscreen[r]
                head.append(("On screen at 1440p against today's TGA ideally filtered: option d as shipped %.1f dB%s; today's "
                             "TGA drawn without mips %.1f dB. See %s" % (
                                 o["d_db"], "" if o["b_db"] == o["d_db"] else ", option b's DXT %.1f" % o["b_db"],
                                 o["today_l0_db"], o["png"]), info_f, SUB))
        if note:
            head.append((note, info_f, SUB))
        columns = COLUMNS_RS if resized else COLUMNS
        path = os.path.join(sdir, key + ".png")
        sample_panel(head, so, do, path, columns=columns)
        m = err_stats(s.astype(np.float32), d.astype(np.float32))
        made.append({"key": key, "title": title, "png": path, "options_shown": use, "head": [t for t, _, _ in head],
                     "head_colours": [c for _, _, c in head],
                     "d_ships_dxt": d_dxt, "columns": list(columns), "panel_psnr_rgb": m["psnr_rgb"], "so": so, "do": do})

    # an atlas sheet of option d, the warm look
    sheet_rel = "KitWarm/atlas/sheet_1"
    sheet_blp = os.path.join(out, "d", sheet_rel.replace("/", os.sep) + ".blp")
    prev = os.path.join(rep, "atlas_d_KitWarm_sheet_1.png")
    if os.path.exists(sheet_blp) and os.path.exists(prev):
        s, d = load_rgba(prev), decode(sheet_blp)
        so, do = _over(s, _tile_bg(stone, *s.shape[:2])), _over(d, _tile_bg(stone, *s.shape[:2]))
        n_p = sum(1 for r in prec["d"].values() if r["sheet"] == sheet_rel + ".tga")
        fmt = blp_dxt.fmt_of(blp_dxt.read_blp_header(open(sheet_blp, "rb").read())).upper()
        head = [("Atlas sheet, option d: KitWarm/atlas/sheet_1 (%s, %dx%d)" % (fmt, s.shape[1], s.shape[0]), title_f, INK),
                ("%d small pieces that pass the gate in every look, each starting on the 4 px block grid with its edges extruded" % n_p, info_f, SUB),
                ("every piece in it was measured in its own rectangle of this very sheet", info_f, OK_INK)]
        columns = ("The sheet as assembled (TGA pixels)",) + COLUMNS[1:]
        path = os.path.join(sdir, "atlas_sheet_warm.png")
        sample_panel(head, so, do, path, columns=columns)
        made.append({"key": "atlas_sheet_warm", "title": head[0][0], "png": path, "options_shown": {sheet_rel: "d"},
                     "head": [t for t, _, _ in head], "head_colours": [c for _, _, c in head], "d_ships_dxt": True, "columns": list(columns), "so": so, "do": do})

    contact_sheet(made, comps, os.path.join(sdir, "contact_sheet.png"))
    for m in made:
        m.pop("so", None)
        m.pop("do", None)
        m.pop("head_colours", None)
    return made, comps


def contact_sheet(made, comps, path, cell=288, per_row=2):
    """One page to read in the morning: a legend, then every sample as its
    worst area -- source, BLP, difference x 8, nearest neighbour, zoomed to
    fill a 288 px cell (2x for the big pictures, up to 8x for a small
    piece) -- under its title and option d's verdict; the right-sizing
    panels (on-screen size, against today's TGA) last."""
    pad, gap = 20, 10
    tile_w = 3 * cell + 2 * gap
    title_f, info_f, head_f = _font(20, True), _font(15), _font(30, True)
    probe = ImageDraw.Draw(Image.new("RGB", (8, 8)))

    def wrap(text, font, width, indent="    "):
        """text as lines no wider than width px (breaking at spaces)."""
        words, lines, cur = text.split(" "), [], ""
        for wd in words:
            t = (cur + " " + wd) if cur else wd
            if cur and probe.textlength(t, font=font) > width:
                lines.append(cur)
                cur = indent + wd
            else:
                cur = t
        lines.append(cur)
        return lines
    tiles = []
    for m in made:
        h, w = m["so"].shape[:2]
        zoom = max(2, min(8, cell // max(1, min(h, w, cell // 2))))
        (x, y, ww, hh), crops = _triple(m["so"], m["do"], zoom, cell // zoom)
        lines = [(t, title_f, INK) for t in wrap(m["title"], title_f, tile_w)]
        for t, colour in zip(m["head"][1:], m["head_colours"][1:]):
            lines += [(u, info_f, colour) for u in wrap(t, info_f, tile_w)]
        lines.append(("%dx: file px %d,%d, %dx%d" % (zoom, x, y, ww, hh), info_f, SUB))
        tiles.append((lines, crops, m["columns"]))
    W = pad + per_row * (tile_w + 2 * pad)
    legend_text = [
        ("MelloUI textures: TGA against BLP (DXT), option d as recommended", head_f, INK),
        ("Each sample: its worst area, nearest neighbour, zoomed to fill the cell. Columns: source | the BLP as the GPU "
         "decodes it | |difference| x 8.", info_f, SUB),
        ("Green line: option d ships that part as DXT; the panel shows the file (or sheet rectangle) d ships.", info_f, OK_INK),
        ("Orange lines: option d keeps that part uncompressed (lossless); the panel then shows option b's DXT of it -- the "
         "file d's gate measured -- and why it was kept.", info_f, WARN_INK),
        ("Right-sized parts: the source column is the right-sized master (said on the tile); the panels at the end show them "
         "at on-screen size against today's TGA, with the file d ships.", info_f, SUB),
        ("dB 'on screen': at the size this client draws it (1440p, uiScale 0.70), only the drawn texels, alpha-weighted. "
         "Gate: >= %.0f dB, 99.9th-percentile error <= %.0f, dark texels drifting <= %.0f levels on average and <= %.0f "
         "in any 8x8 area." % (GATE_PSNR, GATE_P999, GATE_DARK_BIAS, GATE_DARK_LOCAL), info_f, SUB),
        ("Full panels with 1x / 2x / 4x rows: the PNG of the same name in this folder.", info_f, SUB),
    ]
    legend = []
    for t, f, c in legend_text:
        legend += [(u, f, c) for u in wrap(t, f, W - 2 * pad)]
    legend_h = sum(f.size + 8 for _, f, _ in legend) + 20
    rows = [tiles[i:i + per_row] for i in range(0, len(tiles), per_row)]
    row_text = [max(sum(f.size + 6 for _, f, _ in ls) for ls, _, _ in r) for r in rows]
    comp_imgs = []
    for c in comps:
        im = Image.open(c["png"]).convert("RGB")
        s = min(1.0, (W - 2 * pad) / im.width)
        comp_imgs.append(im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS) if s < 1 else im)
    H = pad + legend_h + sum(th + 26 + cell + 18 + pad for th in row_text) + sum(im.height + pad for im in comp_imgs) + pad
    sheet = Image.new("RGB", (W, H), (22, 21, 19))
    dr = ImageDraw.Draw(sheet)
    y = _text_lines(dr, pad, pad, legend) + 12
    for row, text_h in zip(rows, row_text):
        tile_h = text_h + 26 + cell + 18
        for i, (lines, crops, columns) in enumerate(row):
            x = pad + i * (tile_w + 2 * pad)
            dr.rectangle([x - 8, y - 8, x + tile_w + 8, y + tile_h - 4], outline=(60, 56, 50))
            ty = y
            for text, font, colour in lines:
                dr.text((x, ty), text, fill=colour, font=font)
                ty += font.size + 6
            cy = y + text_h + 4
            for k, lab in enumerate(columns):
                while probe.textlength(lab, font=info_f) > cell and len(lab) > 8:
                    lab = lab[:-2]
                dr.text((x + k * (cell + gap), cy), lab, fill=SUB, font=info_f)
            for k, t in enumerate(crops):
                sheet.paste(Image.fromarray(t), (x + k * (cell + gap), cy + 22))
        y += tile_h + pad
    for im in comp_imgs:
        sheet.paste(im, (pad, y))
        y += im.height + pad
    sheet.save(path)
    return path


# ---------------------------------------------------------------- probe

def make_probe(out):
    """Diagnostic BLPs for the in-game test (copy to Media/Probe/ in a test
    copy of the addon): which formats this client loads, whether it samples
    mips (each level a different colour: drawn small, the colour tells the
    level), and a non-square complete chain (256 x 64 down to 1 x 1)."""
    pdir = os.path.join(out, "probe")
    os.makedirs(pdir, exist_ok=True)
    font = _font(40, True)
    n = 256
    written = []
    # level colours: 0 white grid, then red, green, blue, yellow, magenta, cyan, orange, grey
    cols = [(255, 255, 255), (230, 40, 40), (40, 200, 60), (50, 90, 240), (240, 220, 40), (220, 50, 220),
            (40, 220, 220), (250, 140, 30), (128, 128, 128)]
    for fname, (w, h), label in (("mip_probe.blp", (n, n), "LEVEL 0"), ("mip_probe_wide.blp", (n, 64), "256x64 L0")):
        levels = []
        for i in range(blp_dxt.mip_count(w, h)):
            s = blp_dxt.mip_size(w, h, i)
            im = Image.new("RGBA", s, cols[i % len(cols)] + (255,))
            if i == 0:
                dr = ImageDraw.Draw(im)
                for k in range(0, max(s), 16):
                    dr.line([(k, 0), (k, s[1])], fill=(0, 0, 0, 255))
                    dr.line([(0, k), (s[0], k)], fill=(0, 0, 0, 255))
                dr.text((20, min(100, s[1] // 2 - 20)), label, fill=(0, 0, 0, 255), font=font)
            levels.append(np.asarray(im))
        data = blp_dxt.encode_blp(levels[0], "dxt1", mips=True, level_images=levels)
        open(os.path.join(pdir, fname), "wb").write(data)
        written.append(fname)
    # a file per format, labelled
    for fmt, label in (("dxt1", "DXT1"), ("dxt1a", "DXT1 1-bit"), ("dxt5", "DXT5")):
        im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
        dr = ImageDraw.Draw(im)
        if fmt == "dxt5":
            g = np.zeros((n, n, 4), np.uint8)
            yy, xx = np.mgrid[0:n, 0:n]
            r = np.hypot(xx - n / 2, yy - n / 2)
            g[..., :3] = (174, 133, 70)
            g[..., 3] = np.clip(255 * (1 - r / (n / 2)), 0, 255).astype(np.uint8)
            im = Image.fromarray(g)
            dr = ImageDraw.Draw(im)
        elif fmt == "dxt1":
            dr.rectangle([0, 0, n, n], fill=(78, 24, 18, 255))
        else:
            dr.ellipse([8, 8, n - 8, n - 8], fill=(141, 100, 47, 255))
        dr.text((30, 100), label, fill=(255, 255, 255, 255), font=font)
        a = np.asarray(im).copy()
        if fmt == "dxt1a":
            a[..., 3] = np.where(a[..., 3] >= 128, 255, 0)
            a[a[..., 3] == 0, :3] = 0
        data = blp_dxt.encode_blp(a, fmt, mips=False)
        open(os.path.join(pdir, "probe_%s.blp" % fmt), "wb").write(data)
        written.append("probe_%s.blp" % fmt)
    # which file an extension-less path picks: the same name as TGA and BLP
    for ext, label, col in (("blp", "BLP", (40, 120, 60, 255)), ("tga", "TGA", (120, 40, 40, 255))):
        im = Image.new("RGBA", (n, n), col)
        ImageDraw.Draw(im).text((60, 100), label, fill=(255, 255, 255, 255), font=font)
        path = os.path.join(pdir, "probe_order." + ext)
        if ext == "blp":
            open(path, "wb").write(blp_dxt.encode_blp(np.asarray(im), "dxt1"))
        else:
            im.save(path)
        written.append("probe_order." + ext)
    return written


# ---------------------------------------------------------------- ship: the masters -> the addon's Media

LUA_TOKEN = re.compile(r"""
      (?P<ws>\s+)
    | (?P<comment>--\[(?P<ceq>=*)\[.*?\](?P=ceq)\]|--[^\n]*)
    | (?P<lstr>\[(?P<seq>=*)\[.*?\](?P=seq)\])
    | (?P<str>"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*')
    | (?P<num>0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)
    | (?P<name>[A-Za-z_]\w*)
    | (?P<op>\.\.\.|\.\.|==|~=|<=|>=|.)
""", re.S | re.X)
LUA_KINDS = ("ws", "comment", "lstr", "str", "num", "name", "op")
MEDIA_PATH = re.compile(r"^Interface[\\/]AddOns[\\/]MelloUI[\\/]Media[\\/]([A-Za-z0-9_./\\-]*)$", re.I)


def _lua_unescape(s):
    def rep(m):
        c = m.group(1)
        if c.isdigit():
            return chr(int(c))
        return {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b", "f": "\f", "v": "\v"}.get(c, c)
    return re.sub(r"\\(\d{1,3}|.)", rep, s, flags=re.S)


def lua_tokens(text):
    """[(kind, value, line)] of a Lua source, comments and white space left
    out; a quoted string's value unescaped."""
    out, line = [], 1
    for m in LUA_TOKEN.finditer(text):
        kind = next(k for k in LUA_KINDS if m.group(k) is not None)
        tok = m.group(0)
        if kind == "str":
            out.append(("str", _lua_unescape(tok[1:-1]), line))
        elif kind == "lstr":
            body = tok[tok.index("[", 1) + 1:tok.rindex("]", 0, len(tok) - 1)]
            out.append(("str", body[1:] if body.startswith("\n") else body, line))
        elif kind not in ("ws", "comment"):
            out.append((kind, tok, line))
        line += tok.count("\n")
    return out


def _skip_group(toks, i):
    """The index past the bracket group opening at toks[i]."""
    pairs = {"(": ")", "[": "]", "{": "}"}
    depth, j = 0, i
    while j < len(toks):
        v = toks[j][1] if toks[j][0] == "op" else None
        if v in pairs:
            depth += 1
        elif v in (")", "]", "}"):
            depth -= 1
            if depth == 0:
                return j + 1
        j += 1
    return j


def _operand(toks, i, env, funcs):
    """One operand of a concatenation at toks[i]: (its value when it is a
    string, ADDON_NAME, a path variable or a path function called with a
    string, else None; the index past it; the known start of the path it
    builds, for a path function called with anything else)."""
    kind, val, _ = toks[i]
    if kind == "str":
        return val, i + 1, None
    if kind == "name":
        if val == "ADDON_NAME":
            return "MelloUI", i + 1, None
        if val in funcs and i + 1 < len(toks) and toks[i + 1][1] == "(":
            if i + 3 < len(toks) and toks[i + 2][0] == "str" and toks[i + 3][1] == ")":
                return funcs[val] + toks[i + 2][1], i + 4, None
            return None, _skip_group(toks, i + 1), funcs[val]
        j, simple = i + 1, True
        while j < len(toks):
            v = toks[j][1] if toks[j][0] == "op" else None
            if v in (".", ":"):
                j, simple = j + 2, False
            elif v in ("[", "("):
                j, simple = _skip_group(toks, j), False
            else:
                break
        return (env[val] if simple and val in env else None), j, None
    if kind == "op" and val in ("(", "{", "["):
        return None, _skip_group(toks, i), None
    return None, i + 1, None


def _chain(toks, i, env, funcs):
    """A concatenation from toks[i]: ([value or None per operand], index past
    it, the known start a path function gave its first operand)."""
    v, j, dyn = _operand(toks, i, env, funcs)
    parts = [v]
    while j < len(toks) and toks[j][1] == "..":
        v, j, _ = _operand(toks, j + 1, env, funcs)
        parts.append(v)
    return parts, j, dyn


def _media_rel(value):
    m = MEDIA_PATH.match(value or "")
    return m.group(1).replace("\\", "/") if m else None


def lua_refs(root=None):
    """Every path into Media the addon's Lua and TOC name, as far as they
    can be read without running them: the strings, ADDON_NAME, the path
    variables (NAME = "...\\Media\\...") and path functions (return "..." ..
    arg) of each file, concatenated. Returns (refs, dynamic, problems):
      refs     [(file, line, Media-relative path without extension, its
               extension as written: '.tga' / '.blp' / '')], a folder left out
      dynamic  [(file, line, the known start)]: paths finished at run time
               (DYNAMIC_PATHS expands the known ones into refs)
      problems a '.tga' written into a path the scan cannot follow."""
    root = root or ROOT
    refs, dynamic, problems = [], [], []
    files = []
    for dp, dns, fns in os.walk(root):
        rd = os.path.relpath(dp, root).replace(os.sep, "/")
        top = rd.split("/")[0]
        if top in ("Tools", "docs", ".git", ".github", ".claude") or "__pycache__" in rd:
            dns[:] = []
            continue
        for fn in fns:
            if fn.endswith((".lua", ".toc")):
                files.append(fn if rd == "." else rd + "/" + fn)
    for rel in sorted(files):
        if rel in USER_FILE_LISTS:
            continue
        text = open(os.path.join(root, rel), encoding="utf-8", errors="replace").read()
        if rel.endswith(".toc"):
            for n, line in enumerate(text.split("\n"), 1):
                m = re.match(r"^##\s*IconTexture:\s*(\S+)", line)
                if m and _media_rel(m.group(1)):
                    r = _media_rel(m.group(1))
                    stem, ext = os.path.splitext(r)
                    refs.append((rel, n, stem, ext.lower()))
            continue
        toks = lua_tokens(text)
        env, funcs = {}, {}
        i, n = 0, len(toks)
        while i < n:
            kind, val, line = toks[i]
            # local function F(p) return "...\\Media\\..." .. p end
            if val == "function" and i + 6 < n and toks[i + 1][0] == "name" and toks[i + 2][1] == "(" and \
                    toks[i + 3][0] == "name" and toks[i + 4][1] == ")" and toks[i + 5][1] == "return":
                parts, j, _ = _chain(toks, i + 6, env, funcs)
                if j < n and toks[j][1] == "end" and toks[j - 1][1] == toks[i + 3][1] and len(parts) > 1 and \
                        parts[-1] is None and all(isinstance(p, str) for p in parts[:-1]):
                    prefix = "".join(parts[:-1])
                    if _media_rel(prefix) is not None:
                        funcs[toks[i + 1][1]] = prefix
                        i = j + 1
                        continue
            # a string, or a path variable / function used as a value (not a
            # field -- t.name, t:name -- nor the name being assigned to)
            prev_tok = toks[i - 1][1] if i > 0 and toks[i - 1][0] == "op" else None
            next_tok = toks[i + 1][1] if i + 1 < n and toks[i + 1][0] == "op" else None
            starts = kind == "str" or (kind == "name" and (val in env or val in funcs or val == "ADDON_NAME") and
                                       prev_tok not in (".", ":") and next_tok != "=")
            if not starts or prev_tok == "..":
                i += 1
                continue
            parts, j, dyn = _chain(toks, i, env, funcs)
            known = []
            for p in parts:
                if p is None:
                    break
                known.append(p)
            prefix = "".join(known) if known else (dyn or "")
            rel_path = _media_rel(prefix)
            complete = len(known) == len(parts)
            if rel_path is not None:
                # a path variable: NAME = <path> as a statement (local or not),
                # not a table's field (after "{", "," or ";") nor t.NAME
                before = toks[i - 3][1] if i >= 3 and toks[i - 3][0] in ("op", "name") else None
                if complete and i >= 2 and toks[i - 1][1] == "=" and toks[i - 2][0] == "name" and \
                        (before == "local" or before not in ("{", ",", ";", ".", ":", "[")):
                    env[toks[i - 2][1]] = prefix
                tail = parts[-1] if isinstance(parts[-1], str) else ""
                if complete:
                    if rel_path and not rel_path.endswith("/"):
                        stem, ext = os.path.splitext(rel_path)
                        if ext.lower() not in (".tga", ".blp"):
                            stem, ext = rel_path, ""
                        refs.append((rel, line, stem, ext.lower()))
                else:
                    ends = DYNAMIC_PATHS.get((rel, rel_path))
                    ext = ".tga" if tail.lower().endswith(".tga") else ".blp" if tail.lower().endswith(".blp") else ""
                    if ends is not None:
                        for e in ends:
                            refs.append((rel, line, rel_path + e, ext))
                    elif ext:
                        problems.append("%s:%d: a path built at run time ends in '%s' (%s...): add it to "
                                        "DYNAMIC_PATHS so the ship keeps what it can name" % (rel, line, ext, rel_path))
                    elif rel_path.split("/")[0] not in SKIP_DIRS:
                        dynamic.append((rel, line, rel_path))
            i = max(j, i + 1)
    for (vfile, pat), ends in VALUE_ENDINGS.items():
        for f, line, stem, ext in list(refs):
            if f == vfile and re.search(pat, stem):
                refs.extend((f, line, stem + e, ext) for e in ends)
    return refs, dynamic, problems


def tga_pins(refs):
    """{Media-relative master path, lower case: where} for the files a Lua
    or TOC path names with '.tga': the client loads that file only, so it
    ships as a TGA whatever the gate says."""
    pins = {}
    for f, line, stem, ext in refs:
        if ext == ".tga":
            pins.setdefault((stem + ".tga").lower(), "%s:%d" % (f, line))
    return pins


def kit_uncoloured(kit_lua=None):
    """Modules/Kit.lua's UNCOLOURED (the Lua patterns of the pieces it reads
    from Media/Kit in every look), from its source; None if it is not there."""
    text = open(kit_lua or KIT_LUA, encoding="utf-8").read()
    m = re.search(r"^local UNCOLOURED = \{([^}]*)\}", text, re.M)
    return re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(1)) if m else None


def check_colour_rule(names, kit_lua=None):
    """Kit.lua (UNCOLOURED, where it reads a piece from) and kit_palette
    (SKIP, which pieces get a recoloured file in KitWarm / KitBronze) must
    agree on every piece: the ship lays out the looks' sheets by
    kit_palette's rule, the client reads them by Kit.lua's. Returns problems."""
    import kit_palette
    pats = kit_uncoloured(kit_lua)
    if not pats:
        return ["Modules/Kit.lua: no `local UNCOLOURED = { ... }` to check kit_palette.SKIP against"]
    try:
        import lupa.lua51 as lupa
    except ImportError:
        import lupa
    find = lupa.LuaRuntime().eval("function(s, p) return string.find(s, p) ~= nil end")
    problems = []
    for n in sorted(names):
        kit = not any(find(n, p) for p in pats)
        if kit != kit_palette.recoloured(n):
            problems.append("piece %s: Kit.lua reads it from %s, kit_palette %s it (UNCOLOURED and SKIP disagree)" % (
                n, "the look's folder" if kit else "Media/Kit", "recolours" if kit_palette.recoloured(n) else "does not recolour"))
    return problems


def check_refs(final, pieces, slices, refs):
    """Every file the addon will ask for exists in `final` (the Media-relative
    paths, lower case, Media will hold): each piece of the layout in every
    look (Kit.lua's PieceRoot: a piece kit_palette does not recolour is read
    from Media/Kit; the two rules checked to agree), each KitSlices.lua
    picture in every look, each Lua / TOC path. Without an extension the
    client finds a .blp or a .tga: exactly one must be there; with one, that
    file. Returns problems."""
    import kit_palette
    problems = check_colour_rule(pieces)

    def have(stem):
        return [e for e in (".blp", ".tga") if (stem + e).lower() in final]

    for n, p in sorted(pieces.items()):
        for look in LOOKS:
            root = look if (look == "Kit" or kit_palette.recoloured(n)) else "Kit"
            stem = root + "/" + p["file"].replace("\\", "/")
            h = have(stem)
            if len(h) != 1:
                problems.append("layout %s (%s): %s %s" % (n, look, stem, "missing" if not h else "is both .blp and .tga"))
    for prefix, e in sorted((slices or {}).items()):
        for look in LOOKS:
            for k in ("full", "hollow"):
                f = e.get(k)
                if isinstance(f, str):
                    stem = look + "/" + f.replace("\\", "/")
                    h = have(stem)
                    if len(h) != 1:
                        problems.append("KitSlices %s: %s %s" % (prefix, stem, "missing" if not h else "is both .blp and .tga"))
    for f, line, stem, ext in refs:
        if stem.split("/")[0] in SKIP_DIRS:
            continue
        if ext:
            if (stem + ext).lower() not in final:
                other = have(stem)
                problems.append("%s:%d names %s%s, which Media will not hold%s" % (
                    f, line, stem, ext, (" (it holds %s%s)" % (stem, other[0])) if other else ""))
        else:
            h = have(stem)
            if len(h) != 1:
                problems.append("%s:%d names %s: %s" % (f, line, stem, "missing" if not h else "both .blp and .tga"))
    return problems


def _sha(path):
    import hashlib
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _inside(path, root):
    """Whether path is root or lies under it (case as the file system has it)."""
    try:
        a, b = os.path.normcase(os.path.realpath(path)), os.path.normcase(os.path.realpath(root))
        return os.path.commonpath([a, b]) == b
    except ValueError:                     # another drive
        return False


def _files(root):
    """{Media-relative path: absolute path} of every file under root."""
    out = {}
    for dp, dns, fns in os.walk(root):
        rd = os.path.relpath(dp, root).replace(os.sep, "/")
        for fn in fns:
            out[fn if rd == "." else rd + "/" + fn] = os.path.join(dp, fn)
    return out


def ship_install(stage, rows, report, refs, check_only, record_path):
    """Bring the addon's Media in line with the staged option d (`stage`:
    its tree, `rows`: its file records). Writes only inside Media, only the
    texture files it makes and Media/KitLayout.lua / KitSlices.lua; removes
    only files it made before (its record), copies of masters, and BLPs or
    atlas sheets at paths only it writes. Anything else in the way stops it
    before a byte is written. Returns the exit code."""
    media = ADDON_MEDIA
    problems = []
    if not _inside(media, ROOT) or os.path.basename(media) != "Media":
        sys.exit("ship: %s is not the addon's Media" % media)
    if _inside(MEDIA, ROOT) or _inside(media, MEDIA):
        sys.exit("ship: the masters (%s) must be outside the addon, and Media outside them" % MEDIA)
    prev = {}
    if os.path.exists(record_path):
        try:
            prev = json.load(open(record_path, encoding="utf-8")).get("files", {})
        except ValueError:
            prev = {}
    # what Media will hold: the staged files, and the data files
    new = {}
    for r in rows:
        rel = os.path.relpath(r["dst"], stage).replace(os.sep, "/")
        new[rel] = r["dst"]
    data = {}
    for name in ("KitLayout.lua", "KitSlices.lua"):
        src = os.path.join(stage, name)
        if os.path.exists(src):
            data[name] = src
    new_low = {k.lower(): k for k in list(new) + list(data)}
    master_stems = {rel[:-4].lower() for rel in inventory(every=True)}
    looks_low = {lk.lower() for lk in LOOKS}

    def managed(rel):
        low = rel.lower()
        stem, ext = os.path.splitext(low)
        if low in prev:
            return True
        if ext not in (".tga", ".blp"):
            return False
        parts = low.split("/")
        return stem in master_stems or (len(parts) >= 3 and parts[0] in looks_low and parts[1] == "atlas")

    have = _files(media)
    for rel in [k for k in have if k.endswith(".ship-new")]:
        # a write this step was killed in the middle of: never shipped
        if not check_only and _inside(have[rel], media):
            os.remove(have.pop(rel))
    have_low = {k.lower(): k for k in have}
    to_write, same, to_delete = [], [], []
    for rel, src in sorted(list(new.items()) + list(data.items())):
        cur = have_low.get(rel.lower())
        if cur and open(have[cur], "rb").read() == open(src, "rb").read():
            same.append(rel)
        else:
            to_write.append(rel)
    for rel in sorted(have):
        if rel.lower() not in new_low and managed(rel) and rel not in ("KitLayout.lua", "KitSlices.lua"):
            to_delete.append(rel)

    # every file in the way must be one the ship made, or a copy of a master
    def known(rel):
        path = have[have_low[rel.lower()]]
        h = _sha(path)
        low = rel.lower()
        if prev.get(low) == h:
            return "shipped before"
        m = os.path.join(MEDIA, rel.replace("/", os.sep))
        if os.path.exists(m) and _sha(m) == h:
            return "a copy of its master"
        stem, ext = os.path.splitext(low)
        parts = low.split("/")
        if ext == ".blp" and stem in master_stems:
            return "a BLP made from a master"
        if ext in (".blp", ".tga") and len(parts) >= 3 and parts[0] in looks_low and parts[1] == "atlas":
            return "an atlas sheet"
        return None
    unsafe = [rel for rel in to_write + to_delete if rel.lower() in have_low and known(rel) is None]
    # the final tree, for the reference check
    gone = {d.lower() for d in to_delete}
    final = {k for k in have_low if k not in gone} | set(new_low)
    layout_ship = load_layout(data["KitLayout.lua"]) if "KitLayout.lua" in data else load_layout(LAYOUT_LUA)
    slices_ship = {}
    if "KitSlices.lua" in data:
        try:
            slices_ship = _lua_global(data["KitSlices.lua"], "MelloUI_KitSlices") or {}
        except ImportError:
            slices_ship = {}
    problems += check_refs(final, layout_ship, slices_ship, refs)
    foreign = sorted(k for k in have if k.lower() not in new_low and k not in to_delete and
                     os.path.splitext(k)[1].lower() in (".tga", ".blp"))
    report["ship"] = {"media": media, "write": to_write, "delete": to_delete, "unchanged": len(same),
                      "untouched_textures": foreign, "unsafe": unsafe, "problems": problems}
    print("ship: %d files to write, %d to remove, %d already as built; %d texture files in Media not made "
          "from masters left alone" % (len(to_write), len(to_delete), len(same), len(foreign)))
    for f in foreign[:20]:
        print("   untouched:", f)
    if problems:
        print("ship: STOPPED, nothing written -- the paths the addon asks for would not all be there:")
        for p in problems[:40]:
            print("   ", p)
        return 2
    if unsafe:
        print("ship: STOPPED, nothing written -- Media holds files the ship did not make where it would write "
              "or remove (a tool writing into Media instead of the masters?). Copy each into the masters "
              "(%s) if it is new art, or delete it, then run again:" % MEDIA)
        for rel in unsafe[:40]:
            print("   ", rel)
        return 2
    if check_only:
        for rel in to_write[:40]:
            print("   would write", rel)
        for rel in to_delete[:40]:
            print("   would remove", rel)
        print("ship --check: Media is %s" % ("up to date" if not (to_write or to_delete) else "OUT OF DATE"))
        return 1 if (to_write or to_delete) else 0
    # write (beside the file, then moved into place), then remove
    for rel in to_write:
        src = new.get(rel) or data[rel]
        dst = os.path.join(media, rel.replace("/", os.sep))
        cur = have_low.get(rel.lower())
        if cur and cur != rel:
            dst = have[cur]                     # the file as Media spells it
        if not _inside(dst, media):
            sys.exit("ship: refusing to write outside Media: %s" % dst)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        tmp = dst + ".ship-new"
        shutil.copyfile(src, tmp)
        os.replace(tmp, dst)
    emptied = set()
    for rel in to_delete:
        path = have[rel]
        if not _inside(path, media) or _inside(path, MEDIA):
            sys.exit("ship: refusing to remove %s" % path)
        os.remove(path)
        emptied.add(os.path.dirname(path))
    for d in sorted(emptied, key=len, reverse=True):
        while _inside(d, media) and os.path.realpath(d) != os.path.realpath(media) and os.path.isdir(d) and not os.listdir(d):
            os.rmdir(d)
            d = os.path.dirname(d)
    record = {"media": media, "masters": MEDIA,
              "files": {rel.lower(): _sha(os.path.join(media, rel.replace("/", os.sep))) for rel in sorted(list(new) + list(data))}}
    os.makedirs(os.path.dirname(record_path), exist_ok=True)
    with open(record_path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(record, fh, indent=1, sort_keys=True)
    print("ship: %d written, %d removed -> %s  (a FULL client restart shows new files; /reload does not)" % (
        len(to_write), len(to_delete), media))
    return 0


def ship_summary(rows, pieces, report, refs, dynamic):
    """The numbers of what Media ships, and what stays TGA and why."""
    blp = [r for r in rows if r["fmt"] != "tga"]
    tga = [r for r in rows if r["fmt"] == "tga"]
    out = {"files": len(rows), "blp": len(blp), "tga": len(tga),
           "disk_mib": round(sum(r["bytes"] for r in rows) / MIB, 2),
           "gpu_mib": round(sum(r["gpu"] for r in rows) / MIB, 2),
           "blp_disk_mib": round(sum(r["bytes"] for r in blp) / MIB, 2),
           "tga_disk_mib": round(sum(r["bytes"] for r in tga) / MIB, 2),
           "by_folder": report.get("option_d")}
    kept = {"stays as its master": [], "named with '.tga'": [], "the gate": [], "uncompressed sheets": []}
    for r in tga:
        why = r.get("why") or ""
        if r.get("pieces"):
            kept["uncompressed sheets"].append("%s (%s pieces)" % (r["rel"], r["pieces"]))
        elif why.startswith("stays TGA"):
            kept["stays as its master"].append("%s -- %s" % (r["rel"], why.split(": ", 1)[-1]))
        elif why.startswith("named with"):
            kept["named with '.tga'"].append("%s -- %s" % (r["rel"], why))
        else:
            kept["the gate"].append("%s -- %s" % (r["rel"], why[len("gate: "):] if why.startswith("gate: ") else why))
    out["kept_tga"] = kept
    out["uncompressed_pieces"] = len([pc for pc in pieces if pc["fmt"] == "tga"])
    out["dxt_pieces"] = len([pc for pc in pieces if pc["fmt"] != "tga"])
    out["lua_refs"] = len(refs)
    out["lua_dynamic"] = ["%s:%d %s..." % d for d in dynamic]
    return out


# ---------------------------------------------------------------- main

def main():
    global MEDIA, LAYOUT_LUA, TUNING_LUA, SLICES_LUA, GATE_PSNR, GATE_P999
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("cmd", choices=["ship", "all", "convert", "rightsize", "atlas", "recommended", "verify", "samples",
                                    "probe"])
    ap.add_argument("--out", default=None, help="where the files go (ship: its staging folder, default %s)" % SHIP_DIR)
    ap.add_argument("--check", action="store_true", help="ship: build and compare only; exit 1 if Media is out of date")
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) - 2))
    ap.add_argument("--effort", type=int, default=2)
    ap.add_argument("--only", default=None)
    ap.add_argument("--sheet", type=int, default=ATLAS_SHEET)
    ap.add_argument("--src", default=None, help="the TGA tree to read (default: the masters, %s); its KitLayout.lua "
                                                "with it" % MASTER_MEDIA)
    ap.add_argument("--gate-psnr", type=float, default=GATE_PSNR, help="option d's gate, dB on screen (%(default)s)")
    ap.add_argument("--gate-p999", type=float, default=GATE_P999, help="option d's gate, 99.9th percentile error (%(default)s)")
    args = ap.parse_args()
    shipping = args.cmd == "ship"
    if shipping:
        # what ships is option d of every master, at the gate as set here
        if args.only or args.src or args.sheet != ATLAS_SHEET or \
                args.gate_psnr != GATE_PSNR or args.gate_p999 != GATE_P999:
            sys.exit("ship takes no --only, --src, --sheet or --gate-*: Media is made from every master at the set gate")
        if not os.path.exists(LAYOUT_LUA):
            sys.exit("ship: no masters at %s (Tools/paths.py; build_kit.py writes them)" % MEDIA)
    elif not args.out:
        sys.exit("--out is required (every command but ship writes only there)")
    # the gate is applied here, in the main process (the pool's workers
    # import the module afresh and hold the defaults)
    GATE_PSNR, GATE_P999 = args.gate_psnr, args.gate_p999
    if args.src:
        MEDIA = os.path.abspath(args.src)
        LAYOUT_LUA = os.path.join(MEDIA, "KitLayout.lua")
        if os.path.exists(os.path.join(MEDIA, "KitTuning.lua")):
            TUNING_LUA = os.path.join(MEDIA, "KitTuning.lua")
        SLICES_LUA = os.path.join(MEDIA, "KitSlices.lua")
    out = os.path.abspath(args.out or SHIP_DIR)
    for tree, what in ((MEDIA, "the TGA tree it reads"), (ADDON_MEDIA, "the addon's Media")):
        if _inside(out, tree):
            sys.exit("--out must not be inside %s (%s)" % (what, tree))
    rep = os.path.join(out, "report")
    os.makedirs(rep, exist_ok=True)
    t0 = time.time()
    # the paths the Lua and the TOC name: a file named with '.tga' stays TGA
    refs, dynamic, ref_problems = lua_refs()
    pins = tga_pins(refs)
    if ref_problems:
        print("Lua paths the scan cannot account for:\n   " + "\n   ".join(ref_problems))
        if shipping:
            sys.exit("ship: stopped before building (see above)")
    if args.cmd == "probe":
        print("probe:", make_probe(out))
        return
    if args.cmd == "samples":
        made, comps = make_samples(out, load_layout())
        json.dump({"samples": made, "display": comps}, open(os.path.join(rep, "samples.json"), "w"), indent=1)
        print("%d samples -> %s" % (len(made) + len(comps), os.path.join(out, "samples")))
        return
    plans, layout, slices, slice_keep = plan_files(args.only)
    by_rel = {p["rel"]: p for p in plans}
    unshipped = {rel: not_shipped(rel) for rel in inventory(args.only, every=True) if not_shipped(rel)}
    if unshipped:
        print("%d masters never ship (NOT_SHIPPED): %s" % (len(unshipped), ", ".join(sorted(unshipped))))
    tuning, tuning_keep = load_tuning()
    # pieces that stay in their own files, as they are: tuned ones, and the
    # rail pieces a one-texture nine-slice was built from
    keep_out = dict(slice_keep)
    keep_out.update(tuning_keep)
    for p in plans:
        if p["rel"].lower() in pins and piece_name(p["rel"]):
            keep_out[piece_name(p["rel"])] = "named with '.tga' by " + pins[p["rel"].lower()]
    print("%d TGA files planned (%.1fs); kit tuning holds %d piece overrides; %d pieces kept out of sheets "
          "(%d by tuning, %d by KitSlices.lua)" % (len(plans), time.time() - t0, len(tuning), len(keep_out),
                                                   len(tuning_keep), len(slice_keep)))
    report = {"files": len(plans), "target": DISPLAYS[0][1], "displays": DISPLAYS, "mip_at": MIP_AT,
              "gate": {"psnr": GATE_PSNR, "p999": GATE_P999, "dark_bias": GATE_DARK_BIAS, "dark_local": GATE_DARK_LOCAL,
                       "dark_lum": DARK_LUM, "dark_win": DARK_WIN},
              "tuning_pieces": sorted(tuning), "tuning_keep_out": tuning_keep, "slices_keep_out": slice_keep,
              "slice_families": sorted(slices),
              "slice_pictures": sorted(p["rel"] for p in plans if p["info"]["cat"] == "kit slices"),
              "not_shipped": unshipped,
              "hidden_rgb_files": sum(1 for p in plans if p["hidden_rgb"]),
              "hidden_rgb_texels": sum(p["hidden_rgb"] for p in plans)}
    results = {}               # option -> (verify jobs, file records, piece records)

    def resized_map():
        return {piece_name(p["rel"]): (p["rs"]["content"], p["rs"]["canvas"]) for p in plans
                if p["rs"] and piece_name(p["rel"]) and p["rel"].startswith("Kit/")}

    def copy_from_b(j, rb, option):
        """A standalone file of c / d is option b's file: copied, record kept."""
        dst = os.path.join(out, option, j["rel"][:-4].replace("/", os.sep) + ".blp")
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(rb["dst"], dst)
        r = dict(rb)
        r["dst"] = dst
        return r

    def run(option):
        t = time.time()
        odir = os.path.join(out, option)
        if os.path.isdir(odir):
            shutil.rmtree(odir)
        for fn in os.listdir(rep):
            if fn.startswith(("atlas_%s_" % option, "sheet_%s_" % option)) and fn.endswith(".png"):
                os.remove(os.path.join(rep, fn))
        pieces = []
        if option in ("a", "b"):
            jobs = [file_job(p, out, option, args.effort) for p in plans]
            res = run_pool(encode_job, jobs, args.jobs)
            for r in res:
                r["gate"] = gate_fail(r)
            if option == "b":
                write_layout(layout, os.path.join(odir, "KitLayout.lua"), None, resized_map())
            report["slices_check_" + option] = check_slices(
                os.path.join(odir, "KitLayout.lua") if option == "b" else LAYOUT_LUA, slices, out, option)
            vjobs = jobs
        else:
            if "b" not in results:
                run("b")
            bjobs, bres, _ = results["b"]
            brec = {r["rel"]: r for r in bres}
            cand = atlas_candidates(plans, layout, keep_out)
            hq, hq_why = set(), {}
            if option == "d":
                # start from the pieces whose own right-sized file fails in
                # any look; the sheets then have the final word
                for look in LOOKS:
                    for n in cand:
                        r = brec.get(look + "/" + n + ".tga")
                        if r and r["gate"]:
                            hq.add(n)
                            hq_why.setdefault(n, "in look %s, its own file: %s" % (look, r["gate"]))
            rounds = []
            for rnd in range(GATE_ROUNDS if option == "d" else 1):
                if os.path.isdir(os.path.join(odir)):
                    for look in LOOKS:
                        shutil.rmtree(os.path.join(odir, look, "atlas"), ignore_errors=True)
                specs, uvmap = atlas_specs(cand, hq, args.sheet)
                sjobs, atlased = sheet_jobs(specs, cand, by_rel, out, option, args.effort, rep)
                sres = run_pool(sheet_job, sjobs, args.jobs)
                srecs = [s for s, _ in sres]
                pieces = [pc for _, pcs in sres for pc in pcs]
                for pc in pieces:
                    pc["gate"] = gate_fail(pc) if pc["fmt"] != "tga" else ""
                fails = {pc["name"] for pc in pieces if pc["gate"]}
                for pc in pieces:
                    if pc["gate"]:
                        hq_why.setdefault(pc["name"], "in look %s, in its DXT sheet: %s" % (pc["look"], pc["gate"]))
                rounds.append({"round": rnd + 1, "hq": len(hq), "failed_in_sheet": sorted(fails)})
                if option != "d" or not fails:
                    break
                hq |= fails
            else:
                if option == "d":
                    sys.exit("option d: pieces still fail in their sheets after %d rounds" % GATE_ROUNDS)
            for pc in pieces:
                if pc["fmt"] == "tga" and pc["name"] in hq_why:
                    pc["why"] = hq_why[pc["name"]]
            if option == "d":
                report["uncompressed_pieces_d"] = {n: hq_why.get(n, "") for n in sorted(hq)}
            report["atlas_rounds_" + option] = rounds
            report["atlas_" + option] = {
                "candidates": len(cand), "pieces": len(uvmap), "files_replaced": len(atlased), "uncompressed_pieces": len(hq),
                "sheets": [{"rel": s["rel"], "w": s["w"], "h": s["h"], "fmt": s["fmt"], "pieces": s["pieces"],
                            "fill": round(s["used_px"] / (s["w"] * s["h"]), 3)} for s in srecs]}
            json.dump({n: {"file": v["file"], "uv": v["uv"], "rect": v["rect"], "raw": v["raw"]} for n, v in uvmap.items()},
                      open(os.path.join(rep, "atlas_uv_%s.json" % option), "w"), indent=1)
            res, vjobs, kept = [], [], []
            for j in bjobs:
                if j["rel"] in atlased:
                    continue
                rb = brec[j["rel"]]
                why, stay = "", False
                if option == "d":
                    for pat, reason in STAY_TGA:
                        if re.search(pat, j["rel"]):
                            why, stay = "stays TGA, as its master: " + reason, True
                    if not why and j["rel"].lower() in pins:
                        why = "named with '.tga' by " + pins[j["rel"].lower()]
                    if not why and rb["gate"]:
                        why = "gate: " + rb["gate"]
                if why:
                    tj = dict(j)
                    tj["dst"] = os.path.join(odir, j["rel"][:-4].replace("/", os.sep) + ".tga")
                    tj["why"] = why
                    if stay:
                        # the master's bytes, at its own size
                        tj.update(copy=True, rs=None, content=tuple(j["info"]["content"]))
                    kept.append((tj, rb))
                    continue
                res.append(copy_from_b(j, rb, option))
                vj = dict(j)
                vj["dst"] = res[-1]["dst"]
                vjobs.append(vj)
            if kept:
                tres = run_pool(keep_job, [tj for tj, _ in kept], args.jobs)
                for tr, (tj, rb) in zip(tres, kept):
                    tr["why"] = tj["why"]
                    tr["dxt_disp_psnr"] = rb["disp_psnr_rgb"]
                    res.append(tr)
                    vjobs.append(tj)
                report["kept_tga_" + option] = [{"rel": tj["rel"], "why": tj["why"]} for tj, _ in kept]
            for s in srecs:
                res.append(s)
            for sj in sjobs:
                vjobs.append({"rel": sj["rel"], "dst": sj["dst"], "image": sj["image"], "info": None})
                Image.fromarray(sj["image"]).save(os.path.join(rep, "sheet_%s_%s.png" % (option, sj["rel"][:-4].replace("/", "_"))))
            write_layout(layout, os.path.join(odir, "KitLayout.lua"), uvmap, resized_map(),
                         header=SHIP_HEADER if shipping else None)
            if shipping and os.path.exists(SLICES_LUA):
                # the families' record as build_nineslice wrote it: their
                # pieces keep their files and uvs (check_slices below)
                shutil.copyfile(SLICES_LUA, os.path.join(odir, "KitSlices.lua"))
            report["atlas_check_" + option] = check_atlas(os.path.join(odir, "KitLayout.lua"), sjobs, uvmap, plans, out, option)
            report["slices_check_" + option] = check_slices(os.path.join(odir, "KitLayout.lua"), slices, out, option)
            print("slices %s check:" % option, report["slices_check_" + option][:5] or
                  "every KitSlices.lua piece keeps its file, size and uv; every picture present once in every look")
            print("atlas %s check:" % option, report["atlas_check_" + option][:5] or "every uv addresses its pixels on the block grid; every file present once")
        print("option %s: %d files written (%d BLP, %d TGA)%s in %.1fs" % (
            option, len(res), sum(1 for r in res if r["fmt"] != "tga"), sum(1 for r in res if r["fmt"] == "tga"),
            ", %d atlas pieces measured in their sheets" % len(pieces) if pieces else "", time.time() - t))
        results[option] = (vjobs, res, pieces)
        write_csv(os.path.join(rep, "files_%s.csv" % option), res)
        if pieces:
            write_csv(os.path.join(rep, "pieces_%s.csv" % option), pieces)
        return vjobs, res, pieces

    def verify(option, vjobs=None):
        t = time.time()
        vjobs = vjobs if vjobs is not None else results[option][0]
        vres = run_pool(verify_job, vjobs, args.jobs)
        bad = [v for v in vres if v["problems"]]
        nb = sum(1 for v in vres if v["fmt"] != "tga")
        print("verify %s: %d BLP re-read with Pillow and blp_dxt (%d Pillow-exact), %d TGA read back, %d with problems (%.1fs)" % (
            option, nb, sum(1 for v in vres if v["fmt"] != "tga" and v["pillow_exact"]), len(vres) - nb, len(bad), time.time() - t))
        for v in bad[:20]:
            print("   ", v["rel"], v["problems"])
        write_csv(os.path.join(rep, "verify_%s.csv" % option), vres)
        return vres

    if args.cmd == "verify":
        # every file of every option tree, against what it was made from
        for o in "abcd":
            rows = read_csv(os.path.join(rep, "files_%s.csv" % o))
            if not rows:
                continue
            vjobs = []
            for r in rows:
                if r.get("pieces"):
                    png = os.path.join(rep, "sheet_%s_%s.png" % (o, r["rel"][:-4].replace("/", "_")))
                    vjobs.append({"rel": r["rel"], "dst": r["dst"], "image": load_rgba(png), "info": None})
                elif r["rel"] in by_rel:
                    p = by_rel[r["rel"]]
                    vjobs.append({"rel": r["rel"], "dst": r["dst"], "src": p["src"], "info": p["info"],
                                  "rs": p["rs"] if (o != "a" and not r.get("master_copy")) else None,
                                  "content": r["content"]})
            verify(o, vjobs)
        return

    cmds = {"all": ["a", "b", "c", "d"], "convert": ["a"], "rightsize": ["b"], "atlas": ["c"], "recommended": ["d"],
            "ship": ["d"]}
    verified = {}
    for o in cmds[args.cmd]:
        run(o)
    for o in results:
        verified[o] = verify(o)
    # the numbers
    report["tga"] = summarise([{"rel": p["rel"], "tga_bytes": p["tga_bytes"], "tga_gpu": p["tga_gpu"]} for p in plans],
                              "tga_bytes", "tga_gpu")
    stems_tga = {p["rel"][:-4]: (p["tga_bytes"], p["tga_gpu"]) for p in plans}
    report["preload_tga"] = preload_stats(layout, stems_tga)
    report["gamemenu_tga"] = {k: stems_tga.get("Textures/GameMenuFrame" + k) for k in ("", "_warm", "_bronze")}
    for o, (_, rows, pieces) in results.items():
        vres = verified[o]
        report["option_" + o] = summarise(rows, "bytes", "gpu")
        report["verify_" + o] = {"files": len(vres), "blp": sum(1 for v in vres if v["fmt"] != "tga"),
                                 "pillow_exact": sum(1 for v in vres if v["fmt"] != "tga" and v["pillow_exact"]),
                                 "problems": [v["rel"] + ": " + v["problems"] for v in vres if v["problems"]]}
        by = {v["rel"]: v for v in vres}
        for r in rows:
            r.update({k: v for k, v in by.get(r["rel"], {}).items() if k.startswith("pil_") or k in (
                "pillow_exact", "mip_worst_psnr", "last_level")})
        write_csv(os.path.join(rep, "files_%s.csv" % o), rows)
        report["quality_" + o] = quality_summary(rows, pieces)
        report["formats_" + o] = {f: sum(1 for r in rows if r["fmt"] == f) for f in ("dxt1", "dxt1a", "dxt5", "tga")}
        mipped = [r for r in rows if r["mips"]]
        report["mips_" + o] = {"files": len(mipped), "non_square": sum(1 for r in mipped if r["w"] != r["h"]),
                               "chains_to_1x1": sum(1 for r in mipped if by.get(r["rel"], {}).get("last_level") == "1x1")}
        blp_rows = [r for r in rows if r["fmt"] != "tga"]
        # the edge numbers over every drawn DXT item: standalone files and
        # the pieces measured in their DXT sheets (a sheet's own row has none)
        drawn = [r for r in blp_rows if not r.get("pieces")] + [pc for pc in pieces if pc["fmt"] != "tga"]

        def top(key, items):
            vals = [(float(r[key]), r["rel"], r.get("sheet") or "") for r in items if r.get(key) not in (None, "")]
            return max(vals) if vals else (0.0, "", "")
        be, ee = top("bleed_edge", drawn), top("edge_err", drawn)
        report["bleed_" + o] = {"files": sum(1 for r in blp_rows if r.get("bled_texels")),
                                "texels": int(sum(int(r.get("bled_texels") or 0) for r in blp_rows)),
                                "bleed_edge_max": be[0], "bleed_edge_max_at": be[1:],
                                "bleed_edge_over_8": sum(1 for r in drawn if r.get("bleed_edge") not in (None, "") and float(r["bleed_edge"]) > 8),
                                "edge_err_max": ee[0], "edge_err_max_at": ee[1:],
                                "edge_err_max_files": top("edge_err", [r for r in blp_rows if not r.get("pieces")])[0],
                                "edge_err_max_pieces": top("edge_err", [pc for pc in pieces if pc["fmt"] != "tga"])[0]}
        stems = {r["rel"][:-4]: (r["bytes"], r["gpu"]) for r in rows}
        lay_o = layout if o == "a" else load_layout(os.path.join(out, o, "KitLayout.lua"))
        report["preload_" + o] = preload_stats(lay_o, stems)
        report["gamemenu_" + o] = {k: stems.get("Textures/GameMenuFrame" + k) for k in ("", "_warm", "_bronze")}
        report["gamemenu_fmt_" + o] = {k: next((r["fmt"] for r in rows if r["rel"] == "Textures/GameMenuFrame%s.tga" % k), None)
                                       for k in ("", "_warm", "_bronze")}
        if o in ("b", "c", "d"):
            # Modules/Kit.lua's own remap on this layout: a failure stops the ship
            # (a live override would draw the wrong art); stubs that no longer
            # load Kit.lua only warn (that is this harness, not the art)
            try:
                ok, n, fails = test_tuning_remap(os.path.join(out, o, "KitLayout.lua"))
            except KitLoadError as e:
                report["tuning_remap_test_" + o] = {"not_run": str(e)}
                print("WARNING kit tuning remap not tested on %s's layout: Modules/Kit.lua did not load under "
                      "texture_pack's stubs (KIT_STUBS_LUA): %s" % (o, e))
            else:
                report["tuning_remap_test_" + o] = {"passed": ok, "run": n, "failures": fails}
                print("kit tuning remap, Modules/Kit.lua's Kit:ApplyTuning on %s's layout (Lua 5.1): %d / %d checks pass%s" % (
                    o, ok, n, "" if not fails else ": " + "; ".join(fails)))
    # right-sizing, from the data
    rs_rows = []
    for p in plans:
        info = p["info"]
        row = {"rel": p["rel"], "category": info["cat"], "note": info["note"], "w": p["size"][0], "h": p["size"][1],
               "content": list(info["content"]), "drawn": info["drawn"], "tile": info["tile"]}
        if info["upp"]:
            c = 1 / info["upp"]
            row["file_px_per_ui"] = round(c, 3)
            for key, _, px in DISPLAYS:
                row["mag_" + key] = round(px / c, 3)
            if p["rs"]:
                row["new_canvas"] = list(p["rs"]["canvas"])
                row["new_content"] = list(p["rs"]["content"])
                c2 = c * p["rs"]["scale"]
                row["new_file_px_per_ui"] = round(c2, 3)
                for key, _, px in DISPLAYS:
                    row["new_mag_" + key] = round(px / c2, 3)
        rs_rows.append(row)
    write_csv(os.path.join(rep, "rightsize.csv"), rs_rows)
    shrunk = [r for r in rs_rows if "new_canvas" in r]
    report["rightsized"] = {
        "files": len(shrunk),
        "by_folder": {f: sum(1 for r in shrunk if folder_of(r["rel"]) == f) for f in sorted({folder_of(r["rel"]) for r in shrunk})},
        "kit_pieces": sorted({piece_name(r["rel"]) for r in shrunk if piece_name(r["rel"])}),
        "textures": [r["rel"] for r in shrunk if folder_of(r["rel"]) == "Textures"],
        "list": [{"rel": r["rel"], "from": [r["w"], r["h"]], "to": r["new_canvas"],
                  "mag_1440p_070": r.get("new_mag_1440p_ui070"), "mag_4k_070": r.get("new_mag_4k_ui070"),
                  "mag_4k_100": r.get("new_mag_4k_ui100")} for r in shrunk],
    }
    if shipping:
        _, rows, pieces = results["d"]
        stops = report["verify_d"]["problems"] + report.get("atlas_check_d", []) + report.get("slices_check_d", []) +             ["Modules/Kit.lua's tuning remap on the shipped layout: " + f
             for f in report.get("tuning_remap_test_d", {}).get("failures", [])]
        summary = ship_summary(rows, pieces, report, refs, dynamic)
        report["ship_summary"] = summary
        print("ship: %d files (%d BLP, %d TGA): %.2f MiB on disk, %.2f MiB on the GPU; %d atlas pieces in DXT "
              "sheets, %d in uncompressed ones" % (summary["files"], summary["blp"], summary["tga"], summary["disk_mib"],
                                                    summary["gpu_mib"], summary["dxt_pieces"],
                                                    summary["uncompressed_pieces"]))
        for why, items in summary["kept_tga"].items():
            print("  TGA, %s: %d" % (why, len(items)))
            if why != "the gate" and why != "uncompressed sheets":
                for it in items:
                    print("     ", it)
        print("  %d Lua / TOC paths into Media checked; %d built at run time (by hand): %s" % (
            len(refs), len(dynamic), ", ".join(summary["lua_dynamic"]) or "none"))
        if stops:
            print("ship: STOPPED, nothing written -- the staged files failed their checks:")
            for p in stops[:40]:
                print("   ", p)
            code = 2
        else:
            code = ship_install(os.path.join(out, "d"), rows, report, refs, args.check,
                                os.path.join(out, "shipped.json"))
        report["seconds"] = round(time.time() - t0, 1)
        json.dump(report, open(os.path.join(rep, "report.json"), "w"), indent=1, default=str)
        print("report ->", os.path.join(rep, "report.json"), " (%.1fs)" % (time.time() - t0))
        sys.exit(code)
    report["seconds"] = round(time.time() - t0, 1)
    json.dump(report, open(os.path.join(rep, "report.json"), "w"), indent=1, default=str)
    print("report ->", os.path.join(rep, "report.json"))
    if args.cmd == "all":
        made, comps = make_samples(out, layout)
        json.dump({"samples": made, "display": comps}, open(os.path.join(rep, "samples.json"), "w"), indent=1)
        print("%d samples -> %s" % (len(made) + len(comps), os.path.join(out, "samples")))
        print("probe:", make_probe(out))
    print("done in %.1fs" % (time.time() - t0))


if __name__ == "__main__":
    main()

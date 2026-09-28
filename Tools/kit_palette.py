"""
Recolour the painted UI kit to MelloUI's palettes (MelloUI.Palettes,
Core/Core.lua; their colours in Tools/palettes.json, the one source the
tools read): the looks the player chooses between in game (UI Modifications,
Borders: Kit Colours), beside the art in its painted colours.

The kit was painted in cool blue-grey iron and stone with bright reds. Each
piece keeps its light and dark (a gradient map on its luminance), so the
painting, its bevels and the rails' dark edge lines (kit-art-edge-shadows)
stay; only the colour moves.

Ember (the palette MelloUI shipped with, the default) has two looks (user,
2026-09-23: "We can make A and B and let the users select when in game"),
their ramps written out below as they were approved (their folders stay
byte for byte as shipped; user, 2026-09-26):

  * warm   (A, warm iron): the metal stays metal, cool grey turned to the
           palette's browns (innerPanel, mainWindow, border, a light warm
           grey for its highlights);
  * bronze (B): the same browns, the bright bevels gold (trim,
           selectedTrim, text);
  * in both, red wherever it is painted (a selected row, an open tab, the
    title plate, the red button, a lit gem) becomes the palette's deep red
    (selectedTab), its highlights kept brighter so a lit gem still glints.

Every other palette has ONE look, its own kit (user, 2026-09-26: one
recoloured kit per palette, beside the Original), made the way the approved
sheets show it (MelloUI-BuildData/palette/additions_0.14.0/00_Overview.png):
the iron ramp from the palette's own roles, its highlight the text colour
half way to white; the red on the palette's selectedTab, its highlight in
the selection's own hue (OKLCH), so a blue or purple selection glints blue
or purple, never salmon.

Not recoloured, and not copied (the game reads them from Media/Kit in every
look): pictures (backdrops, cards, icons), the tiles already in the palette's
warmth (parchment, vellum, leather), the coloured quilts and the Elite / Rare /
Boss marks' metals and crests. The marks' portrait rings are copied with only
their compass gems recoloured (GEM_TWINS).

build_kit.py runs this after writing Media/Kit; or on its own:
    python Tools/kit_palette.py [--only LOOK,...] [--jobs N]
        Media/Kit -> each look's folder (KitWarm, KitBronze, Kit<Id>: LOOKS);
        Media/Textures/GameMenuFrame -> _warm, _bronze, _<id>
    python Tools/kit_palette.py --check [--jobs N]
        builds nothing: exit 1 when a look's master or Game Menu picture is
        not what Tools/palettes.json and these ramps make (run it beside
        build_nineslice --check and texture_pack ship --check)
    python Tools/kit_palette.py sheets [--out DIR]
        a contact sheet per look and an overview, from the masters
        (default MelloUI-BuildData/output/palette_kit)
All of it in the MASTERS (Tools/paths.py: MelloUI-BuildData/masters/Media);
`python Tools/texture_pack.py ship` then makes what the addon's Media ships.
"""
import io
import json
import math
import os
import re
import sys
from collections import namedtuple
from concurrent.futures import ProcessPoolExecutor

import numpy as np
from PIL import Image

from paths import OUTPUT, master

HERE = os.path.dirname(os.path.abspath(__file__))
KIT = master("Kit")
PALETTES_JSON = os.path.join(HERE, "palettes.json")
ROLES = ("mainWindow", "innerPanel", "raisedPanel", "border", "trim", "text", "mutedText", "selectedTab",
         "selectedTrim", "hover")
DEFAULT = "ember"                  # MelloUI:PaletteId() when nothing is chosen


def _hex(h):
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], float)


def load_palettes(path=PALETTES_JSON):
    """Tools/palettes.json, checked: (the ids in order, Ember first; {id:
    {"name", "blurb", "roles": {role: "#RRGGBB"}}}). Stops on a palette
    without all ten roles or an id that cannot name a folder."""
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    order, pals = list(data.get("order") or []), data.get("palettes") or {}
    if order[:1] != [DEFAULT] or len(set(order)) != len(order) or set(order) != set(pals):
        raise SystemExit("%s: 'order' must list every palette once, %s first" % (path, DEFAULT))
    for pid in order:
        pal = pals[pid]
        if not re.fullmatch(r"[a-z][A-Za-z]*", pid):
            raise SystemExit("%s: palette id %r: letters only, a small first letter (Kit<Id> is its folder)" % (path, pid))
        roles = pal.get("roles") or {}
        if set(roles) != set(ROLES) or not all(re.fullmatch(r"#[0-9A-Fa-f]{6}", str(roles[r])) for r in ROLES):
            raise SystemExit("%s: %s needs the ten roles as #RRGGBB (%s)" % (path, pid, ", ".join(ROLES)))
        if not pal.get("name"):
            raise SystemExit("%s: %s has no name" % (path, pid))
    return order, pals


ORDER, PALETTES = load_palettes()


def folder_id(pid):
    """A palette id as a folder writes it: obsidianVibrant -> ObsidianVibrant."""
    return pid[:1].upper() + pid[1:]


# Ember's colours (MelloUI.Palette's default, Core/Core.lua): the swatches' own
P = {k: _hex(v) for k, v in PALETTES[DEFAULT]["roles"].items()}

# luminance (0..1) -> colour: the metal kept metal, turned warm
WARM = [(0.0, (0, 0, 0)), (0.10, P["innerPanel"]), (0.16, P["mainWindow"]), (0.26, P["border"]),
        (0.55, P["mutedText"] * 1.25), (1.0, (235, 226, 205))]
# ... and the trim: its bright bevels gold
BRONZE = [(0.0, (0, 0, 0)), (0.08, P["innerPanel"]), (0.15, P["mainWindow"]), (0.22, P["border"]),
          (0.38, P["trim"]), (0.55, P["selectedTrim"]), (0.8, P["text"]), (1.0, (245, 235, 210))]
# a red's own brightness -> the palette's deep red, its highlights kept
RED = [(0.0, (0, 0, 0)), (0.18, P["selectedTab"] * 0.7), (0.30, P["selectedTab"]), (0.5, P["selectedTab"] * 1.6),
       (1.0, (200, 120, 100))]
# Whole painted frames outside the kit (TEXTURES, below): their gold (the Game
# Menu's header plate) stays gold, in the palette's trim, not the red ramp
GOLD = [(0.0, (0, 0, 0)), (0.12, P["raisedPanel"]), (0.30, P["trim"] * 0.75), (0.48, P["trim"]),
        (0.65, P["selectedTrim"]), (0.85, P["text"]), (1.0, (245, 235, 210))]


# ---------------------------------------------------------------- the other palettes' ramps
# OKLCH (Bjorn Ottosson's Oklab, in polar form), as the approved sheets used it

def _s2l(c):
    c = c / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _l2s(c):
    c = c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055
    return c * 255


def _oklch(rgb):
    """(L, C, h) of an sRGB colour (0..255)."""
    r, g, b = (_s2l(float(x)) for x in rgb)
    lo = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    mo = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    so = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    lo, mo, so = (math.copysign(abs(x) ** (1 / 3), x) for x in (lo, mo, so))
    L = 0.2104542553 * lo + 0.7936177850 * mo - 0.0040720468 * so
    a = 1.9779984951 * lo - 2.4285922050 * mo + 0.4505937099 * so
    bb = 0.0259040371 * lo + 0.7827717662 * mo - 0.8086757660 * so
    return L, math.hypot(a, bb), math.atan2(bb, a)


def _from_oklch(L, C, h):
    """sRGB 0..255 (whole numbers), the chroma reduced until it is in gamut
    (grey at that lightness if it never is)."""
    def linear(c):
        a, b = c * math.cos(h), c * math.sin(h)
        lo = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
        mo = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
        so = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
        return (4.0767416621 * lo - 3.3077115913 * mo + 0.2309699292 * so,
                -1.2684380046 * lo + 2.6097574011 * mo - 0.3413193965 * so,
                -0.0041960863 * lo - 0.7034186147 * mo + 1.7076147010 * so)

    def srgb(lin):
        return tuple(int(round(min(255, max(0, _l2s(max(0, x)))))) for x in lin)
    for _ in range(40):
        lin = linear(C)
        if all(-1e-6 <= x <= 1 + 1e-6 for x in lin):
            return srgb(lin)
        C *= 0.95
    return srgb(linear(0.0))


def _mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def palette_ramps(roles):
    """A palette's (iron, red, gold) ramps from its ten roles ({role:
    "#RRGGBB"}), as the approved sheets made them: the iron's highlight the
    text colour 55 % of the way to white, the selection's highlight at OKLCH
    lightness 0.70 in its own hue (chroma at most 0.10), the gold's the
    iron's highlight 30 % further. Ember's are written out above instead."""
    Q = {k: _hex(v) for k, v in roles.items()}
    top = _mix(Q["text"], (255, 255, 255), 0.55)
    _, C, h = _oklch(Q["selectedTab"])
    iron = [(0.0, (0, 0, 0)), (0.10, Q["innerPanel"]), (0.16, Q["mainWindow"]), (0.26, Q["border"]),
            (0.55, np.minimum(Q["mutedText"] * 1.25, 255)), (1.0, top)]
    red = [(0.0, (0, 0, 0)), (0.18, Q["selectedTab"] * 0.7), (0.30, Q["selectedTab"]),
           (0.5, np.minimum(Q["selectedTab"] * 1.6, 255)), (1.0, _from_oklch(0.70, min(C, 0.10), h))]
    gold = [(0.0, (0, 0, 0)), (0.12, Q["raisedPanel"]), (0.30, Q["trim"] * 0.75), (0.48, Q["trim"]),
            (0.65, Q["selectedTrim"]), (0.85, Q["text"]), (1.0, _mix(top, (255, 255, 255), 0.3))]
    return iron, red, gold

# pictures, the tiles already in the palette's warmth and the coloured quilts: left as painted; and the
# Elite / Rare / Boss marks (Tools/kit_marks.py): their metals mean what a unit is, under every palette
# (but for the rings' gems, GEM_TWINS)
SKIP = re.compile(r"^(backdrops|cards|icons)/|^marks/(?!ring_)|^tiles/(vellum|parchment|leather|quilt_|crackle)")
# The marks' portrait rings (marks/ring_<kind>): the ring in a metal with a crest, its compass gems left as the
# plain ring has them. In a look only those gems are recoloured, so they are the look's plain ring's gems (the
# user's sketch kept the gems as the look drew them); the metal and the crest stay as baked.
GEM_TWINS = re.compile(r"^marks/ring_")
GEM_PLAIN = "window/portrait_ring"
# Page stones toned down (user, 2026-09-23: "tone down the concrete in Warm
# iron and Bronze"; the social window's lists on it were not readable): the
# tile's light remapped round a dark middle with little spread before the
# ramp -- calm dark stone a step lighter than the list stone (window bodies,
# ~0.10), its cracks a hint
TONED = re.compile(r"^tiles/concrete")
TONED_MID, TONED_SPREAD = 0.16, 0.09

# Each look: its folder beside Media/Kit (Kit:LookFolder in Kit.lua picks it
# from the palette and Kit Colours), its ramps (the metal, the red, a whole
# frame's gold), its palette and the ending of its whole frames' files
# ("GameMenuFrame_warm"). Ember's two looks keep the keys Kit Colours stores
# ("warm", "bronze"); every other palette's one look is keyed by its id.
Look = namedtuple("Look", "folder ramp red gold palette suffix")
LOOKS = {"warm": Look("KitWarm", WARM, RED, GOLD, DEFAULT, "_warm"),
         "bronze": Look("KitBronze", BRONZE, RED, GOLD, DEFAULT, "_bronze")}
for _pid in ORDER:
    if _pid != DEFAULT:
        _iron, _red, _gold = palette_ramps(PALETTES[_pid]["roles"])
        LOOKS[_pid] = Look("Kit" + folder_id(_pid), _iron, _red, _gold, _pid, "_" + _pid)
# the looks' folders beside Media/Kit, in order; Ember's (as shipped in 0.13.7)
FOLDERS = tuple(lk.folder for lk in LOOKS.values())
EMBER_FOLDERS = tuple(lk.folder for lk in LOOKS.values() if lk.palette == DEFAULT)


def _gradient(v, stops):
    xs = np.array([s[0] for s in stops])
    cs = np.array([s[1] for s in stops], float)
    return np.stack([np.interp(v, xs, cs[:, i]) for i in range(3)], -1)


def recoloured(name):
    """Whether the piece `name` ("window/frame_t") is recoloured (else read
    from Media/Kit in every look)."""
    return not SKIP.search(name)


def recolour_toned(a, look):
    """A page stone in the look's colours, toned down (TONED)."""
    rgb = a[..., :3].astype(float) / 255
    lum = 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]
    p5, p50, p95 = np.percentile(lum, [5, 50, 95])
    t = (lum - p50) / max(p95 - p5, 1e-6)
    lum2 = np.clip(TONED_MID + t * TONED_SPREAD, 0, 1)
    b = a.copy()
    b[..., :3] = np.clip(np.round(_gradient(lum2, LOOKS[look].ramp)), 0, 255).astype(np.uint8)
    return b


def recolour(a, look):
    """An RGBA uint8 array in the look's colours."""
    rgb = a[..., :3].astype(float) / 255
    mx, mn = rgb.max(-1), rgb.min(-1)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    red = (sat > 0.45) & (rgb[..., 0] >= rgb[..., 1]) & (rgb[..., 0] >= rgb[..., 2])
    lum = 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]
    lum_red = 0.6 * rgb[..., 0] + 0.3 * rgb[..., 1] + 0.1 * rgb[..., 2]
    out = np.where(red[..., None], _gradient(lum_red, LOOKS[look].red), _gradient(lum, LOOKS[look].ramp))
    b = a.copy()
    b[..., :3] = np.clip(np.round(out), 0, 255).astype(np.uint8)
    return b


def gem_twin_mask(twin, plain):
    """The plain ring's compass gems (kit_gems.gem_mask on `plain`, the painted window/portrait_ring) that the
    ring twin `twin` still shows as the plain ring has them: a gem where the twin matches the plain ring over
    most of it (the crest covers the top gem, and a few edge texels the metal took stay metal)."""
    import kit_gems
    from scipy import ndimage
    mask = kit_gems.gem_mask(GEM_PLAIN, plain)
    lab, _ = ndimage.label(mask, structure=np.ones((3, 3)))
    same = np.abs(twin[..., :3].astype(int) - plain[..., :3].astype(int)).max(-1) <= 8
    keep = np.zeros(mask.shape, bool)
    for i, sl in enumerate(ndimage.find_objects(lab), 1):
        comp = lab[sl] == i
        if same[sl][comp].mean() >= 0.5:
            keep[sl] |= comp
    return keep


def recolour_gems(twin, plain, look):
    """A ring twin (GEM_TWINS) in the look: its gems moved as the look moves the plain ring's (where the twin
    is the plain ring, exactly the look's gem), everything else as baked."""
    keep = gem_twin_mask(twin, plain)
    shift = recolour(plain, look)[..., :3].astype(float) - plain[..., :3].astype(float)
    out = twin.copy()
    out[..., :3] = np.clip(np.round(np.where(keep[..., None], twin[..., :3] + shift, twin[..., :3])), 0, 255).astype(np.uint8)
    return out


def recolour_piece(name, a, look, kit):
    """The piece `name` (its master `a`) as the look has it."""
    if TONED.search(name):
        return recolour_toned(a, look)
    if GEM_TWINS.search(name):
        plain = np.array(Image.open(os.path.join(kit, GEM_PLAIN.replace("/", os.sep) + ".tga")).convert("RGBA"))
        return recolour_gems(a, plain, look)
    return recolour(a, look)


def kit_pieces(kit=KIT):
    """The recoloured pieces of Media/Kit, sorted: [(name, its TGA)]."""
    out = []
    for dirpath, _, files in os.walk(kit):
        for f in files:
            if f.lower().endswith(".tga"):
                src = os.path.join(dirpath, f)
                name = os.path.relpath(src, kit)[:-4].replace(os.sep, "/")
                if recoloured(name):
                    out.append((name, src))
    return sorted(out)


def _build_look(job):
    """One look's folder (a worker: build_looks runs one per look)."""
    look, kit = job
    out_root = os.path.join(os.path.dirname(kit), LOOKS[look].folder)
    wanted, total = set(), 0
    for name, src in kit_pieces(kit):
        dst = os.path.join(out_root, name.replace("/", os.sep) + ".tga")
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        a = np.array(Image.open(src).convert("RGBA"))
        out = recolour_piece(name, a, look, kit)
        Image.fromarray(out).save(dst)
        wanted.add(os.path.normcase(dst))
        total += os.path.getsize(dst)
    # what the look no longer holds (a piece gone from the kit, or one that
    # is no longer recoloured): removed, so the ship does not carry it on
    for dirpath, _, files in os.walk(out_root):
        for f in files:
            p = os.path.join(dirpath, f)
            if os.path.normcase(p) not in wanted:
                os.remove(p)
    return look, (len(wanted), total)


def build_looks(kit=KIT, looks=None, jobs=None):
    """Every recoloured piece of Media/Kit into each look's folder (`looks`:
    some of LOOKS' keys, default all; files of a look no longer in the kit
    removed), a process per look (`jobs` at most, default 8). Returns
    { look: (files, bytes) } in LOOKS' order."""
    todo = [lk for lk in LOOKS if looks is None or lk in looks]
    jobs = max(1, min(jobs or 8, len(todo)))
    if jobs == 1:
        done = dict(_build_look((lk, kit)) for lk in todo)
    else:
        with ProcessPoolExecutor(max_workers=jobs) as ex:
            done = dict(ex.map(_build_look, [(lk, kit) for lk in todo]))
    return {lk: done[lk] for lk in todo}


def _tga_bytes(a):
    """The bytes Image.save writes for an RGBA array as a .tga file."""
    buf = io.BytesIO()
    Image.fromarray(a).save(buf, format="TGA")
    return buf.getvalue()


def _check_look(job):
    """One look's folder against what build_looks would write (a worker):
    its pieces missing, differing or left over. Its slices/ are
    build_nineslice's (its own --check)."""
    look, kit = job
    root = os.path.join(os.path.dirname(kit), LOOKS[look].folder)
    bad, wanted = [], set()
    for name, src in kit_pieces(kit):
        dst = os.path.join(root, name.replace("/", os.sep) + ".tga")
        wanted.add(os.path.normcase(dst))
        if not os.path.exists(dst):
            bad.append("%s/%s: missing" % (LOOKS[look].folder, name))
            continue
        a = np.array(Image.open(src).convert("RGBA"))
        out = recolour_piece(name, a, look, kit)
        with open(dst, "rb") as fh:
            if fh.read() != _tga_bytes(out):
                bad.append("%s/%s: differs" % (LOOKS[look].folder, name))
    for dirpath, _, files in os.walk(root):
        for f in files:
            p = os.path.join(dirpath, f)
            rel = os.path.relpath(p, root).replace(os.sep, "/")
            if not rel.startswith("slices/") and os.path.normcase(p) not in wanted:
                bad.append("%s/%s: no longer made" % (LOOKS[look].folder, rel))
    return bad


def check(kit=KIT, textures=None, jobs=None):
    """Builds nothing: every look's master pieces and every whole frame's
    look (TEXTURES) against what build_looks / build_textures would write
    now. Returns the problems (empty when the masters are up to date)."""
    textures = textures or os.path.join(os.path.dirname(kit), "Textures")
    todo = list(LOOKS)
    jobs = max(1, min(jobs or 8, len(todo)))
    if jobs == 1:
        per = [_check_look((lk, kit)) for lk in todo]
    else:
        with ProcessPoolExecutor(max_workers=jobs) as ex:
            per = list(ex.map(_check_look, [(lk, kit) for lk in todo]))
    bad = [p for ps in per for p in ps]
    for base in TEXTURES:
        src = os.path.join(textures, base + ".tga")
        if not os.path.exists(src):
            continue
        a = np.array(Image.open(src).convert("RGBA"))
        for look, lk in LOOKS.items():
            dst = os.path.join(textures, base + lk.suffix + ".tga")
            if not os.path.exists(dst):
                bad.append("Textures/%s%s: missing" % (base, lk.suffix))
                continue
            with open(dst, "rb") as fh:
                if fh.read() != _tga_bytes(recolour_picture(a, look)):
                    bad.append("Textures/%s%s: differs" % (base, lk.suffix))
    return bad


# Whole painted frames outside the kit (Media/Textures), one file per look
# beside the painted one ("GameMenuFrame_warm.tga", "GameMenuFrame_obsidian.tga";
# user, 2026-09-24: the Game Menu kept its painted colours in both looks).
# Their gold (the Game Menu's header plate) stays gold in the palette's trim,
# not the red ramp (the look's `gold`).
TEXTURES = ["GameMenuFrame"]


def recolour_picture(a, look):
    """A whole frame in the look's colours: red to the deep red, gold to the
    trim's gold, the rest (iron, stone) on the look's ramp."""
    rgb = a[..., :3].astype(float) / 255
    mx, mn = rgb.max(-1), rgb.min(-1)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    d = np.maximum(mx - mn, 1e-6)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    hue = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
    coloured = (sat > 0.35) & (mx > 0.2)
    red = coloured & ((hue < 18) | (hue > 330))
    gold = coloured & (hue >= 18) & (hue <= 65)
    lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
    lum_red = 0.6 * r + 0.3 * g + 0.1 * b
    out = _gradient(lum, LOOKS[look].ramp)
    out = np.where(gold[..., None], _gradient(lum, LOOKS[look].gold), out)
    out = np.where(red[..., None], _gradient(lum_red, LOOKS[look].red), out)
    c = a.copy()
    c[..., :3] = np.clip(np.round(out), 0, 255).astype(np.uint8)
    return c


def build_textures(textures=os.path.join(os.path.dirname(KIT), "Textures"), looks=None):
    """Each of TEXTURES in every look (`looks`: some of LOOKS' keys), beside
    it, named with the look's suffix. Returns the files written."""
    written = []
    for base in TEXTURES:
        src = os.path.join(textures, base + ".tga")
        if not os.path.exists(src):
            continue
        a = np.array(Image.open(src).convert("RGBA"))
        for look, lk in LOOKS.items():
            if looks is not None and look not in looks:
                continue
            dst = os.path.join(textures, base + lk.suffix + ".tga")
            Image.fromarray(recolour_picture(a, look)).save(dst)
            written.append(dst)
    return written


# ---------------------------------------------------------------- contact sheets
# One page per look for judging the art by eye (the masters, before the ship
# compresses them): the palette's swatches, the pieces in place (the title
# plate, the red button, a bar, the ring, slots, gems on the look's stone),
# then every recoloured piece on the palette's window colour, named. Plus an
# overview of every look side by side.

SHEET_PARTS = ["window/portrait_ring", "window/frame_gem_tl", "buttons/slot_normal", "buttons/roundslot_normal",
               "buttons/checkbox_on", "buttons/cog_normal", "deco/gem_large", "lists/card_selected"]


def _font(rel, size):
    from PIL import ImageFont
    from paths import ADDON_MEDIA
    try:
        return ImageFont.truetype(os.path.join(ADDON_MEDIA, "Fonts", rel), size)
    except OSError:
        return ImageFont.load_default()


def _piece(folder_root, name):
    """A piece of a look (its master), cut to its drawn pixels."""
    root = folder_root if recoloured(name) else KIT
    path = os.path.join(root, name.replace("/", os.sep) + ".tga")
    if not os.path.exists(path):
        return None
    im = Image.open(path).convert("RGBA")
    bb = im.getchannel("A").getbbox()
    return im.crop(bb) if bb else im


def _strip(folder_root, left, mid, right, width, height):
    """A cap / middle / cap piece laid out `width` wide at `height`."""
    parts = [_piece(folder_root, n) for n in (left, mid, right)]
    if any(p is None for p in parts):
        return None
    k = height / max(p.height for p in parts)
    l, m, r = [p.resize((max(1, round(p.width * k)), height), Image.LANCZOS) for p in parts]
    out = Image.new("RGBA", (width, height))
    out.alpha_composite(l, (0, 0))
    x, xr = l.width, width - r.width
    while x < xr:
        seg = m.crop((0, 0, min(m.width, xr - x), height))
        out.alpha_composite(seg, (x, 0))
        x += seg.width
    out.alpha_composite(r, (xr, 0))
    return out


def _in_place(folder_root, roles, title, w, h):
    """The look's pieces in place, on its own stone (the toned concrete)."""
    from PIL import ImageDraw
    stone = _piece(folder_root, "tiles/concrete")
    img = Image.new("RGBA", (w, h), tuple(roles["mainWindow"]) + (255,))
    if stone is not None:
        for y in range(0, h, stone.height):
            for x in range(0, w, stone.width):
                img.alpha_composite(stone, (x, y))
    d = ImageDraw.Draw(img)
    gold, text = tuple(roles["selectedTrim"]), tuple(roles["text"])
    plate = _strip(folder_root, "tabs/top_cap_l_title", "tabs/top_mid_title", "tabs/top_cap_r_title", w - 120, 60)
    if plate:
        img.alpha_composite(plate, (60, 16))
    d.text((w / 2, 46), title, font=_font("Cinzel/Cinzel-Bold.ttf", 34), fill=gold, anchor="mm")
    x = 30
    for name in SHEET_PARTS:
        p = _piece(folder_root, name)
        if p is None:
            continue
        p.thumbnail((150, 150), Image.LANCZOS)
        img.alpha_composite(p, (x, 100 + (150 - p.height) // 2))
        x += p.width + 26
    btn = _strip(folder_root, "buttons/redbtn_cap_l_normal", "buttons/redbtn_mid_normal", "buttons/redbtn_cap_r_normal",
                 (w - 90) // 2, 60)
    if btn:
        img.alpha_composite(btn, (30, 276))
        d.text((30 + btn.width / 2, 306), "Install", font=_font("Alegreya/Alegreya-SemiBold.ttf", 30), fill=text,
               anchor="mm")
    bar = _strip(folder_root, "bars/frame_cap_l", "bars/frame_mid", "bars/frame_cap_r", (w - 90) // 2, 48)
    if bar:
        img.alpha_composite(bar, (60 + (w - 90) // 2, 282))
    return img


def _roles_rgb(pid):
    return {k: tuple(int(round(x)) for x in _hex(v)) for k, v in PALETTES[pid]["roles"].items()}


def contact_sheet(look, out_dir, kit=KIT, cols=12, cell=150):
    """The look's page (its masters): a PNG in out_dir. Returns its path."""
    from PIL import ImageDraw
    lk = LOOKS[look]
    pal = PALETTES[lk.palette]
    roles = _roles_rgb(lk.palette)
    root = os.path.join(os.path.dirname(kit), lk.folder)
    names = [n for n, _ in kit_pieces(kit)]
    W = 40 + cols * cell
    label_h = 34
    rows = (len(names) + cols - 1) // cols
    head_h = 250
    place_h = 360
    H = head_h + place_h + 50 + rows * (cell + label_h) + 40
    img = Image.new("RGBA", (W, H), roles["innerPanel"] + (255,))
    d = ImageDraw.Draw(img)
    title = pal["name"] + ("" if lk.palette != DEFAULT else " · " + {"warm": "Warm iron", "bronze": "Bronze"}[look])
    d.text((20, 16), title, font=_font("Cinzel/Cinzel-Bold.ttf", 48), fill=roles["selectedTrim"])
    d.text((22, 80), pal.get("blurb", ""), font=_font("Alegreya/Alegreya-Regular.ttf", 24), fill=roles["text"])
    d.text((22, 112), "Media/%s  ·  %d recoloured pieces  ·  the masters, before the ship compresses them"
           % (lk.folder, len(names)), font=_font("NotoSans/NotoSans-Regular.ttf", 18), fill=roles["text"])
    sw = (W - 40) / len(ROLES)
    small = _font("NotoSans/NotoSans-Regular.ttf", 16)
    for i, k in enumerate(ROLES):
        x0 = 20 + i * sw
        d.rectangle((x0 + 3, 146, x0 + sw - 3, 206), fill=roles[k], outline=(0, 0, 0), width=2)
        d.text((x0 + 6, 212), "%s %s" % (k, PALETTES[lk.palette]["roles"][k].upper()), font=small, fill=roles["text"])
    img.alpha_composite(_in_place(root, roles, pal["name"], W - 40, place_h - 20), (20, head_h))
    y0 = head_h + place_h + 30
    tiny = _font("NotoSans/NotoSans-Regular.ttf", 13)
    for i, n in enumerate(names):
        x, y = 20 + (i % cols) * cell, y0 + (i // cols) * (cell + label_h)
        d.rectangle((x + 2, y + 2, x + cell - 3, y + cell - 3), fill=roles["mainWindow"])
        p = _piece(root, n)
        if p is not None:
            # to fill the cell (a small piece at most 4x, nearest neighbour, so its texels show)
            k = min((cell - 12) / p.width, (cell - 12) / p.height, 4.0)
            p = p.resize((max(1, round(p.width * k)), max(1, round(p.height * k))),
                         Image.NEAREST if k > 1 else Image.LANCZOS)
            img.alpha_composite(p, (x + (cell - p.width) // 2, y + (cell - p.height) // 2))
        lab = n
        while d.textlength(lab, font=tiny) > cell - 4 and len(lab) > 6:
            lab = lab[:-2]
        d.text((x + 2, y + cell + 2), lab, font=tiny, fill=roles["text"])
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "%02d_%s.png" % (list(LOOKS).index(look) + 1, lk.folder))
    img.convert("RGB").save(path, optimize=True)
    return path


def overview(out_dir, kit=KIT, w=940, h=400):
    """Every look's pieces in place, two to a row, with the painted original."""
    cards = [("Original (painted)", KIT, _roles_rgb(DEFAULT))]
    for look, lk in LOOKS.items():
        name = PALETTES[lk.palette]["name"]
        if lk.palette == DEFAULT:
            name += " · " + {"warm": "Warm iron", "bronze": "Bronze"}[look]
        cards.append((name, os.path.join(os.path.dirname(kit), lk.folder), _roles_rgb(lk.palette)))
    rows = (len(cards) + 1) // 2
    img = Image.new("RGBA", (40 + 2 * w + 20, 40 + rows * (h + 20)), (22, 21, 19, 255))
    for i, (name, root, roles) in enumerate(cards):
        card = _in_place(root, roles, name, w, h)
        img.alpha_composite(card, (20 + (i % 2) * (w + 20), 20 + (i // 2) * (h + 20)))
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "00_Overview.png")
    img.convert("RGB").save(path, optimize=True)
    return path


def _arg(flag, default=None):
    return sys.argv[sys.argv.index(flag) + 1] if flag in sys.argv[:-1] else default


if __name__ == "__main__":
    if "sheets" in sys.argv[1:]:
        out = os.path.abspath(_arg("--out", os.path.join(OUTPUT, "palette_kit")))
        print("->", overview(out))
        for lk in LOOKS:
            print("->", contact_sheet(lk, out))
        sys.exit(0)
    if "--check" in sys.argv[1:]:
        problems = check(jobs=int(_arg("--jobs", "8")))
        for p in problems[:40]:
            print("   ", p)
        print("kit_palette --check: the looks' masters are %s" % (
            "up to date" if not problems else "OUT OF DATE (%d files): run python Tools/kit_palette.py" % len(problems)))
        sys.exit(1 if problems else 0)
    only = _arg("--only")
    looks = None
    if only:
        looks = [x.strip() for x in only.split(",") if x.strip()]
        unknown = [x for x in looks if x not in LOOKS]
        if unknown:
            sys.exit("unknown looks %s (known: %s)" % (", ".join(unknown), ", ".join(LOOKS)))
    for look, (n, total) in build_looks(looks=looks, jobs=int(_arg("--jobs", "8"))).items():
        print(f"{look}: {n} pieces -> masters Media/{LOOKS[look].folder} ({total / 1e6:.1f} MB)")
    for dst in build_textures(looks=looks):
        print("->", dst)
    print("next: python Tools/build_nineslice.py, then python Tools/texture_pack.py ship (the addon's Media)")

"""
Tone the painted UI's decorative red gems down to iron studs.

User, 2026-09-23: "people complain that we have way too many red diamond
texture shapes everywhere in the UI ... we should seriously consider toning
it down ... but the ui still has to be nice looking". The kit's art puts a red
gem on nearly every piece: the corners of every action / bag slot, the window
corners, the title, rail, row, header and tab caps, the small buttons'
corners, the slider thumb, the portrait ring, the level orb.

The gems keep their shape and facets but take the frame's own iron: each red
diamond becomes a dark gunmetal stud that sits in the ironwork instead of
shouting from it. Red is left where it MEANS something:

  * the states a piece shows under the mouse or when chosen -- hover,
    pressed, selected, open, checked, focused: a row, tab or slot lights its
    gems red as you point at it or pick it;
  * the red fills (the red button's plate, a selected row, an open tab or
    category, the title band, the scroll thumb): a component that runs along
    the piece or covers most of it is a fill, not a gem;
  * the symbols in the small buttons' middles (check, X, plus, arrow);
  * the gems that are markers, not decoration: deco/gem_large (the route's
    destination, the Legacy level diamonds) and deco/gem_small (the route's
    dots, the followed quest);
  * the action bar's end caps (deco/rail_cap_l / _r, the orbs in the
    gryphons' place: user, 2026-09-23 "the 2 artworks on the side get their
    gem color back"), the portrait ring's four compass gems, and a red copy of the bar
    bracket's end caps for the unit frames' health bars (RED_VARIANTS);
  * pictures: icons, backdrops, cards, tiles.

Used by build_kit.py (every kit piece, from the 2x sources); --red-gems there
builds the old art. The game menu keeps its red gems (user, 2026-09-23:
"restore the game menu how it was").
"""
import re

import numpy as np
from scipy import ndimage

# the frame's own iron, as a tint: the mean colour of the bezels round the
# gems (window/frame_gem_tl: 0.564 0.546 0.512)
IRON = np.array([1.0, 0.968, 0.907])
LUM_GAIN = 1.25     # the stud a shade lighter than the red was, so its facets still read
KEEP_STATES = re.compile(r"_(hover|selected|open|pressed|checked|focused)(_[a-z])?$")
KEEP_PIECES = re.compile(r"^(deco/gem_large|deco/gem_small|deco/rail_cap_|window/portrait_ring|icons/|backdrops/|cards/|tiles/)")
# pieces toned like the rest that ALSO get a red copy, "<piece>_red", for the
# places red is asked for (the strip's "red" state): the bar bracket's end
# gems, red on the unit frames' health bars (user, 2026-09-23, painted on the
# player frame: the portrait ring's four gems and the health bar's end gem red,
# the name plate's, the power bar's and the level orb's iron)
RED_VARIANTS = {"bars/frame_cap_l", "bars/frame_cap_r"}
SYMBOL_BUTTONS = re.compile(r"^(buttons/(arrow_|plus_|minus_|checkbox_|cog_)|window/close_)")


def red_mask(a):
    """(core, soft): the clearly red pixels, and the faintly red ones round them."""
    rgb = a[..., :3].astype(float) / 255
    al = a[..., 3]
    mx = rgb.max(-1)
    mn = rgb.min(-1)
    s = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    reddish = (r >= mx - 1e-6) & (g < r * 0.75) & (b < r * 0.8)
    core = reddish & (s > 0.40) & (mx > 0.10) & (al > 0)
    soft = reddish & (s > 0.18) & (mx > 0.06) & (al > 0)
    return core, soft


def gem_mask(name, a):
    """The pixels of the piece's decorative gems."""
    core, soft = red_mask(a)
    lab, _ = ndimage.label(core, structure=np.ones((3, 3)))
    h, w = core.shape
    opaque = max(1, int((a[..., 3] > 128).sum()))
    keep = np.zeros_like(core)
    for i, sl in enumerate(ndimage.find_objects(lab), 1):
        comp = lab[sl] == i
        area = int(comp.sum())
        ch, cw = comp.shape
        if area < 6:
            continue
        aspect = cw / ch
        fill = area / (cw * ch)
        cy = (sl[0].start + sl[0].stop) / 2 / h
        cx = (sl[1].start + sl[1].stop) / 2 / w
        # a fill runs along the piece or covers most of it; a gem is compact
        if not (0.55 <= aspect <= 1.8) or area > 0.30 * opaque or fill < 0.30:
            continue
        # the symbol in a small button's middle (check, X, plus, arrow, cog)
        if SYMBOL_BUTTONS.search(name) and 0.25 < cx < 0.75 and 0.25 < cy < 0.75:
            continue
        keep[sl] |= comp
    # the gem's soft red rim (anti-aliasing, the shadow in its facets)
    grown = ndimage.binary_dilation(keep, iterations=3)
    return keep | (grown & soft)


def tone(name, a):
    """a: H x W x 4 uint8 of the piece `name` ("group/piece"). Returns the
    toned copy (or `a` itself when nothing changed) and the pixels changed."""
    if KEEP_STATES.search(name) or KEEP_PIECES.search(name):
        return a, 0
    m = gem_mask(name, a)
    if not m.any():
        return a, 0
    out = a.copy()
    rgb = a[..., :3].astype(float) / 255
    # the gem's perceived brightness (red's peak channel is bright, its light
    # is not): a dark gunmetal stud with the facets' light and shade kept
    lum = rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114
    val = np.clip(0.05 + lum * LUM_GAIN, 0, 1)
    iron = (val[..., None] * IRON[None, None, :]).clip(0, 1)
    out[..., :3] = np.where(m[..., None], (iron * 255 + 0.5).astype(np.uint8), a[..., :3])
    return out, int(m.sum())

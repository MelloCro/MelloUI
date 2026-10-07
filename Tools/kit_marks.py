"""
kit_marks.py -- the Elite / Rare / Rare Elite / Boss marks, baked from the kit's own pieces.

User, 2026-09-28 (the approved sketch, MelloUI-BuildData/output/elite_sketch: elite_target_sketch.jpg and
elite_nameplate_sketch.jpg): a unit's class shows in metal. Elite is gold with a crown, Rare silver with a star,
Rare Elite silver with a gold star, a Boss red-bronze with a skull. No crest has wings (user, 2026-09-28: the rare
elite's crest is sketch A's, a gold star in a silver rim, the size of every other crest). The unit frames take
style B (a crest with the mark on the portrait ring's top gem, the ring and the level orb in the metal); the
nameplates style A (a small crest before the name, the left end cap and the level orb in the metal).

Everything here is ART, made once by Tools/build_kit.py into the kit's group `marks/` (then shipped by
texture_pack.py like every piece); the game only swaps a piece for its metal twin (Modules/KitMarks.lua). The
metals mean what a unit is, the same under every palette: the metals and the crests are never recoloured by a
palette's look (Modules/Kit.lua UNCOLOURED, Tools/kit_palette.py SKIP). The rings' compass gems are the plain
ring's own, so they follow the look as the plain ring's gems do (kit_palette.py GEM_TWINS: each look's copy of a
ring recolours those gems alone).

  marks/ring_<kind>             window/portrait_ring in the kind's metal (its compass gems left as the plain
                                ring has them), the crest on its top gem (the sketch's style B); the ring's own
                                canvas and geometry, so a swap needs no refit
  marks/orb_<metal>             buttons/orb_normal in a metal
  marks/cap_<family>_<metal>    a Nameplate Border family's left cap (bars/<family>_cap_l) in a metal (named
                                apart from the strips' parts: a whole piece a strip's cap wears, never a strip)
  marks/<ring>_<kind>           (0.19.6) a border library ring (rings/r1, rings/r3) as marks/ring_<kind> is the
                                portrait ring: the Portrait Ring choice (UnitFramePanel), no compass gems
  marks/crest_<kind>            the crest alone: a nameplate's, before the name (every kind's the same square
                                size, the rare elite's too)
  marks/orb_disc                a white disc that fits inside the orb's ring (tinted with the palette's inner
                                panel in game: the dark ground under a nameplate's level number)

The crest's rim is the level orb's own ring in the metal, its face a dark disc, the mark drawn on it in the metal
(the sketch's shapes, supersampled). Every recoloured piece keeps its light and shade (a gradient map on its
luminance), so its bevels and dark edge lines stay (kit-art-edge-shadows).
"""
import math

import numpy as np
from PIL import Image, ImageDraw

import kit_gems

KINDS = ("elite", "rare", "rareelite", "boss")
# (0.19.6) the border library's rings (rings/<id>, Tools/make_newui2_borders.py) that can be the portrait ring
RINGS = ("r1", "r3")
METAL_OF = {"elite": "gold", "rare": "silver", "rareelite": "silver", "boss": "boss"}
METALS = ("gold", "silver", "boss")
# the Nameplate Border families whose left cap gets a metal twin (Kit.buttonLooks.barBorders)
CAP_FAMILIES = ("frame", "castbar", "rim", "rimhair", "rimround", "rimgold", "rimsunk")

# the approved sketch's ramps: dark edge, shade, body, highlight
RAMP = {
    "gold": [(38, 22, 8), (128, 82, 26), (214, 160, 56), (252, 234, 166)],
    "silver": [(26, 29, 34), (92, 100, 110), (182, 190, 198), (244, 246, 249)],
    "boss": [(44, 8, 8), (128, 26, 20), (206, 96, 44), (252, 206, 128)],
}
FACE = (22, 19, 15)          # the crest's dark face (a fixed near-black: the crest is never recoloured)
OUTLINE = (20, 14, 8)        # the marks' ink line
JEWEL = (186, 36, 32)        # the crown's jewels
BONE, EYES = (236, 228, 208), (120, 14, 14)
SK = 4                       # supersampling of the drawn marks

ORB_RING_IN = 33.5           # buttons/orb_normal (98 px): the inner edge of its ring (the dark line at 32-34)
CREST_SIZE = 64              # a nameplate crest's painted height (its disc's diameter)
CREST_OVER = 2.5             # the ring's crest: px past the gem's room, up to the canvas' top and over the bevel


# ------------------------------------------------------------------ metal

def _ramp(metal, t):
    stops = np.array(RAMP[metal], np.float64)
    t = np.clip(t, 0, 1) * (len(stops) - 1)
    i = np.clip(t.astype(int), 0, len(stops) - 2)
    f = (t - i)[..., None]
    return stops[i] + (stops[i + 1] - stops[i]) * f


def recolour(a, metal, keep=None):
    """The piece `a` (H x W x 4 uint8) in a metal: its luminance through the metal's ramp (the sketch's
    curve: the iron's range stretched onto the ramp), alpha kept; `keep` (a bool mask) left as painted."""
    rgb = a[..., :3].astype(np.float64)
    lum = (rgb[..., 0] * 0.3 + rgb[..., 1] * 0.59 + rgb[..., 2] * 0.11) / 255.0
    col = _ramp(metal, (lum - 0.05) * 1.9)
    out = a.copy()
    new = np.clip(col + 0.5, 0, 255).astype(np.uint8)
    if keep is not None:
        new = np.where(keep[..., None], a[..., :3], new)
    out[..., :3] = new
    return out


def metal_fill(size, metal, box):
    """A metal gradient over `box` (x0, y0, x1, y1) on a canvas of `size`: light from the top left."""
    w, h = size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64)
    x0, y0, x1, y1 = box
    t = 1.0 - ((yy - y0) / max(1, y1 - y0) * 0.8 + (xx - x0) / max(1, x1 - x0) * 0.2)
    rgb = _ramp(metal, t)
    return Image.fromarray(np.dstack([rgb, np.full((h, w), 255.0)]).astype(np.uint8), "RGBA")


# ------------------------------------------------------------------ drawing (the sketch's shapes)

class Canvas:
    """Marks drawn at SK x a canvas of `size` px, in canvas px."""

    def __init__(self, size):
        self.size = size
        self.big = Image.new("RGBA", (size[0] * SK, size[1] * SK), (0, 0, 0, 0))

    def layer(self):
        """A clear layer the size of the canvas and its pen: what is drawn on it is laid over the canvas with
        `lay` (PIL's pen REPLACES an RGBA image's pixels, a translucent colour too: the bevel's shade would
        punch a hole through the mark)."""
        lay = Image.new("RGBA", self.big.size, (0, 0, 0, 0))
        return lay, ImageDraw.Draw(lay)

    def lay(self, lay):
        self.big.alpha_composite(lay)

    def poly(self, pts, metal, width=1.0, box=None):
        P = [(x * SK, y * SK) for x, y in pts]
        m = Image.new("L", self.big.size, 0)
        ImageDraw.Draw(m).polygon(P, fill=255)
        xs, ys = [p[0] for p in P], [p[1] for p in P]
        bx = tuple(v * SK for v in box) if box else (min(xs), min(ys), max(xs), max(ys))
        lay, d = self.layer()
        lay.paste(metal_fill(self.big.size, metal, bx), (0, 0), m)
        d.line(P + [P[0]], fill=OUTLINE + (255,), width=max(1, int(width * SK)), joint="curve")
        self.lay(lay)

    def paste(self, img, cx, cy, r):
        """A round picture (the orb's ring) scaled to radius r, centred on (cx, cy)."""
        d = max(1, int(round(2 * r * SK)))
        pic = img.resize((d, d), Image.LANCZOS)
        self.big.alpha_composite(pic, (int(round((cx - r) * SK)), int(round((cy - r) * SK))))

    def disc(self, cx, cy, r, colour):
        lay, d = self.layer()
        d.ellipse([(cx - r) * SK, (cy - r) * SK, (cx + r) * SK, (cy + r) * SK], fill=colour + (255,))
        self.lay(lay)

    def star(self, cx, cy, r, metal):
        pts = []
        for k in range(10):
            a = -math.pi / 2 + k * math.pi / 5
            rr = r if k % 2 == 0 else r * 0.42
            pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
        self.poly(pts, metal, width=0.7, box=(cx - r, cy - r, cx + r, cy + r))
        # the bevel: one side of each point a shade darker
        lay, d = self.layer()
        for k in range(0, 10, 2):
            tip, inner = pts[k], pts[(k + 1) % 10]
            d.polygon([(cx * SK, cy * SK), (tip[0] * SK, tip[1] * SK), (inner[0] * SK, inner[1] * SK)], fill=(0, 0, 0, 70))
        self.lay(lay)

    def crown(self, cx, cy, r, metal):
        w, h = r * 1.25, r * 1.0
        base_y, top_y = cy + h * 0.45, cy - h * 0.55
        pts = [(cx - w * 0.5, base_y), (cx - w * 0.5, cy - h * 0.05), (cx - w * 0.3, cy + h * 0.12), (cx - w * 0.16, top_y + h * 0.1),
               (cx, cy + h * 0.02), (cx + w * 0.16, top_y + h * 0.1), (cx + w * 0.3, cy + h * 0.12), (cx + w * 0.5, cy - h * 0.05),
               (cx + w * 0.5, base_y)]
        self.poly(pts, metal, width=0.6, box=(cx - w / 2, top_y, cx + w / 2, base_y))
        lay, d = self.layer()
        for bx, by in ((cx - w * 0.5, cy - h * 0.12), (cx - w * 0.16, top_y + h * 0.02), (cx + w * 0.16, top_y + h * 0.02),
                       (cx + w * 0.5, cy - h * 0.12)):
            rr = r * 0.12
            d.ellipse([(bx - rr) * SK, (by - rr) * SK, (bx + rr) * SK, (by + rr) * SK], fill=JEWEL + (255,),
                      outline=OUTLINE + (255,), width=max(1, int(0.4 * SK)))
        d.line([((cx - w * 0.5) * SK, (base_y - h * 0.16) * SK), ((cx + w * 0.5) * SK, (base_y - h * 0.16) * SK)],
               fill=OUTLINE + (200,), width=max(1, int(0.5 * SK)))
        self.lay(lay)

    def skull(self, cx, cy, r):
        lay, d = self.layer()
        s = lambda v: v * SK  # noqa: E731
        line = max(1, int(0.6 * SK))
        d.ellipse([s(cx - 0.62 * r), s(cy - 0.72 * r), s(cx + 0.62 * r), s(cy + 0.36 * r)], fill=BONE + (255,), outline=OUTLINE + (255,), width=line)
        d.rounded_rectangle([s(cx - 0.36 * r), s(cy + 0.05 * r), s(cx + 0.36 * r), s(cy + 0.62 * r)], radius=s(0.12 * r),
                            fill=BONE + (255,), outline=OUTLINE + (255,), width=line)
        d.rectangle([s(cx - 0.34 * r), s(cy + 0.02 * r), s(cx + 0.34 * r), s(cy + 0.2 * r)], fill=BONE + (255,))
        for ex in (-0.26, 0.26):
            d.ellipse([s(cx + ex * r - 0.17 * r), s(cy - 0.28 * r), s(cx + ex * r + 0.17 * r), s(cy + 0.02 * r)],
                      fill=EYES + (255,), outline=OUTLINE + (255,), width=max(1, int(0.4 * SK)))
        d.polygon([(s(cx), s(cy + 0.08 * r)), (s(cx - 0.09 * r), s(cy + 0.24 * r)), (s(cx + 0.09 * r), s(cy + 0.24 * r))], fill=OUTLINE + (255,))
        for tx in (-0.18, 0, 0.18):
            d.line([(s(cx + tx * r), s(cy + 0.36 * r)), (s(cx + tx * r), s(cy + 0.6 * r))], fill=OUTLINE + (255,), width=max(1, int(0.45 * SK)))
        self.lay(lay)

    def wing(self, bx, by, side, scale, metal, rise=1.0, spread=1.0, ink=1.0):
        """One wing from its root (bx, by), `side` +1 right / -1 left: five feathers fanning up and out (the
        sketches' wing, rank_sketch/sketch_ranks.py)."""
        for ang, ln in ((-78, 1.00), (-60, 0.92), (-42, 0.80), (-24, 0.66), (-6, 0.50)):
            a = math.radians(ang) * rise
            L = 34 * scale * ln * spread
            ux, uy = math.cos(a) * side, math.sin(a)
            nx, ny = -uy, ux
            w = 5.2 * scale
            tip = (bx + ux * L, by + uy * L)
            mid1 = (bx + ux * L * 0.55 + nx * w * side, by + uy * L * 0.55 + ny * w * side)
            mid2 = (bx + ux * L * 0.55 - nx * w * 0.55 * side, by + uy * L * 0.55 - ny * w * 0.55 * side)
            self.poly([(bx, by), mid1, tip, mid2], metal, width=ink, box=(bx - L, by - L, bx + L, by + L * 0.3))

    def diamond(self, cx, cy, r, metal, width=1.0):
        self.poly([(cx, cy - r), (cx + r * 0.8, cy), (cx, cy + r), (cx - r * 0.8, cy)], metal, width=width)

    def bead(self, cx, cy, r, metal, ink=1.0):
        box = (cx - r, cy - r, cx + r, cy + r)
        m = Image.new("L", self.big.size, 0)
        ImageDraw.Draw(m).ellipse([v * SK for v in box], fill=255)
        lay, d = self.layer()
        lay.paste(metal_fill(self.big.size, metal, [v * SK for v in box]), (0, 0), m)
        d.ellipse([v * SK for v in box], outline=OUTLINE + (255,), width=max(1, int(ink * SK)))
        self.lay(lay)

    def taper(self, pts, w0, w1, metal, ink):
        """a stroke along `pts` (canvas px), its width from w0 to w1, inked by `ink` px, a ball at its end"""
        n = len(pts)
        ink_m = Image.new("L", self.big.size, 0)
        body = Image.new("L", self.big.size, 0)
        di, db = ImageDraw.Draw(ink_m), ImageDraw.Draw(body)
        for k, (x, y) in enumerate(pts):
            w = w0 + (w1 - w0) * k / (n - 1)
            rb = (w / 2) * SK
            ri = rb + ink * SK
            di.ellipse([x * SK - ri, y * SK - ri, x * SK + ri, y * SK + ri], fill=255)
            db.ellipse([x * SK - rb, y * SK - rb, x * SK + rb, y * SK + rb], fill=255)
        x, y = pts[-1]
        rb = w1 * 0.95 * SK
        ri = rb + ink * SK
        di.ellipse([x * SK - ri, y * SK - ri, x * SK + ri, y * SK + ri], fill=255)
        db.ellipse([x * SK - rb, y * SK - rb, x * SK + rb, y * SK + rb], fill=255)
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        box = tuple(v * SK for v in (min(xs) - w0, min(ys) - w0, max(xs) + w0, max(ys) + w0))
        lay = Image.new("RGBA", self.big.size, (0, 0, 0, 0))
        lay.paste(Image.new("RGBA", self.big.size, OUTLINE + (255,)), (0, 0), ink_m)
        lay.paste(metal_fill(self.big.size, metal, box), (0, 0), body)
        self.lay(lay)

    def done(self):
        return np.array(self.big.resize(self.size, Image.LANCZOS))


def orb_ring(orb, metal):
    """The orb's ring (buttons/orb_normal, toned) in a metal, its middle cut out: a crest's rim."""
    a = recolour(orb, metal)
    h, w = a.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.hypot(xx - (w - 1) / 2, yy - (h - 1) / 2) * (98.0 / w)
    a = a.copy()
    a[..., 3] = np.where(d >= ORB_RING_IN - 1, a[..., 3], 0)
    return Image.fromarray(a, "RGBA")


def draw_crest(c, orb, kind, cx, cy, r, rim=None, mark=1.0):
    """The crest on canvas `c`, its disc of radius r centred on (cx, cy): the dark face, the orb's ring as its
    rim (in `rim`, else the kind's metal), the mark. Nothing past the rim (no wings: user, 2026-09-28), so every
    kind's crest has one outline (the nameplates' mark on top adds its wings around it: top_crest)."""
    metal = rim or METAL_OF[kind]
    face = r * ORB_RING_IN / 49.0
    c.disc(cx, cy, face + 0.6, FACE)
    c.paste(orb_ring(orb, metal), cx, cy, r)
    inner = face * 0.95 * mark      # (`mark`: the mark's size; the mark on top's is the sketch's, larger)
    if kind == "elite":
        c.crown(cx, cy + inner * 0.05, inner * 0.72, "gold")
    elif kind == "rare":
        c.star(cx, cy, inner * 0.74, "silver")
    elif kind == "rareelite":
        c.star(cx, cy, inner * 0.74, "gold")
    else:
        c.skull(cx, cy + inner * 0.02, inner * 0.86)


# ------------------------------------------------------------------ the pieces

def crest(orb, kind, size=CREST_SIZE):
    """A nameplate's crest: `size` px square, every kind's the same (the rare elite's too: no wings)."""
    r = size / 2.0
    c = Canvas((size, size))
    draw_crest(c, orb, kind, (size - 1) / 2.0 + 0.5, (size - 1) / 2.0 + 0.5, r - 0.5)
    return c.done()


def ring(ring_piece, orb, kind, open_top, gems=True):
    """window/portrait_ring (as build_kit made it) in the kind's metal with the crest on its top gem: the crest
    from the canvas' top edge to a little past the ring's inner bevel (`open_top`, the opening's first row;
    the portrait's medallion runs under the bevel there, as in the sketch), on the same canvas, so the ring's
    geometry is the plain ring's (the approved sketch's style B)."""
    metal = METAL_OF[kind]
    # the compass gems as the plain ring has them (a library ring, rings/r1 / r3: no gems, its studs in the metal)
    keep = kit_gems.gem_mask("window/portrait_ring", ring_piece) if gems else None
    a = recolour(ring_piece, metal, keep)
    h, w = a.shape[:2]
    cx = (w - 1) / 2.0 + 0.5
    col = np.where(ring_piece[:, w // 2, 3] > 128)[0]
    top = int(col.min()) if len(col) else 0
    r = (open_top - top) / 2.0 + CREST_OVER
    cy = max(r, top + r - CREST_OVER)
    c = Canvas((w, h))
    draw_crest(c, orb, kind, cx, cy, r)
    mark = c.done()
    out = Image.fromarray(a, "RGBA")
    out.alpha_composite(Image.fromarray(mark, "RGBA"))
    return np.array(out)


def disc(size=98, radius=ORB_RING_IN):
    """A white disc inside the orb's ring (its edge on the ring's inner dark line), anti-aliased."""
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    d = np.hypot(xx - (size - 1) / 2, yy - (size - 1) / 2) * (98.0 / size)
    alpha = np.clip(radius - d + 0.5, 0, 1)
    out = np.zeros((size, size, 4), np.uint8)
    out[..., :3] = 255
    out[..., 3] = (alpha * 255 + 0.5).astype(np.uint8)
    return out


# ------------------------------------------------------------------ the nameplates' mark on top
# (user, 2026-10-05, MelloUI-BuildData/output/rank_sketch: look E, "dont recolor the nameplates themselves ... just
# the metal line with the icon on it"; the boss's line ornate, style 3 of sketch_ornate.py, "keep this last one as
# the Boss nameplate", with "the wings on the edges of the top Metal" line; docs/plans/rank-marks-top.md): a metal
# line over the name, the crest on its middle. The game lays it from these pieces (NameplatePanel's mark on top):
#   marks/topcrest_<kind>    the crest with its wings (an elite's gold, a rare elite's silver around a gold crest, a
#                            boss's red-bronze; a rare has none); a boss's with the filigree's two big scrolls each
#                            side. Its canvas is centred on the crest's disc (the game hangs it by its centre)
#   marks/topline_<metal>    the line: a short strip, the same along its length (the game stretches it between the
#                            ends and the crest), inked above and below only
#   marks/topgem_<metal>     a plain line's end gem (a rare elite's gold on its silver line)
#   marks/topend_boss_<l|r>  a boss's line end: its gem, two small scrolls turned back to the crest, a wing outward;
#                            centred on the gem
#   marks/topbead_boss       the bead halfway along each half of a boss's line
# The sizes are the sketch's, in its pixels (the user's plate, its bracket about 33 tall) times TOP_UNIT (the crest's
# disc 19 sketch px = CREST_SIZE), so the game sizes each piece from the bracket alone.
TOP_UNIT = CREST_SIZE / 19.0
TOP_CR = 9.5                  # the crest disc's radius
TOP_LINE = {"gold": 1.5, "silver": 1.5, "boss": 1.15}   # the line's thickness
TOP_GEM = 3.0                 # an end gem's half height
TOP_BEAD = 1.5                # a boss bead's radius
TOP_INK = 0.27                # the plain pieces' ink (the sketch's 0.8 px at 3x)
TOP_SCROLL_INK = 0.55         # the filigree's ink (sketch_ornate3)
TOP_WINGS = {"elite": "gold", "rareelite": "silver", "boss": "boss"}   # the crest's wings (a rare: none)
TOP_RIM = {"elite": "gold", "rare": "silver", "rareelite": "gold", "boss": "boss"}   # the crest's rim
TOP_MARK = 1.25               # the mark's size on the crest (as the sketch's: the plain crest's is smaller)


def volute(x, y, out, up, length, turn, start, power=3.0, n=140):
    """a scroll from (x, y) heading `out` (+1 right / -1 left), a little toward `up` (-1 up / +1 down) already,
    its curvature growing along it: a long easy sweep, then a tight curl (sketch_ornate3)"""
    pts, px, py = [], x, y
    ds = length / n
    for k in range(n + 1):
        pts.append((px, py))
        phi = start + turn * math.pi * ((k + 0.5) * ds / length) ** power
        px += out * math.cos(phi) * ds
        py += up * math.sin(phi) * ds
    return pts


def centred(draw, reach):
    """A piece drawn by `draw(canvas, cx, cy)` around the centre of a canvas `reach` px each way, cut back to the
    smallest canvas still centred on that point (so the game can hang it by its CENTER)."""
    size = int(2 * reach)
    c = Canvas((size, size))
    draw(c, size / 2.0, size / 2.0)
    a = c.done()
    ys, xs = np.nonzero(a[..., 3] > 0)
    if not len(xs):
        return a
    mid = size / 2.0
    dx = int(math.ceil(max(mid - xs.min(), xs.max() + 1 - mid))) + 2
    dy = int(math.ceil(max(mid - ys.min(), ys.max() + 1 - mid))) + 2
    return a[int(mid - dy):int(mid + dy), int(mid - dx):int(mid + dx)]


def top_crest(orb, kind):
    U = TOP_UNIT

    def draw(c, cx, cy):
        r = TOP_CR * U
        if kind == "boss":
            for side in (-1, 1):
                xs = cx + side * (TOP_CR - 1.0) * U
                c.taper(volute(xs, cy + 0.5 * U, side, -1, 30 * U, 2.15, 0.30), 1.6 * U, 0.55 * U, "boss", TOP_SCROLL_INK * U)
                c.taper(volute(xs, cy + 1.5 * U, side, 1, 23 * U, 2.05, 0.26), 1.35 * U, 0.5 * U, "boss", TOP_SCROLL_INK * U)
        wings = TOP_WINGS.get(kind)
        if wings:
            for side in (-1, 1):
                c.wing(cx + side * r * 0.35, cy + r * 0.25, side, r / 34 * 1.75, wings, rise=0.95, ink=TOP_INK * U)
        draw_crest(c, orb, kind, cx, cy, r, rim=TOP_RIM[kind], mark=TOP_MARK)
    return centred(draw, 48 * U)


def top_line(metal):
    """the line: 16 px long, its band the metal's gradient top to bottom, inked above and below (never at its ends:
    the game stretches it)"""
    U = TOP_UNIT
    t = TOP_LINE[metal] * U
    ink = TOP_INK * U * 2
    h = int(math.ceil(t + 2 * ink + 4))
    h += h % 2
    yy = np.arange(h, dtype=np.float64) + 0.5
    top, bot = h / 2 - t / 2, h / 2 + t / 2

    def cover(a, b):   # how much of each row lies between a and b (anti-aliased edges)
        return np.clip(np.minimum(yy + 0.5, b) - np.maximum(yy - 0.5, a), 0, 1)
    band, outer = cover(top, bot), cover(top - ink, bot + ink)
    rgb = _ramp(metal, 1.0 - np.clip((yy - top) / max(t, 1), 0, 1))
    out = np.zeros((h, 16, 4), np.float64)
    for i in np.nonzero(outer > 0)[0]:
        # (a row the band covers in part is ink for the rest)
        out[i, :, :3] = (rgb[i] * band[i] + np.array(OUTLINE, np.float64) * (outer[i] - band[i])) / outer[i]
        out[i, :, 3] = outer[i] * 255
    return np.clip(out + 0.5, 0, 255).astype(np.uint8)


def top_gem(metal):
    U = TOP_UNIT
    return centred(lambda c, cx, cy: c.diamond(cx, cy, TOP_GEM * U, metal, width=TOP_INK * U), 6 * U)


def top_end(side):
    """a boss's line end, `side` -1 left / +1 right: the wing out of the line's end (under the gem), two small
    scrolls turned back to the crest, the gem; centred on the gem"""
    U = TOP_UNIT

    def draw(c, cx, cy):
        c.wing(cx + side * 1.0 * U, cy + 1.0 * U, side, 0.62 * U, "boss", rise=0.8, spread=1.0, ink=TOP_INK * U)
        xs = cx - side * 3.5 * U
        for up in (-1, 1):
            c.taper(volute(xs, cy + up * 0.4 * U, -side, up, 13 * U, 2.0, 0.35), 1.15 * U, 0.45 * U, "boss", TOP_SCROLL_INK * U)
        c.diamond(cx, cy, TOP_GEM * U, "boss", width=TOP_INK * U)
    return centred(draw, 30 * U)


def top_bead():
    U = TOP_UNIT
    return centred(lambda c, cx, cy: c.bead(cx, cy, TOP_BEAD * U, "boss", ink=TOP_INK * U * 1.6), 4 * U)


def top_pieces(orb):
    out = [("marks/topcrest_" + kind, top_crest(orb, kind)) for kind in KINDS]
    out += [("marks/topline_" + metal, top_line(metal)) for metal in METALS]
    out += [("marks/topgem_" + metal, top_gem(metal)) for metal in ("gold", "silver")]
    out += [("marks/topend_boss_l", top_end(-1)), ("marks/topend_boss_r", top_end(1)), ("marks/topbead_boss", top_bead())]
    return out


def bases():
    """The finished pieces the marks are made from (build_kit.py keeps them as it makes them)."""
    return ({"window/portrait_ring", "buttons/orb_normal"} | {"bars/%s_cap_l" % f for f in CAP_FAMILIES}
            | {"rings/" + r for r in RINGS})


def pieces(made, layout):
    """(piece name, RGBA array, the piece whose geometry it keeps or None) for every mark, from `made` (the
    finished pieces by name) and `layout` (their entries: the ring's opening)."""
    out = []
    orb = made["buttons/orb_normal"]
    ring_piece = made["window/portrait_ring"]
    open_top = layout["window/portrait_ring"]["open"][1]
    for kind in KINDS:
        out.append(("marks/ring_" + kind, ring(ring_piece, orb, kind, open_top), "window/portrait_ring"))
        out.append(("marks/crest_" + kind, crest(orb, kind), None))
        # (0.19.6, border stage 4) the border library's rings as the portrait ring: the same twins, named apart
        # from the gem ring's (marks/<ring>_<kind>: a metal, never recoloured, its shadow the plain ring's)
        for r in RINGS:
            base = "rings/" + r
            if base in made:
                out.append(("marks/%s_%s" % (r, kind), ring(made[base], orb, kind, layout[base]["open"][1], gems=False),
                            base))
    for metal in METALS:
        out.append(("marks/orb_" + metal, recolour(orb, metal), "buttons/orb_normal"))
        for family in CAP_FAMILIES:
            base = "bars/%s_cap_l" % family
            if base in made:
                out.append(("marks/cap_%s_%s" % (family, metal), recolour(made[base], metal), base))
    out.append(("marks/orb_disc", disc(orb.shape[1]), None))
    # the nameplates' mark on top (2026-10-05)
    for name, a in top_pieces(orb):
        out.append((name, a, None))
    return out

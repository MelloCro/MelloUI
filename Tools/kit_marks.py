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


def draw_crest(c, orb, kind, cx, cy, r):
    """The crest on canvas `c`, its disc of radius r centred on (cx, cy): the dark face, the orb's ring as its
    rim, the mark. Nothing past the rim (no wings: user, 2026-09-28), so every kind's crest has one outline."""
    metal = METAL_OF[kind]
    face = r * ORB_RING_IN / 49.0
    c.disc(cx, cy, face + 0.6, FACE)
    c.paste(orb_ring(orb, metal), cx, cy, r)
    inner = face * 0.95
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


def ring(ring_piece, orb, kind, open_top):
    """window/portrait_ring (as build_kit made it) in the kind's metal with the crest on its top gem: the crest
    from the canvas' top edge to a little past the ring's inner bevel (`open_top`, the opening's first row;
    the portrait's medallion runs under the bevel there, as in the sketch), on the same canvas, so the ring's
    geometry is the plain ring's (the approved sketch's style B)."""
    metal = METAL_OF[kind]
    keep = kit_gems.gem_mask("window/portrait_ring", ring_piece)   # the compass gems as the plain ring has them
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


def bases():
    """The finished pieces the marks are made from (build_kit.py keeps them as it makes them)."""
    return {"window/portrait_ring", "buttons/orb_normal"} | {"bars/%s_cap_l" % f for f in CAP_FAMILIES}


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
    for metal in METALS:
        out.append(("marks/orb_" + metal, recolour(orb, metal), "buttons/orb_normal"))
        for family in CAP_FAMILIES:
            base = "bars/%s_cap_l" % family
            if base in made:
                out.append(("marks/cap_%s_%s" % (family, metal), recolour(made[base], metal), base))
    out.append(("marks/orb_disc", disc(orb.shape[1]), None))
    return out

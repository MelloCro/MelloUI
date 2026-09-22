"""
Measured geometry of the three painted HUD art files, and the sprite cuts the
action bar is composed from. This module is pure data + arithmetic: it is
imported by

  Tools/make_hud_frames.py   builds the .tga sheets AND writes Media/HudLayout.lua
  Tools/preview_hud.py       renders the same layout locally with PIL so the
                             sprite cuts can be checked without the client

so the Lua modules and the local preview can never drift apart -- both read
the same numbers, and the Lua side reads them out of the generated
Media/HudLayout.lua.

All ART boxes are in ORIGINAL (uncropped) pixels of the file named in the
comment. Everything the modules use at runtime is expressed as a FRACTION of
a reference length, never in absolute pixels, so the skins scale with
whatever size the game's frames actually have:

  action bar  -> fractions of the button CELL PITCH (button size + the bar's
                 icon padding, i.e. the distance between two button centres)
  xp bar      -> fractions of the status bar's own HEIGHT
  unit frame  -> art px of the unit frame crop, scaled by frame width
  cast bar    -> art px of the cast bar crop, scaled by the status bar width

How the action bar art decomposes (measured on docs/actionbar-frame.webp with
Tools rulers; see the numbers beside each constant):

  * every slot is a square CELL of 145 art px: a 117 px interior (where the
    game's icon goes) with a 14 px rim on each side. Two neighbouring cells
    butt edge to edge and their rims together form the 28 px divider the art
    paints between slots.
  * the red gem diamonds are NOT part of a slot -- in the art they sit on the
    grid lines, one per crossing. They are a separate sprite, drawn once per
    crossing, which is what stops the doubled gems a per-button sprite with
    its own corner gems produced.
  * around the whole block runs an outer rail of the same 14 px thickness
    (the art's top rail; the left/right rails are the same profile turned).
  * the rune title plate is a single piece centred on the block, hanging 22
    art px into the block's top rail.
"""

# ---------------------------------------------------------------------------
# docs/actionbar-frame.webp (2000 x 668)
# ---------------------------------------------------------------------------
AB_ART = "actionbar-frame.webp"

# The whole painted block of rows (outer edge of the rail), and the XP bar.
AB_BLOCK = (14, 152, 1994, 460)
AB_XPBAR_Y = (462, 523)

# One clean slot cell: row 1, column 4 (a plain helmet icon, both neighbouring
# seams carry a gem so the cell's own edges are unambiguous). 145 x 143 px;
# its painted interior is x 474..591, y 180..293.
AB_CELL_SRC = (460, 165, 605, 308)
AB_CELL_PITCH = 145.0
# Rim fraction on each side of the cell. The painted interior gives 0.0966
# horizontally and 0.1049 vertically (the art's slots are 4 px wider than they
# are tall); 0.097 is the compromise that clears every painted icon pixel
# while eating barely a pixel of the rim's inner bevel. This is BOTH the hole
# cut into the sprite and the inset the game's icon is placed at, so the icon
# exactly fills the hole with no transparent ring.
AB_HOLE = 0.097
# How much of the cell the GAME'S ICON covers, as a margin fraction: the icon
# is (1 - 2 * AB_ICON) of the cell pitch, square and centred.
#
# Measured off the user's own mark-up (two red squares drawn on one cell of
# MultiBarBottomLeft): the cell in that crop is 60 px across -- its painted
# hole runs x 6..54, which is 0.806 of 60, the hole fraction exactly -- and
# the square the user drew for the wanted size spans x 4..59 and y 5..60,
# 56 px, i.e. 0.933 of the cell. That is a margin of 0.0335.
#
# It agrees with the emitted 160 px SLOT sprite: reading inward from a cell
# edge, the sides are dark gap to x 8 with the metal bevel from 9 (0.056) and
# the top is dark to y 3 with the metal rail from 4 (0.025); the icon edge
# belongs between them, on the rail's dark inner edge. 0.035 is that, and it
# matches the crop.
AB_ICON = 0.035
# The sprite is emitted square at this size, so the cell is square in game no
# matter what the art's own 145 x 143 aspect was.
AB_SLOT_SIZE = 160
# Slivers of the neighbouring seam gems fall inside the cell crop (they sit ON
# the cell's own corners in the art). They are cleared to transparent: at
# runtime a GEM sprite is drawn over every grid crossing anyway, and it is
# 0.248 pitch across (reach ~20 of 160), so nothing shows through. Measured
# worst case: a red pixel 8 px from a corner.
AB_CORNER_CUT = 14

# Gems. Cut with a Chebyshev-diamond mask so only the diamond and its dark
# socket survive; everything outside is transparent and the composed rail
# shows through. Seam gem: the one over the row 1 col 3|4 seam. Corner gem:
# the bigger one at the block's own top left corner.
AB_GEM_SRC = (437, 157, 473, 193)      # 36 x 36, centre (455, 175)
AB_GEM_REACH = 17
AB_GEMBIG_SRC = (10, 149, 54, 193)     # 44 x 44, centre (32, 171)
AB_GEMBIG_REACH = 21

# Outer rail strips, tiled along each edge (14 px thick, the same profile
# horizontally and vertically).
AB_RAIL_H_SRC = (500, 152, 560, 166)   # 60 x 14, clean stretch of the top rail
AB_RAIL_V_SRC = (14, 216, 28, 276)     # 14 x 60, clean stretch of the left rail
AB_RAIL_T = 14.0

# The rune title plate with its painted red X (decoration: the action bar has
# no game element there). Bottom edge y=174, i.e. 22 px into the block.
AB_TITLE_SRC = (590, 117, 1431, 174)   # 841 x 57
AB_TITLE_DROP = 22.0
# The painted red X on the plate: no game element belongs there and the user
# asked for it gone, so it is tiled over with the plate's own rune band.
# Box and source strip are in the TITLE SPRITE's own pixels.
AB_TITLE_X_BOX = (778, 4, 836, 53)
AB_TITLE_X_SRC = (600, 660)

# ---------------------------------------------------------------------------
# The XP / reputation / honor bar, same art file.
# The bar is cut into a left cap (gem), a right cap (gem) and a middle piece
# stretched between them, so the end gems keep their shape at any bar width.
# Everything scales from the status bar's own HEIGHT against XP_INTERIOR_H.
# ---------------------------------------------------------------------------
# The sprite band. It starts at 464, NOT at the art's 456: rows 452..461 are
# the action bar block's own tapering bottom rim (the art puts the XP bar
# right under the rows, with a transparent gap at 462..463), and carrying
# them into the XP sprites drew a stray full-width line with tapered ends
# above the bar wherever the bar is not sitting under the action bars.
XP_Y0, XP_Y1 = 464, 530
XP_INTERIOR = (479, 508)               # the painted fill interior, art y
XP_CAP_L_SRC = (4, XP_Y0, 104, XP_Y1)  # 100 x 76; the painted fill starts at art x 68
XP_CAP_R_SRC = (1894, XP_Y0, 1994, XP_Y1)
XP_MID_SRC = (296, XP_Y0, 386, XP_Y1)  # 90 x 76, a stretch with no segment divider
XP_FILL_X0 = 68                        # art x where the fill interior starts
XP_FILL_X1 = 1930                      # ... and ends (mirror of the left cap)
# The painted blue fill's soft edge runs one or two pixels past the interior
# box (measured: rows 480..508, first column 67), so the box that is CLEARED
# is a touch bigger than the box the layout uses -- otherwise a blue hairline
# survives along the top, the bottom and the left cap.
XP_CLEAR_Y = (478, 510)
XP_CLEAR_X0 = 66
XP_CLEAR_X1 = 1932
# One painted segment divider, cropped to its metal core only: the art paints
# a navy shadow either side of it that would read as a blue smudge over the
# empty (unfilled) part of the game's bar.
XP_TICK_SRC = (168, 478, 175, 510)     # 7 x 32
XP_SEGMENT = 112.0                     # art px between two segment dividers

# ---------------------------------------------------------------------------
# docs/unitframe-frame.webp, cropped to (44, 9, 1911, 650) -> 1867 x 641
# ---------------------------------------------------------------------------
UF_CROP = (44, 9, 1911, 650)
UF_RING = (322, 307, 288, 228)         # cx, cy, outer radius, portrait hole radius
# The radius the GAME'S portrait is placed at -- bigger than the hole on
# purpose. Two things make it so: the class icon is drawn through a circular
# mask whose art does not reach its own edges, so the visible disc is about
# 0.92 of the box it is given; and the portrait now draws UNDER the painted
# ring (see UnitFramePanel), so anything past the ring's inner metal edge is
# covered by the ring rather than spilling over it.
#
# Measured from the user's mark-up: on the player crop the wanted (green)
# circle is 91 px across and the current visible disc 80, with the hole's own
# 456 art px box measuring 87 px there -- so the visible disc must grow by
# 91/80, the box by 91/80 / 0.92 of the hole, which is radius 259, and 264 is
# that with the ~2 % overfill that guarantees no gap can show at the ring.
UF_PORTRAIT_R = 264
UF_LEVEL = (136, 513, 88)              # cx, cy, r of the red level badge
# The badge sits 277.5 art px from the ring centre and its art reaches ~110
# px, so 167 px of it fall INSIDE the portrait hole we clear (radius 228) --
# the clear punched a hole straight through the badge, and with the portrait
# now drawn under the skin the class icon showed through it. The disc clear
# skips everything within this radius of the badge centre. 111 is the badge's
# dark rim's outer edge: past it lies the painted face, which must stay cut.
UF_LEVEL_KEEP_R = 111
# The two bar interiors, re-measured on the painted fills themselves: the blue
# health fill runs x 687..1763, y 320..401 and the red power fill x 690..1766,
# y 460..545 (both taper at the ends, where the art's fill fills the taper).
# The first pass stopped at x 1753 and left a visible blue/red sliver between
# the game's bar and the end gem -- seen in the client.
UF_HEALTH_BOX = (687, 319, 1764, 402)
UF_POWER_BOX = (690, 458, 1766, 547)
UF_CLEAR_MARGIN = 2                    # clear a touch more than the box, for the fills' soft edge
UF_NAME_BOX = (856, 141, 1606, 271)
# The strip tiled over the painted name: the flattest 60 px of the plate at
# the name's own rows (std 20.1 against 25.3 for the strip used before, which
# carried rune marks that read as leftover text).
UF_NAME_SRC = (730, 790)
# The painted red X at the top right: removed at the user's request (the
# frames have no close button), tiled over with the rune band to its left so
# the plate's corner reads as one continuous piece.
UF_CROSS_BOX = (1776, 118, 1863, 208)
UF_CROSS_SRC = (1680, 1767)

# ---------------------------------------------------------------------------
# docs/castbar-frame.webp, cropped to (25, 197, 1974, 497) -> 1949 x 300
# ---------------------------------------------------------------------------
CB_CROP = (25, 197, 1974, 497)
CB_FILL_BOX = (298, 79, 1646, 140)
# The middle diamond ornament sits inside the cleared fill. Its socket is 156
# art px across at the fill's mid height (measured: no painted blue between
# x 897 and 1052), so a Chebyshev reach of 78 keeps the ornament and nothing
# else -- the first pass used 100 and kept a ring of painted BLUE FILL around
# the gem, which showed in the client as a blue halo on both cast bars.
CB_MID_GEM = (975, 109, 79)            # cx, cy, chebyshev reach of the middle ornament
CB_MIDGEM_BOX = (975 - 82, CB_FILL_BOX[1], 975 + 82, CB_FILL_BOX[3])
# Everything blue inside this band is cleared after the fill box, so no
# hairline of painted fill survives along the top edge (the painted fill's
# soft edge reaches row 78, one above the fill box) or beside the ornament.
CB_FILL_BAND = (280, 72, 1670, 150)
CB_NAME_BOX = (615, 168, 1335, 293)

# The dark trough the modules draw under every game fill, sampled from the
# art's own empty bar segment (the XP bar's unfilled part is RGB 7,20,51).
# Nearly opaque: at 50% black the ground showed through and the bars read as
# holes in the frame rather than slots.
TROUGH = (0.04, 0.07, 0.17, 0.88)

# ---------------------------------------------------------------------------
# The parts sheet. Every sprite is pasted at 1:1 (except SLOT, resampled
# square) at the position given here; the UVs below follow from that.
# ---------------------------------------------------------------------------
PARTS_W, PARTS_H = 2048, 512


def _size(src):
    return src[2] - src[0], src[3] - src[1]


# name -> (sheet x, sheet y, width, height)
PARTS = {
    "SLOT":    (0, 0, AB_SLOT_SIZE, AB_SLOT_SIZE),
    "GEM":     (170, 0, *_size(AB_GEM_SRC)),
    "GEMBIG":  (215, 0, *_size(AB_GEMBIG_SRC)),
    "RAIL_H":  (270, 0, *_size(AB_RAIL_H_SRC)),
    "RAIL_V":  (340, 0, *_size(AB_RAIL_V_SRC)),
    "XP_TICK": (360, 0, *_size(XP_TICK_SRC)),
    "TITLE":   (0, 180, *_size(AB_TITLE_SRC)),
    "XP_L":    (850, 180, *_size(XP_CAP_L_SRC)),
    "XP_R":    (955, 180, *_size(XP_CAP_R_SRC)),
    "XP_MID":  (1060, 180, *_size(XP_MID_SRC)),
}


def uv(name):
    x, y, w, h = PARTS[name]
    return (x / PARTS_W, (x + w) / PARTS_W, y / PARTS_H, (y + h) / PARTS_H)


def part_size(name):
    return PARTS[name][2], PARTS[name][3]


# ---------------------------------------------------------------------------
# Runtime rules, all as fractions of the CELL PITCH (the distance between two
# neighbouring button centres). These are exactly the numbers the Lua module
# multiplies the measured pitch by.
# ---------------------------------------------------------------------------
def actionbar_rules():
    tw, th = part_size("TITLE")
    return {
        "hole": AB_HOLE,
        "icon": AB_ICON,
        "rail": AB_RAIL_T / AB_CELL_PITCH,
        "gem": _size(AB_GEM_SRC)[0] / AB_CELL_PITCH,
        "cornerGem": _size(AB_GEMBIG_SRC)[0] / AB_CELL_PITCH,
        # The title plate is a fraction of the BLOCK's width, not of one cell:
        # in the art it covers 42% of the bar however many slots the bar has,
        # and the art's own slots are wider than the clean 145 px cell, so
        # pinning it to the cell pitch made it too wide for a 12 x 47 row.
        "titleBlockW": tw / float(AB_BLOCK[2] - AB_BLOCK[0]),
        "titleH": th / AB_CELL_PITCH,
        "titleDrop": AB_TITLE_DROP / AB_CELL_PITCH,
        # Two rows that Edit Mode has left touching share one divider: their
        # two rails together are exactly the 28 art px the art paints between
        # rows, but only ONE row of gems belongs on it. A gap up to this many
        # rail thicknesses counts as "touching".
        "joinGap": 3.0,
    }


# ... and for the XP bar, as fractions of the status bar's own HEIGHT.
def xpbar_rules():
    ih = float(XP_INTERIOR[1] - XP_INTERIOR[0])
    cw, ch = part_size("XP_L")
    tw, th = part_size("XP_TICK")
    return {
        "capW": cw / ih,
        "capH": ch / ih,
        # how far the cap's own left edge sits left of the status bar's left edge
        "capInsetX": (XP_FILL_X0 - XP_CAP_L_SRC[0]) / ih,
        # ... and how far its top edge sits above the status bar's top edge
        "capInsetY": (XP_INTERIOR[0] - XP_Y0) / ih,
        "tickW": tw / ih,
        "tickH": th / ih,
        "tickTop": (XP_TICK_SRC[1] - XP_INTERIOR[0]) / ih,
        "segment": XP_SEGMENT / ih,
    }

"""
Layout numbers for the painted backpack window, shared by
Tools/make_backpack_frame.py (builds Media/Textures/BackpackFrame.tga and
writes Media/BackpackLayout.lua) and Tools/preview_backpack.py (renders the
composed window locally with PIL). Modules/BackpackPanel.lua reads the
generated Lua table; never hand-edit that file, change the numbers here.

All numbers are pixels of the 1484 x 1060 painting docs/backpack-frame.webp.

The window is a vertical nine-slice: a fixed TOP piece (ring, title bar,
search bar, sort button), one BAND per row of slots (the two rails with plain
stone between them), and a fixed BOTTOM piece (the money bar and the two
corner gems). The carved slot is ONE sprite laid once per item slot, so the
frame fits any slot count: rows = ceil(slots / columns), the top row holds
the remainder, right-aligned, exactly like the game's own bottom-right-first
grid, so nothing jumps when a bag is added. The art's own top row has six
slots and rune text in the empty cells; that text is a sprite shown when at
least RUNES_MIN_EMPTY cells of the top row are free.

Horizontally the pieces are split at CAP_LEFT / CAP_RIGHT into a left cap, a
stretch zone and a right cap; with the game's ten columns the stretch is
1:1, another column count widens or narrows only the plain zone.
"""

ART_W = 1484            # the painting's width; the window's width at ten columns
ART_FRAME_H = 930       # the painting's window (the bag boxes under it are not used)

# --- vertical slices --------------------------------------------------------
TOP_H = 278             # y 0..278: everything above the first row of slots
ROW_PITCH = 139         # one row band; rows repeat at this pitch
BOTTOM_H = 100          # y 830..930: money bar, bottom rail, corner gems
BOTTOM_START = ART_FRAME_H - BOTTOM_H
BAND_REF_Y = 417        # the band cut from the art: row 2's band (rails only; the interior is filled with STONE_STRIP)
STONE_STRIP = (52, 236, 1449, 280)   # clean stone between the search bar's shadow and the slots, mirror-tiled into the band

# --- horizontal split (caps and stretch zone) --------------------------------
CAP_LEFT = 560          # x 0..560 is the left cap (ring, rune text, money bar's left part)
CAP_RIGHT = 940         # x 940..1484 is the right cap (cross, sort button, money)
BAND_RAIL_L = 52        # the band's left rail cap (0..52); the first slot's gem starts at ~53
BAND_RAIL_R = 1449      # the band's right rail cap (1449..1484)

# --- the slot grid ----------------------------------------------------------
COLUMNS = 10            # the art's columns; the game's combined bag lays out ten as well
SLOT_X0 = 60            # first rim's left edge
SLOT_Y0 = 8             # first rim's top, from the TOP piece's bottom (art y 286)
SLOT_PITCH_X = 140.67   # (1326 - 60) / 9
SLOT_W, SLOT_H = 120, 122          # a slot's rim box
SLOT_REF = (198, 423)   # rim box of the sprite source: row 2, column 2 (empty in the art)
SLOT_MARGIN = 12        # stone kept around the rim in the sprite (feathered), so the corner gems fit
SLOT_INSET = 5          # the game's button sits this far inside the rim (art px)
RIGHT_MARGIN = ART_W - 1441        # art px right of the last rim (the right rail)

# --- rune text in the top row's free cells -----------------------------------
RUNES = (70, 320, 614, 402)        # absolute art box of the text (glyphs span x 82..600, y 335..388)
RUNES_MIN_EMPTY = 4                # shown only when this many top-row cells are free

# --- the game's controls (art boxes; TOP-relative unless noted) ---------------
RING = (27, 34, 175, 153)
TITLE = (230, 42, 1330, 106)
CROSS = (1392, 38, 1463, 106)
SEARCH = (232, 165, 1332, 217)
SORT = (1360, 160, 1436, 226)
MONEY = (1150, 8, 1440, 52)        # relative to the BOTTOM piece's top (art y 838..882)

# --- painting out the picture's own text --------------------------------------
TITLE_TEXT = (520, 40, 965, 108)   # "Combined Backpack"
TITLE_PLAIN = (468, 40, 518, 108)  # plain bar next to it
MONEY_TEXT = (1150, 838, 1418, 882)
MONEY_PLAIN = (470, 40, 516, 108)
GOLD_BOX = (670, 919, 783, 1047)   # the gold-edged bag box under the frame: the bag column's hover glow
CORNER_GEMS = ((46.5, 894), (1441, 894))   # ring centres kept when the bag row is cleared
CORNER_R = 38

# --- the atlas ---------------------------------------------------------------
ATLAS_W, ATLAS_H = 2048, 1024
# where each piece lands in the atlas (x, y); sizes follow from the numbers above
ATLAS = {
    "TOP": (0, 0),
    "BAND": (0, TOP_H),
    "BOTTOM": (0, TOP_H + ROW_PITCH),
    "SLOT": (0, TOP_H + ROW_PITCH + BOTTOM_H + 4),
    "RUNES": (160, TOP_H + ROW_PITCH + BOTTOM_H + 4),
    "GOLD": (720, TOP_H + ROW_PITCH + BOTTOM_H + 4),
}


def slot_sprite_size():
    return SLOT_W + 2 * SLOT_MARGIN, SLOT_H + 2 * SLOT_MARGIN


def art_width(columns=COLUMNS):
    """Window width in art px for a column count (ten = the painting)."""
    return ART_W + (columns - COLUMNS) * SLOT_PITCH_X


def art_height(rows):
    return TOP_H + rows * ROW_PITCH + BOTTOM_H


def rim_box(row, col):
    """Rim box (x0, y0, x1, y1) of the slot in `row` (0 = top) and `col` (0 = left)."""
    x0 = SLOT_X0 + col * SLOT_PITCH_X
    y0 = TOP_H + row * ROW_PITCH + SLOT_Y0
    return x0, y0, x0 + SLOT_W, y0 + SLOT_H


def cell_of(index, slots, columns=COLUMNS):
    """(row, col) of the game's item `index` (1 = bottom right) in a bag of `slots`."""
    import math
    rows = max(1, math.ceil(slots / columns))
    from_bottom, from_right = divmod(index - 1, columns)
    return rows - 1 - from_bottom, columns - 1 - from_right

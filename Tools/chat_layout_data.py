"""
Single source of truth for the chat window skin: every crop box on
docs/chat-frame.png (the user's dedicated chat art, 1577 x 997 RGBA) and every
geometry constant, all in ART PIXELS. Tools/make_chat_frame.py reads this to
build Media/Textures/ChatFrame.tga and Media/ChatLayout.lua (loaded by
Modules/ChatPanel.lua as MelloUI_ChatLayout); Tools/preview_chat.py composes
the window from the SAME numbers into a PNG. Change numbers only here.

Measured with PIL on docs/chat-frame.png (pixel columns/rows, see the
zoomed grids in MelloUI-BuildData/output/chat-cuts.png):

  frame border box      x 104..1460, y 154..823 (this box IS the skin frame)
  left rail             x 104..133  (bronze stripe, body stone starts at 133)
  top rail              y 154..180  (the shelf the tabs stand on)
  body stone            x 133..1362, y 180..710
  scroll track column   x 1362..1460 (+ the red gems overhanging to 1477)
    up button           y 183..241, x 1368..1427 (chevron centre x ~1397)
    small gem mark      y 244..296
    shaft               y 300..550 (two plain vertical lines)
    thumb gem (diamond) x 1371..1429, y 582..641 (the grey knob above it is not used)
    down button         y 648..702
  thin rail             y 710..730 (the bar above the input row)
  input row band        y 731..794
  bottom border         y 795..823
  tabs                  y 93..160 (their bottoms merge into the rail top at 157)
    "General" (open)    x 127..350, text x 175..300, rim colour orange
    "Trade" (plain)     x 638..879, text x 717..797, flat grey interior
  gems: top-right centred (1437,172) spans x 1410..1477, y 140..205;
        bottom-right centred (1437,800) spans x 1405..1471, y 765..848.

There is NO left button column in this art: the game's four side buttons
stand left of the window on a plate composed from the plain tab's own rim.
"""

SRC = "docs/chat-frame.png"
STONE_SRC = "docs/stone-tile.png"          # the user's repeatable stone (shared with the other windows)
STONE_TILE = "Media/Textures/StoneTile.tga"  # 512 x 512, mirror 2x2 -> central 1024 -> LANCZOS 512
STONE_TILE_PX = 512

# This file is painted about twice as heavy as the bottom bar / damage meter
# art read on screen (its bronze rails are 11 px thick; the bar's rim is 4
# texture px drawn at 0.75 px each, the meter's 10 file px drawn at 0.18 px
# each). ART_SCALE brings one file pixel down to a "native" pixel first;
# then everything is drawn at native px * FIXED_SCALE physical screen pixels
# (the bars' rule; FIXED_SCALE is the module's `scale` option default). At
# 0.5 x 0.75 the chat's rails come out ~4 px, between the bar's ~3.5 px and
# the meter's ~2 px, and the tab plates still hold GameFontNormalSmall.
ART_SCALE = 0.5
FIXED_SCALE = 0.75

# ---- the skin frame's own box in the art; every offset below is relative
# to its corners (TL = (104,154), BR = (1460,823)). ---------------------------
SKIN = (104, 154, 1460, 823)
BODY = (133, 180, 1362, 710)                # the stone box between the rails

# ---- crop boxes (x0, y0, x1, y1) in art px --------------------------------------
# Pieces that touch the body carry a strip of the art's own stone with a
# SHADOW ramp: alpha falls from 1 at the rail's inner edge to 0 at `far`, so
# the art's painted vignette lies over the repeated stone tile instead of a
# hard seam. `shadow` = {axis: (edge, far)}; the stone side is edge->far, a
# pixel is shadowed when it is on the stone side of EVERY listed axis, and
# alpha *= 1 - prod(1 - ramp_axis).
SHADOW_X_L = (133, 150)      # left rail's inner edge, ramp to the right
SHADOW_X_R = (1362, 1345)    # scroll column's inner edge, ramp to the left
SHADOW_Y_T = (180, 196)      # top rail's underside, ramp downward
SHADOW_Y_B = (710, 694)      # thin rail's top, ramp upward

PIECES = {
	# name:            (box,                      stretch,  shadow)   stretch "diamond" = fixed size, alpha-masked to a diamond
	"CORNER_TL":       ((104, 154, 165, 215),     None,     {"x": SHADOW_X_L, "y": SHADOW_Y_T}),
	"TOP_RAIL":        ((165, 154, 1345, 196),    "h",      {"y": SHADOW_Y_T}),
	"SCROLL_TOP":      ((1345, 140, 1477, 243),   None,     {"x": SHADOW_X_R, "y": SHADOW_Y_T}),
	"GEM_MARK":        ((1345, 243, 1477, 298),   None,     {"x": SHADOW_X_R}),
	"SCROLL_MID":      ((1345, 300, 1477, 550),   "v",      {"x": SHADOW_X_R}),
	"SCROLL_BOTTOM":   ((1345, 645, 1477, 710),   None,     {"x": SHADOW_X_R}),
	"BOTTOM_R":        ((1345, 694, 1477, 848),   None,     {"x": SHADOW_X_R, "y": SHADOW_Y_B}),
	"BOTTOM_MID":      ((165, 694, 1345, 823),    "h",      {"y": SHADOW_Y_B}),
	"BOTTOM_L":        ((104, 680, 165, 823),     None,     {"x": SHADOW_X_L, "y": SHADOW_Y_B}),
	"LEFT_RAIL":       ((104, 215, 150, 680),     "v",      {"x": SHADOW_X_L}),
	# the thumb is JUST the red diamond gem (no grey knob body): cut on its
	# bounding square and masked to the diamond so the track's side lines in
	# the square's corners are dropped
	"THUMB":           ((1371, 582, 1429, 641),   "diamond", None),
	# tab plates: cap / mid / cap, the mid a text-free vertical slice that
	# carries the plate's top rim and its bottom edge, so any width has a rim
	"TAB_OPEN_L":      ((124, 93, 152, 160),      None,     None),
	"TAB_OPEN_MID":    ((152, 93, 172, 160),      "h",      None),
	"TAB_OPEN_R":      ((325, 93, 353, 160),      None,     None),
	"TAB_PLAIN_L":     ((635, 93, 663, 160),      None,     None),
	"TAB_PLAIN_MID":   ((665, 93, 705, 160),      "h",      None),
	"TAB_PLAIN_R":     ((854, 93, 882, 160),      None,     None),
}

# How each frame piece hangs on the skin: every listed anchor point of the
# piece attaches to the SAME point of the skin, offset by (piece box corner -
# skin box corner) in art px, so a piece sits exactly where it is in the art
# whatever the skin's size. One anchor = fixed size (the box's own); two
# anchors = stretched between them, the other dimension fixed. SCROLL_MID's
# top follows GEM_MARK's top when the gem mark is hidden (short chat).
PLACEMENT = {
	"CORNER_TL":     ("TOPLEFT",),
	"TOP_RAIL":      ("TOPLEFT", "TOPRIGHT"),
	"SCROLL_TOP":    ("TOPRIGHT",),
	"GEM_MARK":      ("TOPRIGHT",),
	"SCROLL_MID":    ("TOPRIGHT", "BOTTOMRIGHT"),
	"SCROLL_BOTTOM": ("BOTTOMRIGHT",),
	"BOTTOM_R":      ("BOTTOMRIGHT",),
	"BOTTOM_MID":    ("BOTTOMLEFT", "BOTTOMRIGHT"),
	"BOTTOM_L":      ("BOTTOMLEFT",),
	"LEFT_RAIL":     ("TOPLEFT", "BOTTOMLEFT"),
}
# a stretched piece whose crop is shorter than the span it must fill hangs
# on this box instead of its crop box (the shaft crop skips the thumb)
ANCHOR_BOX = {
	"SCROLL_MID": (1345, 298, 1477, 645),   # from under the gem mark to the down button's top
}
# the draw order (first = lowest): rails under corners/caps, so a corner's
# ornament always wins where two pieces overlap
DRAW_ORDER = ("LEFT_RAIL", "TOP_RAIL", "BOTTOM_MID", "SCROLL_MID", "SCROLL_TOP", "GEM_MARK", "SCROLL_BOTTOM",
	"BOTTOM_R", "BOTTOM_L", "CORNER_TL")

# The side button plate is COMPOSED (not cropped): the outer SIDE_CAP px of
# the plain tab's caps with its mid between them, laid SIDE_PLATE px wide,
# then the plate's upper half mirrored onto its lower half so the plate has
# a rim on all four sides. 108 art px = 40 physical px = 34 UI units at the
# dump's uiPerPx, the game's 32 + 2 button pitch, so the plates just touch.
SIDE_PLATE = 108
SIDE_CAP = 28

# ---- placement (art px, relative to the skin box) ---------------------------------
GEOMETRY = {
	"SKIN_W": SKIN[2] - SKIN[0], "SKIN_H": SKIN[3] - SKIN[1],
	"BODY_L": BODY[0] - SKIN[0], "BODY_T": BODY[1] - SKIN[1],       # 29, 26
	"BODY_R": SKIN[2] - BODY[2], "BODY_B": SKIN[3] - BODY[3],       # 98, 113
	# ChatFrame1 sits inside the body box with these insets
	"CHAT_PAD_L": 8, "CHAT_PAD_T": 8, "CHAT_PAD_R": 4, "CHAT_PAD_B": 6,
	# tabs: the dock's bottom edge relative to the skin top (positive = above
	# the top rail's top), where the first tab starts, and the plate's bottom
	# relative to the game tab's bottom
	"TAB_X0": 127 - SKIN[0],                                     # 23
	"TAB_PLATE_DY": -8,                                          # plate bottom below the tab's bottom
	"TAB_PLATE_BOTTOM": 160 - SKIN[1],                           # 6 below the skin top
	"TAB_CAP_W": 28, "TAB_H": 67,
	"TAB_TEXT_FROM_BOTTOM": 30,                                  # label centre above the plate's bottom
	# the scroll bar: chevron column centre from the skin's right edge, the
	# up button's top from the skin top, the down button's bottom from the skin bottom
	"SCROLL_CX": SKIN[2] - 1397, "SCROLL_TOP_Y": 183 - SKIN[1], "SCROLL_BOTTOM_Y": SKIN[3] - 702,
	"SCROLL_BUTTON_W": 59, "SCROLL_BUTTON_H": 58,
	# body height needed before the small gem mark is shown under the up
	# button: its own room plus a full thumb's travel below it
	"GEM_MARK_NEEDS": (298 - BODY[1]) + (BODY[3] - 645) + (645 - 553),
	# the edit box on the input row band
	"EDIT_L": 139 - SKIN[0], "EDIT_TOP": SKIN[3] - 733, "EDIT_R": SKIN[2] - 1426, "EDIT_BOTTOM": SKIN[3] - 792,
	# the game's side button column: gap from the skin's left edge
	"SIDE_GAP": 6, "SIDE_PLATE": SIDE_PLATE,
}

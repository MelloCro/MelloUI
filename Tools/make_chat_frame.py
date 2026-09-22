"""
Build the chat window skin's texture AND its Lua layout data from the single
source of truth in Tools/chat_layout_data.py (crop boxes + geometry, all in
art px). Modules/ChatPanel.lua loads Media/ChatLayout.lua (MelloUI_ChatLayout)
instead of hardcoding any of this, and Tools/preview_chat.py composes an
offline preview from the exact same boxes, so the built texture, the module
and the preview can never differ -- change only chat_layout_data.py, then
re-run this script and Tools/preview_chat.py.

  Media/Textures/ChatFrame.tga   one 2048 x 512 atlas: corners, rails, the
                                 scroll track pieces, the thumb, the tab
                                 caps/mids, the composed side button plate
  Media/Textures/StoneTile.tga   the shared repeatable stone body (built here
                                 only if no other builder has written it yet:
                                 mirror 2x2 -> central 1024 -> LANCZOS 512)
  Media/ChatLayout.lua           MelloUI_ChatLayout = { atlas, stone, fixedScale,
                                 geometry, sprites }
  MelloUI-BuildData/output/chat-cuts.png     every crop box drawn on the art
  MelloUI-BuildData/output/chatframe-atlas-preview.png   the atlas over green

Pieces that border the body carry a strip of the art's own stone whose alpha
ramps to 0 (chat_layout_data.SHADOW_*): the painted vignette lies over the
repeated stone tile instead of a hard seam. Nothing painted with text is
ever cut: every box avoids the tab labels.

    python Tools\\make_chat_frame.py
"""
import os

import numpy as np
from PIL import Image, ImageDraw

from chat_layout_data import ANCHOR_BOX, ART_SCALE, BODY, DRAW_ORDER, FIXED_SCALE, GEOMETRY, PIECES, PLACEMENT, SIDE_CAP, SIDE_PLATE, SKIN, SRC, STONE_SRC, STONE_TILE, STONE_TILE_PX
from paths import OUTPUT

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
SRC_PATH = os.path.join(ROOT, SRC)
TEX = os.path.join(ROOT, "Media", "Textures")
MEDIA = os.path.join(ROOT, "Media")
OUT = OUTPUT

SHEET_W, SHEET_H = 2048, 512


def ramp(v, edge, far):
	"""1 at the rail's inner edge, 0 at `far`, clamped; v may be an array."""
	return np.clip((far - v) / float(far - edge), 0.0, 1.0)


def shadowed(img, box, shadow):
	"""Multiply the alpha of the stone strip inside `box` by the shadow ramps."""
	if not shadow:
		return img
	a = np.array(img).astype(np.float32)
	x0, y0, x1, y1 = box
	xs = np.arange(x0, x1)[None, :]
	ys = np.arange(y0, y1)[:, None]
	inside = np.ones((y1 - y0, x1 - x0), dtype=bool)
	keep = np.ones((y1 - y0, x1 - x0), dtype=np.float32)   # prod(1 - ramp)
	for axis, (edge, far) in shadow.items():
		v = xs if axis == "x" else ys
		stone_side = (v - edge) * (far - edge) >= 0
		inside &= np.broadcast_to(stone_side, inside.shape)
		keep = keep * np.broadcast_to(1.0 - ramp(v, edge, far), keep.shape)
	mult = np.where(inside, 1.0 - keep, 1.0)
	a[:, :, 3] = a[:, :, 3] * mult
	return Image.fromarray(a.clip(0, 255).astype(np.uint8), "RGBA")


def diamond_mask(img, feather=1.5):
	"""Alpha-mask a piece to the diamond inscribed in its box (the gem cuts)."""
	a = np.array(img).astype(np.float32)
	h, w = a.shape[0], a.shape[1]
	ys = np.arange(h)[:, None] + 0.5
	xs = np.arange(w)[None, :] + 0.5
	d = np.abs(xs - w / 2) / (w / 2) + np.abs(ys - h / 2) / (h / 2)   # 1 on the diamond's edge
	edge = feather / (min(w, h) / 2)
	mult = np.clip((1 + edge - d) / edge, 0.0, 1.0)
	a[:, :, 3] = a[:, :, 3] * mult
	return Image.fromarray(a.clip(0, 255).astype(np.uint8), "RGBA")


def compose_side_plate(pieces, size, cap=SIDE_CAP):
	"""The outer `cap` px of the plain tab's caps with its mid between, laid
	`size` wide, then the upper half mirrored onto the lower half: a square
	plate with a rim on all four sides."""
	l, m, r = pieces["TAB_PLAIN_L"], pieces["TAB_PLAIN_MID"], pieces["TAB_PLAIN_R"]
	h = l.height
	l = l.crop((0, 0, cap, h))
	r = r.crop((r.width - cap, 0, r.width, h))
	strip = Image.new("RGBA", (size, h), (0, 0, 0, 0))
	mid_w = max(1, size - l.width - r.width)
	strip.paste(l, (0, 0))
	strip.paste(m.resize((mid_w, h), Image.LANCZOS), (l.width, 0))
	strip.paste(r, (size - r.width, 0))
	half = size // 2
	top = strip.crop((0, 0, size, half))
	plate = Image.new("RGBA", (size, size), (0, 0, 0, 0))
	plate.paste(top, (0, 0))
	plate.paste(top.transpose(Image.FLIP_TOP_BOTTOM), (0, size - half))
	return plate


def build_stone_tile(src_path, out_path, px):
	src = Image.open(src_path).convert("RGBA")
	w, h = src.size
	big = Image.new("RGBA", (w * 2, h * 2))
	big.paste(src, (0, 0))
	big.paste(src.transpose(Image.FLIP_LEFT_RIGHT), (w, 0))
	big.paste(src.transpose(Image.FLIP_TOP_BOTTOM), (0, h))
	big.paste(src.transpose(Image.FLIP_LEFT_RIGHT).transpose(Image.FLIP_TOP_BOTTOM), (w, h))
	cx, cy = w, h
	tile = big.crop((cx - 512, cy - 512, cx + 512, cy + 512)).resize((px, px), Image.LANCZOS)
	tile.save(out_path)
	return tile


def main():
	art = Image.open(SRC_PATH).convert("RGBA")
	print(f"source {SRC_PATH}: {art.size}")
	os.makedirs(OUT, exist_ok=True)
	os.makedirs(TEX, exist_ok=True)

	pieces = {}
	for name, (box, stretch, shadow) in PIECES.items():
		pieces[name] = shadowed(art.crop(box), box, shadow)
		if stretch == "diamond":
			pieces[name] = diamond_mask(pieces[name])
	pieces["SIDE_PLATE"] = compose_side_plate(pieces, SIDE_PLATE)

	# ---- the shared stone body tile ----------------------------------------------
	stone_path = os.path.join(ROOT, STONE_TILE)
	if os.path.exists(stone_path):
		print(f"  {STONE_TILE} already present, left as is")
	else:
		build_stone_tile(os.path.join(ROOT, STONE_SRC), stone_path, STONE_TILE_PX)
		print(f"  built {STONE_TILE} {STONE_TILE_PX} x {STONE_TILE_PX} from {STONE_SRC}")

	# ---- atlas: shelf packing, tallest first per row ---------------------------------
	sheet = Image.new("RGBA", (SHEET_W, SHEET_H), (0, 0, 0, 0))
	parts = {}
	# the tall vertical rails go in a column at the left, everything else in
	# shelves to their right (tallest first)
	tall = [n for n in pieces if pieces[n].height > SHEET_H // 2]
	col_w, y = 0, 0
	for name in tall:
		img = pieces[name]
		if y + img.height > SHEET_H:
			raise SystemExit(f"atlas overflow at {name}")
		sheet.paste(img, (0, y))
		parts[name] = (0, y, img.width, img.height)
		y += img.height + 2
		col_w = max(col_w, img.width)
	x0 = col_w + 2 if tall else 0
	x, y, row_h = x0, 0, 0
	for name in sorted((n for n in pieces if n not in tall), key=lambda n: -pieces[n].height):
		img = pieces[name]
		if x + img.width > SHEET_W:
			x, y = x0, y + row_h + 2
			row_h = 0
		if y + img.height > SHEET_H:
			raise SystemExit(f"atlas overflow at {name}")
		sheet.paste(img, (x, y))
		parts[name] = (x, y, img.width, img.height)
		x += img.width + 2
		row_h = max(row_h, img.height)
	sheet.save(os.path.join(TEX, "ChatFrame.tga"))
	print(f"ChatFrame.tga {SHEET_W} x {SHEET_H}")

	sprite_lines = []
	for name in list(PIECES) + ["SIDE_PLATE"]:
		px, py, pw, ph = parts[name]
		u0, u1 = px / SHEET_W, (px + pw) / SHEET_W
		v0, v1 = py / SHEET_H, (py + ph) / SHEET_H
		stretch = PIECES[name][1] if name in PIECES else None
		if stretch == "diamond":
			stretch = None   # a fixed-size sprite; the mask is baked into the atlas
		print(f"  {name:14s} sheet {px:4d},{py:4d} {pw:4d} x {ph:3d}  stretch={stretch}")
		extra = ', stretch = "%s"' % stretch if stretch else ""
		if name in PIECES:
			extra += ", box = { %d, %d, %d, %d }" % PIECES[name][0]
		if name in PLACEMENT:
			extra += ", anchors = { %s }" % ", ".join('"%s"' % p for p in PLACEMENT[name])
		if name in ANCHOR_BOX:
			extra += ", place = { %d, %d, %d, %d }" % ANCHOR_BOX[name]
		sprite_lines.append(
			"\t\t%s = { uv = { %.6f, %.6f, %.6f, %.6f }, w = %d, h = %d%s }," % (name, u0, u1, v0, v1, pw, ph, extra))

	geometry_lines = "\n".join(f"\t\t{k} = {v}," for k, v in GEOMETRY.items())
	lua_path = lambda p: p.replace("/", "\\\\")  # noqa: E731
	lua = f"""-- Generated by Tools/make_chat_frame.py from {SRC}.
-- Do not edit by hand: change Tools/chat_layout_data.py and re-run the script
-- (Tools/preview_chat.py renders the same numbers locally for checking).
-- Every geometry number is in ART (file) pixels; the module multiplies by
-- artScale * scale option (fixedScale default) * (UI units per physical pixel).

MelloUI_ChatLayout = {{
	atlas = "Interface\\\\AddOns\\\\MelloUI\\\\{lua_path("Media/Textures/ChatFrame.tga")}",
	stone = "Interface\\\\AddOns\\\\MelloUI\\\\{lua_path(STONE_TILE)}",
	stonePx = {STONE_TILE_PX},
	artScale = {ART_SCALE},
	fixedScale = {FIXED_SCALE},
	skin = {{ {SKIN[0]}, {SKIN[1]}, {SKIN[2]}, {SKIN[3]} }},
	body = {{ {BODY[0]}, {BODY[1]}, {BODY[2]}, {BODY[3]} }},
	drawOrder = {{ {", ".join('"%s"' % n for n in DRAW_ORDER)} }},
	geometry = {{
{geometry_lines}
	}},
	sprites = {{
{chr(10).join(sprite_lines)}
	}},
}}
"""
	with open(os.path.join(MEDIA, "ChatLayout.lua"), "w", encoding="utf-8", newline="\r\n") as f:
		f.write(lua)
	print("  wrote Media/ChatLayout.lua")

	# ---- checks: the cut boxes on the art, the atlas over green -----------------------
	bg = Image.new("RGBA", art.size, (0, 140, 0, 255))
	bg.alpha_composite(art)
	cuts = bg.convert("RGB")
	d = ImageDraw.Draw(cuts)
	colours = [(255, 0, 0), (0, 255, 255), (255, 255, 0), (255, 0, 255), (0, 255, 0), (255, 128, 0), (128, 128, 255)]
	for i, (name, (box, _s, _sh)) in enumerate(PIECES.items()):
		c = colours[i % len(colours)]
		d.rectangle(box, outline=c, width=2)
		d.text((box[0] + 3, box[1] + 3), name, fill=c)
	d.rectangle(SKIN, outline=(255, 255, 255), width=1)
	d.rectangle(BODY, outline=(0, 0, 255), width=1)
	cuts.save(os.path.join(OUT, "chat-cuts.png"))

	bg = Image.new("RGBA", sheet.size, (0, 140, 0, 255))
	bg.alpha_composite(sheet)
	bg.convert("RGB").save(os.path.join(OUT, "chatframe-atlas-preview.png"))
	print("  MelloUI-BuildData/output/chat-cuts.png and chatframe-atlas-preview.png written")


if __name__ == "__main__":
	main()

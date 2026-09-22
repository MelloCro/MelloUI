"""
Compose the chat window skin EXACTLY as Modules/ChatPanel.lua lays it out --
same pieces, same boxes, same placement rules, same scale (art px *
ART_SCALE * FIXED_SCALE physical pixels), all from Tools/chat_layout_data.py -- into
PNGs, so the cut and the layout can be checked against docs/chat-frame.png
before touching the addon.

The window is sized from ChatFrame1 exactly like the module: skin = chat
size + the fixed margins. Defaults are the in-game numbers from the last
/chdump (uiPerPx 0.8333; ChatFrame1 about 444 x 131 UI units, i.e. the skin
came out 547 x 251 UI = 656 x 301 physical px).

    python Tools\\preview_chat.py [--chat-w 444 --chat-h 131 --ui-per-px 0.8333]

Writes Tools/output/chat-preview-composed.png (in-game size),
chat-preview-wide.png (1.5x chat width) and chat-preview-vs-art.png (the
composed window under the art scaled to the same ART_SCALE * FIXED_SCALE).
"""
import argparse
import os

from PIL import Image, ImageDraw, ImageFont

from chat_layout_data import ANCHOR_BOX, ART_SCALE, DRAW_ORDER, FIXED_SCALE, GEOMETRY, PIECES, PLACEMENT, SIDE_PLATE, SKIN, SRC, STONE_TILE, STONE_TILE_PX

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
OUT = os.path.join(HERE, "output")
G = GEOMETRY
PX_PER_ART = ART_SCALE * FIXED_SCALE      # physical px per art (file) px

# game-side sizes in UI units (from the Blizzard templates)
TAB_UI_H = 32          # ChatTabArtTemplate
TAB_GAP_UI = 1         # FCFDock_UpdateTabs spacing
SIDE_BUTTON_UI = 32    # ChatFrameMenuButton / voice buttons
SIDE_COLUMN_UI = 29    # ChatFrame1ButtonFrame width
SIDE_GAP_UI = 2        # between the voice buttons
DEMO_TABS = [("General", 72, True), ("Combat Log", 96, False), ("Trade", 62, False), ("Guild", 60, False)]


def layout(chat_w_ui, chat_h_ui, ui_per_px):
	"""Every rect in ART units relative to the skin's top-left, exactly the
	module's arithmetic (the module multiplies each art unit by s = ART_SCALE * FIXED_SCALE
	* ui_per_px to get UI units; here art units are kept and drawn at
	PX_PER_ART physical px per art unit)."""
	s = PX_PER_ART * ui_per_px            # UI units per art unit
	ui = lambda v: v / s                  # noqa: E731  UI units -> art units
	chat_w, chat_h = ui(chat_w_ui), ui(chat_h_ui)
	W = chat_w + G["BODY_L"] + G["CHAT_PAD_L"] + G["CHAT_PAD_R"] + G["BODY_R"]
	H = chat_h + G["BODY_T"] + G["CHAT_PAD_T"] + G["CHAT_PAD_B"] + G["BODY_B"]
	body_h = H - G["BODY_T"] - G["BODY_B"]
	r = {}
	r["skin"] = (0, 0, W, H)
	r["body"] = (G["BODY_L"], G["BODY_T"], W - G["BODY_R"], H - G["BODY_B"])
	r["chat"] = (G["BODY_L"] + G["CHAT_PAD_L"], G["BODY_T"] + G["CHAT_PAD_T"], W - G["BODY_R"] - G["CHAT_PAD_R"], H - G["BODY_B"] - G["CHAT_PAD_B"])

	show_gem = body_h >= G["GEM_MARK_NEEDS"]

	def corner(box, point):
		x = box[0] if "LEFT" in point else box[2]
		y = box[1] if "TOP" in point else box[3]
		return x, y

	for name, points in PLACEMENT.items():
		if name == "GEM_MARK" and not show_gem:
			continue
		crop = PIECES[name][0]
		box = ANCHOR_BOX.get(name, crop)
		if name == "SCROLL_MID" and not show_gem:
			box = (box[0], PIECES["GEM_MARK"][0][1], box[2], box[3])
		pw, ph = crop[2] - crop[0], crop[3] - crop[1]
		edges = {}
		for point in points:
			bx, by = corner(box, point)
			sx, sy = corner(SKIN, point)
			edges["x1" if "RIGHT" in point else "x0"] = (W if "RIGHT" in point else 0) + (bx - sx)
			edges["y1" if "BOTTOM" in point else "y0"] = (H if "BOTTOM" in point else 0) + (by - sy)
		x0 = edges.get("x0", edges.get("x1", 0) - pw)
		x1 = edges.get("x1", x0 + pw)
		y0 = edges.get("y0", edges.get("y1", 0) - ph)
		y1 = edges.get("y1", y0 + ph)
		r[name] = (x0, y0, x1, y1)

	# the game's tab dock: its bottom edge (= every tab's bottom) sits so that
	# a plate hung TAB_PLATE_DY below it lands TAB_PLATE_BOTTOM below the skin top
	dock_bottom = G["TAB_PLATE_BOTTOM"] + G["TAB_PLATE_DY"]
	r["dock"] = (G["TAB_X0"], dock_bottom - ui(TAB_UI_H), W - G["BODY_R"], dock_bottom)
	tabs = []
	x = G["TAB_X0"]
	for label, w_ui, is_open in DEMO_TABS:
		w = ui(w_ui)
		tab = (x, dock_bottom - ui(TAB_UI_H), x + w, dock_bottom)
		plate_bottom = dock_bottom - G["TAB_PLATE_DY"]
		plate = (x, plate_bottom - G["TAB_H"], x + w, plate_bottom)
		tabs.append({"label": label, "open": is_open, "tab": tab, "plate": plate, "cap": min(G["TAB_CAP_W"], w / 2),
			"text_y": plate_bottom - G["TAB_TEXT_FROM_BOTTOM"]})
		x += w + ui(TAB_GAP_UI)
	r["tabs"] = tabs

	# the game's scroll bar on the painted track
	cx = W - G["SCROLL_CX"]
	r["scrollbar"] = (cx - ui(4), G["SCROLL_TOP_Y"], cx + ui(4), H - G["SCROLL_BOTTOM_Y"])
	bw, bh = G["SCROLL_BUTTON_W"], G["SCROLL_BUTTON_H"]
	r["scroll_back"] = (cx - bw / 2, G["SCROLL_TOP_Y"], cx + bw / 2, G["SCROLL_TOP_Y"] + bh)
	r["scroll_forward"] = (cx - bw / 2, H - G["SCROLL_BOTTOM_Y"] - bh, cx + bw / 2, H - G["SCROLL_BOTTOM_Y"])
	# the game's Track runs from under the gem mark (or the up button) to the
	# down button's top; the thumb is held at the painted knob's height
	# (bar.fixedThumbExtent) so it never rides into the caps
	track_top = (PIECES["GEM_MARK"][0][3] if show_gem else PIECES["SCROLL_TOP"][0][3]) - SKIN[1]
	track_bottom = H - (SKIN[3] - PIECES["SCROLL_BOTTOM"][0][1])
	r["track"] = (cx - ui(4), track_top, cx + ui(4), track_bottom)
	knob_h = PIECES["THUMB"][0][3] - PIECES["THUMB"][0][1]
	thumb_h = min(knob_h, max(0, track_bottom - track_top))
	thumb_top = track_bottom - thumb_h
	r["thumb"] = (cx - ui(4), thumb_top, cx + ui(4), thumb_top + thumb_h)
	knob_w = PIECES["THUMB"][0][2] - PIECES["THUMB"][0][0]
	k = thumb_h / knob_h if knob_h else 1
	r["THUMB"] = (cx - knob_w * k / 2, thumb_top + thumb_h / 2 - knob_h * k / 2, cx + knob_w * k / 2, thumb_top + thumb_h / 2 + knob_h * k / 2)

	r["editbox"] = (G["EDIT_L"], H - G["EDIT_TOP"], W - G["EDIT_R"], H - G["EDIT_BOTTOM"])

	# the game's side button column, left of the window
	col_r = -G["SIDE_GAP"]
	col = (col_r - ui(SIDE_COLUMN_UI), G["BODY_T"], col_r, H - G["BODY_B"])
	r["side_column"] = col
	ccx = (col[0] + col[2]) / 2
	b = ui(SIDE_BUTTON_UI)
	buttons = []
	y = col[1]
	for _ in range(3):                                            # channel, deafen, mute from the top
		buttons.append((ccx - b / 2, y, ccx + b / 2, y + b))
		y += b + ui(SIDE_GAP_UI)
	buttons.append((ccx - b / 2, col[3] - b, ccx + b / 2, col[3]))  # menu at the bottom
	r["side_buttons"] = buttons
	r["side_plates"] = [((bx0 + bx1) / 2 - SIDE_PLATE / 2, (by0 + by1) / 2 - SIDE_PLATE / 2,
		(bx0 + bx1) / 2 + SIDE_PLATE / 2, (by0 + by1) / 2 + SIDE_PLATE / 2) for bx0, by0, bx1, by1 in buttons]
	return r


_art = None
_stone = None
_cache = {}


def art_piece(name):
	global _art
	if _art is None:
		_art = Image.open(os.path.join(ROOT, SRC)).convert("RGBA")
	if name not in _cache:
		if name == "SIDE_PLATE":
			from make_chat_frame import compose_side_plate, shadowed
			base = {n: shadowed(_art.crop(PIECES[n][0]), PIECES[n][0], PIECES[n][2]) for n in ("TAB_PLAIN_L", "TAB_PLAIN_MID", "TAB_PLAIN_R")}
			_cache[name] = compose_side_plate(base, SIDE_PLATE)
		else:
			from make_chat_frame import diamond_mask, shadowed
			box, stretch, shadow = PIECES[name]
			_cache[name] = shadowed(_art.crop(box), box, shadow)
			if stretch == "diamond":
				_cache[name] = diamond_mask(_cache[name])
	return _cache[name]


def stone():
	global _stone
	if _stone is None:
		_stone = Image.open(os.path.join(ROOT, STONE_TILE)).convert("RGBA")
	return _stone


def compose(r, scale=PX_PER_ART, labels=True, ui_per_px=0.8333):
	px = lambda v: int(round(v * scale))  # noqa: E731
	W, H = r["skin"][2], r["skin"][3]
	pad_l = px(-r["side_column"][0]) + 4
	pad_t = px(G["TAB_H"]) + 4
	pad_r = px(20)
	pad_b = px(30)
	canvas = Image.new("RGBA", (px(W) + pad_l + pad_r, px(H) + pad_t + pad_b), (18, 18, 22, 255))
	ox, oy = pad_l, pad_t

	def paste(img, rect):
		x0, y0, x1, y1 = rect
		w, h = max(1, px(x1) - px(x0)), max(1, px(y1) - px(y0))
		if img.size != (w, h):
			img = img.resize((w, h), Image.LANCZOS)
		canvas.alpha_composite(img, (ox + px(x0), oy + px(y0)))

	# body: the stone tile repeated at its native px * scale, never stretched
	bx0, by0, bx1, by1 = r["body"]
	body = Image.new("RGBA", (max(1, px(bx1) - px(bx0)), max(1, px(by1) - px(by0))))
	period = max(1, int(round(STONE_TILE_PX * scale)))
	tile = stone().resize((period, period), Image.LANCZOS)
	for ty in range(0, body.height, period):
		for tx in range(0, body.width, period):
			body.paste(tile, (tx, ty))
	canvas.alpha_composite(body, (ox + px(bx0), oy + px(by0)))

	for name in DRAW_ORDER:
		if name in r:
			paste(art_piece(name), r[name])
	for t in r["tabs"]:
		l, m, rr = ("TAB_OPEN_L", "TAB_OPEN_MID", "TAB_OPEN_R") if t["open"] else ("TAB_PLAIN_L", "TAB_PLAIN_MID", "TAB_PLAIN_R")
		x0, y0, x1, y1 = t["plate"]
		cap = t["cap"]
		paste(art_piece(l), (x0, y0, x0 + cap, y1))
		paste(art_piece(m), (x0 + cap, y0, x1 - cap, y1))
		paste(art_piece(rr), (x1 - cap, y0, x1, y1))
	for plate in r["side_plates"]:
		paste(art_piece("SIDE_PLATE"), plate)
	paste(art_piece("THUMB"), r["THUMB"])

	if labels:
		d = ImageDraw.Draw(canvas)
		try:
			font = ImageFont.truetype("arialbd.ttf", max(8, int(round(10 / ui_per_px))))   # GameFontNormalSmall, 10 UI units
		except OSError:
			font = ImageFont.load_default()
		for t in r["tabs"]:
			x0, _y0, x1, _y1 = t["plate"]
			cx, cy = ox + px((x0 + x1) / 2), oy + px(t["text_y"])
			d.text((cx, cy), t["label"], fill=(255, 214, 60), font=font, anchor="mm")
		# the game frames' outlines: ChatFrame1 (cyan), edit box (yellow), scroll bar (magenta), side column (white)
		def outline(rect, colour):
			x0, y0, x1, y1 = rect
			d.rectangle((ox + px(x0), oy + px(y0), ox + px(x1) - 1, oy + px(y1) - 1), outline=colour)
		outline(r["chat"], (0, 255, 255))
		outline(r["editbox"], (255, 255, 0))
		outline(r["scrollbar"], (255, 0, 255))
		outline(r["scroll_back"], (255, 0, 255))
		outline(r["scroll_forward"], (255, 0, 255))
		outline(r["thumb"], (255, 0, 255))
		outline(r["track"], (255, 0, 255))
		outline(r["side_column"], (255, 255, 255))
		for b in r["side_buttons"]:
			outline(b, (255, 255, 255))
		for t in r["tabs"]:
			outline(t["tab"], (0, 255, 0))
	return canvas


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--chat-w", type=float, default=444.0, help="ChatFrame1 width in UI units")
	ap.add_argument("--chat-h", type=float, default=131.0, help="ChatFrame1 height in UI units")
	ap.add_argument("--ui-per-px", type=float, default=0.8333)
	ap.add_argument("--no-labels", action="store_true")
	a = ap.parse_args()
	os.makedirs(OUT, exist_ok=True)

	r = layout(a.chat_w, a.chat_h, a.ui_per_px)
	s = PX_PER_ART * a.ui_per_px
	W, H = r["skin"][2], r["skin"][3]
	print(f"chat {a.chat_w} x {a.chat_h} UI -> skin {W * s:.1f} x {H * s:.1f} UI = {W * PX_PER_ART:.0f} x {H * PX_PER_ART:.0f} px  (art units {W:.0f} x {H:.0f}, {s:.4f} UI/art px)")
	print(f"  body {r['body']}  gem mark {'shown' if 'GEM_MARK' in r else 'hidden'}  scroll mid height {r['SCROLL_MID'][3] - r['SCROLL_MID'][1]:.0f} art")
	composed = compose(r, labels=not a.no_labels, ui_per_px=a.ui_per_px)
	composed.convert("RGB").save(os.path.join(OUT, "chat-preview-composed.png"))
	print("  Tools/output/chat-preview-composed.png", composed.size)

	wide = compose(layout(a.chat_w * 1.5, a.chat_h, a.ui_per_px), labels=not a.no_labels, ui_per_px=a.ui_per_px)
	wide.convert("RGB").save(os.path.join(OUT, "chat-preview-wide.png"))
	print("  Tools/output/chat-preview-wide.png", wide.size)

	art = Image.open(os.path.join(ROOT, SRC)).convert("RGBA")
	art_small = art.resize((int(art.width * PX_PER_ART), int(art.height * PX_PER_ART)), Image.LANCZOS)
	bg = Image.new("RGBA", art_small.size, (18, 18, 22, 255))
	bg.alpha_composite(art_small)
	pair = Image.new("RGB", (max(bg.width, composed.width), bg.height + composed.height + 10), (60, 60, 60))
	pair.paste(bg.convert("RGB"), (0, 0))
	pair.paste(composed.convert("RGB"), (0, bg.height + 10))
	pair.save(os.path.join(OUT, "chat-preview-vs-art.png"))
	print("  Tools/output/chat-preview-vs-art.png", pair.size)

	# the damage meter's composed preview (file px) brought to physical px
	# (its module draws one file px as 0.75 * ART_TO_OLD px), beside ours
	meter_path = os.path.join(OUT, "dpsmeter-composed.png")
	if os.path.exists(meter_path):
		meter = Image.open(meter_path).convert("RGB")
		k = 0.75 * 365.0 / 1525.0
		meter = meter.resize((max(1, int(meter.width * k)), max(1, int(meter.height * k))), Image.LANCZOS)
		plain = compose(r, labels=False, ui_per_px=a.ui_per_px).convert("RGB")
		both = Image.new("RGB", (plain.width + meter.width + 10, max(plain.height, meter.height)), (60, 60, 60))
		both.paste(plain, (0, 0))
		both.paste(meter, (plain.width + 10, 0))
		both.save(os.path.join(OUT, "chat-vs-meter.png"))
		print("  Tools/output/chat-vs-meter.png", both.size, "(both at physical px)")


if __name__ == "__main__":
	main()

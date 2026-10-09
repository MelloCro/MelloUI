--------------------------------------------------------------------------------
-- MelloUI - FrameFX: effects played on a unit's frame (0.20.0; the shared
-- engine of Heal Flight and Frame Effects: docs/plans/heal-flight.md,
-- docs/plans/frame-effects.md -- the user, 2026-10-09, made the tanks' and
-- defensives' effects a feature of their own, "Frame Effects": one engine in
-- the core, never a copy per feature)
--
-- Sprites of Media/FrameFX/ (light, the game's ADD blend; drawn by
-- Tools/heal_flight_art.py), placed every frame by a stage's step
-- (MelloUI.Anim:Drive hands it its share of the way):
--   charge   on the cast bar while you cast: round its spell icon and at its
--            fill's leading edge (anchored to the game's fill: nothing read)
--   launch   from the icon (or, a hop, from a frame) along a curve to a frame
--   land     a kind's landing on the frame: a timeline of parts, each with
--            its own start, end and envelope (LANDINGS below): a white flash,
--            a lens streak, rays, waves, sparks, leaves, a crest, a column of
--            light, a sheen, rune marks, square ripples, the kit's border
--            glow (Kit:GlowNine) -- drawn in a frame of ours laid on the
--            target frame, clipping what shows 10% past its sides
-- Looks (the heals'): holy (gold), nature (green and gold, leaves), water
-- (blue and foam, droplets, ripples, a bubble), quiet (the border's flare and
-- little else). The heals' kinds: h heal, o heal over time, s shield, p
-- protection, b big heal (heal to full), r resurrection, t a heal over time's
-- tick; a group or chain heal lands as a heal. The tanks' tools and defensives
-- (COOLDOWNS, the same in every look): W roar (square ripples, 2 s), U
-- taunt, F fortify, L more health, I immunity, E evasion.
-- A layer is one frame of ours with its own pooled sprites and up to two
-- border glows; its state lives in this file's tables, never on a frame.
--   FX.Host() -> host, FX.FreeLayer() -> layer, FX.Layer(host) -> layer
--   FX.state[layer]                its geometry (the caller sets it)
--   FX.Charge(layer, look) / FX.Stop(layer)
--   FX.Land(layer, look, kind, quiet[, hop])   fly, then land
--   FX.Strike(layer, look, kind, quiet[, dur]) land at once (an instant)
--   FX.Show(unit, kind, look, quiet, dur) -> layer   a kind's landing on the
--                                  unit's frame (nil: none of its shown)
--   FX.Clear(layer), FX.Free(layer)
-- The frames (the same for every feature): FX.Members() -> list, set (your
-- group's units now); FX.Canon(unit) (you in a raid: your raid unit);
-- FX.FrameUnit(f); FX.FrameOf(unit) -> the unit's frame shown (MelloUI's Group
-- Frames first, then the game's); FX.Rect(region) -> l, b, r, t in UIParent's
-- units (nil when not plain); FX.Ask(fn, ...) -> true / false / nil (secret).
-- Nothing at login: the host, its layers and their sprites are made on first
-- use.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Safe = MelloUI.Safe
local Secret, Text, Num, ScreenRect = Safe.IsSecret, Safe.Text, Safe.Number, Safe.ScreenRect
local Anim = MelloUI.Anim

local FX = {}
MelloUI.FrameFX = FX

local MEDIA = "Interface\\AddOns\\MelloUI\\Media\\FrameFX\\"
local TAU = 2 * math.pi
local cos, sin, min, max, floor = math.cos, math.sin, math.min, math.max, math.floor
local TIME = { launch = 0.32, hop = 0.22, chargeFade = 0.15, chargeMax = 3 }
FX.TIME = TIME

local WEAK = { __mode = "k" }
local sprites = setmetatable({}, WEAK)   -- [layer] = { texture, ... }
local fileOf = setmetatable({}, WEAK)    -- [texture] = the sprite it shows
local flares = setmetatable({}, WEAK)    -- [layer] = { [slot] = { holder, nine } }
local clips = setmetatable({}, WEAK)     -- [layer] = { frame (clips its children), texture }
local state = setmetatable({}, WEAK)     -- [layer] = its geometry and stage
local tintOf = setmetatable({}, WEAK)    -- [texture] = the colour it is tinted now ({ r, g, b })
local covers = setmetatable({}, WEAK)    -- [layer] = what stands over its light: { frame, tex, text } (a split's)
FX.state = state
FX.sprites = sprites   -- (the tests')
FX.clips = clips       -- (the tests': a landing's sprites live in its clip frame)
FX.tintOf, FX.covers = tintOf, covers   -- (the tests')

--------------------------------------------------------------------------------
-- Sprites
--------------------------------------------------------------------------------

local function Sprite(layer, i)
	local list = sprites[layer]
	local t = list[i]
	if not t then
		t = layer:CreateTexture(nil, "OVERLAY")
		t:SetBlendMode("ADD")
		list[i] = t
	end
	return t
end

-- (w = nil: its anchors size it)
local function Show(t, file, w, h, a, rot)
	if fileOf[t] ~= file then
		t:SetTexture(MEDIA .. file)
		fileOf[t] = file
	end
	if w then
		t:SetSize(max(1, w), max(1, h or w))
	end
	t:SetAlpha(max(0, min(1, a)))
	t:SetRotation(rot or 0)
	t:Show()
end

-- the colours (the game's, constant): { r, g, b } each, read once
local WHITE_RGB = { 1, 1, 1 }
local rgbOf = {}
local function RgbOf(colour)
	local c = rgbOf[colour]
	if not c then
		local W = MelloUI.Widgets
		local r, g, b = 1, 1, 1
		if W and W.ColourValue then
			r, g, b = W.ColourValue(colour)
		end
		c = { r, g, b }
		rgbOf[colour] = c
	end
	return c
end
local function Rgb(colour)
	local c = RgbOf(colour)
	return c[1], c[2], c[3]
end

-- sprite i at (x, y) in UIParent's units, tinted `tint` ({ r, g, b }; white);
-- returns the next index
local function Put(layer, i, file, x, y, w, h, a, rot, tint)
	if a <= 0.004 then
		return i
	end
	local t = Sprite(layer, i)
	t:ClearAllPoints()
	t:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
	Show(t, file, w, h, a, rot)
	tint = tint or WHITE_RGB
	if tintOf[t] ~= tint then
		t:SetVertexColor(tint[1], tint[2], tint[3])
		tintOf[t] = tint
	end
	return i + 1
end

-- sprite i centred on a point of a region (the game's cast bar fill: anchored,
-- never read)
local function PutOn(layer, i, file, region, point, w, h, a)
	local t = Sprite(layer, i)
	t:ClearAllPoints()
	t:SetPoint("CENTER", region, point, 0, 0)
	Show(t, file, w, h, a)
	return i + 1
end

-- sprite i stretched over a region (with `pad` round it)
local function PutOver(layer, i, file, region, pad, a)
	local t = Sprite(layer, i)
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", region, "TOPLEFT", -pad, pad)
	t:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", pad, -pad)
	Show(t, file, nil, nil, a)
	return i + 1
end

local function HideFrom(layer, i)
	local list = sprites[layer]
	for k = i, #list do
		list[k]:Hide()
	end
end

--------------------------------------------------------------------------------
-- The path: a curve from S.x0, S.y0 to S.x1, S.y1, bending upwards; its end
-- may move while it flies (the caller retargets)
--------------------------------------------------------------------------------

local function Path(S, t)
	t = max(0, min(1, t))
	local u = 1 - t
	return u * u * S.x0 + 2 * u * t * S.cx + t * t * S.x1, u * u * S.y0 + 2 * u * t * S.cy + t * t * S.y1
end

local function Normal(S, t)
	local dx = 2 * (1 - t) * (S.cx - S.x0) + 2 * t * (S.x1 - S.cx)
	local dy = 2 * (1 - t) * (S.cy - S.y0) + 2 * t * (S.y1 - S.cy)
	local n = math.sqrt(dx * dx + dy * dy)
	if n == 0 then
		return 0, 1
	end
	return -dy / n, dx / n
end

-- the control point: the line's middle pushed out (a third of its length; a
-- hop a fifth), on the side that bends upwards
function FX.Bend(S, share)
	local dx, dy = S.x1 - S.x0, S.y1 - S.y0
	local len = math.sqrt(dx * dx + dy * dy)
	local nx, ny = 0, 1
	if len > 0 then
		nx, ny = -dy / len, dx / len
		if ny < 0 then
			nx, ny = -nx, -ny
		end
	end
	share = share or 0.3
	S.cx, S.cy = (S.x0 + S.x1) / 2 + nx * len * share, (S.y0 + S.y1) / 2 + ny * len * share
end

--------------------------------------------------------------------------------
-- The charge (S.ix, S.iy, S.isz: the icon; S.bl .. S.bt: the bar; S.fill:
-- the game's fill texture, anchored to; S.start, S.castTime)
--------------------------------------------------------------------------------

local function Ramp(S)
	local e = GetTime() - S.start
	return e, min(1, e / max(0.3, S.castTime or 1.5))
end

local function FillEdge(layer, n, S, r, glow, streak)
	if not S.fill then
		return n
	end
	local s = S.isz
	n = PutOver(layer, n, "glow_gold.tga", S.fill, s * 0.35, 0.25 + 0.35 * r)
	n = PutOn(layer, n, glow, S.fill, "RIGHT", s * 2.4, s * 1.8, 0.7 + 0.3 * r)
	n = PutOn(layer, n, glow, S.fill, "RIGHT", s * 1.2, s * 1.0, 0.6 + 0.4 * r)
	return PutOn(layer, n, streak, S.fill, "RIGHT", s * 5.5, s * 1.1, 0.35 + 0.55 * r)
end

local function ChargeA(layer, S)
	local e, r = Ramp(S)
	local x, y, s = S.ix, S.iy, S.isz
	local pulse = 0.85 + 0.15 * sin(e * 8)
	local n = Put(layer, 1, "ring_gold.tga", x, y, s * 3.4, nil, 0.45 + 0.55 * r, e * 1.4)
	n = Put(layer, n, "glow_gold.tga", x, y, s * 4.2, nil, (0.35 + 0.55 * r) * pulse)
	n = Put(layer, n, "glow_white.tga", x, y, s * 1.7, nil, 0.3 + 0.6 * r)
	for k = 0, 15 do
		local f = (e * 0.9 + k / 16) % 1
		local rad = s * (2.8 * (1 - f) ^ 1.2 + 0.3)
		local ang = (k % 4) * TAU / 4 + f * 2.6 * math.pi
		n = Put(layer, n, "spark_gold.tga", x + rad * cos(ang), y + rad * sin(ang) * 0.75, s * (0.45 + 0.55 * f), nil,
			(0.35 + 0.65 * f) * (0.5 + 0.5 * r))
	end
	n = FillEdge(layer, n, S, r, "glow_gold.tga", "streak_gold.tga")
	HideFrom(layer, n)
end

local function ChargeB(layer, S)
	local e, r = Ramp(S)
	local x, y, s = S.ix, S.iy, S.isz
	local n = 1
	-- two ribbons round the bar: short arcs of light circling it
	local mx, my = (S.bl + S.br) / 2, (S.bb + S.bt) / 2
	local rx, ry = (S.br - S.bl) / 2 + s * 0.9, (S.bt - S.bb) * 1.3 + s * 0.5
	for o = 0, 1 do
		local base = o * math.pi + e * (1.5 + 0.35 * o)
		for j = 0, 11 do
			local ang = base + j * 0.06
			local bell = sin(math.pi * j / 11)
			n = Put(layer, n, o == 0 and "glow_green.tga" or "glow_gold.tga", mx + rx * cos(ang),
				my + ry * sin(ang) + s * 0.2 * o, s * (0.55 + 0.4 * bell), nil, (0.5 + 0.5 * r) * (0.4 + 0.6 * bell))
		end
	end
	-- leaves drifting in to the icon
	for k = 0, 5 do
		local f = (e * 0.55 + k / 6) % 1
		local ang = k * TAU / 6 + 0.6
		local rad = s * 3.8 * (1 - f) + s * 0.4
		n = Put(layer, n, "leaf.tga", x + rad * cos(ang), y + rad * sin(ang) * 0.6, s * 1.0, nil,
			sin(math.pi * f) * (0.6 + 0.4 * r), ang + math.pi)
	end
	n = Put(layer, n, "glow_green.tga", x, y, s * 3.8, nil, 0.3 + 0.5 * r)
	n = Put(layer, n, "glow_white.tga", x, y, s * 1.5, nil, 0.25 + 0.55 * r)
	n = FillEdge(layer, n, S, r, "glow_gold.tga", "streak_green.tga")
	HideFrom(layer, n)
end

-- Water: water circling the bar, droplets drawn in to the icon, a ripple round it
local function ChargeW(layer, S)
	local e, r = Ramp(S)
	local x, y, s = S.ix, S.iy, S.isz
	local n = 1
	local mx, my = (S.bl + S.br) / 2, (S.bb + S.bt) / 2
	local rx, ry = (S.br - S.bl) / 2 + s * 0.9, (S.bt - S.bb) * 1.2 + s * 0.45
	for o = 0, 1 do
		local base = o * math.pi + e * (1.7 + 0.3 * o)
		for j = 0, 11 do
			local ang = base + j * 0.06
			local bell = sin(math.pi * j / 11)
			n = Put(layer, n, o == 0 and "glow_blue.tga" or "glow_white.tga", mx + rx * cos(ang), my + ry * sin(ang),
				s * (o == 0 and (0.6 + 0.4 * bell) or (0.35 + 0.25 * bell)), nil, (0.5 + 0.5 * r) * (0.4 + 0.6 * bell))
		end
	end
	for k = 0, 7 do
		local f = (e * 0.6 + k / 8) % 1
		local ang = k * TAU / 8 + 0.3
		local rad = s * 3.6 * (1 - f) + s * 0.5
		-- (its point the way it moves: in to the icon)
		n = Put(layer, n, "drop.tga", x + rad * cos(ang), y + rad * sin(ang) * 0.6, s * 0.75, nil,
			sin(math.pi * f) * (0.6 + 0.4 * r), ang + math.pi / 2)
	end
	local ring = (e * 0.8) % 1
	n = Put(layer, n, "ripple_blue.tga", x, y, s * (1.6 + 1.6 * ring), s * (1.3 + 1.3 * ring), (1 - ring) * (0.5 + 0.5 * r))
	n = Put(layer, n, "glow_blue.tga", x, y, s * 3.8, nil, 0.3 + 0.5 * r)
	n = Put(layer, n, "glow_white.tga", x, y, s * 1.4, nil, 0.25 + 0.5 * r)
	n = FillEdge(layer, n, S, r, "glow_blue.tga", "streak_blue.tga")
	HideFrom(layer, n)
end

local function ChargeC(layer, S)
	local _, r = Ramp(S)
	local n = FillEdge(layer, 1, S, r * 0.8, "glow_gold.tga", "streak_gold.tga")
	n = Put(layer, n, "glow_gold.tga", S.ix, S.iy, S.isz * 2.4, nil, 0.25 + 0.4 * r)
	HideFrom(layer, n)
end

--------------------------------------------------------------------------------
-- The flight (S.isz the scale; a hop: no release flash at its start)
--------------------------------------------------------------------------------

local function Release(layer, n, S, p, glow)
	if S.hop or p > 0.3 then
		return n
	end
	local a = 1 - p / 0.3
	n = Put(layer, n, glow, S.x0, S.y0, S.isz * 5, nil, a)
	return Put(layer, n, "glow_white.tga", S.x0, S.y0, S.isz * 2.4, nil, a)
end

local function Head(layer, n, S, p, glow, streak, big)
	local hx, hy = Path(S, p)
	local s = S.isz * (big or 1)
	n = Put(layer, n, glow, hx, hy, s * 3.6, nil, 1)
	n = Put(layer, n, glow, hx, hy, s * 2.2, nil, 1)
	n = Put(layer, n, "glow_white.tga", hx, hy, s * 1.5, nil, 1)
	n = Put(layer, n, "glow_white.tga", hx, hy, s * 0.9, nil, 1)
	return Put(layer, n, streak, hx, hy, s * 6, s * 1.2, 0.85)
end

local function LaunchA(layer, S, p)
	local s = S.isz
	local n = Release(layer, 1, S, p, "glow_gold.tga")
	for i = 16, 1, -1 do
		local x, y = Path(S, p - i * 0.028)
		n = Put(layer, n, "glow_gold.tga", x, y, s * 2.1 * (1 - i / 18), nil, 1 - i / 17)
	end
	for i = 1, 8 do
		local t = p - i * 0.05
		if t > 0 then
			local x, y = Path(S, t)
			local nx, ny = Normal(S, t)
			local o = (i % 2 == 0 and 1 or -1) * s * 0.14 * i
			n = Put(layer, n, "spark_gold.tga", x + nx * o, y + ny * o, s * 0.6, nil, 1 - i / 9)
		end
	end
	n = Head(layer, n, S, p, "glow_gold.tga", "streak_gold.tga")
	HideFrom(layer, n)
end

local function LaunchB(layer, S, p)
	local s = S.isz
	local n = Release(layer, 1, S, p, "glow_green.tga")
	for strand = 0, 1 do
		for i = 12, 1, -1 do
			local t = p - i * 0.026
			if t > 0 then
				local x, y = Path(S, t)
				local nx, ny = Normal(S, t)
				local o = s * 0.55 * sin(strand * math.pi + t * 26) * (0.4 + 0.6 * (1 - i / 12))
				n = Put(layer, n, strand == 0 and "glow_green.tga" or "glow_gold.tga", x + nx * o, y + ny * o,
					s * (1.0 - 0.05 * i), nil, 1 - i / 13)
			end
		end
	end
	for i = 1, 4 do
		local t = p - i * 0.08
		if t > 0 then
			local x, y = Path(S, t)
			local nx, ny = Normal(S, t)
			local o = (i % 2 == 0 and 1 or -1) * s * 0.75
			n = Put(layer, n, "leaf.tga", x + nx * o, y + ny * o, s * 0.95, nil, 1 - i / 5, t * 14 + i)
		end
	end
	n = Head(layer, n, S, p, "glow_green.tga", "streak_green.tga")
	HideFrom(layer, n)
end

local function LaunchC(layer, S, p)
	local s = S.isz
	local n = 1
	for i = 18, 1, -1 do
		local x, y = Path(S, p - i * 0.022)
		n = Put(layer, n, "glow_gold.tga", x, y, s * (0.6 - 0.018 * i), nil, 1 - i / 19)
	end
	local hx, hy = Path(S, p)
	n = Put(layer, n, "glow_gold.tga", hx, hy, s * 1.9, nil, 0.9)
	n = Put(layer, n, "glow_white.tga", hx, hy, s * 0.9, nil, 1)
	n = Put(layer, n, "streak_gold.tga", hx, hy, s * 3.6, s * 0.7, 0.6)
	HideFrom(layer, n)
end

-- Water: two strands winding round each other, droplets thrown off, a splash of a head
local function LaunchW(layer, S, p)
	local s = S.isz
	local n = Release(layer, 1, S, p, "glow_blue.tga")
	for strand = 0, 1 do
		for i = 12, 1, -1 do
			local t = p - i * 0.026
			if t > 0 then
				local x, y = Path(S, t)
				local nx, ny = Normal(S, t)
				local o = s * 0.5 * sin(strand * math.pi + t * 22) * (0.4 + 0.6 * (1 - i / 12))
				n = Put(layer, n, strand == 0 and "glow_blue.tga" or "glow_white.tga", x + nx * o, y + ny * o,
					s * (strand == 0 and (1.0 - 0.05 * i) or (0.6 - 0.03 * i)), nil, 1 - i / 13)
			end
		end
	end
	for i = 1, 5 do
		local t = p - i * 0.07
		if t > 0 then
			local x, y = Path(S, t)
			local nx, ny = Normal(S, t)
			local o = (i % 2 == 0 and 1 or -1) * s * (0.6 + 0.1 * i)
			-- (thrown off sideways: its point outwards)
			n = Put(layer, n, "drop.tga", x + nx * o, y + ny * o, s * 0.7, nil, 1 - i / 6,
				math.atan2(ny * o, nx * o) - math.pi / 2)
		end
	end
	n = Head(layer, n, S, p, "glow_blue.tga", "streak_blue.tga")
	HideFrom(layer, n)
end

--------------------------------------------------------------------------------
-- The landings: per look and kind, a list of parts. A part: its kind (the
-- function drawing it), its sprite, from t0 to t1 (s), its envelope
-- (flash: up at once, falling fast; hold: up, held, down; fade; pulse: up and
-- down), its peak alpha `a` (1) and `stack` (drawn so many times: brighter).
-- Sizes and offsets in u (the frame's height); `fit` = w, h of the frame's own
-- width and height. Sprites are placed from the frame's centre unless `at`
-- = "tr" (its top right corner, the plus's spot).
--------------------------------------------------------------------------------

local GOLD, GREEN, BLUE = "LIGHTYELLOW_FONT_COLOR", "GREEN_FONT_COLOR", "LIGHTBLUE_FONT_COLOR"

local FLASH = { "sprite", "glow_white.tga", fit = true, w = 1, h = 1, t0 = 0, t1 = 0.22, env = "flash", stack = 2 }
local FLASH_BIG = { "sprite", "glow_white.tga", fit = true, w = 1, h = 1, t0 = 0, t1 = 0.32, env = "flash", stack = 3 }
local FLASH_SOFT = { "sprite", "glow_white.tga", fit = true, w = 1, h = 1, t0 = 0, t1 = 0.16, env = "flash", a = 0.55 }

local function Streak(file, w, t1)
	-- (across the frame's own width, inside it -- the user 2026-10-09; `w`, the callers' old
	-- length, no longer used)
	return { "sprite", file, fit = true, w = 1.0, h = 0.4, t0 = 0, t1 = t1 or 0.36, env = "flash", grow = { 0.6, 1.0 } }
end

local function Border(colour, slot, grow, t0, t1, a, env)
	return { "border", colour = colour, slot = slot, grow = grow, t0 = t0, t1 = t1, a = a or 1, env = env or "hold" }
end

local LANDINGS = {
	holy = {
		h = {
			FLASH, Streak("streak_gold.tga", 7),
			{ "sprite", "rays_gold.tga", fit = true, w = 1, h = 1, t0 = 0, t1 = 0.5, env = "flash", grow = { 0.48, 1 }, spin = 0.1 },
			{ "sprite", "wave_gold.tga", fit = true, w = 1, h = 1, t0 = 0, t1 = 0.45, env = "fade", grow = { 0.35, 1 } },
			{ "spray", "spark_gold.tga", n = 10, r0 = 0.3, r1 = 0.9, size = 0.5, t0 = 0, t1 = 0.6, env = "fade" },
			{ "plus", "plus_gold.tga", size = 0.62, t0 = 0.04, t1 = 1.0, env = "hold" },
			Border(GOLD, 1, 0, 0, 1.3),
			{ "runes", "rune_gold.tga", m = -0.1, size = 0.26, t0 = 0.25, t1 = 1.4, env = "hold", a = 0.9 },
			{ "rise", "spark_gold.tga", n = 6, height = 0.7, size = 0.3, t0 = 0.3, t1 = 1.4, env = "hold" },
		},
		o = {
			{ "sprite", "wave_gold.tga", fit = true, w = 1, h = 1, t0 = 0, t1 = 0.5, env = "pulse", grow = { 1, 0.61 } },
			{ "settle", "spark_gold.tga", n = 10, from = 1.3, size = 0.4, t0 = 0, t1 = 1.0, env = "hold" },
			{ "sprite", "glow_white.tga", fit = true, w = 1, h = 1, t0 = 0.38, t1 = 0.62, env = "flash", a = 0.8 },
			{ "sprite", "glow_gold.tga", fit = true, w = 1, h = 1, t0 = 0.3, t1 = 1.0, env = "pulse", a = 0.7 },
			Border(GOLD, 1, 0, 0.3, 1.25, 0.8),
		},
		s = {
			FLASH, Streak("streak_gold.tga", 6, 0.3),
			Border(GOLD, 1, 0, 0, 1.4),
			Border(GOLD, 2, -4, 0.04, 1.3, 0.6),
			{ "sheen", "sheen.tga", t0 = 0.12, t1 = 0.72 },
			{ "corners", "spark_gold.tga", m = -0.2, size = 0.5, t0 = 0, t1 = 1.0, env = "hold" },
		},
		p = {
			FLASH, Streak("streak_gold.tga", 8, 0.42),
			{ "crest", "crest_gold.tga", size = 1.0, t0 = 0.02, t1 = 1.5, env = "hold", stack = 2 },
			Border(GOLD, 1, 0, 0, 1.5),
			Border(GOLD, 2, -4, 0, 1.2, 0.65),
			{ "spray", "spark_gold.tga", n = 8, r0 = 0.5, r1 = 0.9, size = 0.45, t0 = 0, t1 = 0.7, env = "fade" },
		},
		b = {
			FLASH_BIG, Streak("streak_gold.tga", 10, 0.48),
			{ "pillar", "pillar_gold.tga", w = 0.9, h = 1.0, t0 = 0, t1 = 1.3, env = "hold", stack = 2, grow = { 0.35, 1 } },
			{ "sprite", "rays_gold.tga", fit = true, w = 1, h = 1, t0 = 0, t1 = 0.7, env = "flash", grow = { 0.43, 1 }, spin = 0.08, stack = 2 },
			{ "sprite", "wave_gold.tga", fit = true, w = 1, h = 1, t0 = 0, t1 = 0.6, env = "fade", grow = { 0.27, 1 } },
			{ "spray", "spark_gold.tga", n = 16, r0 = 0.3, r1 = 0.9, size = 0.55, t0 = 0, t1 = 0.8, env = "fade" },
			{ "rise", "spark_gold.tga", n = 10, height = 0.7, size = 0.35, t0 = 0.1, t1 = 1.5, env = "hold" },
			{ "plus", "plus_gold.tga", size = 0.78, t0 = 0.04, t1 = 1.2, env = "hold" },
			Border(GOLD, 1, 0, 0, 1.5),
		},
		r = {
			{ "pillar", "pillar_gold.tga", w = 0.9, h = 1.0, t0 = 0, t1 = 1.9, env = "hold", stack = 2, grow = { 0.15, 1 } },
			{ "rise", "spark_gold.tga", n = 12, height = 0.7, size = 0.38, t0 = 0, t1 = 1.9, env = "hold" },
			{ "sprite", "glow_gold.tga", fit = true, w = 1, h = 1, t0 = 0.2, t1 = 1.7, env = "pulse", a = 0.9 },
			{ "sprite", "glow_white.tga", fit = true, w = 1, h = 1, t0 = 0.9, t1 = 1.3, env = "flash", a = 0.8 },
			Border(GOLD, 1, 0, 0.2, 1.8, 0.8),
		},
		-- (a heal over time's tick: a small ring closing, three motes, the border warm)
		t = {
			{ "sprite", "wave_gold.tga", fit = true, w = 1, h = 1, t0 = 0, t1 = 0.6, env = "pulse", grow = { 1, 0.68 }, a = 0.75 },
			{ "settle", "spark_gold.tga", n = 3, from = 0.9, size = 0.3, t0 = 0, t1 = 0.7, env = "hold" },
			Border(GOLD, 1, 0, 0, 0.7, 0.4, "pulse"),
		},
	},
	nature = {
		h = {
			FLASH, Streak("streak_green.tga", 7),
			{ "sprite", "wave_teal.tga", fit = true, w = 1, h = 1, t0 = 0, t1 = 0.45, env = "fade", grow = { 0.35, 1 } },
			{ "sprite", "glow_green.tga", fit = true, w = 1, h = 1, t0 = 0, t1 = 0.4, env = "flash" },
			{ "spray", "leaf.tga", n = 12, r0 = 0.25, r1 = 0.9, size = 0.55, t0 = 0, t1 = 0.65, env = "fade", turn = true },
			{ "plus", "plus_green.tga", size = 0.62, t0 = 0.04, t1 = 1.0, env = "hold" },
			Border(GREEN, 1, 0, 0, 1.3),
			{ "rise", "leaf.tga", n = 6, height = 0.7, size = 0.45, t0 = 0.3, t1 = 1.4, env = "hold", leaf = true },
		},
		o = {
			{ "sprite", "wave_teal.tga", fit = true, w = 1, h = 1, t0 = 0, t1 = 0.5, env = "pulse", grow = { 1, 0.61 } },
			{ "settle", "leaf.tga", n = 6, from = 1.4, size = 0.5, t0 = 0, t1 = 1.1, env = "hold", leaf = true },
			{ "sprite", "glow_white.tga", fit = true, w = 1, h = 1, t0 = 0.38, t1 = 0.62, env = "flash", a = 0.7 },
			{ "sprite", "glow_green.tga", fit = true, w = 1, h = 1, t0 = 0.3, t1 = 1.0, env = "pulse", a = 0.7 },
			Border(GREEN, 1, 0, 0.3, 1.25, 0.8),
		},
		s = {
			FLASH, Streak("streak_green.tga", 6, 0.3),
			Border(GREEN, 1, 0, 0, 1.4),
			Border(GREEN, 2, -4, 0.04, 1.3, 0.6),
			{ "sheen", "sheen.tga", t0 = 0.12, t1 = 0.72 },
			{ "orbit", "leaf.tga", n = 4, rx = 0.8, ry = 0.7, spin = 1.2, size = 0.5, t0 = 0, t1 = 1.2, env = "hold" },
		},
		p = {
			FLASH, Streak("streak_green.tga", 8, 0.42),
			{ "crest", "crest_green.tga", size = 1.0, t0 = 0.02, t1 = 1.5, env = "hold", stack = 2 },
			Border(GREEN, 1, 0, 0, 1.5),
			Border(GREEN, 2, -4, 0, 1.2, 0.65),
			{ "orbit", "leaf.tga", n = 10, rx = 0.8, ry = 0.7, spin = 2.2, size = 0.5, t0 = 0, t1 = 1.4, env = "hold" },
		},
		b = {
			FLASH_BIG, Streak("streak_green.tga", 10, 0.48),
			{ "pillar", "pillar_green.tga", w = 0.9, h = 1.0, t0 = 0, t1 = 1.3, env = "hold", stack = 2, grow = { 0.35, 1 } },
			{ "sprite", "wave_teal.tga", fit = true, w = 1, h = 1, t0 = 0, t1 = 0.6, env = "fade", grow = { 0.27, 1 } },
			{ "sprite", "glow_green.tga", fit = true, w = 1, h = 1, t0 = 0, t1 = 0.5, env = "flash", stack = 2 },
			{ "spray", "leaf.tga", n = 16, r0 = 0.25, r1 = 0.9, size = 0.6, t0 = 0, t1 = 0.8, env = "fade", turn = true },
			{ "rise", "leaf.tga", n = 8, height = 0.7, size = 0.5, t0 = 0.1, t1 = 1.5, env = "hold", leaf = true },
			{ "plus", "plus_green.tga", size = 0.78, t0 = 0.04, t1 = 1.2, env = "hold" },
			Border(GREEN, 1, 0, 0, 1.5),
		},
		r = {
			{ "pillar", "pillar_green.tga", w = 0.9, h = 1.0, t0 = 0, t1 = 1.9, env = "hold", stack = 2, grow = { 0.15, 1 } },
			{ "spiral", "leaf.tga", n = 10, r = 0.7, height = 0.9, turns = 1.7, size = 0.5, t0 = 0, t1 = 1.9, env = "hold" },
			{ "sprite", "glow_green.tga", fit = true, w = 1, h = 1, t0 = 0.2, t1 = 1.7, env = "pulse", a = 0.9 },
			{ "sprite", "glow_white.tga", fit = true, w = 1, h = 1, t0 = 0.9, t1 = 1.3, env = "flash", a = 0.7 },
			Border(GREEN, 1, 0, 0.2, 1.8, 0.8),
		},
		-- (a heal over time's tick: one leaf settling, a green pulse)
		t = {
			{ "settle", "leaf.tga", n = 1, from = 0.9, size = 0.5, t0 = 0, t1 = 0.7, env = "hold", leaf = true },
			{ "sprite", "glow_green.tga", fit = true, w = 0.9, h = 1, t0 = 0.1, t1 = 0.65, env = "pulse", a = 0.4 },
			Border(GREEN, 1, 0, 0, 0.7, 0.45, "pulse"),
		},
	},
	water = {
		h = {
			FLASH, Streak("streak_blue.tga", 7),
			{ "sprite", "ripple_blue.tga", fit = true, w = 1, h = 1, t0 = 0, t1 = 0.5, env = "fade", grow = { 0.31, 1 } },
			{ "sprite", "ripple_blue.tga", fit = true, w = 1, h = 1, t0 = 0.1, t1 = 0.6, env = "fade", grow = { 0.31, 1 } },
			{ "sprite", "ripple_blue.tga", fit = true, w = 1, h = 1, t0 = 0.2, t1 = 0.7, env = "fade", grow = { 0.31, 1 } },
			{ "sprite", "glow_blue.tga", fit = true, w = 1, h = 1, t0 = 0, t1 = 0.4, env = "flash" },
			{ "crown", "drop.tga", n = 12, speed = 0.9, fall = 1.1, size = 0.42, t0 = 0, t1 = 0.75, env = "fade" },
			{ "plus", "plus_blue.tga", size = 0.62, t0 = 0.04, t1 = 1.0, env = "hold" },
			Border(BLUE, 1, 0, 0, 1.3),
			{ "settle", "drop.tga", n = 4, from = 1.0, size = 0.32, t0 = 0.5, t1 = 1.3, env = "hold" },
		},
		o = {
			{ "settle", "drop.tga", n = 7, from = 1.4, size = 0.38, t0 = 0, t1 = 0.9, env = "hold" },
			{ "sprite", "ripple_blue.tga", fit = true, w = 0.95, h = 1, t0 = 0.3, t1 = 0.9, env = "fade", grow = { 0.27, 1 } },
			{ "sprite", "ripple_blue.tga", fit = true, w = 0.95, h = 1, t0 = 0.45, t1 = 1.05, env = "fade", grow = { 0.27, 1 } },
			{ "sprite", "glow_white.tga", fit = true, w = 1, h = 1, t0 = 0.38, t1 = 0.62, env = "flash", a = 0.6 },
			{ "sprite", "glow_blue.tga", fit = true, w = 1, h = 1, t0 = 0.3, t1 = 1.0, env = "pulse", a = 0.7 },
			Border(BLUE, 1, 0, 0.3, 1.25, 0.8),
		},
		s = {
			FLASH, Streak("streak_blue.tga", 6, 0.3),
			{ "sprite", "bubble.tga", fit = true, w = 1.02, h = 1.04, t0 = 0, t1 = 1.4, env = "hold", grow = { 0.92, 1 } },
			{ "sheen", "sheen.tga", t0 = 0.12, t1 = 0.72 },
			Border(BLUE, 1, 0, 0, 1.3, 0.6),
		},
		p = {
			FLASH, Streak("streak_blue.tga", 8, 0.42),
			{ "sprite", "bubble.tga", fit = true, w = 1.02, h = 1.04, t0 = 0, t1 = 1.5, env = "hold", grow = { 0.92, 1 } },
			{ "crest", "crest_blue.tga", size = 1.0, t0 = 0.02, t1 = 1.5, env = "hold", stack = 2 },
			Border(BLUE, 1, 0, 0, 1.5),
		},
		b = {
			FLASH_BIG, Streak("streak_blue.tga", 10, 0.48),
			{ "pillar", "pillar_blue.tga", w = 0.9, h = 1.0, t0 = 0, t1 = 1.3, env = "hold", stack = 2, grow = { 0.35, 1 } },
			{ "crown", "drop.tga", n = 16, speed = 1.0, fall = 1.2, size = 0.45, y = -0.2, t0 = 0.05, t1 = 1.0, env = "fade" },
			{ "sprite", "ripple_blue.tga", fit = true, w = 1, h = 1, t0 = 0, t1 = 0.6, env = "fade", grow = { 0.29, 1 } },
			{ "sprite", "ripple_blue.tga", fit = true, w = 1, h = 1, t0 = 0.12, t1 = 0.72, env = "fade", grow = { 0.29, 1 } },
			{ "sprite", "glow_blue.tga", fit = true, w = 1, h = 1, t0 = 0, t1 = 0.5, env = "flash", stack = 2 },
			{ "plus", "plus_blue.tga", size = 0.78, t0 = 0.04, t1 = 1.2, env = "hold" },
			Border(BLUE, 1, 0, 0, 1.5),
		},
		r = {
			{ "pillar", "pillar_blue.tga", w = 0.9, h = 1.0, t0 = 0, t1 = 1.9, env = "hold", stack = 2, grow = { 0.15, 1 } },
			{ "spiral", "drop.tga", n = 12, r = 0.7, height = 0.9, turns = 1.7, size = 0.45, t0 = 0, t1 = 1.9, env = "hold", upright = true },
			{ "sprite", "glow_blue.tga", fit = true, w = 1, h = 1, t0 = 0.2, t1 = 1.7, env = "pulse", a = 0.9 },
			{ "sprite", "glow_white.tga", fit = true, w = 1, h = 1, t0 = 0.9, t1 = 1.3, env = "flash", a = 0.7 },
			Border(BLUE, 1, 0, 0.2, 1.8, 0.8),
		},
		-- (a heal over time's tick: one drop falling in, a ripple)
		t = {
			{ "settle", "drop.tga", n = 1, from = 0.9, size = 0.4, t0 = 0, t1 = 0.45, env = "hold" },
			{ "sprite", "ripple_blue.tga", fit = true, w = 0.75, h = 0.85, t0 = 0.3, t1 = 0.85, env = "fade", grow = { 0.27, 1 }, a = 0.85 },
		},
	},
	quiet = {
		h = { FLASH_SOFT, Border(GOLD, 1, 0, 0, 1.0), { "plus", "plus_gold.tga", size = 0.48, t0 = 0.03, t1 = 0.9, env = "hold" } },
		o = { Border(GOLD, 1, 0, 0, 1.0, 0.65, "pulse"),
			{ "settle", "spark_gold.tga", n = 3, from = 1.0, size = 0.28, t0 = 0, t1 = 0.9, env = "hold", a = 0.8 } },
		s = { Border(GOLD, 1, 0, 0, 1.2, 0.85), Border(GOLD, 2, -4, 0.03, 1.2, 0.55) },
		p = { FLASH_SOFT, Border(GOLD, 1, 0, 0, 1.3),
			{ "crest", "crest_gold.tga", at = "tr", size = 0.5, t0 = 0.02, t1 = 1.3, env = "hold", stack = 2 } },
		b = { FLASH_SOFT, Border(GOLD, 1, 0, 0, 1.2), Border(GOLD, 2, -4, 0, 0.6, 0.7, "flash"),
			{ "plus", "plus_gold.tga", size = 0.6, t0 = 0.03, t1 = 1.0, env = "hold", stack = 2 } },
		r = { { "pillar", "pillar_gold.tga", w = 0.7, h = 1.0, t0 = 0, t1 = 1.4, env = "hold", a = 0.7, grow = { 0.3, 1 } },
			Border(GOLD, 1, 0, 0, 1.4, 0.7) },
		-- (a heal over time's tick: the border breathes)
		t = { Border(GOLD, 1, 0, 0, 0.7, 0.4, "pulse") },
	},
}

-- The tanks' tools and defensives (the user, 2026-10-09: "Last Stand, Shield
-- Wall ... Aoe Taunt ... a roar effect, repeatable pulsing red waves
-- emitting from its unitframe"; first looks, judged in the Effect Tester):
-- the same in every look. `held`: the list lasts as long as the spell
-- (S.dur, ns.SpellLasts; `fixed`: that long instead); a held part runs to the end, in and out at its edges.
local RED, STEEL = "RED_FONT_COLOR", "WHITE_FONT_COLOR"

local function Held(part)
	part.t0, part.held = part.t0 or 0, true
	return part
end

local COOLDOWNS = {
	-- the roar (Challenging Shout, Challenging Roar), after the user's reference (2026-10-09: a champion's
	-- scream, "aggressive vibrating sound waves") and their word on it: "instead of making them round and
	-- jittery, why not make them square, spawning in the middle and spreading trough the whole unitframe,
	-- like a square agressive water ripple". A red flash and streak, then fiery rectangles of the frame's
	-- shape bursting out of its middle one after another (a hot flash there as each starts), each with a
	-- fainter echo just behind it, out to a little past the frame's edge. As long as the taunt holds, the
	-- first three strongest; a ripple every 0.3 s living 0.8 s (50% faster than at first, the user).
	-- (2 s whatever the taunt's length, the user 2026-10-09: "the roar duration should be set to 2 seconds")
	W = { held = true, fixed = 2,
		{ "sprite", "glow_red.tga", fit = true, w = 1, h = 1, t0 = 0, t1 = 0.35, env = "flash", stack = 2 },
		{ "sprite", "streak_red.tga", fit = true, w = 1, h = 0.4, t0 = 0, t1 = 0.42, env = "flash", grow = { 0.54, 1 } },
		Held({ "squares", "line_fire_h.tga", alt = "line_fire_v.tga", grow = { 0.15, 1.2 }, every = 0.3, life = 0.8,
			thick = 0.42, echo = 0.72, strong = 3, soft = 0.8, core = "glow_fire.tga", stack = 2, env = "hold" }),
		Held({ "border", colour = RED, slot = 1, grow = 0, a = 0.9, env = "breathe" }),
	},
	-- a taunt (Taunt, Growl): one square ripple of the roar's, the border flashing red
	U = {
		{ "sprite", "glow_red.tga", fit = true, w = 1, h = 1, t0 = 0, t1 = 0.3, env = "flash" },
		{ "squares", "line_fire_h.tga", alt = "line_fire_v.tga", grow = { 0.15, 1.2 }, every = 9, life = 0.8,
			thick = 0.42, echo = 0.72, core = "glow_fire.tga", stack = 2, t0 = 0, t1 = 0.9, env = "hold" },
		Border(RED, 1, 0, 0, 0.9, 1, "flash"),
	},
	-- a fortify (Shield Wall, Barkskin): a white flash, a steel crest snapping over the frame, a sheen, then a
	-- steel barrier held round it, breathing, for as long as it lasts
	F = { held = true,
		{ "sprite", "glow_white.tga", fit = true, w = 1, h = 1, t0 = 0, t1 = 0.25, env = "flash", stack = 2 },
		{ "sprite", "streak_white.tga", fit = true, w = 1, h = 0.4, t0 = 0, t1 = 0.35, env = "flash" },
		{ "crest", "crest_steel.tga", size = 1.0, t0 = 0.02, t1 = 1.4, env = "hold", stack = 2 },
		{ "sheen", "sheen.tga", t0 = 0.15, t1 = 0.75 },
		Held({ "border", colour = STEEL, slot = 1, grow = 0, a = 0.85, env = "breathe" }),
		Border(STEEL, 2, -4, 0, 1.0, 0.6),
	},
	-- Last Stand (more health): a flash, a gold streak, then the frame beats like a heart, red, for as long as
	-- it lasts
	L = { held = true,
		{ "sprite", "glow_white.tga", fit = true, w = 1, h = 1, t0 = 0, t1 = 0.25, env = "flash", stack = 2 },
		{ "sprite", "streak_gold.tga", fit = true, w = 1, h = 0.4, t0 = 0, t1 = 0.35, env = "flash" },
		Held({ "sprite", "glow_red.tga", fit = true, w = 1, h = 1, env = "beat", a = 0.85 }),
		Held({ "border", colour = RED, slot = 1, grow = 0, a = 1, env = "beat" }),
	},
	-- an immunity (Divine Shield, Ice Block): a big white flash, a gold barrier on the frame's own square edge
	-- (not a rounded bubble swelling past it, the user 2026-10-09), held, breathing,
	-- a sheen passing
	I = { held = true,
		{ "sprite", "glow_white.tga", fit = true, w = 1, h = 1, t0 = 0, t1 = 0.3, env = "flash", stack = 3 },
		{ "sprite", "streak_gold.tga", fit = true, w = 1, h = 0.4, t0 = 0, t1 = 0.45, env = "flash" },
		Held({ "sprite", "bubble_gold.tga", fit = true, w = 1.02, h = 1.04, env = "breathe", grow = { 0.92, 1 } }),
		{ "sheen", "sheen.tga", t0 = 0.15, t1 = 0.75 },
		Held({ "border", colour = GOLD, slot = 1, grow = 0, a = 0.7, env = "breathe" }),
	},
	-- an evasion (Evasion, Deterrence): a quick white streak, then afterimages flickering either side of the
	-- frame for as long as it lasts
	E = { held = true,
		{ "sprite", "streak_white.tga", fit = true, w = 1, h = 0.4, t0 = 0, t1 = 0.3, env = "flash" },
		Held({ "sprite", "glow_steel.tga", fit = true, w = 1, h = 1, dx = -0.18, env = "flicker", a = 0.45 }),
		Held({ "sprite", "glow_steel.tga", fit = true, w = 1, h = 1, dx = 0.18, env = "flicker", a = 0.45, phase = 1.6 }),
		Held({ "border", colour = STEEL, slot = 1, grow = 0, a = 0.6, env = "flicker" }),
	},
}

-- on a round piece (a portrait's ring: the split of a portrait-and-bars frame, FX.Split) the round art in place
-- of the square
local ROUND_ART = { ["bubble.tga"] = "bubble_round.tga", ["bubble_gold.tga"] = "bubble_gold_round.tga" }

local LAUNCH = { holy = LaunchA, nature = LaunchB, water = LaunchW, quiet = LaunchC }
local CHARGE = { holy = ChargeA, nature = ChargeB, water = ChargeW, quiet = ChargeC }

-- the landing for a look and a kind (a group or chain heal, or one not known:
-- a heal); its length (s)
local function Landing(look, kind)
	local set = LANDINGS[look] or LANDINGS.holy
	local list = COOLDOWNS[kind] or set[kind] or set.h
	if not list.total then
		local total = 0
		for _, part in ipairs(list) do
			total = max(total, part.t1 or 0)
		end
		list.total = total
	end
	return list
end

--------------------------------------------------------------------------------
-- Drawing a landing's parts (B: the frame: x, y its centre, l b r t, w h, u)
--------------------------------------------------------------------------------

local function Shape(name, v)
	if name == "flash" then
		if v < 0.08 then
			return v / 0.08
		end
		local d = 1 - (v - 0.08) / 0.92
		return d * d
	elseif name == "hold" then
		if v < 0.12 then
			return v / 0.12
		elseif v < 0.65 then
			return 1
		end
		return 1 - (v - 0.65) / 0.35
	elseif name == "pulse" then
		return sin(math.pi * v)
	end
	return 1 - v
end

-- a heart's beat (lub-dub, a second apart) at local time lt
local function Beat(lt)
	local ph = lt % 1
	return max(math.exp(-(ph / 0.07) ^ 2), 0.75 * math.exp(-((ph - 0.22) / 0.07) ^ 2))
end

-- a part's strength at its share `v` (of `span` s, `lt` s in): a held part
-- comes in and goes at its edges; beat, breathe and flicker ride on that
local function Env(part, v, lt, span)
	local name = part.env
	local base
	if part.held then
		base = max(0, min(1, lt / 0.15, (span - lt) / 0.6))
	else
		base = Shape((name == "beat" or name == "breathe" or name == "flicker") and "hold" or name, v)
	end
	if name == "beat" then
		return base * (0.35 + 0.65 * Beat(lt))
	elseif name == "breathe" then
		return base * (0.7 + 0.3 * sin(lt * TAU / 2.4))
	elseif name == "flicker" then
		return base * (0.55 + 0.45 * sin(lt * 13 + (part.phase or 0)))
	end
	return base
end

local function Grow(part, v)
	local g = part.grow
	if not g then
		return 1
	end
	return g[1] + (g[2] - g[1]) * (1 - (1 - v) * (1 - v))
end

-- a fixed spread per index (the same picture every time)
local function R(i, k)
	local v = sin(i * 12.9898 + k * 78.233) * 43758.5453
	return v - floor(v)
end

-- a pop: in from 60% to a little over its size, then settling
local function Pop(v)
	if v < 0.12 then
		return 0.6 + 0.55 * v / 0.12
	end
	return 1.15 - 0.15 * min(1, (v - 0.12) / 0.1)
end

local DRAW = {}

function DRAW.sprite(layer, n, part, B, v, a)
	local g = Grow(part, v)
	local w = (part.fit and B.w or B.u) * part.w * g
	local h = (part.fit and B.h or B.u) * part.h * g
	local rot = part.spin and part.spin * v * TAU or 0
	local x, y = B.x + (part.dx or 0) * B.u, B.y + (part.dy or 0) * B.u
	local file = B.round and ROUND_ART[part[2]] or part[2]
	for _ = 1, part.stack or 1 do
		n = Put(layer, n, file, x, y, w, h, a, rot)
	end
	return n
end

-- square ripples sent out of the frame's middle one after another, every
-- `every` s, each growing over `life` s from `grow[1]` to `grow[2]` of the
-- frame's size and fading: four lines of up to `thick` u (`[2]` across,
-- `alt` down), an `echo` of it further in (that share of its size) at 40%; the first `strong` at full strength, the rest at `soft`;
-- `core`: a hot flash at the middle as each one starts
-- (the lines meet at the corners, none past another; thinner while the
-- ripple is small, `thick` at its full size)
local function Square(layer, n, part, B, g, a, q)
	local hw, hh = B.w / 2 * g, B.h / 2 * g
	if B.round then
		-- (on a ring: a round ripple of the same fire, its line at 0.84 of the sprite)
		for _ = 1, part.stack or 1 do
			n = Put(layer, n, "ring_fire.tga", B.x, B.y, 2 * hw / 0.84, 2 * hh / 0.84, a)
		end
		return n
	end
	local t = part.thick * B.u * (0.45 + 0.55 * q)
	for _ = 1, part.stack or 1 do
		n = Put(layer, n, part[2], B.x, B.y + hh, 2 * hw, t, a)
		n = Put(layer, n, part[2], B.x, B.y - hh, 2 * hw, t, a)
		n = Put(layer, n, part.alt, B.x - hw, B.y, t, 2 * hh, a)
		n = Put(layer, n, part.alt, B.x + hw, B.y, t, 2 * hh, a)
	end
	return n
end

function DRAW.squares(layer, n, part, B, v, a, lt)
	local every, life = part.every, part.life
	local last = floor(lt / every)
	for j = max(0, last - math.ceil(life / every)), last do
		local age = lt - j * every
		if age >= 0 and age <= life then
			local q = age / life
			local g = part.grow[1] + (part.grow[2] - part.grow[1]) * (1 - (1 - q) * (1 - q))
			local strength = (j < (part.strong or 1e9) and 1 or (part.soft or 0.5)) * a * (1 - q)
			n = Square(layer, n, part, B, g, strength, q)
			if part.echo then
				n = Square(layer, n, part, B, g * part.echo, strength * 0.4, q)
			end
			if part.core and age < 0.18 then
				n = Put(layer, n, part.core, B.x, B.y, B.u * 1.3, nil, a * (1 - age / 0.18))
			end
		end
	end
	return n
end

-- the frame's top right corner (the plus's spot); on a ring, its rim there
local function TopRight(B)
	if B.round then
		return B.x + B.w * 0.3, B.y + B.h * 0.3
	end
	return B.r - B.u * 0.3, B.t - B.u * 0.32
end

local function Corner(part, B)
	if part.at == "tr" then
		return TopRight(B)
	end
	return B.x, B.y
end

-- (the plus: always in the frame's top right corner)
function DRAW.plus(layer, n, part, B, v, a)
	local x, y = TopRight(B)
	local s = part.size * B.u * Pop(v)
	for _ = 1, part.stack or 1 do
		n = Put(layer, n, part[2], x, y, s, nil, a)
	end
	return n
end

function DRAW.crest(layer, n, part, B, v, a)
	local x, y = Corner(part, B)
	local s = part.size * B.u * Pop(v)
	for _ = 1, part.stack or 1 do
		n = Put(layer, n, part[2], x, y, s, nil, a)
	end
	return n
end

function DRAW.spray(layer, n, part, B, v, a)
	local rr = part.r0 + (part.r1 - part.r0) * (1 - (1 - v) * (1 - v))
	for i = 1, part.n do
		local ang = (i / part.n) * TAU + (R(i, 1) - 0.5) * 0.4
		local d = rr * (0.85 + 0.3 * R(i, 2))
		n = Put(layer, n, part[2], B.x + cos(ang) * d * B.w / 2, B.y + sin(ang) * d * B.h / 2,
			part.size * B.u * (0.8 + 0.4 * R(i, 3)), nil, a, part.turn and ang or 0)
	end
	return n
end

function DRAW.settle(layer, n, part, B, v, a)
	for i = 1, part.n do
		local k = max(0, min(1, v * 1.5 - R(i, 4) * 0.4))
		local x = B.l + B.w * (B.round and 0.25 + 0.5 * R(i, 1) or 0.1 + 0.8 * R(i, 1))
		local y0 = B.t - B.u * (0.05 + 0.1 * R(i, 2))   -- (from the frame's top, inside it)
		local y1 = B.b + B.h * (0.25 + 0.6 * R(i, 3))
		local y = y0 + (y1 - y0) * (1 - (1 - k) * (1 - k))
		n = Put(layer, n, part[2], x, y, part.size * B.u, nil, k > 0 and a or 0,
			part.leaf and (-1.6 + 0.5 * sin(v * 6 + i)) or 0)
	end
	return n
end

function DRAW.rise(layer, n, part, B, v, a)
	for i = 1, part.n do
		local x = B.l + B.w * (B.round and 0.25 + 0.5 * R(i, 1) or 0.1 + 0.8 * R(i, 1)) + sin(v * 5 + i) * B.u * 0.15
		local y = B.b + B.u * 0.15 + v * part.height * B.u * (0.6 + 0.4 * R(i, 2))   -- (up through the frame)
		n = Put(layer, n, part[2], x, y, part.size * B.u * (0.8 + 0.4 * R(i, 3)), nil, a,
			part.leaf and (-1.3 + 0.4 * sin(v * 5 + i)) or 0)
	end
	return n
end

-- a crown of droplets thrown up and out (from the frame's middle, or `y` u
-- above it), falling back, each pointing the way it moves
function DRAW.crown(layer, n, part, B, v, a)
	local atan2 = math.atan2
	for i = 1, part.n do
		local ang = math.pi / 2 + ((i - 1) / max(1, part.n - 1) - 0.5) * (part.spread or 2.4)
		local speed = part.speed * B.u * (0.7 + 0.5 * R(i, 1))
		local fall = part.fall * B.u
		local x = B.x + cos(ang) * speed * v
		local y = B.y + (part.y or 0) * B.u + sin(ang) * speed * v - fall * v * v
		local rot = atan2(sin(ang) * speed - 2 * fall * v, cos(ang) * speed) - math.pi / 2
		n = Put(layer, n, part[2], x, y, part.size * B.u * (0.8 + 0.4 * R(i, 2)), nil, a, rot)
	end
	return n
end

function DRAW.orbit(layer, n, part, B, v, a)
	for i = 1, part.n do
		local ang = i / part.n * TAU + v * part.spin
		n = Put(layer, n, part[2], B.x + cos(ang) * part.rx * B.w / 2, B.y + sin(ang) * part.ry * B.h / 2,
			part.size * B.u, nil, a, ang + math.pi / 2)
	end
	return n
end

function DRAW.spiral(layer, n, part, B, v, a)
	for i = 1, part.n do
		local k = max(0, min(1, v * 1.25 - (i - 1) / part.n * 0.5))
		if k > 0 then
			local ang = k * part.turns * TAU + i
			n = Put(layer, n, part[2], B.x + cos(ang) * part.r * B.u, B.b + k * part.height * B.u, part.size * B.u, nil,
				a * sin(math.pi * k), part.upright and 0 or ang + 1.2)
		end
	end
	return n
end

function DRAW.runes(layer, n, part, B, v, a)
	local m = part.m * B.u
	local l, b, r, t = B.l - m, B.b - m, B.r + m, B.t + m
	local w, h = r - l, t - b
	local rad = B.w / 2 + m   -- (on a ring: round it)
	local per = B.round and TAU * rad or 2 * (w + h)
	local count = max(8, floor(per / (B.u * 0.24)))
	for i = 0, count - 1 do
		local d = i / count * per
		local x, y
		if B.round then
			x, y = B.x + cos(d / rad) * rad, B.y + sin(d / rad) * rad
		elseif d < w then
			x, y = l + d, t
		elseif d < w + h then
			x, y = r, t - (d - w)
		elseif d < 2 * w + h then
			x, y = r - (d - w - h), b
		else
			x, y = l, b + (d - 2 * w - h)
		end
		local twinkle = 0.6 + 0.4 * sin(i * 1.7 + v * 9)
		if i % 3 == 0 then
			n = Put(layer, n, part[2], x, y, part.size * B.u, nil, a * twinkle)
		else
			n = Put(layer, n, "glow_gold.tga", x, y, part.size * B.u * 0.5, nil, a * twinkle * 0.8)
		end
	end
	return n
end

function DRAW.corners(layer, n, part, B, v, a)
	local m = part.m * B.u
	local s = part.size * B.u
	local rot = v * math.pi
	if B.round then
		local rad = B.w * 0.36
		for k = 0, 3 do
			local ang = TAU * (k / 4 + 0.125)
			n = Put(layer, n, part[2], B.x + cos(ang) * rad, B.y + sin(ang) * rad, s, nil, a, rot)
		end
		return n
	end
	n = Put(layer, n, part[2], B.l - m, B.t + m, s, nil, a, rot)
	n = Put(layer, n, part[2], B.r + m, B.t + m, s, nil, a, rot)
	n = Put(layer, n, part[2], B.l - m, B.b - m, s, nil, a, rot)
	return Put(layer, n, part[2], B.r + m, B.b - m, s, nil, a, rot)
end

function DRAW.pillar(layer, n, part, B, v, a)
	local w = part.w * B.u
	local h = part.h * B.u * Grow(part, v)
	local foot = B.b
	for _ = 1, part.stack or 1 do
		n = Put(layer, n, part[2], B.x, foot + h / 2, w, h, a)
	end
	return n
end

-- A landing's own frame, laid on the target frame's rect and clipping what
-- it holds: every effect on a frame stays inside it, whatever it is (the
-- user, 2026-10-09: "growing outside of their unitframe, which will colide
-- with other party memebers frames" ... "pull them inside the frame too"),
-- give or take 10% past each side ("the effects can go like 10% outside of
-- their unitframe, looks better that way").
-- A landing's sprites are its children (their own pool); the sheen's too.
-- A split frame's square half has no margin on its ring side (B.cut): its
-- bars start under the ring, which is drawn over it (Cover).
local MARGIN = 0.1   -- of the frame's width / height, past each of its sides

local function Inside(layer, B)
	local c = clips[layer]
	if not c then
		local f = CreateFrame("Frame", nil, layer)
		f:SetClipsChildren(true)
		local t = f:CreateTexture(nil, "OVERLAY", nil, 7)
		t:SetBlendMode("ADD")
		t:SetTexture(MEDIA .. "sheen.tga")
		sprites[f] = {}
		c = { frame = f, tex = t }
		clips[layer] = c
	end
	local f = c.frame
	local mx, my = B.w * MARGIN, B.h * MARGIN
	f:ClearAllPoints()
	f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", B.l - (B.cut and 0 or mx), B.b - my)
	f:SetSize(max(1, B.w + mx * (B.cut and 1 or 2)), max(1, B.h + 2 * my))
	f:Show()
	return f
end

-- the sheen: a band of light passing across the frame, inside it
local function Sheen(layer, part, B, v, a)
	local c = clips[layer]
	local f = c.frame
	local t = c.tex
	t:Show()
	t:SetSize(B.u * 1.3, B.h * 1.7)
	t:ClearAllPoints()
	t:SetPoint("CENTER", f, "LEFT", (B.cut and 0 or B.w * MARGIN) - B.u * 0.6 + (B.w + B.u * 1.2) * v, 0)
	t:SetAlpha(max(0, min(1, a)))
end

-- the kit's outline glow round the frame, as light (the debuff glow's system,
-- Kit:GlowNine), `grow` units outside it (0: on the frame's edge; below 0:
-- inside it -- every effect stays inside the frame); two per layer (a shield's double
-- barrier), laid on the frame's rect (never anchored to the game's frame).
-- A ring's border is drawn with its sprites instead (DRAW.halo: clipped with
-- them, round a badge too)
local function Flare(layer, slot, B, grow, colour)
	local Kit = MelloUI.Kit   -- (looked up here: the core loads the kit after this file)
	local set = flares[layer]
	if not set then
		set = {}
		flares[layer] = set
	end
	local f = set[slot]
	if not f then
		local holder = CreateFrame("Frame", nil, layer)
		f = { holder = holder }
		if Kit and Kit.GlowNine then
			f.nine = Kit:GlowNine(holder, holder, "window/single", { scale = (Kit.scale or 1) * 0.8, alpha = 1 })
		end
		set[slot] = f
	end
	local h = f.holder
	h:ClearAllPoints()
	h:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", B.l - grow, B.b - grow)
	h:SetSize(max(1, B.w + 2 * grow), max(1, B.h + 2 * grow))
	h:SetAlpha(0)
	h:Show()
	if f.nine and Kit.GlowShow then
		local r, g, b = Rgb(colour)
		Kit:GlowShow(f.nine, r, g, b, 1)
	end
end

local function FlareAlpha(layer, slot, a)
	local set = flares[layer]
	local f = set and set[slot]
	if f then
		f.holder:SetAlpha(max(0, min(1, a)))
	end
end

-- a ring's border: a round halo on its rim in the border's colour (its line at
-- HALO_LINE of the sprite)
local HALO_LINE = 0.8

function DRAW.halo(layer, n, part, B, v, a)
	local size = max(1, B.w + 2 * (part.grow or 0)) / HALO_LINE
	return Put(layer, n, "halo_white.tga", B.x, B.y, size, size, a, 0, RgbOf(part.colour))
end

-- (a ring's unit: its parts sized as on a frame of about that height -- a plus,
-- a crest inside the ring)
local ROUND_U = 0.7

local function Box(S)
	local B = S.B
	if not B then
		B = {}
		S.B = B
	end
	B.l, B.b, B.r, B.t = S.fl, S.fb, S.fr, S.ft
	B.w, B.h = S.fr - S.fl, S.ft - S.fb
	B.x, B.y = (S.fl + S.fr) / 2, (S.fb + S.ft) / 2
	B.round, B.bars, B.cut = S.round and true or false, S.bars and true or false, S.cut and true or false
	B.u = B.round and B.h * ROUND_U or B.h
	return B
end

-- What stands over the light on a split frame (the user, 2026-10-09: "dont
-- cut anything, just place the effect under" -- the square half under the
-- portrait's ring, the ring half under the level badge). The kit lays the ring
-- UNDER the bars, so no frame level is under the ring yet over them: their own
-- pixels are drawn once more over the light instead, on the layer's cover (as
-- UnitFramePanel's RingCover draws the ring over the bars' ends). A copy of
-- each region: its texture or atlas, coords, colour, blend and alpha, on its
-- rect; the badge's number its font, text and colour. Laid as a landing
-- starts. (UnitFramePanel:CoverOf names the regions.)
local function NoneSecret(a, b, c, d, e, f, g, h)
	return not (Secret(a) or Secret(b) or Secret(c) or Secret(d) or Secret(e) or Secret(f) or Secret(g) or Secret(h))
end

-- a region's alpha as it shows: its own times its frame's
local function ShownAlpha(src)
	local okA, a = pcall(src.GetAlpha, src)
	a = okA and Num(a) or 1
	local okP, parent = pcall(src.GetParent, src)
	if okP and type(parent) == "table" and parent.GetEffectiveAlpha then
		local okE, e = pcall(parent.GetEffectiveAlpha, parent)
		a = a * ((okE and Num(e)) or 1)
	end
	return a
end

local function Place(dst, l, b, r, t, a)
	dst:ClearAllPoints()
	dst:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
	dst:SetSize(max(1, r - l), max(1, t - b))
	dst:SetAlpha(max(0, min(1, a)))
	dst:Show()
end

local function CopyTexture(dst, src)
	if not (src and FX.Visible(src)) then
		return
	end
	local l, b, r, t = FX.Rect(src)
	if not l then
		return
	end
	local okA, atlas = pcall(src.GetAtlas, src)
	if okA and not Secret(atlas) and type(atlas) == "string" and atlas ~= "" then
		dst:SetAtlas(atlas)
	else
		local okT, file = pcall(src.GetTexture, src)
		if not okT or Secret(file) or file == nil then
			return
		end
		dst:SetTexture(file)
		local okC, c1, c2, c3, c4, c5, c6, c7, c8 = pcall(src.GetTexCoord, src)
		if okC and c8 ~= nil and NoneSecret(c1, c2, c3, c4, c5, c6, c7, c8) then
			dst:SetTexCoord(c1, c2, c3, c4, c5, c6, c7, c8)
		else
			dst:SetTexCoord(0, 1, 0, 1)
		end
	end
	local okV, cr, cg, cb, ca = pcall(src.GetVertexColor, src)
	if okV and cr ~= nil and NoneSecret(cr, cg, cb, ca) then
		dst:SetVertexColor(cr, cg, cb, ca or 1)
	else
		dst:SetVertexColor(1, 1, 1, 1)
	end
	local okB, blend = pcall(src.GetBlendMode, src)
	dst:SetBlendMode((okB and not Secret(blend) and type(blend) == "string") and blend or "BLEND")
	local okD, des = pcall(src.IsDesaturated, src)
	dst:SetDesaturated(okD and not Secret(des) and des == true)
	Place(dst, l, b, r, t, ShownAlpha(src))
end

local function CopyText(dst, src)
	if not (src and FX.Visible(src)) then
		return
	end
	local l, b, r, t = FX.Rect(src)
	local okF, font, size, flags = pcall(src.GetFont, src)
	if not (l and okF) or Secret(font) or type(font) ~= "string" then
		return
	end
	dst:SetFont(font, Num(size) or 12, (not Secret(flags) and type(flags) == "string") and flags or "")
	local okT, text = pcall(src.GetText, src)
	-- (the number as the game has it, a secret one too: only handed on)
	pcall(dst.SetText, dst, okT and text or "")
	local okC, cr, cg, cb = pcall(src.GetTextColor, src)
	if okC and cr ~= nil and NoneSecret(cr, cg, cb) then
		dst:SetTextColor(cr, cg, cb)
	else
		dst:SetTextColor(1, 1, 1)
	end
	local okS, sx, sy = pcall(src.GetShadowOffset, src)
	if okS and sx ~= nil and NoneSecret(sx, sy) then
		dst:SetShadowOffset(sx, sy)
	end
	local okH, jh = pcall(src.GetJustifyH, src)
	if okH and not Secret(jh) and type(jh) == "string" then
		dst:SetJustifyH(jh)
	end
	Place(dst, l, b, r, t, ShownAlpha(src))
end

local COVER_PARTS = { "ring", "orb", "disc" }   -- (S's regions, drawn in this order; the number over them)

local function LayCover(layer, S)
	local cv = covers[layer]
	if cv then
		for _, t in ipairs(cv.tex) do
			t:Hide()
		end
		cv.text:Hide()
		cv.frame:Hide()
	end
	if not (S.ring or S.orb or S.disc or S.number) then
		return
	end
	if not cv then
		local f = CreateFrame("Frame", nil, layer)
		cv = { frame = f, tex = {} }
		for i = 1, #COVER_PARTS do
			cv.tex[i] = f:CreateTexture(nil, "ARTWORK", nil, i - 1)
		end
		cv.text = f:CreateFontString(nil, "OVERLAY")
		covers[layer] = cv
	end
	for i, key in ipairs(COVER_PARTS) do
		CopyTexture(cv.tex[i], S[key])
	end
	CopyText(cv.text, S.number)
	cv.frame:Show()
end

-- the layer's frames stacked: a split's ring half over its square half and
-- that one's ring copy; each layer's light under its own cover
local function Stack(layer, S)
	local base = FX.Host():GetFrameLevel() + (S.round and 20 or 2)
	layer:SetFrameLevel(base)
	local c = clips[layer]
	if c then
		c.frame:SetFrameLevel(base + 1)
	end
	local set = flares[layer]
	if set then
		for _, f in pairs(set) do
			f.holder:SetFrameLevel(base + 1)
		end
	end
	local cv = covers[layer]
	if cv then
		cv.frame:SetFrameLevel(base + 6)
	end
end

--------------------------------------------------------------------------------
-- The stages, one after another on a layer (shared steps and ends: nothing
-- made per cast)
--------------------------------------------------------------------------------

local function Clear(layer)
	HideFrom(layer, 1)
	FlareAlpha(layer, 1, 0)
	FlareAlpha(layer, 2, 0)
	local c = clips[layer]
	if c then
		HideFrom(c.frame, 1)
		c.tex:Hide()
		c.frame:Hide()
	end
	local cv = covers[layer]
	if cv then
		cv.frame:Hide()
	end
	local S = state[layer]
	if S then
		S.stage, S.mate, S.owner = nil, nil, nil
	end
	layer:Hide()
end

local function LandStep(layer, p)
	local S = state[layer]
	local list = S and S.landing
	if not list then
		return
	end
	local B = S.B
	local total = S.total or list.total
	local t = p * total
	local n = 1
	local sheen = false
	local c = clips[layer]   -- (Inside: made by Arrive)
	local host = c.frame
	for _, part in ipairs(list) do
		local kind = part[1]
		local t1 = part.held and (total - (part.tail or 0)) or part.t1
		if t >= part.t0 and t <= t1 then
			local span = max(0.001, t1 - part.t0)
			local lt = t - part.t0
			local v = lt / span
			local a = Env(part, v, lt, span) * (part.a or 1)
			if kind == "border" and not B.round then
				FlareAlpha(layer, part.slot, a)
			elseif kind == "sheen" then
				if not B.round then
					Sheen(layer, part, B, v, a)
					sheen = true
				end
			elseif not (B.bars and (kind == "plus" or kind == "crest")) then
				-- (a split frame's plus and crest: on its ring only, not twice; a
				-- ring's border its halo)
				n = DRAW[kind == "border" and "halo" or kind](host, n, part, B, v, a, lt)
			end
		elseif kind == "border" and t > t1 then
			FlareAlpha(layer, part.slot, 0)
		end
	end
	if not sheen then
		c.tex:Hide()
	end
	HideFrom(host, n)
end

local Arrive

-- a split frame's ring half: a free layer of the pool playing the same landing
-- on the ring's square, round, under the level badge (none when the pool hands
-- this one back)
local function Mate(layer, S, sp)
	local mate = FX.FreeLayer()
	if mate == layer then
		return
	end
	if not FX.Free(mate) then
		FX.Clear(mate)
	end
	local M = state[mate]
	M.fl, M.fb, M.fr, M.ft = sp.rl, sp.rb, sp.rr, sp.rt
	M.ring, M.orb, M.disc, M.number = nil, sp.orb, sp.disc, sp.number
	M.frame, M.Rect, M.unit = nil, nil, S.unit
	M.round, M.bars, M.cut, M.owner, M.mate = true, false, false, layer, nil
	M.look, M.kind, M.quiet, M.dur, M.stage = S.look, S.kind, S.quiet, S.dur, "strike"
	S.mate = mate
	Anim:Stop(mate, "alpha")
	mate:SetAlpha(1)
	mate:Show()
	Arrive(mate)
end

-- the landing: the frame's rect read again (it may have moved while the light
-- flew), its border glows made ready, the timeline played; a portrait-and-bars
-- frame's split (FX.Split): this layer on its name and bars, a mate on its ring
function Arrive(layer)
	local S = state[layer]
	if not S or (S.stage ~= "launch" and S.stage ~= "strike") then
		return
	end
	if S.frame and S.Rect then
		local l, b, r, t = S.Rect(S.frame)
		if l then
			S.fl, S.fb, S.fr, S.ft = l, b, r, t
		end
	end
	if S.frame and not S.round then
		local sp = FX.Split(S.frame)
		S.bars, S.cut = sp and true or false, sp and true or false
		if sp then
			S.fl, S.fb, S.fr, S.ft = sp.bl, sp.bb, sp.br, sp.bt
			-- (the ring over it, and the badge that stands on the ring over that)
			S.ring, S.orb, S.disc, S.number = sp.ring, sp.orb, sp.disc, sp.number
			Mate(layer, S, sp)
		end
	end
	if not S.fl then
		Clear(layer)
		return
	end
	S.stage = "land"
	local B = Box(S)
	local list = Landing(S.quiet and "quiet" or S.look, S.kind)
	S.landing = list
	-- (a held list as long as the spell lasts, unless it has a `fixed` length of its own)
	S.total = list.held and (list.fixed or S.dur or 6) or list.total
	for _, part in ipairs(list) do
		if part[1] == "border" and not B.round then
			Flare(layer, part.slot, B, part.grow, part.colour)
		end
	end
	HideFrom(layer, 1)
	HideFrom(Inside(layer, B), 1)
	clips[layer].tex:Hide()
	LayCover(layer, S)
	Stack(layer, S)
	Anim:Drive(layer, LandStep, S.total, "linear", Clear)
	FX.Also(layer, S)
end

local function LaunchStep(layer, p)
	local S = state[layer]
	if S then
		(LAUNCH[S.look] or LaunchA)(layer, S, p)
	end
end

local function ChargeStep(layer)
	local S = state[layer]
	if S and S.look then
		(CHARGE[S.look] or ChargeA)(layer, S)
	end
end

local function ChargeEnd(layer)
	local S = state[layer]
	if S and S.stage == "charge" then
		FX.Stop(layer)
	end
end

-- the charge fading away (the cast ended or failed)
local function Faded(layer)
	HideFrom(layer, 1)
	layer:Hide()
	layer:SetAlpha(1)
end

--------------------------------------------------------------------------------
-- What the module calls
--------------------------------------------------------------------------------

function FX.Layer(host)
	local layer = CreateFrame("Frame", nil, host)
	layer:SetAllPoints(UIParent)
	layer:Hide()
	sprites[layer] = {}
	state[layer] = {}
	return layer
end

local function Begin(layer)
	Anim:Stop(layer, "alpha")
	layer:SetAlpha(1)
	layer:Show()
end

-- the charge on the cast bar, until Stop (or its longest time)
function FX.Charge(layer, look)
	local S = state[layer]
	S.look, S.stage = look, "charge"
	Begin(layer)
	Anim:Drive(layer, ChargeStep, (S.castTime or 1.5) + TIME.chargeMax, "linear", ChargeEnd)
end

function FX.Stop(layer)
	local S = state[layer]
	if not (S and S.stage == "charge") then
		return
	end
	S.stage = nil
	Anim:Stop(layer, "drive")
	Anim:To(layer, "alpha", 0, TIME.chargeFade, "inQuad", Faded)
end

-- the flight (S's path and frame set by the caller), then the kind's landing;
-- a hop (Chain Heal's) is shorter and starts without the release flash
function FX.Land(layer, look, kind, quiet, hop)
	local S = state[layer]
	S.look, S.kind, S.quiet, S.hop, S.stage = look, kind, quiet, hop and true or false, "launch"
	S.round, S.bars, S.cut, S.mate, S.owner, S.also = nil, nil, nil, nil, nil, nil
	S.ring, S.orb, S.disc, S.number = nil, nil, nil, nil
	-- (a portrait-and-bars frame's: to its portrait)
	local sp = FX.Split(S.frame)
	if sp then
		S.x1, S.y1 = (sp.rl + sp.rr) / 2, (sp.rb + sp.rt) / 2
	end
	FX.Bend(S, hop and 0.2 or 0.3)
	Begin(layer)
	Anim:Drive(layer, LaunchStep, hop and TIME.hop or TIME.launch, "inOutQuad", Arrive)
end

-- the kind's landing at once (an instant: no flight); `dur`: how long a
-- lasting one (a tank's tool, a defensive) stays; `also`: the copy on your
-- player frame (FX.Also)
function FX.Strike(layer, look, kind, quiet, dur, also)
	local S = state[layer]
	S.look, S.kind, S.quiet, S.stage, S.dur = look, kind, quiet, "strike", dur
	S.round, S.bars, S.cut, S.mate, S.owner, S.also = nil, nil, nil, nil, nil, also
	S.ring, S.orb, S.disc, S.number = nil, nil, nil, nil
	Begin(layer)
	Arrive(layer)
end

-- a layer emptied at once, whatever it played
function FX.Clear(layer)
	local S = state[layer]
	local mate = S and S.mate
	Anim:Stop(layer, "drive")
	Clear(layer)
	if mate and state[mate] and state[mate].owner == layer then
		Anim:Stop(mate, "drive")
		Clear(mate)
	end
end

-- whether a layer is free (nothing playing on it)
function FX.Free(layer)
	local S = state[layer]
	return not (S and S.stage)
end


--------------------------------------------------------------------------------
-- The frames: whose unit, which frame shows a unit, where it is (the same for
-- every feature that plays on a frame)
--------------------------------------------------------------------------------

local OWN_HEADERS = { "MelloUIGroupPartyHeader", "MelloUIGroupRaidHeader" }

-- a yes or no: true, false, or nil (secret, an error, no such call)
function FX.Ask(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, v = pcall(fn, ...)
	if not ok or Secret(v) then
		return nil
	end
	return v and true or false
end
local Ask = FX.Ask

local function Visible(f)
	local ok, v = pcall(f.IsVisible, f)
	return ok and not Secret(v) and v == true
end
FX.Visible = Visible

-- a region's rect in UIParent's units, or nil when not plain
function FX.Rect(region)
	local l, b, r, t = ScreenRect(region)
	if not l then
		return nil
	end
	local s = UIParent:GetEffectiveScale()
	return l / s, b / s, r / s, t / s
end

-- the same unit as the frames show it: you in a raid are your raid unit
function FX.Canon(unit)
	if unit == "player" and Ask(IsInRaid) then
		local ok, i = pcall(UnitInRaid, "player")
		i = ok and Num(i) or nil
		if i then
			return "raid" .. i
		end
	end
	return unit
end

-- your group's units now (you alone while solo); in a raid "player" too
local members, memberSet = {}, {}
function FX.Members()
	wipe(members)
	wipe(memberSet)
	if Ask(IsInRaid) then
		local ok, count = pcall(GetNumGroupMembers)
		count = ok and Num(count) or 0
		for i = 1, math.min(count, 40) do
			members[#members + 1] = "raid" .. i
		end
		memberSet.player = true
	else
		members[1] = "player"
		for i = 1, 4 do
			local unit = "party" .. i
			if Ask(UnitExists, unit) then
				members[#members + 1] = unit
			end
		end
	end
	for _, unit in ipairs(members) do
		memberSet[unit] = true
	end
	return members, memberSet
end

-- the unit a frame shows: its secure "unit" attribute, else its unit field
function FX.FrameUnit(f)
	if type(f) ~= "table" then
		return nil
	end
	local unit
	if f.GetAttribute then
		local ok, v = pcall(f.GetAttribute, f, "unit")
		unit = ok and Text(v) or nil
	end
	return unit or Text(rawget(f, "unit"))
end
local FrameUnit = FX.FrameUnit

-- shown and not faded away (the game's frames while Group Frames shows: alpha 0)
local function Seen(f)
	if not Visible(f) then
		return false
	end
	local ok, a = pcall(f.GetEffectiveAlpha, f)
	a = ok and Num(a)
	return not a or a > 0.05
end

local function Shows(f, unit)
	return type(f) == "table" and FrameUnit(f) == unit and Seen(f)
end

-- the unit's frame on the screen: MelloUI's Group Frames first (every frame
-- that shows a member now -- its buttons, or the game's party members while
-- those are the choice for a party: MelloUI.GroupFrames:HostOf), then, with
-- Group Frames off, its secure headers' buttons and the game's party, raid and
-- player frames
function FX.FrameOf(unit)
	local GF = MelloUI.GroupFrames
	if GF and GF.HostOf then
		local ok, e = pcall(GF.HostOf, GF, unit)
		if ok and type(e) == "table" and type(e.frame) == "table" then
			return e.frame
		end
	end
	for _, name in ipairs(OWN_HEADERS) do
		local h = rawget(_G, name)
		if type(h) == "table" then
			for i = 1, 41 do
				local b = rawget(h, i)
				if b == nil and h.GetAttribute then
					local ok, v = pcall(h.GetAttribute, h, "child" .. i)
					b = ok and v or nil
				end
				if type(b) ~= "table" then
					break
				end
				if rawget(b, "unit") == unit and Visible(b) then
					return b
				end
			end
		end
	end
	for i = 1, 5 do
		local f = rawget(_G, "CompactPartyFrameMember" .. i)
		if Shows(f, unit) then
			return f
		end
	end
	for i = 1, 40 do
		local f = rawget(_G, "CompactRaidFrame" .. i)
		if Shows(f, unit) then
			return f
		end
	end
	for g = 1, 8 do
		for i = 1, 5 do
			local f = rawget(_G, "CompactRaidGroup" .. g .. "Member" .. i)
			if Shows(f, unit) then
				return f
			end
		end
	end
	local pf = rawget(_G, "PartyFrame")
	if type(pf) == "table" and pf.PartyMemberFramePool then
		for f in pf.PartyMemberFramePool:EnumerateActive() do
			if Shows(f, unit) then
				return f
			end
		end
	end
	local player = rawget(_G, "PlayerFrame")
	if unit == "player" and type(player) == "table" and Seen(player) then
		return player
	end
	return nil
end

-- A portrait-and-bars frame (the player's, a party member's of the game's;
-- UnitFramePanel:PartsOf, the kit's look on or off): its effects split, a
-- round form on the portrait's ring and the square one on its bars (the user,
-- 2026-10-09, C of the sketch; the bars only, the name clear: their drawing).
-- The ring: the kit's (its rim, Kit:RingRim) while the unit frames wear the
-- kit, else the game's ring round the portrait; the bars: the health and mana
-- bars' rects together, BAR_PAD past them but on the ring's side (they start
-- under the ring). What stands over the light (UnitFramePanel:CoverOf): the
-- ring over the square half, the level badge over the ring half. -> one table,
-- reused (read it at once): the ring's square rl, rb, rr, rt; the bars' bl,
-- bb, br, bt; the ring to draw over them, the badge's orb, disc and number;
-- nil for any other frame (the whole frame then)
local RING_GROW = 1.34   -- the game's ring round a portrait, of its width
local BAR_PAD = 3        -- UI units past the bars

local function Union(l, b, r, t, region)
	if region and Visible(region) then
		local l2, b2, r2, t2 = FX.Rect(region)
		if l2 then
			return min(l, l2), min(b, b2), max(r, r2), max(t, t2)
		end
	end
	return l, b, r, t
end

local split = {}

function FX.Split(frame)
	if type(frame) ~= "table" then
		return nil
	end
	local panel = MelloUI:GetModule("UnitFramePanel")
	if not (panel and panel.PartsOf) then
		return nil
	end
	local portrait, health, mana, _, circle, number = panel:PartsOf(frame)
	local pl, pb, pr, pt
	if portrait then
		pl, pb, pr, pt = FX.Rect(portrait)
	end
	local bl, bb, br, bt
	if health then
		bl, bb, br, bt = FX.Rect(health)
	end
	if not (pl and bl) then
		return nil
	end
	local cx, cy, d = (pl + pr) / 2, (pb + pt) / 2, (pr - pl) * RING_GROW
	local ring = panel.RingOf and panel:RingOf(portrait)
	local Kit = MelloUI.Kit
	if ring and Kit and Kit.RingRim then
		local l, b, r, t = FX.Rect(ring)
		if l then
			cx, cy, d = (l + r) / 2, (b + t) / 2, (r - l) * Kit:RingRim(ring)
		end
	end
	bl, bb, br, bt = Union(bl, bb, br, bt, mana)
	split.rl, split.rb, split.rr, split.rt = cx - d / 2, cy - d / 2, cx + d / 2, cy + d / 2
	split.bl, split.bb, split.br, split.bt = bl, bb - BAR_PAD, br + BAR_PAD, bt + BAR_PAD
	split.ring, split.orb, split.disc, split.number = nil, nil, nil, nil
	if panel.CoverOf then
		split.ring, split.orb, split.disc, split.number = panel:CoverOf(frame, portrait, circle, number)
	end
	return split
end

-- Every frame of yours shows what lands on you (the user, 2026-10-09: "why
-- did you now exclude my own player unitframe?" -- the solo party frame,
-- Group Frames' answer for you, had taken them from it): a landing on you
-- plays on your player frame too, at once, when it shows and was not the
-- frame played on (split as a portrait-and-bars frame)
function FX.Also(layer, S)
	if S.also or S.round or not S.frame or S.unit ~= FX.Canon("player") then
		return
	end
	local pf = rawget(_G, "PlayerFrame")
	if type(pf) ~= "table" or pf == S.frame or not Seen(pf) then
		return
	end
	local l, b, r, t = FX.Rect(pf)
	local other = l and FX.FreeLayer()
	if not other or other == layer then
		return
	end
	if not FX.Free(other) then
		FX.Clear(other)
	end
	local O = state[other]
	O.fl, O.fb, O.fr, O.ft = l, b, r, t
	O.frame, O.Rect, O.unit = pf, FX.Rect, S.unit
	FX.Strike(other, S.look, S.kind, S.quiet, S.dur, true)
end

--------------------------------------------------------------------------------
-- The host and its layers (one pool for every feature)
--------------------------------------------------------------------------------

local LAYERS_MAX = 12     -- effects at once (a group heal's five, the next while they fade)
local host
local layers, oldest = {}, 0

function FX.Host()
	if not host then
		host = CreateFrame("Frame", nil, UIParent)
		host:SetAllPoints(UIParent)
		host:SetFrameStrata("HIGH")
		host:EnableMouse(false)
	end
	return host
end

-- a layer with nothing on it: made on first need (LAYERS_MAX at most; past
-- that, the one taken longest ago)
function FX.FreeLayer()
	for _, layer in ipairs(layers) do
		if FX.Free(layer) then
			return layer
		end
	end
	if #layers < LAYERS_MAX then
		local layer = FX.Layer(FX.Host())
		layers[#layers + 1] = layer
		return layer
	end
	oldest = oldest % LAYERS_MAX + 1
	return layers[oldest]
end

-- every layer emptied at once (a feature switched off)
function FX.ClearAll()
	for _, layer in ipairs(layers) do
		FX.Clear(layer)
	end
end

-- a kind's landing on the unit's frame, at once, as long as `dur` (a lasting
-- one's); the layer, or nil when no frame of the unit's is shown
function FX.Show(unit, kind, look, quiet, dur)
	local frame = FX.FrameOf(unit)
	local l, b, r, t
	if frame then
		l, b, r, t = FX.Rect(frame)
	end
	if not l then
		return nil
	end
	local layer = FX.FreeLayer()
	local S = FX.state[layer]
	S.fl, S.fb, S.fr, S.ft = l, b, r, t
	S.frame, S.Rect, S.unit = frame, FX.Rect, unit
	FX.Strike(layer, look or "holy", kind, quiet, dur)
	return layer
end

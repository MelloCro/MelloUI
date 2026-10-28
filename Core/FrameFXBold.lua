--------------------------------------------------------------------------------
-- MelloUI - Frame Effects' bold landings (1.2.4; MelloUI.FrameFX.Bold)
--
-- The user, 2026-10-26, after the pixel set made for their retail copy: "i want now in the MelloUI forever version to
-- adapt the same mindset when updating the existing animations for them, the wow forever animations will need to be
-- updated for the modern look ... make sure that the spells really are in forever version"; then, of the first
-- sketch, "I said to not reuse the same animation on the portrait and the health bars, and the animations should like
-- it is on the retail version, across the whole unitframe border, that means also on the top border where the name
-- is"; and of MelloUI-BuildData/output/forever_fx_sketch (every kind: today beside two takes): "A versions of
-- everything, they look good".
-- Every heal and cooldown kind lands as a moment -- a wind-up, an impact past the frame's size, pieces flung past its
-- left and right sides, a follow-through -- in the modern look's light (Media/FrameFX/Light; the new pieces from the
-- ChatGPT sheet fx11_bold, Tools/make_icons.py). A landing's bold parts (`bold`) play here on the WHOLE frame -- its
-- ring and its plate (FX.Split: the plate's gold rim round the name and the bars) together -- on two frames of the
-- landing's layer: one over everything, one under the unit's frame (the wings behind it: the strata below its). In a
-- raid they stay inside each cell; a party's reach past the frame's sides. The portrait and the plate never play the
-- same motion: the ring the sign and the gathering light, the plate the sweep, the sparks off its ends and its border.
-- Their border (the plate's rim and the ring's halo) is the engine's own part. Sizes are the sketch's pixels, scaled
-- to the frame (the sketch's ring is RING_PX across). The Quiet look keeps its own landings (FX.Landing).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Safe = MelloUI.Safe
local Text, Num = Safe.Text, Safe.Number
local FX = MelloUI.FrameFX

local cos, sin, min, max, floor, abs, sqrt = math.cos, math.sin, math.min, math.max, math.floor, math.abs, math.sqrt
local PI, TAU = math.pi, 2 * math.pi
local RING_PX = 45     -- the sketch's ring across (its pixels to the frame's units)
local PAD = 3          -- the barrier past the frame's outline (sketch px)
local WAVE_MAX = 4     -- a group heal's wave: steps at most
local RING_LINE = 0.86 -- the barrier's round piece: its line at this share of its half (Tools/make_icons.py FX_RING_LINE)
local WHITE8 = "Interface\\Buttons\\WHITE8X8"
local STRATA_BELOW = { LOW = "BACKGROUND", MEDIUM = "LOW", HIGH = "MEDIUM", DIALOG = "HIGH" }

local Bold = {}
FX.Bold = Bold

--------------------------------------------------------------------------------
-- The looks' colours (main, heal: its light) and their own pieces (each look's own art, the others white, tinted)
--------------------------------------------------------------------------------

local LOOKS = {
	holy = { main = "FFD866", heal = "FFF2A8", plus = "plus_gold", sign = "crest_gold", star = "star_gold",
		seal = "seal_gold", wings = "res_wings", pillar = "pillar_gold" },
	nature = { main = "7CFF6A", heal = "C8FFB0", plus = "plus_green", sign = "crest_green", star = "star_green",
		seal = "seal_green", wings = "res_wings_green", pillar = "pillar_green" },
	water = { main = "6FC8FF", heal = "C8ECFF", plus = "plus_blue", sign = "crest_blue", star = "star_blue",
		seal = "seal_blue", wings = "res_wings_blue", pillar = "pillar_blue" },
}
local NAMED = { white = "FFFFFF", blue = "7FD0FF", steel = "C8D4E6", red = "FF4A3A", gold = "FFC83A", orange = "FF8A2A" }
local WHITE = { 1, 1, 1 }

local rgbs = {}
local function Hex(h)
	local c = rgbs[h]
	if not c then
		c = { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 }
		rgbs[h] = c
	end
	return c
end

local function ColourOf(L, key)
	return (key == "main" and L.main) or (key == "heal" and L.heal) or NAMED[key] or key
end

--------------------------------------------------------------------------------
-- The landings by kind (the sketch's A takes; times in s, sizes in its pixels). A part: its drawing (DRAW below), t0,
-- t1, its envelope (the engine's: flash, hold, pulse, in, blink; none: fading), its peak `a`; `held`: to the end of
-- what lasts (a cooldown's whole length). The engine's own: the border (Rim: the plate's rim and the ring's halo;
-- "main", "heal" or a colour of NAMED; `slot` 1 or 2)
--------------------------------------------------------------------------------

local function P(kind, t0, t1, fields)
	local part = { kind, bold = true, t0 = t0, t1 = t1 }
	for k, v in pairs(fields or {}) do
		part[k] = v
	end
	return part
end
local function Rim(colour, t0, t1, a, env, pulses, slot)
	return { "border", colour = colour, slot = slot or 1, grow = 0, t0 = t0, t1 = t1, a = a or 1, env = env or "hold",
		pulses = pulses }
end
local function Held(part)
	part.held = true
	return part
end

local LISTS = {
	-- 1A Burst: sparks gather into the ring, a flash over the whole frame, the plus pops past its size on the portrait,
	-- a shockwave out past the frame, stars flung off both its ends, a sweep across the whole plate, the border lit
	h = {
		P("converge", 0, 0.2, { s = "spark_white", c = "main", n = 6, r = 26, size = 6, env = "in" }),
		P("flash", 0.2, 0.55, { c = "heal", env = "flash", a = 0.7 }),
		P("ring", 0.2, 0.65, { s = "shock_white", c = "main", from = 24, to = 120, flat = 0.55, a = 0.9 }),
		P("pop", 0.2, 1.3, { s = "plus", at = "ring", size = 22, peak = 1.8, rise = 10, env = "hold" }),
		P("fling", 0.22, 1.0, { s = "star", from = "sides", n = 12, reach = 34, fall = 10, size = 7 }),
		P("sheen", 0.25, 0.65, { env = "pulse" }),
		Rim("main", 0.2, 1.2),
	},
	-- 2A Seal: motes spiral in, a seal ring shrinks down onto the portrait and locks, motes circling it a while
	o = {
		P("converge", 0, 0.3, { s = "spark_white", c = "main", n = 8, r = 34, size = 5, env = "in" }),
		P("pop", 0.05, 2.7, { s = "seal", at = "ring", size = 44, peak = 1.9, stamp = 0.12, env = "hold", a = 0.8 }),
		P("glow", 0.38, 0.7, { at = "ring", c = "main", w = 40, env = "flash" }),
		P("orbit", 0.4, 2.7, { s = "spark_white", c = "main", n = 3, r = 24, size = 5, speed = 3.5, env = "hold", a = 0.85 }),
	},
	-- its ticks: a ripple off the ring, the border breathing once round the whole frame
	t = {
		P("ring", 0, 0.45, { s = "shock_white", c = "heal", from = 40, to = 72 }),
		Rim("main", 0, 0.6, 0.7, "pulse"),
	},
	-- 3A Doors: a barrier in the frame's own shape slides in as two halves from past its sides and locks, a flash,
	-- shards flung; light running across it while it holds
	s = {
		P("barrier", 0, 1.9, { c = "blue", doors = 0.3, from = 60, sheen = 0.9, env = "hold", a = 0.9 }),
		P("flash", 0.28, 0.6, { c = "blue", env = "flash", a = 0.8 }),
		P("fling", 0.3, 1.2, { s = "shard_blue", at = "frame", n = 14, reach = 40, fall = 18, size = 8, turn = true }),
		Rim("blue", 0.3, 1.9),
	},
	-- 4A Stamp: the crest huge and faint over the frame, coming down onto the portrait, rays turning behind it, a flash
	p = {
		P("pop", 0, 1.8, { s = "sign", at = "ring", size = 28, peak = 3.0, stamp = 0.12, env = "hold" }),
		P("spin", 0.22, 1.7, { s = "rays_white", c = "main", at = "ring", size = 64, speed = 1.2, env = "hold", a = 0.7 }),
		P("flash", 0.22, 0.55, { c = "main", env = "flash", a = 0.7 }),
		Rim("main", 0.22, 1.9),
	},
	-- 5A Column: a wide column of light slams down onto the portrait, rays turning, a big flash, pluses flung up and
	-- out of the ring, a sweep across the plate
	b = {
		P("pillar", 0, 1.0, { s = "pillar", at = "ring", w = 40, h = 90, env = "flash" }),
		P("spin", 0.15, 1.6, { s = "rays_white", c = "main", at = "ring", size = 80, env = "hold", a = 0.7 }),
		P("flash", 0.18, 0.6, { c = "heal", env = "flash", a = 0.9 }),
		P("fling", 0.2, 1.4, { s = "plus", at = "ring", n = 12, reach = 40, fall = 30, size = 9 }),
		P("sheen", 0.3, 0.7, { env = "pulse" }),
		Rim("main", 0.2, 1.8),
	},
	-- 6A Wings: wings of light unfold behind the frame, out past both its sides, a halo drops onto the portrait,
	-- motes rising off the bars, a flash
	r = {
		P("flank", 0, 2.2, { s = "wings", h = 62, dy = -4, under = true, env = "hold" }),
		P("glow", 0.1, 1.6, { at = "ring", c = "main", w = 60, env = "hold", a = 0.6 }),
		P("slam", 0.4, 1.9, { s = "halo_white", c = "main", at = "above", size = 30, tall = 0.32, drop = 20, land = 0.25,
			env = "hold" }),
		P("rise", 0.3, 2.2, { s = "spark_white", c = "main", at = "plate", n = 8, height = 40, size = 5, loop = 0.9,
			env = "hold" }),
		P("flash", 0.95, 1.35, { c = "white", env = "flash", a = 0.7 }),
		Rim("main", 1.0, 2.1),
	},
	-- 7A Wave: each frame in turn flashes, its plus pops and a ring runs along it -- yours first, then outwards
	-- (`wave` s a step: FX.BoldLanding)
	g = { wave = 0.14,
		P("flash", 0, 0.35, { c = "heal", env = "flash", a = 0.6 }),
		P("pop", 0, 0.9, { s = "plus", at = "ring", size = 18, peak = 1.8, rise = 8, env = "hold" }),
		P("ring", 0.02, 0.5, { s = "halo_white", c = "main", from = 30, to = 140, flat = 0.4 }),
		P("fling", 0.05, 0.7, { s = "spark_white", c = "main", from = "sides", n = 6, reach = 22, fall = 8, size = 5 }),
	},
	-- 8A Arc (a chain heal's landing on each frame it reaches -- Heal Flight's hops between them): a flash, the plus
	-- pops on the portrait, stars burst one after another along the bars, the border lit
	c = {
		P("flash", 0, 0.3, { c = "heal", env = "flash", a = 0.6 }),
		P("pop", 0, 0.85, { s = "plus", at = "ring", size = 18, peak = 1.7, rise = 6, env = "hold" }),
		P("splash", 0.03, 0.6, { s = "star", n = 3, size = 13 }),
		Rim("main", 0, 0.75),
	},
	-- 9A Shockwaves (a roar, 2 s whatever the taunt's length): the frame's light shaking, three square shockwaves of
	-- the frame's shape out far past its sides, a red flash, sparks off its ends; the border breathing red
	W = { held = true, fixed = 2,
		P("shake", 0.05, 0.6, { amp = 3 }),
		P("flash", 0.05, 0.4, { c = "red", env = "flash", a = 0.6 }),
		P("squares", 0.05, 1.3, { c = "red", n = 3, reach = 50 }),
		P("fling", 0.1, 0.8, { s = "spark_white", c = "orange", from = "sides", n = 10, reach = 30, fall = 6, size = 5 }),
		Held(Rim("red", 0.05, nil, 0.85, "breathe")),
	},
	-- 10A Alarm (a taunt): a red ! springs up over the portrait and shakes, the border blinking red twice
	U = {
		P("bang", 0, 1.3, { at = "above", env = "hold" }),
		Rim("red", 0.05, 1.0, 1, "blink", 2),
		P("glow", 0, 0.5, { at = "ring", c = "red", w = 50, env = "flash", a = 0.6 }),
	},
	-- 11A Plates (a fortify: Shield Wall, Barkskin, Dispersion; held): steel guards slam in from past the sides and
	-- clang onto the frame -- a curved one round the portrait, a straight one down the plate's right border, its whole
	-- height -- sparks, a jolt; they hold, the border steel
	F = { held = true,
		Held(P("guards", 0, nil, { close = 0.25, from = 60 })),
		P("shake", 0.2, 0.42, { amp = 2 }),
		P("fling", 0.22, 0.9, { s = "spark_white", c = "orange", at = "frame", n = 12, reach = 30, fall = 16, size = 5 }),
		Held(Rim("steel", 0.22, nil)),
	},
	-- 12A Heartbeat (more health: Last Stand, Vengeance; held): a heart beats twice over the portrait, each beat a red
	-- ring out along the frame, the bars flaring; the border red while it lasts
	L = { held = true,
		P("heart", 0, 1.4, { at = "ring", env = "hold" }),
		P("ring", 0.05, 0.5, { s = "halo_white", c = "red", from = 30, to = 130, flat = 0.45 }),
		P("ring", 0.35, 0.8, { s = "halo_white", c = "red", from = 30, to = 130, flat = 0.45 }),
		P("barflash", 0.35, 0.7, { c = "red", env = "pulse", a = 0.6 }),
		Held(Rim("red", 0.35, nil, 0.8)),
	},
	-- 13A Sunburst (an immunity: Divine Shield, Divine Protection, Ice Block; held): golden rays burst from the
	-- portrait, a golden barrier in the frame's own shape swells out of it and holds, stars flung past its sides
	I = { held = true,
		Held(P("barrier", 0.1, nil, { c = "gold", swell = 0.36, sheen = 0.9, sheenFor = 2.0, a = 0.9 })),
		P("spin", 0, 1.9, { s = "rays_gold", at = "ring", size = 60, speed = 0.8, env = "hold", a = 0.6 }),
		P("flash", 0.1, 0.5, { c = "gold", env = "flash", a = 0.8 }),
		P("fling", 0.12, 1.0, { s = "star_gold", at = "ring", n = 12, reach = 44, fall = 12, size = 7 }),
	},
	-- 14A Afterimages (an evasion: Evasion, Deterrence; held): afterimages of the frame slip off to the left and right
	-- and fade, wind streaks crossing it; the border white a moment, then steel while it lasts
	E = { held = true,
		P("ghost", 0, 0.9, { n = 3, dist = 26 }),
		P("streaks", 0.05, 0.7, { c = "white", n = 6 }),
		Rim("white", 0, 0.6, 1, "flash"),
		Held(Rim("steel", 0.6, nil, 0.5, nil, nil, 2)),
	},
}
for _, list in pairs(LISTS) do
	list.bold = true
end
FX.BOLD = LISTS   -- (the tests')

--------------------------------------------------------------------------------
-- The lists a look plays: their borders in its colour (copied once); a group heal's on a frame `step`s from yours a
-- step's `wave` s later (a copy for each step)
--------------------------------------------------------------------------------

local made = {}   -- [look] = { [kind] = list, [kind .. step] = list }

local function Resolve(list, L)
	local out = { held = list.held, fixed = list.fixed, bold = true }
	for i, part in ipairs(list) do
		if part[1] == "border" then
			local copy = {}
			for k, v in pairs(part) do
				copy[k] = v
			end
			copy.colour = ColourOf(L, part.colour)
			out[i] = copy
		else
			out[i] = part
		end
	end
	return out
end

local function Delayed(list, delay)
	local out = { held = list.held, fixed = list.fixed, bold = true }
	for i, part in ipairs(list) do
		local copy = {}
		for k, v in pairs(part) do
			copy[k] = v
		end
		copy.t0, copy.t1 = (part.t0 or 0) + delay, part.t1 and part.t1 + delay
		out[i] = copy
	end
	return out
end

-- A wave over the group out of one frame (a group heal's out of yours): each member's frame's step, its distance from
-- that frame (in half frame heights) ranked among the group's frames' -- equal distances one step, the nearest other
-- the first (your player frame may stand far from your party's column: the wave still runs down it); WAVE_MAX steps at
-- most. -> { [frame] = step } (none: 0), read once a moment and origin
local wave = { at = nil, from = nil, steps = setmetatable({}, { __mode = "k" }) }
function FX.WaveSteps(origin)
	local now = GetTime()
	if wave.at ~= now or wave.from ~= origin then
		wave.at, wave.from = now, origin
		wipe(wave.steps)
		local ml, mb, mr, mt
		if type(origin) == "table" then
			ml, mb, mr, mt = FX.Rect(origin)
		end
		if ml then
			local far, ranks = {}, {}
			for _, unit in ipairs((FX.Members())) do
				local f = FX.FrameOf(unit)
				local l, b, r, t
				if f and f ~= origin then
					l, b, r, t = FX.Rect(f)
				end
				if l then
					local dx, dy = ((l + r) - (ml + mr)) / 2, ((b + t) - (mb + mt)) / 2
					local d = floor(sqrt(dx * dx + dy * dy) / max(1, t - b) * 2 + 0.5)   -- (in half heights)
					far[f] = d
					ranks[d] = true
				end
			end
			local order = {}
			for d in pairs(ranks) do
				order[#order + 1] = d
			end
			table.sort(order)
			for i, d in ipairs(order) do
				ranks[d] = i
			end
			for f, d in pairs(far) do
				wave.steps[f] = min(WAVE_MAX, ranks[d])
			end
		end
	end
	return wave.steps
end

-- a group heal's landing on S's frame (a split frame's ring half: its owner's): its step out of your own frame
local function WaveStep(S)
	local frame = S and (S.frame or (S.owner and FX.state[S.owner] and FX.state[S.owner].frame))
	if not frame then
		return 0
	end
	return FX.WaveSteps(FX.FrameOf(FX.Canon("player")))[frame] or 0
end

-- the bold list for a look and kind on S's frame, or nil (none: the look's own)
function FX.BoldLanding(look, kind, S)
	local list = LISTS[kind]
	local L = list and LOOKS[look]
	if not L then
		return nil
	end
	local byKind = made[look]
	if not byKind then
		byKind = {}
		made[look] = byKind
	end
	local out = byKind[kind]
	if not out then
		out = Resolve(list, L)
		byKind[kind] = out
	end
	local step = list.wave and WaveStep(S) or 0
	if step > 0 then
		local key = kind .. step
		local late = byKind[key]
		if not late then
			late = Delayed(out, step * list.wave)
			byKind[key] = late
		end
		return late
	end
	return out
end

--------------------------------------------------------------------------------
-- The boards: a landing layer's frame over everything and its frame under the unit's frame; their sprites
--------------------------------------------------------------------------------

local G = {}   -- (the frame now: below, The frame now)
-- (Put and Sweep: a mirrored frame's middle -- its sprites turned back across it -- or nil: Bold.Begin's, FX.Outline's)
local mirror = nil
local boards = setmetatable({}, { __mode = "k" })   -- [layer] = { over, under, list, frame, sweep, sweepTex }
local pools = setmetatable({}, { __mode = "k" })    -- [board frame] = { texture, ... }
local seen = setmetatable({}, { __mode = "k" })     -- [texture] = what it shows: { file, blend, rgb }
Bold.boards = boards   -- (the tests')

local function BoardOf(layer)
	local b = boards[layer]
	if not b then
		local over = CreateFrame("Frame", nil, layer)
		local under = CreateFrame("Frame", nil, UIParent)
		under:EnableMouse(false)
		under:Hide()
		b = { over = over, under = under }
		boards[layer] = b
	end
	return b
end

local function Tex(f, i)
	local list = pools[f]
	if not list then
		list = {}
		pools[f] = list
	end
	local t = list[i]
	if not t then
		t = f:CreateTexture(nil, "OVERLAY")
		list[i] = t
		seen[t] = {}
	end
	return t
end

local function HideFrom(f, i)
	local list = pools[f]
	if list then
		for k = i, #list do
			list[k]:Hide()
		end
	end
end

-- sprite i: `file` (a light piece's name, or a path) with its middle at (x, y) in UIParent's units, w x h, alpha a,
-- turned `rot`, tinted `rgb` (white), added as light (`add`, the default) or laid; `l, r, tt, b` the part of its
-- picture (all of it)
local function Put(f, i, file, x, y, w, h, a, rot, rgb, add, l, r, tt, b)
	if a <= 0.004 or w < 0.1 or h < 0.1 then   -- (a line a screen pixel thin on a 4K screen: 0.36 units)
		return i
	end
	local t = Tex(f, i)
	local s = seen[t]
	local path = file:find("\\", 1, true) and file or FX.Art(file .. ".tga")
	if s.file ~= path then
		t:SetTexture(path)
		s.file = path
	end
	local blend = add == false and "BLEND" or "ADD"
	if s.blend ~= blend then
		t:SetBlendMode(blend)
		s.blend = blend
	end
	rgb = rgb or WHITE
	if s.rgb ~= rgb then
		t:SetVertexColor(rgb[1], rgb[2], rgb[3])
		s.rgb = rgb
	end
	-- (1.2.4: a mirrored frame drawn the game's way round -- G.mx its middle: Bold.Begin -- each sprite turned back
	-- across it, its picture flipped)
	local axis = mirror
	if axis then
		x = 2 * axis - x
	end
	if l then
		t:SetRotation(0)
		if axis then
			t:SetTexCoord(r, l, tt, b)
		else
			t:SetTexCoord(l, r, tt, b)
		end
	else
		if axis then
			t:SetTexCoord(1, 0, 0, 1)
			t:SetRotation(-(rot or 0))
		else
			t:SetTexCoord(0, 1, 0, 1)
			t:SetRotation(rot or 0)
		end
	end
	t:ClearAllPoints()
	t:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
	t:SetSize(w, h)
	t:SetAlpha(min(1, a))
	t:Show()
	return i + 1
end

-- a line of light over the box (x0, y0) .. (x1, y1) -- across or upright by its shape -- its glow `glow` wide round
-- its core, tinted `rgb`
local function Line(f, i, x0, y0, x1, y1, a, rgb, glow)
	local w, h = abs(x1 - x0), abs(y1 - y0)
	if w >= h then
		return Put(f, i, "line_h", (x0 + x1) / 2, (y0 + y1) / 2, w, h + 2 * glow, a, 0, rgb)
	end
	return Put(f, i, "line_v", (x0 + x1) / 2, (y0 + y1) / 2, w + 2 * glow, h, a, 0, rgb)
end

--------------------------------------------------------------------------------
-- The frame now (G: its whole -- ring and plate -- l b r t, x y its middle, w h; the ring's middle and radius rx ry
-- rr, nil without one; the plate's outline pl pb pr pt -- its gold rim round the name and the bars; the bars' box al
-- ab ar at; k its units a sketch pixel), the look, the shake
--------------------------------------------------------------------------------

local cur = { ox = 0, oy = 0 }
Bold.G = G   -- (the tests')

local function Col(key)
	return Hex(ColourOf(cur.look, key or "white"))
end

-- a part's picture: the look's own piece (plus, sign, star, seal, wings, pillar: untinted), else a white or own piece
-- tinted its colour -> file, tint
local function Spr(p)
	local own = cur.look[p.s]
	if own then
		return own, nil
	end
	return p.s, p.c and Col(p.c) or nil
end

local function At(p)
	local ox, oy = cur.ox, cur.oy
	local at = p.at
	if at == "plate" then
		return (G.al + G.ar) / 2 + ox, (G.ab + G.at) / 2 + oy
	elseif at == "frame" then
		return G.x + ox, G.y + oy
	elseif at == "above" then
		return (G.rx or G.x) + ox, G.t + 6 * G.k + oy
	end
	return (G.rx or G.x) + ox, (G.ry or G.y) + oy
end

local function R(i, k)
	local x = sin(i * 12.9898 + k * 78.233) * 43758.5453
	return x - floor(x)
end
local function Out(v)
	return 1 - (1 - v) ^ 3
end
local function Back(v)
	return 1 + 2.7 * (v - 1) ^ 3 + 1.7 * (v - 1) ^ 2
end
local function Clamp(v)
	return max(0, min(1, v))
end

-- a frame's name's top (Unit Frames' M:PartsOf; a frame it leaves -- the target, the focus -- the name the game's
-- UnitFrame_Initialize keeps on it): the plate's top on a frame with no picture of its plate
local function NameTop(frame)
	local panel = MelloUI:GetModule("UnitFrames")
	if panel and panel.PartsOf and type(frame) == "table" then
		local ok, _, _, _, name = pcall(panel.PartsOf, panel, frame)
		if not (ok and name) then
			ok, name = true, rawget(frame, "name")
		end
		if ok and type(name) == "table" and FX.Visible(name) then
			local _, _, _, top = FX.Rect(name)
			return top and top + 1
		end
	end
	return nil
end

-- S (G, or a frame's shape: ShapeOf) filled: its ring's square (rl, rb, rr, rt; nil: none), its bars' box (al .. at),
-- its plate (pl .. pt)
local function Fill(S, rl, rb, rr, rt, al, ab, ar, at, pl, pb, pr, pt)
	local rad
	if rl then
		S.rx, S.ry, rad = (rl + rr) / 2, (rb + rt) / 2, (rr - rl) / 2
	else
		S.rx, S.ry = nil, nil
	end
	S.rr = rad
	S.al, S.ab, S.ar, S.at = al, ab, ar, at
	S.pl, S.pb, S.pr, S.pt = pl, pb, pr, pt
	local l, b, r, top = pl, pb, pr, pt
	if rad then
		l, b, r, top = min(l, S.rx - rad), min(b, S.ry - rad), max(r, S.rx + rad), max(top, S.ry + rad)
	end
	S.l, S.b, S.r, S.t = l, b, r, top
	S.x, S.y, S.w, S.h = (l + r) / 2, (b + top) / 2, r - l, top - b
	S.k = (rad and 2 * rad or S.h) / RING_PX
end

--------------------------------------------------------------------------------
-- The frame's own shape: the portrait's circle and the plate's box. The barrier: the circle's light (barrier_round,
-- its line at RING_LINE of its half) in three pieces -- its cap over the box, its band beside the box (up to where the
-- circle crosses the box's edges), its cap under it -- and the box from there (a faint fill, lines of light round it):
-- no line inside the shape. `which` 0 whole, 1 the left door (its edge along the cut), 2 the right one; scaled `s`
-- round (sx, sy), moved dx
--------------------------------------------------------------------------------

local function Barrier(f, n, rgb, a, dx, s, sx, sy, which, cut)
	local k, dy = G.k, cur.oy
	local core = 1.4 * k * s
	local glow = 2.5 * k * s
	local pad = PAD * k
	local function X(x)
		return sx + (x - sx) * s + dx
	end
	local function Y(y)
		return sy + (y - sy) * s + dy
	end
	local yb, yt, xr = G.pb - pad, G.pt + pad, G.pr + pad
	local xl = G.pl - pad
	if G.rr and which ~= 2 then
		local cx, cy = G.rx, G.ry
		local rad = G.rr + pad
		local half = rad / RING_LINE   -- (the picture's half: its glow round the line)
		local top, bot = cy + rad, cy - rad
		local ct, cb = min(yt, top), max(yb, bot)
		local d = max(abs(ct - cy), abs(cb - cy))
		local xc = cx + sqrt(max(0, rad * rad - d * d))
		-- a piece of the circle's picture: world rows y0 .. y1, columns from its left to x1
		local function Piece(y0, y1, x1)
			local x0 = cx - half
			if y1 - y0 < 0.5 or x1 <= x0 then
				return
			end
			local u1 = (x1 - x0) / (2 * half)
			local v0, v1 = (cy + half - y1) / (2 * half), (cy + half - y0) / (2 * half)
			local mx, my, w, h = X((x0 + x1) / 2), Y((y0 + y1) / 2), (x1 - x0) * s, (y1 - y0) * s
			n = Put(f, n, "barrier_round", mx, my, w, h, a, 0, rgb, true, 0, u1, v0, v1)
			n = Put(f, n, "barrier_round", mx, my, w, h, a * 0.35, 0, WHITE, true, 0, u1, v0, v1)
		end
		Piece(ct, cy + half, cx + half)
		Piece(cb, ct, min(xc, which == 1 and cut or xc))
		Piece(cy - half, cb, cx + half)
		xl = xc
	end
	local x0, x1 = xl, xr
	local openL = G.rr ~= nil
	if which == 1 then
		x1 = cut
	elseif which == 2 then
		x0, openL = cut, false
	end
	if x1 - x0 < 1 then
		return n
	end
	local L0, L1, B0, T1 = X(x0), X(x1), Y(yb), Y(yt)
	-- the faint fill, then the lines: top, bottom, right (and left on a door or a frame with no ring), each its colour
	-- with a white core
	n = Put(f, n, WHITE8, (L0 + L1) / 2, (B0 + T1) / 2, L1 - L0, T1 - B0, a * 0.12, 0, rgb)
	local function Edge(ax, ay, bx, by)
		n = Line(f, n, ax, ay, bx, by, a, rgb, glow)
		n = Line(f, n, ax, ay, bx, by, a * 0.45, WHITE, glow * 0.4)
	end
	Edge(L0, T1 - core, L1, T1)
	Edge(L0, B0, L1, B0 + core)
	Edge(L1 - core, B0, L1, T1)
	if not openL then
		Edge(L0, B0, L0 + core, T1)
	end
	return n
end

-- a band of light across the plate (the bold landings' sweep -- the name's strip and the bars), or across the
-- barrier's box (its light running over it): a clip frame of the board's own, laid on that box
local function Sweep(key, l, b, r, t, x, w, h, a, rot)
	local board = cur.board
	local axis = mirror
	if axis then
		l, r, x, rot = 2 * axis - r, 2 * axis - l, 2 * axis - x, -(rot or 0)
	end
	local clip = board[key]
	if not clip then
		clip = CreateFrame("Frame", nil, board.over)
		clip:SetClipsChildren(true)
		local tex = clip:CreateTexture(nil, "OVERLAY")
		tex:SetTexture(FX.Art("sheen.tga"))
		tex:SetBlendMode("ADD")
		clip.tex = tex
		board[key] = clip
	end
	clip:ClearAllPoints()
	clip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
	clip:SetSize(max(1, r - l), max(1, t - b))
	clip:Show()
	local tex = clip.tex
	tex:ClearAllPoints()
	tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, (b + t) / 2)
	tex:SetSize(w, h)
	tex:SetRotation(rot or 0)
	tex:SetAlpha(min(1, a))
	tex:Show()
	cur[key] = true
end

--------------------------------------------------------------------------------
-- The parts (f: a board, n its next sprite, p the part, v its share, a its alpha, lt s into it, span its length)
--------------------------------------------------------------------------------

local DRAW = {}
Bold.DRAW = DRAW   -- (the tests')

function DRAW.shake(_, n)
	return n
end

function DRAW.glow(f, n, p, v, a)
	local x, y = At(p)
	local g = p.grow and p.grow[1] + (p.grow[2] - p.grow[1]) * Out(v) or 1
	local w = p.w * G.k * g
	return Put(f, n, "glow_white", x, y, w, (p.h or p.w) * G.k * g, a, 0, Col(p.c))
end

-- the light over the WHOLE frame
function DRAW.flash(f, n, p, v, a)
	n = Put(f, n, "glow_white", G.x + cur.ox, G.y + cur.oy, G.w * 1.5, G.h * 1.6, a, 0, Col(p.c))
	return Put(f, n, "glow_white", G.x + cur.ox, G.y + cur.oy, G.w * 1.1, G.h * 1.1, a * 0.45)
end

-- a piece popping past its size (`peak`) and settling, floating up `rise` after; `stamp`: coming down from its peak
-- (huge and faint) onto its spot in that share of its span
function DRAW.pop(f, n, p, v, a)
	local x, y = At(p)
	local peak = p.peak or 1.6
	local g = v < 0.14 and peak * Out(v / 0.14) or v < 0.3 and peak + (1 - peak) * Out((v - 0.14) / 0.16) or 1
	if p.stamp then
		local q = Clamp(v / p.stamp)
		g, a = peak + (1 - peak) * q * q, a * (0.25 + 0.75 * q)
	end
	local up = (p.rise or 0) * Clamp((v - 0.3) / 0.7) * G.k
	local file, tint = Spr(p)
	local s = p.size * G.k * max(0.05, g)
	return Put(f, n, file, x, y + up, s, s, a, 0, tint)
end

-- a ring growing from `from` to `to` (flattened `flat`): a shockwave
function DRAW.ring(f, n, p, v, a)
	local x, y = At(p)
	local d = (p.from + (p.to - p.from) * Out(v)) * G.k
	return Put(f, n, p.s, x, y, d, d * (p.flat or 1), a * (1 - 0.6 * v), 0, Col(p.c))
end

-- pieces flung out of the frame's sides (`from` "sides": every other one each way, over `spread`) or round a point,
-- out to `reach` fast, falling `fall`, fading in their last 40%
function DRAW.fling(f, n, p, v, a)
	local k = G.k
	local q = Out(v)
	local file, tint = Spr(p)
	local sides = p.from == "sides"
	local per = sides and math.ceil(p.n / 2) or p.n
	local fade = v > 0.6 and a * (1 - v) / 0.4 or a
	for i = 0, p.n - 1 do
		local ox, oy, ang
		if sides then
			local side = i % 2 == 1 and 1 or -1
			ox, oy = (side > 0 and G.r or G.l) + cur.ox, G.y + cur.oy
			ang = (p.spread or 2.4) * ((floor(i / 2) + 0.5) / per - 0.5) + (R(i, 1) - 0.5) * 0.4
			if side < 0 then
				ang = PI - ang
			end
		else
			ox, oy = At(p)
			ang = i / p.n * TAU + (R(i, 1) - 0.5) * 0.5
		end
		local d = p.reach * k * (0.55 + 0.7 * R(i, 2)) * q
		local x, y = ox + cos(ang) * d, oy + sin(ang) * d - (p.fall or 0) * k * v * v
		local s = p.size * k * (0.7 + 0.6 * R(i, 3))
		n = Put(f, n, file, x, y, s, s, fade, p.turn and -(ang + (R(i, 4) - 0.5) * 8 * v) or 0, tint)
	end
	return n
end

-- pieces gathering into a point
function DRAW.converge(f, n, p, v, a)
	local x, y = At(p)
	local file, tint = Spr(p)
	local d = p.r * G.k * (1 - v * v)
	local s = p.size * G.k
	for i = 0, p.n - 1 do
		local ang = i / p.n * TAU + 0.4
		n = Put(f, n, file, x + cos(ang) * d, y + sin(ang) * d, s, s, a, 0, tint)
	end
	return n
end

-- pieces rising off the ring or the bars, swaying; `loop`: on and on, each that many s up
function DRAW.rise(f, n, p, v, a, lt)
	local k = G.k
	local file, tint = Spr(p)
	local ring = p.at == "ring"
	local cx, cy = G.rx or G.x, G.ry or G.y
	for i = 0, p.n - 1 do
		local vv = p.loop and ((lt / p.loop) + R(i, 5)) % 1 or Clamp(v * 1.3 - R(i, 4) * 0.3)
		local x = (ring and cx + (-12 + 24 * R(i, 1)) * k or G.al + (G.ar - G.al) * R(i, 1)) + sin(vv * 5 + i) * 2 * k
		local y = (ring and cy - 6 * k or G.ab + 4 * k) + vv * p.height * k
		local s = p.size * k
		n = Put(f, n, file, x + cur.ox, y + cur.oy, s, s, a * sin(PI * vv), 0, tint)
	end
	return n
end

function DRAW.orbit(f, n, p, v, a, lt)
	local x, y = At(p)
	local file, tint = Spr(p)
	local r, s = p.r * G.k, p.size * G.k
	for i = 0, p.n - 1 do
		local ang = lt * (p.speed or 3) + i / p.n * TAU
		n = Put(f, n, file, x + cos(ang) * r, y + sin(ang) * r * 0.85, s, s, a, 0, tint)
	end
	return n
end

function DRAW.spin(f, n, p, v, a, lt)
	local x, y = At(p)
	local file, tint = Spr(p)
	local s = p.size * G.k
	return Put(f, n, file, x, y, s, s, a, -lt * (p.speed or 1.5), tint)
end

-- a column of light dropping from above onto its point, narrowing
function DRAW.pillar(f, n, p, v, a)
	local x, y = At(p)
	local k = G.k
	local h = p.h * k * Out(Clamp(v / 0.18))
	local top = y + p.h * k
	local file, tint = Spr(p)
	n = Put(f, n, file, x, top - h / 2, p.w * k * (1 - 0.3 * v), h, a, 0, tint)
	return Put(f, n, file, x, top - h / 2, p.w * k * (1 - 0.3 * v) * 0.6, h, a * 0.8, 0, tint)
end

-- a piece dropping onto its point (its `land` share), squashed as it lands; `tall` its height's share (a halo seen
-- from the side)
function DRAW.slam(f, n, p, v, a)
	local x, y = At(p)
	local k = G.k
	local land = p.land or 0.25
	local sx, sy = 1, 1
	if v < land then
		y = y + (p.drop or 40) * k * (1 - (v / land) ^ 2)
	else
		local s = Clamp((v - land) / 0.12)
		sx, sy = 1 + 0.3 * (1 - s), 1 - 0.25 * (1 - s)
	end
	local size = p.size * k
	local h = size * (p.tall or 1)
	local file, tint = Spr(p)
	return Put(f, n, file, x, y - h * (1 - sy) / 2, size * sx, h * sy, a, 0, tint)
end

-- (the wings' move) a pair's halves pinned to the frame's sides, each opening from its root out, overshooting, `h`
-- high, its root tucked `tuck` behind the frame's edge
function DRAW.flank(f, n, p, v, a)
	local k = G.k
	local file, tint = Spr(p)
	local h = p.h * k
	local q = Back(Clamp(v / (p.open or 0.25)))
	local w = h * 0.5 * max(0.05, q)   -- (a half of the pair's square picture)
	local y = G.y + (p.dy or 0) * -k + cur.oy
	local tuck = (p.tuck or 8) * k
	n = Put(f, n, file, G.l + tuck - w / 2 + cur.ox, y, w, h, a, 0, tint, true, 0, 0.5, 0, 1)
	return Put(f, n, file, G.r - tuck + w / 2 + cur.ox, y, w, h, a, 0, tint, true, 0.5, 1, 0, 1)
end

-- the barrier in the frame's shape: `doors` s its halves sliding in from `from` px past the sides and locking (the
-- seam flashing), else `swell` s growing out of the portrait; `sheen`: a band of light across it every so many s
-- (for its first `sheenFor` s)
function DRAW.barrier(f, n, p, v, a, lt)
	local rgb = Col(p.c)
	local k = G.k
	local cut = G.x
	if p.doors and lt < p.doors then
		local gap = (1 - Back(lt / p.doors)) * (p.from or 60) * k
		n = Barrier(f, n, rgb, a, cur.ox - gap, 1, 0, 0, 1, cut)
		return Barrier(f, n, rgb, a, cur.ox + gap, 1, 0, 0, 2, cut)
	end
	if p.swell and lt < p.swell then
		local s = max(0.05, Back(lt / p.swell))
		return Barrier(f, n, rgb, a, cur.ox, s, G.rx or G.x, G.ry or G.y, 0)
	end
	n = Barrier(f, n, rgb, a, cur.ox, 1, 0, 0, 0)
	if p.doors and lt < p.doors + 0.11 then
		n = Line(f, n, cut - k + cur.ox, G.pb - PAD * k, cut + k + cur.ox, G.pt + PAD * k, a, WHITE, 3 * k)
	end
	if p.sheen and lt < (p.sheenFor or 1e9) then
		local q = (lt % p.sheen) / min(0.6, p.sheen)
		if q <= 1 then
			local pad = PAD * k
			local l, r = G.l - pad + cur.ox, G.r + pad + cur.ox
			Sweep("barrierSweep", l, G.b - pad + cur.oy, r, G.t + pad + cur.oy, l + (r - l) * q, 14 * k, G.h * 2.6,
				a * 0.8, -0.35)
		end
	end
	return n
end

-- Shield Wall's steel guards slamming in from `from` px past the sides over `close` s: curved round the portrait's
-- left side (straight on a frame with none) and straight down the plate's right border -- its whole height, the
-- name's strip too
function DRAW.guards(f, n, p, v, a, lt)
	local k = G.k
	local gap = (1 - Back(Clamp(lt / (p.close or 0.25)))) * (p.from or 60) * k
	local y0, y1 = G.pb - 4 * k, G.pt + 4 * k
	local sh = y1 - y0
	if G.rr then
		local h = 2 * (G.rr + 5 * k)
		local w = h * 0.5
		n = Put(f, n, "guard_round", G.rx - G.rr - w * 0.22 - gap + cur.ox, G.ry + cur.oy, w, h, a, 0, nil, false)
	else
		n = Put(f, n, "guard_side", G.pl - sh * 0.08 - gap + cur.ox, (y0 + y1) / 2 + cur.oy, sh * 0.25, sh, a, 0, nil,
			false)
	end
	return Put(f, n, "guard_side", G.pr + sh * 0.08 + gap + cur.ox, (y0 + y1) / 2 + cur.oy, sh * 0.25, sh, a, 0, nil,
		false)
end

-- afterimages of the frame slipping off to the left and right, fading: copies of its picture (a frame wearing one),
-- else of its outline
function DRAW.ghost(f, n, p, v, a)
	local q = Out(v)
	local pic, l, b, r, t = cur.pic, cur.picL, cur.picB, cur.picR, cur.picT
	for side = -1, 1, 2 do
		for i = 1, p.n do
			local dx = side * p.dist * G.k * q * i / p.n
			local fa = a * 0.45 / i
			if pic and FX.CopyLook and fa > 0.004 then
				local tex = Tex(f, n)
				if FX.CopyLook(tex, pic) then
					seen[tex].file, seen[tex].blend, seen[tex].rgb = nil, "ADD", nil
					tex:SetBlendMode("ADD")
					tex:SetVertexColor(1, 1, 1)
					tex:SetRotation(0)
					tex:ClearAllPoints()
					tex:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l + dx, b)
					tex:SetSize(max(1, r - l), max(1, t - b))
					tex:SetAlpha(min(1, fa))
					tex:Show()
					n = n + 1
				end
			else
				n = Barrier(f, n, WHITE, fa, cur.ox + dx, 1, 0, 0, 0)
			end
		end
	end
	return n
end

-- wind streaks crossing the frame, out to its sides
function DRAW.streaks(f, n, p, v, a)
	local k = G.k
	for i = 0, p.n - 1 do
		local side = i % 2 == 1 and 1 or -1
		local y = G.t - 6 * k - (G.h - 12 * k) * R(i, 1)
		local x = G.x + side * (G.w * 0.2 + v * G.w * 0.9)
		n = Put(f, n, "streak_white", x + cur.ox, y + cur.oy, (30 + 20 * R(i, 2)) * k, 4 * k, a * (1 - v), 0, Col(p.c))
	end
	return n
end

-- square shockwaves of the frame's shape bursting out of it one after another, out to `reach` past its sides
function DRAW.squares(f, n, p, v, a)
	local k = G.k
	local rgb = Col(p.c)
	for j = 0, p.n - 1 do
		local vv = Clamp((v - j * 0.15) / 0.6)
		if vv > 0 and vv < 1 then
			local gr = (4 + p.reach * Out(vv)) * k
			local lw = (3 - 2 * vv) * k
			local l, r = G.l - gr + cur.ox, G.r + gr + cur.ox
			local t, b = G.t + gr * 0.25 + cur.oy, G.b - gr * 0.25 + cur.oy
			local fa = a * (1 - vv)
			n = Line(f, n, l, t - lw, r, t, fa, rgb, 3 * k)
			n = Line(f, n, l, b, r, b + lw, fa, rgb, 3 * k)
			n = Line(f, n, l, b, l + lw, t, fa, rgb, 3 * k)
			n = Line(f, n, r - lw, b, r, t, fa, rgb, 3 * k)
		end
	end
	return n
end

-- the taunt's !: springing up past its size, shaking a moment
function DRAW.bang(f, n, p, v, a, lt)
	local x, y = At(p)
	local k = G.k
	local g = v < 0.12 and 1.8 * Out(v / 0.12) or v < 0.25 and 1.8 - 0.8 * Out((v - 0.12) / 0.13) or 1
	local jit = (v > 0.25 and v < 0.6) and ((floor(lt / 0.04) % 2 == 1) and k or -k) or 0
	local h = 34 * k * g
	n = Put(f, n, "bang", x + jit, y + 8 * k, h * 0.5, h, a, 0, nil)
	return Put(f, n, "bang", x + jit, y + 8 * k, h * 0.5, h, a * 0.6, 0, nil)
end

-- Last Stand's heart: beating twice
function DRAW.heart(f, n, p, v, a, lt)
	local x, y = At(p)
	local function Beat(t0)
		local q = (lt - t0) / 0.18
		return (q > 0 and q < 1) and sin(PI * q) or 0
	end
	local g = (1 + 0.45 * max(Beat(0.05), Beat(0.35))) * G.k
	n = Put(f, n, "heart", x, y, 22 * g, 20 * g, a)
	return Put(f, n, "glow_white", x, y, 36 * g, 36 * g, a * 0.5 * (g / G.k - 0.8), 0, Hex(NAMED.red))
end

-- stars bursting one after another along the bars, left to right
function DRAW.splash(f, n, p, v, a, lt)
	local file, tint = Spr(p)
	local y = (G.ab + G.at) / 2 + cur.oy
	for i = 0, p.n - 1 do
		local t = lt - i * 0.07
		if t > 0 then
			local q = Clamp(t / 0.45)
			local g = q < 0.3 and 0.2 + 1.05 * Out(q / 0.3) or 1.25 - 0.75 * (q - 0.3) / 0.7
			local x = G.al + (G.ar - G.al) * (i + 0.5) / p.n + cur.ox
			local s = p.size * G.k * g
			n = Put(f, n, file, x, y, s, s, a * (1 - q), q * 0.6, tint)
		end
	end
	return n
end

-- the bars flaring (the top of their box: the health bar's)
function DRAW.barflash(f, n, p, v, a)
	local y0 = G.at - (G.at - G.ab) * 0.6
	local w, h = G.ar - G.al, G.at - y0
	return Put(f, n, "glow_white", (G.al + G.ar) / 2 + cur.ox, (y0 + G.at) / 2 + cur.oy, w * 1.15, h * 2.2, a, 0, Col(p.c))
end

-- a band of light across the whole plate -- the name's strip and the bars -- from the portrait's side to its far end
function DRAW.sheen(f, n, p, v, a)
	local k = G.k
	local l, r = G.pl + cur.ox, G.pr + cur.ox
	Sweep("plateSweep", l, G.pb + cur.oy, r, G.pt + cur.oy, l - 12 * k + (r - l + 24 * k) * v, 16 * k,
		(G.pt - G.pb) * 2.2, a, -0.3)
	return n
end

--------------------------------------------------------------------------------
-- (1.2.4) A frame outlined: the mouseover highlight on the party and raid frames (MelloUI.FrameHover; retail's pick
-- "B", the user, 2026-10-25, here in the modern look's crisp lines -- the user, 2026-10-26: "The mouseover
-- highlighting should also be imported into the forever addon"): white next to the frame, the colour outside it, each
-- line half a sketch pixel and at least one screen pixel; round on the portrait (outline_round, the colour's line, and
-- outline_edge, the white one: a circle's two lines at its picture's edge -- Tools/make_icons.py), straight along the
-- plate, open on the ring's side; a cell with no portrait its box all round
--------------------------------------------------------------------------------

local hovered = {}                 -- (the outlined frame's shape)
local OUTLINE = { line = 0.5, min = 0 }

-- `frame`'s shape into S (Fill's fields): FX.Split's ring and plate (a frame with no picture of one: the bars' box and
-- the name over them), else its own box. A mirrored party frame (Flip Horizontally) read the game's way round, S.mx its
-- middle (Put turns its sprites back)
local function ShapeOf(frame, S)
	S.mx, S.orb, S.kit = nil, nil, nil
	local sp = FX.Split(frame)
	if sp then
		S.orb, S.kit = sp.orb, sp.kit   -- (its level badge, the region: FrameHalo's glow round it; the kit's frame)
		local pl, pb, pr, pt = sp.pl, sp.pb, sp.pr, sp.pt
		if not pl then
			pl, pb, pr, pt = sp.bl, sp.bb, sp.br, max(sp.bt, NameTop(frame) or sp.bt)
		end
		if sp.rl and sp.rl + sp.rr > pl + pr then
			local m2 = min(pl, sp.rl) + max(pr, sp.rr)
			Fill(S, m2 - sp.rr, sp.rb, m2 - sp.rl, sp.rt, m2 - sp.br, sp.bb, m2 - sp.bl, sp.bt, m2 - pr, pb, m2 - pl, pt)
			S.mx = m2 / 2
		else
			Fill(S, sp.rl, sp.rb, sp.rr, sp.rt, sp.bl, sp.bb, sp.br, sp.bt, pl, pb, pr, pt)
		end
		return true
	end
	local l, b, r, t = FX.Rect(frame)
	if not l then
		return false
	end
	Fill(S, nil, nil, nil, nil, l, b, r, t, l, b, r, t)
	return true
end

-- S as it stands on the screen (a mirrored one turned back: the highlight's glow is laid by it)
local function Unmirror(S)
	local m = S.mx
	if not m then
		return
	end
	local m2 = 2 * m
	if S.rx then
		S.rx = m2 - S.rx
	end
	S.al, S.ar = m2 - S.ar, m2 - S.al
	S.pl, S.pr = m2 - S.pr, m2 - S.pl
	S.l, S.r = m2 - S.r, m2 - S.l
	S.x = m2 - S.x
	S.mx = nil
end

-- a crisp bar, (x0, y0) .. (x1, y1), tinted `rgb` (white)
local function Bar(f, n, x0, y0, x1, y1, rgb)
	return Put(f, n, WHITE8, (x0 + x1) / 2, (y0 + y1) / 2, abs(x1 - x0), abs(y1 - y0), 1, 0, rgb, false)
end

-- the outline's sprites from n: its two lines just outside the frame (the colour's outside, white in)
local function OutlineOf(f, n, S, rgb)
	local px = max(OUTLINE.line * S.k, OUTLINE.min)
	local pad = 2 * px
	local yb, yt, xr = S.pb - pad, S.pt + pad, S.pr + pad
	local xl = S.pl - pad
	if S.rr then
		local cx, cy = S.rx, S.ry
		local rad = S.rr + pad
		local top, bot = cy + rad, cy - rad
		local ct, cb = min(yt, top), max(yb, bot)
		local d = max(abs(ct - cy), abs(cb - cy))
		local xc = cx + sqrt(max(0, rad * rad - d * d))
		-- (a piece of the circle's pictures: rows y0 .. y1, columns from its left to x1)
		for i = 1, 3 do
			local y0, y1, x1 = ct, top, cx + rad
			if i == 2 then
				y0, y1, x1 = cb, ct, xc
			elseif i == 3 then
				y0, y1, x1 = bot, cb, cx + rad
			end
			if y1 - y0 >= 0.5 and x1 > cx - rad then
				local x0 = cx - rad
				local u1 = (x1 - x0) / (2 * rad)
				local v0, v1 = (top - y1) / (2 * rad), (top - y0) / (2 * rad)
				local mx, my, w, h = (x0 + x1) / 2, (y0 + y1) / 2, x1 - x0, y1 - y0
				n = Put(f, n, "outline_round", mx, my, w, h, 1, 0, rgb, false, 0, u1, v0, v1)
				n = Put(f, n, "outline_edge", mx, my, w, h, 1, 0, nil, false, 0, u1, v0, v1)
			end
		end
		xl = xc
	end
	local openL = S.rr ~= nil
	if xr - xl < 1 then
		return n
	end
	-- the outer line in the colour: top, bottom, right (and left on a frame with no ring)
	n = Bar(f, n, xl, yt - px, xr, yt, rgb)
	n = Bar(f, n, xl, yb, xr, yb + px, rgb)
	n = Bar(f, n, xr - px, yb, xr, yt, rgb)
	if not openL then
		n = Bar(f, n, xl, yb, xl + px, yt, rgb)
	end
	-- the white one a line in
	local inL = openL and xl or xl + px
	n = Bar(f, n, inL, yt - 2 * px, xr - px, yt - px)
	n = Bar(f, n, inL, yb + px, xr - px, yb + 2 * px)
	n = Bar(f, n, xr - 2 * px, yb + px, xr - px, yt - px)
	if not openL then
		n = Bar(f, n, xl + px, yb + px, xl + 2 * px, yt - px)
	end
	return n
end

-- (1.2.4: MelloUI.FrameHalo) `frame`'s shape as it stands on the screen -- ShapeOf's fields, `orb` its level badge --
-- (read it at once: reused), or nil. The painted kit's frame (Oldschool) has no plate round its name -- the name lies
-- on the stone over the bars' bracket -- so its plate is the bars' box (the halo's band round the art, not the stone),
-- its ring-side end run in under the ring (the bracket stops short of the ring: no end of the band in the gap)
local onScreen = {}
function FX.Shape(frame)
	if frame and ShapeOf(frame, onScreen) then
		Unmirror(onScreen)
		local S = onScreen
		if S.kit and S.al then
			S.pl, S.pb, S.pr, S.pt = S.al, S.ab, S.ar, S.at
			if S.rx and S.rx < S.pl then
				S.pl = S.rx
			elseif S.rx and S.rx > S.pr then
				S.pr = S.rx
			end
		end
		return S
	end
	return nil
end

-- `frame`'s outline on `f` (its sprites its own), `rgb` outside (white); `frame` nil: hidden. -> its shape as it stands
-- on the screen (read it at once: reused), or nil
function FX.Outline(f, frame, rgb)
	if frame and ShapeOf(frame, hovered) then
		local size = rawget(_G, "GetPhysicalScreenSize")
		local ph = 0
		if size then
			local _, h = size()
			ph = Num(h) or 0
		end
		local scale = UIParent:GetEffectiveScale()
		OUTLINE.min = (ph > 0 and scale > 0) and 768 / ph / scale or 1   -- (one screen pixel; none to read: a unit)
		local was = mirror
		mirror = hovered.mx
		HideFrom(f, OutlineOf(f, 1, hovered, rgb or WHITE))
		mirror = was
		Unmirror(hovered)
		return hovered
	end
	HideFrom(f, 1)
	return nil
end

--------------------------------------------------------------------------------
-- What the engine calls (LandStep, Clear: Core/FrameFX.lua)
--------------------------------------------------------------------------------

-- a step of a bold landing on `layer` (S its state, B its box -- a split frame's bars half --, t s in): the frame read,
-- the boards laid (as it starts), the shake
function Bold.Begin(layer, S, B, t, list)
	local board = BoardOf(layer)
	cur.board, cur.no, cur.nu = board, 1, 1
	cur.plateSweep, cur.barrierSweep = false, false
	cur.look = LOOKS[S.look] or LOOKS.holy
	-- (a new landing: the frame's name read once -- the plate's top on a frame with no picture of one)
	if board.list ~= list or board.frame ~= S.frame then
		board.nameTop = (B.rl and not B.pl) and NameTop(S.frame) or nil
	end
	G.mx = nil
	if B.pl and B.rl and B.rl + B.rr > B.pl + B.pr then
		-- (1.2.4: a mirrored party frame -- Unit Frames' Flip Horizontally, its ring right of its plate -- read across
		-- the middle of its whole, the game's way round: every part drawn on it as on any frame, each sprite turned
		-- back as it is put -- Put, Sweep. Its whole stays where it is: the boards' room the same)
		local axis = (min(B.pl, B.rl) + max(B.pr, B.rr)) / 2
		local m2 = 2 * axis
		Fill(G, m2 - B.rr, B.rb, m2 - B.rl, B.rt, m2 - B.r, B.b, m2 - B.l, B.t, m2 - B.pr, B.pb, m2 - B.pl, B.pt)
		G.mx = axis
	elseif B.pl then
		Fill(G, B.rl, B.rb, B.rr, B.rt, B.l, B.b, B.r, B.t, B.pl, B.pb, B.pr, B.pt)
	else
		-- (no picture with a plate: the bars' box and the name over them)
		Fill(G, B.rl, B.rb, B.rr, B.rt, B.l, B.b, B.r, B.t, B.l, B.b, B.r, max(B.t, board.nameTop or B.t))
	end
	mirror = G.mx
	-- (a new landing: the boards laid -- in a raid its cell's room only, else past its sides; under the unit's frame)
	if board.list ~= list or board.frame ~= S.frame then
		board.list, board.frame = list, S.frame
		local over, under = board.over, board.under
		over:SetFrameLevel(layer:GetFrameLevel() + 30)
		local raid = Text(S.unit) and Text(S.unit):find("^raid") ~= nil
		over:SetClipsChildren(raid)
		board.clips = raid   -- (the tests')
		over:ClearAllPoints()
		local mx, my = raid and G.w * 0.1 or G.w * 2, raid and G.h * 0.1 or G.h * 3
		over:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", G.l - mx, G.b - my)
		over:SetSize(max(1, G.w + 2 * mx), max(1, G.h + 2 * my))
		over:Show()
		local frame = S.frame
		local strata, level = "LOW", 1
		if type(frame) == "table" then
			local okS, s = pcall(frame.GetFrameStrata, frame)
			local okL, lv = pcall(frame.GetFrameLevel, frame)
			strata = okS and Text(s) or strata
			level = okL and Num(lv) or level
		end
		local below = STRATA_BELOW[strata]
		if below then
			under:SetFrameStrata(below)
			under:SetFrameLevel(1)
		else
			under:SetFrameStrata(strata)
			under:SetFrameLevel(max(0, level - 1))
		end
		under:SetAllPoints(over)
		under:SetClipsChildren(raid)
		-- (the frame's own picture, for its afterimages: Unit Frames' M:PlateOf)
		cur.pic = nil
		local panel = MelloUI:GetModule("UnitFrames")
		if panel and panel.PlateOf and type(frame) == "table" then
			local ok, pic = pcall(panel.PlateOf, panel, frame)
			if ok and pic then
				local pl, pb, pr, pt = FX.Rect(pic)
				if pl then
					cur.pic, cur.picL, cur.picB, cur.picR, cur.picT = pic, pl, pb, pr, pt
				end
			end
		end
		board.pic, board.picL, board.picB, board.picR, board.picT = cur.pic, cur.picL, cur.picB, cur.picR, cur.picT
	else
		cur.pic, cur.picL, cur.picB, cur.picR, cur.picT = board.pic, board.picL, board.picB, board.picR, board.picT
	end
	-- the shake: the light jolted every 35 ms, dying away
	cur.ox, cur.oy = 0, 0
	for _, part in ipairs(list) do
		if part[1] == "shake" and t >= part.t0 and t <= part.t1 then
			local amp = part.amp * (1 - (t - part.t0) / (part.t1 - part.t0)) * G.k
			local side = floor(t / 0.035) % 2 == 1 and 1 or -1
			cur.ox, cur.oy = side * amp, -side * amp * 0.5
		end
	end
end

function Bold.Draw(part, v, a, lt, span)
	local fn = DRAW[part[1]]
	local board = cur.board
	if not (fn and board) then
		return
	end
	if part.under then
		if not board.under:IsShown() then
			board.under:Show()
		end
		cur.nu = fn(board.under, cur.nu, part, v, a, lt, span)
	else
		cur.no = fn(board.over, cur.no, part, v, a, lt, span)
	end
end

local function HideSweeps(board, keepPlate, keepBarrier)
	if board.plateSweep and not keepPlate then
		board.plateSweep:Hide()
	end
	if board.barrierSweep and not keepBarrier then
		board.barrierSweep:Hide()
	end
end

function Bold.End(layer)
	local board = boards[layer]
	if board then
		HideFrom(board.over, cur.no)
		HideFrom(board.under, cur.nu)
		HideSweeps(board, cur.plateSweep, cur.barrierSweep)
		if cur.nu == 1 then
			board.under:Hide()
		end
	end
	cur.board = nil
end

function Bold.Clear(layer)
	local board = boards[layer]
	if board then
		HideFrom(board.over, 1)
		HideFrom(board.under, 1)
		HideSweeps(board, false, false)
		board.under:Hide()
		board.list, board.frame, board.pic = nil, nil, nil
	end
end

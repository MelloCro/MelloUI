--------------------------------------------------------------------------------
-- MelloUI - Config motion (1.2.4; docs/plans/configurator-shell.md -- the user's picks of 2026-10-27)
--
-- What moves over the configurator's painting while it is open, per look (Kit:OwnWindow's opts.painting, the look
-- on show), each piece a place of the painting lit or turned, never a new shape over it:
--   Modern     Fiery lines    a slow, uneven flame along the painted lines -- three flame strips under each line
--                             moving apart at unrelated speeds -- and now and then a spark lifting off them
--              Crest ring     the ring's glow flickering like a flame (never a steady pulse)
--              Compass roses  the two painted roses' inner cards turning slowly (once in about three and a third and
--                             four and three quarter minutes, opposite ways: the user, 2026-10-28, "the compas should
--                             spin 100% faster"), their outer rings staying painted; at a page switch
--                             they swing and settle (about four seconds), the next switch the other way
--   Default    Metal glints   now and then a lamp's light running along one of the rails (each 7 to 16 s apart)
--              Ring glint     now and then a glint once round the crest's metal ring (9 to 17 s apart)
--   Oldschool  Candlelight    two warm lights from the corners, flickering unevenly
--              Smouldering cracks  the painting's own ember-lit cracks glowing up and fading, a patch at a time
--              Embers         a few rising from the stone of the footer and the side column's foot
-- The engine runs it: animation groups, no OnUpdate; a few Lua calls a second at most (a spark or an ember moved to
-- where it starts again, a glint's next wait). Made at the look's first show (Media/Textures/Configurator, baked by
-- Tools/make_configurator_motion.py), played while the window is open, stopped and hidden when it closes or the look
-- changes. Reduce Motion (MelloUI.Anim) keeps the painting still: nothing shown. Every piece is a region of the window
-- itself, just over the painting (SUB): no frame of its own, nothing past the window's edge.
--
--   MelloUI.ConfigMotion:Show(window, look)   the look's motion shown and played (another look's stopped)
--   MelloUI.ConfigMotion:Hide()               every piece stopped and hidden
--   MelloUI.ConfigMotion:Refresh()            Reduce Motion read again (a setting changed while it is open)
--   MelloUI.ConfigMotion:Swing()              a page switch: the roses swing and settle
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Config motion")
local C_Timer = Perf.C_Timer
local random, pi = math.random, math.pi

-- a group of the one system's (MelloUI.Anim:Group: made there, played through PlayGroup)
local function Group(region, looping, template)
	return MelloUI.Anim:Group(region, looping, template)
end

local M = { layers = {}, look = nil, window = nil, token = 0 }
MelloUI.ConfigMotion = M

local TEX = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Configurator\\"
local WHITE = "Interface\\Buttons\\WHITE8X8"
-- The pieces are the window's OWN regions, in its BACKGROUND layer over the painting (Modules/KitWindow.lua's ground,
-- sublevel -7): a frame's regions draw before every child frame of it, so the motion lies over the painting and under
-- every part of the window, always. (1.2.4: the first build's frames at the window's level -- even using their
-- parent's level -- were drawn under the painting in game, and the motion never showed.) Each kind's sublevel, upwards:
-- under (the roses' cards, the candles), light (the flames, the glints, the cracks), glow (the crest ring's), spark
local SUB = { under = -6, light = -5, glow = -4, spark = -3 }
-- each look's places on its painting, in UI units from the window's top left (y down), as measured on the paintings
-- (the sketch's: patch_motion_v3.py, patch_motion_skins.py)
local G = {
	modern = {
		-- the painted lines: under the header, down the side column, over the footer, under the crest; w: their weight
		lines = { { x0 = 263, y0 = 148, x1 = 1140, y1 = 148, w = 1 }, { x0 = 260, y0 = 0, x1 = 260, y1 = 760, w = 0.6 },
			{ x0 = 263, y0 = 696, x1 = 1140, y1 = 696, w = 0.55 }, { x0 = 10, y0 = 111, x1 = 250, y1 = 111, w = 0.9 } },
		ring = { x = 55, y = 55, size = 96 },
		-- the roses' cards: their centre and size, a turn's seconds and its way (-1 clockwise), their share of the
		-- swing at a page switch (the second the other way, at 0.8: the sketch's)
		cards = { { x = 1067, y = 78, size = 122, turn = 200, way = -1, swing = -1, file = "Card1_Modern" },
			{ x = 28, y = 605, size = 176, turn = 285, way = 1, swing = 0.8, file = "Card2_Modern" } },
	},
	default = {
		rails = { { x0 = 266, y0 = 137, x1 = 1140, y1 = 137 }, { x0 = 261, y0 = 0, x1 = 261, y1 = 760 },
			{ x0 = 266, y0 = 677, x1 = 1140, y1 = 677 }, { x0 = 6, y0 = 106, x1 = 258, y1 = 106 } },
		ring = { x = 55, y = 55, size = 100 },
	},
	oldschool = {
		candles = { { x = -40, y = -40, size = 1120, alpha = 0.22 }, { x = 1180, y = 800, size = 1200, alpha = 0.17 } },
		-- the cracks' patches: a centre each (the sketch's drifting blobs, where the cracks are)
		patches = { { 120, 130 }, { 60, 480 }, { 400, 60 }, { 980, 70 }, { 700, 730 }, { 190, 700 }, { 1050, 720 } },
		embers = 14,
	},
}
-- the flame strips (Flame.tga's three rows): each tile drawn TILE wide, BAND high, at its alpha (times the line's
-- weight), moving SPEED UI units a second (a minus: the other way)
local TILE, BAND = 600, 24
local STRIPS = { { row = 0, alpha = 0.30, speed = 62 }, { row = 1, alpha = 0.22, speed = -40 },
	{ row = 2, alpha = 0.16, speed = 34 } }
-- the crest ring's flicker: its alpha at each step and the seconds to it (uneven, so it never pulses)
local FLICKER = { 0.28, 0.38, 0.24, 0.41, 0.30, 0.36, 0.22, 0.33 }
local FLICKER_T = { 0.35, 0.5, 0.27, 0.6, 0.4, 0.3, 0.55, 0.45 }
-- a candle's flicker: its light's share at each step (of the candle's own alpha) and the seconds to it
local CANDLE = { 0.80, 0.92, 0.74, 0.95, 0.83, 0.88, 0.70, 0.90, 0.78 }
local CANDLE_T = { 0.6, 0.45, 0.8, 0.5, 0.7, 0.4, 0.65, 0.55, 0.5 }

-- a look's pieces (Layer): the window's regions it made, shown and hidden together, and the groups it plays while shown
local Pieces = {}
Pieces.__index = Pieces

function Pieces:IsShown()
	return self.shown == true
end

-- a piece of the look: a region of the window at its kind's sublevel, hidden until the look shows
local function Piece(layer, sublevel)
	local t = layer.window:CreateTexture(nil, "BACKGROUND", nil, sublevel)
	t:Hide()
	layer.regions[#layer.regions + 1] = t
	return t
end

-- a light of the look (added to the painting)
local function Tex(layer, file, sublevel)
	local t = Piece(layer, sublevel)
	t:SetTexture(TEX .. file .. ".tga")
	t:SetBlendMode("ADD")
	t:SetAlpha(0)   -- (only its animations show it: stopped, it is gone)
	return t
end

local function Fade(g, from, to, dur, order, delay, smooth)
	local a = g:CreateAnimation("Alpha")
	a:SetFromAlpha(from)
	a:SetToAlpha(to)
	a:SetDuration(dur)
	a:SetOrder(order or 1)
	if delay then
		a:SetStartDelay(delay)
	end
	if smooth then
		a:SetSmoothing(smooth)
	end
	return a
end

-- a region's centre at x, y of the window (UI units from its top left, y down)
local function At(region, parent, x, y)
	region:ClearAllPoints()
	region:SetPoint("CENTER", parent, "TOPLEFT", x, -y)
end

-- Nothing past the window's edge (no frame clips the window's own regions):
-- a still piece centred past it (the candles' lights) laid on its part inside the window only, its texture cut to match
local function Inside(layer, t, x, y, size)
	local W, H = layer.window:GetSize()
	local l, top = x - size / 2, y - size / 2
	local x0, x1 = math.max(l, 0), math.min(l + size, W)
	local y0, y1 = math.max(top, 0), math.min(top + size, H)
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", layer.window, "TOPLEFT", x0, -y0)
	t:SetSize(x1 - x0, y1 - y0)
	t:SetTexCoord((x0 - l) / size, (x1 - l) / size, (y0 - top) / size, (y1 - top) / size)
end

-- a piece that turns across the edge (the side column's rose) cut there by a mask of the plain white texture (the
-- masks MelloUI's bars wear in game): its edge dims over a sixteenth of the mask's size each way, so the mask is laid
-- with the dimming ending AT the window's edge on a side it cuts (nothing past it) and the piece whole on the others.
-- One axis: the span a .. b kept (the piece's, cut to the window), lo / hi true where the window cuts it -> the mask's
local function Span(a, b, lo, hi)
	local w = (b - a) / (1 - ((lo and -1 or 1) + (hi and -1 or 1)) / 16)
	local r = w / 16
	return a + (lo and r or -r), b + (hi and -r or r)
end

local function CutAtEdge(layer, t, x, y, size)
	local W, H = layer.window:GetSize()
	local l, r, top, bottom = x - size / 2, x + size / 2, y - size / 2, y + size / 2
	if l >= 0 and r <= W and top >= 0 and bottom <= H then
		return   -- (inside: nothing to cut)
	end
	local x0, x1 = Span(math.max(l, 0), math.min(r, W), l < 0, r > W)
	local y0, y1 = Span(math.max(top, 0), math.min(bottom, H), top < 0, bottom > H)
	local mask = layer.window:CreateMaskTexture()
	mask:SetTexture(WHITE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetPoint("TOPLEFT", layer.window, "TOPLEFT", x0, -y0)
	mask:SetPoint("BOTTOMRIGHT", layer.window, "TOPLEFT", x1, -y1)
	t:AddMaskTexture(mask)
end

-- the groups a layer plays while shown; a few wait on a timer of their own between runs (start)
local function Keep(layer, group, start)
	layer.groups[#layer.groups + 1] = { group = group, start = start }
end

--------------------------------------------------------------------------------
-- Modern
--------------------------------------------------------------------------------

-- the flame's run, its picture a tile through the strip each run, on along the line (right, or down: the picture's u
-- falls under a still point) or back: a TextureCoordTranslation, a kind the client makes only from XML (retail 12.1.5
-- hands a plain Animation, no SetOffset, for it from Lua: 1.2.4) -- Core/ConfigMotion.xml's groups, their seconds set
-- here. Without them (a client not restarted since the file came) the strip lies still: never an error
local RUN = { on = "MelloUIConfigFlameOn", back = "MelloUIConfigFlameBack" }

-- three flame strips under a line, moving apart: each strip lies on the line and its picture runs through it (as the
-- game's own anima links): the strip never leaves the line
local function FlameLine(layer, L)
	local window = layer.window
	local vertical = L.x0 == L.x1
	local len = vertical and (L.y1 - L.y0) or (L.x1 - L.x0)
	local reps = len / TILE
	for _, S in ipairs(STRIPS) do
		local t = Tex(layer, "Flame", SUB.light)
		t:SetTexture(TEX .. "Flame.tga", "REPEAT", "CLAMP")
		local v0, v1 = S.row / 4, (S.row + 1) / 4
		if vertical then
			t:SetSize(BAND, len)
			t:SetPoint("TOPLEFT", window, "TOPLEFT", L.x0 - BAND / 2, -L.y0)
			-- (turned: the strip's length down the line)
			t:SetTexCoord(0, v0, reps, v0, 0, v1, reps, v1)
		else
			t:SetSize(len, BAND)
			t:SetPoint("TOPLEFT", window, "TOPLEFT", L.x0, -(L.y0 - BAND / 2))
			t:SetTexCoord(0, reps, v0, v1)
		end
		local g = Group(t, "REPEAT", S.speed > 0 and RUN.on or RUN.back)
		local run = g.run
		if run then
			run:SetDuration(TILE / math.abs(S.speed))
		end
		local a = S.alpha * L.w
		Fade(g, a, a, TILE / math.abs(S.speed))
		Keep(layer, g)
	end
end

-- a spark: lifts off a horizontal line, fades; where it starts again is picked at each loop (its own half inside the
-- line's ends: never past the window's edge)
local function Spark_OnLoop(g)
	local s = g.melloSpark
	local L = s.lines[random(#s.lines)]
	At(s.tex, s.window, L.x0 + s.half + random() * (L.x1 - L.x0 - 2 * s.half), L.y0)
end

local function Sparks(layer, lines)
	local flat = {}
	for _, L in ipairs(lines) do
		if L.y0 == L.y1 then
			flat[#flat + 1] = L
		end
	end
	for i = 1, 8 do
		local t = Tex(layer, "Glow", SUB.spark)
		local r = 0.9 + random() * 1.1
		t:SetSize(r * 8, r * 8)
		local g = Group(t, "REPEAT")
		local life = 0.8 + random() * 0.9
		local rise = g:CreateAnimation("Translation")
		rise:SetOffset((random() - 0.5) * 10, 14 + random() * 20)
		rise:SetDuration(life)
		rise:SetSmoothing("OUT")
		Fade(g, 0, 0.9, life * 0.15)
		Fade(g, 0.9, 0, life * 0.85, 1, life * 0.15)
		-- (a wait between sparks: the group's last part, nothing shown)
		Fade(g, 0, 0, 0.6 + random() * 2.4, 2)
		g.melloSpark = { tex = t, window = layer.window, lines = flat, half = r * 4 }
		g:SetScript("OnLoop", Spark_OnLoop)
		Spark_OnLoop(g)
		Keep(layer, g, i * 0.35)
	end
end

local function Flicker(layer, g, values, times, scale)
	g:SetLooping("REPEAT")
	for i = 1, #values do
		local nextValue = values[i % #values + 1]
		Fade(g, values[i] * scale, nextValue * scale, times[i], i, nil, "IN_OUT")
	end
	Keep(layer, g)
end

-- the roses' swing at a page switch (the sketch's: 24 degrees times e^(-1.4 s) times sin(5.2 s), over four seconds): the
-- curve's turning points as engine steps -- each step's turn (degrees, from the last point) and its seconds -- ending
-- where it began, so the group's end puts nothing back. A card swings `swing` of it (the second rose the other way, at
-- 0.8); each switch the other way round from the last
local SWING_TURN = { 16.29, -23.28, 9.99, -4.29, 1.84, -0.79, 0.24 }
local SWING_T = { 0.25, 0.60, 0.60, 0.60, 0.60, 0.60, 0.73 }

local function SwingGroup(layer, card, share)
	local g = Group(card)
	g.melloTurns = {}
	for i, deg in ipairs(SWING_TURN) do
		local step = g:CreateAnimation("Rotation")
		step:SetDegrees(deg * share)
		step:SetDuration(SWING_T[i])
		step:SetOrder(i)
		step:SetSmoothing(i == 1 and "OUT" or "IN_OUT")
		g.melloTurns[i] = step
	end
	g.melloShare = share
	layer.swings[#layer.swings + 1] = g
end

local function BuildModern(layer, P)
	local window = layer.window
	for _, L in ipairs(P.lines) do
		FlameLine(layer, L)
	end
	Sparks(layer, P.lines)
	local ring = Tex(layer, "RingGlow", SUB.glow)
	ring:SetSize(P.ring.size, P.ring.size)
	At(ring, window, P.ring.x, P.ring.y)
	Flicker(layer, Group(ring), FLICKER, FLICKER_T, 1)
	for _, C in ipairs(P.cards) do
		local card = Piece(layer, SUB.under)
		card:SetTexture(TEX .. C.file .. ".tga")
		card:SetSize(C.size, C.size)
		At(card, window, C.x, C.y)
		CutAtEdge(layer, card, C.x, C.y, C.size)
		local g = Group(card, "REPEAT")
		local turn = g:CreateAnimation("Rotation")
		turn:SetDegrees(360 * C.way)
		turn:SetDuration(C.turn)
		Keep(layer, g)
		-- (a second group on the same card: the engine adds its turn to the slow one's)
		SwingGroup(layer, card, C.swing)
	end
end

--------------------------------------------------------------------------------
-- Default
--------------------------------------------------------------------------------

-- a lamp's light along a rail: once, then a wait of 7 to 16 s (a timer of the layer's session) before the next
local function Glint_OnFinished(g)
	local layer = g.melloLayer
	if layer:IsShown() then
		local token = M.token
		C_Timer.After(7 + random() * 9, function()
			if M.token == token and layer:IsShown() then
				g:Play()
			end
		end)
	end
end

-- the lamp's light: a streak STREAK long, its run inside the rail's ends by its own half (the light never leaves the
-- rail, nor the window)
local STREAK = 96

local function Glints(layer, P)
	local window = layer.window
	for i, R in ipairs(P.rails) do
		local vertical = R.x0 == R.x1
		local t = Tex(layer, "Streak", SUB.light)
		t:SetSize(STREAK, 10)
		if vertical then
			t:SetRotation(pi / 2)
		end
		local inX, inY = vertical and 0 or STREAK / 2, vertical and STREAK / 2 or 0
		At(t, window, R.x0 + inX, R.y0 + inY)
		local g = Group(t)
		local run = g:CreateAnimation("Translation")
		run:SetOffset(R.x1 - R.x0 - 2 * inX, R.y0 - R.y1 + 2 * inY)
		run:SetDuration(1.5)
		run:SetSmoothing("IN_OUT")
		Fade(g, 0, 0.85, 0.75, 1, nil, "OUT")
		Fade(g, 0.85, 0, 0.75, 1, 0.75, "IN")
		g.melloLayer = layer
		g:SetScript("OnFinished", Glint_OnFinished)
		Keep(layer, g, 1.5 + (i - 1) * 2.3)
	end
	local ring = Tex(layer, "RingGlint", SUB.glow)
	ring:SetSize(P.ring.size, P.ring.size)
	At(ring, window, P.ring.x, P.ring.y)
	local g = Group(ring)
	local turn = g:CreateAnimation("Rotation")
	turn:SetDegrees(-360)
	turn:SetDuration(1.8)
	turn:SetSmoothing("IN_OUT")
	Fade(g, 0, 0.9, 0.9, 1, nil, "OUT")
	Fade(g, 0.9, 0, 0.9, 1, 0.9, "IN")
	g.melloLayer = layer
	g:SetScript("OnFinished", Glint_OnFinished)
	Keep(layer, g, 4)
end

--------------------------------------------------------------------------------
-- Oldschool
--------------------------------------------------------------------------------

-- an ember: rises from the window's foot (its own half above the edge), fades; where it starts again is picked at
-- each loop
local function Ember_OnLoop(g)
	local e = g.melloEmber
	local side = random() < 0.35
	At(e.tex, e.window, side and (20 + random() * 220) or (280 + random() * 840), e.foot)
end

local function BuildOldschool(layer, P)
	local window = layer.window
	for _, C in ipairs(P.candles) do
		local t = Tex(layer, "Candle", SUB.under)
		Inside(layer, t, C.x, C.y, C.size)
		Flicker(layer, Group(t), CANDLE, CANDLE_T, C.alpha)
	end
	for i, at in ipairs(P.patches) do
		local t = Tex(layer, "Cracks_Oldschool", SUB.light)
		t:SetAllPoints(window)
		t:SetTexCoord(0, 0.75, 0, 1)
		local mask = window:CreateMaskTexture()
		mask:SetTexture(TEX .. "PatchMask.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetSize(460, 460)
		At(mask, window, at[1], at[2])
		t:AddMaskTexture(mask)
		-- (glowing up and fading, each patch at its own pace: 11 to 17 s)
		local period = 11 + (i * 0.97) % 6
		local g = Group(t, "REPEAT")
		Fade(g, 0.1, 0.95, period / 2, 1, nil, "IN_OUT")
		Fade(g, 0.95, 0.1, period / 2, 2, nil, "IN_OUT")
		Keep(layer, g, (i - 1) * 1.3)
	end
	local _, H = window:GetSize()
	for i = 1, P.embers do
		local t = Tex(layer, "Glow", SUB.spark)
		local r = 1.2 + random() * 1.3
		t:SetSize(r * 8, r * 8)
		local g = Group(t, "REPEAT")
		local life = 2.6 + random() * 2
		local rise = g:CreateAnimation("Translation")
		rise:SetOffset((random() - 0.5) * 18, (16 + random() * 18) * life)
		rise:SetDuration(life)
		Fade(g, 0, 1, 0.5)
		Fade(g, 1, 0, 0.8, 1, life - 0.8)
		g.melloEmber = { tex = t, window = window, foot = H - r * 4 }
		g:SetScript("OnLoop", Ember_OnLoop)
		Ember_OnLoop(g)
		Keep(layer, g, (i - 1) * 0.33)
	end
end

--------------------------------------------------------------------------------
-- Showing
--------------------------------------------------------------------------------

local BUILD = { modern = BuildModern, oldschool = BuildOldschool }

-- the look's pieces, made at its first show: regions of the window over the painting, under every part of the window
-- (SUB)
local function Layer(window, look)
	local layer = M.layers[look]
	if layer then
		return layer
	end
	layer = setmetatable({ window = window, regions = {}, groups = {}, swings = {}, shown = false }, Pieces)
	local P = G[look]
	if look == "default" then
		Glints(layer, P)
	else
		BUILD[look](layer, P)
	end
	M.layers[look] = layer
	return layer
end

local function Stop(layer)
	layer.shown = false
	for _, k in ipairs(layer.groups) do
		MelloUI.Anim:StopGroup(k.group)
	end
	for _, g in ipairs(layer.swings) do
		MelloUI.Anim:StopGroup(g)
	end
	for _, t in ipairs(layer.regions) do
		t:Hide()
	end
end

local function Start(layer)
	layer.shown = true
	for _, t in ipairs(layer.regions) do
		t:Show()
	end
	local token = M.token
	for _, k in ipairs(layer.groups) do
		if k.start then
			C_Timer.After(k.start, function()
				if M.token == token and layer:IsShown() then
					MelloUI.Anim:PlayGroup(k.group)
				end
			end)
		else
			MelloUI.Anim:PlayGroup(k.group)
		end
	end
end

function M:Show(window, look)
	if not G[look] then
		look = "modern"
	end
	self.window = window
	if self.look == look and self.layers[look] and self.layers[look]:IsShown() then
		return
	end
	self:Hide()
	self.look = look
	if MelloUI.Anim.reduceMotion then
		return   -- (Reduce Motion: the painting still, nothing made)
	end
	Start(Layer(window, look))
end

-- a page switch: the roses swing and settle (Modern's; the other looks have none), each switch the other way round;
-- a switch while they swing starts it again from where the slow turn is (the sketch's). Reduce Motion: no swing
function M:Swing()
	local layer = self.look and self.layers[self.look]
	if not (layer and layer:IsShown() and layer.swings[1]) then
		return
	end
	self.swingWay = -(self.swingWay or -1)
	for _, g in ipairs(layer.swings) do
		g:Stop()
		for i, step in ipairs(g.melloTurns) do
			step:SetDegrees(SWING_TURN[i] * g.melloShare * self.swingWay)
		end
		MelloUI.Anim:PlayGroup(g)
	end
end

function M:Hide()
	self.token = self.token + 1   -- (every wait of the session before ends quietly)
	for _, layer in pairs(self.layers) do
		if layer:IsShown() then
			Stop(layer)
		end
	end
end

function M:Refresh()
	local window, look = self.window, self.look
	if not (window and look and window:IsShown()) then
		return
	end
	local layer = self.layers[look]
	local shown = layer ~= nil and layer:IsShown()
	if MelloUI.Anim.reduceMotion and shown then
		self:Hide()
	elseif not MelloUI.Anim.reduceMotion and not shown then
		self.look = nil
		self:Show(window, look)
	end
end

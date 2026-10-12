--------------------------------------------------------------------------------
-- MelloUI - Personal Display (0.21.0; docs/plans/personal-display.md)
--
-- Legion's resource display under your character, revived (the user, 2026-10-12: "back in Legion, WoW added Personal
-- Resource Display under your character ... revive that feature and also expand on it, to have a cast bar and also a
-- shield bar"; their picks on personal_display_sketch: look A -- the unit frames' gem-capped bracket --, the shield
-- column on the right side of the character, the cast bar only while casting, the animations judged in game first).
-- This client makes no player nameplate (probed in game: C_NamePlate.GetNamePlateForUnit("player") nil, forbidden
-- ones too) and nothing projects the character onto the screen: the display stands where Edit Layout puts it (under
-- the character by default) and hops while you jump (IsFalling, plain).
--   the bars    health and power in the kit's bracket (Kit:Bar), their percent the game's own curve
--               (UnitHealthPercent / UnitPowerPercent with CurveConstants.ScaleTo100: the secret values handed to the
--               font strings, which take them); the cast bar under them while you cast or channel (Anim:Timer: the
--               engine counts it)
--   the shield  an upright column of its own beside the character (Kit:VBar): the total absorb (UnitGetTotalAbsorbs,
--               secret on this client: handed to the bars) against the amount it went up with, the engine's smooth
--               fill rising and draining, a pale bar of the part lost; its light (MelloUI.FrameFX's "shield" look)
--               at its events only: applied, a hit, low (only while the amount reads plain), broken, then faded out
--               (no repeating pulse: the user, 2026-10-12, "this animation keeps flashing the whole time every few
--               seconds" -- a shield whose end this client keeps secret pulsed on unseen)
-- A plain amount tells it all; a secret one is read from the events around it (an aura added with it: applied, one
-- taken with it: broken, else a hit) -- no feature hung on a secret. /mello personal secrets: what this client hands
-- over plain. Preview (Core/Preview.lua, part "personal"; /mello personal test): a made-up shield and casts on the
-- solo scene's beats. The game's own Personal Resource Display is held off while this is on (its CVar, given back).
-- Nothing at login but the frames it shows (built after the login); its events only while it is on.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Perf = MelloUI.Perf:Scope("MelloUI_PersonalDisplay (Personal Display)")
local hooksecurefunc = Perf.hooksecurefunc
local Secret = MelloUI.Safe.IsSecret
local Num = MelloUI.Safe.Number
local W = MelloUI.Widgets
local Anim = MelloUI.Anim
local FX = MelloUI.FrameFX
local pairs, ipairs, type, pcall = pairs, ipairs, type, pcall

local OWNER = "PersonalDisplay"
local NEW = "0.21.0"
local GAME_CVAR = "nameplateShowSelf"   -- the game's own display (Blizzard_PersonalResourceDisplay's switch)
local PREVIEW_PART = "personal"

-- sizes in UI units (the sketch's, at the game's scale) and the timings
local T = {
	power = 0.7, cast = 0.9,             -- the power and cast fills' heights, shares of the health fill's (Height)
	gap = 1,                             -- between two brackets' painted edges
	colW = 7, colH = 70,                 -- the shield column's fill
	text = 11,                           -- the percents' and the spell's size
	textGap = 3,                         -- the percents past the widest cap
	hop = 12, hopTime = 0.62,            -- the hop when you jump: how high, how long
	jumpCheck = 0.06,                    -- the jump key pressed: airborne this soon after, a jump
	zoomMin = 0.35, zoomMax = 2.5,       -- the zoom's scaling of the display's offset, at most
	zoomNear = 0.5,                      -- (yards) a camera nearer than this counts as this near
	zoomSettle = 0.3, zoomLonger = 4,    -- the zoom followed until it held still this long (s), this long at most
	castFade = 0.2,                      -- the cast bar in and out
	columnFade = 0.25,                   -- the column in
	breakHold = 0.5, breakFade = 0.7,    -- the broken column held, then faded out
	lossDelay = 0.3,                     -- the part lost held pale this long, then drained
	low = 0.3,                           -- (a plain amount) under this share of the amount it went up with: low
	recent = 0.25,                       -- (a secret amount) an aura added or taken this close: applied / broken
	spill = { 6, 5 },                    -- how far the shield's light may reach past the column's fill (its units)
	-- (Heal Light From Your Character) the character's middle: this share of the way from the screen's middle (the
	-- camera's target, about the chest) down to the bars' top (under the feet); the light's size there, scaled with
	-- the zoom as the character is, within its bounds
	stomach = 0.38, charge = 20, chargeMin = 12, chargeMax = 34,
	-- (Swing On The Rails) the sparks' size on the health and power rails (at Height 10, in step with it), how long
	-- after a swing's time with no next one they go, the landing's flash
	glint = 7, glintOff = 5.5, swingGrace = 0.6, landFlash = 0.35,
	-- (the ranged swing on the seam, the user's pick B of prd_ranged) its sparks' size, the aim at a shot's end (Swing
	-- Timers' B.AIM: Auto Shot's last half second, standing still), the aim's red line and its held dimming
	glintRanged = 6, aim = 0.5, aimLine = 1.4, aimHeld = 0.45,
	-- (the shields in parts, the user's pick B of prd_multishield) at most this many parts (more: the one total), their
	-- icons' size beside the column and the gap between them
	partMax = 6, partIcon = 11, partGap = 2,
	-- (Big Cooldowns) the icons above the health bar: their size as made (Big Cooldown Size scales them from it), the
	-- gap between them, how far over the bar's painted top, at most this many; one lasting "until used" with no aura of
	-- it seen, ended after this long
	cdIcon = 16, cdGap = 3, cdLift = 2, cdMax = 4, cdUntilUsed = 30,
	cdLink = 1.5,   -- an aura of a cooldown's kind this soon after its cast: its own (its early end ends it)
}
local TEXT = {
	bars = "Personal Display",
	column = "Shield Column",
	secrets = "Personal Display: what this client hands over",
	plain = "plain",
	secret = "secret",
	none = "nothing",
	failed = "refused (%s)",
}
-- Preview's made-up shield (plain amounts) and casts, on the solo scene's beats (Core/Preview.lua: pull, hit 1..12,
-- kill): the shield up at the pull, drained hit by hit to low, broken at the sixth; a heal cast; a second shield
local SAMPLE = {
	shield = 600,
	-- (the shields in parts) the pull's three -- Power Word: Shield, Ice Barrier, a Greater Fire Protection Potion --
	-- and the second rise's one (Ice Barrier): [spell, amount], spent from the bottom up
	parts = { { 17, 250 }, { 11426, 200 }, { 17543, 150 } }, againParts = { { 11426, 420 } },
	-- (Big Cooldowns) Shield Wall at the pull, Recklessness at the fourth hit, Shield Block at the seventh
	cooldowns = { pull = 871, [4] = 1719, [7] = 2565 },
	hits = { [1] = 470, [2] = 340, [3] = 230, [4] = 150, [5] = 70, [6] = 0, [10] = 260 },
	again = 9, againAmount = 420,
	health = 100, hurt = 4,              -- the health falling this many % a hit
	casts = { pull = { "Power Word: Shield", 1.2 }, [7] = { "Flash Heal", 1.5 } },
	swing = 0.9,                         -- the main hand's swing (the scene's hit spacing), the off hand's twice it
}

local EASE = (Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut) or 1
-- the game's 0..100 curve for a percent (Blizzard_SharedXMLBase's CurveConstants), looked up when asked
local function Curve()
	local c = rawget(_G, "CurveConstants")
	return type(c) == "table" and c.ScaleTo100 or nil
end

local M   -- (the module, registered below)

-- state: the frames (Build), the shield's story, the cast, the events' frame
local S = {
	ui = nil,
	shieldOn = false, low = false, max = nil, value = nil,
	auraAddedAt = 0, auraRemovedAt = 0, absorbAt = 0, lastKind = nil, lastAmount = nil,
	added = {}, shieldIDs = {},   -- the last aura update's added auras (instances), the shield's own (adopted at its rise)
	addedSure = {},               -- ... of them, the ones the client's spell data names shields (ShieldSpells.lua)
	partsOn = false, previewParts = nil,   -- the column in parts (each shield its own); the preview's made-up ones
	-- (Big Cooldowns) the ones up, in the order shown, their icons
	cds = {}, cdOrder = {}, cdIcons = {},
	casting = false, hopping = false, hooked = false, preview = false, previewHealth = nil,
	watching = false,
	reads = { shield = nil, cast = nil, path = {} },   -- what was read plain or secret (/mello personal secrets)
}
local Shield = {}

local function On()
	return M and M.isEnabled and true or false
end

local function Db()
	return M and M.db or {}
end

local function Width()
	local w = Num(Db().width) or 160
	return math.floor(w + 0.5)
end

-- the fills' heights (Height: the health bar's; power and the cast bar their shares of it)
local function Heights()
	local h = Num(Db().height) or 10
	h = math.floor(h + 0.5)
	return h, math.max(3, math.floor(h * T.power + 0.5)), math.max(3, math.floor(h * T.cast + 0.5))
end

local function Paint(bar, key)
	local c = MelloUI.Meaning[key]
	if c then
		bar:SetStatusBarColor(c[1], c[2], c[3])
	end
end

local function Note(path)
	local list = S.reads.path
	list[#list + 1] = path
	if #list > 12 then
		table.remove(list, 1)
	end
end

--------------------------------------------------------------------------------
-- The frames
--------------------------------------------------------------------------------

-- a bracket look's painted rows (bars/<kind>_mid, the Ornate's by default): its opening, the clear rows over and under
-- its painted box
local function Rows(kind)
	local p = MelloUI.Kit:Piece("bars/" .. (kind or "frame") .. "_mid")
	local open, box = p and p.open, p and p.box
	if not (open and box) and kind and kind ~= "frame" then
		return Rows("frame")
	end
	return open and (open[4] - open[2]) or 21, box and box[2] or 14, p and box and (p.h - box[4]) or 10
end

local function StyleText(fs, size)
	MelloUI.Look.Text(fs, "text", size, { area = "unitframes" })
	fs:SetShadowOffset(1, -1)
end

-- a bar's scale for a fill `h` tall in its bracket look, and the caps' solid arms either side of the opening at it (as
-- Kit:Bar sets the fill in)
local function Fit(b, h)
	local Kit = MelloUI.Kit
	local kind = b.kind or "frame"
	b.h = h
	b.scale = h / Rows(kind)
	local capL, capR = Kit:Piece("bars/" .. kind .. "_cap_l"), Kit:Piece("bars/" .. kind .. "_cap_r")
	local armL = capL and capL.open and capL.open[1] * b.scale or b.strip.wl or 0
	local armR = capR and capR.open and (capR.w - capR.open[3]) * b.scale or b.strip.wr or 0
	b.arms = armL + armR
end

-- one bar: the bracket (Kit:Bar) round a fill `h` tall and the Width() wide, a StatusBar on its opening
local function NewBar(parent, h, area)
	local strip = MelloUI.Kit:Bar(parent, { kind = "frame", scale = h / Rows("frame") })
	local bar = CreateFrame("StatusBar", nil, strip.fill)
	bar:SetAllPoints(strip.fill)
	bar:SetStatusBarTexture(W.BarFill(area))
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	local b = { strip = strip, bar = bar, kind = "frame" }
	Fit(b, h)
	return b
end

--------------------------------------------------------------------------------
-- The bars' look (0.21.0, the user: "i also want to be able to change the borders from the personal resources, they
-- should reflect the changes made in the Look -> Borders"; the pick: Personal Resource Border with every bar look):
-- a bracket look in place (Kit:Bar's and Kit:VBar's SetBarLook), a style of the border library round each fill
-- (Kit:NewBorder, the bracket put out, the trough run half a rail under it as Kit:BarLibraryFit does), or none (the
-- fill on its trough). Each bar's reach -- its painted frame past its fill, over and under -- stacks the bars and
-- places the swing's rails
--------------------------------------------------------------------------------
local Dress = {}

function Dress.Value()
	local Kit = MelloUI.Kit
	return Kit and Kit.BorderValue and Kit:BorderValue("personal") or "frame"
end

-- a value's bracket look (its own bar pieces; an unknown one the Ornate), nil for a library style or none
function Dress.Kind(value)
	local Kit = MelloUI.Kit
	if value == "none" or (Kit.BorderStyles and Kit.BorderStyles[value]) then
		return nil
	end
	return Kit:Piece("bars/" .. tostring(value) .. "_mid") and value or "frame"
end

-- the column's bracket across, for a fill T.colW wide in that look
function Dress.Across(kind)
	local p = MelloUI.Kit:Piece("bars/" .. kind .. "_mid")
	return T.colW * ((p and p.h) or 64) / Rows(kind)
end

-- a library style's rails at most a quarter of the Ornate bracket's painted depth round a fill `h` deep (a thin bar, a
-- thin rail)
function Dress.Band(h)
	local open, padTop, padBottom = Rows("frame")
	local p = MelloUI.Kit:Piece("bars/frame_mid")
	local boxRows = p and (p.h - padTop - padBottom) or (open * 1.9)
	return h * boxRows / open * (MelloUI.Kit.BorderBandRail or 0.25)
end

-- a strip's painted pieces shown or put out (alpha: the strip's own show and hide untouched)
function Dress.Pieces(strip, on)
	local a = on and 1 or 0
	for _, key in ipairs({ "capL", "mid", "capR", "capT", "capB" }) do
		local tex = rawget(strip, key)
		if tex then
			tex:SetAlpha(a)
		end
	end
end

-- the library's style round a fill (the border made with the first), or put away. Frameless -- the fill's own
-- regions on an empty anchor of it -- so a rail family's eight are laid again in place for each new depth
-- (RailSet:Relay; a framed one would be made again, the 2026-10-12 crash's kind of leak)
function Dress.Round(owner, fill, style, depth)
	if not style then
		if owner.border then
			owner.border:SetShown(false)
		end
		return
	end
	if not owner.border then
		local anchor = fill:CreateTexture(nil, "BACKGROUND")
		anchor:SetAllPoints(fill)
		owner.border = MelloUI.Kit:NewBorder({ rect = anchor, owner = fill, place = "round", layer = "ARTWORK", sub = 3,
			noBg = true })
	end
	owner.border:SetFit(Dress.Band(depth), nil)
	owner.border:Lay(style, "light")
	owner.border:SetShown(true)
end

-- the trough on the fill (none), half a rail under a style's border on each side (the bars' rule: Kit:TuckTrough), or
-- as the bracket laid it
function Dress.Trough(owner, strip)
	if owner.style or owner.bare then
		MelloUI.Kit:TuckTrough(strip.trough, strip.fill, owner.style and owner.border or nil)
	end
end

-- one bar in the look `value` (its fill b.h deep; b.kind the strip's bracket look)
function Dress.Bar(b, value)
	local kind = Dress.Kind(value)
	b.style = (not kind and value ~= "none") and value or nil
	b.bare = value == "none"
	-- (a library style or none: the Ornate strip, put out, keeps the fill where it was)
	b.kind = kind or "frame"
	Fit(b, b.h)
	local strip = b.strip
	strip:SetBarLook(b.kind)
	strip:SetBarScale(b.scale)
	Dress.Pieces(strip, kind ~= nil)
	Dress.Round(b, strip.fill, b.style, b.h)
	Dress.Trough(b, strip)
end

-- the shield column in the look `value` (its upright pieces; a bracket look with none: the Ornate's)
function Dress.Column(col, value)
	local kind = Dress.Kind(value)
	col.style = (not kind and value ~= "none") and value or nil
	col.bare = value == "none"
	col.kind = kind or "frame"
	local strip = col.strip
	if not strip:SetBarLook(col.kind, Dress.Across(col.kind)) then
		col.kind = "frame"
		strip:SetBarLook("frame", Dress.Across("frame"))
	end
	local ins = strip.insets
	strip:SetHeight(T.colH + ins[3] + ins[4])
	col.holder:SetSize(strip:GetWidth(), strip:GetHeight())
	Dress.Pieces(strip, kind ~= nil)
	Dress.Round(col, strip.fill, col.style, T.colW)
	Dress.Trough(col, strip)
end

-- every part in the Personal Resource Border's look (laid again by the caller: LayStack, Place)
function Dress.Apply(ui)
	local value = Dress.Value()
	ui.look = value
	for _, b in ipairs(ui.stack) do
		Dress.Bar(b, value)
	end
	if ui.column then
		Dress.Column(ui.column, value)
	end
end

-- a bar's painted reach past its fill, over and under
function Dress.Reach(b)
	if b.style and b.border then
		local _, y = b.border:Inset()
		return y, y
	elseif b.bare then
		return 0, 0
	end
	local p = MelloUI.Kit:Piece("bars/" .. b.kind .. "_mid")
	local open, box = p and p.open, p and p.box
	if not (open and box) then
		return 0, 0
	end
	return (open[2] - box[2]) * b.scale, (box[4] - open[4]) * b.scale
end

-- its painted width past the fill's, both sides together
function Dress.Side(b)
	if b.style and b.border then
		return 2 * b.border:Inset()
	elseif b.bare then
		return 0
	end
	return b.arms
end

-- the Height changed: each bar at its new depth, in its look (no frame made again)
local function Refit(ui)
	local hh, hp, hc = Heights()
	ui.health.h, ui.power.h, ui.cast.h = hh, hp, hc
	Dress.Apply(ui)
end

-- the bars' widths: each fill the Width(), its caps outside it; the widest painted width
local function LayWidth(ui)
	local w = Width()
	local widest = 0
	for _, b in ipairs(ui.stack) do
		b.strip:SetWidth(w + b.arms)
		widest = math.max(widest, w + Dress.Side(b))
	end
	return widest
end

-- The swing on the rails (the user's pick C of prd_swing, 2026-10-12: "a glint on the rails", no bar at all): along a
-- bracket's rail an unseen StatusBar whose fill grows from the middle to both ends over the swing (Anim:Timer: the
-- engine counts it, no Lua a frame, Reduce Motion or not -- it tells time), a spark pinned to each end of that fill; the
-- swing lands as the sparks reach the ends (a flash there as the next one starts). The main hand on the health bar's
-- top rail, the off hand on the power bar's foot, shots on the seam between the two (Ranged, the aim's red halves)
local SPARK_ART = "Interface\\AddOns\\MelloUI\\Media\\FrameFX\\"

local function Spark(parent, layer, sub, file, colour)
	local tex = parent:CreateTexture(nil, layer, nil, sub)
	tex:SetTexture(SPARK_ART .. file)
	tex:SetBlendMode("ADD")
	if colour then
		tex:SetVertexColor(colour[1], colour[2], colour[3])
	end
	return tex
end

local function NewRail(b)
	local strip = b.strip
	local rail = CreateFrame("StatusBar", nil, strip)
	rail:SetFrameLevel(strip:GetFrameLevel() + 2)
	rail:SetStatusBarTexture(W.BarFill("personal"))
	local fill = rail:GetStatusBarTexture()
	fill:SetAlpha(0)   -- (only its ends are wanted: the sparks pinned to them)
	local style = Enum and Enum.StatusBarFillStyle
	if style and style.Center and rail.SetFillStyle then
		pcall(rail.SetFillStyle, rail, style.Center)
	end
	rail:SetMinMaxValues(0, 1)
	rail:SetValue(0)
	local colour = MelloUI.Meaning.swingMelee
	rail.parts = {}
	for _, point in ipairs({ "LEFT", "RIGHT" }) do
		local glow = Spark(rail, "OVERLAY", 6, "glow_white.tga")
		glow:SetPoint("CENTER", fill, point, 0, 0)
		local star = Spark(rail, "OVERLAY", 7, "spark_gold.tga", colour)
		star:SetPoint("CENTER", fill, point, 0, 0)
		rail.parts[#rail.parts + 1] = glow
		rail.parts[#rail.parts + 1] = star
	end
	-- the landing: a flash at both ends
	local land = CreateFrame("Frame", nil, rail)
	land:SetAllPoints(rail)
	land:SetAlpha(0)
	rail.ends = {}
	for _, point in ipairs({ "LEFT", "RIGHT" }) do
		local flash = Spark(land, "OVERLAY", 7, "glow_white.tga")
		flash:SetPoint("CENTER", rail, point, 0, 0)
		rail.ends[#rail.ends + 1] = flash
	end
	rail.land = land
	rail.bar = b
	rail:Hide()
	return rail
end

-- (the ranged rail's aim, the user's pick B of prd_ranged, 2026-10-12) two red lines growing from the rail's ends to
-- its middle over the aim -- each half a StatusBar filling from its own end, the engine's timer (Anim:Timer) -- and a
-- red spark at each end; held (moving), dimmed and still
local function NewAim(rail)
	local aim = CreateFrame("Frame", nil, rail)
	aim:SetAllPoints(rail)
	aim:Hide()
	local colour = MelloUI.Meaning.swingAim
	local style = Enum and Enum.StatusBarFillStyle
	aim.halves, aim.ends = {}, {}
	for i, point in ipairs({ "LEFT", "RIGHT" }) do
		local half = CreateFrame("StatusBar", nil, aim)
		half:SetStatusBarTexture(W.BarFill("personal"))
		half:SetStatusBarColor(colour[1], colour[2], colour[3])
		if point == "RIGHT" and style and style.Reverse and half.SetFillStyle then
			pcall(half.SetFillStyle, half, style.Reverse)   -- (the right half fills from its right end)
		end
		half:SetMinMaxValues(0, 1)
		half:SetValue(0)
		aim.halves[i] = half
		local glow = Spark(aim, "OVERLAY", 6, "glow_red.tga")
		glow:SetPoint("CENTER", rail, point, 0, 0)
		local star = Spark(aim, "OVERLAY", 7, "spark_gold.tga", colour)
		star:SetPoint("CENTER", rail, point, 0, 0)
		aim.ends[#aim.ends + 1] = glow
		aim.ends[#aim.ends + 1] = star
	end
	rail.aim = aim
end

-- the rails on their brackets (the rail's middle: halfway through its painted rows), the sparks sized to the bar
local function LayRails(ui)
	local rails = ui.rails
	if not rails then
		return
	end
	for hand, rail in pairs(rails) do
		local b = rail.bar
		local fill = b.strip.fill
		local above, below = Dress.Reach(b)
		rail:ClearAllPoints()
		if hand == "main" then
			rail:SetPoint("BOTTOMLEFT", fill, "TOPLEFT", 0, above / 2)
			rail:SetPoint("BOTTOMRIGHT", fill, "TOPRIGHT", 0, above / 2)
		elseif hand == "ranged" then
			-- the seam: where the health bar's painted foot meets the power's painted top (a gap apart, LayStack)
			local seam = below + T.gap / 2
			rail:SetPoint("TOPLEFT", fill, "BOTTOMLEFT", 0, -seam)
			rail:SetPoint("TOPRIGHT", fill, "BOTTOMRIGHT", 0, -seam)
		else
			rail:SetPoint("TOPLEFT", fill, "BOTTOMLEFT", 0, -below / 2)
			rail:SetPoint("TOPRIGHT", fill, "BOTTOMRIGHT", 0, -below / 2)
		end
		rail:SetHeight(1)
		local size = (hand == "main" and T.glint or hand == "ranged" and T.glintRanged or T.glintOff) * (b.h / 10)
		for i, tex in ipairs(rail.parts) do
			-- (the glow wide and low, the star square)
			if i % 2 == 1 then
				tex:SetSize(size * 2.4, size * 1.1)
			else
				tex:SetSize(size * 1.5, size * 1.5)
			end
		end
		for _, tex in ipairs(rail.ends) do
			tex:SetSize(size * 2.6, size * 1.8)
		end
		local aim = rail.aim
		if aim then
			local line = T.aimLine * (b.h / 10) / 2
			local left, right = aim.halves[1], aim.halves[2]
			left:ClearAllPoints()
			left:SetPoint("TOPLEFT", rail, "LEFT", 0, line)
			left:SetPoint("BOTTOMRIGHT", rail, "CENTER", 0, -line)
			right:ClearAllPoints()
			right:SetPoint("TOPLEFT", rail, "CENTER", 0, line)
			right:SetPoint("BOTTOMRIGHT", rail, "RIGHT", 0, -line)
			for i, tex in ipairs(aim.ends) do
				if i % 2 == 1 then
					tex:SetSize(size * 2.6, size * 1.3)
				else
					tex:SetSize(size * 1.6, size * 1.6)
				end
			end
		end
	end
end

-- the stack: health, power, the cast bar under them, each bracket's painted edge on the one above's (their
-- transparent rows overlapping), centred (their fills line up: each cap the same both sides)
local function LayStack(ui)
	local widest = LayWidth(ui)
	local float = ui.float
	local y, prev, prevBelow = 0, nil, 0
	for i, b in ipairs(ui.stack) do
		local above, below = Dress.Reach(b)
		local _, _, top = b.strip:GetInsets()   -- (the strip's top to its opening: the fill's)
		b.strip:ClearAllPoints()
		if not prev then
			-- the first one's painted top on the float's
			b.strip:SetPoint("TOP", float, "TOP", 0, top - above)
		else
			-- each painted top a gap under the one before's painted foot
			b.strip:SetPoint("TOP", prev.strip.fill, "BOTTOM", 0, top - (prevBelow + T.gap + above))
		end
		if i < #ui.stack then
			y = y + above + b.h + below + T.gap
		end
		prev, prevBelow = b, below
	end
	-- (the holder: health and power, the cast bar hanging under them when it shows)
	ui.holder:SetSize(widest, math.max(1, y - T.gap))
	-- the percents past the widest caps, each on its bar's middle
	local textX = widest / 2 + T.textGap
	for _, b in ipairs(ui.stack) do
		if b.text then
			b.text:ClearAllPoints()
			b.text:SetPoint("LEFT", b.strip.fill, "CENTER", textX, 0)
		end
	end
	LayRails(ui)
end

local function Home(kind)
	return function(holder)
		holder:ClearAllPoints()
		if kind == "bars" then
			-- under the character's feet as the default camera shows them (the user, 2026-10-12: "more under the feet
			-- of the character ... i dont want them covering my character model"; Follow Camera Zoom keeps them there)
			holder:SetPoint("TOP", UIParent, "CENTER", 0, -105)
		else
			-- the shield column on the character's right
			holder:SetPoint("LEFT", UIParent, "CENTER", 55, -10)
		end
		return true
	end
end

local Refresh   -- (below)
local Cds = {}  -- (Big Cooldowns: below, after Heal Light From Your Character)

local function Build()
	local ui = S.ui
	if ui then
		return ui
	end
	local Kit = MelloUI.Kit
	if not (Kit and Kit.Bar and Kit.VBar) then
		return nil
	end
	ui = {}
	S.ui = ui
	-- (0.21.0, the user: "a option in the fader to fade out of combat") both holders on the Fader's host: their own
	-- fades (the column's, the cast bar's) never meet the Fader's
	local host = MelloUI.Fader and MelloUI.Fader:Host("personal") or UIParent
	-- the bars: a holder Edit Layout moves, a float inside it the hop lifts
	local holder = CreateFrame("Frame", "MelloUIPersonalDisplay", host)
	holder:SetFrameStrata("MEDIUM")
	holder:EnableMouse(false)
	holder:SetClampedToScreen(true)
	ui.holder = holder
	local float = CreateFrame("Frame", nil, holder)
	float:SetAllPoints(holder)
	ui.float = float
	local hh, hp, hc = Heights()
	ui.health = NewBar(float, hh, "personal")
	ui.power = NewBar(float, hp, "personal")
	ui.cast = NewBar(float, hc, "castbars")
	ui.stack = { ui.health, ui.power, ui.cast }
	Paint(ui.health.bar, "personalHealth")
	Paint(ui.cast.bar, "personalCast")
	for _, b in ipairs({ ui.health, ui.power }) do
		b.text = b.bar:CreateFontString(nil, "OVERLAY")
		StyleText(b.text, T.text)
		b.text:SetJustifyH("LEFT")
	end
	-- the cast bar: the spell on its left, the seconds on its right (the engine writes them: Anim:TimerText)
	local cast = ui.cast
	cast.name = cast.bar:CreateFontString(nil, "OVERLAY")
	StyleText(cast.name, T.text - 1)
	cast.name:SetPoint("LEFT", cast.strip.fill, "LEFT", 3, 0)
	cast.name:SetJustifyH("LEFT")
	cast.time = cast.bar:CreateFontString(nil, "OVERLAY")
	StyleText(cast.time, T.text - 1)
	cast.time:SetPoint("RIGHT", cast.strip.fill, "RIGHT", -3, 0)
	cast.timed = Anim:TimerText(cast.time, cast.bar)
	cast.strip:SetAlpha(0)
	cast.strip:Hide()
	ui.rails = { main = NewRail(ui.health), off = NewRail(ui.power), ranged = NewRail(ui.health) }
	NewAim(ui.rails.ranged)
	LayStack(ui)

	-- the shield column: its own holder beside the character, a float the hop lifts with the bars
	local colHolder = CreateFrame("Frame", "MelloUIPersonalShield", host)
	colHolder:SetFrameStrata("MEDIUM")
	colHolder:EnableMouse(false)
	colHolder:SetClampedToScreen(true)
	local colFloat = CreateFrame("Frame", nil, colHolder)
	colFloat:SetAllPoints(colHolder)
	-- (the user's video, 2026-10-12: a shield broken before its time left its column up -- its 0 is secret, no Lua
	-- sees it) the column's presence is the engine's: an unseen StatusBar holding the shield's amount against 1 (full
	-- while any is left, empty at 0) and a frame clipping the column to that fill -- at 0 the column is clipped away,
	-- whatever Lua knows. The column itself anchored to the float, not the clip: its rect stays readable (the light,
	-- the zoom)
	local presence = CreateFrame("StatusBar", nil, colFloat)
	presence:SetOrientation("VERTICAL")
	presence:SetStatusBarTexture(W.BarFill("personal"))
	presence:GetStatusBarTexture():SetAlpha(0)
	presence:SetMinMaxValues(0, 1)
	presence:SetValue(0)
	local clip = CreateFrame("Frame", nil, colFloat)
	clip:SetClipsChildren(true)
	clip:SetPoint("TOPLEFT", presence:GetStatusBarTexture(), "TOPLEFT")
	clip:SetPoint("BOTTOMRIGHT", presence:GetStatusBarTexture(), "BOTTOMRIGHT")
	local strip = Kit:VBar(clip, { kind = "frame", width = Dress.Across("frame") })
	local ins = strip.insets
	strip:SetHeight(T.colH + ins[3] + ins[4])
	strip:SetPoint("CENTER", colFloat, "CENTER")
	colHolder:SetSize(strip:GetWidth(), strip:GetHeight())
	-- (the presence's fill covers the column and its number under it)
	presence:SetPoint("TOPLEFT", strip, "TOPLEFT", -T.text, T.gap)
	presence:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", T.text, -(T.text + 6))
	-- the part lost (pale, under the fill) and the fill, upright
	local loss = CreateFrame("StatusBar", nil, strip.fill)
	loss:SetAllPoints(strip.fill)
	loss:SetOrientation("VERTICAL")
	loss:SetStatusBarTexture(W.BarFill("personal"))
	Paint(loss, "personalLoss")
	loss:SetMinMaxValues(0, 1)
	loss:SetValue(0)
	local bar = CreateFrame("StatusBar", nil, strip.fill)
	bar:SetAllPoints(strip.fill)
	bar:SetOrientation("VERTICAL")
	bar:SetStatusBarTexture(W.BarFill("personal"))
	bar:SetFrameLevel(loss:GetFrameLevel() + 1)
	Paint(bar, "personalShield")
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	local amount = clip:CreateFontString(nil, "OVERLAY")
	StyleText(amount, T.text)
	amount:SetPoint("TOP", strip, "BOTTOM", 0, -2)
	colHolder:SetAlpha(0)
	ui.column = { holder = colHolder, float = colFloat, strip = strip, bar = bar, loss = loss, amount = amount,
		presence = presence, clip = clip }   -- (clip: the tests' Q6 reads the column's structure from it)
	-- every part in the Personal Resource Border's look, the bars stacked by it
	Dress.Apply(ui)
	LayStack(ui)
	-- (Follow Camera Zoom's frame: its OnUpdate set only while the zoom moves)
	S.zoomFrame = CreateFrame("Frame", nil, holder)

	-- Edit Layout: each where it stands
	ui.entry = MelloUI:RegisterMover(holder, holder, { key = "personalbars", default = Home("bars"), min = 0.5, max = 2,
		base = 1, label = TEXT.bars, page = OWNER, when = On, placeholder = true, settings = { "PersonalDisplay.width" } })
	if not MelloUI:RestorePosition("personalbars", holder) then
		Home("bars")(holder)
	end
	ui.colEntry = MelloUI:RegisterMover(colHolder, colHolder, { key = "personalshield", default = Home("shield"), min = 0.5,
		max = 2, base = 1, label = TEXT.column, page = OWNER, when = function() return On() and Db().shield ~= false end,
		placeholder = true })
	if not MelloUI:RestorePosition("personalshield", colHolder) then
		Home("shield")(colHolder)
	end
	return ui
end

--------------------------------------------------------------------------------
-- Health, power
--------------------------------------------------------------------------------

-- a value or its secret: either goes to the bar or the font string as it is
local function Usable(v)
	return Secret(v) or type(v) == "number"
end

local function Percent(fs, fn, ...)
	if Db().text == false or not fn then
		fs:SetText("")
		return
	end
	local ok, pct = pcall(fn, ...)
	if ok and Usable(pct) then
		fs:SetFormattedText("%.0f%%", pct)
	end
end

local function Health()
	local ui = S.ui
	if not ui or S.preview then
		return
	end
	local okM, max = pcall(UnitHealthMax, "player")
	local okV, v = pcall(UnitHealth, "player")
	if okM and okV and Usable(max) and Usable(v) then
		ui.health.bar:SetMinMaxValues(0, max)
		ui.health.bar:SetValue(v, EASE)
	end
	Percent(ui.health.text, rawget(_G, "UnitHealthPercent"), "player", true, Curve())
end

local function Power()
	local ui = S.ui
	if not ui or S.preview then
		return
	end
	local okT, _, token = pcall(UnitPowerType, "player")
	local colours = rawget(_G, "PowerBarColor")
	local c = okT and not Secret(token) and type(token) == "string" and type(colours) == "table" and colours[token]
	if c and c.r then
		ui.power.bar:SetStatusBarColor(c.r, c.g, c.b)
	else
		Paint(ui.power.bar, "combatResource")
	end
	local okM, max = pcall(UnitPowerMax, "player")
	local okV, v = pcall(UnitPower, "player")
	if okM and okV and Usable(max) and Usable(v) then
		ui.power.bar:SetMinMaxValues(0, max)
		ui.power.bar:SetValue(v, EASE)
	end
	Percent(ui.power.text, rawget(_G, "UnitPowerPercent"), "player", nil, false, Curve())
end

--------------------------------------------------------------------------------
-- The cast bar: only while you cast or channel
--------------------------------------------------------------------------------

local function HideFrame(frame)
	frame:Hide()
end

-- a cast's start or end: the Fader looks again (the Personal Display back while casting, In Combat)
local function FadePoke()
	local F = MelloUI.Fader
	if F and F.Poke then
		F:Poke()
	end
end

local function CastIn()
	local strip = S.ui.cast.strip
	if not strip:IsShown() then
		strip:Show()
	end
	Anim:To(strip, "alpha", 1, T.castFade, "outQuad")
end

local function CastOut()
	S.casting = false
	FadePoke()
	local cast = S.ui and S.ui.cast
	if not cast then
		return
	end
	Anim:To(cast.strip, "alpha", 0, T.castFade, "inQuad", HideFrame)
end

-- a cast (or a channel: its bar runs down) shown: the spell's name and the time left, counted by the engine
local function CastShow(name, seconds, channel)
	local cast = S.ui.cast
	cast.name:SetText(Db().text == false and "" or name)
	-- (the seconds the engine's: shown or not with the text)
	cast.time:SetShown(Db().text ~= false and cast.timed and true or false)
	if seconds then
		Anim:Timer(cast.bar, seconds, not channel)
	else
		Anim:StopTimer(cast.bar, true)   -- (its times unreadable: the bar full, no seconds)
	end
	S.casting = true
	FadePoke()
	CastIn()
end

-- a cast or a channel still running (its name read, plain or secret)
local function Casting(info)
	local ok, name = pcall(info, "player")
	return ok and (Secret(name) or type(name) == "string") or false
end

local function StillCasting()
	return Casting(UnitCastingInfo) or Casting(UnitChannelInfo)
end

local function CastRead(channel)
	if not S.ui or S.preview then
		return
	end
	local info = channel and UnitChannelInfo or UnitCastingInfo
	local ok, name, _, _, startMS, endMS = pcall(info, "player")
	if not ok or not (Secret(name) or type(name) == "string") then
		CastOut()
		return
	end
	local seconds
	if Secret(startMS) or Secret(endMS) then
		S.reads.cast = TEXT.secret
	elseif type(endMS) == "number" then
		S.reads.cast = TEXT.plain
		seconds = math.max(0.05, endMS / 1000 - GetTime())
	end
	CastShow(name, seconds, channel)
end

--------------------------------------------------------------------------------
-- The shields in parts (the user's pick B of prd_multishield, 2026-10-12: "a single shield bar which includes all of
-- the shields in the game, there are certain passives and active spells that give you a shield, also some items which
-- absorb certain damage types"): the column one part for each shield on you -- a spell's, a talent's, an item's --
-- stacked in the order they went up, each in its school's colour (ShieldSpells.lua: the client's own spell data), its
-- icon in a stack beside the column. Each part a StatusBar holding that shield's own amount (its aura's value: plain
-- or secret, the engine draws it) against the whole at the column's last rise, the next part laid on its fill's top.
-- A shield whose spell or amount cannot be read, or more than T.partMax: the column the game's one total, as before
--------------------------------------------------------------------------------
local Parts = {}
local SPELLS = ns and ns.ShieldSpells or {}
local SCHOOL_KEY = { [0] = "personalShield", "personalShieldHoly", "personalShieldFire", "personalShieldNature",
	"personalShieldFrost", "personalShieldShadow", "personalShieldArcane" }

-- one shield's aura: its amount (plain or secret), its colour's school, its icon; nil when it cannot be read
function Parts.Read(id)
	local api = _G.C_UnitAuras
	local get = api and api.GetAuraDataByAuraInstanceID
	if type(get) ~= "function" then
		return nil
	end
	local ok, aura = pcall(get, "player", id)
	if not ok or Secret(aura) or type(aura) ~= "table" then
		return nil
	end
	local spell, points = aura.spellId, aura.points
	if Secret(spell) or Secret(points) or type(points) ~= "table" then
		return nil
	end
	local code = SPELLS[spell]
	if not code then
		return nil
	end
	local v = points[math.floor(code / 10)]
	if not Usable(v) then
		return nil
	end
	return v, code % 10, aura.icon
end

-- part i, made the first time a shield needs it and kept: a StatusBar on the one below's fill (the first on the
-- column's foot) in a frame clipping them to the column, its icon in the stack beside the column
function Parts.Get(i)
	local col = S.ui.column
	if not col.parts then
		col.parts = {}
		local host = CreateFrame("Frame", nil, col.strip.fill)
		host:SetAllPoints(col.strip.fill)
		host:SetClipsChildren(true)
		host:SetFrameLevel(col.bar:GetFrameLevel())
		col.partHost = host
	end
	local p = col.parts[i]
	if p then
		return p
	end
	local bar = CreateFrame("StatusBar", nil, col.partHost)
	bar:SetOrientation("VERTICAL")
	bar:SetStatusBarTexture(W.BarFill("personal"))
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	if i == 1 then
		bar:SetPoint("BOTTOMLEFT", col.partHost, "BOTTOMLEFT")
		bar:SetPoint("BOTTOMRIGHT", col.partHost, "BOTTOMRIGHT")
	else
		local below = col.parts[i - 1].bar:GetStatusBarTexture()
		bar:SetPoint("BOTTOMLEFT", below, "TOPLEFT")
		bar:SetPoint("BOTTOMRIGHT", below, "TOPRIGHT")
	end
	bar:SetHeight(T.colH)
	local icon = W.RoundIcon(col.float, T.partIcon, nil)
	icon:EnableMouse(false)   -- (the pointer passes through the display to the world)
	icon:SetKit(MelloUI.Kit)
	icon:SetPoint("BOTTOMLEFT", col.strip, "BOTTOMRIGHT", T.partGap,
		col.strip.insets[4] + (i - 1) * (T.partIcon + T.partGap))
	p = { bar = bar, icon = icon }
	col.parts[i] = p
	return p
end

function Parts.Set(i, value, school, icon)
	local p = Parts.Get(i)
	p.bar:SetMinMaxValues(0, S.max or 1)   -- (the whole at the last rise: a secret too)
	p.bar:SetValue(value, EASE)
	Paint(p.bar, SCHOOL_KEY[school] or "personalShield")
	p.bar:Show()
	local shown = Secret(icon) or icon ~= nil
	if shown then
		shown = pcall(p.icon.SetIcon, p.icon, icon)
	end
	p.icon:SetShown(shown and true or false)
end

-- (the preview) its made-up shields at the total `left`: spent from the bottom up
function Parts.Sample(left)
	local list = S.previewParts or {}
	local spent = 0
	for _, part in ipairs(list) do
		spent = spent + part[2]
	end
	spent = spent - (Num(left) or 0)
	local i = 0
	for _, part in ipairs(list) do
		local value = math.max(0, part[2] - math.max(0, spent))
		spent = spent - part[2]
		if value > 0 then
			i = i + 1
			local code = SPELLS[part[1]] or 0
			local ok, tex = pcall(_G.C_Spell and _G.C_Spell.GetSpellTexture or _G.GetSpellTexture, part[1])
			Parts.Set(i, value, code % 10, ok and tex or nil)
		end
	end
	return i
end

-- the column in parts (each shield its own) or the one total: read again at each rise, hit and aura update
function Parts.Update()
	local col = S.ui and S.ui.column
	if not col then
		return
	end
	local n = 0
	if S.shieldOn and Db().shield ~= false then
		if S.preview then
			n = Parts.Sample(S.value)
		elseif #S.shieldIDs > 0 and #S.shieldIDs <= T.partMax then
			n = #S.shieldIDs
			for i, id in ipairs(S.shieldIDs) do
				local value, school, icon = Parts.Read(id)
				if value == nil then
					n = 0   -- (one not read: the one total, nothing guessed)
					break
				end
				Parts.Set(i, value, school, icon)
			end
		end
	end
	if col.parts then
		for i = n + 1, #col.parts do
			col.parts[i].bar:Hide()
			col.parts[i].icon:Hide()
		end
	end
	S.partsOn = n > 0
	col.bar:SetAlpha(S.partsOn and 0 or 1)
end

--------------------------------------------------------------------------------
-- The shield column
--------------------------------------------------------------------------------

-- its light (MelloUI.FrameFX, the "shield" look), at its events: a = applied, x = hit, l = low, k = broken. On the
-- column's fill, the bar itself (the strip's rect reaches far past the painted bracket: the light started under the
-- bar, the user's screenshot of 2026-10-12), its room past it in the column's own units, at the column's scale
local spillNow = {}
local function Light(kind)
	local col = S.ui and S.ui.column
	local F = MelloUI.Fader
	if F and F.Shown and not F:Shown("personal") then
		return   -- (the display faded by the Fader: no light round a column nobody sees)
	end
	if col and FX and FX.ShowOn and Db().shield ~= false then
		local fill = col.strip.fill
		local k = (Num(fill:GetEffectiveScale()) or 1) / (Num(UIParent:GetEffectiveScale()) or 1)
		spillNow[1], spillNow[2] = T.spill[1] * k, T.spill[2] * k
		FX.ShowOn(fill, "shield", kind, spillNow)
	end
end

local function ColumnIn()
	local h = S.ui.column.holder
	if Db().shield == false then
		h:SetAlpha(0)
		return
	end
	Anim:To(h, "alpha", 1, T.columnFade, "outQuad")
end

local function ColumnOut()
	if S.shieldOn then
		return
	end
	Anim:To(S.ui.column.holder, "alpha", 0, T.breakFade, "inQuad")
end

function Shield.Low(on)
	if S.low == on then
		return
	end
	S.low = on
	Paint(S.ui.column.bar, on and "personalShieldLow" or "personalShield")
	if on then
		Light("l")
	end
end

local function Amount(amount)
	local fs = S.ui.column.amount
	if Db().text == false then
		fs:SetText("")
	else
		fs:SetFormattedText("%d", amount)   -- (a secret too: the font string takes it)
	end
end

-- up (or up again above what it was): the fill rising from empty to the whole of it, the light round the column
function Shield.Apply(amount)
	local col = S.ui.column
	S.shieldOn, S.max, S.value = true, amount, amount
	col.presence:SetValue(amount)
	col.bar:SetMinMaxValues(0, amount)
	col.loss:SetMinMaxValues(0, amount)
	col.loss:SetValue(0)
	col.bar:SetValue(0)
	col.bar:SetValue(amount, EASE)
	Amount(amount)
	Shield.Low(false)
	ColumnIn()
	Light("a")
	Parts.Update()
end

local function LossDrain()
	local col = S.ui and S.ui.column
	if col and S.shieldOn then
		col.loss:SetValue(S.value, EASE)
	end
end

-- a hit: the fill down to what is left, the part lost held pale a moment and drained after it; low under T.low of
-- the whole (a plain amount only)
function Shield.Hit(amount)
	local col = S.ui.column
	col.presence:SetValue(amount)
	col.loss:SetValue(S.value)
	col.bar:SetValue(amount, EASE)
	S.value = amount
	Amount(amount)
	Light("x")
	C_Timer.After(T.lossDelay, LossDrain)
	local max, now = Num(S.max), Num(amount)
	if max and now and max > 0 then
		Shield.Low(now / max < T.low)
	end
	Parts.Update()
end

-- broken (or run out): the shards, the column emptied, held a moment, faded out
function Shield.Break()
	local col = S.ui.column
	S.shieldOn = false
	wipe(S.shieldIDs)
	Shield.Low(false)
	col.bar:SetValue(0, EASE)
	col.loss:SetValue(0, EASE)
	col.amount:SetText("")
	Light("k")
	C_Timer.After(T.breakHold, ColumnOut)
	Parts.Update()
end

-- the shield's own auras: the ones the aura update that came with its rise added
-- (the user, 2026-10-12: "a single shield bar which includes all of the shields in the game" -- spells, passives,
-- items, the ones against one kind of damage; the column is the game's total of them all) a fresh shield's auras
-- known as its own; one more on top of shields already up added to the ones known, never in their place
function Shield.Adopt()
	-- (the ones the client's spell data names shields, when there are: a buff gone up beside them is not one)
	local from = #S.addedSure > 0 and S.addedSure or S.added
	if #from == 0 then
		return   -- (no aura of its kind heard: the ones known kept)
	end
	if not S.shieldOn then
		wipe(S.shieldIDs)
	end
	for _, id in ipairs(from) do
		local known = false
		for _, have in ipairs(S.shieldIDs) do
			if have == id then
				known = true
			end
		end
		if not known then
			S.shieldIDs[#S.shieldIDs + 1] = id
		end
	end
end

-- the total absorb changed: a plain amount tells it all, a secret one is read from the auras around it
function Shield.Changed()
	if not S.ui or S.preview then
		return
	end
	local ok, amount = pcall(UnitGetTotalAbsorbs, "player")
	if not ok then
		return
	end
	S.absorbAt, S.lastAmount = GetTime(), amount
	-- (the column's presence: the amount itself, secret or not -- the engine hides the column at 0)
	if Usable(amount) then
		S.ui.column.presence:SetValue(amount)
	end
	if not Secret(amount) then
		if type(amount) ~= "number" then
			return
		end
		S.reads.shield = TEXT.plain
		local max, value = Num(S.max), Num(S.value)
		if amount <= 0 then
			if S.shieldOn then
				Note("plain: broken")
				Shield.Break()
			end
		elseif not S.shieldOn or (max and amount > max) or (value and amount > value) then
			Note("plain: applied")
			S.lastKind = "apply"
			Shield.Apply(amount)
		elseif value and amount < value then
			Note("plain: hit")
			S.lastKind = "hit"
			Shield.Hit(amount)
		end
		return
	end
	S.reads.shield = TEXT.secret
	local now = S.absorbAt
	-- (with its own auras known, their going is the break: Shield.Aura)
	if S.shieldOn and #S.shieldIDs == 0 and now - S.auraRemovedAt <= T.recent then
		Note("secret: broken (an aura taken with it)")
		S.lastKind = "break"
		Shield.Break()
	elseif not S.shieldOn or now - S.auraAddedAt <= T.recent then
		Note("secret: applied")
		S.lastKind = "apply"
		if now - S.auraAddedAt <= T.recent then
			Shield.Adopt()
		end
		Shield.Apply(amount)
	else
		Note("secret: hit")
		S.lastKind = "hit"
		Shield.Hit(amount)
	end
end

-- an aura update's news: auras added (their instances kept in `into`, the harmful ones left out where that reads --
-- Weakened Soul comes with Power Word: Shield), auras taken (whether one of `mine`, the shield's own, is among them),
-- a full update (no list: what is left asked after). One function for every event, no closure made per update;
-- called through pcall (an answer it cannot read: nothing)
local function AuraNews(info, into, mine, sure)
	if type(info) ~= "table" then
		return false, false, false, false
	end
	if info.isFullUpdate then
		return false, false, false, true
	end
	local added, removed = info.addedAuras, info.removedAuraInstanceIDs
	local n = 0
	if type(added) == "table" then
		for _, aura in ipairs(added) do
			local id, harmful = aura.auraInstanceID, aura.isHarmful
			if not Secret(id) and type(id) == "number" and (Secret(harmful) or harmful ~= true) then
				if n == 0 then
					wipe(into)   -- (news with none of its kind -- a debuff -- keeps the last one's)
					wipe(sure)
				end
				n = n + 1
				into[n] = id
				local spell = aura.spellId
				if not Secret(spell) and SPELLS[spell] then
					sure[#sure + 1] = id   -- (a shield by the client's own spell data)
				end
			end
		end
	end
	-- (one of the shields' own auras taken: off the list -- the column breaks when the last one is gone)
	local gone = false
	if type(removed) == "table" then
		for _, r in ipairs(removed) do
			if not Secret(r) then
				for j = #mine, 1, -1 do
					if r == mine[j] then
						table.remove(mine, j)
						gone = true
					end
				end
			end
		end
	end
	return n > 0, removed ~= nil, gone, false
end

-- (a full update) whether one of the shield's own auras is still on
-- (a full update) the shields' own auras no longer on taken off the list (one that cannot be told: kept)
local function Prune(ids)
	local api = _G.C_UnitAuras
	local get = api and api.GetAuraDataByAuraInstanceID
	if type(get) ~= "function" then
		return
	end
	for j = #ids, 1, -1 do
		local ok, aura = pcall(get, "player", ids[j])
		if ok and not Secret(aura) and aura == nil then
			table.remove(ids, j)
		end
	end
end

-- the auras changed: noted for a secret amount's story; one added or taken just after a change read as a hit
-- makes that change an application or a break after all
function Shield.Aura(info)
	local now = GetTime()
	local had = #S.shieldIDs
	local ok, added, removed, _, full = pcall(AuraNews, info, S.added, S.shieldIDs, S.addedSure)   -- (the auras left decide a break)
	if not ok then
		return
	end
	if added then
		S.auraAddedAt = now
	end
	if removed then
		S.auraRemovedAt = now
	end
	if not S.ui or S.preview then
		return
	end
	-- (the user's video, 2026-10-12: a shield broken before its time stayed up) its own auras gone, the last of
	-- them: broken; one of several (a second shield still holding): the column stays, the game's total in it
	if full and had > 0 then
		pcall(Prune, S.shieldIDs)
	end
	if S.shieldOn and had > 0 and #S.shieldIDs == 0 then
		Note("broken (its own auras gone)")
		S.lastKind = "break"
		Shield.Break()
		return
	end
	-- (the amount's change heard before its aura: the shield's own adopted now; one the spell data names a shield,
	-- gone up on top of shields already up, adopted whenever it comes)
	if added and S.shieldOn and #S.shieldIDs == 0 and S.lastKind == "apply" and now - S.absorbAt <= T.recent then
		Shield.Adopt()
	elseif added and S.shieldOn and #S.addedSure > 0 then
		Shield.Adopt()
	end
	if S.shieldOn then
		Parts.Update()   -- (an aura's amount changed, one went or came: the parts read again)
	end
	if not (S.reads.shield == TEXT.secret and S.lastKind == "hit" and now - S.absorbAt <= T.recent) then
		return
	end
	if removed and S.shieldOn and #S.shieldIDs == 0 then
		Note("secret: broken (an aura taken just after)")
		S.lastKind = "break"
		Shield.Break()
	elseif added then
		Note("secret: applied (an aura added just after)")
		S.lastKind = "apply"
		Shield.Adopt()
		Shield.Apply(S.lastAmount)
	end
end

local function ShieldOff()
	S.shieldOn, S.low, S.max, S.value = false, false, nil, nil
	wipe(S.shieldIDs)
	local col = S.ui and S.ui.column
	if col then
		col.presence:SetValue(0)
		Anim:Stop(col.holder, "alpha")
		col.holder:SetAlpha(0)
		col.bar:SetValue(0)
		col.loss:SetValue(0)
		col.amount:SetText("")
		Paint(col.bar, "personalShield")
		Parts.Update()
	end
end

--------------------------------------------------------------------------------
-- Where it stands: Edit Layout's place, moved with the camera's zoom and lifted by the hop
--------------------------------------------------------------------------------

-- Follow Camera Zoom (the user, 2026-10-12: "place them more under the feet of the character and adjust with the
-- zoom, i dont want them covering my character model"). The camera looks at the character from the screen's middle:
-- the further it pulls back, the closer every point of the character comes to that middle, as zoomRef / zoom. Each
-- holder's own point (the bars' top middle, under the feet; the column's left middle, beside the body) is scaled so
-- about the screen's middle from where Edit Layout put it; zoomRef is the zoom it was placed at (noted when Edit
-- Layout closes with it moved; the first start's otherwise). The zoom read plainly (GetCameraZoom; anything else: no
-- following), and followed only while it moves (the zoom keys' post-hooks), never polled
local Zoom = { last = nil, still = 0, time = 0, following = false }

function Zoom.Read()
	local get = rawget(_G, "GetCameraZoom")
	if type(get) ~= "function" then
		return nil
	end
	local ok, z = pcall(get)
	if ok and not Secret(z) and type(z) == "number" then
		return z
	end
	return nil
end

function Zoom.Factor()
	if S.editing or Db().zoom == false then
		return 1
	end
	local z, ref = Zoom.Read(), Num(Db().zoomRef)
	if not (z and ref and ref > 0) then
		return 1
	end
	return math.max(T.zoomMin, math.min(T.zoomMax, ref / math.max(z, T.zoomNear)))
end

-- a holder's float moved by its point's share of the scaling (px, py: the point less the screen's middle, in screen
-- pixels) and the hop
local function Shift(holder, float, px, py, k, hop)
	local s = holder:GetEffectiveScale()
	local dx, dy = px * (k - 1) / s, py * (k - 1) / s + hop
	float:ClearAllPoints()
	float:SetPoint("TOPLEFT", holder, "TOPLEFT", dx, dy)
	float:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", dx, dy)
end

local function Place()
	local ui = S.ui
	if not ui then
		return
	end
	local k, hop = Zoom.Factor(), S.hopY or 0
	local us = UIParent:GetEffectiveScale()
	local mx, my = UIParent:GetCenter()
	mx, my = mx * us, my * us
	local h = ui.holder
	local hs = h:GetEffectiveScale()
	local l, r, t = h:GetLeft(), h:GetRight(), h:GetTop()
	if l and r and t then
		Shift(h, ui.float, (l + r) / 2 * hs - mx, t * hs - my, k, hop)
	end
	local c = ui.column.holder
	local cs = c:GetEffectiveScale()
	local cl, cb, ct = c:GetLeft(), c:GetBottom(), c:GetTop()
	if cl and cb and ct then
		Shift(c, ui.column.float, cl * cs - mx, (cb + ct) / 2 * cs - my, k, hop)
	end
end

-- the zoom keys pressed: the camera eases to its new distance; followed each frame until it has held still
local function FollowStep(frame, elapsed)
	local z = Zoom.Read()
	Zoom.time = Zoom.time + elapsed
	if z ~= Zoom.last then
		Zoom.last, Zoom.still = z, 0
		Place()
	else
		Zoom.still = Zoom.still + elapsed
	end
	if Zoom.still >= T.zoomSettle or Zoom.time >= T.zoomLonger then
		Zoom.following = false
		Perf.SetScript(frame, "OnUpdate", nil)
	end
end

function Zoom.Follow()
	if not (On() and S.ui and S.zoomFrame) or Db().zoom == false then
		return
	end
	Zoom.time, Zoom.still = 0, 0
	if not Zoom.following then
		Zoom.following = true
		Perf.SetScript(S.zoomFrame, "OnUpdate", FollowStep)
	end
end

-- where Edit Layout has the holders (screen pixels): a move there noted, so the zoom it was placed at is kept
local function Spot()
	local ui = S.ui
	local h, c = ui.holder, ui.column.holder
	local hs, cs = h:GetEffectiveScale(), c:GetEffectiveScale()
	return string.format("%.1f %.1f %.1f %.1f %.3f %.3f", (h:GetLeft() or 0) * hs, (h:GetTop() or 0) * hs,
		(c:GetLeft() or 0) * cs, (c:GetTop() or 0) * cs, hs, cs)
end

-- Edit Layout open: the display on its plate (no zoom); closed with it moved: the zoom now its reference
local function OnEditLayout(showing)
	if not S.ui then
		return
	end
	if showing then
		S.editing, S.editFrom = true, Spot()
	else
		S.editing = false
		if S.editFrom and Spot() ~= S.editFrom then
			local z = Zoom.Read()
			if z and M.db then
				M.db.zoomRef = z
			end
		end
		S.editFrom = nil
	end
	Place()
end

--------------------------------------------------------------------------------
-- The hop: the jump key pressed and airborne just after, the display lifted and set down
--------------------------------------------------------------------------------

local function HopStep(_, p)
	S.hopY = T.hop * 4 * p * (1 - p)
	Place()
end

local function HopDone()
	S.hopping, S.hopY = false, 0
	Place()
end

local function HopCheck()
	if S.hopping or not (On() and S.ui and Db().hop ~= false) then
		return
	end
	local ok, falling = pcall(IsFalling)
	if ok and not Secret(falling) and falling then
		S.hopping = true
		Anim:Drive(S.ui.holder, HopStep, T.hopTime, "linear", HopDone)
	end
end

local function OnJump()
	if On() and Db().hop ~= false then
		C_Timer.After(T.jumpCheck, HopCheck)
	end
end

--------------------------------------------------------------------------------
-- The swing (Swing On The Rails): the client's PLAYER_SWING (its seconds to the next swing, the hand) starts the
-- rail's run; the one before it has just landed (a flash at the ends); no next swing a moment past its time (out of
-- the fight, the attack stopped): the sparks go. The timing the client's alone -- nothing counted here
--------------------------------------------------------------------------------

local Swing = { due = { main = 0, off = 0, ranged = 0 } }

local function SwingOn()
	return On() and Db().swing ~= false
end

function Swing.Land(rail)
	local land = rail.land
	Anim:Stop(land, "alpha")
	land:SetAlpha(1)
	Anim:To(land, "alpha", 0, T.landFlash, "outQuad")
end

-- a rail whose swing is long past: put away
function Swing.Idle()
	local rails = S.ui and S.ui.rails
	if not rails then
		return
	end
	local now = GetTime()
	for hand, rail in pairs(rails) do
		if rail.running and now + 0.01 >= Swing.due[hand] then
			rail.running = false
			Anim:StopTimer(rail)
			rail:Hide()
			if rail.aim then
				Swing.AimOff(rail)
			end
		end
	end
end

-- a swing of `hand` ("main" / "off") due in `seconds`
function Swing.Start(hand, seconds)
	local rail = S.ui and S.ui.rails and S.ui.rails[hand]
	if not (rail and seconds and seconds > 0) or not SwingOn() then
		return
	end
	if rail.running then
		Swing.Land(rail)
	end
	rail.running = true
	rail:Show()
	Anim:Timer(rail, seconds, true)
	Swing.due[hand] = GetTime() + seconds + T.swingGrace
	C_Timer.After(seconds + T.swingGrace, Swing.Idle)
end

-- The ranged swing (the user's pick B of prd_ranged: "the shot on its own rail", the seam between the health and power
-- bars): a shot's reload (cream sparks out from the middle, moving is fine), then the aim (Auto Shot's last T.aim s:
-- red lines grown from the ends back to the middle, standing still -- moving holds it, dimmed, as Swing Timers' "Hold"),
-- the next shot as they meet. A wand's Shoot has no aim: its one run. The stage and the aim's due time kept here (one
-- C_Timer.After a shot, the function shared: a later shot moves aimAt, an earlier call finds it not due)
local Ranged = { stage = nil, aimAt = 0, moving = false, wand = false }

function Swing.AimOff(rail)
	local aim = rail.aim
	for _, half in ipairs(aim.halves) do
		Anim:StopTimer(half)
	end
	aim:Hide()
	for _, tex in ipairs(rail.parts) do
		tex:SetAlpha(1)
	end
end

-- the aim: run now, or held while moving
function Ranged.Aim()
	local rail = S.ui and S.ui.rails and S.ui.rails.ranged
	if not (rail and rail.running) then
		return
	end
	local aim = rail.aim
	aim:Show()
	for _, tex in ipairs(rail.parts) do
		tex:SetAlpha(0)   -- (the cream sparks at the ends turn red: the aim's own)
	end
	if Ranged.moving then
		Ranged.stage = "hold"
		for _, half in ipairs(aim.halves) do
			Anim:StopTimer(half)
		end
		aim:SetAlpha(T.aimHeld)
		Swing.due.ranged = math.huge   -- (held for as long as it takes)
	else
		Ranged.stage = "aim"
		aim:SetAlpha(1)
		for _, half in ipairs(aim.halves) do
			Anim:Timer(half, T.aim, true)
		end
		Swing.due.ranged = GetTime() + T.aim + T.swingGrace
		C_Timer.After(T.aim + T.swingGrace, Swing.Idle)
	end
end

-- the reload's end (C_Timer.After): the aim, unless a later shot moved it
function Ranged.Due()
	if Ranged.stage == "reload" and GetTime() + 0.01 >= Ranged.aimAt then
		Ranged.Aim()
	end
end

-- a shot fired, the next one due in `seconds`
function Ranged.Start(seconds)
	local rail = S.ui and S.ui.rails and S.ui.rails.ranged
	if not (rail and seconds and seconds > 0) or not SwingOn() then
		return
	end
	if rail.running then
		Swing.Land(rail)
	end
	rail.running = true
	rail:Show()
	Swing.AimOff(rail)
	local reload = Ranged.wand and seconds or (seconds - T.aim)
	Ranged.stage = Ranged.wand and "wand" or "reload"
	Ranged.aimAt = GetTime() + math.max(reload, 0)
	Swing.due.ranged = GetTime() + seconds + T.swingGrace
	C_Timer.After(seconds + T.swingGrace, Swing.Idle)
	if reload > 0 then
		Anim:Timer(rail, reload, true)
		if not Ranged.wand then
			C_Timer.After(reload, Ranged.Due)
		end
	else
		Anim:StopTimer(rail, true)
		Ranged.Aim()
	end
end

-- started or stopped moving: the aim held, or run again
function Ranged.Moving(moving)
	Ranged.moving = moving
	if (moving and Ranged.stage == "aim") or (not moving and Ranged.stage == "hold") then
		Ranged.Aim()
	end
end

-- Auto Shot stopped: no shot on its way
function Ranged.Stop()
	Ranged.stage = nil
	local rail = S.ui and S.ui.rails and S.ui.rails.ranged
	if rail then
		rail.running = false
		Anim:StopTimer(rail)
		Swing.AimOff(rail)
		rail:Hide()
	end
end

-- PLAYER_SWING (the client's own swing timer: seconds, the swing type -- 0 main hand, 1 off hand, 2 ranged)
function Swing.Event(seconds, swingType)
	seconds = Num(seconds)
	if Secret(swingType) or not seconds then
		return
	end
	if swingType == 2 then
		Ranged.Start(seconds)
	else
		Swing.Start(swingType == 1 and "off" or "main", seconds)
	end
end

function Swing.Off()
	Ranged.stage = nil
	local rails = S.ui and S.ui.rails
	if rails then
		for _, rail in pairs(rails) do
			rail.running = false
			Anim:StopTimer(rail)
			rail:Hide()
			if rail.aim then
				Swing.AimOff(rail)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local UNIT_EVENTS = {
	"UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
	"UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_AURA",
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
	"UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_SUCCEEDED",
}
local CAST_START = { UNIT_SPELLCAST_START = false, UNIT_SPELLCAST_DELAYED = false, UNIT_SPELLCAST_CHANNEL_START = true,
	UNIT_SPELLCAST_CHANNEL_UPDATE = true }
local CAST_END = { UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_FAILED = true, UNIT_SPELLCAST_INTERRUPTED = true,
	UNIT_SPELLCAST_CHANNEL_STOP = true }

local function OnEvent(_, event, a1, a2, a3)
	if not S.ui then
		return
	end
	if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
		Health()
	elseif event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
		Power()
	elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" then
		Shield.Changed()
	elseif event == "UNIT_AURA" then
		Shield.Aura(a2)
		Cds.Aura(a2)
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		-- (a cooldown of yours cast: its spell ID plain, as Frame Effects reads its own; a secret one plays nothing)
		if not S.preview and not Secret(a3) and type(a3) == "number" then
			Cds.Start(a3)
		end
	elseif CAST_START[event] ~= nil then
		CastRead(CAST_START[event])
	elseif CAST_END[event] then
		-- (a failed or interrupted attempt -- another spell pressed mid-cast -- while a cast still runs: that cast
		-- stays, as the game's own cast bar keeps it by its castID)
		local attempt = event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED"
		if not S.preview and not (attempt and StillCasting()) then
			CastOut()
		end
	elseif event == "PLAYER_SWING" then
		if not S.preview then
			Swing.Event(a1, a2)
		end
	elseif event == "PLAYER_STARTED_MOVING" or event == "PLAYER_STOPPED_MOVING" then
		Ranged.Moving(event == "PLAYER_STARTED_MOVING")
	elseif event == "STOP_AUTOREPEAT_SPELL" then
		if not S.preview then
			Ranged.Stop()
		end
	elseif event == "PLAYER_EQUIPMENT_CHANGED" then
		Ranged.wand = MelloUI.Safe.RangedIsWand() == true
	elseif event == "PLAYER_ENTERING_WORLD" then
		Refresh()
	end
end

local function Events(on)
	local f = S.frame
	if not f then
		if not on then
			return
		end
		f = CreateFrame("Frame")
		Perf.SetScript(f, "OnEvent", OnEvent)
		S.frame = f
	end
	f:UnregisterAllEvents()
	if not on then
		return
	end
	for _, event in ipairs(UNIT_EVENTS) do
		pcall(f.RegisterUnitEvent, f, event, "player")
	end
	f:RegisterEvent("PLAYER_ENTERING_WORLD")
	if SwingOn() then
		for _, event in ipairs({ "PLAYER_SWING", "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", "STOP_AUTOREPEAT_SPELL",
			"PLAYER_EQUIPMENT_CHANGED" }) do
			pcall(f.RegisterEvent, f, event)
		end
		Ranged.wand = MelloUI.Safe.RangedIsWand() == true
		local okM, moving = pcall(_G.IsPlayerMoving)
		Ranged.moving = okM and not Secret(moving) and moving == true or false
	end
end

-- everything read again (the login, a setting, the preview's end)
Refresh = function()
	local ui = S.ui
	if not ui then
		return
	end
	Health()
	Power()
	CastRead(false)
	if not S.casting then
		CastRead(true)
	end
	local ok, amount = pcall(UnitGetTotalAbsorbs, "player")
	if ok and not Secret(amount) and type(amount) == "number" then
		-- (read again: a shield already up kept as it is, one gone meanwhile broken)
		if amount > 0 and not S.shieldOn then
			Shield.Apply(amount)
		elseif amount <= 0 and S.shieldOn then
			Shield.Break()
		end
	elseif ok and Secret(amount) then
		-- (secret: whether one is up cannot be told until it changes; the column waits for that)
		S.reads.shield = TEXT.secret
	end
end

-- Hide The Game's Cast Bar (the user, 2026-10-12: "when i have the Personal Display option enabled, i want the normal
-- castbar to be hidden"): no CVar switches the player's cast bar off, so it is held see-through -- its alpha 0, and
-- the game's own write of it (ApplyAlpha(1) as each cast starts: once a cast, its fade an animation, no write a
-- frame) answered by a post-hook, counted (Perf.WriteBack). Never Show / Hide or a key of the game's; its 1 given
-- back when off
local GameCast = { hooked = false, held = false, writing = false }

function GameCast.OnAlpha(bar, alpha)
	if not GameCast.held or GameCast.writing or (not Secret(alpha) and alpha == 0) then
		return
	end
	GameCast.writing = true
	bar:SetAlpha(0)
	GameCast.writing = false
	MelloUI.Perf.WriteBack("PersonalDisplay: the game's cast bar")
end

function GameCast.Hold(on)
	local bar = rawget(_G, "PlayerCastingBarFrame")
	if type(bar) ~= "table" or type(bar.SetAlpha) ~= "function" then
		return
	end
	on = on and true or false
	if on == GameCast.held then
		return
	end
	GameCast.held = on
	if on and not GameCast.hooked then
		GameCast.hooked = true
		hooksecurefunc(bar, "SetAlpha", GameCast.OnAlpha)
	end
	GameCast.writing = true
	bar:SetAlpha(on and 0 or 1)
	GameCast.writing = false
end

local function CastHeld()
	return On() and Db().hideCastBar ~= false
end

-- Heal Light From Your Character (the user, 2026-10-12: "this casting animation that we have for Frame Effects, to
-- be anchored on the stomach of my Character, and after the cast is done, shoot the healing animation from my
-- stomach onto the Party/Raid Frames"): Heal Flight's charge placed at the character's middle (MelloUI.FrameFX's
-- SetChargePlace: the flight leaves from there), the place worked out as the bars' (the screen's middle, the bars'
-- top under the feet, the zoom); Heal Flight's own settings (its look, Flying Light) as they are
local function ChargePlace(C)
	local ui = S.ui
	if not (ui and On() and ui.holder:IsShown()) then
		return false
	end
	local l, b, r, t = FX.Rect(ui.float)
	local ml, mb, mr, mt = FX.Rect(UIParent)
	if not (l and b and r and t and ml) then
		return false
	end
	local mx, my = (ml + mr) / 2, (mb + mt) / 2
	local x = mx + ((l + r) / 2 - mx) * T.stomach
	local y = my + (t - my) * T.stomach
	local s = math.max(T.chargeMin, math.min(T.chargeMax, T.charge * Zoom.Factor()))
	C.ix, C.iy, C.isz = x, y, s
	C.bl, C.br, C.bb, C.bt = x - s * 0.9, x + s * 0.9, y - s * 0.35, y + s * 0.35
	C.fill = nil
	return true
end

local function ChargeFrom()
	if FX and FX.SetChargePlace then
		FX.SetChargePlace((On() and Db().healFrom ~= false) and ChargePlace or nil)
	end
end

--------------------------------------------------------------------------------
-- Big Cooldowns (the user, 2026-10-12: "How would it make sense to add aditional effects like big cooldowns ... not
-- add more bars"; their pick C with B's icons of prd_cooldowns, the icons "above the hp bar center aligned", "Also
-- effects like recklessness and shield block"): the buffs you give yourself on a cooldown (CooldownSpells.lua, the
-- client's own spell data, Tools/personal_cooldowns.py: immunity, fortify, more health, block, evasion, offence),
-- begun by your own cast (its spell ID plain; how long from the data), ended by its time or by its aura going (an aura
-- of its kind seen just after the cast is its own). Above the health bar, centred, every one's icon with the game's
-- sweep and its seconds (the engine's timer text), the most important kind first (an immunity, offence last). Nothing
-- drawn on your character (the user, 2026-10-12: "lets scrap this idea of those visual cooldown effects on my
-- character ... the only thing i like to keep are the Big Cooldown Icons above the Personal Resource Healthbar").
-- Nothing per frame in Lua; nothing made at login (each icon the first time one is needed, then kept)
--------------------------------------------------------------------------------
local CDS, CD_LASTS = ns and ns.Cooldowns or {}, ns and ns.CooldownLasts or {}
local CD_PRIO = { I = 1, F = 2, L = 3, B = 4, E = 5, O = 6 }

local function CdsOn()
	return On() and Db().cooldowns ~= false
end

-- a cooldown sweep's call, where this client has it (each set once, at the sweep's making)
local function Try(frame, method, ...)
	local fn = frame[method]
	if type(fn) == "function" then
		pcall(fn, frame, ...)
	end
end

-- the order shown: the most important kind first, then the newest
local function CdOrder(a, b)
	local pa, pb = CD_PRIO[a.kind] or 9, CD_PRIO[b.kind] or 9
	if pa ~= pb then
		return pa < pb
	end
	return a.start > b.start
end

local function SpellIcon(spell)
	local api = _G.C_Spell
	local fn = api and api.GetSpellTexture or _G.GetSpellTexture
	local ok, tex = false, nil
	if type(fn) == "function" then
		ok, tex = pcall(fn, spell)
	end
	return ok and tex or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- one of them up (cast again: its time from now)
function Cds.Start(spell, now)
	local kind = CDS[spell]
	if not (kind and S.ui and CdsOn()) then
		return
	end
	now = now or GetTime()
	local entry
	for _, e in ipairs(S.cds) do
		if e.spell == spell then
			entry = e
		end
	end
	if not entry then
		entry = { spell = spell }
		S.cds[#S.cds + 1] = entry
	end
	local dur = CD_LASTS[spell] or 0
	entry.kind, entry.start, entry.dur, entry.aura = kind, now, dur, nil
	entry.ends = now + (dur > 0 and dur or T.cdUntilUsed)
	C_Timer.After(entry.ends - now + 0.05, Cds.Expire)
	Cds.Refresh()
end

-- the ones whose time is over taken off
function Cds.Expire()
	local now, changed = GetTime(), false
	for i = #S.cds, 1, -1 do
		if S.cds[i].ends <= now + 0.01 then
			table.remove(S.cds, i)
			changed = true
		end
	end
	if changed then
		Cds.Refresh()
	end
end

-- (UNIT_AURA) an aura of a cooldown's kind just after its cast: its own; its own taken: it ends there
function Cds.Aura(info)
	if #S.cds == 0 or type(info) ~= "table" then
		return
	end
	local now, changed = GetTime(), false
	local added, removed = info.addedAuras, info.removedAuraInstanceIDs
	if type(added) == "table" then
		for _, aura in ipairs(added) do
			local id, spell = aura.auraInstanceID, aura.spellId
			local kind = not Secret(spell) and CDS[spell]
			if kind and not Secret(id) then
				for _, e in ipairs(S.cds) do
					if e.aura == nil and e.kind == kind and now - e.start <= T.cdLink then
						e.aura = id
						break
					end
				end
			end
		end
	end
	if type(removed) == "table" then
		for _, r in ipairs(removed) do
			if not Secret(r) then
				for i = #S.cds, 1, -1 do
					if S.cds[i].aura == r then
						table.remove(S.cds, i)
						changed = true
					end
				end
			end
		end
	end
	if changed then
		Cds.Refresh()
	end
end

-- icon i above the health bar (made the first time one is needed, kept): the spell's icon in the round rim, the game's
-- sweep over it, its seconds on top
function Cds.Icon(i)
	local ic = S.cdIcons[i]
	if ic then
		return ic
	end
	ic = W.RoundIcon(S.ui.float, T.cdIcon, nil)
	ic:EnableMouse(false)   -- (the pointer passes through the display to the world)
	ic:SetKit(MelloUI.Kit)
	local sweep = CreateFrame("Cooldown", nil, ic, "CooldownFrameTemplate")
	sweep:SetAllPoints(ic.icon)
	Try(sweep, "SetSwipeTexture", "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
	Try(sweep, "SetDrawEdge", false)
	Try(sweep, "SetHideCountdownNumbers", true)
	Try(sweep, "SetReverse", true)
	sweep:EnableMouse(false)
	ic.sweep = sweep
	local top = CreateFrame("Frame", nil, ic)
	top:SetAllPoints(ic)
	top:SetFrameLevel(sweep:GetFrameLevel() + 1)
	local timer = CreateFrame("StatusBar", nil, top)
	timer:SetAlpha(0)   -- (its seconds only: the engine counts them)
	ic.timer = timer
	local secs = top:CreateFontString(nil, "OVERLAY")
	StyleText(secs, T.text - 1)
	secs:SetPoint("CENTER", ic, "CENTER", 0, 0)
	ic.top, ic.secs = top, secs
	ic.timed = Anim:TimerText(secs, timer)
	S.cdIcons[i] = ic
	return ic
end

-- the row above the health bar, centred: every one up, the most important first. (Big Cooldown Size, the user's
-- video of 2026-10-12: "i need a slider to resize the Big Cooldown icons above my HP bar") Each icon scaled from its
-- made size, its rim, sweep and the gap with it; its seconds kept at the display's text size (over a larger icon
-- they fit inside it, not over the next one's), the row's place over the bar unchanged
function Cds.Icons()
	local ui, list = S.ui, S.cdOrder
	local n = math.min(#list, T.cdMax)
	local above = Dress.Reach(ui.health)
	local k = math.max(12, math.min(40, Num(Db().cdSize) or T.cdIcon)) / T.cdIcon
	for i = 1, n do
		local e, ic = list[i], Cds.Icon(i)
		ic:SetScale(k)
		ic.top:SetScale(1 / k)
		ic:ClearAllPoints()
		ic:SetPoint("BOTTOM", ui.health.strip.fill, "TOP", (i - (n + 1) / 2) * (T.cdIcon + T.cdGap), above / k + T.cdLift)
		ic:SetIcon(SpellIcon(e.spell))
		if e.dur > 0 then
			Try(ic.sweep, "SetCooldown", e.start, e.dur)
			ic.sweep:Show()
			Anim:Timer(ic.timer, e.ends - GetTime(), false)
			ic.secs:SetShown(ic.timed and Db().text ~= false and true or false)
		else
			ic.sweep:Hide()
			Anim:StopTimer(ic.timer)
			ic.secs:Hide()
		end
		ic:Show()
	end
	for i = n + 1, #S.cdIcons do
		S.cdIcons[i]:Hide()
	end
end

-- the row again
function Cds.Refresh()
	if not S.ui then
		return
	end
	wipe(S.cdOrder)
	for _, e in ipairs(S.cds) do
		S.cdOrder[#S.cdOrder + 1] = e
	end
	table.sort(S.cdOrder, CdOrder)
	Cds.Icons()
end

-- all put away (off, the preview's end)
function Cds.Off()
	wipe(S.cds)
	Cds.Refresh()
end

-- (0.21.0, the user 2026-10-12: "the swing timer needs to hide if im using the new ones") the game's own swing timers
-- held off while the rails show the swing (their CVar, the player's own value given back); MelloUI's Swing Timers stand
-- down by themselves (their RailsOn) and hold that CVar while they are on, so here only while they are off
local SWING_CVAR = "showSwingTimer"
local function HoldGameSwing()
	if not (M.db and MelloUI.HoldCVar) then
		return
	end
	local timers = MelloUI:GetModule("SwingTimers")
	local theirs = timers ~= nil and timers.isEnabled == true
	local function Hold()
		if theirs then
			-- (Swing Timers on: it holds them -- the player's own value, kept here while this held them, handed to it;
			-- never written back, or the game's would show beside the rails)
			if M.db.savedSwing ~= nil then
				if timers.db and timers.db.savedSwing == nil then
					timers.db.savedSwing = M.db.savedSwing
				end
				M.db.savedSwing = nil
			end
			return
		end
		MelloUI:HoldCVar(M.db, SWING_CVAR, "savedSwing", SwingOn(), "0")
	end
	if MelloUI.InCombat() and MelloUI.Kit and MelloUI.Kit.WhenOutOfCombat then
		MelloUI.Kit:WhenOutOfCombat(Hold, "Personal Display: the game's swing timers")
	else
		Hold()
	end
end

local function OnModule(name)
	if name == "SwingTimers" and On() then
		HoldGameSwing()
	end
end

-- the game's own display held off while this is on (its CVar, the player's own value given back); out of combat
local function HoldGame()
	if not (M.db and MelloUI.HoldCVar) then
		return
	end
	local function Hold()
		MelloUI:HoldCVar(M.db, GAME_CVAR, "savedGameDisplay", M.isEnabled, "0")
	end
	if MelloUI.InCombat() and MelloUI.Kit and MelloUI.Kit.WhenOutOfCombat then
		MelloUI.Kit:WhenOutOfCombat(Hold, "Personal Display: the game's own display")
	else
		Hold()
	end
end

local function Start()
	if not On() then
		return
	end
	local again = S.ui ~= nil
	local ui = Build()
	if not ui then
		return
	end
	if again then
		-- (switched on again: what changed while it was off -- its border on the Look page, a profile's sizes)
		Refit(ui)
		LayStack(ui)
	end
	ui.holder:Show()
	ui.column.holder:Show()
	Events(true)
	if not S.hooked then
		S.hooked = true
		if rawget(_G, "JumpOrAscendStart") then
			hooksecurefunc("JumpOrAscendStart", OnJump)
		end
		-- (the zoom keys and the mouse wheel: CameraZoomIn / CameraZoomOut, the bindings')
		for _, name in ipairs({ "CameraZoomIn", "CameraZoomOut" }) do
			if rawget(_G, name) then
				hooksecurefunc(name, Zoom.Follow)
			end
		end
	end
	-- (the zoom placed at: the first start's, until Edit Layout moves it)
	if M.db and Num(M.db.zoomRef) == nil then
		M.db.zoomRef = Zoom.Read()
	end
	GameCast.Hold(CastHeld())
	ChargeFrom()
	HoldGameSwing()
	Refresh()
	Place()
end

--------------------------------------------------------------------------------
-- Preview (Core/Preview.lua, part "personal"): a made-up shield and casts on the solo scene's beats, plain amounts
--------------------------------------------------------------------------------

local function SampleHealth(pct)
	local ui = S.ui
	ui.health.bar:SetMinMaxValues(0, 100)
	ui.health.bar:SetValue(pct, EASE)
	ui.health.text:SetFormattedText("%.0f%%", pct)
	ui.power.bar:SetMinMaxValues(0, 100)
	ui.power.bar:SetValue(100, EASE)
	ui.power.text:SetFormattedText("%.0f%%", 100)
end

-- (the preview's own cast ended: a real one begun after the preview's stop left running)
local function PreviewCastOut()
	if S.preview then
		CastOut()
	end
end

local function SampleCast(spec)
	if spec then
		CastShow(spec[1], spec[2], false)
		C_Timer.After(spec[2], PreviewCastOut)
	end
end

local function OnPreview(beat, _, n)
	if beat == "stop" then
		if S.preview then
			S.preview = false
			ShieldOff()
			CastOut()
			Swing.Off()
			Cds.Off()
			Refresh()
		end
		return
	end
	local P = MelloUI.Preview
	if not (On() and S.ui and P and P:Plays(PREVIEW_PART)) then
		return
	end
	if beat == "start" then
		S.preview = true
		ShieldOff()
		S.previewHealth = SAMPLE.health
		SampleHealth(S.previewHealth)
	elseif beat == "pull" then
		Cds.Start(SAMPLE.cooldowns.pull)
		Swing.Start("main", SAMPLE.swing)
		Swing.Start("off", SAMPLE.swing * 2)
		S.previewParts = SAMPLE.parts
		Shield.Apply(SAMPLE.shield)
		SampleCast(SAMPLE.casts.pull)
	elseif beat == "hit" then
		S.previewHealth = math.max(20, (S.previewHealth or SAMPLE.health) - SAMPLE.hurt)
		SampleHealth(S.previewHealth)
		local left = SAMPLE.hits[n]
		if left == 0 then
			Shield.Break()
		elseif left and S.shieldOn then
			Shield.Hit(left)
		end
		if SAMPLE.cooldowns[n] then
			Cds.Start(SAMPLE.cooldowns[n])
		end
		if n == SAMPLE.again then
			S.previewParts = SAMPLE.againParts
			Shield.Apply(SAMPLE.againAmount)
		end
		SampleCast(SAMPLE.casts[n])
		Swing.Start("main", SAMPLE.swing)
		if n % 2 == 0 then
			Swing.Start("off", SAMPLE.swing * 2)
		end
	elseif beat == "kill" then
		if S.shieldOn then
			Shield.Break()
		end
		SampleHealth(SAMPLE.health)
	end
end

--------------------------------------------------------------------------------
-- The module
--------------------------------------------------------------------------------

M = MelloUI:RegisterModule("PersonalDisplay", {
	title = "Personal Display",
	desc = "Your health, power and cast bar under your character, as Legion's resource display had them, and a shield column beside your character: it fills when a shield goes up, drains as it takes the hits, turns amber when low and breaks when it is gone. The game's own Personal Resource Display is switched off while this is on, and comes back as you had it when it is off; Hide The Game's Cast Bar (on) hides the game's cast bar too, and Swing On The Rails (on) stands in for Swing Timers. This client cannot tell an addon where your character stands, so the display stays where you put it in Edit Layout (under your character to begin with) and hops when you jump.",
	icon = "Interface\\Icons\\Spell_Holy_PowerWordShield",
	flavour = "Health, power, casts and shields, right by your character.",
	role = "replaces",
	slash = "personal",
	new = NEW,
	enabledByDefault = false,
	installer = false,
	-- the player's own game setting, given back when off, and the camera zoom the display was placed at: never in a
	-- profile
	keep = { "savedGameDisplay", "zoomRef", "savedSwing" },
	defaults = { width = 160, height = 10, shield = true, text = true, hop = true, zoom = true, hideCastBar = true,
		healFrom = true, swing = true, cooldowns = true, cdSize = 16 },
	options = {
		{ type = "toggle", key = "shield", name = "Shield Column", new = NEW,
		  desc = "An upright bar beside your character for every shield on you added up, as the game counts them: spells (Power Word: Shield, Ice Barrier, Mana Shield, the wards), talents and items, the ones against one kind of damage too. Each shield is its own part, in its school's colour (Power Word: Shield gold, Ice Barrier frost, Mana Shield arcane, a Fire Protection Potion fire), stacked in the order they went up, its icon beside the column. It fills when one goes up, drains as it takes the hits, turns amber when low and breaks when the last one is gone; one ending while another holds only takes its part away. Edit Layout places it." },
		{ type = "toggle", key = "hideCastBar", name = "Hide The Game's Cast Bar", new = NEW,
		  desc = "The game's own cast bar is hidden while this is on: your casts show on the display's cast bar under your character. Off: both show." },
		{ type = "toggle", key = "healFrom", name = "Heal Light From Your Character", new = NEW,
		  desc = "With Heal Effects on (Frame Effects > Heals): the light of a heal you cast gathers at your character's middle instead of on the cast bar, and flies from there to the party or raid frame of the one you heal. It follows the display's place and the camera's zoom." },
		{ type = "toggle", key = "swing", name = "Swing On The Rails", new = NEW,
		  desc = "Your swing timer without a bar of its own: in a fight, two sparks run out from the middle of the health bar's top rail to its ends, and your swing lands as they reach them. An off hand's swings run along the bottom of the power bar. Your shots run on the seam between the health and power bars: cream sparks out while you reload, then a red line grows back from the ends while you aim (stand still: moving holds it), and the shot flies as it meets in the middle. A wand's shots run out once, with no aim. While it is on, MelloUI's Swing Timers step aside and the game's own swing timers stay off." },
		{ type = "toggle", key = "cooldowns", name = "Big Cooldowns", new = NEW,
		  desc = "The buffs you give yourself on a cooldown -- Shield Wall, Shield Block, Last Stand, Evasion, Ice Block, Recklessness, a trinket's -- as icons above the health bar, their time sweeping round them and their seconds on them, the most important first: an immunity, then damage taken down, more health, block, evasion, the rest. From the game's own spell data, for every class." },
		{ type = "toggle", key = "text", name = "Percent And Spell Text", new = NEW,
		  desc = "Your health and power in percent beside their bars, the spell and its seconds on the cast bar, and the shield's amount under its column." },
		{ type = "toggle", key = "hop", name = "Hop When You Jump", new = NEW,
		  desc = "The display hops with you when you jump, as Legion's did under your character. Reduce Motion keeps it still." },
		{ type = "slider", key = "width", name = "Width", new = NEW, min = 100, max = 260, step = 5,
		  desc = "How wide the health, power and cast bars are. Edit Layout sizes the whole display." },
		{ type = "slider", key = "height", name = "Height", new = NEW, min = 5, max = 16, step = 1,
		  desc = "How tall the health bar is; the power and cast bars are a little thinner, in step with it. Their frames grow and shrink with them." },
		{ type = "slider", key = "cdSize", name = "Big Cooldown Size", new = NEW, min = 12, max = 40, step = 1,
		  desc = "How big the Big Cooldowns' icons above the health bar are. Their seconds keep the display's text size." },
		{ type = "toggle", key = "zoom", name = "Follow Camera Zoom", new = NEW,
		  desc = "The display keeps its place by your character as you zoom the camera: closer under your feet when you zoom out, further down when you zoom in, so it never covers your character. Place it in Edit Layout at the zoom you play at; it follows from there. Turning the camera up or down is not followed (the game does not tell)." },
		{ type = "button", name = "Preview", text = "Play", new = NEW,
		  hint = "a shield going up, hit, low and broken, and casts",
		  desc = "Plays a made-up fight on the display: a shield going up, taking hits until it is low and breaks, a cast and a second shield. Also /mello personal test.",
		  onClick = function() M.Preview() end },
	},
})

function M.Preview()
	if not On() then
		return
	end
	local P = MelloUI.Preview
	if P and P.Slash then
		P.Slash(PREVIEW_PART)
	end
end

function M:SlashTest()
	M.Preview()
end

-- /mello personal secrets: what this client hands over plain or secret for the display
local function Kind(ok, v)
	if not ok then
		return TEXT.failed:format(tostring(v))
	end
	if Secret(v) then
		return TEXT.secret
	end
	if v == nil then
		return TEXT.none
	end
	return TEXT.plain .. " (" .. tostring(v) .. ")"
end

local function SecretsLog()
	MelloUI:ClearLog()
	local function Read(label, fn, ...)
		if type(fn) ~= "function" then
			MelloUI:Print("  %-28s not on this client", label)
			return
		end
		local ok, v = pcall(fn, ...)
		MelloUI:Print("  %-28s %s", label, Kind(ok, v))
	end
	MelloUI:Print("Personal Display: the player's values now")
	Read("UnitHealth", UnitHealth, "player")
	Read("UnitHealthMax", UnitHealthMax, "player")
	Read("UnitHealthPercent (curve)", rawget(_G, "UnitHealthPercent"), "player", true, Curve())
	Read("UnitPower", UnitPower, "player")
	Read("UnitPowerPercent (curve)", rawget(_G, "UnitPowerPercent"), "player", nil, false, Curve())
	Read("UnitGetTotalAbsorbs", rawget(_G, "UnitGetTotalAbsorbs"), "player")
	Read("IsFalling", rawget(_G, "IsFalling"))
	Read("GetCameraZoom", rawget(_G, "GetCameraZoom"))
	MelloUI:Print("Follow Camera Zoom: placed at zoom %s, scaled by %.2f now", tostring(Num(Db().zoomRef) or "?"),
		Zoom.Factor())
	MelloUI:Print("Read while it ran: the shield %s, the cast's times %s", S.reads.shield or "not yet",
		S.reads.cast or "not yet (cast something with a cast time)")
	MelloUI:Print("The shield's last reads, oldest first:")
	for _, line in ipairs(S.reads.path) do
		MelloUI:Print("  %s", line)
	end
	-- (the user's pick B of prd_multishield, 2026-10-12: a part for each shield -- spells, talents, items -- needs each
	-- one's own amount and spell; read here, in a fight and out of it, before it is built)
	MelloUI:Print("The shields' own auras known now (%d), as the game hands them:", #S.shieldIDs)
	local api = _G.C_UnitAuras
	local get = api and api.GetAuraDataByAuraInstanceID
	for _, id in ipairs(S.shieldIDs) do
		local ok, aura = false, nil
		if type(get) == "function" then
			ok, aura = pcall(get, "player", id)
		end
		if not ok or Secret(aura) or type(aura) ~= "table" then
			MelloUI:Print("  aura %s: %s", tostring(id), Kind(ok, aura))
		else
			local points, parts = aura.points, {}
			if Secret(points) then
				parts[1] = "secret"
			elseif type(points) == "table" then
				for i = 1, #points do
					parts[#parts + 1] = Kind(true, points[i])
				end
			end
			MelloUI:Print("  aura %s: spell %s, name %s, amounts [%s]", tostring(id), Kind(true, aura.spellId),
				Kind(true, aura.name), table.concat(parts, ", "))
		end
	end
	if #S.shieldIDs == 0 then
		MelloUI:Print("  (none: put a shield up, then type this again -- in a fight and out of it)")
	end
	MelloUI:ShowLog(TEXT.secrets)
end
M.SlashWords = { secrets = SecretsLog }

-- Edit Layout's plates: the display made when it opens (its movers with it), never at login
local function MoverSource()
	if On() then
		Build()
	end
end

function M:OnInit(db)
	self.db = db
	MelloUI:AddMoverSource(MoverSource)
end

function M:OnAddonLoaded(db)
	self.db = db
end

-- the Bar Texture set or switched: the fills again (the Unit Frames page's Personal Display pick's for the bars and the
-- column, as Group Frames wear the Raid Frames pick's; the cast bars' for the cast)
local function UnitFill()
	local ui = S.ui
	if ui then
		local fill = W.BarFill("personal")
		ui.health.bar:SetStatusBarTexture(fill)
		ui.power.bar:SetStatusBarTexture(fill)
		ui.column.bar:SetStatusBarTexture(fill)
		ui.column.loss:SetStatusBarTexture(fill)
	end
end

local function CastFill()
	if S.ui then
		S.ui.cast.bar:SetStatusBarTexture(W.BarFill("castbars"))
	end
end

-- Look > Borders' Personal Resource Border changed (the kit's 'border' on the bus): every part in the new look
local function OnBorder(kind)
	local ui = S.ui
	if kind == "personal" and ui then
		Dress.Apply(ui)
		LayStack(ui)
		Place()
	end
end

function M:OnEnable(db)
	self.db = db or self.db
	MelloUI:On("preview", OnPreview, OWNER)
	MelloUI:On("editlayout", OnEditLayout, OWNER)
	MelloUI:On("module", OnModule, OWNER)
	MelloUI:On("border", OnBorder, OWNER)
	if not S.watching then
		-- (once: their owners' own listeners on the bus; with nothing made they do nothing)
		S.watching = true
		W.OnBarTexture("personal", UnitFill, OWNER .. ": the bars' fill")
		W.OnBarTexture("castbars", CastFill, OWNER .. ": the cast bar's fill")
	end
	HoldGame()
	MelloUI:AfterLogin(Start)
end

function M:OnDisable()
	MelloUI:Off(OWNER)
	Events(false)
	Cds.Off()
	HoldGame()
	GameCast.Hold(false)
	ChargeFrom()
	Swing.Off()
	HoldGameSwing()
	S.preview = false
	ShieldOff()
	local ui = S.ui
	if ui then
		Anim:StopTimer(ui.cast.bar)
		S.casting = false
		Anim:Stop(ui.cast.strip, "alpha")
		ui.cast.strip:SetAlpha(0)
		ui.cast.strip:Hide()
		Anim:Stop(ui.holder, "drive")
		Zoom.following = false
		Perf.SetScript(S.zoomFrame, "OnUpdate", nil)
		S.editing = false
		HopDone()
		ui.holder:Hide()
		ui.column.holder:Hide()
	end
end

function M:OnSettingChanged(key, _, db)
	self.db = db or self.db
	local ui = S.ui
	if not ui then
		return
	end
	if key == "width" or key == "height" then
		if key == "height" then
			Refit(ui)
		end
		LayStack(ui)
		Place()
	elseif key == "zoom" then
		Place()
	elseif key == "hideCastBar" then
		GameCast.Hold(CastHeld())
	elseif key == "healFrom" then
		ChargeFrom()
	elseif key == "swing" then
		if not SwingOn() then
			Swing.Off()
		end
		Events(true)
		HoldGameSwing()
	elseif key == "shield" then
		if Db().shield == false then
			ShieldOff()
		else
			Refresh()
		end
	elseif key == "text" then
		Refresh()
		Cds.Refresh()
	elseif key == "cooldowns" then
		if not CdsOn() then
			Cds.Off()
		end
	elseif key == "cdSize" then
		Cds.Icons()
	end
end

-- the state (the Fader reads the cast from it), the timings, the ranged swing's stages and the big cooldowns (the tests)
M.S = S
M.T = T
M.Ranged = Ranged
M.Cds = Cds

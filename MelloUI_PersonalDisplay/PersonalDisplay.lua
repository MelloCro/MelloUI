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
--   the bars    health and power in the kit's bracket (Kit:Bar; without MelloUI_Oldschool's painted engine a flat fill
--               on a dark track with a thin border, PlainStrip), their percent the game's own curve
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
-- Motion (0.25.0, the section after the hop): the bars answer the fight -- the part a hit or a cost took held lit and
-- drained, a heal or a gain lit ahead of the bar, a heavy blow's red rim, the dodge's word, low health ember, a stun
-- run down under the bars, the bars settled out of a fight.
-- Nothing at login but the frames it shows (built in the frame after it is switched on); its events only while it is
-- on.
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
	-- (the swing badge, 1.2.0: MelloUI.SwingBadge's, Core/SwingBadge.lua) its size under the display (its units) and
	-- the gap to the health bar's end there
	badgeHere = 22, badgeGap = 4,
	-- (the shields in parts, the user's pick B of prd_multishield) at most this many parts (more: the one total), their
	-- icons' size beside the column and the gap between them
	partMax = 6, partIcon = 11, partGap = 2,
	-- (Big Cooldowns) the icons above the health bar: their size as made (Big Cooldown Size scales them from it), the
	-- gap between them, how far over the bar's painted top, at most this many; one lasting "until used" with no aura of
	-- it seen, ended after this long
	cdIcon = 16, cdGap = 3, cdLift = 2, cdMax = 4, cdUntilUsed = 30,
	-- (1.2.0, animations round 3) the icons' motion: the pop-in, the row's glide, the end's flash and shrink, and how
	-- long before its end an icon turns ember
	cdPop = 0.32, cdGlide = 0.25, cdEnd = 0.3, cdEmber = 1.5,
	cdLink = 1.5,   -- an aura of a cooldown's kind this soon after its cast: its own (its early end ends it)
	-- (Motion, the user's "aproved" to the Personal Display Motion page) the part lost held this long, then drained;
	-- the ghost's strength; the lead's lift toward white; a heavy blow's rim and its dip (how deep, how long); the low
	-- health share, its colour's edge, its beat; a big gain's share of the bar (its spark), the spark's size (its width,
	-- its height a share of the power fill's) and fade; the rim's soft glow past the bracket's painted edge (at its ends,
	-- over and under; its solid core tucked this far inside the art); the word's place, way and time; the loss of
	-- control's line, its rim's strength, its fades, its grace past its time; the settle: the bars' rest out of a fight
	-- (dimmed, a little lower), the wait before they settle, the times in and out
	ghostDelay = 0.24, ghostAlpha = 0.85, pale = 0.6,
	heavyRim = 0.38, dipDepth = 3, dip = 0.2,
	lowHealth = 0.35, lowEdge = 0.001, beat = 0.6,
	sparkShare = 0.08, sparkW = 8, sparkH = 2.4, spark = 0.42,
	rimFeather = 12, rimFeatherY = 9, rimTuck = 3,
	wordX = 4, wordY = 2, wordDX = 22, wordDY = 8, word = 0.85,
	lineH = 3, locRim = 0.8, locFade = 0.15, locGrace = 0.2,
	restDrop = 5, settleDelay = 0.3, settleIn = 0.34, settleOut = 0.7,
	-- (1.2.0, Gilded: the user's pick A of prd_looks) the gold rim's rail past every fill; health to power, fill to fill,
	-- and the trim's hairline between them; the cast's spell icon, a share of the cast fill's depth; the soft shade
	-- under the rims (its strength, its feather)
	rim = 2.7, joint = 3, hair = 1, hairAlpha = 0.55, castIcon = 1.7, shade = 0.5, shadeFeather = 4,
	-- (1.2.0, the ten motions: the user's "All of them" to prd_motion2, seen in look A) the cast bar opening from its
	-- middle (from this wide), the light on its head (its glow, its core); a cast landed: the flash, the light off its
	-- end (how far, how long), the fold (when, how long, to this deep); cut: the jolt (how long, how far), the drop
	-- (when, how long, how far); pushed back: the old fill held, then faded, the red at the head
	unfold = 0.2, unfoldFrom = 12, head = 12, headCore = 5,
	flash = 0.35, landRun = 30, landStreak = 26, landTip = 10, land = 0.4, foldAt = 0.22, fold = 0.2, foldTo = 2,
	jolt = 0.3, joltX = 3, dropAt = 0.45, drop = 0.35, dropY = 6,
	pushHold = 0.24, pushFade = 0.46, castLate = 0.4,
	-- a heal's rush over the part it gave (how long, the light's width) and the light at its end; a heal heard this
	-- recently (UNIT_COMBAT) makes the next health change one; the glint along the bar back at full (its share of
	-- the bar, the glint's width, how long)
	rush = 0.38, rushW = 18, rushEnd = 0.35, rushGlow = 16, healRecent = 0.4,
	full = 0.995, glintW = 14, glint = 0.55,
	-- a heavy blow's shards: how long they fall, how far down at the end, how far apart sideways
	shards = 0.75, shardFall = 40, shardSpread = 9,
	-- a big spend (a plain share of the bar at least): the block dropped, how far, how long
	spendShare = 0.15, spendDrop = 6, spendTime = 0.45,
	-- into a fight: the gold line (grown, held, faded), the bars opening from their middle; out of it the slim rest
	-- (the fills' depths) and its percents out
	openLine = 0.2, openHold = 0.25, openFade = 0.3, open = 0.25, openFrom = 0.02, restHealth = 3, restPower = 2,
	-- death: the fills drained, greyed, folded (to this deep); back: unfolded, filled with the sweep
	deathDrain = 0.4, deathGrey = 0.5, deathFold = 0.35, deathAt = 0.8, deathTo = 1.5, back = 0.3, backFill = 0.6,
	-- (the shield crack) its shards: how many, how long, how far out
	crackN = 6, crack = 0.7, crackOut = 22,
}
local TEXT = {
	bars = "Personal Display",
	column = "Shield Column",
	secrets = "Personal Display: what this client hands over",
	plain = "plain",
	secret = "secret",
	none = "nothing",
	failed = "refused (%s)",
	-- (Motion) the words where the game's own strings are missing
	stunned = "Stunned",
	interrupted = "Interrupted", castFailed = "Failed",   -- (1.2.0, Cast Motion: a cut cast's word)
	words = { DODGE = "Dodge", PARRY = "Parry", BLOCK = "Block", MISS = "Miss" },
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
	-- (Motion) the power at the start, gained each hit, spent at these hits; a critical blow at the fifth (it takes
	-- this much), a dodge, a parry and a block, a stun at the tenth for 1.7 s (the user's clip, 2026-10-18; no cast
	-- of the preview's running then)
	power = 30, gain = 9, spend = { [4] = 30, [8] = 25, [11] = 30 },
	crit = 5, critHurt = 30, avoid = { [3] = "DODGE", [9] = "PARRY", [12] = "BLOCK" }, stun = { 10, 1.7 },
	hits = { [1] = 470, [2] = 340, [3] = 230, [4] = 150, [5] = 70, [6] = 0, [10] = 260 },
	again = 9, againAmount = 420,
	health = 100, hurt = 4,              -- the health falling this many % a hit
	casts = { pull = { "Power Word: Shield", 1.2, 17 }, [7] = { "Flash Heal", 1.5, 2061 } },   -- (name, seconds, spell)
	swing = 0.9,                         -- the main hand's swing (the scene's hit spacing), the off hand's twice it
	-- (the swing badge) your blows' outcomes as the game would report them: a critical one, a parry
	outcomes = { [4] = { "WOUND", "CRITICAL" }, [9] = { "PARRY" } },
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
	cds = {}, cdOrder = {}, cdIcons = {}, cdSpare = {},   -- (cdIcons every icon made, cdSpare the free ones)
	casting = false, hopping = false, hooked = false, preview = false, previewHealth = nil,
	watching = false,
	reads = { shield = nil, cast = nil, path = {} },   -- what was read plain or secret (/mello personal secrets)
	texts = setmetatable({}, { __mode = "k" }),   -- [fs] = its size: the texts in Text Font's face (StyleText)
}
local Shield = {}
local Motion = {}   -- (0.25.0: the bars answering the fight; its section after the hop)
local Gilded = {}   -- (1.2.0: the modern look's gold rims; its section after the bars' look)
local CastFX = {}   -- (1.2.0, Cast Motion: the cast bar's moments; in the cast bar's section)

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

-- the health bar's colour: your class's with Class Colours (C_ClassColor, else the plain RAID_CLASS_COLORS, as the
-- group frames read it), else the meaning green
local function HealthRGB()
	if Db().classColour then
		local ok, _, class = pcall(UnitClass, "player")
		if ok and class ~= nil then
			local CC = rawget(_G, "C_ClassColor")
			if type(CC) == "table" and type(CC.GetClassColor) == "function" then
				local okC, c = pcall(CC.GetClassColor, class)
				if okC and c and c.GetRGB then
					return c:GetRGB()
				end
			end
			local t = not Secret(class) and rawget(_G, "RAID_CLASS_COLORS") and RAID_CLASS_COLORS[class]
			if t then
				return t.r, t.g, t.b
			end
		end
	end
	local c = MelloUI.Meaning.personalHealth
	return c[1], c[2], c[3]
end

local function PaintHealth(bar)
	bar:SetStatusBarColor(HealthRGB())
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
	-- (one look C11: their own face, Text Font; Shared the Interface text's)
	S.texts[fs] = size
	MelloUI.Look.Text(fs, "text", size, { face = Db().textFont })
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

-- (one look stage I, step 4) the bar without the painted engine (MelloUI_Oldschool not loaded): the Personal
-- Display's own -- a flat fill on a dark track, in the palette -- in the shape Kit:Bar and Kit:VBar hand back (the
-- fill, the trough, the insets, the arms, SetBarLook / SetBarScale), dressed as "gilded" (Dress.Value; 1.2.0, the
-- user's pick A of prd_looks: its 1 px border of 0.21.0 went for the gold rims, Gilded). The track on the fill, under
-- the Motion layers as the bracket's trough is
local function PlainStrip(parent, vertical)
	local strip = CreateFrame("Frame", nil, parent)
	local fill = CreateFrame("Frame", nil, strip)
	fill:SetFrameLevel(strip:GetFrameLevel() + 1)
	fill:SetPoint("TOPLEFT", strip, "TOPLEFT", 1, -1)
	fill:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", -1, 1)
	strip.fill = fill
	strip.trough = W.Solid(fill, "BACKGROUND", "innerPanel", 0.9)
	strip.trough:SetAllPoints(fill)
	strip.plain, strip.vertical = true, vertical or nil
	strip.insets, strip.wl, strip.wr = { 1, 1, 1, 1 }, 1, 1
	function strip.GetInsets()
		return 1, 1, 1, 1
	end
	function strip.SetBarLook(self)
		if self.vertical then
			self:SetWidth(T.colW + 2)
		end
		return true
	end
	function strip.SetBarScale() end
	if vertical then
		strip:SetWidth(T.colW + 2)
	end
	return strip
end

-- one bar: the bracket (Kit:Bar) round a fill `h` tall and the Width() wide, a StatusBar on its opening. Layered
-- (health, power: Motion): the ghost and the lead under it, a level each, the bracket's art lifted over all three
local function NewBar(parent, h, area, layered)
	local Kit = MelloUI.Kit
	local strip = Kit.Bar and Kit:Bar(parent, { kind = "frame", scale = h / Rows("frame") }) or PlainStrip(parent)
	local level = parent:GetFrameLevel()
	local ghost, lead
	if layered then
		strip:SetFrameLevel(level + 5)
		strip.fill:SetFrameLevel(level + 1)
		ghost = Motion.Fill(strip.fill, area, level + 2)
		lead = Motion.Fill(strip.fill, area, level + 3)
	end
	local bar = CreateFrame("StatusBar", nil, strip.fill)
	if layered then
		bar:SetFrameLevel(level + 4)
	end
	bar:SetAllPoints(strip.fill)
	bar:SetStatusBarTexture(W.BarFill(area))
	W.SoftEnds(bar)   -- (every bar's ends soft: the user, 2026-10-16)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	local b = { strip = strip, bar = bar, kind = "frame", ghost = ghost, lead = lead }
	Fit(b, h)
	return b
end

-- (Motion) a fill under the bar: the ghost (the part lost) or the lead (the part gained)
function Motion.Fill(parent, area, level)
	local f = CreateFrame("StatusBar", nil, parent)
	f:SetAllPoints(parent)
	f:SetFrameLevel(level)
	f:SetStatusBarTexture(W.BarFill(area))
	W.SoftEnds(f)
	f:SetMinMaxValues(0, 1)
	f:SetValue(1)
	return f
end

--------------------------------------------------------------------------------
-- The bars' look (0.21.0, the user: "i also want to be able to change the borders from the personal resources, they
-- should reflect the changes made in the Look -> Borders"; the pick: Personal Resource Border with every bar look):
-- a bracket look in place (Kit:Bar's and Kit:VBar's SetBarLook), a style of the border library round each fill
-- (Kit:NewBorder, the bracket put out, the trough run half a rail under it as Kit:BarLibraryFit does), or none (the
-- fill on its trough). Each bar's reach -- its painted frame past its fill, over and under -- stacks the bars; its
-- painted width past the fill places the swing badge at the display's left end
--------------------------------------------------------------------------------
local Dress = {}

function Dress.Value()
	local Kit = MelloUI.Kit
	if not (Kit and Kit.Bar) then
		return "gilded"   -- (the plain strip in MelloUI's gold rims: 1.2.0, Gilded)
	end
	return Kit.BorderValue and Kit:BorderValue("personal") or "frame"
end

-- a value's bracket look (its own bar pieces; an unknown one the Ornate), nil for a library style or none
function Dress.Kind(value)
	local Kit = MelloUI.Kit
	if value == "none" or value == "gilded" or (Kit.BorderStyles and Kit.BorderStyles[value]) then
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
	b.gilded = value == "gilded"
	b.style = (not kind and value ~= "none" and not b.gilded) and value or nil
	b.bare = value == "none" or b.gilded
	-- (a library style or none: the Ornate strip, put out, keeps the fill where it was; the plain strip: no pieces)
	b.kind = b.strip.plain and "plain" or kind or "frame"
	Fit(b, b.h)
	local strip = b.strip
	strip:SetBarLook(b.kind)
	strip:SetBarScale(b.scale)
	if strip.plain then
		strip:SetHeight(b.h + 2)
	end
	Dress.Pieces(strip, kind ~= nil)
	Dress.Round(b, strip.fill, b.style, b.h)
	Dress.Trough(b, strip)
end

-- the shield column in the look `value` (its upright pieces; a bracket look with none: the Ornate's)
function Dress.Column(col, value)
	local kind = Dress.Kind(value)
	col.gilded = value == "gilded"
	col.style = (not kind and value ~= "none" and not col.gilded) and value or nil
	col.bare = value == "none" or col.gilded
	col.kind = col.strip.plain and "plain" or kind or "frame"
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
	if value == "gilded" and ui.column then
		Gilded.Make(ui)
	end
end

-- a bar's painted reach past its fill, over and under
function Dress.Reach(b)
	if b.gilded then
		return Gilded.Reach(b)
	elseif b.style and b.border then
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
	if b.gilded then
		return 2 * T.rim
	elseif b.style and b.border then
		return 2 * b.border:Inset()
	elseif b.bare then
		return 0
	end
	return b.arms
end

--------------------------------------------------------------------------------
-- Gilded (1.2.0; the user, 2026-10-22: "lets try with some custom borders for hp, mana and cast bar", "Dont forget
-- the shield bar"; their pick "I would go with A" of BuildData/output/animation_previews/prd_looks.html): the modern
-- look's frames in MelloUI's gold rim (W.RimArt) -- health and power in one, a dark joint between them with a hairline
-- of trim; the cast bar in its own, the spell's icon in the gold ring (W.RoundIcon) at its left; the shield column in
-- its own -- a soft shade under each (MelloUI.Shade). Made the first time the look is laid (the build, with no painted
-- engine), kept; laid again with the stack (LayStack)
--------------------------------------------------------------------------------

-- a bar's reach past its fill: the rim over and under; health and power one frame, the joint between them
function Gilded.Reach(b)
	local ui = S.ui
	local half = (T.joint - T.gap) / 2
	if ui and b == ui.health then
		return T.rim, half
	elseif ui and b == ui.power then
		return half, T.rim
	end
	return T.rim, T.rim
end

-- a rim on a frame of its own at `level` (laid by Gilded.Round), its shade on `under` (a frame under the fills)
function Gilded.Rim(parent, level, under)
	local f = CreateFrame("Frame", nil, parent)
	f:SetFrameLevel(level)
	f.art = f:CreateTexture(nil, "OVERLAY")
	W.RimArt(f.art, T.rim)
	f.art:SetAllPoints(f)
	local Shade = MelloUI.Shade
	f.shade = Shade and Shade:Band(under, { alpha = T.shade, feather = T.shadeFeather, featherY = T.shadeFeather,
		sublevel = -8 })
	return f
end

-- round `from`'s top left to `to`'s bottom right, the rail past them; its shade under it
function Gilded.Round(f, from, to)
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", from, "TOPLEFT", -T.rim, T.rim)
	f:SetPoint("BOTTOMRIGHT", to, "BOTTOMRIGHT", T.rim, -T.rim)
	if f.shade then
		f.shade:Anchor(f, -1, -1)
	end
end

-- the pieces (once): the block's dark joint under the fills (over the Motion rims), its hairline, its rim over them;
-- the cast bar's rim and icon on its strip (its fades and folds theirs); the column's rim
function Gilded.Make(ui)
	if ui.gild then
		return
	end
	local level = ui.float:GetFrameLevel()
	local g = {}
	g.back = CreateFrame("Frame", nil, ui.float)
	g.back:SetFrameLevel(level + 1)
	g.joint = W.Solid(g.back, "BACKGROUND", "innerPanel", 1)
	g.joint:SetDrawLayer("BACKGROUND", -7)
	g.joint:SetAllPoints(g.back)
	g.hair = W.Solid(g.back, "BACKGROUND", "trim", T.hairAlpha)
	g.hair:SetDrawLayer("BACKGROUND", -6)
	g.block = Gilded.Rim(ui.float, level + 6, g.back)
	local cast = ui.cast
	g.cast = Gilded.Rim(cast.strip, cast.bar:GetFrameLevel() + 2, cast.strip)
	local icon = W.RoundIcon(cast.strip, 16, nil)
	icon:EnableMouse(false)   -- (the pointer passes through the display to the world)
	icon:SetFrameLevel(cast.bar:GetFrameLevel() + 3)
	g.icon = icon
	local col = ui.column
	g.column = Gilded.Rim(col.strip, col.bar:GetFrameLevel() + 3, col.strip)
	ui.gild = g
end

-- (LayStack) every piece round its fills, shown in the gilded look only
function Gilded.Lay(ui)
	local g = ui.gild
	if not g then
		return
	end
	local on = ui.look == "gilded"
	for _, f in ipairs({ g.back, g.block, g.cast, g.icon, g.column }) do
		f:SetShown(on)
	end
	if not on then
		return
	end
	local hf, pf = ui.health.strip.fill, ui.power.strip.fill
	g.back:ClearAllPoints()
	g.back:SetPoint("TOPLEFT", hf, "TOPLEFT")
	g.back:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT")
	local y = -(T.joint - T.hair) / 2
	g.hair:ClearAllPoints()
	g.hair:SetPoint("TOPLEFT", hf, "BOTTOMLEFT", 0, y)
	g.hair:SetPoint("TOPRIGHT", hf, "BOTTOMRIGHT", 0, y)
	g.hair:SetHeight(T.hair)
	Gilded.Round(g.block, hf, pf)
	local cf = ui.cast.strip.fill
	Gilded.Round(g.cast, cf, cf)
	-- (the icon's ring over the rail's left end, its right edge on the fill's)
	local d = math.floor(T.castIcon * ui.cast.h + 0.5)
	g.icon.size = d
	g.icon:SetSize(d, d)
	g.icon:SetKit(false)
	g.icon:ClearAllPoints()
	g.icon:SetPoint("RIGHT", cf, "LEFT", 0, 0)
	local colFill = ui.column.strip.fill
	Gilded.Round(g.column, colFill, colFill)
end

-- the cast's spell icon (plain or secret: the texture takes it), the question mark when there is none
function Gilded.Icon(texture)
	local g = S.ui and S.ui.gild
	if g and not (texture ~= nil and pcall(g.icon.icon.SetTexture, g.icon.icon, texture)) then
		g.icon.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
	end
end

-- the rims' colour: a meaning's (a cut cast's red), or the palette's gold again
function Gilded.Tint(f, key)
	local c = key and MelloUI.Meaning[key]
	if c then
		f.art:SetVertexColor(c[1], c[2], c[3])
	else
		W.Paint(f.art, "selectedTrim", "vertex", 1)
	end
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

-- (the glows: Frame Effects' own art, added; Motion's spark, Big Cooldowns' light)
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

-- (the swing badge: MelloUI.SwingBadge, the one for everyone; this display one of its hosts -- below, at Events --
-- laid again with the stack, its place under the display)
local SB = MelloUI.SwingBadge
local SwingOn   -- (below)

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
			-- each painted top a gap under the one before's painted foot (kept: the cast bar's moves start there)
			b.anchorTo, b.anchorY = prev.strip.fill, top - (prevBelow + T.gap + above)
			b.strip:SetPoint("TOP", b.anchorTo, "BOTTOM", 0, b.anchorY)
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
	Gilded.Lay(ui)
	if SwingOn() then
		SB.Lay()
	end
	Motion.Lay(ui)
	Motion.FormApply()   -- (the bars' form again: at rest, folded, opening)
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
	if not Kit then
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
	ui.health = NewBar(float, hh, "personal", true)
	ui.power = NewBar(float, hp, "personal", true)
	ui.cast = NewBar(float, hc, "castbars")
	ui.stack = { ui.health, ui.power, ui.cast }
	PaintHealth(ui.health.bar)
	Paint(ui.cast.bar, "personalCast")
	Motion.Make(ui)
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
	CastFX.Make(ui)
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
	local strip = Kit.VBar and Kit:VBar(clip, { kind = "frame", width = Dress.Across("frame") }) or PlainStrip(clip, true)
	local ins = strip.insets
	strip:SetHeight(T.colH + ins[3] + ins[4])
	strip:SetPoint("CENTER", colFloat, "CENTER")
	colHolder:SetSize(strip:GetWidth(), strip:GetHeight())
	-- (the presence's fill covers the column, its rim and its number under it)
	presence:SetPoint("TOPLEFT", strip, "TOPLEFT", -T.text, T.gap + T.rim)
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
	Motion.MakeCrack(ui)
	-- every part in the Personal Resource Border's look, the bars stacked by it
	Dress.Apply(ui)
	LayStack(ui)
	-- (Follow Camera Zoom's frame: its OnUpdate set only while the zoom moves)
	S.zoomFrame = CreateFrame("Frame", nil, holder)

	-- Edit Layout: each where it stands
	ui.entry = MelloUI:RegisterMover(holder, holder, { key = "personalbars", default = Home("bars"), min = 0.5, max = 2,
		base = 1, label = TEXT.bars, page = OWNER, when = On, placeholder = true })
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
		Motion.Value(ui.health, max, v)
		-- (its share only where both read plain: the beat as it turns low; else the game's curves, secret)
		local pm, pv = Num(max), Num(v)
		local share = pm and pv and pm > 0 and pv / pm or nil
		Motion.Low(share)
		Motion.HealthMoment(share, S.healAt and GetTime() - S.healAt < T.healRecent)
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
	local plain = okT and not Secret(token) and type(token) == "string" and token or nil
	-- (another power -- a druid's form --: its fills set at once, no cost or gain shown)
	local shifted = plain ~= S.powerToken
	S.powerToken = plain
	local c = plain and type(colours) == "table" and colours[plain]
	if c and c.r then
		ui.power.bar:SetStatusBarColor(c.r, c.g, c.b)
		ui.power.lead:SetStatusBarColor(Motion.Pale(c.r, c.g, c.b))
	else
		Paint(ui.power.bar, "combatResource")
		local m = MelloUI.Meaning.combatResource
		ui.power.lead:SetStatusBarColor(Motion.Pale(m[1], m[2], m[3]))
	end
	local okM, max = pcall(UnitPowerMax, "player")
	local okV, v = pcall(UnitPower, "player")
	if okM and okV and Usable(max) and Usable(v) then
		ui.power.bar:SetMinMaxValues(0, max)
		ui.power.bar:SetValue(v, EASE)
		Motion.Value(ui.power, max, v, shifted)
		if shifted then
			S.powerLast = nil
		end
		Motion.Gain(Num(max), Num(v), plain)
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

-- (1.2.0, Cast Motion; the user's "All of them" to prd_motion2, seen in look A) the cast bar's moments: a cast begun
-- opens the bar from its middle, a light on its head running with the fill (anchored to the fill's edge: the engine
-- moves it, no Lua a frame); one landed flashes, sends a light off the bar's end and folds it; one cut turns red, jolts,
-- says why and drops; a pushback holds the old fill a moment, the head red. Told by the events (SUCCEEDED before STOP:
-- landed; INTERRUPTED, FAILED: cut), never by a secret; a cast whose times are secret runs full, no head. The spell's
-- icon in its ring is never scaled: it moves and fades with the bar (the user: "make sure that the icon borders stay
-- sharp in all animations"). Off (Cast Motion): the bar fades in and out, as before

function CastFX.On()
	return Db().castMotion ~= false
end

-- the pieces (Build, once): the old fill a pushback leaves (under the bar), the head's light, the flash over the fill,
-- the light off its end, a frame for the end's drive
function CastFX.Make(ui)
	local cast = ui.cast
	local fill = cast.strip.fill
	local level = cast.bar:GetFrameLevel()
	local ghost = CreateFrame("StatusBar", nil, fill)
	ghost:SetAllPoints(fill)
	ghost:SetFrameLevel(level)
	ghost:SetStatusBarTexture(W.BarFill("castbars"))
	W.SoftEnds(ghost)
	ghost:SetMinMaxValues(0, 1)
	ghost:SetAlpha(0)
	cast.bar:SetFrameLevel(level + 1)
	cast.ghost = ghost
	local head = CreateFrame("Frame", nil, cast.strip)
	head:SetFrameLevel(level + 2)
	head:SetPoint("CENTER", cast.bar:GetStatusBarTexture(), "RIGHT", 0, 0)
	head:SetSize(T.head, T.head)
	head:SetAlpha(0)
	head.glow = Spark(head, "OVERLAY", 5, "glow_white.tga")
	head.glow:SetAllPoints(head)
	head.core = Spark(head, "OVERLAY", 6, "glow_white.tga")
	head.core:SetSize(T.headCore, T.headCore)
	head.core:SetPoint("CENTER", head, "CENTER", 0, 0)
	cast.head = head
	cast.flash = Spark(cast.bar, "OVERLAY", -1, "glow_white.tga")
	cast.flash:SetTexture(W.BarFill("castbars"))
	cast.flash:SetAllPoints(fill)
	cast.flash:SetAlpha(0)
	local run = CreateFrame("Frame", nil, cast.strip)
	run:SetFrameLevel(level + 2)
	run:SetSize(1, 1)
	run:SetAlpha(0)
	run.streak = Spark(run, "OVERLAY", 5, "glow_white.tga")
	run.streak:SetSize(T.landStreak, cast.h / 2)
	run.streak:SetPoint("RIGHT", run, "CENTER", 0, 0)
	run.tip = Spark(run, "OVERLAY", 6, "glow_white.tga")
	run.tip:SetSize(T.landTip, T.landTip)
	run.tip:SetPoint("CENTER", run, "CENTER", 0, 0)
	cast.run = run
	cast.fx = CreateFrame("Frame", nil, cast.strip)
	CastFX.Paint(ui)
end

-- (Motion.Paint, the bus's 'palette') their colours: the head and the flash the text's warm white, the light off the
-- end the gold, the old fill the ghosts' colour
function CastFX.Paint(ui)
	local cast = ui and ui.cast
	if not (cast and cast.head) then
		return
	end
	local r, g, b = Motion.Look("text")
	cast.head.glow:SetVertexColor(r, g, b)
	cast.head.core:SetVertexColor(1, 1, 1)
	cast.flash:SetVertexColor(r, g, b)
	cast.run.streak:SetVertexColor(Motion.Look("selectedTrim"))
	cast.run.tip:SetVertexColor(r, g, b)
	cast.ghost:SetStatusBarColor(r, g, b, T.ghostAlpha)
end

-- the bar where LayStack hangs it, moved by dx, dy (the jolt, the drop, the fold's middle)
function CastFX.Place(cast, dx, dy)
	if cast.anchorTo then
		cast.strip:SetPoint("TOP", cast.anchorTo, "BOTTOM", dx, cast.anchorY + dy)
	end
end

-- everything a moment moved put back: its place, depth and width, its colours, every light out
function CastFX.Reset(cast)
	Anim:Stop(cast.strip, "drive")
	Anim:Stop(cast.fx, "drive")
	Anim:Stop(cast.ghost, "drive")
	CastFX.Place(cast, 0, 0)
	if cast.strip.plain then
		cast.strip:SetHeight(cast.h + 2)
	end
	cast.strip:SetWidth(Width() + cast.arms)
	Paint(cast.bar, "personalCast")
	local g = S.ui.gild
	if g then
		Gilded.Tint(g.cast, nil)
	end
	cast.name:SetAlpha(1)
	cast.time:SetAlpha(1)
	cast.flash:SetAlpha(0)
	cast.run:SetAlpha(0)
	cast.ghost:SetAlpha(0)
	CastFX.Head(cast, false)
end

-- the head's light: on while a timed cast runs (its colour the warm white, or a pushback's red)
function CastFX.Head(cast, on, key)
	local head = cast.head
	if not head then
		return
	end
	head:SetAlpha(on and CastFX.On() and 0.85 or 0)
	local c = key and MelloUI.Meaning[key]
	if c then
		head.glow:SetVertexColor(c[1], c[2], c[3])
	else
		head.glow:SetVertexColor(Motion.Look("text"))
	end
end

-- the cast's share shown now (its time read plain), nil when unknown
function CastFX.Share(now)
	local total = Num(S.castTotal)
	if not (total and total > 0 and S.castStart) then
		return nil
	end
	local p = math.min(1, math.max(0, (now - S.castStart) / total))
	return S.castChannel and 1 - p or p
end

-- opening: the bar from T.unfoldFrom wide out to its width, its texts in
function CastFX.UnfoldStep(strip, p)
	local cast = S.ui.cast
	local w = Width() + cast.arms
	strip:SetWidth(T.unfoldFrom + (w - T.unfoldFrom) * p)
	cast.name:SetAlpha(p)
	cast.time:SetAlpha(p)
end

local function Seg(t, a, d)
	return math.min(1, math.max(0, (t - a) / d))
end

local function OutCubic(p)
	return 1 - (1 - p) ^ 3
end

-- landed: the flash, the light off the end, the fold to its middle as it fades
function CastFX.LandStep(_, p)
	local cast = S.ui.cast
	local t = p * (T.foldAt + T.fold)
	cast.flash:SetAlpha(1 - Seg(t, 0, T.flash))
	local q = Seg(t, 0, T.land)
	cast.run:SetPoint("CENTER", cast.strip.fill, "RIGHT", 2 + T.landRun * OutCubic(q), 0)
	cast.run:SetAlpha(0.9 * (1 - q))
	local u = OutCubic(Seg(t, T.foldAt, T.fold))
	if cast.strip.plain then
		-- (the fill folded to its middle line; the painted bracket only fades)
		local h = cast.h + (T.foldTo - cast.h) * u
		cast.strip:SetHeight(h + 2)
		CastFX.Place(cast, 0, -(cast.h - h) / 2)
	end
	cast.strip:SetAlpha(1 - u)
end

-- cut: the jolt, then the drop as it fades
function CastFX.CutStep(_, p)
	local cast = S.ui.cast
	local t = p * (T.dropAt + T.drop)
	local s = Seg(t, 0, T.jolt)
	local dx = s < 1 and math.sin(s * math.pi * 4) * T.joltX * (1 - s) or 0
	local d = Seg(t, T.dropAt, T.drop)
	CastFX.Place(cast, dx, -T.dropY * d)
	cast.strip:SetAlpha(1 - d)
end

-- pushed back: the old fill held, then faded; the head red a moment
function CastFX.PushStep(ghost, p)
	local t = p * (T.pushHold + T.pushFade)
	ghost:SetAlpha(1 - Seg(t, T.pushHold, T.pushFade))
	if t >= T.pushHold then
		CastFX.Head(S.ui.cast, S.casting, nil)
	end
end

-- an end played out: the bar away, put back for the next
function CastFX.Gone()
	local cast = S.ui and S.ui.cast
	if cast and not S.casting then
		cast.strip:Hide()
		cast.strip:SetAlpha(0)
		CastFX.Reset(cast)
	end
end

function CastFX.PushDone(ghost)
	ghost:SetAlpha(0)
end

-- a cast read again later than it was (a pushback, a channel cut short): the fill it had, held and faded
function CastFX.Push(old)
	local cast = S.ui.cast
	if not (CastFX.On() and old and cast.ghost) then
		return
	end
	cast.ghost:SetValue(old)
	cast.ghost:SetAlpha(1)
	CastFX.Head(cast, true, "combatTaken")
	Anim:Drive(cast.ghost, CastFX.PushStep, T.pushHold + T.pushFade, "linear", CastFX.PushDone)
end

-- its end played: landed, cut (the game's word for why), or the plain fade
function CastFX.Play(cast, kind, text)
	Anim:Stop(cast.strip, "drive")
	Anim:Stop(cast.strip, "alpha")
	cast.strip:SetAlpha(1)
	cast.strip:SetWidth(Width() + cast.arms)
	if kind == "cut" then
		local share = CastFX.Share(GetTime())
		Anim:StopTimer(cast.bar, share or true)
		Paint(cast.bar, "combatTaken")
		local g = S.ui.gild
		if g then
			Gilded.Tint(g.cast, "combatTaken")
		end
		cast.name:SetAlpha(1)
		cast.name:SetText(Db().text == false and "" or text)
		cast.time:SetShown(false)
		Anim:Drive(cast.fx, CastFX.CutStep, T.dropAt + T.drop, "linear", CastFX.Gone)
	else
		Anim:StopTimer(cast.bar, not S.castChannel)
		Anim:Drive(cast.fx, CastFX.LandStep, T.foldAt + T.fold, "linear", CastFX.Gone)
	end
end

-- how a cast ended, from its event: landed (its SUCCEEDED just heard; a channel run out), cut (interrupted, failed: the
-- game's word for it), else plain
function CastFX.Kind(event, a4)
	if event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
		local word = rawget(_G, event == "UNIT_SPELLCAST_FAILED" and "FAILED" or "INTERRUPTED")
		if Secret(word) or type(word) ~= "string" or word == "" then
			word = event == "UNIT_SPELLCAST_FAILED" and TEXT.castFailed or TEXT.interrupted
		end
		return "cut", word
	elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		-- (its fourth: who interrupted it, nil when it ran out -- this client's own cast bar reads it so)
		if Secret(a4) or a4 ~= nil then
			return "cut", rawget(_G, "INTERRUPTED") or TEXT.interrupted
		end
		return "land"
	elseif S.castLanded and GetTime() - S.castLanded < T.castLate then
		return "land"
	end
	return "plain"
end

local function CastIn(fresh)
	local cast = S.ui.cast
	local strip = cast.strip
	if fresh and cast.fx then
		CastFX.Reset(cast)
	end
	if not strip:IsShown() then
		strip:Show()
	end
	Anim:To(strip, "alpha", 1, T.castFade, "outQuad")
	if fresh and CastFX.On() and cast.fx then
		cast.name:SetAlpha(0)
		cast.time:SetAlpha(0)
		Anim:Drive(strip, CastFX.UnfoldStep, T.unfold, "outCubic")
	end
	Motion.LayLine()
end

-- the cast's end: `kind` landed, cut (`text` its word) or plain (the fade). Told once: a cut heard just after a plain
-- end (the game's order may be either) still turns it
local function CastOut(kind, text)
	S.casting = false
	FadePoke()
	local cast = S.ui and S.ui.cast
	if not cast then
		return
	end
	Motion.LayLine()
	kind = kind or "plain"
	local now = GetTime()
	if S.castEnd and not (kind == "cut" and S.castEnd == "plain" and now - S.castEndAt < T.castLate) then
		return
	end
	S.castEnd, S.castEndAt = kind, now
	if not cast.fx then
		Anim:To(cast.strip, "alpha", 0, T.castFade, "inQuad", HideFrame)
		return
	end
	CastFX.Head(cast, false)
	if kind ~= "plain" and CastFX.On() and cast.strip:IsShown() then
		CastFX.Play(cast, kind, text)
	else
		Anim:To(cast.strip, "alpha", 0, T.castFade, "inQuad", CastFX.Gone)
	end
end

-- a cast (or a channel: its bar runs down) shown: the spell's name, its icon and the time left, counted by the engine
-- from when it began (`from`: a cast read again after a pushback stands where its time has it)
local function CastShow(name, seconds, channel, texture, from)
	local cast = S.ui.cast
	local fresh = not S.casting
	local old = not fresh and CastFX.Share(GetTime()) or nil
	cast.name:SetText(Db().text == false and "" or name)
	-- (the seconds the engine's: shown or not with the text)
	cast.time:SetShown(Db().text ~= false and cast.timed and true or false)
	if seconds then
		Anim:Timer(cast.bar, seconds, not channel, from)
	else
		Anim:StopTimer(cast.bar, true)   -- (its times unreadable: the bar full, no seconds)
	end
	S.castStart, S.castTotal, S.castChannel = from or GetTime(), seconds, channel or nil
	S.casting, S.castEnd, S.castLanded = true, nil, nil
	Gilded.Icon(texture)
	FadePoke()
	CastIn(fresh)
	if cast.head then
		CastFX.Head(cast, seconds ~= nil)
	end
	local now = CastFX.Share(GetTime())
	if old and now and now < old - 0.01 then
		CastFX.Push(old)
	end
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
	local ok, name, _, texture, startMS, endMS = pcall(info, "player")
	if not ok or not (Secret(name) or type(name) == "string") then
		CastOut()
		return
	end
	local seconds, from
	if Secret(startMS) or Secret(endMS) then
		S.reads.cast = TEXT.secret
	elseif type(endMS) == "number" and type(startMS) == "number" then
		S.reads.cast = TEXT.plain
		from, seconds = startMS / 1000, math.max(0.05, (endMS - startMS) / 1000)
	end
	CastShow(name, seconds, channel, texture, from)
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
	icon:SetKit(W.KitFor("unitframes"))   -- (0.25.0: MelloUI's ring unless Oldschool dresses the frames)
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
	Motion.Crack()
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
			-- (its aura heard just before -- the game sends the two in either order: its own, as a secret amount's are;
			-- else the column fell back to the one total, the user's Power Word: Shield blue one time, yellow the next)
			if S.absorbAt - S.auraAddedAt <= T.recent then
				Shield.Adopt()
			end
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
	-- (the float's lift: the hop, a heavy blow's dip, the settle's drop -- Motion)
	local k, hop = Zoom.Factor(), (S.hopY or 0) + (S.dipY or 0) + (S.settleY or 0)
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
	-- (Combat Settle: the display at its full place on the plate, no drop or dimming)
	Motion.SettleGo(MelloUI.InCombat(), true)
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
	if S.hopping or not (On() and S.ui) then
		return
	end
	local ok, falling = pcall(IsFalling)
	if ok and not Secret(falling) and falling then
		S.hopping = true
		Anim:Drive(S.ui.holder, HopStep, T.hopTime, "linear", HopDone)
	end
end

local function OnJump()
	-- (one look C13: the hop is MelloUI's choice -- Hop When You Jump gone; Reduce
	-- Motion keeps it still, Anim's)
	if On() then
		C_Timer.After(T.jumpCheck, HopCheck)
	end
end

--------------------------------------------------------------------------------
-- Motion (0.25.0; the user, 2026-10-18: "aproved" to the Personal Display Motion page,
-- https://claude.ai/artifact/9D9x4hxRGXxffC7afGhNdD, after the nameplates' Impact Effects): the bars answer the
-- fight, each effect its own switch (Behaviour), all on:
--   Damage Chunk, Power Spent  the part lost held lit, then drained: a ghost fill under the bar, set to the new value
--                              T.ghostDelay after the change and eased there by the engine
--   Heal Lead, Power Gained    the part gained lit at once: a lead fill between the ghost and the bar, which the bar
--                              (eased) grows into; a big plain gain of power a spark at its edge (energy's ticks none)
--   Heavy Hit                  a critical or crushing blow on you (UNIT_COMBAT, plain): the bars' rim red a moment,
--                              the bars dipped a hair
--   Dodge, Parry, Block        the word off the health bar's end (the Revenge window, where you look)
--   Low Health                 under T.lowHealth the health bar ember: the game's curves on its secret percent (one
--                              curve a colour channel -- numbers, no table made per event); its beat as it turns low
--                              only where the health reads plain (the preview)
--   Loss Of Control            stunned, feared, silenced, locked out: the bars' rim red and a line under them running
--                              its time down (the engine's timer on the game's own duration), its name under it; the
--                              game's banner over the character held off while it is on (its CVar, given back)
--   Combat Settle              into a fight the bars rise into place; out of it, a moment later, they settle a little
--                              lower, dimmed (the Fader's fades are its host's: they never meet)
-- A secret value is never compared: the three fills, layered (ghost, lead, the bar), show a loss or a gain by drawing
-- alone. The shield column's own light (applied, hit, low, broken: FrameFX's "shield") was there before. Reduce
-- Motion: the dip, the word's way and the settle's drop go; Anim's fades end at once. One driver (its OnUpdate only
-- while something is due); every piece made once, in Build
--------------------------------------------------------------------------------

Motion.CVAR = "lossOfControl"   -- the game's banner (LossOfControlFrame's switch)
Motion.NONE = 0                 -- (LossOfControlData.displayType: shown by nothing)
Motion.ACTIVE = (Constants and Constants.LossOfControlConsts
	and Constants.LossOfControlConsts.LOSS_OF_CONTROL_ACTIVE_INDEX) or 1
-- [UNIT_COMBAT's action] = its word's global string (the game's own text)
Motion.AVOID = { DODGE = "DODGE", PARRY = "PARRY", BLOCK = "BLOCK" }

function Motion.On(key)
	return Db()[key] ~= false
end

-- a palette colour as the Look shows it (the reskin's own by the same keys)
function Motion.Look(key)
	local look = MelloUI.Look
	local p = look and look.Palette and look.Palette() or MelloUI.Palette
	local c = p and p[key]
	if type(c) == "table" then
		return c[1] or 1, c[2] or 1, c[3] or 1
	end
	return 1, 1, 1
end

-- a fill's colour lifted toward white: the lead's (the part gained, lit)
function Motion.Pale(r, g, b)
	local k = T.pale
	return r + (1 - r) * k, g + (1 - g) * k, b + (1 - b) * k
end

-- the pieces (Build, once): each bar's rim under it, the loss of control's line, two words, the power's spark, the
-- driver
function Motion.Make(ui)
	local float = ui.float
	local level = float:GetFrameLevel()
	local Shade = MelloUI.Shade
	ui.motionBars = { ui.health, ui.power }
	for _, b in ipairs(ui.motionBars) do
		-- (under the fill: a glow round the bar, never on it -- the nameplates' lesson, seen in the simulator)
		local rim = CreateFrame("Frame", nil, float)
		rim:SetFrameLevel(level)
		rim:SetAllPoints(b.strip.fill)
		rim:SetAlpha(0)
		-- (full strength under the bracket's art, soft past its painted edge: Lay anchors it)
		local band = Shade and Shade:Band(rim, { colour = "combatTaken", feather = T.rimFeather,
			featherY = T.rimFeatherY })
		if band then
			band:SetStrength(1)
		end
		b.rim, b.rimBand = rim, band
	end
	-- the loss of control's line: the engine counts it down (Anim:TimerFor / Anim:Timer)
	local line = CreateFrame("StatusBar", nil, float)
	line:SetFrameLevel(level + 4)
	line:SetStatusBarTexture(W.BarFill("personal"))
	W.SoftEnds(line)
	line:SetMinMaxValues(0, 1)
	line:SetValue(1)
	line:SetHeight(T.lineH)
	line:SetAlpha(0)
	line:Hide()
	line.name = line:CreateFontString(nil, "OVERLAY")
	StyleText(line.name, T.text - 1)
	line.name:SetPoint("TOP", line, "BOTTOM", 0, -1)
	ui.loc = line
	-- two words, in turn (over the bracket's art)
	ui.words, ui.nextWord = {}, 1
	for i = 1, 2 do
		local w = CreateFrame("Frame", nil, float)
		w:SetSize(1, 1)
		w:SetFrameLevel(level + 9)
		w.text = w:CreateFontString(nil, "OVERLAY")
		StyleText(w.text, T.text + 1)
		w.text:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT")
		w:Hide()
		ui.words[i] = w
	end
	-- the spark on the power lead's edge (over the bracket's art)
	local spark = CreateFrame("Frame", nil, ui.power.strip)
	spark:SetFrameLevel(level + 6)
	spark:SetPoint("CENTER", ui.power.lead:GetStatusBarTexture(), "RIGHT", 0, 0)
	spark:SetAlpha(0)
	Spark(spark, "OVERLAY", 6, "glow_white.tga"):SetAllPoints(spark)
	ui.spark = spark
	ui.motionFrame = CreateFrame("Frame", nil, float)
	S.settle = { 0, 0 }
	S.settleY, S.dipY = 0, 0
	Motion.MakeMoments(ui, level)
end

-- (1.2.0, the ten motions) a frame between two anchors of the fills: from `a`'s right edge to `b`'s (the part a heal
-- gave, a hit or a cost took) -- the engine's own anchors, no value read, so a secret one draws as a plain one
local function Between(parent, level, a, b)
	local f = CreateFrame("Frame", nil, parent)
	f:SetFrameLevel(level)
	f:SetPoint("TOPLEFT", a:GetStatusBarTexture(), "TOPRIGHT")
	f:SetPoint("BOTTOMRIGHT", b:GetStatusBarTexture(), "BOTTOMRIGHT")
	return f
end

-- a frame from `a`'s point to `b`'s, top to bottom (the halves and quarters the shards are cut by)
local function Span(parent, a, aPoint, b, bPoint)
	local f = CreateFrame("Frame", nil, parent)
	f:SetPoint("TOPLEFT", a, aPoint)
	f:SetPoint("BOTTOMRIGHT", b, bPoint)
	return f
end

-- an unseen StatusBar over the health fill (and a glint's room either side), holding 0 or 1 as the game's curve has
-- it, and a frame clipped to its fill: shown only while it holds 1 (the shield column's way: no Lua reads the value)
local function Presence(parent, fill)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetPoint("TOPLEFT", fill, "TOPLEFT", -T.glintW, T.rim)
	bar:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", T.glintW, -T.rim)
	bar:SetStatusBarTexture(W.BarFill("personal"))
	bar:GetStatusBarTexture():SetAlpha(0)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	local clip = CreateFrame("Frame", nil, parent)
	clip:SetClipsChildren(true)
	clip:SetPoint("TOPLEFT", bar:GetStatusBarTexture(), "TOPLEFT")
	clip:SetPoint("BOTTOMRIGHT", bar:GetStatusBarTexture(), "BOTTOMRIGHT")
	return bar, clip
end

-- a glint to sweep across a fill: a soft light a little wider than tall, on `parent` (a clip)
local function Glint(parent, level)
	local f = CreateFrame("Frame", nil, parent)
	f:SetFrameLevel(level)
	f:SetSize(T.glintW, 1)
	f:SetAlpha(0)
	f.tex = Spark(f, "OVERLAY", 6, "glow_white.tga")
	f.tex:SetAllPoints(f)
	return f
end

-- (1.2.0) the moments' pieces: the heal's rush and its light, the shards of a heavy blow (the part lost cut in four by
-- anchors), the block a big cost drops, the gold line a fight opens from, the glint back at full (behind two presence
-- clips: full now, not full before) and the sweep coming back to life; each its own driver frame
function Motion.MakeMoments(ui, level)
	local float = ui.float
	local hb, pb = ui.health, ui.power
	-- the rush: over the bar, under the rim; its light clipped to the part given
	local rush = Between(float, level + 5, hb.bar, hb.lead)
	rush:SetClipsChildren(true)
	rush:SetAlpha(0)
	rush.light = rush:CreateTexture(nil, "OVERLAY")
	rush.light:SetTexture(W.BarFill("personal"))
	rush.light:SetBlendMode("ADD")
	rush.light:SetAllPoints(rush)
	rush.tip = Spark(rush, "OVERLAY", 6, "glow_white.tga")
	rush.tip:SetSize(T.rushGlow, T.rushGlow)
	rush.tip:SetPoint("CENTER", rush, "RIGHT", 0, 0)
	ui.rush = rush
	-- the shards: the part lost (the lead at the new value, the ghost held at the old), halves, quarters
	local lost = Between(float, level + 5, hb.lead, hb.ghost)
	local halves = { Span(lost, lost, "TOPLEFT", lost, "BOTTOM"), Span(lost, lost, "TOP", lost, "BOTTOMRIGHT") }
	ui.shards = {}
	for _, half in ipairs(halves) do
		for _, q in ipairs({ Span(half, half, "TOPLEFT", half, "BOTTOM"), Span(half, half, "TOP", half, "BOTTOMRIGHT") }) do
			local s = CreateFrame("Frame", nil, float)
			s:SetFrameLevel(level + 7)
			s.quarter = q
			s.tex = s:CreateTexture(nil, "OVERLAY")
			s.tex:SetTexture(W.BarFill("personal"))
			s.tex:SetAllPoints(s)
			s:SetAlpha(0)
			ui.shards[#ui.shards + 1] = s
		end
	end
	ui.shardFrame = CreateFrame("Frame", nil, float)
	-- the block a big cost drops: the part spent (the power's lead at the new value, its ghost at the old)
	local spent = Between(float, level + 5, pb.lead, pb.ghost)
	local drop = CreateFrame("Frame", nil, float)
	drop:SetFrameLevel(level + 7)
	drop.from = spent
	drop.tex = drop:CreateTexture(nil, "OVERLAY")
	drop.tex:SetTexture(W.BarFill("personal"))
	drop.tex:SetAllPoints(drop)
	drop:SetAlpha(0)
	ui.drop = drop
	-- the gold line a fight opens from, at the joint
	local line = CreateFrame("Frame", nil, float)
	line:SetFrameLevel(level + 7)
	line:SetPoint("CENTER", hb.strip.fill, "BOTTOM", 0, -T.joint / 2)
	line:SetSize(1, 2)
	line:SetAlpha(0)
	line.core = line:CreateTexture(nil, "OVERLAY")
	line.core:SetTexture(W.BarFill("personal"))
	line.core:SetAllPoints(line)
	line.glow = Spark(line, "OVERLAY", -1, "glow_white.tga")
	line.glow:SetPoint("TOPLEFT", line, "TOPLEFT", -4, 4)
	line.glow:SetPoint("BOTTOMRIGHT", line, "BOTTOMRIGHT", 4, -4)
	ui.openLine = line
	-- the glint back at full: inside "full now", inside "not full before"
	local nowBar, nowClip = Presence(float, hb.strip.fill)
	local beforeBar, beforeClip = Presence(nowClip, hb.strip.fill)
	nowClip:SetFrameLevel(level + 5)
	beforeClip:SetFrameLevel(level + 5)
	ui.fullNow, ui.fullBefore = nowBar, beforeBar
	ui.glint = Glint(beforeClip, level + 5)
	-- the sweep back to life, inside the health fill
	local lifeClip = CreateFrame("Frame", nil, float)
	lifeClip:SetClipsChildren(true)
	lifeClip:SetAllPoints(hb.strip.fill)
	lifeClip:SetFrameLevel(level + 5)
	ui.lifeGlint = Glint(lifeClip, level + 5)
	ui.formFrame = CreateFrame("Frame", nil, float)
	ui.deathFrame = CreateFrame("Frame", nil, float)
	S.restK, S.deathK, S.openK = 0, 0, 1
end

-- (1.2.0, the shield crack) the column's shards, made with the column (Build, once)
function Motion.MakeCrack(ui)
	local col = ui.column
	local crack = CreateFrame("Frame", nil, col.float)
	crack:SetFrameLevel(col.bar:GetFrameLevel() + 6)
	crack:SetAllPoints(col.strip.fill)
	crack:SetAlpha(0)
	crack.pieces = {}
	for i = 1, T.crackN do
		local p = crack:CreateTexture(nil, "OVERLAY")
		p:SetTexture(W.BarFill("personal"))
		p:SetSize(5, 7)
		crack.pieces[i] = p
	end
	col.crack = crack
end

-- (LayStack) each rim out to its bracket's painted edge, the line, the spark the power fill's depth
function Motion.Lay(ui)
	if not ui.loc then
		return
	end
	for _, b in ipairs(ui.motionBars) do
		local above, below = Dress.Reach(b)
		if b.rimBand then
			b.rimBand:Anchor(b.strip.fill, math.max(0, Dress.Side(b) / 2 - T.rimTuck),
				math.max(0, math.max(above, below) - T.rimTuck))
		end
	end
	Motion.LayLine()
	ui.spark:SetSize(T.sparkW, (ui.power.h or T.lineH) * T.sparkH)
end

-- the line under the lowest bar shown, as wide as its fill: the power bar, or the cast bar while you cast (a root
-- leaves the cast running; seen in the simulator, the line over the cast bar)
function Motion.LayLine()
	local ui = S.ui
	local line = ui and ui.loc
	if not line then
		return
	end
	local b = S.casting and ui.cast or ui.power
	local _, below = Dress.Reach(b)
	local fill = b.strip.fill
	local y = -(below + T.gap + 1)
	line:ClearAllPoints()
	line:SetPoint("TOPLEFT", fill, "BOTTOMLEFT", 0, y)
	line:SetPoint("TOPRIGHT", fill, "BOTTOMRIGHT", 0, y)
end

-- the ghosts the text's colour (as the nameplates' Impact Effects show the part lost), the health's lead its own
-- colour lifted (the power's: Power, by its kind), the line the selected trim's; again on the bus's 'palette'
function Motion.Paint()
	local ui = S.ui
	if not (ui and ui.loc) then
		return
	end
	local r, g, b = Motion.Look("text")
	for _, bar in ipairs(ui.motionBars) do
		bar.ghost:SetStatusBarColor(r, g, b, T.ghostAlpha)
	end
	ui.health.lead:SetStatusBarColor(Motion.Pale(HealthRGB()))
	ui.loc:SetStatusBarColor(Motion.Look("selectedTrim"))
	ui.loc.name:SetTextColor(r, g, b)
	CastFX.Paint(ui)
	-- (1.2.0) the moments: the rush the health's lead lifted, the shards and the dropped block the ghosts' colour, the
	-- line and the glints gold and warm white
	if ui.rush then
		ui.rush.light:SetVertexColor(Motion.Pale(HealthRGB()))
		ui.rush.tip:SetVertexColor(r, g, b)
		ui.drop.tex:SetVertexColor(r, g, b, T.ghostAlpha)
		ui.openLine.core:SetVertexColor(Motion.Look("selectedTrim"))
		ui.openLine.glow:SetVertexColor(Motion.Look("selectedTrim"))
		ui.glint.tex:SetVertexColor(r, g, b)
		ui.lifeGlint.tex:SetVertexColor(Motion.Look("selectedTrim"))
	end
	local col = ui.column
	if col and col.crack then
		local c = MelloUI.Meaning.personalShield
		for _, p in ipairs(col.crack.pieces) do
			p:SetVertexColor(Motion.Pale(c[1], c[2], c[3]))
		end
	end
end

-- each fill shown by its switch
function Motion.Shown()
	local ui = S.ui
	if not (ui and ui.loc) then
		return
	end
	ui.health.ghost:SetShown(Motion.On("chunk"))
	ui.health.lead:SetShown(Motion.On("lead"))
	ui.power.ghost:SetShown(Motion.On("spend"))
	ui.power.lead:SetShown(Motion.On("gain"))
end

-- a bar's new value, plain or secret (it goes to the fills as it is): the lead at once, the ghost T.ghostDelay after
-- the first change (the driver), eased there; at once with `snap` or S.snap (read again, another power)
function Motion.Value(b, max, v, snap)
	local lead, ghost = b.lead, b.ghost
	if not lead then
		return
	end
	lead:SetMinMaxValues(0, max)
	lead:SetValue(v)
	ghost:SetMinMaxValues(0, max)
	b.ghostV = v
	if snap or S.snap then
		b.ghostAt = nil
		ghost:SetValue(v)
	elseif not b.ghostAt then
		b.ghostAt = GetTime() + T.ghostDelay
		Motion.Wake()
	end
end

-- the driver: awake only while a drain, the settle's wait or a loss of control's end is due
function Motion.Wake()
	local f = S.ui and S.ui.motionFrame
	if f and not S.motionAwake then
		S.motionAwake = true
		Perf.SetScript(f, "OnUpdate", Motion.Tick)
	end
end

function Motion.Tick(f)
	local now, busy = GetTime(), false
	for _, b in ipairs(S.ui.motionBars) do
		local at = b.ghostAt
		if at and now >= at then
			b.ghostAt = nil
			b.ghost:SetValue(b.ghostV, EASE)
		elseif at then
			busy = true
		end
	end
	if S.settleAt and now >= S.settleAt then
		S.settleAt = nil
		Motion.SettleGo(MelloUI.InCombat())
	elseif S.settleAt then
		busy = true
	end
	if S.locDue and now >= S.locDue then
		Motion.LocEnd()
	elseif S.locDue then
		busy = true
	end
	if not busy then
		S.motionAwake = false
		Perf.SetScript(f, "OnUpdate", nil)
	end
end

-- a rim lit at once, faded over `time` to its rest (lit while control is lost)
function Motion.Rim(b, time)
	local rim = b.rim
	Anim:Stop(rim, "alpha")
	rim:SetAlpha(1)
	Anim:To(rim, "alpha", S.locOn and T.locRim or 0, time, "outQuad")
end

-- (Heavy Hit) the rims red a moment, the bars dipped a hair (and Damage Chunk's shards)
function Motion.Heavy()
	Motion.Shards()   -- (1.2.0: the part lost in shards, Damage Chunk's)
	local ui = S.ui
	if not (ui and ui.loc and Motion.On("heavy")) then
		return
	end
	for _, b in ipairs(ui.motionBars) do
		Motion.Rim(b, T.heavyRim)
	end
	if not Anim.reduceMotion then
		Anim:Drive(ui.motionFrame, Motion.DipStep, T.dip, "linear", Motion.DipDone)
	end
end

-- down a hair and back, the deepest at 30% of the way
function Motion.DipStep(_, p)
	local d = p < 0.3 and p / 0.3 or (1 - p) / 0.7
	S.dipY = -T.dipDepth * d
	Place()
end

function Motion.DipDone()
	S.dipY = 0
	Place()
end

-- (Dodge, Parry, Block) the word off the health bar's end, up and out, faded
function Motion.Word(action)
	local ui = S.ui
	if not (ui and ui.loc and Motion.On("avoid")) then
		return
	end
	local w = ui.words[ui.nextWord]
	ui.nextWord = ui.nextWord % #ui.words + 1
	local text = rawget(_G, Motion.AVOID[action] or "")
	if Secret(text) or type(text) ~= "string" or text == "" then
		text = TEXT.words[action] or action
	end
	w.text:SetText(text)
	w.text:SetTextColor(Motion.Look("text"))
	local fill = ui.health.strip.fill
	Anim:Stop(w, "alpha")
	w:ClearAllPoints()
	w:SetPoint("BOTTOMLEFT", fill, "TOPRIGHT", T.wordX, T.wordY)
	w:SetAlpha(1)
	w:Show()
	Anim:Slide(w, "BOTTOMLEFT", fill, "TOPRIGHT", T.wordX, T.wordY, T.wordDX, T.wordDY, T.word, "outCubic")
	Anim:To(w, "alpha", 0, T.word, "inQuad", HideFrame)
end

-- (UNIT_COMBAT on you: the action and its flag, plain strings) a heavy blow, a dodge, parry or block
function Motion.Combat(action, flag)
	if S.preview or Secret(action) or Secret(flag) then
		return
	end
	if action == "HEAL" then
		S.healAt = GetTime()   -- (the next health change a heal's: its rush)
	elseif action == "WOUND" then
		if flag == "CRITICAL" or flag == "CRUSHING" then
			Motion.Heavy()
		elseif flag == "BLOCK" then
			Motion.Word("BLOCK")
		end
	elseif Motion.AVOID[action] then
		Motion.Word(action)
	end
end

-- (Low Health) three curves, one a colour channel: the health colour from T.lowHealth up, ember under it; made once
-- (false: this client has none; nil again when Class Colours turns)
function Motion.Curves()
	if S.lowCurves ~= nil then
		return S.lowCurves or nil
	end
	S.lowCurves = false
	local CU = rawget(_G, "C_CurveUtil")
	if not (CU and CU.CreateCurve and rawget(_G, "UnitHealthPercent")) then
		return nil
	end
	local hi, lo = { HealthRGB() }, MelloUI.Meaning.personalLow
	local list = {}
	for i = 1, 3 do
		local ok, c = pcall(CU.CreateCurve)
		if not (ok and c and pcall(c.AddPoint, c, 0, lo[i]) and pcall(c.AddPoint, c, T.lowHealth - T.lowEdge, lo[i])
			and pcall(c.AddPoint, c, T.lowHealth, hi[i]) and pcall(c.AddPoint, c, 1, hi[i])) then
			return nil
		end
		list[i] = c
	end
	S.lowCurves = list
	return list
end

-- the health bar's colour: a plain share (the preview, a client handing it plain) told here, the beat as it turns
-- low; else the game's curves on the secret percent, straight into the bar's colour
function Motion.Low(pct)
	local ui = S.ui
	if not (ui and ui.loc and Motion.On("lowHealth")) then
		return
	end
	local bar = ui.health.bar
	if pct then
		local low = pct < T.lowHealth
		if low then
			Paint(bar, "personalLow")
		else
			PaintHealth(bar)
		end
		if low and S.lowWas == false then
			Motion.Rim(ui.health, T.beat)
		end
		S.lowWas = low
		return
	end
	local curves = Motion.Curves()
	if not curves then
		PaintHealth(bar)
		return
	end
	local Percent100 = rawget(_G, "UnitHealthPercent")
	local okR, r = pcall(Percent100, "player", true, curves[1])
	local okG, g = pcall(Percent100, "player", true, curves[2])
	local okB, b = pcall(Percent100, "player", true, curves[3])
	if not (okR and okG and okB and pcall(bar.SetStatusBarColor, bar, r, g, b)) then
		PaintHealth(bar)
	end
end

-- (Power Gained) a big plain gain: a spark at the lead's edge; energy's steady ticks (a fifth of the bar) none
function Motion.Gain(max, v, token)
	local last = S.powerLast
	S.powerLast = v
	local ui = S.ui
	if S.snap or not (ui and ui.spark and max and v and last) or max <= 0 then
		return
	end
	if (last - v) / max >= T.spendShare then
		Motion.Drop()   -- (1.2.0: a big cost's block dropped off)
		return
	end
	if token ~= "ENERGY" and Motion.On("gain") and (v - last) / max >= T.sparkShare then
		Anim:Stop(ui.spark, "alpha")
		ui.spark:SetAlpha(1)
		Anim:To(ui.spark, "alpha", 0, T.spark, "outQuad")
	end
end

-- (Loss Of Control) the game's active one, shown by something (nil: none)
function Motion.LocData()
	local L = rawget(_G, "C_LossOfControl")
	if not (L and L.GetActiveLossOfControlData) then
		return nil
	end
	local ok, data = pcall(L.GetActiveLossOfControlData, Motion.ACTIVE)
	if ok and not Secret(data) and type(data) == "table" and not Secret(data.displayType)
		and data.displayType ~= Motion.NONE then
		return data
	end
	return nil
end

-- LOSS_OF_CONTROL_ADDED / _UPDATE: one taken on (a new one: its time from now), or the last one over
function Motion.Loc(added)
	if S.preview or not Motion.On("stun") then
		return
	end
	local data = Motion.LocData()
	if not data then
		Motion.LocEnd()
	elseif added or not S.locOn then
		Motion.LocStart(data)
	end
end

-- its time on the line: the engine's timer on the game's own duration
function Motion.LocTimer(line)
	local L = rawget(_G, "C_LossOfControl")
	if not (L and L.GetActiveLossOfControlDuration) then
		return false
	end
	local ok, d = pcall(L.GetActiveLossOfControlDuration, "player", Motion.ACTIVE)
	return ok and Anim:TimerFor(line, d) or false
end

-- the rims red, the line in, run down: the game's duration (the engine reads it), else its seconds read plain, else
-- held full until it ends; its name under it (plain or secret: the font string takes it). The preview: its seconds
-- and its name
function Motion.LocStart(data, seconds, name)
	local ui = S.ui
	if not (ui and ui.loc) then
		return
	end
	local line = ui.loc
	S.locOn, S.locDue = true, nil
	Motion.LayLine()
	local s = seconds or (data and Num(data.timeRemaining))
	local timed = data ~= nil and Motion.LocTimer(line)
	if not timed and s and s > 0 then
		timed = Anim:Timer(line, s)
	end
	if not timed then
		Anim:StopTimer(line, true)
	end
	if s and s > 0 then
		S.locDue = GetTime() + s + T.locGrace
		Motion.Wake()
	end
	local text
	if Db().text == false then
		text = ""
	elseif name then
		text = name
	elseif data then
		text = data.displayText
	else
		text = TEXT.stunned
	end
	pcall(line.name.SetText, line.name, text)
	line:Show()
	Anim:Stop(line, "alpha")
	Anim:To(line, "alpha", 1, T.locFade, "outQuad")
	for _, b in ipairs(ui.motionBars) do
		Anim:Stop(b.rim, "alpha")
		Anim:To(b.rim, "alpha", T.locRim, T.locFade, "outQuad")
	end
end

function Motion.LocHidden(line)
	line:Hide()
	Anim:StopTimer(line, true)
end

-- over: the rims and the line out
function Motion.LocEnd()
	local ui = S.ui
	if not (S.locOn and ui and ui.loc) then
		return
	end
	S.locOn, S.locDue = false, nil
	Anim:To(ui.loc, "alpha", 0, T.locFade, "inQuad", Motion.LocHidden)
	for _, b in ipairs(ui.motionBars) do
		Anim:To(b.rim, "alpha", 0, T.locFade, "inQuad")
	end
end

-- the game's banner held off while Loss Of Control is on (its CVar, the player's own value given back); out of combat
function Motion.HoldNow()
	MelloUI:HoldCVar(M.db, Motion.CVAR, "savedLoc", M.isEnabled and Motion.On("stun"), "0")
end

function Motion.HoldBanner()
	if not (M.db and MelloUI.HoldCVar) then
		return
	end
	if MelloUI.InCombat() and MelloUI.Kit and MelloUI.Kit.WhenOutOfCombat then
		MelloUI.Kit:WhenOutOfCombat(Motion.HoldNow, "Personal Display: the game's loss of control banner")
	else
		Motion.HoldNow()
	end
end

-- (Combat Settle) where the bars rest: in place in a fight, while Edit Layout places them, with it off or with Reduce
-- Motion; else a little lower. Never dimmed (the user, 2026-10-19: the bars "are transparent" out of a fight): fading
-- out of combat is the Fader's (its "personal" host, the Fader's page)
function Motion.Rest(fight)
	if fight or S.editing or not Motion.On("settle") or Anim.reduceMotion then
		return 0
	end
	return -T.restDrop
end

function Motion.SettleStep(_, p)
	local m = S.settle
	S.settleY = m[1] + (m[2] - m[1]) * p
	Place()
end

-- from where they are to their rest: eased (into a fight quick, out of it slow), or at once (`now`)
function Motion.SettleGo(fight, now)
	local ui = S.ui
	if not (ui and ui.loc) then
		return
	end
	local y = Motion.Rest(fight)
	Motion.Form(fight, now)   -- (1.2.0: opened from the gold line, slim at rest)
	local m = S.settle
	m[1], m[2] = S.settleY, y
	if now then
		Anim:Stop(ui.float, "drive")
		Motion.SettleStep(nil, 1)
		return
	end
	Anim:Drive(ui.float, Motion.SettleStep, fight and T.settleIn or T.settleOut, fight and "outQuad" or "inOutQuad")
end

-- a fight begun (at once) or over (a moment later: the driver)
function Motion.Settle(fight)
	S.settleAt = nil
	if fight then
		Motion.SettleGo(true)
	else
		S.settleAt = GetTime() + T.settleDelay
		Motion.Wake()
	end
end

--------------------------------------------------------------------------------
-- The moments (1.2.0; the user's "All of them" to prd_motion2, seen in look A of prd_looks): a heal's rush over the
-- part it gave and the light at its end; a heavy blow's part lost broken in shards that fall; the glint along the bar
-- back at full; a big cost's block dropped off; a fight opening from a gold line, the bars slim at rest out of it; at
-- death grey and folded, back to life unfolded with a sweep; the shield's crack. Each plays once at its moment (no
-- pulse), from the events and the engine's anchors -- never a secret compared. Their switches the effects' own: Heal
-- Lead, Heavy Hit, Power Spent, Combat Settle; the crack with the column
--------------------------------------------------------------------------------

local function Lerp(a, b, p)
	return a + (b - a) * p
end

-- (Heal Lead) the rush: the part given lit and fading, the light at its end after it (both clipped to the part: none
-- with nothing given, a heal at full)
function Motion.RushStep(rush, p)
	local t = p * T.rush * 2
	rush.light:SetAlpha(0.9 * (1 - Seg(t, 0, T.rush)))
	rush.tip:SetAlpha(0.9 * Seg(t, 0.25, 0.07) * (1 - Seg(t, 0.32, T.rushEnd)))
end

function Motion.RushDone(rush)
	rush:SetAlpha(0)
end

function Motion.Rush()
	local ui = S.ui
	if not (ui and ui.rush and Motion.On("lead")) or Anim.reduceMotion then
		return
	end
	ui.rush:SetAlpha(1)
	Anim:Drive(ui.rush, Motion.RushStep, T.rush * 2, "linear", Motion.RushDone)
end

-- the health's two presences: "full now" (the share now at T.full or more), "not full before" (under it): a plain share
-- told, else the game's curves on the secret percent
function Motion.FullCurves()
	if S.fullCurves ~= nil then
		return S.fullCurves or nil
	end
	S.fullCurves = false
	local CU = rawget(_G, "C_CurveUtil")
	if not (CU and CU.CreateCurve and rawget(_G, "UnitHealthPercent")) then
		return nil
	end
	local list = {}
	for i, low in ipairs({ 0, 1 }) do
		local ok, c = pcall(CU.CreateCurve)
		if not (ok and c and pcall(c.AddPoint, c, 0, low) and pcall(c.AddPoint, c, T.full - 0.001, low)
			and pcall(c.AddPoint, c, T.full, 1 - low) and pcall(c.AddPoint, c, 1, 1 - low)) then
			return nil
		end
		list[i] = c
	end
	S.fullCurves = list
	return list
end

function Motion.FullSet(bar, share, before)
	if share then
		local full = share >= T.full
		bar:SetValue((full ~= before) and 1 or 0)
		return
	end
	local curves = Motion.FullCurves()
	local fn = rawget(_G, "UnitHealthPercent")
	local ok, v = false, nil
	if curves and fn then
		ok, v = pcall(fn, "player", true, curves[before and 2 or 1])
	end
	if not (ok and pcall(bar.SetValue, bar, v)) then
		bar:SetValue(0)   -- (unreadable: no glint)
	end
end

-- the glint along the health bar, seen only back at full (the presences: full now, not full before)
function Motion.GlintStep(g, p)
	local w = Width()
	g:ClearAllPoints()
	g:SetPoint("CENTER", S.ui.health.strip.fill, "LEFT", -T.glintW / 2 + (w + T.glintW) * p, 0)
	g:SetHeight(S.ui.health.h + 2)
	g:SetAlpha(1)
end

function Motion.GlintDone(g)
	g:SetAlpha(0)
	S.glinting = false
	local ui = S.ui
	if ui and ui.fullBefore then
		Motion.FullSet(ui.fullBefore, S.healthShare, true)
	end
end

-- a health change: the presences read, a heal's rush and glint played (`healed`: a heal just heard)
function Motion.HealthMoment(share, healed)
	local ui = S.ui
	if not (ui and ui.fullNow) then
		return
	end
	S.healthShare = share
	Motion.FullSet(ui.fullNow, share, false)
	if healed and not S.snap then
		Motion.Rush()
		if Motion.On("lead") and not Anim.reduceMotion and not S.glinting then
			S.glinting = true
			Anim:Drive(ui.glint, Motion.GlintStep, T.glint, "inOutQuad", Motion.GlintDone)
		end
	end
	if not S.glinting then
		Motion.FullSet(ui.fullBefore, share, true)
	end
end

-- (Heavy Hit) the part lost in four shards, falling apart (the ghost held unseen meanwhile, drained after them)
function Motion.ShardStep(_, p)
	local ui = S.ui
	local q = p
	local r, g, b = Motion.Look("text")
	local red = MelloUI.Meaning.combatTaken
	local k = 0.35 * q
	for i, s in ipairs(ui.shards) do
		local x = (i - 2.5) * T.shardSpread * q
		local y = -((14 + (i % 2) * 8) * q + T.shardFall * q * q)
		s:ClearAllPoints()
		s:SetPoint("TOPLEFT", s.quarter, "TOPLEFT", x + 0.6, y)
		s:SetPoint("BOTTOMRIGHT", s.quarter, "BOTTOMRIGHT", x - 0.6, y)
		s.tex:SetRotation((i % 2 == 1 and 1 or -1) * (0.6 + i * 0.3) * q * 3)
		s.tex:SetVertexColor(Lerp(r, red[1], k), Lerp(g, red[2], k), Lerp(b, red[3], k))
		s:SetAlpha(1 - q)
	end
end

function Motion.ShardDone()
	local ui = S.ui
	for _, s in ipairs(ui.shards) do
		s:SetAlpha(0)
	end
	ui.health.ghost:SetAlpha(1)
end

function Motion.Shards()
	local ui = S.ui
	if not (ui and ui.shards) or Anim.reduceMotion or not Motion.On("chunk") then
		return
	end
	local b = ui.health
	b.ghost:SetAlpha(0)
	b.ghostAt = GetTime() + T.shards
	Motion.Wake()
	Anim:Drive(ui.shardFrame, Motion.ShardStep, T.shards, "linear", Motion.ShardDone)
end

-- (Power Spent) a big cost's block dropped off (the ghost held unseen meanwhile, drained after it)
function Motion.DropStep(drop, p)
	local dy = -T.spendDrop * OutCubic(p)
	drop:ClearAllPoints()
	drop:SetPoint("TOPLEFT", drop.from, "TOPLEFT", 2 * p, dy)
	drop:SetPoint("BOTTOMRIGHT", drop.from, "BOTTOMRIGHT", 2 * p, dy)
	drop:SetAlpha(1 - p)
end

function Motion.DropDone(drop)
	drop:SetAlpha(0)
	S.ui.power.ghost:SetAlpha(1)
end

function Motion.Drop()
	local ui = S.ui
	if not (ui and ui.drop and Motion.On("spend")) or Anim.reduceMotion then
		return
	end
	local b = ui.power
	b.ghost:SetAlpha(0)
	b.ghostAt = GetTime() + T.spendTime
	Motion.Wake()
	Anim:Drive(ui.drop, Motion.DropStep, T.spendTime, "linear", Motion.DropDone)
end

-- (Combat Settle) the bars' form: slim at rest (S.restK 1), folded at death (S.deathK 1), opened to S.openK of their
-- width; laid on the plain strips (a painted bracket keeps its depth), again after every LayStack
function Motion.FormApply()
	local ui = S.ui
	if not (ui and ui.formFrame) then
		return
	end
	local rest, dead = S.restK or 0, S.deathK or 0
	local w = Width()
	for i, b in ipairs({ ui.health, ui.power }) do
		local strip = b.strip
		if strip.plain then
			local h = Lerp(b.h, i == 1 and T.restHealth or T.restPower, rest)
			h = Lerp(h, i == 1 and T.deathTo or 0.5, dead)
			strip:SetHeight(h + 2)
			strip:SetWidth(Lerp(T.unfoldFrom, w, S.openK or 1) + b.arms)
		end
		if b.text then
			b.text:SetAlpha(1 - math.max(rest, dead))
		end
	end
end

-- into a fight: the gold line grown from the middle, held, faded; the bars opening from it and filling out to their
-- depth. Out of one: slim at rest
function Motion.OpenStep(_, p)
	local ui = S.ui
	local t = p * (T.openLine + T.openHold + T.openFade)
	local line = ui.openLine
	line:SetWidth(math.max(1, Width() * OutCubic(Seg(t, 0, T.openLine))))
	line:SetAlpha(1 - Seg(t, T.openLine + T.openHold, T.openFade))
	S.openK = Lerp(T.openFrom, 1, OutCubic(Seg(t, 0.12, T.open)))
	S.restK = S.restFrom * (1 - OutCubic(Seg(t, 0.18, T.open)))
	Motion.FormApply()
end

function Motion.RestStep(_, p)
	S.restK = Lerp(S.restFrom, 1, p)
	Motion.FormApply()
end

function Motion.FormDone()
	S.ui.openLine:SetAlpha(0)
	S.openK = 1
	Motion.FormApply()
end

-- the form for a fight begun or over (Motion.SettleGo's): at rest only where the bars settle (Motion.Rest)
function Motion.Form(fight, now)
	local ui = S.ui
	if not (ui and ui.formFrame) then
		return
	end
	local rest = Motion.Rest(fight) ~= 0
	S.restFrom = S.restK or 0
	if now or Anim.reduceMotion or S.deathK > 0 then
		Anim:Stop(ui.formFrame, "drive")
		S.restK, S.openK = rest and 1 or 0, 1
		ui.openLine:SetAlpha(0)
		Motion.FormApply()
	elseif rest then
		Anim:Drive(ui.formFrame, Motion.RestStep, T.settleOut, "inOutQuad", Motion.FormDone)
	elseif S.restFrom > 0 then
		-- (from rest into a fight: the line and the opening; a fight begun at full form only fills out)
		S.openK = T.openFrom
		Anim:Drive(ui.formFrame, Motion.OpenStep, T.openLine + T.openHold + T.openFade, "linear", Motion.FormDone)
	end
end

-- death: the fills greyed, the bars folded, their percents out; back: unfolded, the colours back, the sweep
function Motion.DeathStep(_, p)
	local ui = S.ui
	local t = p * (T.deathAt + T.deathFold)
	local grey = Seg(t, T.deathDrain / 2, T.deathGrey)
	for _, b in ipairs({ ui.health, ui.power }) do
		b.bar:GetStatusBarTexture():SetDesaturated(grey > 0.5)
		b.bar:SetAlpha(1 - 0.2 * grey)
	end
	S.deathK = OutCubic(Seg(t, T.deathAt, T.deathFold))
	Motion.FormApply()
end

function Motion.BackStep(_, p)
	local ui = S.ui
	local t = p * (T.back + T.backFill)
	S.deathK = 1 - OutCubic(Seg(t, 0, T.back))
	Motion.FormApply()
	local g = ui.lifeGlint
	local q = Seg(t, T.back * 0.8, T.backFill)
	g:ClearAllPoints()
	g:SetPoint("CENTER", ui.health.strip.fill, "LEFT", Width() * q, 0)
	g:SetHeight(ui.health.h + 2)
	g:SetAlpha(q > 0 and q < 1 and 1 or 0)
end

function Motion.BackDone()
	S.deathK = 0
	S.ui.lifeGlint:SetAlpha(0)
	Motion.FormApply()
end

function Motion.Death(dead)
	local ui = S.ui
	if not (ui and ui.deathFrame) or S.preview or (dead and S.dead) or (not dead and not S.dead) then
		return
	end
	S.dead = dead
	for _, b in ipairs({ ui.health, ui.power }) do
		b.bar:GetStatusBarTexture():SetDesaturated(false)
		b.bar:SetAlpha(1)
	end
	if not Motion.On("settle") then
		S.deathK = 0
		Motion.FormApply()
		return
	end
	if dead then
		Anim:Drive(ui.deathFrame, Motion.DeathStep, T.deathAt + T.deathFold, "linear")
	else
		Anim:Drive(ui.deathFrame, Motion.BackStep, T.back + T.backFill, "linear", Motion.BackDone)
	end
end

-- dead or a ghost now (plain on this client; a secret: alive)
function Motion.IsDead()
	local ok, dead = pcall(UnitIsDeadOrGhost, "player")
	return ok and not Secret(dead) and dead and true or false
end

-- (the shield crack) the column broken: its shards flung out either side and falling
function Motion.CrackStep(crack, p)
	local fill = S.ui.column.strip.fill
	local q = OutCubic(p)
	for i, piece in ipairs(crack.pieces) do
		local side = i % 2 == 1 and -1 or 1
		local x = side * (4 + T.crackOut * q) * (0.6 + i * 0.12)
		local y = -T.colH * (0.55 + i * 0.07) - 18 * p * p
		piece:ClearAllPoints()
		piece:SetPoint("CENTER", fill, "TOP", x, y)
		piece:SetRotation(side * p * (1.5 + i * 0.4))
	end
	crack:SetAlpha(1 - p)
end

function Motion.Crack()
	local col = S.ui and S.ui.column
	if not (col and col.crack) or Anim.reduceMotion or Db().shield == false then
		return
	end
	col.crack:SetAlpha(1)
	Anim:Drive(col.crack, Motion.CrackStep, T.crack, "linear")
end

-- off: nothing of it left lit or moved; the game's banner given back
function Motion.Off()
	local ui = S.ui
	if not (ui and ui.loc) then
		return
	end
	S.settleAt, S.locDue, S.locOn, S.motionAwake = nil, nil, false, false
	Perf.SetScript(ui.motionFrame, "OnUpdate", nil)
	for _, b in ipairs(ui.motionBars) do
		b.ghostAt = nil
		Anim:Stop(b.rim, "alpha")
		b.rim:SetAlpha(0)
	end
	Anim:Stop(ui.loc, "alpha")
	Motion.LocHidden(ui.loc)
	ui.loc:SetAlpha(0)
	for _, w in ipairs(ui.words) do
		Anim:Stop(w, "alpha")
		Anim:Stop(w, "slide")
		w:Hide()
	end
	Anim:Stop(ui.spark, "alpha")
	ui.spark:SetAlpha(0)
	Anim:Stop(ui.motionFrame, "drive")
	Anim:Stop(ui.float, "drive")
	S.dipY, S.settleY = 0, 0
	-- (1.2.0) the moments
	for _, f in ipairs({ ui.rush, ui.glint, ui.lifeGlint, ui.drop, ui.shardFrame, ui.formFrame, ui.deathFrame }) do
		Anim:Stop(f, "drive")
	end
	ui.rush:SetAlpha(0)
	ui.glint:SetAlpha(0)
	ui.lifeGlint:SetAlpha(0)
	ui.drop:SetAlpha(0)
	ui.openLine:SetAlpha(0)
	for _, s in ipairs(ui.shards) do
		s:SetAlpha(0)
	end
	for _, b in ipairs(ui.motionBars) do
		b.ghost:SetAlpha(1)
		b.bar:GetStatusBarTexture():SetDesaturated(false)
		b.bar:SetAlpha(1)
	end
	S.glinting, S.dead = false, false
	S.restK, S.deathK, S.openK = 0, 0, 1
	Motion.FormApply()
	if ui.column and ui.column.crack then
		Anim:Stop(ui.column.crack, "drive")
		ui.column.crack:SetAlpha(0)
	end
	Motion.HoldBanner()
end

--------------------------------------------------------------------------------
-- The swing badge (1.2.0; the user, 2026-10-21: the swing on the rails "reimagined ... a visual indicator/feedback
-- without it cluttering the screen with bars"; docs/plans/swing-badge.md): MelloUI.SwingBadge (Core/SwingBadge.lua),
-- since animations round 3 (the user 2026-10-22, "yes to all") the one for everyone -- this display its host while the
-- Swing Badge is on, ahead of the Swing Timers: with no plate for your target the badge stands at the display's left
-- end, hung on the health bar (T.badgeHere); the display's preview plays its swings, the game's left out meanwhile;
-- its word in the display's Text Font
--------------------------------------------------------------------------------

-- a cooldown sweep's call, where this client has it (each set once, at the sweep's making: Big Cooldowns')
local function Try(frame, method, ...)
	local fn = frame[method]
	if type(fn) == "function" then
		pcall(fn, frame, ...)
	end
end

SwingOn = function()
	return On() and Db().swing ~= false
end

local Host = { key = "personal" }

-- the two at the display's left end, the off hand's left of the main one (the strike toward the display)
function Host.Here(big, small)
	local ui = S.ui
	if not ui then
		return
	end
	local fill = ui.health.strip.fill
	local k = T.badgeHere / SB.T.badge
	local level = ui.float:GetFrameLevel() + 12
	SB.Attach(big, ui.float, level, k)
	SB.Attach(small, ui.float, level, k)
	big:ClearAllPoints()
	big:SetPoint("RIGHT", fill, "BOTTOMLEFT", -(Dress.Side(ui.health) / 2 + T.badgeGap) / k, -(T.gap / 2) / k)
	small:ClearAllPoints()
	small:SetPoint("RIGHT", big, "LEFT", -3, 0)
end

function Host.Quiet()
	return S.preview == true
end

function Host.Style(fs, size)
	StyleText(fs, size)
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
	"UNIT_COMBAT", "LOSS_OF_CONTROL_ADDED", "LOSS_OF_CONTROL_UPDATE",   -- (Motion)
}
local CAST_START = { UNIT_SPELLCAST_START = false, UNIT_SPELLCAST_DELAYED = false, UNIT_SPELLCAST_CHANNEL_START = true,
	UNIT_SPELLCAST_CHANNEL_UPDATE = true }
local CAST_END = { UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_FAILED = true, UNIT_SPELLCAST_INTERRUPTED = true,
	UNIT_SPELLCAST_CHANNEL_STOP = true }

local function OnEvent(_, event, a1, a2, a3, a4)
	if not S.ui then
		return
	end
	if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
		Health()
	elseif event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
		Power()
	elseif event == "UNIT_COMBAT" then
		-- (a blow on you: Motion's; one on your target is the swing badge's own)
		Motion.Combat(a2, a3)
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
		-- (Cast Motion: the cast in hand landed -- its STOP comes after this)
		if S.casting and not S.castChannel then
			S.castLanded = GetTime()
		end
	elseif CAST_START[event] ~= nil then
		CastRead(CAST_START[event])
	elseif CAST_END[event] then
		-- (a failed or interrupted attempt -- another spell pressed mid-cast -- while a cast still runs: that cast
		-- stays, as the game's own cast bar keeps it by its castID)
		local attempt = event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED"
		if not S.preview and not (attempt and StillCasting()) then
			CastOut(CastFX.Kind(event, a4))
		end
	elseif event == "LOSS_OF_CONTROL_ADDED" or event == "LOSS_OF_CONTROL_UPDATE" then
		Motion.Loc(event == "LOSS_OF_CONTROL_ADDED")
	elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
		if not S.preview then
			Motion.Settle(event == "PLAYER_REGEN_DISABLED")
		end
	elseif event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
		Motion.Death(Motion.IsDead())   -- (1.2.0: grey and folded, back with the sweep)
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
	-- (the swing badge's host while the Swing Badge is on: its own events, Core/SwingBadge.lua)
	if on and SwingOn() then
		SB:Use(Host)
	else
		SB:Drop(Host)
	end
	if not on then
		return
	end
	for _, event in ipairs(UNIT_EVENTS) do
		pcall(f.RegisterUnitEvent, f, event, "player")
	end
	f:RegisterEvent("PLAYER_ENTERING_WORLD")
	f:RegisterEvent("PLAYER_REGEN_DISABLED")
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	for _, event in ipairs({ "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
		f:RegisterEvent(event)
	end
end

-- everything read again (the login, a setting, the preview's end)
Refresh = function()
	local ui = S.ui
	if not ui then
		return
	end
	-- (read again: the fills set at once, no loss or gain shown)
	S.snap = true
	Health()
	Power()
	S.snap = false
	Motion.Paint()
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
-- Nothing per frame in Lua; nothing made at login (each icon the first time one is needed, then kept).
-- (1.2.0, the user's pick of 2026-10-22: BuildData/output/animation_previews/more_anims.html, "yes to all") Its motion:
-- an icon pops in with a ring of light, the row glides as icons come and go, its last T.cdEmber seconds in ember (the
-- ring and the seconds: personalLow), a flash and a shrink as it ends (its time, or its aura gone). Each icon is its
-- cooldown's from start to end (e.icon), not the row's n-th; Lua each frame only while one moves (Anim:Drive), the
-- moves from the times they began (Cds.Place); Reduce Motion: in place at once
--------------------------------------------------------------------------------
local CDS, CD_LASTS = ns and ns.Cooldowns or {}, ns and ns.CooldownLasts or {}
local CD_PRIO = { I = 1, F = 2, L = 3, B = 4, E = 5, O = 6 }

local function CdsOn()
	return On() and Db().cooldowns ~= false
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
		if e.spell == spell and not e.leaving then
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
	entry.ember = false
	if entry.icon then
		Cds.Ember(entry.icon, false)
	end
	C_Timer.After(entry.ends - now + 0.05, Cds.Expire)
	if dur > T.cdEmber then
		C_Timer.After(dur - T.cdEmber, Cds.EmberDue)
	end
	Cds.Refresh()
end

-- one at its end (its time, or its aura gone): its flash and shrink, then away (Reduce Motion: away at once)
function Cds.End(e)
	local ic = e.icon
	if ic and not Anim.reduceMotion then
		e.leaving = true
		ic.endAt = GetTime()
		Cds.Move(ic)
		C_Timer.After(T.cdEnd + 0.02, Cds.Gone)
		return
	end
	Cds.Release(e)
	for i = #S.cds, 1, -1 do
		if S.cds[i] == e then
			table.remove(S.cds, i)
		end
	end
end

-- (C_Timer.After) the ones whose end has played taken off
function Cds.Gone()
	local now = GetTime()
	for i = #S.cds, 1, -1 do
		local e = S.cds[i]
		if e.leaving and (not e.icon or now + 0.01 >= (e.icon.endAt or 0) + T.cdEnd) then
			Cds.Release(e)
			table.remove(S.cds, i)
		end
	end
end

-- the ones whose time is over: their end
function Cds.Expire()
	local now, changed = GetTime(), false
	for i = #S.cds, 1, -1 do
		local e = S.cds[i]
		if not e.leaving and e.ends <= now + 0.01 then
			Cds.End(e)
			changed = true
		end
	end
	if changed then
		Cds.Refresh()
	end
end

-- (C_Timer.After) the ones in their last T.cdEmber seconds: ember
function Cds.EmberDue()
	local now = GetTime()
	for _, e in ipairs(S.cds) do
		if e.icon and not e.ember and not e.leaving and now + 0.01 >= e.ends - T.cdEmber then
			e.ember = true
			Cds.Ember(e.icon, true)
		end
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
					local e = S.cds[i]
					if e and e.aura == r and not e.leaving then
						Cds.End(e)
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

-- an icon (made the first time one is needed, kept, used again): the spell's icon in the round rim, the game's sweep
-- over it, its seconds on top, its light (the ring's pop and the end's flash)
function Cds.Make()
	local ic = W.RoundIcon(S.ui.float, T.cdIcon, nil)
	ic:EnableMouse(false)   -- (the pointer passes through the display to the world)
	ic:SetKit(W.KitFor("unitframes"))   -- (0.25.0: MelloUI's ring unless Oldschool dresses the frames)
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
	ic.flare = Spark(top, "OVERLAY", 7, "glow_white.tga", SB.GOLD)
	ic.flare:SetPoint("CENTER", ic, "CENTER", 0, 0)
	ic.flare:SetSize(T.cdIcon * 2.2, T.cdIcon * 2.2)
	ic.flare:SetAlpha(0)
	S.cdIcons[#S.cdIcons + 1] = ic
	return ic
end

-- a free icon, else a new one
function Cds.Take()
	local spare = S.cdSpare
	local ic = spare[#spare]
	if ic then
		spare[#spare] = nil
		return ic
	end
	return Cds.Make()
end

-- an entry's icon put away and freed
function Cds.Release(e)
	local ic = e.icon
	if not ic then
		return
	end
	e.icon = nil
	Anim:Stop(ic, "drive")
	Anim:StopTimer(ic.timer)
	ic.popAt, ic.glideAt, ic.endAt = nil, nil, nil
	Cds.Ember(ic, false)
	ic:SetAlpha(1)
	ic.flare:SetAlpha(0)
	ic:Hide()
	S.cdSpare[#S.cdSpare + 1] = ic
end

-- an icon in ember (its last seconds) or back to its own look
function Cds.Ember(ic, on)
	local c = on and MelloUI.Meaning.personalLow or nil
	local rim = ic.plainRim
	if c then
		rim:SetVertexColor(c[1], c[2], c[3])
		ic.secs:SetTextColor(c[1], c[2], c[3])
	else
		rim:SetVertexColor(1, 1, 1)
		StyleText(ic.secs, T.text - 1)
	end
end

-- an icon where its moves have it now (from the times they began): the pop's scale and ring of light, the glide's
-- place, the end's flash, shrink and fade. Its offsets in its own units (it is scaled: Big Cooldown Size times the
-- pop), its seconds kept at the display's text size
local function OutBack(t)
	local y = t - 1
	return 1 + 2.9 * y * y * y + 1.9 * y * y
end

function Cds.Place(ic)
	local now = GetTime()
	local sc, x, flare, alpha = 1, ic.toX, 0, 1
	if ic.popAt then
		local t = (now - ic.popAt) / T.cdPop
		if t < 1 then
			sc = math.max(0.05, OutBack(t))
			flare = 0.7 * (1 - t)
		else
			ic.popAt = nil
		end
	end
	if ic.glideAt then
		local t = (now - ic.glideAt) / T.cdGlide
		if t < 1 then
			x = ic.fromX + (ic.toX - ic.fromX) * Anim.easing.outCubic(t)
		else
			ic.glideAt = nil
		end
	end
	if ic.endAt then
		local t = math.min(1, (now - ic.endAt) / T.cdEnd)
		sc, alpha, flare = 1 - 0.4 * t, 1 - t, 0.85 * (1 - t)
		ic.flare:SetVertexColor(1, 1, 1)
	else
		ic.flare:SetVertexColor(SB.GOLD[1], SB.GOLD[2], SB.GOLD[3])
	end
	ic.x = x
	local k = ic.k
	ic:SetScale(k * sc)
	W.RoundIconRefit(ic)   -- (its ring sharp at every step of the pop and the end)
	ic.top:SetScale(1 / k)
	ic:SetAlpha(alpha)
	ic:ClearAllPoints()
	ic:SetPoint("BOTTOM", S.ui.health.strip.fill, "TOP", x / sc, ic.above / (k * sc) + T.cdLift / sc)
	ic.flare:SetAlpha(flare)
end

local function CdStep(ic)
	Cds.Place(ic)
end

-- an icon's moves run (Lua each frame until the last of them ends), or laid in place
function Cds.Move(ic)
	local now, last = GetTime(), 0
	if ic.popAt then
		last = math.max(last, ic.popAt + T.cdPop - now)
	end
	if ic.glideAt then
		last = math.max(last, ic.glideAt + T.cdGlide - now)
	end
	if ic.endAt then
		last = math.max(last, ic.endAt + T.cdEnd - now)
	end
	if last > 0 then
		Anim:Drive(ic, CdStep, last + 0.02, "linear")
	else
		Cds.Place(ic)
	end
end

-- the row above the health bar, centred: every one up, the most important first, each its own icon -- a new one pops
-- in at its place, the others glide to theirs; one leaving stays where it is for its end. (Big Cooldown Size, the
-- user's video of 2026-10-12: "i need a slider to resize the Big Cooldown icons above my HP bar") Each icon scaled
-- from its made size, its rim, sweep and the gap with it; its seconds kept at the display's text size (over a larger
-- icon they fit inside it, not over the next one's), the row's place over the bar unchanged
function Cds.Icons()
	local ui, list = S.ui, S.cdOrder
	local n = math.min(#list, T.cdMax)
	local above = Dress.Reach(ui.health)
	local k = math.max(12, math.min(40, Num(Db().cdSize) or T.cdIcon)) / T.cdIcon
	local motion = not Anim.reduceMotion
	local now = GetTime()
	for i = 1, #list do
		local e = list[i]
		if i > n then
			Cds.Release(e)
		else
			local ic = e.icon
			local x = (i - (n + 1) / 2) * (T.cdIcon + T.cdGap)
			if not ic then
				ic = Cds.Take()
				e.icon = ic
				ic:SetIcon(SpellIcon(e.spell))
				Cds.Ember(ic, e.ember == true)
				ic.toX, ic.x, ic.glideAt, ic.endAt = x, x, nil, nil
				ic.popAt = motion and now or nil
				ic:SetAlpha(1)
				ic:Show()
			elseif x ~= ic.toX then
				if motion then
					ic.fromX, ic.toX, ic.glideAt = ic.x or x, x, now
				else
					ic.toX = x
				end
			end
			ic.k, ic.above = k, above
			if e.dur > 0 then
				Try(ic.sweep, "SetCooldown", e.start, e.dur)
				ic.sweep:Show()
				Anim:Timer(ic.timer, e.ends - now, false)
				ic.secs:SetShown(ic.timed and Db().text ~= false and true or false)
			else
				ic.sweep:Hide()
				Anim:StopTimer(ic.timer)
				ic.secs:Hide()
			end
			Cds.Move(ic)
		end
	end
	-- (the size changed: the ones leaving keep their place at the new size)
	for _, e in ipairs(S.cds) do
		if e.leaving and e.icon then
			e.icon.k, e.icon.above = k, above
		end
	end
end

-- the row again (the ones leaving out of it)
function Cds.Refresh()
	if not S.ui then
		return
	end
	wipe(S.cdOrder)
	for _, e in ipairs(S.cds) do
		if not e.leaving then
			S.cdOrder[#S.cdOrder + 1] = e
		end
	end
	table.sort(S.cdOrder, CdOrder)
	Cds.Icons()
end

-- all put away at once (off, the preview's end)
function Cds.Off()
	for _, e in ipairs(S.cds) do
		Cds.Release(e)
	end
	wipe(S.cds)
	Cds.Refresh()
end

-- (0.21.0, the user 2026-10-12: "the swing timer needs to hide if im using the new ones") the game's own swing timers
-- held off while the swing badge shows the swing (their CVar, the player's own value given back); MelloUI's Swing
-- Timers stand down by themselves (their RailsOn) and hold that CVar while they are on, so here only while they are off
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
			-- never written back, or the game's would show beside the badge)
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
	Motion.Shown()
	Motion.HoldBanner()
	Refresh()
	Motion.SettleGo(MelloUI.InCombat(), true)
	Place()
end

--------------------------------------------------------------------------------
-- Preview (Core/Preview.lua, part "personal"): a made-up shield and casts on the solo scene's beats, plain amounts
--------------------------------------------------------------------------------

local function SampleHealth(pct)
	local ui = S.ui
	local power = S.previewPower or 100
	ui.health.bar:SetMinMaxValues(0, 100)
	ui.health.bar:SetValue(pct, EASE)
	Motion.Value(ui.health, 100, pct)
	Motion.Low(pct / 100)
	Motion.HealthMoment(pct / 100, S.samplePct ~= nil and pct > S.samplePct)
	S.samplePct = pct
	ui.health.text:SetFormattedText("%.0f%%", pct)
	ui.power.bar:SetMinMaxValues(0, 100)
	ui.power.bar:SetValue(power, EASE)
	Motion.Value(ui.power, 100, power)
	Motion.Gain(100, power, nil)
	ui.power.text:SetFormattedText("%.0f%%", power)
end

-- (the preview's own cast ended: a real one begun after the preview's stop left running)
local function PreviewCastOut()
	if S.preview then
		CastOut("land")
	end
end

local function SampleCast(spec)
	if spec then
		CastShow(spec[1], spec[2], false, SpellIcon(spec[3]))
		C_Timer.After(spec[2], PreviewCastOut)
	end
end

local function OnPreview(beat, _, n)
	if beat == "stop" then
		if S.preview then
			S.preview = false
			ShieldOff()
			CastOut()
			SB.Off()
			Cds.Off()
			Motion.LocEnd()
			S.previewPower, S.powerLast, S.lowWas = nil, nil, nil
			Refresh()
			if MelloUI.InCombat() then
				Motion.Settle(true)
			end
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
		S.previewHealth, S.previewPower, S.powerLast, S.lowWas = SAMPLE.health, SAMPLE.power, nil, nil
		S.snap = true
		SampleHealth(S.previewHealth)
		S.snap = false
		Motion.SettleGo(false, true)
	elseif beat == "pull" then
		Motion.Settle(true)
		Cds.Start(SAMPLE.cooldowns.pull)
		if SwingOn() then
			SB.Start("main", SAMPLE.swing)
			SB.Start("off", SAMPLE.swing * 2)
		end
		S.previewParts = SAMPLE.parts
		Shield.Apply(SAMPLE.shield)
		SampleCast(SAMPLE.casts.pull)
	elseif beat == "hit" then
		local hurt = n == SAMPLE.crit and SAMPLE.critHurt or SAMPLE.hurt
		S.previewHealth = math.max(20, (S.previewHealth or SAMPLE.health) - hurt)
		S.previewPower = math.max(0, math.min(100, (S.previewPower or SAMPLE.power) + SAMPLE.gain - (SAMPLE.spend[n] or 0)))
		SampleHealth(S.previewHealth)
		if n == SAMPLE.crit then
			Motion.Heavy()
		end
		if SAMPLE.avoid[n] then
			Motion.Word(SAMPLE.avoid[n])
		end
		if n == SAMPLE.stun[1] and Motion.On("stun") then
			Motion.LocStart(nil, SAMPLE.stun[2], rawget(_G, "LOSS_OF_CONTROL_DISPLAY_STUN"))
		end
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
		if SwingOn() then
			if SAMPLE.outcomes[n] then
				SB.Outcome(SAMPLE.outcomes[n][1], SAMPLE.outcomes[n][2])
			end
			SB.Start("main", SAMPLE.swing)
			if n % 2 == 0 then
				SB.Start("off", SAMPLE.swing * 2)
			end
		end
	elseif beat == "kill" then
		if S.shieldOn then
			Shield.Break()
		end
		SampleHealth(SAMPLE.health)
		Motion.Settle(false)
	end
end

--------------------------------------------------------------------------------
-- The module
--------------------------------------------------------------------------------

M = MelloUI:RegisterModule("PersonalDisplay", {
	title = "Personal Display",
	desc = "Your health, power and cast bar under your character, as Legion's resource display had them, and a shield column beside your character: it fills when a shield goes up, drains as it takes the hits, turns amber when low and breaks when it is gone. The game's own Personal Resource Display is switched off while this is on, and comes back as you had it when it is off; Hide The Game's Cast Bar (on) hides the game's cast bar too, and Swing Badge (on) stands in for Swing Timers. This client cannot tell an addon where your character stands, so the display stays where you put it in Edit Layout (under your character to begin with) and hops when you jump.",
	icon = "Interface\\Icons\\Spell_Holy_PowerWordShield",
	flavour = "Health, power, casts and shields, right by your character.",
	role = "replaces",
	slash = "personal",
	enabledByDefault = false,
	installer = false,
	-- the player's own game setting, given back when off, and the camera zoom the display was placed at: never in a
	-- profile
	keep = { "savedGameDisplay", "zoomRef", "savedSwing", "savedLoc" },
	defaults = { width = 160, height = 10, shield = true, text = true, zoom = true, hideCastBar = true,
		healFrom = true, swing = true, cooldowns = true, cdSize = 16, textFont = "shared",
		chunk = true, lead = true, heavy = true, spend = true, gain = true, avoid = true, lowHealth = true,
		stun = true, settle = true, classColour = false, castMotion = true },
	options = {
		{ type = "toggle", key = "shield", name = "Shield Column",
		  desc = "An upright bar beside your character for every shield on you added up, as the game counts them: spells (Power Word: Shield, Ice Barrier, Mana Shield, the wards), talents and items, the ones against one kind of damage too. Each shield is its own part, in its school's colour (Power Word: Shield gold, Ice Barrier frost, Mana Shield arcane, a Fire Protection Potion fire), stacked in the order they went up, its icon beside the column. It fills when one goes up, drains as it takes the hits, turns amber when low and breaks when the last one is gone; one ending while another holds only takes its part away. Edit Layout places it." },
		{ type = "toggle", key = "hideCastBar", name = "Hide The Game's Cast Bar",
		  desc = "The game's own cast bar is hidden while this is on: your casts show on the display's cast bar under your character. Off: both show." },
		{ type = "toggle", key = "healFrom", name = "Heal Light From Your Character",
		  desc = "With Heal Effects on (Frame Effects > Heals): the light of a heal you cast gathers at your character's middle instead of on the cast bar, and flies from there to the party or raid frame of the one you heal. It follows the display's place and the camera's zoom." },
		{ type = "toggle", key = "swing", name = "Swing Badge",
		  desc = "Your swing timer as a small badge on your target's nameplate, right of its level: your weapon in a gold ring, its shade turning off as your next swing nears. It winds up, strikes into your target's health bar as the swing lands, turns gold on a critical blow and bounces off grey on a dodge, parry or miss. An off hand's smaller badge stands beside it. Your shots: the badge turns red for the aim (stand still: moving holds it) and fires into the plate; a wand gathers its bolt. With no plate for your target (nameplates off), the badge waits at the left end of the display. While it is on, MelloUI's Swing Timers step aside and the game's own swing timers stay off." },
		{ type = "toggle", key = "cooldowns", name = "Big Cooldowns",
		  desc = "The buffs you give yourself on a cooldown -- Shield Wall, Shield Block, Last Stand, Evasion, Ice Block, Recklessness, a trinket's -- as icons above the health bar, their time sweeping round them and their seconds on them, the most important first: an immunity, then damage taken down, more health, block, evasion, the rest. From the game's own spell data, for every class." },
		{ type = "toggle", key = "text", name = "Percent And Spell Text",
		  desc = "Your health and power in percent beside their bars, the spell and its seconds on the cast bar, the shield's amount under its column, and what took your control under the bars." },
		{ type = "dropdown", key = "textFont", name = "Text Font", values = MelloUI.FontFaces,
		  desc = "The face of the display's texts: the percents, the spell and its seconds, the shield's amount. Shared: the Interface text's face (Look > Fonts)." },
		{ type = "toggle", key = "classColour", name = "Class Colours",
		  desc = "The health bar in your class's colour instead of green. With Low Health on it still turns ember under 35%." },
		{ type = "slider", key = "width", name = "Width", min = 100, max = 260, step = 5,
		  desc = "How wide the health, power and cast bars are. Edit Layout sizes the whole display." },
		{ type = "slider", key = "height", name = "Height", min = 5, max = 16, step = 1,
		  desc = "How tall the health bar is; the power and cast bars are a little thinner, in step with it. Their frames grow and shrink with them." },
		{ type = "slider", key = "cdSize", name = "Big Cooldown Size", min = 12, max = 40, step = 1,
		  desc = "How big the Big Cooldowns' icons above the health bar are. Their seconds keep the display's text size." },
		{ type = "toggle", key = "zoom", name = "Follow Camera Zoom",
		  desc = "The display keeps its place by your character as you zoom the camera: closer under your feet when you zoom out, further down when you zoom in, so it never covers your character. Place it in Edit Layout at the zoom you play at; it follows from there. Turning the camera up or down is not followed (the game does not tell)." },
		{ type = "toggle", key = "castMotion", name = "Cast Motion", new = "1.2.0",
		  desc = "The cast bar opens from its middle with a light on its head; a cast that lands flashes and folds away, one that is interrupted turns red, jolts and drops, and a pushback shows where the bar was a moment." },
		{ type = "toggle", key = "chunk", name = "Damage Chunk",
		  desc = "What a hit takes from your health stays lit a moment, then drains away; a critical or crushing blow breaks it into shards that fall." },
		{ type = "toggle", key = "lead", name = "Heal Lead",
		  desc = "A heal lights the health it gives at once, a light at its end; the bar then grows into it. Back at full health, a glint runs along the bar." },
		{ type = "toggle", key = "heavy", name = "Heavy Hit",
		  desc = "A critical or crushing blow on you flashes the bars' rim red and dips them a hair, once." },
		{ type = "toggle", key = "spend", name = "Power Spent",
		  desc = "The rage, energy or mana an ability costs stays lit a moment, then drains, so you see the cost; a big cost drops off the bar as a block." },
		{ type = "toggle", key = "gain", name = "Power Gained",
		  desc = "New power lights ahead of the bar, which grows into it; a big gain sparks at its edge (energy's steady ticks do not)." },
		{ type = "toggle", key = "avoid", name = "Dodge, Parry, Block",
		  desc = "Your dodge, parry or block flicks its word off the health bar's end: your Revenge window, on the bars you watch." },
		{ type = "toggle", key = "lowHealth", name = "Low Health",
		  desc = "Under 35% health the health bar turns ember." },
		{ type = "toggle", key = "stun", name = "Loss Of Control",
		  desc = "While you are stunned, feared, silenced or locked out of a school, the bars' rim turns red and a line under them runs down its time, its name under it. The game's own banner over your character is off while this is on, and comes back as you had it when it is off." },
		{ type = "toggle", key = "settle", name = "Combat Settle",
		  desc = "Into a fight the bars open from a gold line and rise into place; a moment after it they settle a little lower and slimmer, their percents hidden, until the next one. At death they grey and fold; back to life they open again. (To fade them out of combat: the Fader.)" },
		{ type = "button", name = "Preview", text = "Play",
		  hint = "a shield going up, hit, low and broken, casts, and the bars in the fight",
		  desc = "Plays a made-up fight on the display: a shield going up, taking hits until it is low and breaks, a cast and a second shield, and the bars answering it -- the hits, a critical blow, power gained and spent, a dodge, a stun, low health and the heal after. Also /mello personal test.",
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
		for _, b in ipairs(ui.motionBars) do
			b.ghost:SetStatusBarTexture(fill)
			b.lead:SetStatusBarTexture(fill)
		end
		ui.loc:SetStatusBarTexture(fill)
	end
end

local function CastFill()
	if S.ui then
		S.ui.cast.bar:SetStatusBarTexture(W.BarFill("castbars"))
	end
end

-- Oldschool > Borders' Personal Resource Border changed (the kit's 'border' on the bus): every part in the new look
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
	MelloUI:On("palette", Motion.Paint, OWNER)
	if not S.watching then
		-- (once: their owners' own listeners on the bus; with nothing made they do nothing)
		S.watching = true
		W.OnBarTexture("personal", UnitFill, OWNER .. ": the bars' fill")
		W.OnBarTexture("castbars", CastFill, OWNER .. ": the cast bar's fill")
	end
	HoldGame()
	-- (0.21.3; the user's /reload, 2026-10-13: the bars two seconds after the
	-- rest -- they waited for the login's settling seconds) at login in the
	-- frame after it is switched on, as the party frames
	if MelloUI.LoggingIn and MelloUI:LoggingIn() then
		C_Timer.After(0, function()
			if M.isEnabled then
				Start()
			end
		end)
	else
		Start()
	end
end

function M:OnDisable()
	MelloUI:Off(OWNER)
	Events(false)
	Cds.Off()
	HoldGame()
	GameCast.Hold(false)
	ChargeFrom()
	HoldGameSwing()
	S.preview = false
	Motion.Off()
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
		Events(true)   -- (the swing badge's host or not)
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
	elseif key == "chunk" or key == "lead" or key == "spend" or key == "gain" then
		Motion.Shown()
		Refresh()
	elseif key == "lowHealth" or key == "classColour" then
		if key == "classColour" then
			S.lowCurves = nil
			Motion.Paint()
		end
		PaintHealth(ui.health.bar)
		S.lowWas = nil
		Refresh()
	elseif key == "stun" then
		if not Motion.On("stun") then
			Motion.LocEnd()
		end
		Motion.HoldBanner()
	elseif key == "settle" then
		Motion.SettleGo(MelloUI.InCombat(), true)
	elseif key == "textFont" then
		for fs, size in pairs(S.texts) do
			StyleText(fs, size)
		end
	end
end

-- the state (the Fader reads the cast from it), the timings, the swing badge's host and the big cooldowns (the tests)
M.S = S
M.T = T
M.Host = Host
M.Cds = Cds
M.Motion = Motion

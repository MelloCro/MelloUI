--------------------------------------------------------------------------------
-- MelloUI - Healer Frames (0.19.0; user, 2026-10-04: "the Unitframes, Party
-- Frames and Raid Frames are lacking the "Heal Prediction" feature ... there
-- is a Default Blizzard Option to Color specific unitframes when they recieve
-- a Curse, Magic Debuff etc"; docs/plans/heal-prediction-dispel.md, the
-- picked sketch: https://claude.ai/artifact/ChqU1tfsuEmhvAYCiVCUGb)
--
-- Two things a healer reads off the frames:
--   * Incoming Heals, on the frames whose Forever templates have no heal
--     prediction bars (Camelot's Player- and TargetFrameTemplates): the
--     player, the target, the focus and their targets. After the health
--     fill: my heals, others' heals, then shields, in the game's own colours
--     (CompactUnitFrame.lua's CUF_MY_HEAL_PREDICTION_COLOR and
--     CUF_OTHER_HEAL_PREDICTION_COLOR, its raidframe-shield-fill). The party,
--     pet and raid frames draw the game's own. Health and heals are secret:
--     the client's calculator (CreateUnitHealPredictionCalculator,
--     UnitGetDetailedHealPrediction) splits and clamps them to the missing
--     health, and three StatusBars are handed its amounts, the unit's
--     maximum health their maximum, each starting at the fill before it.
--     Nothing is read or compared.
--   * Debuff Glow: while a frame's unit (a friend) has a debuff that Debuff
--     Glow Shows keeps -- every dispellable one, one anyone in the group can
--     dispel, or one I can -- a soft glow in the debuff's colour round the
--     frame (B): round the portrait, and the rail family's soft outline round
--     the bars. On a raid frame (C) the outline round the frame and the
--     kit's rail itself in the colour (RaidFramePanel:RailSkin,
--     Kit:TintSkin). The colour is the client's (GetAuraDispelTypeColor
--     through a curve of the game's own debuff colours), handed on as it
--     is, secret or not.
-- Pieces are made after the login and out of combat only (frames under the
-- game's protected unit buttons): a frame first seen in a fight gets its
-- pieces when it ends. No OnUpdate: the units' events, the health bars'
-- own changes. /ufdump heals: what each frame shows.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("HealerFrames")
local hooksecurefunc = Perf.hooksecurefunc
local Shared = Perf.Shared
local Kit = MelloUI.Kit
local Secret = MelloUI.Safe.IsSecret
local Num = MelloUI.Safe.Number
local Text = MelloUI.Safe.Text

-- a value or a table the client hands out secret (an aura update's fields in a
-- restricted fight: its flag a secret boolean, its lists secret tables, user
-- 2026-10-04): never tested, counted or indexed
local function Hidden(v)
	if Secret(v) then
		return true
	end
	if type(issecrettable) ~= "function" then
		return false
	end
	local ok, s = pcall(issecrettable, v)
	return ok and not Secret(s) and s == true
end

local SHOWS = {
	{ value = "all", label = "Every Dispellable Debuff" },
	{ value = "group", label = "Ones The Group Can Dispel" },
	{ value = "mine", label = "Ones I Can Dispel" },
}
-- the aura filters (AuraUtil.AuraFilters): DISPELLABLE, whoever can remove it;
-- RAID_PLAYER_DISPELLABLE, someone in the group can; RAID, I can
local FILTER = { all = "HARMFUL|DISPELLABLE", group = "HARMFUL|RAID_PLAYER_DISPELLABLE", mine = "HARMFUL|RAID" }

local M = MelloUI:RegisterModule("HealerFrames", {
	title = "Healer Frames",
	desc = "Incoming heals on the unit frames, and a glow in a debuff's colour round any frame whose unit has a debuff to remove.",
	icon = "Interface\\Icons\\Spell_Holy_FlashHeal",
	flavour = "See the heals coming in, and who needs a cleanse.",
	role = "feature",
	-- (no group: its rows sit on the Unit Frames page; not on the installer's
	-- Features step, on by default)
	installer = false,
	enabledByDefault = true,
	defaults = { incomingHeals = true, debuffGlow = true, debuffGlowShows = "all" },
	options = {
		{ type = "toggle", key = "incomingHeals", name = "Incoming Heals", new = "0.19.0",
		  desc = "The heals on their way to a unit shown on its health bar: your heals, other healers' heals and shields. On the player, target and focus frames and their targets; the party, pet and raid frames show the game's own (the raid frames' Display Incoming Heals)." },
		{ type = "toggle", key = "debuffGlow", name = "Debuff Glow", new = "0.19.0",
		  desc = "A soft glow in the debuff's colour (Magic blue, Curse purple, Disease brown, Poison green) round a friend's frame while they have a debuff that can be removed. On the raid frames the border takes the colour too." },
		{ type = "dropdown", key = "debuffGlowShows", name = "Debuff Glow Shows", values = SHOWS, new = "0.19.0",
		  desc = "Which debuffs light a frame: every one that can be removed, the ones someone in your group can remove, or only the ones you can remove." },
	},
})

local active = false
local hooked = false
local WEAK = { __mode = "k" }

-- the frames' parts, read where the game keeps them (UnitFramePanel's map)
local function PlayerMain(f)
	local c = f.PlayerFrameContent
	return c and c.PlayerFrameContentMain
end
local function TargetMain(f)
	local c = f.TargetFrameContent
	return c and c.TargetFrameContentMain
end

-- The unit frames (fixed): their unit (the frame's own `unit` where the game
-- keeps one: the player frame's is the vehicle's while in one), portrait,
-- health and mana bars; `heals`: their template has no heal prediction bars
local UNIT_FRAMES = {
	{ key = "player", unit = "player", heals = true, frame = function() return PlayerFrame end,
	  portrait = function(f) local c = f.PlayerFrameContainer return c and c.PlayerPortrait end,
	  health = function(f) local m = PlayerMain(f) return m and m.HealthBarsContainer and m.HealthBarsContainer.HealthBar end,
	  mana = function(f) local m = PlayerMain(f) return m and m.ManaBarArea and m.ManaBarArea.ManaBar end },
	{ key = "target", unit = "target", heals = true, frame = function() return TargetFrame end,
	  portrait = function(f) local c = f.TargetFrameContainer return c and c.Portrait end,
	  health = function(f) local m = TargetMain(f) return m and m.HealthBarsContainer and m.HealthBarsContainer.HealthBar end,
	  mana = function(f) local m = TargetMain(f) return m and m.ManaBar end },
	{ key = "focus", unit = "focus", heals = true, frame = function() return FocusFrame end,
	  portrait = function(f) local c = f.TargetFrameContainer return c and c.Portrait end,
	  health = function(f) local m = TargetMain(f) return m and m.HealthBarsContainer and m.HealthBarsContainer.HealthBar end,
	  mana = function(f) local m = TargetMain(f) return m and m.ManaBar end },
	{ key = "targettarget", unit = "targettarget", heals = true, frame = function() return TargetFrame and TargetFrame.totFrame end,
	  portrait = function(f) return f.Portrait end, health = function(f) return f.HealthBar end, mana = function(f) return f.ManaBar end },
	{ key = "focustarget", unit = "focustarget", heals = true, frame = function() return FocusFrame and FocusFrame.totFrame end,
	  portrait = function(f) return f.Portrait end, health = function(f) return f.HealthBar end, mana = function(f) return f.ManaBar end },
	{ key = "pet", unit = "pet", frame = function() return PetFrame end,
	  portrait = function(f) return f.Portrait end, health = function() return _G.PetFrameHealthBar end, mana = function() return _G.PetFrameManaBar end },
}
-- a party member's frame (the pool's) and its pet's
local PARTY = {
	portrait = function(f) return f.Portrait end,
	health = function(f) return f.HealthBarContainer and f.HealthBarContainer.HealthBar end,
	mana = function(f) return f.ManaBar end,
}
local PARTY_PET = {
	portrait = function(f) return f.Portrait end,
	health = function(f) return f.HealthBar end,
}

-- a frame's unit now: the game's own `unit` field where it keeps one
local function UnitOf(f, fallback)
	local u = Text(rawget(f, "displayedUnit")) or Text(rawget(f, "unit"))
	return u or fallback
end

--------------------------------------------------------------------------------
-- Incoming heals
--------------------------------------------------------------------------------

local calc = nil   -- the client's calculator, made once (false: this client has none)
local function Calculator()
	if calc == nil then
		calc = false
		if type(CreateUnitHealPredictionCalculator) == "function" and type(UnitGetDetailedHealPrediction) == "function" then
			local ok, c = pcall(CreateUnitHealPredictionCalculator)
			if ok and (type(c) == "userdata" or type(c) == "table") then
				local E = Enum or {}
				local heal = E.UnitIncomingHealClampMode and E.UnitIncomingHealClampMode.MissingHealth or 0
				local absorb = E.UnitDamageAbsorbClampMode and E.UnitDamageAbsorbClampMode.MissingHealth or 0
				-- clamped to the missing health (shields after the heals): the
				-- segments never run past the bar's end
				pcall(c.SetIncomingHealClampMode, c, heal)
				pcall(c.SetIncomingHealOverflowPercent, c, 1)
				pcall(c.SetDamageAbsorbClampMode, c, absorb)
				calc = c
			end
		end
	end
	return calc or nil
end

local WHITE = "Interface\\Buttons\\WHITE8X8"
local SHIELD_ATLAS = "raidframe-shield-fill"
-- the stripes over a shield: the game's own tiled overlay (StatusBarOverlaySegment.xml's TiledFillOverlay), tiled by
-- the engine at its own size over whatever width the fill has (no size read)
local SHIELD_STRIPES = "Interface\\RaidFrame\\Shield-Overlay"
local healSets = {}   -- every set made: { health, unit (fn), mine, other, shield, fill }
local healOf = setmetatable({}, WEAK)   -- [health bar] = its set

local function Colour(c)
	if type(c) == "table" and c.GetRGBA then
		return c:GetRGBA()
	end
	return 1, 1, 1, 1
end

-- (user, 2026-10-04: "the heal prediction needs to stay on top of the unitframe
-- background, but still be covered with the borders") Each segment on the
-- health bar's OWN level, as the game's prediction bars are
-- (StatusBarOverlaySegmentTemplate: useParentLevel): there the regions of the
-- bar, its container and its segments go by their draw layers, so the fills
-- lie just over the health fill (Layers, below) and under the kit's bracket
-- (Kit:BracketLayers: a layer above the fill) and the bar's text.
local function Segment(health)
	local bar = CreateFrame("StatusBar", nil, health)
	if bar.SetUsingParentLevel then
		bar:SetUsingParentLevel(true)
	else
		bar:SetFrameLevel(health:GetFrameLevel())
	end
	bar:EnableMouse(false)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	bar:Hide()
	return bar
end

-- each segment as wide as the health bar (its fill is its share of it)
local function Widths(set)
	local w = Num(MelloUI.Safe.Call(set.health, "GetWidth"))
	if w and w > 0 then
		set.mine:SetWidth(w)
		set.other:SetWidth(w)
		set.shield:SetWidth(w)
	end
end

-- the chain: mine on the health fill's right edge, others' on mine's, the
-- shield on others' (a zero fill ends where it starts)
-- the segments' fills one sublevel after another over the health fill's (its
-- layer as it is now: Bar Textures may lift it), the shield's stripes over
-- them; set only when the fill's layer changed
local function Layers(set, fill)
	local ok, layer, sub = pcall(fill.GetDrawLayer, fill)
	if not ok or Secret(layer) or Secret(sub) or type(layer) ~= "string" then
		return
	end
	sub = Num(sub) or 0
	if layer == set.layer and sub == set.sub then
		return
	end
	set.layer, set.sub = layer, sub
	local k = 0
	for _, bar in ipairs({ set.mine, set.other, set.shield }) do
		k = k + 1
		local tex = bar:GetStatusBarTexture()
		if tex then
			tex:SetDrawLayer(layer, math.min(7, sub + k))
		end
	end
	if set.stripes then
		set.stripes:SetDrawLayer(layer, math.min(7, sub + 4))
	end
end

local function Chain(set)
	local fill = set.health:GetStatusBarTexture()
	if fill then
		Layers(set, fill)
	end
	if not fill or fill == set.fill then
		return fill ~= nil
	end
	set.fill = fill
	local prev = fill
	for _, bar in ipairs({ set.mine, set.other, set.shield }) do
		bar:ClearAllPoints()
		bar:SetPoint("TOPLEFT", prev, "TOPRIGHT")
		bar:SetPoint("BOTTOMLEFT", prev, "BOTTOMRIGHT")
		prev = bar:GetStatusBarTexture()
	end
	return true
end

local function HideHeals(set)
	set.mine:Hide()
	set.other:Hide()
	set.shield:Hide()
end

-- (the preview's stand-ins, MelloUI's own frames, below: sample heals from
-- their own plain health, mine / others' / the shield as shares of it,
-- clamped to what is missing as the calculator would)
local SAMPLE_HEALS = { 0.14, 0.09, 0.07 }
local function PaintSample(set)
	local health = set.health
	local okV, v = pcall(health.GetValue, health)
	local okM, _, hi = pcall(health.GetMinMaxValues, health)
	v, hi = okV and Num(v), okM and Num(hi)
	if not (active and M.db and M.db.incomingHeals and v and hi and hi > 0 and Chain(set)) then
		HideHeals(set)
		return
	end
	local missing = math.max(0, hi - v)
	local mine = math.min(hi * SAMPLE_HEALS[1], missing)
	local others = math.min(hi * SAMPLE_HEALS[2], missing - mine)
	local shield = math.min(hi * SAMPLE_HEALS[3], missing - mine - others)
	set.mine:SetMinMaxValues(0, hi)
	set.mine:SetValue(mine)
	set.other:SetMinMaxValues(0, hi)
	set.other:SetValue(others)
	set.shield:SetMinMaxValues(0, hi)
	set.shield:SetValue(shield)
	set.mine:Show()
	set.other:Show()
	set.shield:Show()
end

local function UpdateHeals(set)
	if set.sample then
		PaintSample(set)
		return
	end
	local c = Calculator()
	local unit = set.unit()
	if not (active and M.db and M.db.incomingHeals and c and unit and Chain(set)) then
		HideHeals(set)
		return
	end
	if not pcall(UnitGetDetailedHealPrediction, unit, "player", c) then
		HideHeals(set)
		return
	end
	local okI, _, mine, others = pcall(c.GetIncomingHeals, c)
	local okA, shield = pcall(c.GetDamageAbsorbs, c)
	local okM, max = pcall(UnitHealthMax, unit)
	if not (okI and okA and okM) then
		HideHeals(set)
		return
	end
	-- (every value handed on as it is: secret in a fight, never compared)
	set.mine:SetMinMaxValues(0, max)
	set.mine:SetValue(mine)
	set.other:SetMinMaxValues(0, max)
	set.other:SetValue(others)
	set.shield:SetMinMaxValues(0, max)
	set.shield:SetValue(shield)
	set.mine:Show()
	set.other:Show()
	set.shield:Show()
end

-- (one handler each for every health bar: the bar the script runs on)
local OnHealthChanged = Shared("OnValueChanged / OnMinMaxChanged on a health bar with incoming heals", function(health)
	local set = healOf[health]
	if set then
		UpdateHeals(set)
	end
end, "script")

local OnHealthSize = Shared("OnSizeChanged on a health bar with incoming heals", function(health)
	local set = healOf[health]
	if set then
		Widths(set)
	end
end, "script")

-- the heal bars on one health bar (once; out of combat)
local function MakeHeals(health, unit)
	if healOf[health] or InCombatLockdown() then
		return healOf[health]
	end
	local set = { health = health, unit = unit }
	set.mine, set.other, set.shield = Segment(health), Segment(health), Segment(health)
	set.mine:SetStatusBarTexture(WHITE)
	set.mine:SetStatusBarColor(Colour(_G.CUF_MY_HEAL_PREDICTION_COLOR))
	set.other:SetStatusBarTexture(WHITE)
	set.other:SetStatusBarColor(Colour(_G.CUF_OTHER_HEAL_PREDICTION_COLOR))
	if not pcall(set.shield.SetStatusBarTexture, set.shield, SHIELD_ATLAS) then
		set.shield:SetStatusBarTexture(WHITE)
	end
	local fill = set.shield:GetStatusBarTexture()
	if fill then
		local stripes = set.shield:CreateTexture(nil, "BACKGROUND")
		stripes:SetTexture(SHIELD_STRIPES, "REPEAT", "REPEAT")
		stripes:SetHorizTile(true)
		stripes:SetVertTile(true)
		stripes:SetPoint("TOPLEFT", fill, "TOPLEFT")
		stripes:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
		set.stripes = stripes
	end
	healOf[health] = set
	healSets[#healSets + 1] = set
	Widths(set)
	Chain(set)
	Perf.HookScript(health, "OnValueChanged", OnHealthChanged)
	Perf.HookScript(health, "OnMinMaxChanged", OnHealthChanged)
	Perf.HookScript(health, "OnSizeChanged", OnHealthSize)
	UpdateHeals(set)
	return set
end

--------------------------------------------------------------------------------
-- The debuff glow
--------------------------------------------------------------------------------

local RING_GROW = 1.34       -- the game's ring round a portrait, as a share of the portrait's width (the kit's: its rim, FitRing)
local RIM_TUCK = 4           -- piece px: the glow's edge this far under the kit ring's rim (no gap between them)
local BAR_PAD = 3            -- UI units: the bars' outline round the health and mana bars (their bracket's rails)
local GLOW_ALPHA = 0.9
local glows = {}             -- every glow made: { frame, unit (fallback), holder, ring, nine, raid }
local glowOf = setmetatable({}, WEAK)   -- [frame] = its glow

-- the curve from a debuff's dispel type to its colour: the game's own colours
-- (DEBUFF_TYPE_<TYPE>_COLOR; the type IDs of the client's SpellDispelType)
local DISPEL_TYPES = { { 1, "MAGIC", "Magic" }, { 2, "CURSE", "Curse" }, { 3, "DISEASE", "Disease" }, { 4, "POISON", "Poison" },
	{ 11, "BLEED", "Bleed" } }
local curve = nil
local function Curve()
	if curve == nil then
		curve = false
		local CU = C_CurveUtil
		if CU and CU.CreateColorCurve and C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor then
			local ok, c = pcall(CU.CreateColorCurve)
			if ok and c then
				if Enum and Enum.LuaCurveType then
					pcall(c.SetType, c, Enum.LuaCurveType.Step)
				end
				for _, t in ipairs(DISPEL_TYPES) do
					local col = _G["DEBUFF_TYPE_" .. t[2] .. "_COLOR"]
					if not col and type(DebuffTypeColor) == "table" and DebuffTypeColor[t[3]] and CreateColor then
						local d = DebuffTypeColor[t[3]]
						col = CreateColor(d.r, d.g, d.b, 1)
					end
					if col then
						pcall(c.AddPoint, c, t[1], col)
					end
				end
				curve = c
			end
		end
	end
	return curve or nil
end

-- a friend: a unit I can help (an answer that is secret counts as one)
local function Friend(unit)
	local ok, v = pcall(UnitCanAssist, "player", unit)
	if not ok then
		return false
	end
	return Secret(v) or (v and true or false)
end

-- the colour of the unit's first debuff the setting keeps: found, r, g, b
local function DispelColour(unit)
	local c = Curve()
	if not c then
		return false
	end
	local ok, ids = pcall(C_UnitAuras.GetUnitAuraInstanceIDs, unit, FILTER[M.db.debuffGlowShows] or FILTER.all, 1)
	if not ok or type(ids) ~= "table" then
		return false
	end
	-- (a list the client may hand out secret: its first entry read guarded)
	local okI, id = pcall(rawget, ids, 1)
	if not okI then
		return false
	end
	if not Secret(id) and id == nil then
		return false
	end
	local okC, col = pcall(C_UnitAuras.GetAuraDispelTypeColor, unit, id, c)
	if not okC or type(col) ~= "table" or not col.GetRGB then
		return false
	end
	local r, g, b = col:GetRGB()
	return true, r, g, b
end

-- The round glow hugs the ring it lies under (user, 2026-10-04: "a lot of
-- space between the round border and the glow"): the kit's ring by its rim
-- (Kit:RingRim; the kit fits the portrait to 0.759 x the ring, so the
-- portrait's width overshoots it), else the game's ring round the portrait.
-- Set only when the ring or its size changed; an unreadable (secret) width
-- leaves it as it was.
local function FitRing(g)
	if not (g.ring and g.area) then
		return
	end
	local panel = MelloUI:GetModule("UnitFramePanel")
	local ring = panel and panel.RingOf and panel:RingOf(g.portrait)
	local region, w, share = ring
	if ring then
		w, share = Num(MelloUI.Safe.Call(ring, "GetWidth")), Kit:RingRim(ring, RIM_TUCK)
	else
		region = g.portrait
		w, share = Num(MelloUI.Safe.Call(region, "GetWidth")), RING_GROW
	end
	if not (w and w > 0) then
		return
	end
	local size = w * share
	if region == g.ringOn and size == g.ringSize then
		return
	end
	g.ringOn, g.ringSize = region, size
	g.area:ClearAllPoints()
	g.area:SetPoint("CENTER", region, "CENTER")
	g.area:SetSize(size, size)
	g.ring:Anchor(g.area, size)
end

local function ShowGlow(g, on, r, gg, b)
	if on then
		if g.ring then
			FitRing(g)
			g.ring:SetTint(r, gg, b)
			g.ring:SetShown(true)
		end
		if g.nine then
			Kit:GlowShow(g.nine, r, gg, b, GLOW_ALPHA)
		end
		if g.raid then
			local panel = MelloUI:GetModule("RaidFramePanel")
			local rail = panel and panel.RailSkin and panel:RailSkin(g.frame)
			if rail then
				Kit:TintSkin(rail, r, gg, b)
				g.rail = rail
			end
		end
		g.shown = true
		return
	end
	if g.ring then
		g.ring:SetShown(false)
	end
	if g.nine then
		Kit:GlowShow(g.nine, nil)
	end
	if g.rail then
		Kit:TintSkin(g.rail, nil)
		g.rail = nil
	end
	g.shown = false
end

local function UpdateGlow(g)
	if g.sample then
		return   -- (the preview's while it plays: put back at its stop)
	end
	if not (active and M.db and M.db.debuffGlow) then
		ShowGlow(g, false)
		return
	end
	local unit = UnitOf(g.frame, g.unit)
	if not (unit and Friend(unit)) then
		ShowGlow(g, false)
		return
	end
	local found, r, gg, b = DispelColour(unit)
	ShowGlow(g, found, r, gg, b)
	g.lastUnit = unit
end

-- the glow round one frame (once; out of combat): parts = UNIT_FRAMES' or
-- PARTY's accessors; raid = a compact frame (its rect, the rail's weight)
local function MakeGlow(frame, parts, unit, raid)
	if glowOf[frame] or InCombatLockdown() then
		return glowOf[frame]
	end
	local holder = CreateFrame("Frame", nil, frame)
	holder:SetAllPoints(frame)
	holder:EnableMouse(false)
	-- (one level under the frame: under the frame's own art and the kit's, over the world)
	holder:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
	local g = { frame = frame, unit = unit, holder = holder, raid = raid }
	if raid then
		g.nine = Kit:GlowNine(holder, frame, "window/single", { scale = Kit.scale * 0.8, alpha = GLOW_ALPHA })
	else
		local portrait = parts.portrait and parts.portrait(frame)
		local w = portrait and Num(MelloUI.Safe.Call(portrait, "GetWidth"))
		if w and w > 0 and MelloUI.Shade and MelloUI.Shade.Glow then
			local area = CreateFrame("Frame", nil, holder)
			area:SetSize(w * RING_GROW, w * RING_GROW)
			area:SetPoint("CENTER", portrait, "CENTER")
			g.ring = MelloUI.Shade:Glow(holder, { region = area, size = w * RING_GROW, strength = GLOW_ALPHA })
			if g.ring then
				g.ring:Still()
				g.area, g.portrait = area, portrait
				FitRing(g)
			end
		end
		local health = parts.health and parts.health(frame)
		local mana = parts.mana and parts.mana(frame)
		if health then
			local area = CreateFrame("Frame", nil, holder)
			area:SetPoint("TOPLEFT", health, "TOPLEFT", -BAR_PAD, BAR_PAD)
			area:SetPoint("BOTTOMRIGHT", mana or health, "BOTTOMRIGHT", BAR_PAD, -BAR_PAD)
			g.nine = Kit:GlowNine(holder, area, "window/single", { scale = Kit.scale * Kit.frameScale, alpha = GLOW_ALPHA })
		end
	end
	glowOf[frame] = g
	glows[#glows + 1] = g
	UpdateGlow(g)
	return g
end

--------------------------------------------------------------------------------
-- The frames
--------------------------------------------------------------------------------

local function SetUpUnitFrames()
	for _, e in ipairs(UNIT_FRAMES) do
		local f = e.frame()
		if type(f) == "table" and f.GetObjectType then
			MakeGlow(f, e, e.unit)
			if e.heals then
				local health = e.health(f)
				if health and health.GetStatusBarTexture then
					local frame, fallback = f, e.unit
					MakeHeals(health, function() return UnitOf(frame, fallback) end)
				end
			end
		end
	end
end

local function SetUpParty()
	local pf = PartyFrame
	if not (pf and pf.PartyMemberFramePool) then
		return
	end
	for frame in pf.PartyMemberFramePool:EnumerateActive() do
		MakeGlow(frame, PARTY, nil)
		local pet = frame.PetFrame
		if pet then
			MakeGlow(pet, PARTY_PET, nil)
		end
	end
end

local function SetUpCompact(frame)
	if type(frame) == "table" and frame.healthBar then
		MakeGlow(frame, nil, nil, true)
	end
end

local function SetUpRaid()
	for i = 1, 8 do
		for j = 1, 5 do
			SetUpCompact(_G["CompactRaidGroup" .. i .. "Member" .. j])
		end
	end
	for i = 1, 40 do
		SetUpCompact(_G["CompactRaidFrame" .. i])
	end
	for i = 1, 5 do
		SetUpCompact(_G["CompactPartyFrameMember" .. i])
		SetUpCompact(_G["CompactPartyFramePet" .. i])
	end
end

local SETUP_KEY = "Healer frames: set up"
local function SetUpAll()
	if not active then
		return
	end
	SetUpUnitFrames()
	SetUpParty()
	SetUpRaid()
end

local function RefreshAll()
	for _, set in ipairs(healSets) do
		UpdateHeals(set)
	end
	for _, g in ipairs(glows) do
		UpdateGlow(g)
	end
end

-- every set and glow of a unit (a unit's event)
local function RefreshUnit(unit, healsToo)
	if healsToo then
		for _, set in ipairs(healSets) do
			if set.unit() == unit then
				UpdateHeals(set)
			end
		end
	end
	for _, g in ipairs(glows) do
		if UnitOf(g.frame, g.unit) == unit then
			UpdateGlow(g)
		end
	end
end

-- an aura update that adds or removes nothing (a duration refreshed): no
-- debuff came or went
local function Quiet(info)
	if type(info) ~= "table" then
		return false
	end
	local full, added, removed = info.isFullUpdate, info.addedAuras, info.removedAuraInstanceIDs
	-- (any of them secret: nothing can be told from it, so the unit is asked)
	if Hidden(full) or Hidden(added) or Hidden(removed) then
		return false
	end
	if full then
		return false
	end
	return not (type(added) == "table" and #added > 0) and not (type(removed) == "table" and #removed > 0)
end

local HEAL_EVENTS = { UNIT_HEAL_PREDICTION = true, UNIT_ABSORB_AMOUNT_CHANGED = true, UNIT_HEAL_ABSORB_AMOUNT_CHANGED = true,
	UNIT_MAXHEALTH = true }

local events = nil
local function OnEvent(_, event, unit, info)
	if not active then
		return
	end
	if (event == "UNIT_AURA" or HEAL_EVENTS[event]) and not Text(unit) then
		-- (a unit that cannot be read plainly: every frame asked again)
		RefreshAll()
	elseif event == "UNIT_AURA" then
		if not Quiet(info) then
			RefreshUnit(unit)
		end
	elseif HEAL_EVENTS[event] then
		RefreshUnit(unit, true)
	elseif event == "UNIT_TARGET" then
		RefreshUnit(unit == "focus" and "focustarget" or "targettarget", true)
	elseif event == "GROUP_ROSTER_UPDATE" or event == "UNIT_PET" then
		Kit:WhenOutOfCombat(SetUpAll, SETUP_KEY)
		RefreshAll()
	else
		-- the target, the focus: new units on their frames
		RefreshAll()
	end
end

local PreviewBeat   -- (below: the preview's beats, heard from the first switch-on)

local function Hook()
	if hooked then
		return
	end
	hooked = true
	events = CreateFrame("Frame")
	for _, e in ipairs({ "UNIT_AURA", "UNIT_HEAL_PREDICTION", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
		"UNIT_MAXHEALTH", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "GROUP_ROSTER_UPDATE", "UNIT_PET" }) do
		pcall(events.RegisterEvent, events, e)
	end
	pcall(events.RegisterUnitEvent, events, "UNIT_TARGET", "target", "focus")
	Perf.SetScript(events, "OnEvent", OnEvent)
	-- the compact frames are set up (and given a unit) by the game on every
	-- roster and profile change
	for _, fname in ipairs({ "DefaultCompactUnitFrameSetup", "DefaultCompactMiniFrameSetup" }) do
		if type(_G[fname]) == "function" then
			hooksecurefunc(fname, function(frame)
				if active then
					Kit:WhenOutOfCombat(function() SetUpCompact(frame) end)
				end
			end)
		end
	end
	if type(CompactUnitFrame_SetUnit) == "function" then
		hooksecurefunc("CompactUnitFrame_SetUnit", function(frame)
			local g = active and glowOf[frame]
			if g then
				UpdateGlow(g)
			end
		end)
	end
	-- a new palette: the glows keep their colours (Kit:ShadowTint, the round
	-- glow's SetTint) -- nothing to do here
	-- the preview's scenes (its part "healer")
	MelloUI:On("preview", PreviewBeat, M)
	-- the unit frames' look switched (the kit's ring on or off): the round
	-- glows hug the ring that shows now
	MelloUI:On("cover", function(group)
		if group == "unitframes" or group == "partyframes" then
			for _, g in ipairs(glows) do
				FitRing(g)
			end
		end
	end, M)
end

--------------------------------------------------------------------------------
-- The preview (MelloUI.Preview, its part "healer"; the user, 2026-10-04: "how
-- can i simulate and see how it works ingame? Can you adjust the Preview to
-- see it in action?"). Out of combat, MelloUI's own state only: on the
-- preview's stand-in party (its own frames, hurt and healed through the
-- scene) sample heals that follow their health and a debuff glow each in
-- one of the four colours; on the player frame the glow going through the
-- four. All put back at the stop.
--------------------------------------------------------------------------------

local SAMPLE_TYPES = { "MAGIC", "CURSE", "DISEASE", "POISON" }
local HITS_PER_COLOUR = 3
local previewing = { on = false, sets = {}, glows = {} }

local function NoUnit()
	return nil
end

-- the game's own colour of the i-th sample type (plain: a sample, no aura)
local function SampleColour(i)
	local c = _G["DEBUFF_TYPE_" .. SAMPLE_TYPES[(i - 1) % #SAMPLE_TYPES + 1] .. "_COLOR"]
	if type(c) == "table" and c.GetRGB then
		return c:GetRGB()
	end
	return 1, 1, 1
end

local function SampleGlow(g, i)
	if active and M.db and M.db.debuffGlow then
		ShowGlow(g, true, SampleColour(i))
	else
		ShowGlow(g, false)
	end
end

PreviewBeat = function(beat, _, n)
	local P = MelloUI.Preview
	if beat == "stop" then
		if previewing.on then
			previewing.on = false
			for _, set in ipairs(previewing.sets) do
				set.sample = false
				HideHeals(set)
			end
			for _, g in ipairs(previewing.glows) do
				g.sample = false
				ShowGlow(g, false)
			end
			wipe(previewing.sets)
			wipe(previewing.glows)
			RefreshAll()
		end
		return
	end
	if not (active and P and P:Plays("healer")) then
		return
	end
	if beat == "start" then
		previewing.on = true
		for i = 1, #P.PARTY do
			local f = P:StandIn(i)
			if f then
				local health = PARTY.health(f)
				local set = health and MakeHeals(health, NoUnit)
				if set then
					set.sample = true
					previewing.sets[#previewing.sets + 1] = set
					UpdateHeals(set)
				end
				local g = MakeGlow(f, PARTY, nil)
				if g then
					g.sample = true
					previewing.glows[#previewing.glows + 1] = g
					SampleGlow(g, i)
				end
			end
		end
		local pg = glowOf[PlayerFrame]
		if pg then
			pg.sample = true
			previewing.glows[#previewing.glows + 1] = pg
			SampleGlow(pg, 1)
		end
	elseif beat == "hit" and previewing.on then
		local pg = glowOf[PlayerFrame]
		if pg and pg.sample then
			SampleGlow(pg, math.floor(((n or 1) - 1) / HITS_PER_COLOUR) + 1)
		end
	end
end

local function SetUpSoon()
	Kit:WhenOutOfCombat(SetUpAll, SETUP_KEY)
end

function M:OnEnable(db)
	self.db = db
	active = true
	Hook()
	-- (the HUD's pieces after the login's frames, as the UI shade's)
	MelloUI:AfterLogin(SetUpSoon)
	RefreshAll()
end

function M:OnDisable()
	active = false
	RefreshAll()
end

function M:OnSettingChanged(_, _, db)
	self.db = db
	RefreshAll()
end

--------------------------------------------------------------------------------
-- The dump (/ufdump heals, UnitFramePanel's): each frame's unit, its glow
-- and its heal bars as they are now
--------------------------------------------------------------------------------
function M:Dump(print)
	print("Healer Frames: %s; calculator %s, colour curve %s; Debuff Glow Shows %s", active and "on" or "off",
		Calculator() and "yes" or "NO", Curve() and "yes" or "NO", tostring(self.db and self.db.debuffGlowShows))
	for _, set in ipairs(healSets) do
		print("heals on %s (%s): shown %s", set.health:GetName() or "?", tostring(set.unit()), tostring(set.mine:IsShown()))
	end
	local filter = FILTER[self.db and self.db.debuffGlowShows] or FILTER.all
	for _, g in ipairs(glows) do
		local unit = UnitOf(g.frame, g.unit)
		local ids = unit and select(2, pcall(C_UnitAuras.GetUnitAuraInstanceIDs, unit, filter))
		print("glow on %s (%s): %s, %d debuff(s) kept%s", g.frame:GetName() or "?", tostring(unit), g.shown and "SHOWN" or "hidden",
			type(ids) == "table" and #ids or 0, g.rail and ", rail tinted" or "")
	end
end

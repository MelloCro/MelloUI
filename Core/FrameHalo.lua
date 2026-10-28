--------------------------------------------------------------------------------
-- MelloUI - Frame halo (1.2.4; MelloUI.FrameHalo)
--
-- A soft light behind a unit frame, round its own shape (the frames' shape system, FX.Shape: the portrait's ring, the
-- plate's box, the level badge): Shade's round glow round the ring, a hollow soft band round the plate, a small glow
-- round the badge, on a frame of their own at the strata under the frame's -- the frame's whole art lies over it, so
-- it shows round the outline only and nothing of it ties with the frame. The mouseover highlight's glow
-- (Core/FrameHover.lua) and the threat halo below are made of it.
--
-- The threat halo (the user, 2026-10-28: "Hide Combat Flash option ticked off, if players preffer to use it, it needs
-- to fit the Player Unitframe Borders and Artwork and be adjusted properly trought all of the different themes"; their
-- pick "A: halo" of MelloUI-BuildData/output/combat_flash_sketch). The game's combat flash is each unit frame's threat
-- indicator (UnitFrame_UpdateThreatIndicator: shown while the unit has threat, yellow / orange / red by how much,
-- still). Unit Frames keeps it hidden while the module is on; with Hide Combat Flash unticked a halo of ours follows it
-- instead -- the player, target, focus, pet, party members and their pets: shown while the game shows its indicator
-- (post-hooks on its Show, Hide and SetShown, which the game calls from its threat event, never per frame; the frame's
-- own show and hide), amber (MelloUI.Meaning.threatClose) at threat 1, red (threatAggro) at 2 and 3 and while the game
-- keeps the threat secret. In 0.25 s; amber to red over 0.3 s with one brighter beat (red to amber the same, no beat);
-- out in 0.4 s. Still: nothing loops. Reduce Motion (MelloUI.Anim): shown and hidden at once. A frame's halos are made
-- at its first threat, never at login.
--
--   MelloUI.FrameHalo.Make([opts][, into]) -> halo   opts: key (a palette or meaning key, "selectedTrim"), badge
--                                  (true: a glow round the level badge too); `into`: the table filled (a caller's own)
--   MelloUI.FrameHalo.Lay(halo, frame[, S]) -> laid   round `frame`'s shape S (FX.Shape's, read now when left out),
--                                  hung on the frame, at the strata under its; false when it has no shape
--   MelloUI.FrameHalo.Paint(halo, key)               its colour (a palette or meaning key)
--   MelloUI.FrameHalo.Strength(halo, share)          its light at that share of its strengths
--   MelloUI.FrameHalo.Threat(on)   Unit Frames' Hide Combat Flash: on (unticked, the module on) follows the game's
--                                  threat indicators; off hides every threat halo at once
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Safe = MelloUI.Safe
local Secret, Text, Num = Safe.IsSecret, Safe.Text, Safe.Number
local Perf = MelloUI.Perf:Scope("Frame halo")
local FX = MelloUI.FrameFX
local max, pi, sin = math.max, math.pi, math.sin

local Halo = {}
MelloUI.FrameHalo = Halo

-- the strata under a frame's; the light (the mouseover highlight's, 2026-10-25): the ring's and the badge's glow
-- (Shade's "near"), the band's alpha and soft edges, the glows' sizes
local STRATA_BELOW = { LOW = "BACKGROUND", MEDIUM = "LOW", HIGH = "MEDIUM", DIALOG = "HIGH" }
local LIGHT = { ring = 0.7, band = 0.55, feather = 10, featherY = 8, ringSize = 40, badgeSize = 20 }

local function PaintGlow(glow, key, c)
	if not glow then
		return
	end
	if c then
		glow:SetTint(c[1], c[2], c[3])
	else
		glow:SetTint(nil)
		glow:SetColour(key)
	end
end

-- its colour: a palette key, or a meaning colour's key (MelloUI.Meaning: the glows take it as a tint, the band by key)
function Halo.Paint(h, key)
	h.key = key
	local c = MelloUI.Meaning[key]
	if not (type(c) == "table" and type(c[1]) == "number") then
		c = nil
	end
	PaintGlow(h.glow, key, c)
	PaintGlow(h.badge, key, c)
	if h.band then
		h.band:SetColour(key)
	end
end

function Halo.Strength(h, share)
	h.share = share
	if h.glow then
		h.glow:SetStrength(LIGHT.ring * share)
	end
	if h.badge then
		h.badge:SetStrength(LIGHT.ring * share)
	end
	if h.band then
		h.band:SetStrength(LIGHT.band * share)
	end
end

function Halo.Make(opts, into)
	opts = opts or {}
	local h = into or {}
	local Shade = MelloUI.Shade
	h.key, h.share = opts.key or "selectedTrim", 1
	h.back = CreateFrame("Frame", nil, UIParent)
	h.back:EnableMouse(false)
	h.back:Hide()
	h.ring = CreateFrame("Frame", nil, h.back)
	h.plate = CreateFrame("Frame", nil, h.back)
	h.glow = Shade:Glow(h.back, { key = "selectedTrim", region = h.ring, size = LIGHT.ringSize, strength = "near" })
	if h.glow then
		h.glow:Still()
	end
	h.band = Shade:Band(h.back, { colour = h.key, alpha = LIGHT.band, feather = LIGHT.feather,
		featherY = LIGHT.featherY, blend = "ADD", hollow = true, region = h.plate })
	if opts.badge then
		h.orb = CreateFrame("Frame", nil, h.back)
		h.badge = Shade:Glow(h.back, { key = "selectedTrim", region = h.orb, size = LIGHT.badgeSize, strength = "near" })
		if h.badge then
			h.badge:Still()
		end
	end
	Halo.Paint(h, h.key)
	return h
end

-- laid round the shape (on the screen, UIParent's units), its parts hung on the frame: they follow where it moves
function Halo.Lay(h, frame, S)
	S = S or (FX.Shape and FX.Shape(frame))
	local fl, fb = FX.Rect(frame)
	if not (S and fl and S.pl) then
		h.back:Hide()
		return false
	end
	local okS, strata = pcall(frame.GetFrameStrata, frame)
	local okL, level = pcall(frame.GetFrameLevel, frame)
	strata, level = okS and Text(strata) or "MEDIUM", okL and Num(level) or 1
	local below = STRATA_BELOW[strata]
	h.back:SetFrameStrata(below or strata)
	h.back:SetFrameLevel(below and 1 or max(0, level - 1))
	h.plate:ClearAllPoints()
	h.plate:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", S.pl - fl, S.pb - fb)
	h.plate:SetSize(max(1, S.pr - S.pl), max(1, S.pt - S.pb))
	if h.band then
		h.band:SetShown(true)
	end
	if h.glow then
		if S.rr then
			h.ring:ClearAllPoints()
			h.ring:SetPoint("CENTER", frame, "BOTTOMLEFT", S.rx - fl, S.ry - fb)
			h.ring:SetSize(2 * S.rr, 2 * S.rr)
			h.glow:Anchor(h.ring, 2 * S.rr)
			h.glow:SetShown(true)
		else
			h.glow:SetShown(false)
		end
	end
	if h.badge then
		local ol, ob, orr, ot
		if S.orb and FX.Visible(S.orb) then
			ol, ob, orr, ot = FX.Rect(S.orb)
		end
		if ol and orr > ol then
			local d = orr - ol
			h.orb:ClearAllPoints()
			h.orb:SetPoint("CENTER", frame, "BOTTOMLEFT", (ol + orr) / 2 - fl, (ob + ot) / 2 - fb)
			h.orb:SetSize(d, d)
			h.badge:Anchor(h.orb, d)
			h.badge:SetShown(true)
		else
			h.badge:SetShown(false)
		end
	end
	return true
end

--------------------------------------------------------------------------------
-- The threat halo
--------------------------------------------------------------------------------

-- the seconds: in, out, amber to red (and back), the beat; the beat's peak (a share of the light's strengths)
local TIME = { fadeIn = 0.25, fadeOut = 0.4, turn = 0.3, beat = 0.5, peak = 1.5 }

local T = {
	on = false,
	frameOf = setmetatable({}, { __mode = "k" }),   -- [the game's indicator] = its unit frame (hooked once)
	hooked = setmetatable({}, { __mode = "k" }),    -- [unit frame] = true: its indicator and its show / hide hooked
	of = setmetatable({}, { __mode = "k" }),        -- [unit frame] = { close, aggro (halos), shown, key }
	beatOf = setmetatable({}, { __mode = "k" }),    -- [a red halo's back] = the halo (the beat's Drive)
}
Halo.threat = T   -- (the tests')

-- the unit frames the game lights (UnitFrame_Initialize's threatIndicator: the textures Unit Frames' combat flash
-- hides): the player, target, focus, pet, the party members and their pets
local function Each(fn)
	fn(rawget(_G, "PlayerFrame"))
	fn(rawget(_G, "TargetFrame"))
	fn(rawget(_G, "FocusFrame"))
	fn(rawget(_G, "PetFrame"))
	local party = rawget(_G, "PartyFrame")
	if type(party) == "table" then
		for i = 1, 4 do
			local m = rawget(party, "MemberFrame" .. i)
			if type(m) == "table" then
				fn(m)
				fn(rawget(m, "PetFrame"))
			end
		end
	end
end

local function Indicator(frame)
	local ind = type(frame) == "table" and rawget(frame, "threatIndicator") or nil
	return type(ind) == "table" and ind or nil
end

-- the game's own question (UnitFrame_UpdateThreatIndicator's: the unit's threat, on the frame's unit where they
-- differ -- the target's, the focus's), tested for a secret first: amber at 1; red at 2 and 3, and while it is secret
local function KeyOf(ind)
	local unit, feedback = rawget(ind, "unit"), rawget(ind, "feedbackUnit")
	if type(feedback) ~= "string" then
		feedback = unit
	end
	if type(feedback) ~= "string" then
		return "threatAggro"
	end
	local mob = (type(unit) == "string" and unit ~= feedback) and unit or nil
	local ok, status = pcall(_G.UnitThreatSituation, feedback, mob)
	if ok and not Secret(status) and type(status) == "number" and status <= 1 then
		return "threatClose"
	end
	return "threatAggro"
end

local function Shown(region)
	local ok, on = pcall(region.IsShown, region)
	if not ok or Secret(on) then
		return true
	end
	return on == true
end

-- the beat: the red halo's light swelling once and back (a shared step: Anim:Drive)
local function Beat(back, share)
	local h = T.beatOf[back]
	if h then
		Halo.Strength(h, 1 + (TIME.peak - 1) * sin(pi * share))
	end
end

local function HalosOf(frame)
	local t = T.of[frame]
	if not t then
		t = { close = Halo.Make({ key = "threatClose", badge = true }), aggro = Halo.Make({ key = "threatAggro", badge = true }),
			shown = false }
		T.beatOf[t.aggro.back] = t.aggro
		T.of[frame] = t
	end
	return t
end

local function Gone(h, fade)
	local back = h.back
	if not back:IsShown() then
		return
	end
	if fade then
		MelloUI.Anim:FadeOut(back, TIME.fadeOut)
	else
		MelloUI.Anim:Stop(back)
		back:Hide()
		back:SetAlpha(1)
	end
end

-- the frame's halo as the game's indicator stands now
local function Update(frame)
	local t = T.of[frame]
	local ind = Indicator(frame)
	local okV, visible = pcall(frame.IsVisible, frame)
	if not (T.on and ind and Shown(ind) and okV and visible == true) then
		if t and t.shown then
			-- (the game's indicator gone: faded out; the option ticked or the frame gone: at once)
			local fade = T.on and okV and visible == true
			t.shown, t.key = false, nil
			Gone(t.close, fade)
			Gone(t.aggro, fade)
		end
		return
	end
	t = t or HalosOf(frame)
	local key = KeyOf(ind)
	local Anim = MelloUI.Anim
	if not t.shown then
		if not (Halo.Lay(t.close, frame) and Halo.Lay(t.aggro, frame)) then
			return   -- (no shape to lay it round: none)
		end
		Halo.Strength(t.close, 1)
		Halo.Strength(t.aggro, 1)
		t.shown, t.key = true, key
		Anim:FadeIn((key == "threatClose" and t.close or t.aggro).back, TIME.fadeIn)
		return
	end
	if key == t.key then
		return
	end
	local from, to = t.key == "threatClose" and t.close or t.aggro, key == "threatClose" and t.close or t.aggro
	t.key = key
	Anim:FadeOut(from.back, TIME.turn)
	Anim:FadeIn(to.back, TIME.turn)
	if key == "threatAggro" then
		Anim:Drive(to.back, Beat, TIME.beat)
	end
end
Halo.Update = Update   -- (the tests': the sim's hooks)

local OnIndicator = Perf.Shared("the game's threat indicator shown or hidden: its frame's threat halo", function(ind)
	local frame = T.frameOf[ind]
	if frame then
		Update(frame)
	end
end)
local OnFrameShow = Perf.Shared("a unit frame shown: its threat halo", Update, "script")
-- (its frame gone: its halo at once, whatever the frame's state reads while its OnHide runs)
local OnFrameHide = Perf.Shared("a unit frame hidden: its threat halo away", function(frame)
	local t = T.of[frame]
	if t and t.shown then
		t.shown, t.key = false, nil
		Gone(t.close, false)
		Gone(t.aggro, false)
	end
end, "script")

local function Hook(frame)
	local ind = Indicator(frame)
	if not ind or T.hooked[frame] then
		return
	end
	T.hooked[frame] = true
	T.frameOf[ind] = frame
	hooksecurefunc(ind, "Show", OnIndicator)
	hooksecurefunc(ind, "Hide", OnIndicator)
	hooksecurefunc(ind, "SetShown", OnIndicator)
	Perf.HookScript(frame, "OnShow", OnFrameShow)
	Perf.HookScript(frame, "OnHide", OnFrameHide)
end

local function Refresh(frame)
	if type(frame) == "table" and (T.on or T.of[frame]) then
		Update(frame)
	end
end

function Halo.Threat(on)
	T.on = on and true or false
	if T.on then
		Each(Hook)
	end
	Each(Refresh)
end

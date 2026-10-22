--------------------------------------------------------------------------------
-- MelloUI - Impact Effects (0.25.0; the user, 2026-10-18, after the Thistle
-- Bear video and the Nameplate Impact page: "yes build it and sync to my
-- addon")
--
-- Your target's nameplate answers the fight:
--   * Hit Flash: a hit lights its bar's fill a moment (a crit in gold);
--   * Damage Chunk: the part a hit took stays lit, then drains -- a ghost bar
--     the engine eases (StatusBar:SetValue's ExponentialEaseOut), shown only
--     past the fill's live right edge by a clipping frame: health is secret
--     here, so nothing is compared or measured, the values go straight in;
--   * Crit Glow: a soft gold glow bursts round the bar;
--   * Kill Flash: the killing blow flashes the bar out (UnitIsDead is plain);
--   * Dodge And Miss: the word flicks off the plate's edge (Anim:Slide: a
--     plate's anchoring is secret, the slide sets the anchor and reads none);
--   * Cast Warning: the enemy's cast bar glows hotter towards its end and
--     shatters when the cast is interrupted.
-- (1.2.0, animations round 4; the user 2026-10-22, "all of them" to BuildData/output/animation_previews/
-- round4_anims.html) On Your Target Frame: the target frame's health bar answers the same way -- the flash, the chunk,
-- the crit glow, the kill flash (the words and the cast warning stay the plate's). The target frame is the game's
-- protected unit frame: our pieces for it are UIParent's, anchored to its bar in its strata above it (FX.Make's
-- `free`), so nothing is parented onto it; its bar found anew on each target (TargetFrame's content), made at its
-- first need.
-- From the page, Execute Shine and Debuff Pop were left out:
-- UnitHealthPercent is SecretReturns (the crossing cannot be seen), and the
-- aura data is hidden in a fight, its buttons the game's restricted ones.
--
-- The rules kept: the game's plate is never moved, scaled, hidden or written
-- on (our pieces by unit frame in weak tables; textures and frames of ours
-- made on it, as the plate names' bands); the target's plate only; pieces
-- made at its first need, never at login; nothing made per event (one driver
-- for the delayed drain); every colour the palette's (MelloUI.Look,
-- MelloUI.Shade's band); Reduce Motion: the flashes stay, the movement goes.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("PlateImpact")
local Secret = MelloUI.Safe.IsSecret

local M = MelloUI:RegisterModule("PlateImpact", {
	title = "Impact Effects",
	desc = "Your target's nameplate answers the fight: hits flash its bar, the part a hit took drains away, crits glow gold, a dodge or a miss flicks off its edge, an enemy's cast glows hotter towards its end and shatters when you interrupt it, and the killing blow flashes the bar out.",
	icon = "Interface\\Icons\\Ability_Warrior_Revenge",
	flavour = "Every hit lands on the plate, not only in a number.",
	role = "adds",
	installer = false,
	enabledByDefault = true,
	defaults = {
		flash = true,
		chunk = true,
		crit = true,
		kill = true,
		evade = true,
		cast = true,
		targetFrame = true,
	},
	options = {
		{ type = "toggle", key = "flash", name = "Hit Flash",
		  desc = "Your target's health bar flashes a moment when it is hit; a critical hit flashes gold." },
		{ type = "toggle", key = "chunk", name = "Damage Chunk",
		  desc = "The part of the bar a hit took stays lit for a moment, then drains away, so you see how big each hit was." },
		{ type = "toggle", key = "crit", name = "Crit Glow",
		  desc = "A soft gold glow bursts round your target's bar on a critical hit." },
		{ type = "toggle", key = "kill", name = "Kill Flash",
		  desc = "The killing blow flashes the bar out where the plate stood, instead of the plate simply vanishing." },
		{ type = "toggle", key = "evade", name = "Dodge And Miss",
		  desc = "When your target dodges, parries or is missed, the word flicks off the side of its plate." },
		{ type = "toggle", key = "cast", name = "Cast Warning",
		  desc = "Your target's cast bar glows hotter as its cast nears the end, and shatters when the cast is interrupted." },
		-- (1.2.0, animations round 4; the user, 2026-10-22: "all of them" to the round 4 previews)
		{ type = "toggle", key = "targetFrame", name = "On Your Target Frame", new = "1.2.0",
		  desc = "Your target frame's health bar answers the hits too: the flash, the part a hit took draining away, the gold glow of a critical hit and the killing blow's flash, as on your target's nameplate." },
	},
})

-- (one table: few top-level locals)
local FX = {
	rec = setmetatable({}, { __mode = "k" }),   -- [unit frame] = our pieces on its plate (and the target frame's)
	uf = nil,            -- the target's plate's unit frame
	frame = nil,         -- (1.2.0) the target frame while On Your Target Frame has it (its pieces in rec[TargetFrame])
	dead = false,        -- the target's killing blow seen (once a life)
	drainAt = nil,       -- the chunk's pending drain (GetTime), one at a time
	WHITE = "Interface\\Buttons\\WHITE8X8",
	DRAIN = 0.25,        -- the chunk lit this long before it drains
	FLASH = 0.16, CRIT = 0.26, GLOW = 0.45, KILL = 0.42, WORD = 0.7, SHARDS = 0.42,
	CAST_RAMP = 1.5,     -- a cast's glow ramp when its times are not to be read
	WORDS = { DODGE = "DODGE", PARRY = "PARRY", MISS = "MISS", EVADE = "EVADE", IMMUNE = "IMMUNE", RESIST = "RESIST",
		BLOCK = "BLOCK", ABSORB = "ABSORB", DEFLECT = "DEFLECT", REFLECT = "REFLECT" },
	WORD_FALLBACK = { DODGE = "Dodge", PARRY = "Parry", MISS = "Miss", EVADE = "Evade", IMMUNE = "Immune",
		RESIST = "Resist", BLOCK = "Block", ABSORB = "Absorb", DEFLECT = "Deflect", REFLECT = "Reflect" },
	SHARD = { { -26, -16, -10 }, { -15, -8, 12 }, { -5, -3, -14 }, { 5, 4, 13 }, { 15, 9, -11 }, { 26, 16, 10 } },
}

local function Palette(key)
	local look = MelloUI.Look
	local p = look and look.Palette and look.Palette()
	local c = p and p[key]
	if type(c) == "table" then
		return c[1] or 1, c[2] or 1, c[3] or 1
	end
	return 1, 1, 1
end

local function On(key)
	return M.isEnabled and M.db and M.db[key] ~= false
end

local function Anim()
	return MelloUI.Anim
end

local function Motion()
	local a = Anim()
	return not (a and a.reduceMotion)
end

-- the target's plate's unit frame, its health bar and its fill (nil: none, or forbidden)
function FX.Target()
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, "target")
	if not ok or type(plate) ~= "table" then
		return nil
	end
	local okF, forbidden = pcall(plate.IsForbidden, plate)
	if not okF or forbidden then
		return nil
	end
	local uf = plate.UnitFrame
	local bars = type(uf) == "table" and uf.HealthBarsContainer
	local bar = type(bars) == "table" and bars.healthBar
	if type(bar) ~= "table" or not bar.GetStatusBarTexture then
		return nil
	end
	return uf, bar
end

-- a frame's alpha eased (the engine's; a straight set when it is not there)
local function Fade(frame, from, to, duration, onDone)
	local a = Anim()
	if from then
		frame:SetAlpha(from)
	end
	if a and a.To then
		a:Stop(frame, "alpha")
		a:To(frame, "alpha", to, duration, to > (from or 0) and "inQuad" or "outQuad", onDone)
	else
		frame:SetAlpha(to)
		if onDone then
			onDone(frame)
		end
	end
end

local function HideFrame(f)
	f:Hide()
end

-- Our pieces on a plate, made once per unit frame at its first need (kept as
-- the plates recycle): over the bar a frame with the flash (on the fill) and
-- the crit glow (a soft band round the bar); the ghost bar in a clip from the
-- fill's right edge to the bar's; the words; on the cast bar its glow.
-- (1.2.0) the fill's own picture: its atlas (the game's bar shape -- the target frame's has clear rows top and bottom,
-- seen in wowsim 2026-10-22), else its file, else the white one -> the asset, and whether it is an atlas. The chunk and
-- the flash take its shape
function FX.FillLook(fill)
	local okA, atlas = pcall(fill.GetAtlas, fill)
	if okA and not Secret(atlas) and type(atlas) == "string" and atlas ~= "" then
		return atlas, true
	end
	local ok, file = pcall(fill.GetTexture, fill)
	if ok and not Secret(file) and (type(file) == "string" or type(file) == "number") then
		return file, false
	end
	return FX.WHITE, false
end

-- (1.2.0) `free`: the pieces UIParent's, anchored to the bar in its strata (the target frame: protected, nothing
-- parented onto it)
function FX.Make(uf, bar, free)
	local r = FX.rec[uf]
	if r then
		return r
	end
	local ok, fill = pcall(bar.GetStatusBarTexture, bar)
	if not ok or type(fill) ~= "table" then
		return nil
	end
	r = {}
	local level = bar:GetFrameLevel() or 1
	local host = free and UIParent or bar
	local strata = free and bar:GetFrameStrata() or nil
	-- the ghost: a full bar of ours behind a clip that starts where the fill ends
	local clip = CreateFrame("Frame", nil, host)
	if strata then
		clip:SetFrameStrata(strata)
	end
	clip:SetClipsChildren(true)
	clip:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
	clip:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
	clip:SetFrameLevel(level + 2)
	local ghost = CreateFrame("StatusBar", nil, clip)
	ghost:SetAllPoints(bar)
	local file, isAtlas = FX.FillLook(fill)
	ghost:SetStatusBarTexture(file)
	-- (its own colours out: the chunk and the flash in the palette's, the bar's shape kept)
	local okG, gtex = pcall(ghost.GetStatusBarTexture, ghost)
	if okG and type(gtex) == "table" and gtex.SetDesaturated then
		gtex:SetDesaturated(true)
		gtex:SetBlendMode("ADD")   -- (added to the empty bar under it: pale, as the white chunk was)
	end
	r.clip, r.ghost = clip, ghost
	-- the flash and the glow
	local top = CreateFrame("Frame", nil, host)
	if strata then
		top:SetFrameStrata(strata)
	end
	top:SetAllPoints(bar)
	top:SetFrameLevel(level + 4)
	local flashHost = CreateFrame("Frame", nil, top)
	flashHost:SetAllPoints(fill)
	flashHost:SetAlpha(0)
	local flash = flashHost:CreateTexture(nil, "OVERLAY")
	flash:SetAllPoints(flashHost)
	if isAtlas then
		flash:SetAtlas(file)
	else
		flash:SetTexture(file)
	end
	flash:SetDesaturated(true)
	flash:SetBlendMode("ADD")
	r.top, r.flashHost, r.flash = top, flashHost, flash
	-- (the glow under the bar, so only its halo shows round it: a band has a
	-- solid middle -- seen in the simulator, 2026-10-18, gold over the bar)
	local glowHost = CreateFrame("Frame", nil, free and UIParent or (bar:GetParent() or bar))
	if strata then
		glowHost:SetFrameStrata(strata)
	end
	glowHost:SetAllPoints(bar)
	glowHost:SetFrameLevel(math.max(0, level - 1))
	glowHost:SetAlpha(0)
	local Shade = MelloUI.Shade
	local glow = Shade and Shade:Band(glowHost, { colour = "selectedTrim", feather = 10, layer = "BACKGROUND", pixel = true })
	if glow then
		glow:Anchor(bar, 6, 6)
		glow:SetStrength(1)
		glow:SetShown(true)
	end
	r.glowHost = glowHost
	-- two words, in turn
	r.words, r.nextWord = {}, 1
	for i = 1, 2 do
		local w = CreateFrame("Frame", nil, top)
		w:SetSize(80, 16)
		w:Hide()
		w.text = w:CreateFontString(nil, "OVERLAY", "MelloUIFont_GameFontNormalSmall")
		w.text:SetPoint("LEFT", w, "LEFT", 0, 0)
		w.text:SetJustifyH("LEFT")
		w.text:SetShadowOffset(1, -1)
		r.words[i] = w
	end
	-- the cast bar's glow and its shards (the shards on the plate: the cast
	-- bar hides as its cast ends; a plate's only)
	local cast = not free and uf.castBar
	if type(cast) == "table" and cast.CreateTexture then
		-- (under the cast bar too: its halo round it; let down by the cast's end events)
		local castGlow = CreateFrame("Frame", nil, cast:GetParent() or uf)
		castGlow:SetAllPoints(cast)
		castGlow:SetFrameLevel(math.max(0, (cast:GetFrameLevel() or level) - 1))
		castGlow:SetAlpha(0)
		local band = Shade and Shade:Band(castGlow, { colour = "selectedTrim", feather = 8, layer = "BACKGROUND", pixel = true })
		if band then
			band:Anchor(cast, 4, 4)
			band:SetStrength(1)
			band:SetShown(true)
		end
		r.cast, r.castGlow = cast, castGlow
		r.shards = {}
		for i = 1, #FX.SHARD do
			local s = CreateFrame("Frame", nil, uf)
			s:SetSize(9, 6)
			s:SetFrameLevel((cast:GetFrameLevel() or level) + 4)
			s.tex = s:CreateTexture(nil, "OVERLAY")
			s.tex:SetAllPoints(s)
			s.tex:SetTexture(FX.WHITE)
			s:Hide()
			r.shards[i] = s
		end
	end
	FX.rec[uf] = r
	return r
end

-- the ghost set to the target's health at once, or eased (the drain)
function FX.Ghost(r, eased)
	local ghost = r and r.ghost
	if not ghost then
		return
	end
	local okM, max = pcall(UnitHealthMax, "target")
	local okH, hp = pcall(UnitHealth, "target")
	if not (okM and okH) or max == nil or hp == nil then
		return
	end
	pcall(ghost.SetMinMaxValues, ghost, 0, max)
	local smooth = eased and Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
	if smooth then
		pcall(ghost.SetValue, ghost, hp, smooth)
	else
		pcall(ghost.SetValue, ghost, hp)
	end
end

function FX.Paint(r)
	local lr, lg, lb = Palette("text")
	r.ghost:SetStatusBarColor(lr, lg, lb, 0.85)
end

-- the target's plate taken on (or let go): its pieces made, the ghost on its health
function FX.Attach()
	local uf, bar = FX.Target()
	if FX.uf and FX.uf ~= uf then
		FX.Calm(FX.rec[FX.uf])
	end
	FX.uf = uf
	FX.dead = false
	FX.drainAt = nil
	if not uf then
		return
	end
	local r = FX.Make(uf, bar)
	if not r then
		FX.uf = nil
		return
	end
	FX.Paint(r)
	r.clip:SetShown(On("chunk"))
	FX.Ghost(r, false)
	FX.CastNow()
end

-- a plate let go: nothing of ours left lit on it
function FX.Calm(r)
	if not r then
		return
	end
	local a = Anim()
	for _, f in ipairs({ r.flashHost, r.glowHost, r.castGlow }) do
		if f then
			if a then
				a:Stop(f, "alpha")
			end
			f:SetAlpha(0)
		end
	end
	for _, w in ipairs(r.words) do
		w:Hide()
	end
	r.clip:Hide()
end

local function Rec()
	return FX.uf and FX.rec[FX.uf] or nil
end

-- (1.2.0) the target frame's pieces while On Your Target Frame has it
local function FrameRec()
	return FX.frame and FX.rec[FX.frame] or nil
end

-- (1.2.0) the target frame and its health bar while there is a target (nil: none, the option off)
function FX.TargetFrame()
	local tf = rawget(_G, "TargetFrame")
	local content = type(tf) == "table" and tf.TargetFrameContent
	local main = type(content) == "table" and content.TargetFrameContentMain
	local bars = type(main) == "table" and main.HealthBarsContainer
	local bar = type(bars) == "table" and bars.HealthBar
	if type(bar) ~= "table" or not bar.GetStatusBarTexture then
		return nil
	end
	local okE, exists = pcall(UnitExists, "target")
	if not okE or Secret(exists) or not exists then
		return nil
	end
	return tf, bar
end

-- (1.2.0) the target frame taken on with a new target (or let go)
function FX.AttachFrame()
	FX.Calm(FrameRec())
	FX.frame = nil
	if not On("targetFrame") then
		return
	end
	local tf, bar = FX.TargetFrame()
	if not tf then
		return
	end
	local r = FX.Make(tf, bar, true)
	if not r then
		return
	end
	FX.frame = tf
	FX.Paint(r)
	r.clip:SetShown(On("chunk"))
	FX.Ghost(r, false)
end

-- a hit on one bar's pieces: the flash, a crit's glow
local function HitOn(r, crit)
	if not r then
		return
	end
	if On("flash") then
		r.flash:SetVertexColor(Palette(crit and "selectedTrim" or "text"))
		Fade(r.flashHost, crit and 0.95 or 0.75, 0, crit and FX.CRIT or FX.FLASH)
	end
	if crit and On("crit") then
		Fade(r.glowHost, 1, 0, FX.GLOW)
	end
end

-- a hit: on the plate and the target frame
function FX.Hit(crit)
	HitOn(Rec(), crit)
	HitOn(FrameRec(), crit)
end

-- the drain: due DRAIN after the last health change, one driver (no timer made per hit)
function FX.Drain()
	if not (On("chunk") and (Rec() or FrameRec())) then
		return
	end
	FX.drainAt = GetTime() + FX.DRAIN
	Perf.SetScript(FX.driver, "OnUpdate", FX.OnUpdate)
end

function FX.OnUpdate(self)
	if FX.drainAt and GetTime() >= FX.drainAt then
		FX.drainAt = nil
		FX.Ghost(Rec(), true)
		FX.Ghost(FrameRec(), true)
	end
	if not FX.drainAt then
		self:SetScript("OnUpdate", nil)
	end
end

-- a dodge, parry or miss: the word off the plate's side
function FX.Word(action)
	local r = Rec()
	if not (r and On("evade")) then
		return
	end
	local w = r.words[r.nextWord]
	r.nextWord = r.nextWord % #r.words + 1
	local text = _G[FX.WORDS[action] or ""]
	if type(text) ~= "string" or Secret(text) or text == "" then
		text = FX.WORD_FALLBACK[action] or action
	end
	w.text:SetText(text)
	w.text:SetTextColor(Palette("text"))
	local a = Anim()
	w:ClearAllPoints()
	w:SetPoint("LEFT", r.top, "RIGHT", 6, 0)
	w:Show()
	if a and a.Slide then
		a:Slide(w, "LEFT", r.top, "RIGHT", 6, 0, 22, 10, FX.WORD, "outCubic")
	end
	Fade(w, 1, 0, FX.WORD, HideFrame)
end

-- the killing blow: the bar flashes out where the plate stood (a frame of
-- UIParent's, anchored to the bar: it outlives the plate a moment); (1.2.0) the target frame's bar too, its own
function FX.Kill()
	if FX.dead or not On("kill") then
		return
	end
	FX.dead = true
	local uf, bar = FX.uf, nil
	if uf then
		local bars = uf.HealthBarsContainer
		bar = type(bars) == "table" and bars.healthBar or nil
	end
	local fr = FrameRec()
	if fr then
		local _, fbar = FX.TargetFrame()
		if fbar then
			FX.KillOn(fbar, "killFrameTF")
		end
		FX.Calm(fr)
	end
	if not bar then
		return
	end
	FX.KillOn(bar, "killFrame")
	local r = Rec()
	if r then
		FX.Calm(r)
	end
end

-- a bar's kill flash on its own frame of ours (`slot`: which one, made at its first need)
function FX.KillOn(bar, slot)
	local k = FX[slot]
	if not k then
		k = CreateFrame("Frame", nil, UIParent)
		k:SetFrameStrata("MEDIUM")
		k.tex = k:CreateTexture(nil, "OVERLAY")
		k.tex:SetAllPoints(k)
		k.tex:SetTexture(FX.WHITE)
		k.tex:SetBlendMode("ADD")
		local Shade = MelloUI.Shade
		k.band = Shade and Shade:Band(k, { colour = "text", feather = 12, layer = "BACKGROUND", pixel = true })
		if k.band then
			k.band:Anchor(k, 8, 8)
			k.band:SetStrength(1)
			k.band:SetShown(true)
		end
		k:Hide()
		FX[slot] = k
	end
	k:ClearAllPoints()
	if not pcall(k.SetAllPoints, k, bar) then
		return
	end
	local okS, strata = pcall(bar.GetFrameStrata, bar)
	if okS and type(strata) == "string" and not Secret(strata) then
		k:SetFrameStrata(strata)
	end
	k.tex:SetVertexColor(Palette("text"))
	k:Show()
	Fade(k, 1, 0, FX.KILL, HideFrame)
end

-- the cast bar's glow: up towards the cast's end, down when it stops
function FX.CastNow()
	local r = Rec()
	if not (r and r.castGlow) then
		return
	end
	if not On("cast") then
		r.castGlow:SetAlpha(0)
		return
	end
	local ok, name, _, _, startMS, endMS = pcall(UnitCastingInfo, "target")
	if not ok or not name then
		ok, name, _, _, startMS, endMS = pcall(UnitChannelInfo, "target")
	end
	if not ok or not name then
		Fade(r.castGlow, nil, 0, 0.15)
		return
	end
	local span = FX.CAST_RAMP
	if not (Secret(startMS) or Secret(endMS)) and type(startMS) == "number" and type(endMS) == "number" and endMS > startMS then
		span = math.max(0.3, (endMS - GetTime() * 1000) / 1000)
	end
	Fade(r.castGlow, 0.12, 1, span * 0.9)
end

function FX.CastEnd(interrupted)
	local r = Rec()
	if not (r and r.castGlow) then
		return
	end
	local a = Anim()
	if a then
		a:Stop(r.castGlow, "alpha")
	end
	if not (interrupted and On("cast")) then
		Fade(r.castGlow, nil, 0, 0.15)
		return
	end
	r.castGlow:SetAlpha(0)
	-- the shards: from the bar's middle out, fading (Reduce Motion: in place)
	local lr, lg, lb = Palette("selectedTrim")
	for i, s in ipairs(r.shards) do
		local d = FX.SHARD[i]
		s.tex:SetVertexColor(lr, lg, lb)
		s:ClearAllPoints()
		s:SetPoint("CENTER", r.cast, "CENTER", d[1], 0)
		s:Show()
		if a and a.Slide and Motion() then
			a:Slide(s, "CENTER", r.cast, "CENTER", d[1], 0, d[2], d[3], FX.SHARDS, "outCubic")
		end
		Fade(s, 1, 0, FX.SHARDS, HideFrame)
	end
end

--------------------------------------------------------------------------------
-- Events: the target's only
--------------------------------------------------------------------------------

local UNIT_EVENTS = { "UNIT_COMBAT", "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
	"UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_START",
	"UNIT_SPELLCAST_CHANNEL_STOP" }

function FX.OnEvent(_, event, unit, a1, a2, a3)
	if event == "PLAYER_TARGET_CHANGED" then
		FX.Attach()
		FX.AttachFrame()
		return
	end
	if event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
		-- the target's plate came or went (seen, or out of sight)
		local okT, isTarget = pcall(UnitIsUnit, unit, "target")
		if okT and not Secret(isTarget) and isTarget then
			if event == "NAME_PLATE_UNIT_REMOVED" then
				local okD, dead = pcall(UnitIsDead, "target")
				if okD and dead == true then
					FX.Kill()
				end
				FX.Calm(Rec())
				FX.uf = nil
			else
				FX.Attach()
			end
		end
		return
	end
	if not (FX.uf or FX.frame) then
		return
	end
	if event == "UNIT_COMBAT" then
		local action, flag, amount = a1, a2, a3
		if Secret(action) or type(action) ~= "string" then
			return
		end
		if action == "WOUND" then
			local hit = not Secret(amount) and type(amount) == "number" and amount > 0
			if hit then
				FX.Hit(not Secret(flag) and flag == "CRITICAL")
			end
		elseif FX.WORDS[action] then
			FX.Word(action)
		end
	elseif event == "UNIT_HEALTH" then
		FX.Drain()
		local okD, dead = pcall(UnitIsDead, "target")
		if okD and dead == true then
			FX.Kill()
		end
	elseif event == "UNIT_MAXHEALTH" then
		FX.Ghost(Rec(), false)
		FX.Ghost(FrameRec(), false)
	elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
		FX.CastNow()
	elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
		FX.CastEnd(true)
	else
		FX.CastEnd(false)
	end
end

function M:OnInit(db)
	self.db = db
end

function M:OnEnable(db)
	self.db = db
	local f = FX.driver
	if not f then
		f = CreateFrame("Frame")
		Perf.SetScript(f, "OnEvent", FX.OnEvent)
		FX.driver = f
	end
	f:RegisterEvent("PLAYER_TARGET_CHANGED")
	f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	f:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
	for _, event in ipairs(UNIT_EVENTS) do
		pcall(f.RegisterUnitEvent, f, event, "target")
	end
	FX.Attach()
	FX.AttachFrame()
end

function M:OnDisable()
	local f = FX.driver
	if f then
		f:UnregisterAllEvents()
		f:SetScript("OnUpdate", nil)
	end
	FX.Calm(Rec())
	FX.Calm(FrameRec())
	FX.uf, FX.frame, FX.drainAt = nil, nil, nil
end

function M:OnSettingChanged(key, _, db)
	self.db = db
	if key == "targetFrame" then
		FX.AttachFrame()
		return
	end
	local fr = FrameRec()
	if fr and key == "chunk" then
		fr.clip:SetShown(On("chunk"))
		FX.Ghost(fr, false)
	end
	local r = Rec()
	if not r then
		return
	end
	if key == "chunk" then
		r.clip:SetShown(On("chunk"))
		FX.Ghost(r, false)
	elseif key == "cast" then
		FX.CastNow()
	end
end

-- (the configurator's Play and the tests: the effects on the target's plate now)
M.FX = FX

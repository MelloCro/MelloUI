--------------------------------------------------------------------------------
-- MelloUI - Cast bars: a game cast bar held see-through, and the target's cast bar detached
-- (2.1.95; the user, 2026-11-28: "an option to detach the target cast bar and move it freely";
-- docs/plans/target-tot-castbar.md)
--
-- MelloUI.CastHold: a game cast bar held see-through while one of MelloUI's stands for it -- its alpha 0, and the
-- game's own writes of it answered: ApplyAlpha(1) as each cast starts (once a cast, a post-hook), and its fades, which
-- animate its own alpha over the alpha set (HoldFadeOutAnim after an interrupt, FadeOutAnim after a cast: stopped as
-- they play, once a cast's end). Each answer counted (Perf.WriteBack). Never Show / Hide or a key of the game's; its 1
-- given back when let go. One system: the Personal Display's hold of the player's bar (since 2.1.0, its Hide The
-- Game's Cast Bar) and the target's below.
--
-- MelloUI.TargetCast: Unit Frames' Detach Cast Bar. The game's target cast bar (TargetFrame.spellbar) is laid by the
-- game's own code (TargetSpellBarMixin:AdjustPosition: on its show, the target changing, the aura updates -- under the
-- aura row, whose forbidden aspects it then carries), so it cannot be moved without undoing the game's write again and
-- again. The bar that moves is ours, MelloUITargetCastBar: built as the game's is (SmallCastingBarFrameTemplate's
-- parts, the same atlases under the same keys, 150 x 10, the text box under it), an Edit Layout element of its own
-- ("Target Cast Bar"), driven on the target's cast events. Its fill is played by the engine from the cast's own
-- duration (UnitCastingDuration / UnitChannelDuration, secret where casts are: handed to SetTimerDuration, never
-- read); the name and icon handed over as they are; the "can't be interrupted" fill shown by the cast's own flag
-- (SetAlphaFromBoolean: secret or not, never compared); the end as the game's (a cast done: the full fill and its
-- flash, then the fade; interrupted or failed: the red fill and its word, held a moment). The game's bar held
-- see-through meanwhile. Built the first time the row is on; nothing at all while it is off.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Secret = MelloUI.Safe.IsSecret

--------------------------------------------------------------------------------
-- MelloUI.CastHold
--------------------------------------------------------------------------------

local CastHold = { bars = {}, fadeOf = setmetatable({}, { __mode = "k" }), FADES = { "HoldFadeOutAnim", "FadeOutAnim" } }
MelloUI.CastHold = CastHold

function CastHold.OnAlpha(bar, alpha)
	local s = CastHold.bars[bar]
	if not (s and s.held) or s.writing or (not Secret(alpha) and alpha == 0) then
		return
	end
	s.writing = true
	bar:SetAlpha(0)
	s.writing = false
	MelloUI.Perf.WriteBack(s.label)
end

function CastHold.OnFade(anim)
	local bar = CastHold.fadeOf[anim]
	local s = bar and CastHold.bars[bar]
	if s and s.held then
		anim:Stop()
		MelloUI.Perf.WriteBack(s.label .. " fade")
	end
end

-- the bar's own fades (its animation groups, read raw)
function CastHold.Fades(bar)
	local out = {}
	for _, key in ipairs(CastHold.FADES) do
		local anim = rawget(bar, key)
		if type(anim) == "table" and type(anim.Play) == "function" then
			out[#out + 1] = anim
		end
	end
	return out
end

-- held (on) or let go. `label`: its write-backs' name; `casting()`: true while its unit still casts -- let go with no
-- cast while it still stands from the last one's end (its fade held off), it is left see-through, so no old bar comes
-- back: the game's next cast gives it its 1, as each start does
function CastHold.Hold(bar, on, label, casting)
	if type(bar) ~= "table" or type(bar.SetAlpha) ~= "function" then
		return
	end
	on = on and true or false
	local s = CastHold.bars[bar]
	if not s then
		if not on then
			return
		end
		s = { held = false, hooked = false, writing = false }
		CastHold.bars[bar] = s
	end
	s.label = label or s.label or "the game's cast bar"
	if on == s.held then
		return
	end
	s.held = on
	if on and not s.hooked then
		s.hooked = true
		hooksecurefunc(bar, "SetAlpha", CastHold.OnAlpha)
		for _, anim in ipairs(CastHold.Fades(bar)) do
			CastHold.fadeOf[anim] = bar
			hooksecurefunc(anim, "Play", CastHold.OnFade)
		end
	end
	if on then
		-- (one running as it comes on: an interrupt's hold, stopped)
		for _, anim in ipairs(CastHold.Fades(bar)) do
			if anim:IsPlaying() then
				anim:Stop()
			end
		end
	elseif bar:IsShown() and not (casting and casting()) and not rawget(bar, "isInEditMode") then
		return
	end
	s.writing = true
	bar:SetAlpha(on and 0 or 1)
	s.writing = false
end

--------------------------------------------------------------------------------
-- MelloUI.TargetCast: the target's cast bar, detached
--------------------------------------------------------------------------------

local TC = { on = false, bar = nil, casting = false, UNIT = "target", KEY = "MelloUITargetCastBar",
	LABEL = "Target Cast Bar", W = 150, H = 10, HOLD = 1, FADE = 0.3,
	HOLD_LABEL = "Unit Frames: the game's target cast bar" }
MelloUI.TargetCast = TC

-- SmallCastingBarFrameTemplate's pictures (CastingBarFrame.xml) and CastingBarMixin's fills by kind
TC.ART = { background = "ui-castingbar-background", textbox = "ui-castingbar-textbox", border = "ui-castingbar-frame",
	shield = "ui-castingbar-shield", spark = "ui-castingbar-pip", flash = "ui-castingbar-full-glow-standard",
	cast = "ui-castingbar-filling-standard", castFull = "ui-castingbar-full-standard",
	channel = "ui-castingbar-filling-channel", channelFull = "ui-castingbar-full-channel",
	locked = "ui-castingbar-uninterruptable", cut = "ui-castingbar-interrupted" }
-- the events the game's own bar listens to for its unit (CastingBarMixin:SetUnit), the empowered ones left out (no
-- empowered spells on this client's classes)
TC.EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
	"UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" }

local function Region(bar, layer, sub, atlas)
	local t = bar:CreateTexture(nil, layer, nil, sub)
	if atlas then
		t:SetAtlas(atlas)
	end
	return t
end

-- its fill's picture for its kind (CastingBarMixin:UpdateBarFillTexture's: the game's method name, so a dresser's
-- post-hook of it runs as on the game's bar -- Bar Textures' colours)
function TC.UpdateBarFillTexture(bar, full)
	local kind = bar.fillKind or "cast"
	bar:SetStatusBarTexture(TC.ART[kind .. (full and "Full" or "")] or TC.ART[kind])
	bar:SetStatusBarColor(1, 1, 1)
end

-- a bar's fill kind, named as CastingBarMixin names it (CastingBarType: Bar Textures' colours read it)
TC.TYPES = { cast = "Standard", channel = "Channel", cut = "Interrupted" }
function TC.Fill(bar, kind, full)
	local types = rawget(_G, "CastingBarType")
	bar.fillKind = kind
	bar.barType = type(types) == "table" and types[TC.TYPES[kind] or "Standard"] or nil
	bar:UpdateBarFillTexture(full)
end

function TC.Build()
	if TC.bar then
		return TC.bar
	end
	local bar = CreateFrame("StatusBar", TC.KEY, UIParent)
	bar:SetSize(TC.W, TC.H)
	bar:SetFrameStrata("MEDIUM")
	bar:Hide()
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	bar:SetStatusBarTexture(TC.ART.cast)
	-- the game's own parts, the same keys, the same places (SmallCastingBarFrameTemplate)
	bar.TextBorder = Region(bar, "BACKGROUND", 0, TC.ART.textbox)
	bar.TextBorder:SetPoint("TOPLEFT", 0, 0)
	bar.TextBorder:SetPoint("BOTTOMRIGHT", 0, -12)
	bar.Background = Region(bar, "BACKGROUND", 0, TC.ART.background)
	bar.Background:SetAllPoints()
	bar.BorderShield = Region(bar, "BACKGROUND", 0, TC.ART.shield)   -- (the target's: never shown, as the game's)
	bar.BorderShield:SetSize(29, 33)
	bar.BorderShield:SetPoint("TOPLEFT", -27, 4)
	bar.BorderShield:Hide()
	bar.Icon = Region(bar, "ARTWORK", 1)
	bar.Icon:SetSize(20, 20)
	bar.Icon:SetPoint("RIGHT", bar, "LEFT", -2, -5)   -- (the spell's icon, as the game's: CastingBarMixin's showIcon)
	-- "can't be interrupted": the game's red-grey fill over ours, its alpha the cast's own flag, its fill played as ours
	local locked = CreateFrame("StatusBar", nil, bar)
	locked:SetAllPoints()
	locked:SetMinMaxValues(0, 1)
	locked:SetValue(0)
	locked:SetStatusBarTexture(TC.ART.locked)
	locked:SetAlpha(0)
	bar.Uninterruptible = locked
	-- the frame, the spark, the flash and the name above both fills
	local top = CreateFrame("Frame", nil, bar)
	top:SetAllPoints()
	top:SetFrameLevel(locked:GetFrameLevel() + 1)
	bar.Top = top
	bar.Border = Region(top, "OVERLAY", 0, TC.ART.border)
	bar.Border:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 2)
	bar.Border:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -2)
	bar.Spark = Region(top, "OVERLAY", 1, TC.ART.spark)
	bar.Spark:SetSize(6, 16)
	bar.Spark:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT", 0, 0)   -- (at the fill's edge, as it plays)
	bar.Flash = Region(top, "OVERLAY", 2, TC.ART.flash)
	bar.Flash:SetBlendMode("ADD")
	bar.Flash:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
	bar.Flash:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)
	bar.Flash:SetAlpha(0)
	bar.Text = top:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
	bar.Text:SetHeight(16)
	bar.Text:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, -8)
	bar.Text:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, -8)
	bar.unit = TC.UNIT
	bar.UpdateBarFillTexture = TC.UpdateBarFillTexture
	local types = rawget(_G, "CastingBarMixin")
	if type(types) == "table" and type(types.GetTypeInfo) == "function" then
		bar.GetTypeInfo = types.GetTypeInfo   -- (the game's table of fills by kind, read only: Bar Textures' colours)
	end
	bar:SetScript("OnEvent", TC.OnEvent)
	TC.bar = bar
	MelloUI:RegisterMover(bar, bar, { key = TC.KEY, label = TC.LABEL, group = "hud", category = "frames",
		page = "UnitFrames", placeholder = true, default = TC.Home, reset = TC.Home,
		when = function() return TC.on end })
	MelloUI:Fire("targetcast", true)   -- (the dressers of cast bars dress ours: Dark Mode, Bar Textures, Oldschool)
	return bar
end

-- its standard place: where the game lays its bar under the target frame with no aura row under it
-- (TargetSpellBarMixin:AdjustPosition: TOPLEFT to the frame's BOTTOMLEFT, 43, 5)
function TC.Home()
	local bar, frame = TC.bar, rawget(_G, "TargetFrame")
	if not bar then
		return false
	end
	bar:ClearAllPoints()
	bar:SetScale(1)
	if not (type(frame) == "table" and pcall(bar.SetPoint, bar, "TOPLEFT", frame, "BOTTOMLEFT", 43, 5)) then
		bar:ClearAllPoints()
		MelloUI:PlayPoint(bar, "TOP", "CENTER", 0, -150)
	end
	return true
end

-- a cast (UnitCastingInfo) or a channel (UnitChannelInfo) of the target's going on now (its name read, plain or
-- secret)
function TC.Going(info)
	local ok, name = pcall(info, TC.UNIT)
	return ok and (Secret(name) or type(name) == "string") or false
end

function TC.Casting()
	return TC.Going(UnitCastingInfo) or TC.Going(UnitChannelInfo)
end

function TC.Gone()
	local bar = TC.bar
	if bar then
		bar:SetScript("OnUpdate", nil)
		bar:Hide()
		bar:SetAlpha(1)
	end
end

-- a cut cast's word held for TC.HOLD seconds (the game's HoldFadeOutAnim), Reduce Motion or not -- a word to read, no
-- motion: the bar's own count, run only while it holds
function TC.Tick(bar, elapsed)
	TC.left = (TC.left or 0) - (elapsed or 0)
	if TC.left <= 0 then
		bar:SetScript("OnUpdate", nil)
		TC.FadeOut()
	end
end

-- the end: `kind` "done" (the full fill, its flash, the fade) or "cut" (the red fill and its word, held, then the fade);
-- nil: away now (no cast to show)
function TC.End(kind, word)
	local bar = TC.bar
	TC.casting = false
	if not bar then
		return
	end
	MelloUI.Anim:Stop(bar, "alpha")
	if not kind or not bar:IsShown() then
		TC.Gone()
		return
	end
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	bar.Uninterruptible:SetMinMaxValues(0, 1)
	bar.Uninterruptible:SetValue(1)
	if kind == "cut" then
		bar.Uninterruptible:SetAlpha(0)
		TC.Fill(bar, "cut", true)
		bar.Text:SetText(word or "")
		bar.Spark:Hide()
		TC.left = TC.HOLD
		bar:SetScript("OnUpdate", TC.Tick)
	else
		bar.Flash:SetAlpha(1)
		bar.Spark:Hide()
		TC.FadeOut()
	end
end

function TC.FadeOut()
	if TC.bar and not TC.casting then
		MelloUI.Anim:To(TC.bar, "alpha", 0, TC.FADE, "inQuad", TC.Gone)
	end
end

-- the cast's flag for "can't be interrupted" on the locked fill (secret or not, never compared)
function TC.Locked(flag)
	local locked = TC.bar and TC.bar.Uninterruptible
	if not locked then
		return
	end
	if Secret(flag) and type(locked.SetAlphaFromBoolean) == "function" then
		pcall(locked.SetAlphaFromBoolean, locked, flag, 1, 0)
	elseif Secret(flag) then
		locked:SetAlpha(0)
	else
		locked:SetAlpha(flag and 1 or 0)
	end
end

-- its fill played from the cast's own duration (the engine counts it; a channel runs down)
function TC.Play(channel)
	local bar = TC.bar
	local get = channel and rawget(_G, "UnitChannelDuration") or rawget(_G, "UnitCastingDuration")
	local ok, duration = false, nil
	if type(get) == "function" then
		ok, duration = pcall(get, TC.UNIT)
	end
	local Dir = Enum and Enum.StatusBarTimerDirection
	local Lerp = Enum and Enum.StatusBarInterpolation
	if ok and duration ~= nil and type(bar.SetTimerDuration) == "function" and Dir and Lerp then
		local dir = channel and Dir.RemainingTime or Dir.ElapsedTime
		local played = pcall(bar.SetTimerDuration, bar, duration, Lerp.Immediate, dir)
		pcall(bar.Uninterruptible.SetTimerDuration, bar.Uninterruptible, duration, Lerp.Immediate, dir)
		if played then
			return
		end
	end
	-- (no duration to play: the bar full, as the Personal Display's with times it cannot read)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	bar.Uninterruptible:SetMinMaxValues(0, 1)
	bar.Uninterruptible:SetValue(1)
end

-- a cast (or a channel) of the target's shown from what the client tells now
function TC.Start(channel)
	local bar = TC.bar
	local info = channel and UnitChannelInfo or UnitCastingInfo
	local ok, name, _, texture, _, _, a7, _, a9 = pcall(info, TC.UNIT)
	if not ok or not (Secret(name) or type(name) == "string") then
		TC.End()
		return
	end
	-- (notInterruptible: the channel's 7th value, the cast's 9th -- UnitDocumentation)
	local locked = channel and a7 or a9
	MelloUI.Anim:Stop(bar, "alpha")
	bar:SetScript("OnUpdate", nil)   -- (a cut word still held: the new cast stands)
	TC.casting = true
	bar:SetAlpha(1)
	bar.Flash:SetAlpha(0)
	bar.Spark:Show()
	TC.Fill(bar, channel and "channel" or "cast", false)
	bar.Text:SetText(name)
	-- (2.1.95; the user: "the target castbar does not show the cast spell icon") the spell's icon, handed over as it is
	-- (secret or not, never read)
	bar.Icon:SetShown(texture ~= nil and pcall(bar.Icon.SetTexture, bar.Icon, texture) and true or false)
	TC.Locked(locked)
	TC.Play(channel)
	bar:Show()
end

function TC.OnEvent(_, event)
	if event == "PLAYER_TARGET_CHANGED" then
		MelloUI.Anim:Stop(TC.bar, "alpha")
		TC.Gone()
		TC.Refresh()
	elseif event == "UNIT_SPELLCAST_START" then
		TC.Start(false)
	elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
		TC.Start(true)
	elseif event == "UNIT_SPELLCAST_DELAYED" then
		TC.Play(false)
	elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
		TC.Play(true)
	elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
		TC.Locked(false)
	elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
		TC.Locked(true)
	elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
		TC.End("cut", rawget(_G, "INTERRUPTED") or "Interrupted")
	elseif event == "UNIT_SPELLCAST_FAILED" then
		-- (a failed cast that was never shown -- a spell the target could not start -- stays unseen, as the game's)
		if TC.casting then
			TC.End("cut", rawget(_G, "FAILED") or "Failed")
		end
	elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		-- (a stop heard as a new cast already goes: that one stands)
		if TC.casting and not TC.Casting() then
			TC.End("done")
		end
	end
end

-- what the target casts now: shown, or nothing
function TC.Refresh()
	if not (TC.on and TC.bar) then
		return
	end
	if TC.Going(UnitChannelInfo) then
		TC.Start(true)
	elseif TC.Going(UnitCastingInfo) then
		TC.Start(false)
	else
		TC.End()
	end
end

-- on (the row on with Unit Frames on) or off: ours built and listening, the game's held see-through; off: ours away,
-- the game's given back
function TC.Set(on)
	on = on and true or false
	if on == TC.on then
		return
	end
	TC.on = on
	local game = rawget(_G, "TargetFrame")
	game = type(game) == "table" and rawget(game, "spellbar") or nil
	if on then
		local bar = TC.Build()
		for _, e in ipairs(TC.EVENTS) do
			bar:RegisterUnitEvent(e, TC.UNIT)
		end
		bar:RegisterEvent("PLAYER_TARGET_CHANGED")
		CastHold.Hold(game, true, TC.HOLD_LABEL, TC.Casting)
		TC.Refresh()
	else
		local bar = TC.bar
		if bar then
			bar:UnregisterAllEvents()
			MelloUI.Anim:Stop(bar, "alpha")
			TC.Gone()
		end
		CastHold.Hold(game, false, TC.HOLD_LABEL, TC.Casting)
	end
	MelloUI:Fire("targetcast", on)
end

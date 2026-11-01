--------------------------------------------------------------------------------
-- MelloUI - Unit Frames: the target frame and its target of target, MelloUI's own (fr-17 stage 2, 2026-11-01; the
-- user: "Add target of target in there aswell")
--
-- While Unit Frames is on, the target frame on the screen is ours (MelloUITargetFrame) and so is its target of target
-- (MelloUITargetFrameToT): secure unit buttons (a click targets the unit; a right click on the target opens its menu
-- -- the target of target has none, as the game's), built as the game's own are built -- TargetFrame.xml and Camelot's
-- TargetFrame.lua of this client (1.60.1.70425): the same parts under the same keys (TargetFrameContainer.Portrait,
-- TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar, totFrame.HealthBar ...), the same sizes,
-- places, layers and the game's own pictures -- so every dresser of MelloUI's dresses them as it dressed the game's,
-- through MelloUI.Units (Modules/UnitFramesOwn.lua). The same methods too (Update, CheckLevel, CheckFaction,
-- CheckClassification, CheckDead, CheckPartyLeader, UpdateRaidTargetIcon): a dresser's post-hook of one runs as ours
-- does it. Its bars are our own StatusBars handed the unit's health and power as the game hands them (a secret value
-- goes to the bar as it is, never read or compared).
-- This client's builds lay these frames differently (its Camelot TargetFrame.lua moved the name, the type band, the
-- mana bar, the PvP badge and the target of target's bars between builds of 1.60.1.70425), so ours follow the build
-- that runs, two ways: (1) at the build, the game frame's own live layout copied onto ours -- each part's anchors (onto
-- our twins), size, draw layer, scale, texel snapping and justification (Mirror), and a part the build has not is none
-- of ours; (2) on each target, the game's own code of its frame run on OURS -- TargetFrameMixin's CheckClassification
-- (its health bar box and mask per classification, its pictures), CheckLevel, CheckFaction, CheckDead ... (Game) --
-- never on the game's frame; where that code refuses (a secret value it compares), our own secret-safe version.
--
-- They stand ON the game's frames: the target of ours a child of the game's TargetFrame over its rect, the target of
-- target of ours a child of the game's TargetFrameToT over its rect. So they show and hide exactly as the game's do --
-- the game's own secure code shows its target frame with the unit (PLAYER_TARGET_CHANGED, kept with it) and its
-- target of target every frame by its own rule (the CVar, a unit, not you, alive) -- in a fight too, and they take the
-- game frame's place, size and alpha (Edit Mode 3:2, Edit Layout, the installer, the Fader). Nobody's frame moves.
-- What is ours updates on the unit's events only, never per frame: the target on its own unit events; the target of
-- target on the target's UNIT_TARGET, the target changing, and the events of whichever unit it is (the client fires
-- none for "targettarget": a unit event is ours when UnitIsUnit(unit, "targettarget")), listened to while it shows.
--
-- The game's frames kept away while ours stand in (Units.Fade / Quiet / Silence, the player frame's means): its art
-- holder (TargetFrameContainer) and content holder's main part at alpha 0, the contextual part's pictures and frames
-- at alpha 0 -- all but its aura row, which stays the game's (MelloUI's Buffs & Debuffs veils it and lays its own rows
-- there; off, the game's row shows as before) and keeps laying the cast bar (TargetFrameSpellBar, the game's) where the
-- game lays it. The target of target's every picture and frame at alpha 0. Out of a fight their mouse off and Edit
-- Mode's box unseen and click-through. The events of the game's own updates let go but four the game's frame keeps:
-- the world entered and the target changing (its show and hide, its sounds, its aura row), UNIT_FACTION and
-- UNIT_TARGET (its aura row's layout). No key written on them or their regions, no hook on them, nothing of theirs
-- shown, hidden or moved. The combo points (Camelot's ComboFrame on the target), the cast bar and the alternate power
-- bar are frames of their own jobs and stay the game's.
--
-- Stage 3: the focus frame and its focus target, the same way -- the game's FocusFrame is the target's template
-- (TargetFrame.xml: TargetFrameTemplate under FocusFrameMixin), so it is the same build of ours with the focus's unit,
-- names and events (KINDS below: one system, two frames). Its own: the focus changing (PLAYER_FOCUS_CHANGED) and the
-- group's change (GROUP_ROSTER_UPDATE: the game's frame clears a focus gone) stay with the game's frame, which shows
-- and hides itself with the focus; so do the two events its size switches (UNIT_CLASSIFICATION_CHANGED,
-- PLAYER_FLAGS_CHANGED: the game's own SetSmallSize lets them go for the small frame and takes them again for the large
-- one -- let go by ours, a small frame given back held them again: its leader crown back). Edit Mode's small focus
-- frame (FocusFrameMixin:SetSmallSize -- the frame and its focus target scaled, which ours follow as their children; the
-- health text's larger font, the threat box's place, the leader and PvP pictures off) read from the game's frame as
-- ours updates, never hooked.
--
-- Units.T / Units.F (one kind each): Start(login) / Stop() with the Unit Frames module (Modules/UnitFrames.lua), as the
-- player frame's P.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local U = MelloUI.Units
if not U then
	return
end
local Perf = MelloUI.Perf:Scope("UnitFrames (own target)")
local Shared = Perf.Shared
local Secret = MelloUI.Safe.IsSecret
local Num = MelloUI.Safe.Number
local Text = MelloUI.Safe.Text
local K = U.Parts
local Atlas, Tex, Crisp, Font, Holder = K.Atlas, K.Tex, K.Crisp, K.Font, K.Holder
local FillOf, Masked, Bar, TextsOn, Ask, Yes, Later = K.FillOf, K.Masked, K.Bar, K.TextsOn, K.Ask, K.Yes, K.Later

-- the frames of the target's template (TargetFrame.xml), each with its target of target: the target (stage 2) and the
-- focus (stage 3). `change` the event the game's frame shows and hides itself on (kept with it); `keep` the game
-- frame's own events it keeps besides (the focus's group change: the game's frame clears a focus gone; the two its
-- SetSmallSize lets go and takes again)
local KINDS = {
	{ key = "target", unit = "target", totUnit = "targettarget", game = "TargetFrame", gameToT = "TargetFrameToT",
	  name = "MelloUITargetFrame", change = "PLAYER_TARGET_CHANGED", owner = "target frame", totOwner = "target of target",
	  keep = {} },
	{ key = "focus", unit = "focus", totUnit = "focustarget", game = "FocusFrame", gameToT = "FocusFrameToT",
	  name = "MelloUIFocusFrame", change = "PLAYER_FOCUS_CHANGED", owner = "focus frame", totOwner = "focus target",
	  keep = { GROUP_ROSTER_UPDATE = true, UNIT_CLASSIFICATION_CHANGED = true, PLAYER_FLAGS_CHANGED = true } },
}
for _, kind in ipairs(KINDS) do
	kind.frame, kind.tot, kind.wanted, kind.standing, kind.usedGame = nil, nil, false, false, false
end
local T, F = KINDS[1], KINDS[2]
U.T, U.F = T, F
-- the methods ours carry (the game's names: a dresser's post-hook of one runs as ours does it), one set for each frame
local O = {}

local ART = {
	frame = "UI-HUD-UnitFrame-Target-PortraitOn",
	rare = "UI-HUD-UnitFrame-Target-Rare-PortraitOn",
	minus = "UI-HUD-UnitFrame-Target-MinusMob-PortraitOn",
	flash = "UI-HUD-UnitFrame-Target-PortraitOn-InCombat",
	minusFlash = "UI-HUD-UnitFrame-Target-MinusMob-PortraitOn-InCombat",
	boss = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold",
	type = "UI-HUD-UnitFrame-Target-PortraitOn-Type",
	health = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health",
	minusHealth = "UI-HUD-UnitFrame-Target-MinusMob-PortraitOn-Bar-Health",
	healthMask = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health-Mask",
	minusHealthMask = "UI-HUD-UnitFrame-Target-MinusMob-PortraitOn-Bar-Health-Mask",
	mana = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Mana",
	manaMask = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Mana-Mask",
	circle = "UI-HUD-UnitFrame-SmallCircle",
	pvp = "UI-HUD-UnitFrame-SmallCircle-Alliance",
	skull = "UI-HUD-UnitFrame-Target-HighLevelTarget_Icon",
	leader = "UI-HUD-UnitFrame-Player-Group-LeaderIcon",
	guide = "UI-HUD-UnitFrame-Player-Group-GuideIcon",
	raidIcons = "Interface\\TargetingFrame\\UI-RaidTargetingIcons",   -- (TargetFrame.xml's own: the game's raid target icons)
	star = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star",
	quest = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Quest",
	petBadge = "Interface\\TargetingFrame\\PetBadge-Beast",   -- (TargetFrame.xml's own: the game's battle pet badge)
	circleMask = "CircleMask",
	threatBg = "Interface\\TargetingFrame\\UI-StatusBar",   -- (TargetFrame.xml's own: the game's numeric threat box)
	threatBorder = "Interface\\TargetingFrame\\NumericThreatBorder",   -- (TargetFrame.xml's own: the game's numeric threat box)
	tot = "UI-HUD-UnitFrame-TargetofTarget-PortraitOn",
	totHealth = "UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Bar-Health",
	totMana = "UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Bar-Mana",
	totHealthMask = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health-Mask",
	totManaMask = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Mana-Mask",
	debuffBorder = "Interface\\Buttons\\UI-Debuff-Overlays",   -- (TargetFrame.xml's own: the game's debuff border)
}
-- (TargetofTargetDebuffFrameTemplate's border cut and its four places)
local DEBUFF_COORDS = { 0.296875, 0.5703125, 0, 0.515625 }
local MAX_TOT_DEBUFFS = 4

local function Dead()
	return rawget(_G, "DEAD") or "Dead"
end

--------------------------------------------------------------------------------
-- The target frame of ours: TargetFrameTemplate's parts (TargetFrame.xml) as Camelot's TargetFrame.lua lays them
-- (the name 117 wide at the type band's right -133,-1; the level in its circle at the bottom right; the skull on it)
--------------------------------------------------------------------------------

-- a key path read on a game frame, never written (rawget all the way: nil where the client has no such part)
local function Path(t, ...)
	for i = 1, select("#", ...) do
		if type(t) ~= "table" then
			return nil
		end
		t = rawget(t, (select(i, ...)))
	end
	return t
end

-- The game frame's own layout as the client laid it -- the template and its game type's OnLoad overrides, whatever
-- the client's build (this client's Camelot TargetFrame.lua has changed between its builds: the name, the type band,
-- the mana bar, the PvP badge, the target of target's bars) -- copied onto ours, pair by pair: its anchors (onto the
-- twins of ours: Units.Parts.CopyPoints), its size, draw layer, scale and a text's justification. Read only, each
-- read guarded: a secret or refused answer keeps ours as made from the template. `pairs_`: { ours, game, how } --
-- `how` nil: all; "nosize": no size (a text sized by its words); "look": its texel snapping only (a bar's fill, laid by
-- its bar)
local function Snap(ours, game)
	if not (ours.SetTexelSnappingBias and game.GetTexelSnappingBias) then
		return
	end
	local okB, bias = pcall(game.GetTexelSnappingBias, game)
	if okB and Num(bias) then
		ours:SetTexelSnappingBias(bias)
	end
	local okG, grid = pcall(game.IsSnappingToPixelGrid, game)
	if okG and type(grid) == "boolean" and ours.SetSnapToPixelGrid then
		ours:SetSnapToPixelGrid(grid)
	end
end

local function Mirror(pairs_, map)
	for _, p in ipairs(pairs_) do
		local ours, game, how = p[1], p[2], p[3]
		if ours and type(game) == "table" and how == "look" then
			Snap(ours, game)
		elseif ours and type(game) == "table" then
			Snap(ours, game)
			if how ~= "nosize" then
				local okS, w, h = pcall(game.GetSize, game)
				if okS and Num(w) and Num(h) and w > 0 and h > 0 then
					pcall(ours.SetSize, ours, w, h)
				end
			end
			K.CopyPoints(ours, game, map, function() end)
			local kind = ours.GetObjectType and ours:GetObjectType()
			if ours.SetDrawLayer and game.GetDrawLayer and (kind == "Texture" or kind == "FontString"
				or kind == "MaskTexture") then
				local okL, layer, sub = pcall(game.GetDrawLayer, game)
				if okL and type(layer) == "string" and not Secret(layer) and Num(sub) then
					pcall(ours.SetDrawLayer, ours, layer, sub)
				end
			end
			local okC, scale = pcall(game.GetScale, game)
			if okC and Num(scale) and scale > 0 then
				pcall(ours.SetScale, ours, scale)
			end
			if ours.SetJustifyH and game.GetJustifyH then
				local okH, jh = pcall(game.GetJustifyH, game)
				if okH and type(jh) == "string" and not Secret(jh) then
					ours:SetJustifyH(jh)
				end
				local okV, jv = pcall(game.GetJustifyV, game)
				if okV and type(jv) == "string" and not Secret(jv) then
					ours:SetJustifyV(jv)
				end
			end
		end
	end
end

-- The game's own code of a frame -- TargetFrameMixin's / TargetOfTargetMixin's method `name` -- run on OURS (its
-- keys are the game's): what the client's build does, done to our parts, nothing of the game's touched. A refused
-- run (a secret value its code compares) falls back to ours: `fallback(f)`.
local function Game(mixin, name, f, fallback)
	local m = rawget(_G, mixin)
	local fn = type(m) == "table" and rawget(m, name)
	if type(fn) ~= "function" or not pcall(fn, f) then
		fallback(f)
	end
end

-- TextStatusBar's own rule for its bar: shown while its most is above none and its updates go on, else hidden (a
-- creature without power shows no mana bar); a secret most counts as above none
local function BarShown(bar, max)
	local plain = Num(max)
	local on = not bar.pauseUpdates and (plain == nil or plain > 0)
	if on and not bar:IsShown() then
		bar:Show()
	elseif not on and not bar.alwaysShow and bar:IsShown() then
		bar:Hide()
	end
end

local function FontLike(fs, game, object)
	local okF, font = pcall(function() return game and game:GetFontObject() end)
	if okF and font then
		fs:SetFontObject(font)
	elseif rawget(_G, object) then
		fs:SetFontObject(rawget(_G, object))
	end
end

local BuildToT   -- (below)
local function Build(kind)
	local game = rawget(_G, kind.game)
	if kind.frame or type(game) ~= "table" or InCombatLockdown() then
		return kind.frame
	end
	local unit = kind.unit
	local f = CreateFrame("Button", kind.name, game, "SecureUnitButtonTemplate")
	U.mine[f] = true
	f:SetAllPoints(game)
	f:SetFrameLevel(game:GetFrameLevel())
	f:SetHitRectInsets(0, 5, 4, 9)
	f:SetAttribute("unit", unit)
	f:SetAttribute("*type1", "target")
	f:SetAttribute("*type2", "togglemenu")
	f:RegisterForClicks("AnyUp")
	f.unit, f.frameType, f.capNumeric, f.deadText, f.kind = unit, "Target", true, "", kind
	f.showLevel, f.showPVP, f.showLeader, f.showThreat, f.showPortrait, f.showClassification = true, true, true, true,
		true, true
	f:Hide()
	local gContent = rawget(game, "TargetFrameContent")
	local gMain = gContent and rawget(gContent, "TargetFrameContentMain")

	-- the art: the portrait in its round mask, the frame's picture, the threat flash, the elite / rare / boss picture
	local c = Holder(f)
	f.TargetFrameContainer = c
	local portrait = Tex(c, "BACKGROUND", 1)
	portrait:SetSize(58, 58)
	portrait:SetPoint("TOPRIGHT", c, "TOPRIGHT", -26, -19)
	c.Portrait = portrait
	local pmask = c:CreateMaskTexture(nil, "BACKGROUND", nil, 1)
	Atlas(pmask, ART.circleMask)
	pmask:SetPoint("TOPLEFT", portrait, "TOPLEFT", 0, -1)
	pmask:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", -1, 0)
	Masked(portrait, pmask)
	c.PortraitMask = pmask
	local art = Tex(c, "BACKGROUND", 2, ART.frame, true)
	art:SetPoint("CENTER", c, "CENTER", 0, 0)
	Crisp(art)
	c.FrameTexture = art
	local flash = Tex(c, "ARTWORK", 1, ART.flash, true)
	flash:SetPoint("CENTER", c, "CENTER", 0, 2)
	flash:Hide()
	Crisp(flash)
	c.Flash = flash
	local boss = Tex(c, "ARTWORK", 2, ART.boss, true)
	boss:SetPoint("TOPRIGHT", c, "TOPRIGHT", -11, -8)
	boss:Hide()
	c.BossPortraitFrameTexture = boss

	-- the content: the type band, the name, the level in its circle, the bars and their texts
	local content = Holder(f)
	f.TargetFrameContent = content
	local main = Holder(content)
	content.TargetFrameContentMain = main
	main.skipLevelAndNameTextLocalizationAdjustment = true
	local band = Tex(main, "BACKGROUND", 0, ART.type, true)
	band:SetPoint("TOPRIGHT", main, "TOPRIGHT", -75, -25)
	main.ReputationColor = band
	local name = Font(main, "OVERLAY", 0, "GameFontNormalSmall")
	FontLike(name, gMain and rawget(gMain, "Name"), "GameFontNormalSmall")
	name:SetSize(117, 12)
	name:SetJustifyH("LEFT")
	name:SetJustifyV("MIDDLE")
	name:SetPoint("TOPLEFT", band, "TOPRIGHT", -133, -1)
	main.Name = name
	f.name = name
	local circle = Tex(main, "OVERLAY", 0, ART.circle, true)
	circle:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -13, 7)
	main.LevelBackgroundCircle = circle
	local level = Font(main, "OVERLAY", 0, "WhiteLargeNumberFont")
	FontLike(level, gMain and rawget(gMain, "LevelText"), "WhiteLargeNumberFont")
	level:SetJustifyH("RIGHT")
	level:SetJustifyV("MIDDLE")
	level:SetPoint("CENTER", circle, "CENTER", 0, -0.5)
	main.LevelText = level
	f.levelText = level

	local hc = CreateFrame("Frame", nil, main)
	hc:SetFrameLevel(main:GetFrameLevel())   -- (useParentLevel)
	hc:SetSize(126, 20)
	hc:SetPoint("BOTTOMRIGHT", c, "LEFT", 148, 2)
	main.HealthBarsContainer = hc
	local health = Bar(hc, 126, 20)
	health:SetPoint("TOPLEFT", hc, "TOPLEFT", 0, 0)
	health:SetStatusBarTexture(ART.health)
	local fill = FillOf(health)
	if fill then
		fill:SetDrawLayer("BACKGROUND", 0)
	end
	Crisp(fill)
	health.HealthBarTexture = fill
	hc.HealthBar = health
	local loss = CreateFrame("StatusBar", nil, hc)
	loss:SetFrameLevel(hc:GetFrameLevel())
	loss:SetAllPoints(hc)
	loss:SetMinMaxValues(0, 1)
	loss:SetValue(0)
	loss:SetStatusBarTexture("UI-HUD-UnitFrame-Target-PortraitOn-Bar-TempHPLoss")
	loss.TempMaxHealthLossTexture = FillOf(loss)
	if loss.TempMaxHealthLossTexture then
		loss.TempMaxHealthLossTexture:SetDrawLayer("BACKGROUND", 0)
	end
	hc.TempMaxHealthLoss = loss
	local texts = TextsOn(health, hc, { right = -5 })
	hc.HealthBarText, hc.LeftText, hc.RightText = texts.center, texts.left, texts.right
	-- (TextStatusBar's own keys on the bar, as SetBarText lays them: Bar Text fades these and hangs its value on them)
	health.TextString, health.LeftText, health.RightText = texts.center, texts.left, texts.right
	local deadText = Font(hc, "OVERLAY", 1, "GameFontNormalSmall")
	deadText:SetJustifyH("CENTER")
	deadText:SetJustifyV("MIDDLE")
	deadText:SetPoint("CENTER", hc, "CENTER", 0, 0)
	deadText:SetText(Dead())
	deadText:Hide()
	hc.DeadText = deadText
	local unconscious = Font(hc, "OVERLAY", 1, "GameFontNormalSmall")
	unconscious:SetJustifyH("CENTER")
	unconscious:SetJustifyV("MIDDLE")
	unconscious:SetPoint("CENTER", hc, "CENTER", 0, 0)
	unconscious:SetText(rawget(_G, "UNCONSCIOUS") or "Unconscious")
	unconscious:Hide()
	hc.UnconsciousText = unconscious
	local hmask = hc:CreateMaskTexture(nil, "OVERLAY", nil, 2)
	Atlas(hmask, ART.healthMask, true)
	hmask:SetPoint("TOPLEFT", hc, "TOPLEFT", -1, 6)
	Masked(fill, hmask)
	hc.HealthBarMask = hmask
	health.unit, health.unitFrame, health.lockColor, health.capNumericDisplay = unit, f, true, true

	local mana = Bar(main, 134, 10)
	mana:SetFrameLevel(main:GetFrameLevel() + 1)
	mana:SetPoint("TOPRIGHT", hc, "BOTTOMRIGHT", 8, -1)
	mana:SetStatusBarTexture(ART.mana)
	Crisp(FillOf(mana))
	mana.ManaBarTexture = FillOf(mana)
	main.ManaBar = mana
	local mtexts = TextsOn(mana, mana, { center = -4, right = -13 })
	mana.ManaBarText, mana.LeftText, mana.RightText = mtexts.center, mtexts.left, mtexts.right
	mana.TextString = mtexts.center
	local mmask = mana:CreateMaskTexture(nil, "OVERLAY", nil, 3)
	Atlas(mmask, ART.manaMask, true)
	mmask:SetPoint("TOPLEFT", mana, "TOPLEFT", -61, 3)
	Crisp(mmask)
	Masked(FillOf(mana), mmask)
	mana.ManaBarMask = mmask
	mana.unit, mana.unitFrame, mana.lockColor, mana.capNumericDisplay = unit, f, true, true
	f.texts = { health = texts, mana = mtexts }

	-- the contextual: the PvP circle, the skull, the crown, the raid mark, the star and quest marks, the PvP and honour
	-- pictures, the numeric threat
	local ctx = Holder(content)
	content.TargetFrameContentContextual = ctx
	local pvpCircle = Tex(ctx, "OVERLAY", -1, ART.circle, true)
	pvpCircle:SetScale(0.8)
	pvpCircle:SetPoint("TOP", ctx, "TOPRIGHT", -23, -50)
	pvpCircle:Hide()
	ctx.PvpBackgroundCircle = pvpCircle
	local pvpIcon = Tex(ctx, "OVERLAY", 0, ART.pvp, true)
	pvpIcon:SetScale(0.8)
	pvpIcon:SetPoint("CENTER", pvpCircle, "CENTER", 0, 0)
	pvpIcon:Hide()
	ctx.PvpBackgroundIcon = pvpIcon
	local skull = Tex(ctx, "OVERLAY", 1, ART.skull, true)
	skull:SetPoint("CENTER", circle, "CENTER", 0, 0)
	ctx.HighLevelTexture = skull
	ctx.LeaderIcon = Tex(ctx, "OVERLAY", 1, ART.leader, true)
	ctx.LeaderIcon:SetPoint("TOPRIGHT", ctx, "TOPRIGHT", -85, -8)
	ctx.LeaderIcon:Hide()
	ctx.GuideIcon = Tex(ctx, "OVERLAY", 1, ART.guide, true)
	ctx.GuideIcon:SetPoint("TOPRIGHT", ctx, "TOPRIGHT", -85, -8)
	ctx.GuideIcon:Hide()
	local raid = Tex(ctx, "OVERLAY", 1)
	raid:SetTexture(ART.raidIcons)
	raid:SetSize(26, 26)
	raid:SetPoint("CENTER", portrait, "TOP", 0, 0)
	raid:Hide()
	ctx.RaidTargetIcon = raid
	ctx.BossIcon = Tex(ctx, "OVERLAY", 1, ART.star, true)
	ctx.BossIcon:SetPoint("CENTER", portrait, "BOTTOM", 0, 0)
	ctx.BossIcon:Hide()
	ctx.QuestIcon = Tex(ctx, "OVERLAY", 1, ART.quest, true)
	ctx.QuestIcon:SetPoint("CENTER", portrait, "BOTTOM", 0, 0)
	ctx.QuestIcon:Hide()
	ctx.PvpIcon = Tex(ctx, "OVERLAY", 1)
	ctx.PvpIcon:SetPoint("TOP", ctx, "TOPRIGHT", -26, -50)
	ctx.PvpIcon:Hide()
	ctx.PrestigePortrait = Tex(ctx, "OVERLAY", 1)
	ctx.PrestigePortrait:SetSize(50, 52)
	ctx.PrestigePortrait:SetPoint("TOPRIGHT", ctx, "TOPRIGHT", -2, -38)
	ctx.PrestigePortrait:Hide()
	ctx.PetBattleIcon = Tex(ctx, "OVERLAY", 1)
	ctx.PetBattleIcon:SetTexture(ART.petBadge)
	ctx.PetBattleIcon:SetSize(32, 32)
	ctx.PetBattleIcon:SetPoint("TOPRIGHT", ctx, "TOPRIGHT", -13, -52)
	ctx.PetBattleIcon:Hide()
	ctx.PrestigeBadge = Tex(ctx, "OVERLAY", 2)
	ctx.PrestigeBadge:SetSize(30, 30)
	ctx.PrestigeBadge:SetPoint("CENTER", ctx.PrestigePortrait, "CENTER", 0, 0)
	ctx.PrestigeBadge:Hide()
	local threat = CreateFrame("Frame", nil, ctx)
	threat:SetSize(49, 18)
	threat:SetPoint("BOTTOM", band, "TOP", 0, 0)
	threat:Hide()
	threat.text = Font(threat, "BACKGROUND", 0, "GameFontHighlight")
	threat.text:SetPoint("TOP", threat, "TOP", 0, -4)
	threat.text:SetText("100%")
	threat.bg = Tex(threat, "BACKGROUND", 0)
	threat.bg:SetTexture(ART.threatBg)
	threat.bg:SetSize(37, 14)
	threat.bg:SetPoint("TOP", threat, "TOP", 0, -3)
	local border = Tex(threat, "ARTWORK", 0)
	border:SetTexture(ART.threatBorder)
	border:SetTexCoord(0, 0.765625, 0, 0.5625)
	border:SetAllPoints(threat)
	ctx.NumericalThreat = threat

	-- the game's own keys of a unit frame (UnitFrame_Initialize's) for the modules that read them; the cast bar and
	-- the aura row stay the game's (read through ours by the cast bar's dressers)
	f.portrait, f.healthbar, f.manabar = portrait, health, mana
	f.threatIndicator, f.threatNumericIndicator = flash, threat
	flash.unit, flash.feedbackUnit = unit, "player"
	f.spellbar = rawget(game, "spellbar")
	local mixin = rawget(_G, "TargetFrameMixin")
	f.UpdateHealthBarVisuals = type(mixin) == "table" and rawget(mixin, "UpdateHealthBarVisuals") or nil
	f.GetPvPIndicatorElements = type(mixin) == "table" and rawget(mixin, "GetPvPIndicatorElements") or nil
	mana.UpdateTextString = O.ManaText
	health.UpdateTextString = O.HealthText
	local g = function(...) return Path(game, ...) end
	local map = { [game] = f }
	local pairs_ = {
		{ c, g("TargetFrameContainer") }, { portrait, g("TargetFrameContainer", "Portrait") },
		{ pmask, g("TargetFrameContainer", "PortraitMask") }, { art, g("TargetFrameContainer", "FrameTexture") },
		{ flash, g("TargetFrameContainer", "Flash") }, { boss, g("TargetFrameContainer", "BossPortraitFrameTexture") },
		{ content, gContent }, { main, gMain }, { band, Path(gMain, "ReputationColor") },
		{ name, Path(gMain, "Name") }, { circle, Path(gMain, "LevelBackgroundCircle") },
		{ level, Path(gMain, "LevelText"), "nosize" },
		{ hc, Path(gMain, "HealthBarsContainer") },
		{ health, Path(gMain, "HealthBarsContainer", "HealthBar") },
		{ loss, Path(gMain, "HealthBarsContainer", "TempMaxHealthLoss") },
		{ texts.center, Path(gMain, "HealthBarsContainer", "HealthBarText"), "nosize" },
		{ texts.left, Path(gMain, "HealthBarsContainer", "LeftText"), "nosize" },
		{ texts.right, Path(gMain, "HealthBarsContainer", "RightText"), "nosize" },
		{ deadText, Path(gMain, "HealthBarsContainer", "DeadText"), "nosize" },
		{ unconscious, Path(gMain, "HealthBarsContainer", "UnconsciousText"), "nosize" },
		{ hmask, Path(gMain, "HealthBarsContainer", "HealthBarMask") },
		{ mana, Path(gMain, "ManaBar") },
		{ mtexts.center, Path(gMain, "ManaBar", "ManaBarText"), "nosize" },
		{ mtexts.left, Path(gMain, "ManaBar", "LeftText"), "nosize" },
		{ mtexts.right, Path(gMain, "ManaBar", "RightText"), "nosize" },
		{ mmask, Path(gMain, "ManaBar", "ManaBarMask") },
	}
	local gFill = function(bar) return type(bar) == "table" and bar.GetStatusBarTexture and bar:GetStatusBarTexture() end
	pairs_[#pairs_ + 1] = { FillOf(health), gFill(Path(gMain, "HealthBarsContainer", "HealthBar")), "look" }
	pairs_[#pairs_ + 1] = { FillOf(mana), gFill(Path(gMain, "ManaBar")), "look" }
	pairs_[#pairs_ + 1] = { FillOf(loss), gFill(Path(gMain, "HealthBarsContainer", "TempMaxHealthLoss")), "look" }
	local gCtx = Path(gContent, "TargetFrameContentContextual")
	pairs_[#pairs_ + 1] = { ctx, gCtx }
	for _, key in ipairs({ "PvpBackgroundCircle", "PvpBackgroundIcon", "HighLevelTexture", "LeaderIcon", "GuideIcon",
		"RaidTargetIcon", "BossIcon", "QuestIcon", "PvpIcon", "PrestigePortrait", "PetBattleIcon", "PrestigeBadge",
		"NumericalThreat" }) do
		pairs_[#pairs_ + 1] = { ctx[key], Path(gCtx, key) }
	end
	for _, p in ipairs(pairs_) do
		if p[1] and type(p[2]) == "table" and p[3] ~= "look" then
			map[p[2]] = p[1]
		end
	end
	Mirror(pairs_, map)
	-- (a part the client's build has not -- this build's target frame has no PvP circle -- none on ours either)
	if type(gCtx) == "table" and rawget(gCtx, "PvpBackgroundCircle") == nil then
		ctx.PvpBackgroundCircle:Hide()
		ctx.PvpBackgroundCircle = nil
	end
	f.Update = O.Update
	f.CheckLevel = O.CheckLevel
	f.CheckFaction = O.CheckFaction
	f.CheckClassification = O.CheckClassification
	f.CheckDead = O.CheckDead
	f.CheckPartyLeader = O.CheckPartyLeader
	f.UpdateRaidTargetIcon = O.UpdateRaidTargetIcon
	f.GetPortrait = O.GetPortrait
	f.map = map   -- (the game's parts -> ours: the small focus frame's places copied again, below)
	kind.frame = f
	O.Scripts(f)
	f.totFrame = BuildToT(kind)
	return f
end

--------------------------------------------------------------------------------
-- The target of target of ours: TargetofTargetFrameTemplate's parts (120 x 49: the portrait 37 round at 5,-5, the
-- name at its right, the health bar 70 x 10 and the mana bar 74 x 7 in the party's masks, four debuffs at its right)
--------------------------------------------------------------------------------

local OnDebuffEnter = Shared("your target of target's debuff: its tooltip", function(self)
	local okC, x = pcall(self.GetCenter, self)
	local width = rawget(_G, "GetScreenWidth")
	local wide = width and Num(width()) or 0
	if okC and Num(x) and x > wide / 2 then
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	else
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	end
	local tot = self:GetParent()
	pcall(GameTooltip.SetUnitDebuff, GameTooltip, tot and tot.unit or "targettarget", self.index or self:GetID(),
		self.filter)
end, "script")

local OnDebuffLeave = Shared("your target of target's debuff: its tooltip away", function()
	GameTooltip:Hide()
end, "script")

local function Debuff(tot, i, ...)
	local d = CreateFrame("Frame", tot:GetName() .. "Debuff" .. i, tot)
	d:SetID(i)
	d:SetSize(12, 12)
	d:SetPoint(...)
	d:EnableMouse(true)
	d:Hide()
	d.Icon = Tex(d, "ARTWORK", 0)
	d.Icon:SetAllPoints(d)
	d.Border = Tex(d, "OVERLAY", 0)
	d.Border:SetTexture(ART.debuffBorder)
	d.Border:SetSize(13, 13)
	d.Border:SetPoint("TOPLEFT", d, "TOPLEFT", -1, 1)
	d.Border:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", 1, -1)
	d.Border:SetTexCoord(DEBUFF_COORDS[1], DEBUFF_COORDS[2], DEBUFF_COORDS[3], DEBUFF_COORDS[4])
	local okC, cd = pcall(CreateFrame, "Cooldown", nil, d, "CooldownFrameTemplate")
	if okC and cd then
		pcall(cd.SetHideCountdownNumbers, cd, true)
		pcall(cd.SetReverse, cd, true)
		pcall(cd.SetDrawEdge, cd, true)
		cd:SetAllPoints(d)
		cd:ClearAllPoints()
		cd:SetPoint("CENTER", d, "CENTER", 0, -1)
		cd:SetSize(12, 12)
		cd:Hide()
		d.Cooldown = cd
	end
	Perf.SetScript(d, "OnEnter", OnDebuffEnter)
	Perf.SetScript(d, "OnLeave", OnDebuffLeave)
	return d
end

function BuildToT(kind)
	local game = rawget(_G, kind.gameToT)
	if kind.tot or type(game) ~= "table" or InCombatLockdown() then
		return kind.tot
	end
	local unit = kind.totUnit
	local f = CreateFrame("Button", kind.name .. "ToT", game, "SecureUnitButtonTemplate")
	U.mine[f] = true
	f:SetAllPoints(game)
	f:SetFrameLevel(game:GetFrameLevel())
	f:SetAttribute("unit", unit)
	f:SetAttribute("*type1", "target")
	f:RegisterForClicks("AnyUp")
	f.unit, f.frameType, f.capNumeric, f.kind = unit, "TargetofTarget", true, kind
	f:Hide()
	local portrait = Tex(f, "BACKGROUND", 1)
	portrait:SetSize(37, 37)
	portrait:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -5)
	f.Portrait = portrait
	local pmask = f:CreateMaskTexture(nil, "BACKGROUND", nil, 1)
	Atlas(pmask, ART.circleMask)
	pmask:SetPoint("TOPLEFT", portrait, "TOPLEFT", 0, 0)
	pmask:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", 0, 0)
	Masked(portrait, pmask)
	f.PortraitMask = pmask
	local art = Tex(f, "BACKGROUND", 2, ART.tot, true)
	art:SetPoint("CENTER", f, "CENTER", 0, 0)
	f.FrameTexture = art
	local name = Font(f, "OVERLAY", 0, "GameFontNormalSmall")
	FontLike(name, rawget(game, "Name"), "GameFontNormalSmall")
	name:SetSize(68, 10)
	name:SetJustifyH("LEFT")
	name:SetPoint("TOPLEFT", portrait, "TOPRIGHT", 2, 0)
	f.Name = name
	f.name = name
	local health = CreateFrame("StatusBar", nil, f)
	health:SetSize(70, 10)
	health:SetMinMaxValues(0, 1)
	health:SetValue(1)
	health:SetPoint("BOTTOMRIGHT", f, "RIGHT", -6, -2.5)
	health:SetStatusBarTexture(ART.totHealth)
	f.HealthBar = health
	for _, key in ipairs({ "DeadText", "UnconsciousText" }) do
		local fs = Font(health, "ARTWORK", 0, "GameFontNormalSmall")
		fs:SetJustifyH("CENTER")
		fs:SetJustifyV("MIDDLE")
		fs:SetPoint("CENTER", health, "CENTER", 0, 0)
		fs:SetText(key == "DeadText" and Dead() or (rawget(_G, "UNCONSCIOUS") or "Unconscious"))
		fs:Hide()
		health[key] = fs
	end
	local hmask = health:CreateMaskTexture(nil, "OVERLAY")
	Atlas(hmask, ART.totHealthMask, true)
	hmask:SetPoint("TOPLEFT", health, "TOPLEFT", -29, 3)
	Masked(FillOf(health), hmask)
	health.HealthBarMask = hmask
	health.unit, health.unitFrame, health.lockColor = unit, f, true
	local mana = CreateFrame("StatusBar", nil, f)
	mana:SetSize(74, 7)
	mana:SetMinMaxValues(0, 1)
	mana:SetValue(1)
	mana:SetPoint("TOPLEFT", health, "BOTTOMLEFT", -4, -1)
	mana:SetStatusBarTexture(ART.totMana)
	f.ManaBar = mana
	local mmask = mana:CreateMaskTexture(nil, "OVERLAY", nil, 2)
	Atlas(mmask, ART.totManaMask, true)
	mmask:SetPoint("TOPLEFT", mana, "TOPLEFT", -27, 4)
	Crisp(mmask)
	Masked(FillOf(mana), mmask)
	mana.ManaBarMask = mmask
	mana.unit, mana.unitFrame, mana.lockColor = unit, f, true
	local d1 = Debuff(f, 1, "TOPLEFT", f, "TOPRIGHT", 4, -10)
	local d2 = Debuff(f, 2, "LEFT", d1, "RIGHT", 1, 0)
	local d3 = Debuff(f, 3, "TOPLEFT", d1, "BOTTOMLEFT", 0, -1)
	local d4 = Debuff(f, 4, "LEFT", d3, "RIGHT", 1, 0)
	f.debuffs = { d1, d2, d3, d4 }
	f.portrait, f.healthbar, f.manabar = portrait, health, mana
	local g = function(...) return Path(game, ...) end
	local map = { [game] = f }
	local pairs_ = { { portrait, g("Portrait") }, { pmask, g("PortraitMask") }, { art, g("FrameTexture") },
		{ name, g("Name") }, { health, g("HealthBar") }, { health.DeadText, g("HealthBar", "DeadText"), "nosize" },
		{ health.UnconsciousText, g("HealthBar", "UnconsciousText"), "nosize" }, { hmask, g("HealthBar", "HealthBarMask") },
		{ mana, g("ManaBar") }, { mmask, g("ManaBar", "ManaBarMask") } }
	local gFill = function(bar) return type(bar) == "table" and bar.GetStatusBarTexture and bar:GetStatusBarTexture() end
	pairs_[#pairs_ + 1] = { FillOf(health), gFill(g("HealthBar")), "look" }
	pairs_[#pairs_ + 1] = { FillOf(mana), gFill(g("ManaBar")), "look" }
	local gname = game:GetName()
	for i = 1, MAX_TOT_DEBUFFS do
		pairs_[#pairs_ + 1] = { f.debuffs[i], gname and rawget(_G, gname .. "Debuff" .. i) }
	end
	for _, p in ipairs(pairs_) do
		if p[1] and type(p[2]) == "table" then
			map[p[2]] = p[1]
		end
	end
	Mirror(pairs_, map)
	f.Update = O.ToTUpdate
	f.CheckDead = O.ToTCheckDead
	f.HealthCheck = O.ToTHealthCheck
	kind.tot = f
	O.ToTScripts(f)
	return f
end

--------------------------------------------------------------------------------
-- What the target frame shows, as the game's code shows it (TargetFrame.lua, UnitFrame.lua): on its unit's events
--------------------------------------------------------------------------------

local function Main(f)
	return f.TargetFrameContent.TargetFrameContentMain
end
local function Ctx(f)
	return f.TargetFrameContent.TargetFrameContentContextual
end

function O.GetPortrait(f)
	return f.TargetFrameContainer.Portrait
end

-- the name (UnitFrame_Update: GetUnitName, the follower prefix in a follower dungeon)
local function Name(f)
	local unit = f.unit
	local okN, text = pcall(rawget(_G, "GetUnitName") or UnitName, unit, false)
	if not okN then
		text = nil
	end
	if text ~= nil and not Secret(text) and Yes(rawget(_G, "UnitInPartyIsAI"), unit) then
		local lfg = rawget(_G, "C_LFGInfo")
		local prefix = rawget(_G, "LFG_FOLLOWER_NAME_PREFIX")
		if prefix and lfg and Yes(lfg.IsInLFGFollowerDungeon) then
			text = prefix:format(text)
		end
	end
	if text ~= nil then
		pcall(f.name.SetText, f.name, text)
	end
end

-- the portrait (UnitFramePortrait_Update: the class picture for a player while the CVar says so, else the unit's)
local function Portrait(f)
	local portrait = f.portrait
	local replace = rawget(_G, "UnitFrame_ShouldReplacePortrait")
	if replace and Ask(replace, f) == true then
		local okC, _, class = pcall(UnitClass, f.unit)
		class = okC and Text(class) or nil
		local atlas = class and Ask(rawget(_G, "GetClassAtlas"), class)
		if atlas then
			Atlas(portrait, atlas)
			U.Notify("UnitFramePortrait_Update", f)
			return
		end
	end
	pcall(SetPortraitTexture, portrait, f.unit, f.disablePortraitMask)
	U.Notify("UnitFramePortrait_Update", f)
end

-- the health bar (UnitFrameHealthBar_Update: a disconnected unit's full)
local function Health(f)
	local hb, unit = f.healthbar, f.unit
	local max = UnitHealthMax(unit)
	local plainMax = Num(max)
	pcall(hb.SetMinMaxValues, hb, 0, (plainMax and plainMax == 0) and 1 or max)
	BarShown(hb, max)
	if U.Connected(unit) then
		pcall(hb.SetValue, hb, UnitHealth(unit))
	else
		pcall(hb.SetValue, hb, (plainMax and plainMax == 0) and 1 or max)
	end
	U.Notify("UnitFrameHealthBar_Update", hb, unit)
	U.Texts(f)
	if f.HealthCheck then
		f:HealthCheck()
	end
end

-- the mana bar (UnitFrameManaBar_Update: its values, paused or not -- a "minus" unit's bar is hidden by its shown rule)
local function Power(f)
	local mb, unit = f.manabar, f.unit
	local pt = mb.powerType
	local okM, max = pcall(UnitPowerMax, unit, pt)
	max = okM and max or 0
	pcall(mb.SetMinMaxValues, mb, 0, max)
	BarShown(mb, max)
	if U.Connected(unit) then
		local okV, v = pcall(UnitPower, unit, pt)
		if okV then
			pcall(mb.SetValue, mb, v)
		end
	else
		pcall(mb.SetValue, mb, max)
	end
	U.Texts(f)
end

-- the power's picture (UnitFrameManaBar_UpdateType: "UI-HUD-UnitFrame-<Target|TargetofTarget>-PortraitOn-Bar-<Mana|
-- Rage|...>", or the power's own, or the colourable mana picture in the power's alternative colour)
local function PowerType(f)
	local mb, unit = f.manabar, f.unit
	local okT, powerType, token, altR, altG, altB = pcall(UnitPowerType, unit)
	token = okT and Text(token) or nil
	local colours = rawget(_G, "PowerBarColor")
	local info = token and type(colours) == "table" and colours[token] or nil
	local base = "UI-HUD-UnitFrame-" .. f.frameType .. "-PortraitOn"
	if type(info) == "table" and info.atlasElementName then
		mb:SetStatusBarTexture(base .. "-Bar-" .. info.atlasElementName)
		mb:SetStatusBarColor(1, 1, 1)
	elseif type(info) == "table" and info.atlas then
		mb:SetStatusBarTexture(info.atlas)
		mb:SetStatusBarColor(1, 1, 1)
	else
		mb:SetStatusBarColor(1, 1, 1)
		if Num(altR) then
			mb:SetStatusBarTexture(base .. "-Bar-Mana-Status")
			mb:SetStatusBarColor(altR, altG, altB)
		else
			mb:SetStatusBarTexture(base .. "-Bar-Mana")
		end
	end
	local fill = FillOf(mb)
	if f.frameType == "Target" then
		Crisp(fill)   -- (the target's fills: TargetFrameMixin:OnLoadBase's; the target of target's are left as made)
	end
	Masked(fill, mb.ManaBarMask)   -- (a new picture keeps the mask)
	if fill then
		fill:SetDesaturated(false)
		fill:SetAlpha(1)
	end
	if okT and not Secret(powerType) then
		mb.powerType, mb.powerToken = powerType, token
	end
	U.Notify("UnitFrameManaBar_UpdateType", mb)
end

-- the threat flash and the numeric threat (UnitFrame_UpdateThreatIndicator: your threat on the target; a secret
-- answer shows none)
local function Threat(f)
	local flash, numeric, unit = f.threatIndicator, f.threatNumericIndicator, f.unit
	local okS, s = pcall(rawget(_G, "UnitThreatSituation"), "player", unit)
	local status = okS and Num(s) or nil
	if not Yes(rawget(_G, "IsThreatWarningEnabled")) or Yes(UnitIsDead, unit) then
		flash:Hide()
		numeric:Hide()
		return
	end
	if status and status > 0 then
		local okC, r, g, b = pcall(rawget(_G, "GetThreatStatusColor"), status)
		if okC and Num(r) then
			flash:SetVertexColor(r, g, b)
		end
		flash:Show()
	else
		flash:Hide()
	end
	local cls = Text(Ask(UnitClassification, unit))
	if Yes(rawget(_G, "ShowNumericThreat")) and cls ~= "minus" then
		local okD, tanking, detailed, _, raw = pcall(rawget(_G, "UnitDetailedThreatSituation"), "player", unit)
		local display = okD and Num(raw) or nil
		if okD and tanking == true then
			display = Num(Ask(rawget(_G, "UnitThreatPercentageOfLead"), "player", unit))
		end
		detailed = okD and Num(detailed) or nil
		local util = rawget(_G, "PlayerUtil")
		if okD and tanking ~= true and type(util) == "table" and Yes(util.IsPlayerEffectivelyTank) then
			detailed = 2
		end
		if display and display ~= 0 then
			numeric.text:SetText(("%1.0f"):format(display) .. "%")
			local okC, r, g, b = pcall(rawget(_G, "GetThreatStatusColor"), detailed or 0)
			if okC and Num(r) then
				numeric.bg:SetVertexColor(r, g, b)
			end
			numeric:Show()
		else
			numeric:Hide()
		end
	else
		numeric:Hide()
	end
end

-- (TargetFrameMixin:CheckLevel: a corpse's and a too high level's the skull; the level in the game's difficulty
-- colour for a unit you can attack, else gold)
local function OwnCheckLevel(f)
	local unit = f.unit
	local level, skull = Main(f).LevelText, Ctx(f).HighLevelTexture
	local effective = Num(Ask(UnitEffectiveLevel, unit))
	if Yes(rawget(_G, "UnitIsCorpse"), unit) then
		level:Hide()
		skull:Show()
	elseif effective and effective > 0 then
		level:SetText(effective)
		local colour
		if Yes(UnitCanAttack, "player", unit) then
			local info = rawget(_G, "C_PlayerInfo")
			local difficulty = info and Ask(info.GetContentDifficultyCreatureForPlayer, unit)
			colour = difficulty ~= nil and Ask(rawget(_G, "GetDifficultyColor"), difficulty) or nil
		end
		if type(colour) == "table" and Num(colour.r) then
			level:SetVertexColor(colour.r, colour.g, colour.b)
		else
			level:SetVertexColor(1.0, 0.82, 0.0)
		end
		level:Show()
		skull:Hide()
	else
		level:Hide()
		skull:Show()
	end
end

-- (TargetFrameMixin:CheckFaction: the type band in the unit's selection colour, grey and the portrait grey for a
-- creature tapped by others; the PvP circle through the game's own secret-safe helper)
local function OwnCheckFaction(f)
	local unit = f.unit
	local band, portrait = Main(f).ReputationColor, f.TargetFrameContainer.Portrait
	if not Yes(UnitPlayerControlled, unit) and Yes(UnitIsTapDenied, unit) then
		band:SetVertexColor(0.5, 0.5, 0.5)
		portrait:SetVertexColor(0.5, 0.5, 0.5)
	else
		local colour = rawget(_G, "UnitSelectionColor")
		pcall(function() band:SetVertexColor(colour(unit)) end)
		portrait:SetVertexColor(1.0, 1.0, 1.0)
	end
	local rules, E = rawget(_G, "C_GameRules"), rawget(_G, "Enum")
	local off = rules and E and E.GameRule and E.GameRule.UnitFramePvPContextualDisabled
		and Yes(rules.IsGameRuleActive, E.GameRule.UnitFramePvPContextualDisabled)
	local util = rawget(_G, "UnitFrameUtil")
	if f.showPVP and not off and type(util) == "table" and type(util.UpdateUnitPvPIndicator) == "function" then
		local ctx = Ctx(f)
		pcall(util.UpdateUnitPvPIndicator, { pvpBackground = ctx.PvpBackgroundCircle, pvpIcon = ctx.PvpBackgroundIcon },
			unit)
	end
end

-- (TargetFrameMixin:CheckClassification: the frame's picture for a rare or a "minus" unit, the health bar's box and
-- mask, the mana bar paused and hidden for a "minus" one; Camelot's GetBossPortraitFrameData: the winged gold for a
-- boss, the winged silver for a rare, the gold for an elite; the quest mark for a quest boss)
local function OwnCheckClassification(f)
	local unit = f.unit
	local c, main = f.TargetFrameContainer, Main(f)
	local hc = main.HealthBarsContainer
	local hb, mb = hc.HealthBar, main.ManaBar
	local cls = Text(Ask(UnitClassification, unit))
	mb.pauseUpdates = false
	mb:Show()
	local visuals = f.UpdateHealthBarVisuals
	if cls == "minus" then
		Atlas(c.FrameTexture, ART.minus, true)
		Atlas(f.threatIndicator, ART.minusFlash, true)
	end
	if visuals then
		pcall(visuals, f, cls or "normal")
	end
	if cls == "minus" and not visuals then
		Atlas(FillOf(hb), ART.minusHealth, true)
		hc:SetHeight(12)
		hc:SetWidth(125)
		hc:SetPoint("BOTTOMRIGHT", c, "LEFT", 148, -1)
		Atlas(hc.HealthBarMask, ART.minusHealthMask, true)
		hc.HealthBarMask:SetPoint("TOPLEFT", hc, "TOPLEFT", -1, 2)
	end
	if cls == "minus" then
		mb.pauseUpdates = true
		mb:Hide()
		mb.TextString:Hide()
		mb.LeftText:Hide()
		mb.RightText:Hide()
	else
		Atlas(c.FrameTexture, (cls == "rare" or cls == "rareelite") and ART.rare or ART.frame, true)
		Atlas(f.threatIndicator, ART.flash, true)
	end
	if cls ~= "minus" and not visuals then
		Atlas(FillOf(hb), ART.health, true)
		hc:SetHeight(20)
		hc:SetWidth(126)
		hc:SetPoint("BOTTOMRIGHT", c, "LEFT", 149, -10)
		Atlas(hc.HealthBarMask, ART.healthMask, true)
		hc.HealthBarMask:SetPoint("TOPLEFT", hc, "TOPLEFT", -1, 6)
	end
	local okB, atlas, x, y = pcall(rawget(_G, "GetBossPortraitFrameData") or function() return nil end, unit, cls)
	local bossTex = c.BossPortraitFrameTexture
	if okB and type(atlas) == "string" then
		Atlas(bossTex, atlas, true)
		bossTex:SetPoint("TOPRIGHT", c, "TOPRIGHT", Num(x) or 0, Num(y) or 0)
		bossTex:Show()
	else
		bossTex:Hide()
	end
	local ctx = Ctx(f)
	local questBoss = Yes(rawget(_G, "UnitIsQuestBoss"), unit)
	ctx.QuestIcon:SetShown(questBoss)
	local star = rawget(_G, "ShouldShowStar")
	if questBoss then
		ctx.BossIcon:Hide()
	elseif star and Ask(star, cls) == true then
		Atlas(ctx.BossIcon, ART.star, true)
		ctx.BossIcon:Show()
	else
		ctx.BossIcon:Hide()
	end
end

-- (TargetFrameMixin:CheckDead: "Dead" or "Unconscious" on the health bar at none -- a secret amount: the unit's death)
local function OwnCheckDead(f)
	local unit = f.unit
	local hc = Main(f).HealthBarsContainer
	local h = Num(Ask(UnitHealth, unit))
	local none
	if h ~= nil then
		none = h <= 0
	else
		none = Yes(UnitIsDead, unit) or Yes(UnitIsGhost, unit)
	end
	if none and U.Connected(unit) then
		local out = Yes(rawget(_G, "UnitIsUnconscious"), unit)
		hc.UnconsciousText:SetShown(out)
		hc.DeadText:SetShown(not out)
	else
		hc.DeadText:Hide()
		hc.UnconsciousText:Hide()
	end
end

local function OwnCheckPartyLeader(f)
	local ctx = Ctx(f)
	if Yes(rawget(_G, "UnitLeadsAnyGroup"), f.unit) then
		local lfg = Yes(HasLFGRestrictions)
		ctx.LeaderIcon:SetShown(not lfg)
		ctx.GuideIcon:SetShown(lfg)
	else
		ctx.LeaderIcon:Hide()
		ctx.GuideIcon:Hide()
	end
end

-- the frame's methods (a dresser's post-hook of one runs as ours does it): the game's own code of this client's build
-- run on ours (TargetFrameMixin's), ours where it refuses (a secret it compares)
function O.CheckLevel(f) Game("TargetFrameMixin", "CheckLevel", f, OwnCheckLevel) end
function O.CheckFaction(f) Game("TargetFrameMixin", "CheckFaction", f, OwnCheckFaction) end
function O.CheckClassification(f) Game("TargetFrameMixin", "CheckClassification", f, OwnCheckClassification) end
function O.CheckDead(f) Game("TargetFrameMixin", "CheckDead", f, OwnCheckDead) end
function O.CheckPartyLeader(f) Game("TargetFrameMixin", "CheckPartyLeader", f, OwnCheckPartyLeader) end

-- the bars' text update the game's code calls on them (TextStatusBar's UpdateTextString): their shown rule, their texts
function O.ManaText(bar)
	local okM, _, max = pcall(bar.GetMinMaxValues, bar)
	BarShown(bar, okM and max or 0)
	if bar.unitFrame then
		U.Texts(bar.unitFrame)
	end
end
function O.HealthText(bar)
	if bar.unitFrame then
		U.Texts(bar.unitFrame)
	end
end

-- (a battle pet's level circle away where the game shows no badge: ShouldShowBattlePetIcon)
local function BattlePet(f)
	local unit = f.unit
	if Yes(rawget(_G, "UnitIsWildBattlePet"), unit) or Yes(rawget(_G, "UnitIsBattlePetCompanion"), unit) then
		if not Yes(rawget(_G, "ShouldShowBattlePetIcon")) then
			Main(f).LevelBackgroundCircle:Hide()
			Main(f).LevelText:Hide()
			Ctx(f).PetBattleIcon:Hide()
		end
	end
end

local function OwnUpdateRaidTargetIcon(f)
	local icon = Ctx(f).RaidTargetIcon
	local index = Num(Ask(GetRaidTargetIndex, f.unit))
	local set = rawget(_G, "SetRaidTargetIconTexture")
	if index and set and pcall(set, icon, index) then
		icon:Show()
	else
		icon:Hide()
	end
end

function O.UpdateRaidTargetIcon(f) Game("TargetFrameMixin", "UpdateRaidTargetIcon", f, OwnUpdateRaidTargetIcon) end

-- (FocusFrameMixin:SetSmallSize, stage 3) the small focus frame of Edit Mode's setting, read from the game's frame --
-- its own key, never written -- as ours updates: the game scales its frame and its focus target (ours follow, their
-- children); on ours what the game does to its parts: the health text's font (TextStatusBarTextLarge), the threat box's
-- place, the leader and PvP pictures off (showLeader / showPVP: the game's own code run on ours reads them). The
-- target's frame has no such setting: none read
local SMALL_OFF = { "PvpIcon", "PrestigePortrait", "PrestigeBadge", "LeaderIcon", "GuideIcon" }
local function Size(f)
	local game = f:GetParent()
	local small = rawget(game, "smallSize") and true or false
	if f.smallSize == small or not rawget(game, "SetSmallSize") then
		return
	end
	f.smallSize = small
	f.showLeader = (not small) or nil
	f.showPVP = (not small) or nil
	local gMain = Path(game, "TargetFrameContent", "TargetFrameContentMain")
	local gText = Path(gMain, "HealthBarsContainer", "HealthBar", "TextString")
		or Path(gMain, "HealthBarsContainer", "HealthBarText")
	local okF, font = pcall(function() return gText and gText:GetFontObject() end)
	local health = Main(f).HealthBarsContainer.HealthBar
	if okF and font then
		health.TextString:SetFontObject(font)
	end
	local ctx = Ctx(f)
	local gThreat = Path(game, "TargetFrameContent", "TargetFrameContentContextual", "NumericalThreat")
	if type(gThreat) == "table" and f.map then
		K.CopyPoints(ctx.NumericalThreat, gThreat, f.map, function() end)
	end
	if small then
		for _, key in ipairs(SMALL_OFF) do
			if ctx[key] then
				ctx[key]:Hide()
			end
		end
	end
end

-- (TargetFrameMixin:Update: the target of target first, then UnitFrame_Update, the level, the faction, the
-- classification, death, the crown, the portrait at full; its raid mark with the target changing)
function O.Update(f)
	f = f or T.frame
	if not f then
		return
	end
	Size(f)
	if not Yes(UnitExists, f.unit) and not Yes(rawget(_G, "UnitIsVisible"), f.unit) then
		return
	end
	if f.totFrame then
		f.totFrame:Update()
	end
	Name(f)
	Portrait(f)
	PowerType(f)
	Health(f)
	Power(f)
	Threat(f)
	U.Notify("UnitFrame_Update", f)
	f:CheckLevel()
	f:CheckFaction()
	f:CheckClassification()
	f:CheckDead()
	f:CheckPartyLeader()
	f.TargetFrameContainer.Portrait:SetAlpha(1.0)
	BattlePet(f)
	f:UpdateRaidTargetIcon()
end

--------------------------------------------------------------------------------
-- What the target of target shows (TargetOfTargetMixin): the game's ToT shows and hides itself, every frame, by its
-- rule (ours its child); ours reads its unit as it changes and as that unit's events come
--------------------------------------------------------------------------------

-- (TargetOfTargetMixin:CheckDead)
local function OwnToTCheckDead(f)
	local unit, hb = f.unit, f.HealthBar
	local h = Num(Ask(UnitHealth, unit))
	local none
	if h ~= nil then
		none = h <= 0
	else
		none = Yes(UnitIsDead, unit) or Yes(UnitIsGhost, unit)
	end
	if none and U.Connected(unit) then
		local out = Yes(rawget(_G, "UnitIsUnconscious"), unit)
		hb.UnconsciousText:SetShown(out)
		hb.DeadText:SetShown(not out)
	else
		hb.DeadText:Hide()
		hb.UnconsciousText:Hide()
	end
end

-- (TargetOfTargetMixin:HealthCheck: a player's portrait grey while dead, blue as a ghost, red at a fifth or less; a
-- secret amount: dead and ghost only)
local function OwnToTHealthCheck(f)
	local unit = f.unit
	if not Yes(UnitIsPlayer, unit) then
		return
	end
	local portrait = f.Portrait
	if Yes(UnitIsDead, unit) then
		portrait:SetVertexColor(0.35, 0.35, 0.35, 1.0)
		return
	elseif Yes(UnitIsGhost, unit) then
		portrait:SetVertexColor(0.2, 0.2, 0.75, 1.0)
		return
	end
	local cur, max = Num(Ask(UnitHealth, unit)), Num(Ask(UnitHealthMax, unit))
	local share = (cur and max and max > 0) and cur / max or nil
	if share and share > 0 and share <= 0.2 then
		portrait:SetVertexColor(1.0, 0.0, 0.0)
	else
		portrait:SetVertexColor(1.0, 1.0, 1.0, 1.0)
	end
end

-- its debuffs (AuraUtil.RefreshAuras' debuffs: up to four, a friend's dispellable ones where the game's setting says
-- so, only yours on an enemy where the castable-debuffs setting says so; secret parts set as they are or left out)
local function ToTDebuffs(f)
	local unit = f.unit
	local cvar = rawget(_G, "GetCVarBool")
	local raid = cvar and Ask(cvar, "showDispelDebuffs") == true and Yes(UnitCanAssist, "player", unit)
	local filter = raid and "HARMFUL|RAID" or "HARMFUL"
	local castable = rawget(_G, "SHOW_CASTABLE_DEBUFFS")
	if castable ~= nil and castable ~= "0" and Yes(UnitCanAttack, "player", unit) then
		filter = filter .. "|PLAYER"
	end
	local A = rawget(_G, "C_UnitAuras")
	local n = 0
	for i = 1, 40 do
		if n >= MAX_TOT_DEBUFFS then
			break
		end
		local okA, data = false, nil
		if A and A.GetAuraDataByIndex then
			okA, data = pcall(A.GetAuraDataByIndex, unit, i, filter)
		end
		if not okA or data == nil then
			break
		end
		local icon = data.icon
		if icon ~= nil then
			n = n + 1
			local d = f.debuffs[n]
			d.index, d.filter = i, filter
			pcall(d.Icon.SetTexture, d.Icon, icon)
			local dispel = data.dispelName
			local util = rawget(_G, "AuraUtil")
			if not (util and util.SetAuraBorderColor and pcall(util.SetAuraBorderColor, d.Border,
				(not Secret(dispel)) and dispel or nil)) then
				d.Border:SetVertexColor(0.8, 0, 0)
			end
			local cd = d.Cooldown
			if cd then
				local start, dur = Num(data.expirationTime), Num(data.duration)
				local set = rawget(_G, "CooldownFrame_Set")
				if start and dur and set then
					pcall(set, cd, start - dur, dur, true)
				elseif A.GetAuraDuration and cd.SetCooldownFromDurationObject and not Secret(data.auraInstanceID) then
					local okD, obj = pcall(A.GetAuraDuration, unit, data.auraInstanceID)
					if not (okD and obj and pcall(cd.SetCooldownFromDurationObject, cd, obj)) then
						cd:Hide()
					end
				else
					cd:Hide()
				end
			end
			d:Show()
		end
	end
	for i = n + 1, MAX_TOT_DEBUFFS do
		f.debuffs[i]:Hide()
	end
end

function O.ToTCheckDead(f) Game("TargetOfTargetMixin", "CheckDead", f, OwnToTCheckDead) end
function O.ToTHealthCheck(f) Game("TargetOfTargetMixin", "HealthCheck", f, OwnToTHealthCheck) end

-- everything once (TargetOfTargetMixin:Update's while it shows: UnitFrame_Update, death, the portrait's tint, the
-- debuffs)
function O.ToTUpdate(f)
	if not (f and f:IsVisible()) then
		return
	end
	Name(f)
	Portrait(f)
	PowerType(f)
	Health(f)
	Power(f)
	U.Notify("UnitFrame_Update", f)
	f:CheckDead()
	ToTDebuffs(f)
end

--------------------------------------------------------------------------------
-- Their scripts and events (only while they stand in)
--------------------------------------------------------------------------------

-- (and the frame's own change: the target changing, the focus changing -- its kind's `change`)
local EVENTS = { "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "RAID_TARGET_UPDATE", "PLAYER_FLAGS_CHANGED",
	"PORTRAITS_UPDATED", "CVAR_UPDATE", "UNIT_THREAT_SITUATION_UPDATE" }
local UNIT_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER",
	"UNIT_DISPLAYPOWER", "UNIT_NAME_UPDATE", "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_LEVEL",
	"UNIT_CLASSIFICATION_CHANGED", "UNIT_CONNECTION", "UNIT_THREAT_LIST_UPDATE", "UNIT_TARGET" }

local HANDLERS = {
	PLAYER_ENTERING_WORLD = function(f) O.Update(f) end,
	PLAYER_TARGET_CHANGED = function(f) O.Update(f) end,
	PLAYER_FOCUS_CHANGED = function(f) O.Update(f) end,
	-- (TargetFrameMixin:OnEvent: the focus updated -- the game's own frame clears a focus gone -- the target's target of
	-- target and faction)
	GROUP_ROSTER_UPDATE = function(f)
		if f.unit == "focus" then
			O.Update(f)
			return
		end
		if f.totFrame then
			f.totFrame:Update()
		end
		f:CheckFaction()
	end,
	RAID_TARGET_UPDATE = function(f) f:UpdateRaidTargetIcon() end,
	PLAYER_FLAGS_CHANGED = function(f, unit) if unit == f.unit then f:CheckPartyLeader() end end,
	PORTRAITS_UPDATED = function(f) Portrait(f) end,
	UNIT_THREAT_SITUATION_UPDATE = function(f, unit) if unit == nil or unit == "player" then Threat(f) end end,
	UNIT_THREAT_LIST_UPDATE = function(f) Threat(f) end,
	UNIT_HEALTH = function(f) Health(f) f:CheckDead() end,
	UNIT_MAXHEALTH = function(f) Health(f) end,
	UNIT_CONNECTION = function(f) Health(f) Power(f) end,
	UNIT_POWER_UPDATE = function(f) Power(f) end,
	UNIT_POWER_FREQUENT = function(f) Power(f) end,
	UNIT_MAXPOWER = function(f) Power(f) end,
	UNIT_DISPLAYPOWER = function(f) PowerType(f) Power(f) end,
	UNIT_NAME_UPDATE = function(f) Name(f) U.Notify("UnitFrame_Update", f) end,
	UNIT_PORTRAIT_UPDATE = function(f) Portrait(f) end,
	UNIT_MODEL_CHANGED = function(f) Portrait(f) end,
	UNIT_LEVEL = function(f) f:CheckLevel() end,
	UNIT_FACTION = function(f) f:CheckFaction() f:CheckLevel() end,
	UNIT_CLASSIFICATION_CHANGED = function(f) f:CheckClassification() end,
	UNIT_TARGET = function(f)
		if f.totFrame then
			f.totFrame:Update()
		end
	end,
	CVAR_UPDATE = function(f, cvar)
		if cvar == "statusText" or cvar == "statusTextDisplay" then
			U.TextsChanged()
			U.Texts(f)
		end
	end,
}

local OnEvent = Shared("your target frame (MelloUI's own): its unit's events", function(self, event, ...)
	local fn = HANDLERS[event]
	if fn then
		fn(self, ...)
	end
end, "script")

local function Listen(f, on)
	if on then
		for _, e in ipairs(EVENTS) do
			pcall(f.RegisterEvent, f, e)
		end
		pcall(f.RegisterEvent, f, f.kind.change)
		for _, e in ipairs(UNIT_EVENTS) do
			pcall(f.RegisterUnitEvent, f, e, f.unit)
		end
		pcall(f.RegisterUnitEvent, f, "UNIT_FACTION", f.unit, "player")
	else
		f:UnregisterAllEvents()
	end
end

-- (the target frame's bars under the mouse)
local function TargetHoverAt(f)
	local main = Main(f)
	return (main.HealthBarsContainer:IsMouseOver() and "health") or (main.ManaBar:IsShown() and main.ManaBar:IsMouseOver()
		and "mana") or nil
end

function O.Scripts(f)
	Perf.SetScript(f, "OnEvent", OnEvent)
	U.Tooltip(f, TargetHoverAt)
end

-- the target of target's: the events of whichever unit it is, heard while it shows (the client names no event
-- "targettarget": an event is its when its unit is that one)
local TOT_UNIT_EVENTS = { UNIT_HEALTH = "health", UNIT_MAXHEALTH = "health", UNIT_CONNECTION = "all",
	UNIT_POWER_UPDATE = "power", UNIT_MAXPOWER = "power", UNIT_DISPLAYPOWER = "powertype", UNIT_NAME_UPDATE = "name",
	UNIT_PORTRAIT_UPDATE = "portrait", UNIT_MODEL_CHANGED = "portrait", UNIT_AURA = "auras", PORTRAITS_UPDATED = "portrait" }

local OnToTEvent = Shared("your target of target (MelloUI's own): its unit's events", function(self, event, unit)
	local what = TOT_UNIT_EVENTS[event]
	if not what then
		return
	end
	if event ~= "PORTRAITS_UPDATED" then
		if type(unit) ~= "string" or Secret(unit) then
			return
		end
		local okU, same = pcall(UnitIsUnit, unit, self.unit)
		if not okU or Secret(same) or not same then
			return
		end
	end
	if what == "health" then
		Health(self)
		self:CheckDead()
	elseif what == "power" then
		Power(self)
	elseif what == "powertype" then
		PowerType(self)
		Power(self)
	elseif what == "name" then
		Name(self)
		U.Notify("UnitFrame_Update", self)
	elseif what == "portrait" then
		Portrait(self)
	elseif what == "auras" then
		ToTDebuffs(self)
	else
		self:Update()
	end
end, "script")

local function ToTListen(f, on)
	if on then
		for e in pairs(TOT_UNIT_EVENTS) do
			pcall(f.RegisterEvent, f, e)
		end
	else
		f:UnregisterAllEvents()
	end
end

local OnToTShow = Shared("your target of target shown (the game's own rule shows it)", function(self)
	if self.kind.standing then
		ToTListen(self, true)
		self:Update()
	end
end, "script")

local OnToTHide = Shared("your target of target hidden", function(self)
	ToTListen(self, false)
end, "script")

function O.ToTScripts(f)
	Perf.SetScript(f, "OnEvent", OnToTEvent)
	Perf.SetScript(f, "OnShow", OnToTShow)
	Perf.SetScript(f, "OnHide", OnToTHide)
end

--------------------------------------------------------------------------------
-- The game's frames kept away while ours stand in, and given back
--------------------------------------------------------------------------------

-- the events of the game's target frame's own updates (TargetFrameMixin:OnLoadBase, UnitFrame_Initialize, its bars,
-- TextStatusBar). Four stay with it: the world entered and the target changing (it shows and hides itself, its
-- sounds, its aura row), UNIT_FACTION and UNIT_TARGET (its aura row's layout: a friend's, the target of target's room).
-- The focus's frame keeps its group change too (its kind's `keep`: it clears a focus gone), and the two events its
-- own SetSmallSize lets go and takes again (the small frame listens to neither: no leader crown on it): the game's to
-- hold as its size says, so a frame given back holds what the game's own last size left it
local GAME_EVENTS = { "UNIT_HEALTH", "UNIT_LEVEL", "UNIT_CLASSIFICATION_CHANGED", "PLAYER_FLAGS_CHANGED",
	"GROUP_ROSTER_UPDATE", "RAID_TARGET_UPDATE", "UNIT_NAME_UPDATE", "UNIT_DISPLAYPOWER", "UNIT_PORTRAIT_UPDATE",
	"PORTRAITS_UPDATED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "UNIT_MAXHEALTH", "UNIT_HEAL_PREDICTION",
	"UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
	"UNIT_SPELLCAST_SUCCEEDED", "UNIT_MAX_HEALTH_MODIFIERS_CHANGED", "UNIT_THREAT_SITUATION_UPDATE",
	"UNIT_THREAT_LIST_UPDATE", "CVAR_UPDATE", "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER",
	"UNIT_CONNECTION", "VARIABLES_LOADED", "PLAYER_GAINS_VEHICLE_DATA", "PLAYER_LOSES_VEHICLE_DATA", "PLAYER_DEAD",
	"PLAYER_ALIVE", "PLAYER_UNGHOST", "UNIT_POWER_BAR_SHOW", "UNIT_POWER_BAR_HIDE" }
for _, kind in ipairs(KINDS) do
	kind.gameEvents = {}
	for _, e in ipairs(GAME_EVENTS) do
		if not kind.keep[e] then
			kind.gameEvents[#kind.gameEvents + 1] = e
		end
	end
end

local function GameParts(kind)
	local game = rawget(_G, kind.game)
	if type(game) ~= "table" then
		return nil
	end
	local content = rawget(game, "TargetFrameContent")
	local main = content and rawget(content, "TargetFrameContentMain")
	local ctx = content and rawget(content, "TargetFrameContentContextual")
	local hc = main and rawget(main, "HealthBarsContainer")
	return game, rawget(game, "TargetFrameContainer"), content, main, ctx, hc and rawget(hc, "HealthBar"),
		main and rawget(main, "ManaBar"), rawget(game, "Selection")
end

-- (a list of a frame's pictures and frames: select, then one table)
local function Pack(out, skip, ...)
	for i = 1, select("#", ...) do
		local r = select(i, ...)
		if r and r ~= skip and not U.mine[r] then
			out[#out + 1] = r
		end
	end
	return out
end
U.Pack = Pack   -- (the pet frame's, Modules/UnitFramesPet.lua)

-- the contextual part's pictures and frames but its aura row (the game's, kept)
local function Contextual(ctx)
	if not ctx then
		return {}
	end
	local auras = rawget(ctx, "Auras")
	local out = Pack({}, auras, ctx:GetRegions())
	return Pack(out, auras, ctx:GetChildren())
end

-- the game's target of target's every picture and frame (but ours)
local function ToTParts(tot)
	local out = Pack({}, nil, tot:GetRegions())
	return Pack(out, nil, tot:GetChildren())
end

local function GameToT(kind, game)
	local tot = rawget(game, "totFrame") or rawget(_G, kind.gameToT)
	return type(tot) == "table" and tot or nil
end

local function FadeGame(kind)
	local game, art, content, main, ctx = GameParts(kind)
	if not game then
		return
	end
	local parts = Contextual(ctx)
	local fade = { art or false, main or false }
	for _, r in ipairs(parts) do
		fade[#fade + 1] = r
	end
	U.Fade(kind.owner, fade, { game, content or false, ctx or false }, fade)
	local tot = GameToT(kind, game)
	if tot then
		U.Fade(kind.totOwner, ToTParts(tot), nil, { tot })
	end
end

local function QuietGame(kind)
	local game, _, _, main, _, health, mana, selection = GameParts(kind)
	if not game or InCombatLockdown() then
		return
	end
	U.Quiet(kind.owner, { game }, { health or false, mana or false }, { selection or false })
	U.Silence(game, kind.gameEvents, kind.owner, 0)
	U.Silence(main, kind.gameEvents, kind.owner, 5)
	local tot = GameToT(kind, game)
	if tot then
		local debuffs = {}
		for i = 1, MAX_TOT_DEBUFFS do
			debuffs[i] = rawget(_G, (tot:GetName() or "") .. "Debuff" .. i) or false
		end
		debuffs[#debuffs + 1] = tot
		U.Quiet(kind.totOwner, debuffs, { rawget(tot, "HealthBar") or false, rawget(tot, "ManaBar") or false })
		U.Silence(tot, GAME_EVENTS, kind.totOwner, 2)
	end
end

local function GiveBack(kind)
	U.Return(kind.owner)
	U.Return(kind.totOwner)
end

--------------------------------------------------------------------------------
-- Standing in and going (Unit Frames on and off), as the player frame's: made out of a fight only (secure buttons)
--------------------------------------------------------------------------------

local function Stand(kind)
	if not kind.wanted or kind.standing then
		return
	end
	local f = Build(kind)
	if not f then
		return
	end
	kind.standing = true
	U.own[kind.unit] = f
	U.own[kind.totUnit] = f.totFrame
	if kind.usedGame then
		U.AskReload()
	end
	FadeGame(kind)
	QuietGame(kind)
	Listen(f, true)
	f:Show()
	local tot = f.totFrame
	if tot then
		tot:Show()
		if tot:IsVisible() then
			ToTListen(tot, true)
		end
	end
	O.Update(f)
	MelloUI:Fire("units", kind.key, true)
end

local function Go(kind)
	if kind.wanted or not kind.standing then
		return
	end
	local f = kind.frame
	kind.standing = false
	U.own[kind.unit] = nil
	U.own[kind.totUnit] = nil
	if f then
		Listen(f, false)
		f:Hide()
		local tot = f.totFrame
		if tot then
			ToTListen(tot, false)
			tot:Hide()
		end
	end
	GiveBack(kind)
	kind.usedGame = true
	MelloUI:Fire("units", kind.key, false)
end

for _, kind in ipairs(KINDS) do
	local later = "MelloUI own " .. kind.owner
	local stand, go = function() Stand(kind) end, function() Go(kind) end
	-- on (`login`: the login's own frame, before any module dresses a frame: nothing to ask then)
	kind.Start = function(login)
		if kind.wanted and (kind.standing or login) then
			return
		end
		kind.wanted = true
		if not login or InCombatLockdown() then
			kind.usedGame = true
		end
		Later(stand, later)
	end
	kind.Stop = function()
		kind.wanted = false
		Later(go, later)
	end
	kind.Build, kind.FadeGame, kind.QuietGame = function() return Build(kind) end, function() FadeGame(kind) end,
		function() QuietGame(kind) end
	kind.GiveBack = function() GiveBack(kind) end
	kind.Update = function(f) O.Update(f or kind.frame) end
end

-- (/ufdump own) the target's and the focus's lines
U.dumps[#U.dumps + 1] = function(add)
	for _, kind in ipairs(KINDS) do
		local game, art, _, main = GameParts(kind)
		add(("own %s: %s (standing %s, wanted %s), its target %s"):format(kind.owner,
			tostring(kind.frame and kind.frame:GetName()), tostring(kind.standing), tostring(kind.wanted),
			tostring(kind.tot and kind.tot:GetName())))
		if game then
			add(("game %s: shown %s, art %.2f, main %.2f, mouse %s"):format(kind.game, tostring(game:IsShown()),
				art and K.Alpha(art) or -1, main and K.Alpha(main) or -1, tostring(K.Mouse(game))))
		end
		local n = 0
		for _, owner in ipairs({ kind.owner, kind.totOwner }) do
			for _, had in pairs(U.Silenced(owner)) do
				n = n + #had
			end
		end
		add(("%s events let go: %d"):format(kind.key, n))
	end
end

-- (stage 4) the pieces the pet frame of ours is built and kept with (Modules/UnitFramesPet.lua): one set -- the live
-- layout copied, the game's own code run on ours, the unit's name, portrait, bars and their texts as the target's
K.Path, K.Mirror, K.Game, K.FontLike = Path, Mirror, Game, FontLike
U.Show = { Name = Name, Portrait = Portrait, Health = Health, Power = Power, PowerType = PowerType,
	ManaText = O.ManaText, HealthText = O.HealthText }

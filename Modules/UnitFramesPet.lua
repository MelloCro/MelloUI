--------------------------------------------------------------------------------
-- MelloUI - Unit Frames: the pet frame, MelloUI's own (fr-17 stage 4, 2026-11-01)
--
-- While Unit Frames is on, the pet frame on the screen is ours (MelloUIPetFrame): a secure unit button (a click
-- targets the pet, a right click opens its menu), built as the game's own PetFrame is built -- PetFrame.xml of this
-- client (120 x 49, the target of target's pictures by design: the portrait 37 round at 5,-5, the frame's picture, the
-- threat flash and the attack glow over it, the name at the portrait's right, the health bar 70 x 10 and the mana bar
-- 74 x 7 in the party's masks with their texts, the numbers on the portrait) -- copying the running build's live
-- layout of the game's frame at the build (Units.Parts.Mirror) and updating on the pet's own events as the game's
-- PetFrameMixin does (its name, portrait, bars and their texts through the target's pieces -- Units.Show -- the pet's
-- own threat on its flash, the attack glow pulsing while the pet attacks, the numbers on its portrait). Its bars are our
-- own StatusBars handed the pet's health and power as the game hands them (a secret value goes to the bar as it is).
--
-- It stands ON the game's frame: a child of the game's PetFrame over its rect, at its level. So it shows and hides
-- exactly as the game's does -- the game's own secure code shows its pet frame with the pet (UNIT_PET, PET_UI_UPDATE,
-- the vehicle's exit: kept with it; its UpdateShownState) -- in a fight too, and takes the game frame's place, size and
-- alpha (a child of the game's PlayerFrame, a layout child of its bottom container: Edit Mode, Edit Layout, the
-- installer, the Fader). Nobody's frame moves; the totems and class bars beside it are never touched.
--
-- The game's frame kept away while ours stands in (Units.Fade / Quiet / Silence, the other frames' means): its own
-- pictures (PetPortrait, PetFrameTexture, PetFrameFlash, PetAttackModeTexture) and its frames (the text holders with
-- PetName and PetHitIndicator, its two bars) at alpha 0; out of a fight its mouse off, its bars' hover off and Edit
-- Mode's box unseen and click-through; the events of its own updates let go (its bars', its attack glow's, its
-- numbers'). Kept with it: its show and hide (UNIT_PET, UNIT_EXITED_VEHICLE, PET_UI_UPDATE), and two frames of their
-- own jobs that stay the game's and working -- its debuff row (AuraFrameContainer, on its UNIT_AURA) and the hunter's
-- happiness (PetFrameHappiness: its own events and tooltip). No key written on it or its regions, no hook on them,
-- nothing of it shown, hidden or moved. This client has no pet-target frame.
--
-- Units.PetKind: Start(login) / Stop() with the Unit Frames module (Modules/UnitFrames.lua), as the other kinds.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local U = MelloUI.Units
if not (U and U.Show and U.Parts and U.Parts.Mirror) then
	return
end
local Perf = MelloUI.Perf:Scope("UnitFrames (own pet)")
local Shared = Perf.Shared
local Num = MelloUI.Safe.Number
local K = U.Parts
local Atlas, Tex, Crisp, Font, Holder = K.Atlas, K.Tex, K.Crisp, K.Font, K.Holder
local FillOf, Masked, TextsOn, Yes, Later, Path = K.FillOf, K.Masked, K.TextsOn, K.Yes, K.Later, K.Path
local Show = U.Show

local Pet = { key = "pet", unit = "pet", game = "PetFrame", owner = "pet frame", frame = nil, wanted = false,
	standing = false, usedGame = false }
U.PetKind = Pet   -- (Units.Pet() is the frame on the screen)

-- PetFrame.xml's own pictures (the target of target's, the party's masks: the game's own design)
local ART = {
	frame = "UI-HUD-UnitFrame-TargetofTarget-PortraitOn",
	flash = "UI-HUD-UnitFrame-TargetofTarget-PortraitOn-InCombat",
	attack = "UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Status",
	health = "UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Bar-Health",
	mana = "UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Bar-Mana",
	healthMask = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health-Mask",
	manaMask = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Mana-Mask",
	circleMask = "CircleMask",
}
local HIT = { "NumberFontNormalHuge", 30 }   -- (CombatFeedback_Initialize(self, PetHitIndicator, 30))

--------------------------------------------------------------------------------
-- The pet frame of ours
--------------------------------------------------------------------------------

local function G(name)
	local v = rawget(_G, name)
	return type(v) == "table" and v or nil
end

-- (the game's hit rect where it reads plainly, else PetFrame.xml's: 7, 66, 6, 7)
local function HitRect(f, game)
	local ok, l, r, t, b = pcall(game.GetHitRectInsets, game)
	if ok and Num(l) and Num(r) and Num(t) and Num(b) then
		f:SetHitRectInsets(l, r, t, b)
	else
		f:SetHitRectInsets(7, 66, 6, 7)
	end
end

local function StatusBar(parent, w, h, atlas)
	local b = CreateFrame("StatusBar", nil, parent)
	b:SetSize(w, h)
	b:SetMinMaxValues(0, 1)
	b:SetValue(1)
	b:SetStatusBarTexture(atlas)
	return b
end

function Pet.Build()
	local game = G("PetFrame")
	if Pet.frame or not game or InCombatLockdown() then
		return Pet.frame
	end
	local f = CreateFrame("Button", "MelloUIPetFrame", game, "SecureUnitButtonTemplate")
	U.mine[f] = true
	f:SetAllPoints(game)
	f:SetFrameLevel(game:GetFrameLevel())
	HitRect(f, game)
	f:SetAttribute("unit", "pet")
	f:SetAttribute("*type1", "target")
	f:SetAttribute("*type2", "togglemenu")
	f:RegisterForClicks("AnyUp")
	-- (deadText false: its bar's numbers at none -- the game's pet health bar has no zero text)
	f.unit, f.frameType, f.capNumeric, f.deadText, f.kind = "pet", "TargetofTarget", true, false, Pet
	f:Hide()

	-- the art: the portrait in its round mask, the frame's picture, the threat flash and the attack glow over it
	local portrait = Tex(f, "BACKGROUND", 0)
	portrait:SetSize(37, 37)
	portrait:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -5)
	local pmask = f:CreateMaskTexture(nil, "BACKGROUND")
	Atlas(pmask, ART.circleMask)
	pmask:SetPoint("TOPLEFT", portrait, "TOPLEFT", 0, 0)
	pmask:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", 0, 0)
	Masked(portrait, pmask)
	local art = Tex(f, "BORDER", 0, ART.frame, true)
	art:SetPoint("CENTER", f, "CENTER", 0, 0)
	local flash = Tex(f, "OVERLAY", 0, ART.flash, true)
	flash:SetPoint("TOPLEFT", f, "TOPLEFT", 1, 0)
	flash:Hide()
	local attack = Tex(f, "OVERLAY", 0, ART.attack, true)
	attack:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 1)
	attack:SetBlendMode("ADD")
	attack:Hide()

	-- the texts' holders (the template's two frames over the whole frame): the numbers on the portrait, the name
	local h1 = Holder(f)
	local h2 = Holder(h1)
	local hit = Font(h2, "BORDER", 0, HIT[1])
	hit:SetPoint("TOPLEFT", h2, "TOPLEFT", 5, -5)
	hit:Hide()
	local name = Font(h2, "ARTWORK", 0, "GameFontNormalSmall")
	K.FontLike(name, G("PetName"), "GameFontNormalSmall")
	name:SetSize(68, 10)
	name:SetJustifyH("LEFT")
	name:SetJustifyV("BOTTOM")
	name:SetPoint("TOPLEFT", portrait, "TOPRIGHT", 2, 0)

	-- the bars, their texts and masks
	local health = StatusBar(f, 70, 10, ART.health)
	health:SetPoint("BOTTOMLEFT", portrait, "RIGHT", 2, -3.5)
	local hfill = FillOf(health)
	if hfill then
		hfill:SetDrawLayer("BACKGROUND", 0)   -- (the template's drawLayer)
	end
	local htexts = TextsOn(health, health, { left = 0, right = 0 })
	local hmask = health:CreateMaskTexture(nil, "OVERLAY", nil, 2)
	Atlas(hmask, ART.healthMask, true)
	hmask:SetPoint("TOPLEFT", health, "TOPLEFT", -29, 3)
	Masked(hfill, hmask)
	health.HealthBarMask = hmask
	local mana = StatusBar(f, 74, 7, ART.mana)
	mana:SetPoint("TOPLEFT", health, "BOTTOMLEFT", -4, -1)
	local mtexts = TextsOn(mana, mana, { center = 2, left = 4, right = 0 })
	local mmask = mana:CreateMaskTexture(nil, "OVERLAY", nil, 2)
	Atlas(mmask, ART.manaMask, true)
	mmask:SetPoint("TOPLEFT", mana, "TOPLEFT", -27, 4)
	Crisp(mmask)
	Masked(FillOf(mana), mmask)
	mana.ManaBarMask = mmask
	for _, bar in ipairs({ health, mana }) do
		bar.unit, bar.unitFrame, bar.lockColor, bar.capNumericDisplay = "pet", f, true, true
	end
	-- (TextStatusBar's own keys on the bars: Bar Text fades these and hangs its value on them)
	health.TextString, health.LeftText, health.RightText = htexts.center, htexts.left, htexts.right
	mana.TextString, mana.LeftText, mana.RightText = mtexts.center, mtexts.left, mtexts.right
	health.UpdateTextString, mana.UpdateTextString = Show.HealthText, Show.ManaText
	f.texts = { health = htexts, mana = mtexts }

	-- the game's own keys of a unit frame (UnitFrame_Initialize's, PetFrame.xml's) for the modules that read them
	f.Portrait, f.PortraitMask, f.FrameTexture, f.Flash, f.AttackModeTexture = portrait, pmask, art, flash, attack
	f.Name, f.name, f.HitIndicator, f.HealthBar, f.ManaBar = name, name, hit, health, mana
	f.portrait, f.healthbar, f.manabar, f.threatIndicator = portrait, health, mana, flash
	flash.unit, flash.feedbackUnit = "pet", "pet"
	f.feedbackText, f.feedbackFontHeight = hit, HIT[2]   -- (CombatFeedback_Initialize's)
	f.textHolder = h2
	-- (the game's PetFrame names its parts as globals: Units.PetPart answers ours by these names while it stands in)
	f.parts = { frame = f, texture = art, portrait = portrait, name = name, health = health, mana = mana,
		healthMask = hmask, manaMask = mmask, flash = flash, attack = attack, hit = hit }

	-- the client's build's own layout of its pet frame, copied (anchors onto our twins, sizes, layers, scales)
	local gName = G("PetName")
	local gH2 = gName and gName:GetParent()
	local gH1 = gH2 and gH2:GetParent()
	local gHealth, gMana = G("PetFrameHealthBar"), G("PetFrameManaBar")
	local map = { [game] = f }
	local pairs_ = {
		{ portrait, G("PetPortrait") or Path(game, "Portrait") }, { pmask, Path(game, "PortraitMask") },
		{ art, G("PetFrameTexture") }, { flash, G("PetFrameFlash") }, { attack, G("PetAttackModeTexture") },
		{ h1, gH1 ~= game and gH1 or nil }, { h2, gH2 ~= game and gH2 or nil },
		{ hit, G("PetHitIndicator"), "nosize" }, { name, gName },
		{ health, gHealth }, { htexts.center, G("PetFrameHealthBarText"), "nosize" },
		{ htexts.left, G("PetFrameHealthBarTextLeft"), "nosize" }, { htexts.right, G("PetFrameHealthBarTextRight"), "nosize" },
		{ hmask, G("PetFrameHealthBarMask") },
		{ mana, gMana }, { mtexts.center, G("PetFrameManaBarText"), "nosize" },
		{ mtexts.left, G("PetFrameManaBarTextLeft"), "nosize" }, { mtexts.right, G("PetFrameManaBarTextRight"), "nosize" },
		{ mmask, G("PetFrameManaBarMask") },
	}
	local gFill = function(bar) return type(bar) == "table" and bar.GetStatusBarTexture and bar:GetStatusBarTexture() end
	pairs_[#pairs_ + 1] = { hfill, gFill(gHealth), "look" }
	pairs_[#pairs_ + 1] = { FillOf(mana), gFill(gMana), "look" }
	for _, p in ipairs(pairs_) do
		if p[1] and type(p[2]) == "table" and p[3] ~= "look" then
			map[p[2]] = p[1]
		end
	end
	K.Mirror(pairs_, map)
	f.Update = Pet.Update
	Pet.frame = f
	Pet.Scripts(f)
	return f
end

--------------------------------------------------------------------------------
-- What it shows, as the game's PetFrameMixin shows it: on the pet's own events
--------------------------------------------------------------------------------

-- the attack glow (PET_ATTACK_START: red, pulsing while it shows -- the game's OnUpdate's pulse, ours an engine one;
-- PET_ATTACK_STOP and every update: away)
local function Attack(f, on)
	local glow = f.AttackModeTexture
	if on then
		glow:SetVertexColor(1.0, 0, 0, 1.0)
		glow:Show()
	else
		glow:Hide()
	end
	K.Pulse(f, glow, on)
end

-- (PetFrameMixin:Update: UnitFrame_Update -- the name, portrait, bars, the pet's own threat -- the attack glow away)
function Pet.Update(f)
	f = f or Pet.frame
	if not f or not Yes(UnitExists, f.unit) then
		return
	end
	Show.Name(f)
	Show.Portrait(f)
	Show.PowerType(f)
	Show.Health(f)
	Show.Power(f)
	K.Threat(f)
	U.Notify("UnitFrame_Update", f)
	Attack(f, false)
end

local EVENTS = { "PLAYER_ENTERING_WORLD", "PET_UI_UPDATE", "PET_ATTACK_START", "PET_ATTACK_STOP", "PORTRAITS_UPDATED",
	"CVAR_UPDATE" }
local UNIT_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER",
	"UNIT_DISPLAYPOWER", "UNIT_NAME_UPDATE", "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_CONNECTION",
	"UNIT_THREAT_SITUATION_UPDATE", "UNIT_COMBAT" }

local HANDLERS = {
	PLAYER_ENTERING_WORLD = function(f) Pet.Update(f) end,
	UNIT_PET = function(f) Pet.Update(f) end,
	PET_UI_UPDATE = function(f) Pet.Update(f) end,
	PET_ATTACK_START = function(f) Attack(f, true) end,
	PET_ATTACK_STOP = function(f) Attack(f, false) end,
	PORTRAITS_UPDATED = function(f) Show.Portrait(f) end,
	UNIT_HEALTH = function(f) Show.Health(f) end,
	UNIT_MAXHEALTH = function(f) Show.Health(f) end,
	UNIT_CONNECTION = function(f) Show.Health(f) Show.Power(f) end,
	UNIT_POWER_UPDATE = function(f) Show.Power(f) end,
	UNIT_POWER_FREQUENT = function(f) Show.Power(f) end,
	UNIT_MAXPOWER = function(f) Show.Power(f) end,
	UNIT_DISPLAYPOWER = function(f) Show.PowerType(f) Show.Power(f) end,
	UNIT_NAME_UPDATE = function(f) Show.Name(f) U.Notify("UnitFrame_Update", f) end,
	UNIT_PORTRAIT_UPDATE = function(f) Show.Portrait(f) end,
	UNIT_MODEL_CHANGED = function(f) Show.Portrait(f) end,
	UNIT_THREAT_SITUATION_UPDATE = function(f) K.Threat(f) end,
	UNIT_COMBAT = function(f, _, event, flags, amount, kind) U.Feedback(f, f.textHolder, event, flags, amount, kind) end,
	CVAR_UPDATE = function(f, cvar)
		if cvar == "statusText" or cvar == "statusTextDisplay" then
			U.TextsChanged()
			U.Texts(f)
		end
	end,
}

local OnEvent = Shared("your pet frame (MelloUI's own): its unit's events", function(self, event, ...)
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
		pcall(f.RegisterUnitEvent, f, "UNIT_PET", "player")
		for _, e in ipairs(UNIT_EVENTS) do
			pcall(f.RegisterUnitEvent, f, e, "pet")
		end
	else
		f:UnregisterAllEvents()
	end
end

-- shown with the game's frame (the pet summoned, a zone entered): everything once (PetFrameMixin:OnShow)
local OnShow = Shared("your pet frame shown (the game's own rule shows it)", function(self)
	if Pet.standing then
		Pet.Update(self)
	end
end, "script")

-- (its bars under the mouse)
local function PetHoverAt(f)
	return (f.HealthBar:IsMouseOver() and "health") or (f.ManaBar:IsShown() and f.ManaBar:IsMouseOver() and "mana") or nil
end

function Pet.Scripts(f)
	Perf.SetScript(f, "OnEvent", OnEvent)
	Perf.SetScript(f, "OnShow", OnShow)
	U.Tooltip(f, PetHoverAt)
end

--------------------------------------------------------------------------------
-- The game's frame kept away while ours stands in, and given back
--------------------------------------------------------------------------------

-- the events of the game's pet frame's own updates (PetFrameMixin:OnLoad, UnitFrame_Initialize, its bars,
-- TextStatusBar). Kept with it: its show and hide (UNIT_PET, UNIT_EXITED_VEHICLE, PET_UI_UPDATE) and its debuff row
-- (UNIT_AURA)
local GAME_EVENTS = { "UNIT_NAME_UPDATE", "UNIT_DISPLAYPOWER", "UNIT_PORTRAIT_UPDATE", "PORTRAITS_UPDATED",
	"UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "UNIT_MAXHEALTH", "UNIT_HEAL_PREDICTION", "UNIT_ABSORB_AMOUNT_CHANGED",
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_SUCCEEDED",
	"UNIT_MAX_HEALTH_MODIFIERS_CHANGED", "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE", "PET_ATTACK_START",
	"PET_ATTACK_STOP", "UNIT_COMBAT", "CVAR_UPDATE", "UNIT_HEALTH", "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT",
	"UNIT_MAXPOWER", "UNIT_CONNECTION", "VARIABLES_LOADED", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
	"UNIT_POWER_BAR_SHOW", "UNIT_POWER_BAR_HIDE", "PLAYER_GAINS_VEHICLE_DATA", "PLAYER_LOSES_VEHICLE_DATA" }

-- the game's frame, its parts kept away (its pictures and frames but ours, its debuff row, the happiness and Edit
-- Mode's box), its bars, its box
local function GameParts()
	local game = G("PetFrame")
	if not game then
		return nil
	end
	local keep = { [rawget(game, "AuraFrameContainer") or false] = true, [G("PetFrameHappiness") or false] = true,
		[rawget(game, "Selection") or false] = true }
	local parts, seen = {}, {}
	-- (its named pictures too wherever they stand now: a dresser's replacement may hold one under a holder of its own
	-- and give it back later)
	local named = { G("PetPortrait") or false, G("PetFrameTexture") or false, G("PetFrameFlash") or false,
		G("PetAttackModeTexture") or false }
	for _, r in ipairs(U.Pack(U.Pack(U.Pack({}, false, unpack(named)), nil, game:GetRegions()), nil, game:GetChildren())) do
		if not keep[r] and not seen[r] then
			seen[r] = true
			parts[#parts + 1] = r
		end
	end
	return game, parts, G("PetFrameHealthBar"), G("PetFrameManaBar"), rawget(game, "Selection")
end

-- its parts unseen at once (an alpha: in a fight too); the game's frame away itself, its parts with all in them
function Pet.FadeGame()
	local game, parts = GameParts()
	if game then
		U.Fade(Pet.owner, parts, { game }, parts)
	end
end

-- the rest out of a fight: the mouse off, Edit Mode's box unseen and click-through, the events let go
function Pet.QuietGame()
	local game, _, health, mana, selection = GameParts()
	if not game or InCombatLockdown() then
		return
	end
	U.Quiet(Pet.owner, { game }, { health or false, mana or false }, { selection or false })
	U.Silence(game, GAME_EVENTS, Pet.owner, 0)
	U.Silence(health, GAME_EVENTS, Pet.owner, 1)
	U.Silence(mana, GAME_EVENTS, Pet.owner, 1)
end

function Pet.GiveBack()
	U.Return(Pet.owner)
end

--------------------------------------------------------------------------------
-- Standing in and going (Unit Frames on and off): made out of a fight only (a secure button)
--------------------------------------------------------------------------------

local function Stand()
	if not Pet.wanted or Pet.standing then
		return
	end
	local f = Pet.Build()
	if not f then
		return
	end
	Pet.standing = true
	U.own.pet = f
	if Pet.usedGame then
		U.AskReload()
	end
	Pet.FadeGame()
	Pet.QuietGame()
	Listen(f, true)
	f:Show()
	Pet.Update(f)
	-- (a pet attacking as ours stands in: its glow, as the game's would show it)
	if Yes(rawget(_G, "IsPetAttackActive")) then
		Attack(f, true)
	end
	MelloUI:Fire("units", "pet", true)
	-- (a dresser that dressed the game's frame meanwhile lays its look again on the bus -- the painted skin gives its
	-- faded pictures their alpha back as it goes: kept away again, the first alphas kept to give back)
	Pet.FadeGame()
end

local function Go()
	if Pet.wanted or not Pet.standing then
		return
	end
	local f = Pet.frame
	Pet.standing = false
	U.own.pet = nil
	if f then
		Listen(f, false)
		Attack(f, false)
		f:Hide()
	end
	Pet.GiveBack()
	Pet.usedGame = true
	MelloUI:Fire("units", "pet", false)
end

-- on (`login`: the login's own frame, before any module dresses a frame: nothing to ask then)
function Pet.Start(login)
	if Pet.wanted and (Pet.standing or login) then
		return
	end
	Pet.wanted = true
	if not login or InCombatLockdown() then
		Pet.usedGame = true
	end
	Later(Stand, "MelloUI own pet frame")
end

function Pet.Stop()
	Pet.wanted = false
	Later(Go, "MelloUI own pet frame")
end

-- (/ufdump own) the pet's lines
U.dumps[#U.dumps + 1] = function(add)
	local game, parts = GameParts()
	add(("own pet frame: %s (standing %s, wanted %s)"):format(tostring(Pet.frame and Pet.frame:GetName()),
		tostring(Pet.standing), tostring(Pet.wanted)))
	if game then
		local seen = 0
		for _, r in ipairs(parts) do
			if K.Alpha(r) > 0 then
				seen = seen + 1
			end
		end
		add(("game PetFrame: shown %s, %d parts, %d at alpha above 0, mouse %s"):format(tostring(game:IsShown()), #parts,
			seen, tostring(K.Mouse(game))))
	end
	local n = 0
	for _, had in pairs(U.Silenced(Pet.owner)) do
		n = n + #had
	end
	add(("pet events let go: %d"):format(n))
end

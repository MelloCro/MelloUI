--------------------------------------------------------------------------------
-- MelloUI - Group Frames: you as a normal party frame while solo (the user,
-- 2026-10-09: "when choosing in a party "party frames" if im not in a raid
-- group, the party frames should look like normal party frames even when im
-- solo" -- to see how healing looks on them)
--
-- The game shows its normal party frames in a party only. While In A Party is
-- Party Frames (and Show Yourself While Solo is on), you alone get a frame
-- that is the game's party member frame: the replica ConfigPreview.MakeParty
-- builds (the game's template's keys and geometry, PartyFrameTemplates.xml),
-- built on a secure unit button of ours for "player" (a click targets you, a
-- right click opens your menu), dressed by the unit frame skin as the members
-- are (UnitFramePanel:DressStandIn), its bars in the look the settings give
-- the members' (Bar Textures), filled with your health and power as the game
-- hands them (a secret value goes to the bar as it is, never read), your
-- portrait (or Class Icons' medallion), your name, and the members' aura row
-- (the game's aura container: up to four debuffs, as the members show them).
-- It stands where the game's first member stands: the party container's top
-- left (Edit Layout's "Party Frames", where the game's party frame is held:
-- GroupHeaders.lua), at the game's party frame's scale, in the container (it
-- fades with the party frames), and shows by the game's state driver
-- ("[group] hide; show": in a fight too). It is a host as
-- the members are: the indicators (kind "party"), the Designer's party parts,
-- Healer Frames' heals and debuff glow, and Heal Flight and Frame Effects
-- (Headers:Hosts / HostOf: kind "party", its portrait and ring).
-- Made the first time it is wanted, never before; its events only while it
-- is wanted.
--   Solo:Update()            wanted or not: made, placed and driven, or put away
--   Solo:Repaint()           its look again (a setting of the looks)
--   Solo:Shown() -> frame    the frame while it shows, else nil
--   Solo.frame               the frame (nil until made)
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Perf = MelloUI.Perf:Scope("MelloUI_GroupFrames (solo)")
local Shared = Perf.Shared
local Text = MelloUI.Safe.Text
local Num = MelloUI.Safe.Number
local RD = ns.RD
local Looks = ns.Looks

local Solo = { frame = nil, driven = false, listening = false, editing = false }
ns.Solo = Solo

local UNIT = "player"
local RULE = "[group] hide; show"
-- the members' aura row (PartyAuraFrameTemplate: 15 x 15, 2 apart, its
-- border the debuff overlay's; MAX_PARTY_DEBUFFS four; the row at 48,-43)
local AURA = { size = 15, gap = 2, max = 4, x = 48, y = -43 }
local DEBUFF_BORDER = "Interface\\Buttons\\UI-Debuff-Overlays"   -- look-ok: the game's party aura border
local BORDER_COORDS = { 0.296875, 0.5703125, 0, 0.515625 }
-- the game's leader and guide icons (PartyMemberOverlay's)
local GROUP_ICONS = { LeaderIcon = "UI-HUD-UnitFrame-Player-Group-LeaderIcon",
	GuideIcon = "UI-HUD-UnitFrame-Player-Group-GuideIcon" }
-- the modules whose settings change its look
local LOOKS = { BarTextures = true, UnitFrames = true, ClassIcons = true, UnitFramePanel = true, HealerFrames = true }

local function Later(fn, key)
	local K = MelloUI.Kit
	if InCombatLockdown() and K and K.WhenOutOfCombat then
		K:WhenOutOfCombat(fn, key)
	elseif not InCombatLockdown() then
		fn()
	end
end

local function Call(obj, method, ...)
	local fn = obj and obj[method]
	if type(fn) ~= "function" then
		return false
	end
	return (pcall(fn, obj, ...))
end

local function Enum2(group, name)
	local E = rawget(_G, "Enum")
	local t = type(E) == "table" and E[group]
	return type(t) == "table" and t[name] or nil
end

-- wanted: the module on, Party Frames the choice in a party, you shown solo
local function Wanted()
	local H = ns.Headers
	local db = RD.DB()
	return (H and H.S and H.S.on and db.partyStyle == "party" and db.solo) and true or false
end

--------------------------------------------------------------------------------
-- The aura row: the game's aura container, its frames dressed as the members'
--------------------------------------------------------------------------------

local function DressAura(b)
	b:SetSize(AURA.size, AURA.size)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(b)
	local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	cd:SetPoint("CENTER", b, "CENTER", 0, -1)
	cd:SetSize(AURA.size, AURA.size)
	Call(cd, "SetReverse", true)
	Call(cd, "SetHideCountdownNumbers", true)
	local count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	count:SetJustifyH("RIGHT")
	count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 5, 0)
	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetTexture(DEBUFF_BORDER)
	border:SetTexCoord(BORDER_COORDS[1], BORDER_COORDS[2], BORDER_COORDS[3], BORDER_COORDS[4])
	border:SetPoint("TOPLEFT", b, "TOPLEFT", -1, 1)
	border:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
	Call(b, "SetIcon", icon)
	Call(b, "SetDurationCooldown", cd)
	Call(b, "SetApplicationCount", count)
	local style = Enum2("CustomAuraButtonDispelTypeTextureStyle", "PreserveAsset")
	if style ~= nil then
		Call(b, "AddDispelTypeTexture", border, { style = style, showWhenHarmful = true, showWithoutDispelType = true })
	end
end

local function MakeAuras(f)
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, f, "CustomAuraContainerTemplate")
	if not ok or type(c) ~= "table" or type(c.AddAuraGroup) ~= "function" then
		return nil
	end
	c:SetPoint("TOPLEFT", f, "TOPLEFT", AURA.x, AURA.y)
	c:SetSize(AURA.size, AURA.size)
	-- (the members show their buffs instead where the game says so)
	local buffs = rawget(_G, "PARTY_FRAME_SHOW_BUFFS") and true or false
	local sort = rawget(_G, "AuraContainerSortMethod")
	local opts = { maxFrameCount = AURA.max, initializeFrame = DressAura,
		layout = { elementSpacing = AURA.gap, elementWidth = AURA.size, elementHeight = AURA.size } }
	if not buffs and type(sort) == "table" then
		opts.sortMethod = sort.UnitFrameDebuff
	end
	if not Call(c, "AddAuraGroup", "auras", buffs and "HELPFUL" or "HARMFUL", opts) then
		return nil
	end
	Call(c, "SetUnit", UNIT)
	return c
end

--------------------------------------------------------------------------------
-- Painting
--------------------------------------------------------------------------------

local function Module(name)
	local m = MelloUI:GetModule(name)
	return (m and m.isEnabled and m.db) and m or nil
end

-- the health bar's colour as Bar Textures gives the members' (nil: the one
-- the look put on stays -- the art's own, or its green)
local function Colour(f)
	local bt = Module("BarTextures")
	if not (bt and bt.LiveHealthColor) then
		return
	end
	local hb = f.HealthBarContainer.HealthBar
	local ok, r, g, b = pcall(bt.LiveHealthColor, hb)
	if ok and r ~= nil then
		pcall(hb.SetStatusBarColor, hb, r, g, b)
	end
end

local function ByHealth()
	local bt = Module("BarTextures")
	return bt and bt.db.healthColor == "health" or false
end

-- the bars' values, as the game hands them
local function Health(f)
	local hb = f.HealthBarContainer.HealthBar
	pcall(hb.SetMinMaxValues, hb, 0, UnitHealthMax(UNIT))
	pcall(hb.SetValue, hb, UnitHealth(UNIT))
	if ByHealth() then
		Colour(f)
	end
end

local function Power(f)
	local mb = f.ManaBar
	pcall(mb.SetMinMaxValues, mb, 0, UnitPowerMax(UNIT))
	pcall(mb.SetValue, mb, UnitPower(UNIT))
end

-- your portrait (the game's), or Class Icons' medallion while its portraits
-- are on (the look put that on)
local function Portrait(f)
	local ci = Module("ClassIcons")
	if ci and ci.db.portraits then
		return
	end
	f.Portrait:SetTexCoord(0, 1, 0, 1)
	pcall(SetPortraitTexture, f.Portrait, UNIT)
end

-- the look the settings give the members' (the replica's painter, with your
-- plain facts: name, class, power type), then your values
local function Look(f)
	local CP = MelloUI.ConfigPreview
	if not (CP and CP.PaintParty and CP.PartySample) then
		return
	end
	local s = CP.PartySample()
	local okN, name = pcall(UnitName, UNIT)
	local okC, _, class = pcall(UnitClass, UNIT)
	local okP, _, token = pcall(UnitPowerType, UNIT)
	s.first, s.last = okN and Text(name) or "", nil
	s.class = okC and Text(class) or nil
	s.token = okP and Text(token) or "MANA"
	s.display = nil
	s.health, s.max, s.power, s.powerMax = 1, 1, 1, 1
	pcall(CP.PaintParty, f, s)
	if okN and not Text(name) then
		pcall(f.Name.SetText, f.Name, name)   -- (a secret name as it is)
	end
	Portrait(f)
	Colour(f)
	Health(f)
	Power(f)
end

local function Paint(f)
	if f and f:IsShown() then
		Look(f)
	end
end

--------------------------------------------------------------------------------
-- Its place: where the game's first member stands
--------------------------------------------------------------------------------

local function EffectiveScale(region)
	if type(region) ~= "table" or type(region.GetEffectiveScale) ~= "function" then
		return nil
	end
	local ok, s = pcall(region.GetEffectiveScale, region)
	s = ok and Num(s) or nil
	return (s and s > 0) and s or nil
end

local function Place(f)
	local parent = f:GetParent()
	local pe = EffectiveScale(parent) or 1
	local want = EffectiveScale(rawget(_G, "PartyFrame")) or pe
	f:SetScale(want / pe)
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
end

--------------------------------------------------------------------------------
-- Made once, its events while wanted
--------------------------------------------------------------------------------

local UNIT_EVENTS = { UNIT_HEALTH = Health, UNIT_MAXHEALTH = Health, UNIT_POWER_UPDATE = Power,
	UNIT_MAXPOWER = Power, UNIT_DISPLAYPOWER = Look, UNIT_NAME_UPDATE = Look, UNIT_PORTRAIT_UPDATE = Portrait }
-- (a place to read again: the game's party frame laid out by Edit Mode, the
-- world entered, the UI's scale)
local PLACE_EVENTS = { UI_SCALE_CHANGED = true, PLAYER_ENTERING_WORLD = true, EDIT_MODE_LAYOUTS_UPDATED = true }

local function PlaceNow()
	if Solo.frame and Solo.driven then
		Place(Solo.frame)
	end
end

local events = nil
local OnEvent = Shared("the solo party frame's events", function(_, event)
	local f = Solo.frame
	if not f then
		return
	end
	if PLACE_EVENTS[event] then
		Later(PlaceNow, "Group Frames: the solo frame's place")
		Paint(f)
		return
	end
	if not f:IsShown() then
		return
	end
	local paint = UNIT_EVENTS[event]
	if paint then
		paint(f)
	elseif event == "PORTRAITS_UPDATED" then
		Portrait(f)
	end
end, "script")

local function Listen(on)
	if on == Solo.listening then
		return
	end
	Solo.listening = on
	if on then
		if not events then
			events = CreateFrame("Frame")
			Perf.SetScript(events, "OnEvent", OnEvent)
		end
		for e in pairs(UNIT_EVENTS) do
			pcall(events.RegisterUnitEvent, events, e, UNIT)
		end
		pcall(events.RegisterEvent, events, "PORTRAITS_UPDATED")
		for e in pairs(PLACE_EVENTS) do
			pcall(events.RegisterEvent, events, e)
		end
	elseif events then
		events:UnregisterAllEvents()
	end
end

-- the look's settings (one listener each, made once)
local hooked = false
local function Hook()
	if hooked then
		return
	end
	hooked = true
	MelloUI:On("setting", function(module)
		if LOOKS[module] then
			Solo:Repaint()
		end
	end, "GroupFrames.solo")
	MelloUI:On("module", function(module)
		if LOOKS[module] then
			Solo:Repaint()
		end
	end, "GroupFrames.solo")
	-- Edit Mode moves the game's party frame (and shows its own sample members
	-- there): ours away while it is open, at the new place after
	MelloUI:On("editmode", function(entering)
		Solo.editing = entering and true or false
		Solo:Update()
	end, "GroupFrames.solo")
end

-- the skin's dressing, Healer Frames' heals and glow, the indicators, the
-- parts (each idempotent: asked again when the look comes on later)
local function Dress(f)
	local ufp = MelloUI:GetModule("UnitFramePanel")
	if ufp and ufp.DressStandIn then
		pcall(ufp.DressStandIn, ufp, f)
	end
	local hf = MelloUI:GetModule("HealerFrames")
	if hf and hf.Heals then
		local hb = f.HealthBarContainer.HealthBar
		pcall(hf.Heals, hf, hb, function()
			return UNIT
		end)
		pcall(hf.Glow, hf, f, "party")
	end
	if ns.Parts then
		ns.Parts:Lay(f, "party", true)
	end
end

local function Make()
	local CP = MelloUI.ConfigPreview
	local H = ns.Headers
	local parent = H and H.containers and H.containers.party
	if not (CP and CP.MakeParty and parent) then
		return nil
	end
	local f = CreateFrame("Button", "MelloUIGroupSoloParty", parent, "SecureUnitButtonTemplate")
	f:Hide()
	f:SetAttribute("unit", UNIT)
	f:SetAttribute("*type1", "target")
	f:SetAttribute("*type2", "togglemenu")
	f:SetAttribute("toggleForVehicle", false)
	f:RegisterForClicks("AnyUp")
	if not pcall(CP.MakeParty, parent, f) then
		return nil
	end
	f.unit = UNIT
	-- (its health bar keeps its art's colour, as the game's own: Bar Textures
	-- leaves such a bar white under its green)
	f.HealthBarContainer.HealthBar.lockColor = true
	-- the overlay's role, leader and guide icons (none solo; the Designer's
	-- Role Icon and Leader Icon parts lay them)
	local ov = f.PartyMemberOverlay
	local role = ov:CreateTexture(nil, "OVERLAY")
	role:SetSize(12, 12)
	role:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
	role:Hide()
	ov.RoleIcon = role
	for key, atlas in pairs(GROUP_ICONS) do
		local icon = ov:CreateTexture(nil, "OVERLAY")
		Call(icon, "SetAtlas", atlas, true)
		icon:SetPoint("BOTTOM", f, "TOP", -10, -6)
		icon:Hide()
		ov[key] = icon
	end
	f.AuraFrameContainer = MakeAuras(f)
	Perf.HookScript(f, "OnShow", Shared("the solo party frame shown", function(self)
		Look(self)
	end, "script"))
	Solo.frame = f
	Dress(f)
	if ns.Indicators then
		ns.Indicators:Host(f, UNIT, Looks.Fill(f.HealthBarContainer.HealthBar), "party")
	end
	return f
end

local function Drive(f, on)
	if on == Solo.driven then
		return
	end
	Solo.driven = on
	if on then
		RegisterStateDriver(f, "visibility", RULE)
	else
		UnregisterStateDriver(f, "visibility")
		f:Hide()
	end
	if f.AuraFrameContainer then
		Call(f.AuraFrameContainer, "SetAuraGroupEnabled", "auras", on)
	end
end

local function UpdateNow()
	local want = Wanted()
	local f = Solo.frame
	if want and not f then
		Hook()
		f = Make()
	end
	if not f then
		return
	end
	local on = want and not Solo.editing
	if on then
		Place(f)
	end
	Drive(f, on)
	Listen(on)
	if on then
		Paint(f)
	end
end

function Solo:Update()
	Later(UpdateNow, "Group Frames: the solo party frame")
end

local function RepaintNow()
	local f = Solo.frame
	if f and Solo.driven then
		Dress(f)
		Paint(f)
	end
end

function Solo:Repaint()
	if self.frame and self.driven then
		Later(RepaintNow, "Group Frames: the solo party frame's look")
	end
end

function Solo:Shown()
	local f = self.frame
	return (f and self.driven and f:IsVisible()) and f or nil
end

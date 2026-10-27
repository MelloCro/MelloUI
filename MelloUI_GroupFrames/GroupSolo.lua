--------------------------------------------------------------------------------
-- MelloUI - Group Frames: you as a normal party frame while solo (the user,
-- 2026-10-09: "when choosing in a party "party frames" if im not in a raid
-- group, the party frames should look like normal party frames even when im
-- solo" -- to see how healing looks on them)
--
-- The game shows its normal party frames in a party only. While In A Party is
-- Party Frames (and Show Yourself While Solo is on), you alone get a frame
-- that is the game's party member frame: the replica ConfigPreview's
-- 'unitframe' kind builds as its party sample (CP.Build, painted with
-- CP.Values / CP.Paint; the game's template's keys and geometry,
-- PartyFrameTemplates.xml),
-- built on a secure unit button of ours for "player" (a click targets you, a
-- right click opens your menu), dressed as the members are (Unit Frames'
-- M:DressStandIn, with the painted skin's dressing while it is on), its bars in the look the settings give
-- the members' (Bar Textures), filled with your health and power as the game
-- hands them (a secret value goes to the bar as it is, never read), your
-- portrait (or Class Icons' medallion), your name, and the members' aura row
-- (the game's aura container: up to four debuffs, as the members show them).
-- It stands where the game's first member stands: the party container's top
-- left (Edit Layout's "Party Frames", where the game's party frame is held:
-- GroupHeaders.lua), at the game's party frame's scale, in the container (it
-- fades with the party frames), and shows by the game's state driver
-- ("[group] hide; show": in a fight too). With Show Yourself In Your Party
-- (2026-10-25, the user: the option did nothing on the Portraits look -- the
-- game's party frames never show you) it shows in a party too, at the top,
-- the game's members stacked under it (GroupHeaders.lua StackMembers:
-- Solo.InParty), with your role and the leader's crown as theirs. It is a host as
-- the members are: the indicators (kind "party"), the Designer's party parts,
-- Healer Frames' heals and debuff glow, and Heal Flight and Frame Effects
-- (Headers:Hosts / HostOf: kind "party", its portrait and ring).
-- Made the first time it is wanted, never before; its events only while it
-- is wanted.
--   Solo:Update()            wanted or not: made, placed and driven, or put away
--   Solo:Repaint()           its look again (a setting of the looks)
--   Solo:Shown() -> frame    the frame while it shows, else nil
--   Solo.InParty() -> bool   it stands at the top of your party now (the settings and the group's state)
--   Solo.frame               the frame (nil until made)
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Perf = MelloUI.Perf:Scope("MelloUI_GroupFrames (solo)")
local Shared = Perf.Shared
local Text = MelloUI.Safe.Text
local Num = MelloUI.Safe.Number
local IsSecret = MelloUI.Safe.IsSecret
local RD = ns.RD
local Looks = ns.Looks
local Button = ns.Button

local Solo = { frame = nil, driven = false, rule = nil, listening = false, editing = false }
ns.Solo = Solo

local UNIT = "player"
-- when it shows: solo (Show Yourself While Solo), in a party (Show Yourself In Your Party), or both; never in a raid
-- (Group Frames' raid frames show there)
local RULES = { solo = "[group] hide; show", party = "[group:raid] hide; [group] show; hide",
	both = "[group:raid] hide; show" }
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

-- wanted: the module on, Party Frames the choice in a party, you shown solo or in your party
local function Wanted()
	local H = ns.Headers
	local db = RD.DB()
	return (H and H.S and H.S.on and db.partyStyle == "party" and (db.solo or db.showPlayer)) and true or false
end

local function Rule()
	local db = RD.DB()
	return RULES[db.solo and (db.showPlayer and "both" or "solo") or "party"]
end

function Solo.InParty()
	local okG, grouped = pcall(IsInGroup)
	local okR, raid = pcall(IsInRaid)
	return (Wanted() and RD.DB().showPlayer and not Solo.editing and okG and grouped == true
		and not (okR and raid == true)) and true or false
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
	-- (retail: a click goes through to the frame -- click casting -- the hover still its tooltip)
	Looks.ClickThrough(b)
end

-- an aura row dressed as the members' (the game's aura container: up to four,
-- 2 apart), `filter`'s auras of `unit`, sorted by `sort` (nil: the game's own
-- order), placed by the SetPoint arguments `...` (before its group: the game
-- holds a container with aura groups to its own layout)
function Solo.AuraRow(parent, filter, unit, sort, ...)
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
	if not ok or type(c) ~= "table" or type(c.AddAuraGroup) ~= "function" then
		return nil
	end
	c:SetPoint(...)
	c:SetSize(AURA.size, AURA.size)
	local opts = { maxFrameCount = AURA.max, initializeFrame = DressAura, sortMethod = sort,
		layout = { elementSpacing = AURA.gap, elementWidth = AURA.size, elementHeight = AURA.size } }
	if not Call(c, "AddAuraGroup", "auras", filter, opts) then
		return nil
	end
	Call(c, "SetUnit", unit)
	return c
end

local function MakeAuras(f)
	-- (the members show their buffs instead where the game says so)
	local buffs = rawget(_G, "PARTY_FRAME_SHOW_BUFFS") and true or false
	local sort = rawget(_G, "AuraContainerSortMethod")
	return Solo.AuraRow(f, buffs and "HELPFUL" or "HARMFUL", UNIT,
		(not buffs and type(sort) == "table") and sort.UnitFrameDebuff or nil, "TOPLEFT", f, "TOPLEFT", AURA.x, AURA.y)
end

-- (retail, never shipped: the user, 2026-10-24, "this mouseover container that shows the buffs instead of just
-- showing them under it, which makes it a problem to click cast heal") the game's party members show their buffs
-- only in a box on mouseover (PartyMemberBuffTooltip, which GroupHeaders.lua puts away there): a row of their buffs
-- under the frame instead, right after the game's debuff row -- in it, so the Designer's Buffs & Debuffs part moves,
-- sizes and hides both. Made out of a fight (the caller's), its unit followed (`unit`: the member's now)
local buffRows = setmetatable({}, { __mode = "k" })   -- [member] = its row
-- (2026-10-24, the user: the preview "a accurate representation of the actual unitframes"; the solo frame's buffs
-- sat a line under its debuffs, the members' after theirs) our solo frame's debuff row is a game aura container --
-- nothing may be anchored to it -- so its buffs are a second group in it, flowing after the debuffs on their line
-- (the container lays its groups in turn, groupSpacing apart): as the members show them, and moved, sized and hidden
-- with the Buffs & Debuffs part by being in it
local ownBuffs = setmetatable({}, { __mode = "k" })   -- [our solo frame] = its debuff container, the buffs in it
local function OwnBuffs(f, unit)
	local c = rawget(f, "AuraFrameContainer")
	if ownBuffs[f] or InCombatLockdown() or not (type(c) == "table" and type(c.AddAuraGroup) == "function") then
		return ownBuffs[f]
	end
	local opts = { maxFrameCount = AURA.max, initializeFrame = DressAura, layout = { elementSpacing = AURA.gap,
		elementWidth = AURA.size, elementHeight = AURA.size, groupSpacing = AURA.gap } }
	if not Call(c, "AddAuraGroup", "buffs", "HELPFUL", opts) then
		return nil
	end
	Call(c, "SetUnit", unit or UNIT)
	ownBuffs[f] = c
	return c
end

function Solo.BuffRow(member, unit)
	if not RD.Retail() or type(member) ~= "table" then
		return nil
	end
	if member == Solo.frame then
		return OwnBuffs(member, unit)
	end
	local row = buffRows[member]
	if not row then
		if InCombatLockdown() then
			return nil
		end
		local debuffs = rawget(member, "AuraFrameContainer")
		if not (type(debuffs) == "table" and debuffs.CreateTexture) then
			return nil
		end
		row = Solo.AuraRow(debuffs, "HELPFUL", unit or UNIT, nil, "TOPLEFT", debuffs, "TOPRIGHT", AURA.gap, 0)
		if not row then
			return nil
		end
		buffRows[member] = row
		row.unit = unit or UNIT
	elseif unit and row.unit ~= unit and not InCombatLockdown() then
		if Call(row, "SetUnit", unit) then
			row.unit = unit
		end
	end
	return row
end

-- every member's buff row on or off (Party Frames the choice, the module on)
function Solo.BuffRowsOn(on)
	for _, row in pairs(buffRows) do
		Call(row, "SetAuraGroupEnabled", "auras", on and true or false)
		row:SetShown(on and true or false)
	end
end
Solo.buffRows, Solo.ownBuffs = buffRows, ownBuffs   -- (the tests', the party dump's)

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
	local s = CP and CP.Values and CP.Paint and CP.Values("unitframe", "party")
	if not s then
		return
	end
	local okN, name = pcall(UnitName, UNIT)
	local okC, _, class = pcall(UnitClass, UNIT)
	local okP, _, token = pcall(UnitPowerType, UNIT)
	s.first, s.last = okN and Text(name) or "", nil
	s.class = okC and Text(class) or nil
	s.token = okP and Text(token) or "MANA"
	s.display = nil
	s.health, s.max, s.power, s.powerMax = 1, 1, 1, 1
	pcall(CP.Paint, "unitframe", f, "party", s)
	if okN and not Text(name) then
		pcall(f.Name.SetText, f.Name, name)   -- (a secret name as it is)
	end
	Portrait(f)
	Colour(f)
	Health(f)
	Power(f)
	Solo.Group(f)
end

-- in a party: your role and the leader's crown (the guide's in a group from the dungeon finder), as the game's members
-- show theirs (PartyMemberFrame.lua UpdateAssignedRoles / UpdateLeader; the role in the members' sharp picture,
-- Button.RoleAtlas); solo: none. Shown or hidden here, faded by the Designer's parts (their alpha)
function Solo.Group(f)
	local ov = f.PartyMemberOverlay
	local okG, grouped = pcall(IsInGroup)
	grouped = okG and grouped == true
	local okR, role = pcall(UnitGroupRolesAssigned, UNIT)
	local atlas = grouped and okR and Button.RoleAtlas(Text(role)) or nil
	if atlas then
		Call(ov.RoleIcon, "SetAtlas", atlas)
	end
	ov.RoleIcon:SetShown(atlas ~= nil)
	local okL, lead = pcall(UnitIsGroupLeader, UNIT)
	lead = grouped and okL and not IsSecret(lead) and lead == true
	local okF, guide = pcall(HasLFGRestrictions)
	guide = okF and not IsSecret(guide) and guide == true
	ov.LeaderIcon:SetShown(lead and not guide)
	ov.GuideIcon:SetShown(lead and guide)
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

-- (in the game's first member's place: its party frame's padding -- PartyFrame.lua UpdatePaddingAndLayout; read only)
local function Place(f)
	local parent = f:GetParent()
	local pf = rawget(_G, "PartyFrame")
	local pe = EffectiveScale(parent) or 1
	local want = EffectiveScale(pf) or pe
	local left = type(pf) == "table" and Num(rawget(pf, "leftPadding")) or 0
	local top = type(pf) == "table" and Num(rawget(pf, "topPadding")) or 0
	f:SetScale(want / pe)
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", parent, "TOPLEFT", left, -top)
end

--------------------------------------------------------------------------------
-- Made once, its events while wanted
--------------------------------------------------------------------------------

local UNIT_EVENTS = { UNIT_HEALTH = Health, UNIT_MAXHEALTH = Health, UNIT_POWER_UPDATE = Power,
	UNIT_MAXPOWER = Power, UNIT_DISPLAYPOWER = Look, UNIT_NAME_UPDATE = Look, UNIT_PORTRAIT_UPDATE = Portrait }
-- (a place to read again: the game's party frame laid out by Edit Mode, the
-- world entered, the UI's scale)
local PLACE_EVENTS = { UI_SCALE_CHANGED = true, PLAYER_ENTERING_WORLD = true, EDIT_MODE_LAYOUTS_UPDATED = true }
-- (your role and the leader in a party: Solo.Group)
local GROUP_EVENTS = { GROUP_ROSTER_UPDATE = true, PLAYER_ROLES_ASSIGNED = true, PARTY_LEADER_CHANGED = true }

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
	elseif GROUP_EVENTS[event] then
		Solo.Group(f)
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
		for e in pairs(GROUP_EVENTS) do
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
	local ufp = MelloUI:GetModule("UnitFrames")
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
	if not (CP and CP.Kind and CP.Kind("unitframe") and CP.Build and parent) then
		return nil
	end
	local f = CreateFrame("Button", "MelloUIGroupSoloParty", parent, "SecureUnitButtonTemplate")
	f:Hide()
	f:SetAttribute("unit", UNIT)
	f:SetAttribute("*type1", "target")
	f:SetAttribute("*type2", "togglemenu")
	f:SetAttribute("toggleForVehicle", false)
	f:RegisterForClicks("AnyUp")
	local okB, made = pcall(CP.Build, "unitframe", parent, "party", f)
	if not (okB and made) then
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
	if MelloUI.FrameHover then
		MelloUI.FrameHover.Attach(f)   -- (1.2.4: the mouseover highlight)
	end
	-- (retail: your buffs after your debuffs, as the members' -- Solo.BuffRow)
	Solo.BuffRow(f, UNIT)
	Dress(f)
	if ns.Indicators then
		ns.Indicators:Host(f, UNIT, Looks.Fill(f.HealthBarContainer.HealthBar), "party")
	end
	return f
end

local function Drive(f, on)
	local rule = on and Rule() or nil
	if on == Solo.driven and rule == Solo.rule then
		return
	end
	local was = Solo.driven
	Solo.driven, Solo.rule = on, rule
	if on then
		RegisterStateDriver(f, "visibility", rule)
	else
		UnregisterStateDriver(f, "visibility")
		f:Hide()
	end
	if on == was then
		return   -- (only its rule changed)
	end
	if f.AuraFrameContainer then
		Call(f.AuraFrameContainer, "SetAuraGroupEnabled", "auras", on)
	end
	if ownBuffs[f] then
		Call(f.AuraFrameContainer, "SetAuraGroupEnabled", "buffs", on)
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

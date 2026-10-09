--------------------------------------------------------------------------------
-- MelloUI - Group Frames: the headers (stage 1 of MelloUI's own group frames,
-- docs/plans/raid-frame-designer.md "Stage 1 design")
--
-- Two of the game's secure group headers (SecureGroupHeaderTemplate; their
-- unit buttons SecureUnitButtonTemplate -- a click targets, a right click
-- opens the unit's menu):
--   party   you (Show Yourself In Your Party) and your party; you alone while
--           solo (Show Yourself While Solo: the header's own SOLO) -- while In
--           A Party is Group Frames; under Party Frames the game's own in a
--           party, and you alone as a normal party frame (GroupSolo.lua)
--   raid    the raid, one list: by group, role or class, so many per column
--           (or row), the columns (rows) side by side
-- Each in a container on MelloUI's mover (Edit Layout: "Party Frames", "Raid
-- Frames"), where the game's own stand by default. Every button is made out
-- of a fight when the headers are made (the header's startingIndex walked back
-- over all its buttons once), then dressed in Lua (GroupButton.lua): nothing
-- is made in a fight. A header shows by the game's state driver ("[group:raid]
-- hide; show" / "[group:raid] show; hide"), in a fight too. Their layout and
-- the buttons' size are set out of a fight only: a change in a fight waits for
-- its end. A button's unit is the header's (its "unit" attribute, followed by
-- an attribute hook); the units' events reach the buttons that show them.
-- The game's party and raid frames: faded to nothing and click-through, out
-- of a fight; given back when the module goes off. Nothing of theirs is laid
-- out or rebuilt. Under In A Party: Party Frames the game's normal party
-- frames show instead of our party, at the party container's place (Edit
-- Layout's "Party Frames": the party moves there only, whichever frames show
-- it).
--   Headers:Start() / Stop()   on and off
--   Headers:Layout()           the layout settings again (a fight: later)
--   Headers:Repaint()          every button painted again
--   Headers:Blizzard()         the game's frames hidden or given back
--   Headers:Buttons() -> list  every button made
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Perf = MelloUI.Perf:Scope("MelloUI_GroupFrames (headers)")
local Shared = Perf.Shared
local hooksecurefunc = Perf.hooksecurefunc
local Text = MelloUI.Safe.Text
local Num = MelloUI.Safe.Number
local ScreenRect = MelloUI.Safe.ScreenRect
local RD = ns.RD
local Button = ns.Button
local Looks = ns.Looks

local H = {}
ns.Headers = H

local TEXT = { party = "Party Frames", raid = "Raid Frames",
	partyNote = "The game's normal party frames stand here too (In A Party: Party Frames): move them here, not in Edit Mode." }
local COUNT = { party = 5, raid = 40 }
local ROLE_ORDER = "TANK,HEALER,DAMAGER,NONE"
local CLASS_ORDER = "WARRIOR,DEATHKNIGHT,PALADIN,MONK,PRIEST,SHAMAN,DRUID,ROGUE,MAGE,WARLOCK,HUNTER,DEMONHUNTER,EVOKER"
local GROUPS = "1,2,3,4,5,6,7,8"

-- (a button made by the header in a fight -- never, all are made before --
-- sized and made clickable in the restricted environment by this snippet)
local INIT = [[
	local header = self:GetParent()
	self:SetWidth(header:GetAttribute("mello-width") or 80)
	self:SetHeight(header:GetAttribute("mello-height") or 40)
	self:SetAttribute("*type1", "target")
	self:SetAttribute("*type2", "togglemenu")
	self:SetAttribute("toggleForVehicle", false)
]]

local S = { made = false, on = false, pending = false, hidden = false }
local containers, headers = {}, {}
local buttons = {}            -- every button made, in order
local byUnit = {}             -- [unit] = { [button] = true }
local mouseOff = setmetatable({}, { __mode = "k" })   -- [game frame] = true: its mouse turned off by us

local function DB()
	return RD.DB()
end

local function Later(fn, key)
	local K = MelloUI.Kit
	if InCombatLockdown() and K and K.WhenOutOfCombat then
		K:WhenOutOfCombat(fn, key)
	elseif not InCombatLockdown() then
		fn()
	end
end

function H:Buttons()
	return buttons
end

--------------------------------------------------------------------------------
-- A button's unit
--------------------------------------------------------------------------------

local function SetUnit(b, unit)
	unit = Text(unit)
	if b.unit == unit then
		return
	end
	if b.unit and byUnit[b.unit] then
		byUnit[b.unit][b] = nil
	end
	b.unit = unit
	if unit then
		byUnit[unit] = byUnit[unit] or {}
		byUnit[unit][b] = true
		Button.Refresh(b)
	end
	if ns.Indicators then
		ns.Indicators:SetUnit(b, unit)
	end
	-- (Healer Frames' heals and debuff glow on it: its unit now)
	local hf = MelloUI:GetModule("HealerFrames")
	if hf and hf.Update then
		pcall(hf.Update, hf, b, b.healthBar)
	end
end

local OnAttribute = Shared("OnAttributeChanged on a group frame", function(b, name, value)
	if name == "unit" then
		SetUnit(b, value)
	end
end, "script")

local function Dress(b)
	if b.melloDressed then
		return
	end
	b.melloDressed = true
	b:RegisterForClicks("AnyUp")
	Button.Build(b)
	Perf.HookScript(b, "OnAttributeChanged", OnAttribute)
	buttons[#buttons + 1] = b
	-- the kit's raid dressing (its rail and stone) while the painted skin is on
	local rfp = MelloUI:GetModule("RaidFramePanel")
	if rfp and rfp.DressStandIn then
		pcall(rfp.DressStandIn, rfp, b)
		-- (its border known now: the bars inside it, Kit:RaidFrameInset)
		Button.Lay(b)
	end
	-- Healer Frames' incoming heals and shields after the health, and its debuff
	-- glow round the frame (one system: as on every frame of the game's)
	local hf = MelloUI:GetModule("HealerFrames")
	if hf and hf.Heals then
		pcall(hf.Heals, hf, b.healthBar, function()
			return b.unit
		end)
		pcall(hf.Glow, hf, b)
	end
	if ns.Indicators then
		ns.Indicators:Host(b, nil, Looks.Fill(b.healthBar))
	end
	SetUnit(b, b:GetAttribute("unit"))
end

--------------------------------------------------------------------------------
-- The containers, their places
--------------------------------------------------------------------------------

-- a region's effective scale (nil: none to read plainly)
local function Scale(region)
	if type(region) ~= "table" or type(region.GetEffectiveScale) ~= "function" then
		return nil
	end
	local ok, s = pcall(region.GetEffectiveScale, region)
	s = ok and Num(s) or nil
	return (s and s > 0) and s or nil
end

-- the game's normal party frames' footprint in the party container's units:
-- four members (PartyMemberFrameTemplate, 120 x 53) at the party frame's
-- scale, the game's spacing between (10; 26 with the pets shown)
local GAME_MEMBER = { w = 120, h = 53, n = 4, spacing = 10 }
local function GameFootprint()
	local pf, c = rawget(_G, "PartyFrame"), containers.party
	local ratio = 1
	local ps, cs = Scale(pf), Scale(c)
	if ps and cs then
		ratio = ps / cs
	end
	local sp = type(pf) == "table" and Num(rawget(pf, "spacing")) or GAME_MEMBER.spacing
	return GAME_MEMBER.w * ratio, (GAME_MEMBER.n * GAME_MEMBER.h + (GAME_MEMBER.n - 1) * sp) * ratio
end

local function Footprint(kind)
	local db = DB()
	local w, h, sp = db.width, db.height, db.spacing
	if kind == "party" and db.partyStyle == "party" then
		-- (the game's normal party frames show at its place: the plate their size)
		return GameFootprint()
	end
	if kind == "party" then
		if db.partyGrowth == "RIGHT" or db.partyGrowth == "LEFT" then
			return 5 * w + 4 * sp, h
		end
		return w, 5 * h + 4 * sp
	end
	local per = math.max(1, db.raidPerLine or 5)
	local lines = math.ceil(COUNT.raid / per)
	if db.raidFlow == "across" then
		return per * w + (per - 1) * sp, lines * h + (lines - 1) * (db.raidGap or 0)
	end
	return lines * w + (lines - 1) * (db.raidGap or 0), per * h + (per - 1) * sp
end

-- where the game's own frames stand (a place to start from)
local function Home(kind)
	return function(c)
		c:ClearAllPoints()
		local us = UIParent:GetEffectiveScale()
		local names = kind == "party" and { "CompactPartyFrame", "PartyFrame" } or { "CompactRaidFrameContainer" }
		for _, name in ipairs(names) do
			local f = rawget(_G, name)
			local l, _, _, t = ScreenRect(f)
			if l and t then
				c:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l / us, t / us)
				return true
			end
		end
		c:SetPoint("TOPLEFT", UIParent, "LEFT", 20, kind == "party" and 220 or 0)
		return true
	end
end
H.Home = Home

local function MakeContainer(kind)
	local c = CreateFrame("Frame", kind == "party" and "MelloUIGroupParty" or "MelloUIGroupRaid", UIParent)
	c:SetSize(Footprint(kind))
	c:SetFrameStrata("LOW")
	local key = kind == "party" and "GroupFramesParty" or "GroupFramesRaid"
	MelloUI:RegisterMover(c, c, { key = key, default = Home(kind), label = TEXT[kind], page = RD.module.name,
		placeholder = true, when = function()
			return RD.module.isEnabled and true or false
		end, note = kind == "party" and function()
			return DB().partyStyle == "party" and TEXT.partyNote or nil
		end or nil })
	if not MelloUI:RestorePosition(key, c) then
		Home(kind)(c)
	end
	containers[kind] = c
	return c
end

--------------------------------------------------------------------------------
-- The headers' attributes
--------------------------------------------------------------------------------

local function Set(h, name, value)
	if h:GetAttribute(name) ~= value then
		h:SetAttribute(name, value)
	end
end

local function Sorting(h, kind)
	local db = DB()
	local by, order, method, filter = nil, nil, "INDEX", nil
	if kind == "party" then
		if db.partySort == "role" then
			by, order = "ASSIGNEDROLE", ROLE_ORDER
		elseif db.partySort == "name" then
			method = "NAME"
		end
	else
		filter = GROUPS
		if db.raidGroupBy == "group" then
			by, order = "GROUP", GROUPS
		elseif db.raidGroupBy == "role" then
			by, order = "ASSIGNEDROLE", ROLE_ORDER
		elseif db.raidGroupBy == "class" then
			by, order = "CLASS", CLASS_ORDER
		end
	end
	Set(h, "groupFilter", filter)
	Set(h, "groupBy", by)
	Set(h, "groupingOrder", order)
	Set(h, "sortMethod", method)
end

local ANCHOR = { DOWN = "TOPLEFT", UP = "BOTTOMLEFT", RIGHT = "TOPLEFT", LEFT = "TOPRIGHT" }

local function Attributes(kind)
	local h, c = headers[kind], containers[kind]
	local db = DB()
	local sp = db.spacing or 0
	Set(h, "mello-width", db.width)
	Set(h, "mello-height", db.height)
	if kind == "party" then
		local g = db.partyGrowth or "DOWN"
		Set(h, "showParty", true)
		Set(h, "showRaid", false)
		Set(h, "showPlayer", db.showPlayer and true or false)
		Set(h, "showSolo", db.solo and true or false)
		local point = (g == "DOWN" and "TOP") or (g == "UP" and "BOTTOM") or (g == "RIGHT" and "LEFT") or "RIGHT"
		Set(h, "point", point)
		Set(h, "xOffset", (g == "RIGHT" and sp) or (g == "LEFT" and -sp) or 0)
		Set(h, "yOffset", (g == "DOWN" and -sp) or (g == "UP" and sp) or 0)
		Set(h, "unitsPerColumn", 5)
		Set(h, "maxColumns", 1)
		h:ClearAllPoints()
		local a = ANCHOR[g] or "TOPLEFT"
		h:SetPoint(a, c, a, 0, 0)
	else
		local per = math.max(1, db.raidPerLine or 5)
		Set(h, "showRaid", true)
		Set(h, "showParty", false)
		Set(h, "showPlayer", true)
		Set(h, "showSolo", false)
		if db.raidFlow == "across" then
			Set(h, "point", "LEFT")
			Set(h, "xOffset", sp)
			Set(h, "yOffset", 0)
			Set(h, "columnAnchorPoint", "TOP")
		else
			Set(h, "point", "TOP")
			Set(h, "xOffset", 0)
			Set(h, "yOffset", -sp)
			Set(h, "columnAnchorPoint", "LEFT")
		end
		Set(h, "columnSpacing", db.raidGap or 0)
		Set(h, "unitsPerColumn", per)
		Set(h, "maxColumns", math.ceil(COUNT.raid / per))
		h:ClearAllPoints()
		h:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
	end
	Sorting(h, kind)
	c:SetSize(Footprint(kind))
end

-- every button's size and dressing as the settings say
local function SizeButtons()
	local db = DB()
	for _, b in ipairs(buttons) do
		b:SetSize(db.width, db.height)
		Button.Lay(b)
	end
end

local function MakeHeader(kind)
	local c = containers[kind] or MakeContainer(kind)
	local name = kind == "party" and "MelloUIGroupPartyHeader" or "MelloUIGroupRaidHeader"
	local h = CreateFrame("Frame", name, c, "SecureGroupHeaderTemplate")
	h:SetAttribute("template", "SecureUnitButtonTemplate")
	h:SetAttribute("initialConfigFunction", INIT)
	headers[kind] = h
	Attributes(kind)
	-- every button made now (out of a fight): the header walks back over all of
	-- them once, then shows from the first again
	local n = COUNT[kind]
	h:SetAttribute("startingIndex", -(n - 1))
	h:Show()
	h:SetAttribute("startingIndex", 1)
	-- (every button it made: a unit already shown -- you, solo -- makes it one
	-- more than asked, as the game's header counts)
	local i = 1
	while true do
		local b = h[i] or h:GetAttribute("child" .. i)
		if not b then
			break
		end
		Dress(b)
		i = i + 1
	end
	return h
end

-- (In A Party: Group Frames -- ours in a party and solo -- or Party Frames: the
-- game's normal party frames in a party, and solo the normal party frame of
-- ours, GroupSolo.lua: this header never)
local function PartyRule()
	return DB().partyStyle == "party" and "hide" or "[group:raid] hide; show"
end

local function SoloUpdate()
	if ns.Solo then
		ns.Solo:Update()
	end
end

local function Drive(on)
	for kind, h in pairs(headers) do
		if on then
			RegisterStateDriver(h, "visibility", kind == "party" and PartyRule() or "[group:raid] show; hide")
		else
			UnregisterStateDriver(h, "visibility")
			h:Hide()
		end
	end
	for _, c in pairs(containers) do
		c:SetShown(on)
	end
end

--------------------------------------------------------------------------------
-- The game's own frames: faded and click-through, or given back
--------------------------------------------------------------------------------

-- the game's party members (its normal party frames: PartyFrame's pool)
local function PartyMembers(fn)
	local pf = rawget(_G, "PartyFrame")
	if type(pf) == "table" and pf.PartyMemberFramePool then
		for f in pf.PartyMemberFramePool:EnumerateActive() do
			fn(f)
		end
	end
end

local function GameMembers(fn)
	for i = 1, 5 do
		fn(rawget(_G, "CompactPartyFrameMember" .. i))
	end
	for i = 1, 40 do
		fn(rawget(_G, "CompactRaidFrame" .. i))
	end
	for g = 1, 8 do
		for i = 1, 5 do
			fn(rawget(_G, "CompactRaidGroup" .. g .. "Member" .. i))
		end
	end
end

local GAME_HOLDERS = { "CompactPartyFrame", "CompactRaidFrameContainer", "CompactRaidFrameManager", "PartyFrame" }

local function MouseOff(f)
	if type(f) == "table" and f.EnableMouse and f.IsMouseEnabled then
		local ok, on = pcall(f.IsMouseEnabled, f)
		if ok and on then
			pcall(f.EnableMouse, f, false)
			mouseOff[f] = true
		end
	end
end

local function MouseBack(f)
	if mouseOff[f] then
		pcall(f.EnableMouse, f, true)
		mouseOff[f] = nil
	end
end

-- the game's own frames give way to ours (the user, 2026-10-09: "i want these
-- frames to be the main ones"): always its raid frames, its raid-style party
-- frames and its raid manager; its normal party frames too, unless they are
-- the player's choice for a party (In A Party: Party Frames)
local function GameParty()
	return DB().partyStyle == "party"
end

local function HideGame()
	S.hidden = true
	local party = GameParty()
	for _, name in ipairs(GAME_HOLDERS) do
		local f = rawget(_G, name)
		if type(f) == "table" and f.SetAlpha then
			pcall(f.SetAlpha, f, (name == "PartyFrame" and party) and 1 or 0)
		end
	end
	MouseOff(rawget(_G, "CompactRaidFrameManager"))
	GameMembers(MouseOff)
	PartyMembers(party and MouseBack or MouseOff)
end

local TinyRoles   -- (below: the game's tiny role icons back)

local function ShowGame()
	S.hidden = false
	TinyRoles()
	for _, name in ipairs(GAME_HOLDERS) do
		local f = rawget(_G, name)
		if type(f) == "table" and f.SetAlpha then
			pcall(f.SetAlpha, f, 1)
		end
	end
	for f in pairs(mouseOff) do
		pcall(f.EnableMouse, f, true)
		mouseOff[f] = nil
	end
end

--------------------------------------------------------------------------------
-- The normal party frames' place: Edit Layout's (the user, 2026-10-09: "why
-- are we moving the raid frames with the Edit Layout MelloUI option, and the
-- normal Party Frames with Edit mode, both of them need to be only moveable
-- with Edit Layout")
-- While they are the choice for a party, the game's party frame stands at the
-- party container's top left -- Edit Layout's "Party Frames" plate, one place
-- for the party whichever frames show it (the solo frame of ours there too,
-- GroupSolo.lua) -- and the container takes their size, so the plate is what
-- shows. Laid with the plain methods Edit Mode keeps aside (ClearAllPointsBase
-- / SetPointBase: hard rule 2, nothing of Edit Mode's runs), at the
-- container's place on the screen (hung from UIParent, never from a frame of
-- ours: Edit Mode reads its anchor back); laid again after the container
-- moves, after Edit Mode lays it (its layout applied, a drag in Edit Mode put
-- back), when Edit Mode closes and on a UI scale change -- out of a fight.
-- Given back (the module off, Group Frames chosen): the place it had when
-- first taken.
--------------------------------------------------------------------------------
local held = { on = false, placing = false, home = nil, hooked = false }
local PlaceParty   -- (below: held or given back, as the choice is now)

local function Base(frame, method)
	local fn = frame[method .. "Base"] or frame[method]
	return type(fn) == "function" and fn or nil
end

local function LayGame(pf, ...)
	local clear, set = Base(pf, "ClearAllPoints"), Base(pf, "SetPoint")
	if not (clear and set) then
		return false
	end
	held.placing = true
	local ok = pcall(clear, pf) and pcall(set, pf, ...)
	held.placing = false
	return ok
end

local function PlaceLater()
	Later(PlaceParty, "Group Frames: the normal party frames' place")
end

-- (Edit Mode laid it, or the container moved: laid again, out of a fight)
local function OnGameLaid()
	if held.on and not held.placing then
		PlaceLater()
	end
end

local function HoldGameParty()
	local pf, c = rawget(_G, "PartyFrame"), containers.party
	if not (type(pf) == "table" and c and type(pf.GetPoint) == "function") then
		return
	end
	if not held.home then
		local ok, p, rel, rp, x, y = pcall(pf.GetPoint, pf, 1)
		if ok and Text(p) and Text(rp) and Num(x) and Num(y) then
			held.home = { Text(p), type(rel) == "table" and rel or UIParent, Text(rp), Num(x), Num(y) }
		end
	end
	local l, _, _, t = ScreenRect(c)
	local s = Scale(pf)
	if not (l and t and s) then
		return
	end
	held.on = true
	LayGame(pf, "TOPLEFT", UIParent, "BOTTOMLEFT", l / s, t / s)
	if not held.hooked then
		held.hooked = true
		hooksecurefunc(pf, "SetPoint", OnGameLaid)
		hooksecurefunc(c, "SetPoint", OnGameLaid)
	end
end

local function FreeGameParty()
	if not held.on then
		return
	end
	held.on = false
	local pf, h = rawget(_G, "PartyFrame"), held.home
	if type(pf) == "table" and h then
		LayGame(pf, h[1], h[2], h[3], h[4], h[5])
	end
end

PlaceParty = function()
	local c = containers.party
	if c then
		c:SetSize(Footprint("party"))
	end
	if S.on and S.made and GameParty() then
		HoldGameParty()
	else
		FreeGameParty()
	end
end

function H:Blizzard()
	Later(function()
		if S.on then
			HideGame()
		elseif S.hidden then
			ShowGame()
		end
	end, "Group Frames: the game's frames")
end

-- the game's party members' role icon sharp (the user, 2026-10-09: "the role
-- icons on the unitframes are too low resolution"; pick B): the round badge
-- Group Frames show (Button.RoleAtlas) put on the game's own icon right after
-- the game sets its tiny one -- a post-hook on the member's role update, which
-- the game runs on its group events, never per frame -- and the tiny one back
-- when the frames give the game's back
local TINY_ROLE = { ["roleicon-tiny-tank"] = "TANK", ["roleicon-tiny-healer"] = "HEALER",
	["roleicon-tiny-dps"] = "DAMAGER" }
local SHARP_TINY = {}   -- [sharp atlas] = the game's tiny one (filled as met)
local roleHooked = setmetatable({}, { __mode = "k" })

local function RoleIconOf(m)
	local ov = rawget(m, "PartyMemberOverlay")
	local icon = type(ov) == "table" and rawget(ov, "RoleIcon") or nil
	return type(icon) == "table" and icon.SetAtlas and icon or nil
end

local function AtlasOf(icon)
	local ok, atlas = pcall(icon.GetAtlas, icon)
	return ok and Text(atlas) or nil
end

local function SharpRole(m)
	if not (S.on and GameParty()) then
		return
	end
	local icon = RoleIconOf(m)
	local tiny = icon and AtlasOf(icon)
	local role = tiny and TINY_ROLE[tiny:lower()]
	local sharp = role and Button.RoleAtlas(role)
	if sharp and sharp ~= tiny then
		SHARP_TINY[sharp] = tiny
		pcall(icon.SetAtlas, icon, sharp)
	end
end

local function HookRole(m)
	if roleHooked[m] or type(m.UpdateAssignedRoles) ~= "function" then
		return
	end
	roleHooked[m] = true
	hooksecurefunc(m, "UpdateAssignedRoles", SharpRole)
end

TinyRoles = function()
	PartyMembers(function(m)
		local icon = RoleIconOf(m)
		local atlas = icon and AtlasOf(icon)
		local tiny = atlas and SHARP_TINY[atlas]
		if tiny then
			pcall(icon.SetAtlas, icon, tiny)
		end
	end)
end

-- the game's normal party members as hosts of the indicators (while they are
-- the choice for a party): the unit theirs, the health tint over their bar
local function PartyHosts()
	if not (ns.Indicators and GameParty()) then
		return
	end
	PartyMembers(function(f)
		local hc = rawget(f, "HealthBarContainer")
		local hb = type(hc) == "table" and rawget(hc, "HealthBar") or nil
		ns.Indicators:Host(f, Text(rawget(f, "unit")), Looks.Fill(hb), "party")
		-- (and their parts as the Designer moved them, their role icon sharp)
		if ns.Parts then
			ns.Parts:HookMember(f)
			ns.Parts:Lay(f, "party")
		end
		HookRole(f)
		SharpRole(f)
	end)
end

-- each of the game's party members now, and the solo party frame of ours
-- (fn(frame, own): the Designer's party parts)
function H:EachPartyMember(fn)
	PartyMembers(fn)
	local solo = ns.Solo and ns.Solo.frame
	if solo then
		fn(solo, true)
	end
end

-- In A Party changed: the party header's rule, the game's frames, the hosts
function H:Style()
	Later(function()
		if S.on and S.made then
			Drive(true)
			HideGame()
			PartyHosts()
		end
		PlaceParty()
		SoloUpdate()
	end, "Group Frames: In A Party")
end

-- a normal party frame's health bar, portrait and the painted ring over it
-- while the unit frame skin dresses it (UnitFramePanel:RingOf -- as Healer
-- Frames' glow), else nil
local function PartyParts(f)
	local hc = rawget(f, "HealthBarContainer")
	local portrait = rawget(f, "Portrait")
	local panel = MelloUI:GetModule("UnitFramePanel")
	local okR, ring = false, nil
	if portrait and panel and panel.RingOf then
		okR, ring = pcall(panel.RingOf, panel, portrait)
	end
	return type(hc) == "table" and rawget(hc, "HealthBar") or nil, portrait, okR and ring or nil
end

local function PartyEntry(f, unit)
	local health, portrait, ring = PartyParts(f)
	return { frame = f, unit = unit, health = health, kind = "party", portrait = portrait, ring = ring }
end

-- every frame that shows a member now, for every feature that marks one (Heal
-- Flight, Frame Effects): { frame, unit, health, kind } -- ours shown with a
-- unit, and the normal party frames while they are the choice for a party:
-- the game's members, and you alone as one of ours (GroupSolo.lua) -- theirs
-- also `portrait`, the portrait texture, and `ring`, the painted ring over it
-- while the unit frame skin dresses it, else nil.
-- A fresh list each call: read it, never keep it
function H:Hosts()
	local out = {}
	for _, b in ipairs(buttons) do
		if b.unit and b:IsVisible() then
			out[#out + 1] = { frame = b, unit = b.unit, health = b.healthBar, kind = "group" }
		end
	end
	if GameParty() then
		PartyMembers(function(f)
			local unit = Text(rawget(f, "unit"))
			if unit and f:IsVisible() then
				out[#out + 1] = PartyEntry(f, unit)
			end
		end)
		local solo = ns.Solo and ns.Solo:Shown()
		if solo then
			out[#out + 1] = PartyEntry(solo, solo.unit)
		end
	end
	return out
end

-- one member's frame (the effects ask it on every cast and tick: Frame Effects'
-- FX.FrameOf): looked up, nothing made -- ONE entry table reused for every
-- answer, so read it at once and never keep it (rule 7: nothing per event)
local found = {}
local function Found(frame, unit, kind, health, portrait, ring)
	found.frame, found.unit, found.health, found.kind = frame, unit, health, kind
	found.portrait, found.ring = portrait, ring
	return found
end

function H:HostOf(unit)
	unit = Text(unit)
	if not unit then
		return nil
	end
	local set = byUnit[unit]
	if set then
		for b in pairs(set) do
			if b:IsVisible() then
				return Found(b, unit, "group", b.healthBar, nil, nil)
			end
		end
	end
	if not GameParty() then
		return nil
	end
	-- (you alone: the solo party frame of ours)
	local solo = ns.Solo and ns.Solo:Shown()
	if solo and solo.unit == unit then
		return Found(solo, unit, "party", PartyParts(solo))
	end
	local pf = rawget(_G, "PartyFrame")
	if not (type(pf) == "table" and pf.PartyMemberFramePool) then
		return nil
	end
	for f in pf.PartyMemberFramePool:EnumerateActive() do
		if Text(rawget(f, "unit")) == unit and f:IsVisible() then
			return Found(f, unit, "party", PartyParts(f))
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local UNIT_PAINT = {
	UNIT_HEALTH = "Health", UNIT_MAXHEALTH = "Health", UNIT_CONNECTION = "Refresh", UNIT_FLAGS = "Health",
	UNIT_POWER_UPDATE = "Power", UNIT_MAXPOWER = "Power", UNIT_DISPLAYPOWER = "Power",
	UNIT_NAME_UPDATE = "Name", UNIT_IN_RANGE_UPDATE = "Range", UNIT_PHASE = "Range",
}

local function Each(fn, ...)
	for _, b in ipairs(buttons) do
		if b.unit then
			fn(b, ...)
		end
	end
end

local events = nil
local OnEvent = Shared("the group frames' events", function(_, event, unit, ...)
	if not S.on then
		return
	end
	local paint = UNIT_PAINT[event]
	if paint then
		local set = unit and byUnit[Text(unit) or ""]
		if set then
			for b in pairs(set) do
				Button[paint](b)
			end
		end
		return
	end
	if event == "PLAYER_REGEN_ENABLED" then
		if S.pending then
			H:Layout()
		end
		H:Blizzard()
	elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" or event == "PLAYER_ENTERING_WORLD" then
		Each(Button.Refresh)
		if S.hidden then
			H:Blizzard()
		end
		PartyHosts()
	elseif event == "RAID_TARGET_UPDATE" then
		Each(Button.Mark)
	elseif event == "READY_CHECK" or event == "READY_CHECK_CONFIRM" then
		Each(Button.Ready)
	elseif event == "READY_CHECK_FINISHED" then
		-- (the marks stay a few seconds, as the game's)
		C_Timer.After(6, function()
			Each(Button.Ready, false)
		end)
	end
end, "script")

local EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION", "UNIT_FLAGS", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER",
	"UNIT_DISPLAYPOWER", "UNIT_NAME_UPDATE", "UNIT_IN_RANGE_UPDATE", "UNIT_PHASE", "PLAYER_REGEN_ENABLED",
	"GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PLAYER_ENTERING_WORLD", "RAID_TARGET_UPDATE", "READY_CHECK",
	"READY_CHECK_CONFIRM", "READY_CHECK_FINISHED" }

local function Listen()
	if events then
		return
	end
	events = CreateFrame("Frame")
	for _, e in ipairs(EVENTS) do
		pcall(events.RegisterEvent, events, e)
	end
	Perf.SetScript(events, "OnEvent", OnEvent)
	-- the game's members made later (a raid formed): click-through too while hidden
	if type(rawget(_G, "DefaultCompactUnitFrameSetup")) == "function" then
		hooksecurefunc("DefaultCompactUnitFrameSetup", function(frame)
			if S.hidden then
				Later(function()
					if S.hidden then
						MouseOff(frame)
					end
				end)
			end
		end)
	end
	-- Edit Mode closed (its own place laid on the party frame meanwhile), the
	-- UI's scale changed: the normal party frames at the container again
	MelloUI:On("editmode", function(entering)
		if not entering and held.on then
			PlaceLater()
		end
	end, "GroupFrames.party")
	MelloUI:On("scale", function()
		if held.on then
			PlaceLater()
		end
	end, "GroupFrames.party")
	-- the bar look (Bar Textures) changed: the fills again
	MelloUI.Widgets.OnBarTexture("raidframes", function()
		H:Repaint()
	end, "GroupFrames.bars")
	-- the raid frames' border changed (Raid Frame Border, its placement): the
	-- bars inside it again (Kit:RaidFrameInset; the kit lays borders out of a fight)
	MelloUI:On("raidborder", function()
		for _, b in ipairs(buttons) do
			Button.Lay(b)
		end
	end, "GroupFrames.border")
end

--------------------------------------------------------------------------------
-- On, off, layout, repaint
--------------------------------------------------------------------------------

function H:Layout()
	if not S.made then
		return
	end
	if InCombatLockdown() then
		S.pending = true
		return
	end
	S.pending = false
	for kind in pairs(headers) do
		Attributes(kind)
	end
	SizeButtons()
	Each(Button.Refresh)
	PlaceParty()
	SoloUpdate()
	MelloUI:Fire("groupframes", "layout")
end

function H:Repaint()
	for _, b in ipairs(buttons) do
		Button.Lay(b)
		if b.unit then
			Button.Refresh(b)
		end
	end
end

function H:Start()
	S.on = true
	Listen()
	Later(function()
		if not S.on then
			return
		end
		if not S.made then
			S.made = true
			MakeHeader("party")
			MakeHeader("raid")
		else
			H:Layout()
		end
		Drive(true)
		H:Blizzard()
		PartyHosts()
		PlaceParty()
		SoloUpdate()
	end, "Group Frames: the headers")
end

function H:Stop()
	S.on = false
	Later(function()
		if S.on then
			return
		end
		Drive(false)
		PlaceParty()
		SoloUpdate()
		if S.hidden then
			ShowGame()
		end
	end, "Group Frames: the headers off")
end

-- (the tests')
H.S = S
H.headers, H.containers, H.byUnit, H.held = headers, containers, byUnit, held
